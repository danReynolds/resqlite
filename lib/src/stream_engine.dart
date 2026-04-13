import 'dart:async';

import 'reader/reader_pool.dart';
import 'result_hash.dart';

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

  /// Number of active stream entries. Exposed for testing cleanup behavior.
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
  /// Each affected entry's reQueryGeneration is bumped so that stale results
  /// from older re-queries are discarded on arrival.
  void handleDirtyTables(List<String> dirtyTables) {
    if (dirtyTables.isEmpty) return;
    _writeGeneration++;

    // Inline invalidation — find affected stream keys via inverted index.
    final affected = <int>{};
    for (final table in dirtyTables) {
      final keys = _tableToKeys[table];
      if (keys != null) affected.addAll(keys);
    }
    if (affected.isEmpty) return;

    for (final key in affected) {
      final entry = _entries[key];
      if (entry == null) continue;

      entry.reQueryGeneration++;
      unawaited(_reQuery(entry, entry.reQueryGeneration));
    }
  }

  /// Close all streams and clear state.
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

        final initialRows = result.$1;
        final readTables = result.$2;

        // Set real read tables so future writes trigger invalidation.
        _updateReadTables(key, readTables);
        entry.lastResult = initialRows;
        entry.lastResultHash = _hashResult(initialRows);

        // Push initial result to all subscribers.
        for (final sub in entry.subscribers) {
          if (!sub.isClosed) sub.add(initialRows);
        }

        // If a write happened while the initial query was in-flight,
        // the data may be stale. Re-query to catch up. The hash check
        // in _emitResult suppresses the emission if data is unchanged.
        if (_writeGeneration != generationBefore) {
          entry.reQueryGeneration++;
          unawaited(_reQuery(entry, entry.reQueryGeneration));
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
  /// [generation] is the entry's reQueryGeneration at dispatch time.
  /// If a newer re-query was dispatched while we were running (the entry's
  /// generation moved on), the result is stale and we discard it.
  Future<void> _reQuery(StreamEntry entry, int generation) async {
    try {
      final pool = await _pool();
      final (rows, newHash) = await pool.selectIfChanged(
        entry.sql,
        entry.params,
        entry.lastResultHash,
      );
      // Discard if a newer re-query was dispatched while we were running.
      if (entry.reQueryGeneration != generation) return;
      if (rows == null) return; // Unchanged — worker-side hash matched.
      // Changed — update cache and emit.
      entry.lastResultHash = newHash;
      entry.lastResult = rows;
      for (final sub in entry.subscribers) {
        if (!sub.isClosed) sub.add(rows);
      }
    } catch (e) {
      // Discard if a newer re-query was dispatched while we were running.
      if (entry.reQueryGeneration != generation) return;
      // Propagate error to subscribers so they can handle it (e.g., table
      // dropped, schema changed). Silent failure would leave the stream
      // stuck with stale data and no signal to the listener.
      for (final sub in entry.subscribers) {
        if (!sub.isClosed) sub.addError(e);
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

  /// Per-entry re-query generation. Bumped each time a re-query is dispatched.
  /// When the result arrives, it's discarded if the generation has moved on
  /// (a newer re-query was dispatched), preventing stale out-of-order results.
  int reQueryGeneration = 0;
}

/// Compute a stable hash key for a stream query.
int _streamKey(String sql, List<Object?> params) {
  return Object.hash(sql, Object.hashAll(params));
}

/// Hash a query result for change detection using shared FNV-1a.
///
/// Uses [stableValueHash] instead of `Object.hashCode` so that
/// `Uint8List` values are hashed by content, not by identity.
int _hashResult(List<Map<String, Object?>> rows) {
  if (rows.isEmpty) return 0;
  var hash = fnvOffsetBasis;
  hash = fnvCombine(hash, rows.length);
  for (final row in rows) {
    for (final value in row.values) {
      hash = fnvCombine(hash, stableValueHash(value));
    }
  }
  return hash;
}
