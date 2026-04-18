import 'dart:async';

import 'reader/reader_pool.dart';

/// Stream engine — reactive query lifecycle.
///
/// Manages the full lifecycle of reactive streams: registration,
/// deduplication, initial query with dependency tracking, write
/// invalidation, re-query with result-change detection, and
/// per-subscriber buffered delivery.
final class StreamEngine {
  StreamEngine(this._pool);

  final Future<ReaderPool> Function() _pool;

  final Map<int, StreamEntry> _entries = {};

  /// Inverted index: table name → set of stream keys that read from it.
  /// Maintained on register/remove so invalidation is O(dirtyTables)
  /// instead of O(streams × dirtyTables).
  final Map<String, Set<int>> _tableToKeys = {};

  /// Monotonic write counter. Streams compare before/after their initial
  /// query to detect writes that landed during the setup window.
  int _writeGeneration = 0;

  /// Accumulated dirty tables for microtask coalescing.
  /// Multiple handleDirtyTables calls within the same microtask are batched
  /// into a single invalidation pass, reducing redundant re-queries.
  Set<String>? _pendingDirtyTables;
  bool _flushScheduled = false;

  /// Experiment 079: probe that returns `true` if any write is currently
  /// in flight on the writer isolate. Wired up by the [Writer]
  /// constructor. Used by [_reQuery] to suppress emissions whose data
  /// is about to be invalidated by the in-flight write's response.
  ///
  /// Reads "busy" conservatively — a value of `true` only means "don't
  /// emit now" (the follow-up re-query, scheduled by the write's own
  /// `handleDirtyTables`, will emit fresh data). False negatives (missing
  /// a write that's about to start) are already handled by the post-
  /// flight `writeGen` check.
  bool Function()? _writerBusyProbe;

  /// Register the writer-busy probe. Called by [Writer].
  void setWriterBusyProbe(bool Function() probe) {
    _writerBusyProbe = probe;
  }

  /// Number of active stream entries.
  ///
  /// Increments when [stream] registers a new query, decrements when all
  /// listeners for that query cancel. Useful for verifying cleanup in tests.
  int get length => _entries.length;

  /// Create a reactive stream that emits query results and re-emits
  /// whenever the underlying tables change.
  ///
  /// The first emission contains the current results. Subsequent emissions
  /// occur after any write that modifies tables the query depends on.
  ///
  /// Streams are deduplicated: multiple calls with the same SQL and params
  /// share a single underlying query. New listeners receive the cached
  /// result immediately.
  Stream<List<Map<String, Object?>>> stream(
    String sql, [
    List<Object?> parameters = const [],
  ]) {
    final key = _streamKey(sql, parameters);

    // Check for existing stream with same query.
    final existing = _entries[key];
    if (existing != null) {
      return _subscribe(existing);
    }

    // No existing stream — register, subscribe, run initial query.
    return _createStream(key, sql, parameters);
  }

  /// Called after every write — checks dirty tables against active streams
  /// and re-queries affected ones.
  ///
  /// Re-queries fire concurrently. The C reader pool handles contention
  /// via spin-wait — each reader-holding isolate makes independent forward
  /// progress, so there's no circular dependency and no livelock risk.
  ///
  /// Each affected entry's in-flight re-query (if any) is flagged for a
  /// follow-up via [_scheduleReQuery]; otherwise a fresh re-query is
  /// dispatched. At most one re-query per entry is in flight at a time.
  void handleDirtyTables(List<String> dirtyTables) {
    if (dirtyTables.isEmpty) return;
    _writeGeneration++;

    // Experiment 077: fast-reject when no stream has yet registered any
    // table dependencies. `_tableToKeys` is populated by
    // [_updateReadTables], which only fires after a stream's initial
    // query returns. If it's empty, either (a) there are no streams at
    // all, or (b) every active stream is still waiting for its initial
    // query to return — in which case those streams rely on the
    // `_writeGeneration != generationBefore` race-detection path in
    // [_createStream], not on the dirty-tables pipeline. Either way,
    // the accumulate + microtask below would be pure waste.
    if (_tableToKeys.isEmpty) return;

    // Accumulate dirty tables for microtask coalescing.
    // Multiple writes within the same synchronous work batch are combined
    // into a single invalidation pass, reducing redundant re-queries.
    if (_pendingDirtyTables == null) {
      _pendingDirtyTables = Set<String>.from(dirtyTables);
    } else {
      _pendingDirtyTables!.addAll(dirtyTables);
    }

    if (!_flushScheduled) {
      _flushScheduled = true;
      scheduleMicrotask(_flushDirtyTables);
    }
  }

  /// Flush accumulated dirty tables and dispatch re-queries.
  void _flushDirtyTables() {
    _flushScheduled = false;
    final tables = _pendingDirtyTables;
    _pendingDirtyTables = null;
    if (tables == null || tables.isEmpty) return;

    // Find affected stream keys via inverted index.
    final affected = <int>{};
    for (final table in tables) {
      final keys = _tableToKeys[table];
      if (keys != null) affected.addAll(keys);
    }
    if (affected.isEmpty) return;

    for (final key in affected) {
      final entry = _entries[key];
      if (entry == null) continue;
      _scheduleReQuery(entry);
    }
  }

  /// Dispatch a re-query for [entry], coalescing against any in-flight one.
  ///
  /// Without coalescing, a tight write burst against a table watched by N
  /// streams queues O(writes × N) re-queries in the reader pool. For a
  /// workload with 100 streams and 200 writes, that's up to 20,000
  /// dispatches — each one a full pool round-trip.
  ///
  /// With coalescing, at most ONE re-query is in flight per stream entry
  /// at a time. Each invalidation bumps [StreamEntry.writeGen]; if
  /// a re-query is already in flight, we return without dispatching. The
  /// in-flight re-query captured the pre-bump value of `writeGen`
  /// when it was dispatched, so on completion it can compare:
  ///
  ///   - `entry.writeGen == gen` → no invalidations arrived during
  ///      the in-flight run; its result is current, emit normally, done.
  ///   - `entry.writeGen != gen` → at least one invalidation landed
  ///      during the in-flight run. Skip the emit (the DB snapshot the
  ///      in-flight read may predate the intervening write) and dispatch
  ///      exactly one follow-up, which captures the now-current gen and
  ///      reads current state (reflecting every intermediate write).
  void _scheduleReQuery(StreamEntry entry) {
    entry.writeGen++;
    if (entry.inFlightReQuery != null) return;
    _startReQuery(entry);
  }

  /// Actually dispatches the re-query and manages the in-flight slot.
  /// Only called via [_scheduleReQuery], which enforces the single-
  /// in-flight invariant.
  void _startReQuery(StreamEntry entry) {
    final gen = entry.writeGen;
    entry.inFlightReQuery = _reQuery(entry, gen).whenComplete(() {
      entry.inFlightReQuery = null;
      // If the stream was invalidated while running, re-query it again.
      if (_entries[entry.key] != null && entry.writeGen != gen) {
        _startReQuery(entry);
      }
    });
  }

  /// Closes all active streams and clears internal state.
  ///
  /// Called by [Database.close]. After this, existing subscriber streams
  /// receive a done event and no new streams can be created.
  void close() {
    for (final entry in _entries.values) {
      for (final sub in entry.subscribers) {
        if (!sub.isClosed) sub.close();
      }
      entry.subscribers.clear();
    }
    _entries.clear();
    _tableToKeys.clear();
  }

  // ---------------------------------------------------------------------------
  // Stream lifecycle
  // ---------------------------------------------------------------------------

  /// Create a new stream entry and return a subscriber stream.
  ///
  /// Each subscriber gets a buffered (non-broadcast) StreamController,
  /// eliminating the race condition where async* generators + broadcast
  /// controllers silently drop events during microtask gaps.
  ///
  /// Uses the write generation counter to detect writes that happened during
  /// the initial query — if the generation changed, triggers an immediate
  /// re-query so the stream reflects the latest data.
  Stream<List<Map<String, Object?>>> _createStream(
    int key,
    String sql,
    List<Object?> params,
  ) {
    final entry = _entries[key] = StreamEntry(
      key: key,
      sql: sql,
      params: params,
    );

    // Subscribe immediately — buffered controller queues events until listened.
    final subscriberStream = _subscribe(entry);

    // Capture write generation before the initial query. If any write
    // lands while the query is in-flight, we'll re-query after setup.
    final generationBefore = _writeGeneration;

    // Run initial query on the reader pool to discover read tables.
    _pool().then((pool) => pool.selectWithDeps(sql, params)).then(
      (result) {
        if (entry.subscribers.isEmpty) {
          return; // cancelled before query finished
        }

        final (initialRows, readTables, initialHash, initialRowCount) = result;

        // Set real read tables so future writes trigger invalidation.
        _updateReadTables(key, readTables);
        entry.lastResult = initialRows;
        // Hash (exp 075) and row count (exp 077) both come from the
        // worker. Together they form the baseline that selectIfChanged
        // re-queries short-circuit against.
        entry.lastResultHash = initialHash;
        entry.lastRowCount = initialRowCount;

        // Push initial result to all subscribers.
        for (final sub in entry.subscribers) {
          if (!sub.isClosed) sub.add(initialRows);
        }

        // If a write happened while the initial query was in-flight,
        // the data may be stale. Re-query to catch up. The hash check
        // in _reQuery suppresses the emission if data is unchanged.
        // Goes through the same coalescing path as normal invalidation
        // so the in-flight cap is honored even at setup.
        if (_writeGeneration != generationBefore) {
          _scheduleReQuery(entry);
        }
      },
      onError: (Object error) {
        // Propagate error to all subscribers so they don't hang.
        for (final sub in entry.subscribers) {
          if (!sub.isClosed) sub.addError(error);
        }
        _remove(key);
      },
    );

    return subscriberStream;
  }

  /// Re-query a single stream on the reader pool.
  ///
  /// [gen] is [StreamEntry.writeGen] captured at dispatch time by
  /// [_startReQuery]. If `entry.writeGen` differs at completion,
  /// at least one invalidation landed during our flight — the result is
  /// potentially stale (DB snapshot may predate the intervening write),
  /// so we return without emitting. The follow-up dispatched by
  /// [_startReQuery]'s `whenComplete` hook reads current state.
  Future<void> _reQuery(StreamEntry entry, int gen) async {
    try {
      final pool = await _pool();
      final (rows, newHash, newRowCount) = await pool.selectIfChanged(
        entry.sql,
        entry.params,
        entry.lastResultHash,
        entry.lastRowCount,
      );
      if (entry.writeGen != gen) return;  // stale — caught during flight
      if (rows == null) return; // Unchanged — worker-side hash matched.

      // Experiment 079: if the writer is busy right now, another write
      // is in progress and its response will arrive soon, fire its own
      // `handleDirtyTables`, bump this entry's writeGen, and schedule
      // a follow-up re-query. Emitting our (soon-stale) result now
      // just burns the UI thread for an emission the user would
      // immediately supersede. Skip it — the follow-up will emit fresh.
      //
      // Mirrors drift's cancel-on-new-invalidation behavior via a
      // different mechanism: drift cancels the reader mid-query; we
      // let it finish but drop the result if a write is already
      // queued up. Correctness invariant: the follow-up re-query IS
      // guaranteed to fire because the in-flight write WILL call
      // handleDirtyTables on response (see database.dart:execute +
      // executeBatch + transaction paths).
      //
      // Concrete win: Sync Burst COUNT(*) emissions 103 → 1–2. The
      // stream watcher sees the final count after all 100 batches,
      // not a per-batch intermediate count nobody uses.
      if (_writerBusyProbe?.call() ?? false) return;

      // Changed — update cache and emit.
      entry.lastResultHash = newHash;
      entry.lastRowCount = newRowCount;
      entry.lastResult = rows;
      for (final sub in entry.subscribers) {
        if (!sub.isClosed) sub.add(rows);
      }
    } catch (e, st) {
      // Stale: skip surfacing the error too; the follow-up may succeed
      // (e.g. schema re-created, connection recovered) or may fail in
      // the same way, at which point its own error handling fires.
      if (entry.writeGen != gen) return;
      // Propagate error to subscribers so they can handle it (e.g., table
      // dropped, schema changed). Silent failure would leave the stream
      // stuck with stale data and no signal to the listener.
      for (final sub in entry.subscribers) {
        if (!sub.isClosed) sub.addError(e, st);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Registry operations
  // ---------------------------------------------------------------------------

  void _updateReadTables(int key, List<String> readTables) {
    final entry = _entries[key];
    if (entry == null) return;

    // Remove old table mappings.
    for (final table in entry.readTables) {
      _tableToKeys[table]?.remove(key);
    }

    // Set new tables and update inverted index.
    final tables = Set<String>.unmodifiable(readTables.toSet());
    entry.readTables = tables;
    for (final table in tables) {
      (_tableToKeys[table] ??= {}).add(key);
    }
  }

  /// Add a subscriber controller to a stream entry and return the stream.
  /// The controller buffers events — no events can be lost regardless of
  /// async timing. Emits the cached result immediately if available.
  Stream<List<Map<String, Object?>>> _subscribe(StreamEntry entry) {
    final controller = StreamController<List<Map<String, Object?>>>();
    entry.subscribers.add(controller);

    controller.onCancel = () {
      entry.subscribers.remove(controller);
      if (!controller.isClosed) controller.close();
      // Clean up entry when last subscriber cancels.
      if (entry.subscribers.isEmpty) {
        _remove(entry.key);
      }
    };

    // Seed with cached result if available.
    final cached = entry.lastResult;
    if (cached != null) {
      controller.add(cached);
    }

    return controller.stream;
  }

  /// Remove a stream entry.
  void _remove(int key) {
    final entry = _entries.remove(key);
    if (entry == null) return;

    // Clean up inverted index.
    for (final table in entry.readTables) {
      final keys = _tableToKeys[table];
      if (keys != null) {
        keys.remove(key);
        if (keys.isEmpty) _tableToKeys.remove(table);
      }
    }

    // Close any remaining subscriber controllers.
    for (final sub in entry.subscribers) {
      if (!sub.isClosed) sub.close();
    }
    entry.subscribers.clear();
  }
}

// ---------------------------------------------------------------------------
// Supporting types
// ---------------------------------------------------------------------------

/// A single tracked stream query with its metadata and subscriber list.
final class StreamEntry {
  StreamEntry({
    required this.key,
    required this.sql,
    required this.params,
    this.readTables = const {},
  });

  /// Hash key identifying this stream (derived from SQL + params).
  final int key;

  /// The SQL query for this stream.
  final String sql;

  /// Bind parameters for the query.
  final List<Object?> params;

  /// Tables this query reads from, used for invalidation matching.
  /// Mutable — updated after initial query when tables aren't known at registration.
  Set<String> readTables;

  /// Per-subscriber buffered controllers. Each subscriber gets their own
  /// non-broadcast StreamController that buffers events, eliminating the
  /// race condition where broadcast controllers silently drop events
  /// when no listener is attached (async* generator gap).
  final List<StreamController<List<Map<String, Object?>>>> subscribers = [];

  /// The most recently emitted result, used to seed new subscribers.
  List<Map<String, Object?>>? lastResult;

  /// Hash of the last emitted result, for change detection.
  int lastResultHash = 0;

  /// Row count of the last emitted result (experiment 077). -1 means
  /// "no baseline yet" — the initial query hasn't returned. Passed into
  /// `selectIfChanged` so the worker can short-circuit hashing once it
  /// knows the fresh row count diverges.
  int lastRowCount = -1;

  /// Tracks the currently-executing re-query for this entry, if any.
  /// `null` means no re-query is in flight; a non-null value means
  /// additional invalidations should be absorbed into [writeGen]
  /// rather than dispatching fresh pool work. See
  /// [StreamEngine._scheduleReQuery] for the full rationale.
  Future<void>? inFlightReQuery;

  /// Monotonic counter bumped by [StreamEngine._scheduleReQuery] on
  /// every qualifying invalidation (writes that touch this entry's
  /// watched tables, plus the initial-query race catchup). Never decreases.
  ///
  /// [StreamEngine._startReQuery] captures this value at dispatch time;
  /// on completion, if the captured value and the current value differ,
  /// invalidations arrived during the in-flight run and the result is
  /// skipped in favor of a fresh follow-up (which captures the now-current
  /// gen and re-reads). Monotonic-capture-and-compare — no manual reset.
  int writeGen = 0;
}

/// Compute a stable hash key for a stream query.
int _streamKey(String sql, List<Object?> params) {
  return Object.hash(sql, Object.hashAll(params));
}
