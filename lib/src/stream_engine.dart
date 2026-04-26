import 'dart:collection';
import 'dart:async';

import 'profile_counters.dart';
import 'profile_mode.dart';
import 'reader/reader_pool.dart';

/// Stream engine — reactive query lifecycle.
///
/// Manages the full lifecycle of reactive streams: registration,
/// deduplication, initial query with dependency tracking, write
/// invalidation, re-query with result-change detection, and
/// per-subscriber buffered delivery.
final class StreamEngine {
  StreamEngine(this._pool);

  final Future<ReaderPool> _pool;

  /// The index of streamed queries by their hash key.
  final Map<int, StreamEntry> _entries = {};

  /// The set of stream queries pending initialization and performing their first initial query.
  final Set<StreamEntry> _pendingEntries = {};

  /// Index of tables to the set of stream entries that depend on that table.
  final Map<String, Set<StreamEntry>> _tableIndex = {};

  /// Stream entries scheduled to be requeried when an available reader opens up.
  final LinkedHashSet<StreamEntry> _requeryQueue = LinkedHashSet<StreamEntry>();

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

    // If there is already a stream entry for this query, then subscribe to it.
    if (_entries[key] case StreamEntry entry) {
      return _subscribe(entry);
    }

    // Otherwise, create the stream and execute its initial query.
    return _createStream(key, sql, parameters);
  }

  /// Invalidate all streams dependent on the given tables, scheduling them
  /// for requery.
  ///
  /// Experiment 106: when [dirtyColumns] is provided, perform a per-table
  /// column-intersection check before scheduling the requery. A stream
  /// only re-runs if its read-column set intersects the writer's modified
  /// column set for at least one shared table. The check degrades to
  /// today's table-only behaviour when either side is unknown — a `null`
  /// entry in `dirtyColumns` (writer-side wildcard for INSERT/DELETE) or
  /// a missing entry in the stream's `columnDependencies` (e.g. legacy
  /// streams created before this experiment landed) both force the
  /// re-query.
  Future<void> invalidate(
    List<String>? dirtyTables, [
    Map<String, Set<String>?>? dirtyColumns,
  ]) async {
    if (_entries.isEmpty || dirtyTables == null || dirtyTables.isEmpty) {
      return;
    }

    // Profile-mode instrumentation: time the synchronous body of this
    // method (everything except the awaited `_pool` future inside
    // `_flushQueue`) and the per-entry intersection probe separately.
    // Tree-shaken in release builds.
    final invalidateSw = kProfileMode ? (Stopwatch()..start()) : null;

    // Pending entries have not resolved dependencies yet, so any table write
    // could affect their eventual result.
    for (final entry in _pendingEntries) {
      entry.dirty = true;
    }

    final dirtyEntries = <StreamEntry>{};

    for (final table in dirtyTables) {
      if (_tableIndex[table] case Set<StreamEntry> entries) {
        dirtyEntries.addAll(entries);
      }
    }

    final intersectionSw = kProfileMode ? Stopwatch() : null;
    var intersectionEntries = 0;
    for (final entry in dirtyEntries) {
      // Experiment 106: column-level dispatch elision. Skip the per-stream
      // requery when we know the modified columns can't change the
      // result. This is the writer-side complement to exp 075's hash
      // short-circuit — the hash short-circuit pays the requery cost and
      // suppresses the emission; the column elision skips the requery
      // itself.
      if (dirtyColumns != null) {
        if (kProfileMode) {
          intersectionEntries++;
          intersectionSw!.start();
        }
        final affects = _writeAffectsEntry(entry, dirtyTables, dirtyColumns);
        if (kProfileMode) {
          intersectionSw!.stop();
        }
        if (!affects) {
          continue;
        }
      }

      entry.dirty = true;

      // Don't schedule dirty entries for requery if they are *already in-flight*
      // so that there is at most 1 reader assigned to a given stream query at a time.
      // This is a performance trade-off that optimizes for availability to other streams
      // versus eagerly re-querying a stream that is invalidated while still reading.
      if (!entry.inFlight) {
        _requeryQueue.add(entry);
      }
    }

    _flushQueue();

    if (kProfileMode) {
      invalidateSw!.stop();
      ProfileCounters.invalidateUs += invalidateSw.elapsedMicroseconds;
      ProfileCounters.invalidateCount++;
      ProfileCounters.intersectionUs += intersectionSw!.elapsedMicroseconds;
      ProfileCounters.intersectionEntries += intersectionEntries;
    }
  }

  /// Return `true` when at least one table in [dirtyTables] is in
  /// [entry]'s dependency set AND the writer's modified columns intersect
  /// the entry's read columns for that table (or either side carries a
  /// wildcard, forcing the re-query).
  static bool _writeAffectsEntry(
    StreamEntry entry,
    List<String> dirtyTables,
    Map<String, Set<String>?> dirtyColumns,
  ) {
    final entryDeps = entry.dependencies;
    final entryCols = entry.columnDependencies;
    for (final table in dirtyTables) {
      if (!entryDeps.contains(table)) continue;

      // Writer-side wildcard: INSERT / DELETE / untagged writes — every
      // stream watching this table must re-query because rows may have
      // appeared or disappeared.
      final writerCols = dirtyColumns[table];
      if (writerCols == null) {
        if (dirtyColumns.containsKey(table)) return true;
        // Table-only invalidation with no column info available — fall
        // back to today's behaviour and re-query.
        return true;
      }

      // Reader-side wildcard or missing column data: degrade safely —
      // re-query the stream.
      final readerCols = entryCols[table];
      if (readerCols == null) return true;

      // Both sides have concrete column sets. Skip the re-query only
      // when they are disjoint.
      for (final c in writerCols) {
        if (readerCols.contains(c)) return true;
      }
    }
    return false;
  }

  Future<void> _flushQueue() async {
    if (_requeryQueue.isEmpty) {
      return;
    }

    final pool = await _pool;
    while (_requeryQueue.isNotEmpty && pool.hasAvailableWorker) {
      // Experiment 107: cross-stream re-query batching.
      //
      // When the dirty queue exceeds the pool width by a wide margin,
      // the per-entry path would otherwise cost the writer's microtask
      // drain `ceil(N / W)` sequential pool round-trips. A batched
      // dispatch ships the whole queue to one worker for a single
      // round-trip and frees the rest of the pool for unrelated reads.
      //
      // Threshold heuristic: only batch when queue length is large
      // enough that the parallel per-entry path would need many
      // sequential rounds AND each per-entry round-trip dominates the
      // C-side hash work. Empirically (initial benchmark sweep):
      //   - 11 streams × 1000-row hashes → C work dominates,
      //     batching serialises and *regresses* (Unchanged Fanout).
      //   - 50 streams × ~100-row hashes → IPC dominates, batching
      //     wins (A11c overlap).
      // Pick a threshold that catches the latter shape while leaving
      // small-to-mid fan-out on the parallel path: a queue size of at
      // least `workerCount * 8 + 1` (33 for cap=4) reliably means the
      // per-entry parallel drain would burn ≥ 8 round-trips per worker.
      // This keeps Unchanged Fanout (11 entries) and similar mid-cardinality
      // streaming workloads on today's parallel dispatch.
      final batchThreshold = pool.workerCount * 8 + 1;
      if (_requeryQueue.length >= batchThreshold) {
        final batch = List<StreamEntry>.of(_requeryQueue);
        _requeryQueue.clear();
        if (kProfileMode) {
          ProfileCounters.batchDispatchCount++;
        }
        _requeryBatch(batch);
        // _requeryBatch holds one worker for the duration of the batch.
        // The remaining workers stay free for unrelated reads; if more
        // entries are added to `_requeryQueue` mid-batch they'll be
        // picked up by the post-batch `_flushQueue()` call.
        return;
      }

      final entry = _requeryQueue.first;
      _requeryQueue.remove(entry);
      if (kProfileMode) {
        ProfileCounters.perEntryDispatchCount++;
      }
      _requery(entry);
    }
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
    _tableIndex.clear();
    _requeryQueue.clear();
  }

  /// Create a new stream entry and return a subscriber stream.
  ///
  /// Each subscriber gets a buffered (non-broadcast) StreamController,
  /// eliminating the race condition where async* generators + broadcast
  /// controllers silently drop events during microtask gaps.
  ///
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
    entry.inFlight = true;

    // Add the new entry to the list of entries pending initialization.
    _pendingEntries.add(entry);

    // Subscribe immediately — buffered controller queues events until listened.
    final subscriberStream = _subscribe(entry);

    Future.sync(() async {
      try {
        final pool = await _pool;
        final result = await pool.selectWithDeps(sql, params);

        // Cancelled before query finished.
        if (entry.subscribers.isEmpty) {
          return;
        }

        final (
          initialRows,
          initialTables,
          initialColumns,
          initialHash,
          initialRowCount,
        ) = result;

        // Index the entry's table dependencies after its initial query completes.
        for (final table in initialTables) {
          (_tableIndex[table] ??= {}).add(entry);
        }

        entry.lastResult = initialRows;
        entry.lastResultHash = initialHash;
        entry.lastRowCount = initialRowCount;
        entry.dependencies = initialTables.toSet();
        // Experiment 106: persist the per-table read-column map for the
        // dispatch elision check on subsequent invalidations.
        entry.columnDependencies = initialColumns;

        // If an invalidation occurred while performing the entry's initial query then the entry
        // needs to be re-queried since its dependencies were not known at the time and this result could be stale.
        if (entry.dirty) {
          _requeryQueue.add(entry);
          _flushQueue();
        } else {
          entry.emit(initialRows);
        }
      } catch (e, stackTrace) {
        // Propagate error to all subscribers so they don't hang.
        entry.emitError(e, stackTrace);
        _remove(entry);
      } finally {
        entry.inFlight = false;
        _pendingEntries.remove(entry);
      }
    });

    return subscriberStream;
  }

  /// Experiment 107 — batched re-query of multiple stream entries.
  ///
  /// All [entries] share one pool worker for one round-trip. The worker
  /// runs `executeQueryIfChanged` per entry and returns aligned
  /// `(rows?, hash, count)` tuples. Per-entry dirty/cancellation/error
  /// handling mirrors [_requery] so the public observable contract
  /// (one re-query per dirty mark, late-mark forces re-queue, errors
  /// propagate to subscribers) is unchanged.
  Future<void> _requeryBatch(List<StreamEntry> entries) async {
    // Mark every batched entry in-flight synchronously so concurrent
    // invalidations can see the in-flight state and queue the entry
    // for a follow-up requery rather than scheduling a duplicate.
    for (final entry in entries) {
      entry.inFlight = true;
      entry.dirty = false;
    }

    try {
      final pool = await _pool;
      final batchInputs = List<(String, List<Object?>, int, int)>.generate(
        entries.length,
        (i) {
          final entry = entries[i];
          return (
            entry.sql,
            entry.params,
            entry.lastResultHash,
            entry.lastRowCount,
          );
        },
        growable: false,
      );
      final results = await pool.selectBatchIfChanged(batchInputs);

      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final (rows, newHash, newRowCount) = results[i];

        // Skip cancelled entries: `_remove` empties `subscribers` so
        // there's nothing to emit to and nothing to requeue.
        if (entry.subscribers.isEmpty) continue;

        // If the entry was re-marked dirty mid-batch (a write landed
        // while the batch was in flight) requeue it so the next flush
        // re-runs the query. The intermediate result is discarded.
        if (entry.dirty) {
          _requeryQueue.add(entry);
          continue;
        }

        // Hash + row-count match — no change to emit.
        if (rows == null) continue;

        entry.lastResultHash = newHash;
        entry.lastRowCount = newRowCount;
        entry.lastResult = rows;
        entry.emit(rows);
      }
    } catch (e, st) {
      // A batch-level failure (worker crash, FFI error before per-entry
      // dispatch) propagates to every entry's subscribers. Per-entry
      // SQL errors land here as well — they're rare, and matching the
      // single-stream path means subscribers see the error rather than
      // a silent stall.
      for (final entry in entries) {
        for (final sub in entry.subscribers) {
          if (!sub.isClosed) sub.addError(e, st);
        }
      }
    } finally {
      for (final entry in entries) {
        entry.inFlight = false;
      }
      _flushQueue();
    }
  }

  /// Re-query a single stream on the reader pool.
  Future<void> _requery(StreamEntry entry) async {
    try {
      entry.inFlight = true;
      entry.dirty = false;

      final pool = await _pool;
      final (rows, newHash, newRowCount) = await pool.selectIfChanged(
        entry.sql,
        entry.params,
        entry.lastResultHash,
        entry.lastRowCount,
      );

      // If the entry has already been marked dirty again from an invalidation that ocurred
      // while it was requerying, then this intermediate result should be discarded and instead
      // the entry should be re-scheduled for requery.
      if (entry.dirty) {
        _requeryQueue.add(entry);
        return;
      }

      // If no rows were returned, then the query result has not changed.
      if (rows == null) {
        return;
      }

      entry.lastResultHash = newHash;
      entry.lastRowCount = newRowCount;
      entry.lastResult = rows;

      entry.emit(rows);
    } catch (e, st) {
      // Propagate error to subscribers so they can handle it (e.g., table
      // dropped, schema changed). Silent failure would leave the stream
      // stuck with stale data and no signal to the listener.
      for (final sub in entry.subscribers) {
        if (!sub.isClosed) sub.addError(e, st);
      }
    } finally {
      entry.inFlight = false;
      _flushQueue();
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
        _remove(entry);
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
  void _remove(StreamEntry entry) {
    _entries.remove(entry.key);
    _requeryQueue.remove(entry);

    // Clean up inverted index.
    for (final table in entry.dependencies) {
      _tableIndex[table]?.remove(entry);
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
    this.dependencies = const {},
    this.columnDependencies = const {},
  });

  /// Hash key identifying this stream (derived from SQL + params).
  final int key;

  /// The SQL query for this stream.
  final String sql;

  /// Bind parameters for the query.
  final List<Object?> params;

  /// The table dependencies of the query.
  Set<String> dependencies;

  /// Experiment 106: per-table column dependencies. The authorizer
  /// captures every column referenced in the query (SELECT projection
  /// columns plus WHERE / ORDER BY / etc. — everything that can affect
  /// the result). A `null` entry for a table means "any column" and
  /// forces the writer-side dispatch path to re-query unconditionally
  /// for that table. An absent entry behaves the same as `null` per the
  /// elision contract in [StreamEngine.invalidate].
  Map<String, Set<String>?> columnDependencies;

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

  /// Whether the stream is dirty and needs to be requeried.
  bool dirty = false;

  /// Whether the stream is currently being queried (and we are waiting for the result).
  bool inFlight = false;

  @override
  int get hashCode => key;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! StreamEntry) return false;
    return key == other.key;
  }

  void emit(List<Map<String, Object?>> rows) {
    for (final sub in subscribers) {
      if (!sub.isClosed) sub.add(rows);
    }
  }

  void emitError(Object e, StackTrace? st) {
    for (final sub in subscribers) {
      if (!sub.isClosed) sub.addError(e, st);
    }
  }
}

/// Compute a stable hash key for a stream query.
int _streamKey(String sql, List<Object?> params) {
  return Object.hash(sql, Object.hashAll(params));
}
