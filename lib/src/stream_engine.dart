import 'dart:async';

import 'query_cache.dart';
import 'reader_pool.dart';

/// Stream engine — reactive query lifecycle.
///
/// Manages stream subscriptions and re-query scheduling. Delegates result
/// caching, table dependency tracking, and invalidation to [QueryCache].
final class StreamEngine {
  StreamEngine(this._pool, this._cache);

  final Future<ReaderPool> Function() _pool;
  final QueryCache _cache;

  /// Stream subscriber lists, keyed by query key.
  final Map<int, StreamSubscribers> _streams = {};

  /// Monotonic write counter. Streams compare before/after their initial
  /// query to detect writes that landed during the setup window.
  int _writeGeneration = 0;

  /// Number of active stream entries. Exposed for testing cleanup behavior.
  int get length => _streams.length;

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
    final key = queryKey(sql, parameters);

    // Check for existing stream with same query.
    final existing = _streams[key];
    if (existing != null) {
      return _subscribe(key, existing);
    }

    // No existing stream — register, subscribe, run initial query.
    return _createStream(key, sql, parameters);
  }

  /// Called after every write — invalidates cache entries for dirty tables,
  /// then re-queries affected streams.
  void handleDirtyTables(List<String> dirtyTables) {
    if (dirtyTables.isEmpty) return;
    _writeGeneration++;

    // Cache handles invalidation: evicts unpinned entries, returns pinned
    // keys (streams) that need re-querying.
    final affectedKeys = _cache.handleDirtyTables(dirtyTables);
    if (affectedKeys.isEmpty) return;

    for (final key in affectedKeys) {
      final subs = _streams[key];
      if (subs == null) continue;

      subs.reQueryGeneration++;
      unawaited(_reQuery(key, subs, subs.reQueryGeneration));
    }
  }

  /// Close all streams and clear state.
  void closeAll() {
    for (final subs in _streams.values) {
      for (final sub in subs.controllers) {
        if (!sub.isClosed) sub.close();
      }
      subs.controllers.clear();
    }
    _streams.clear();
    // Don't clear the entire cache — unpinned entries can survive.
    // But unpin all stream entries since streams are gone.
  }

  // ---------------------------------------------------------------------------
  // Stream lifecycle
  // ---------------------------------------------------------------------------

  Stream<List<Map<String, Object?>>> _createStream(
    int key,
    String sql,
    List<Object?> params,
  ) {
    final subs = _streams[key] = StreamSubscribers();

    // Subscribe immediately — buffered controller queues events until listened.
    final subscriberStream = _subscribe(key, subs);

    // Check if the cache already has a result for this query (e.g., from
    // a previous select() call). If so, use it as the initial result.
    final cached = _cache.get(key);
    if (cached != null) {
      // Pin the existing cache entry for this stream.
      _cache.pin(key);

      // Push initial result to all subscribers.
      for (final sub in subs.controllers) {
        if (!sub.isClosed) sub.add(cached.result);
      }

      return subscriberStream;
    }

    // No cached result — run initial query to discover read tables.
    final generationBefore = _writeGeneration;

    _pool()
        .then((pool) => pool.selectWithDeps(sql, params))
        .then(
          (result) {
            if (subs.controllers.isEmpty) {
              return; // cancelled before query finished
            }

            final initialRows = result.$1;
            final readTables = result.$2;
            final hash = hashResult(initialRows);

            // Store in cache as a pinned entry.
            _cache.put(
              key: key,
              sql: sql,
              params: params,
              result: initialRows,
              resultHash: hash,
              readTables: Set<String>.unmodifiable(readTables.toSet()),
              pinned: true,
            );

            // Push initial result to all subscribers.
            for (final sub in subs.controllers) {
              if (!sub.isClosed) sub.add(initialRows);
            }

            // If a write happened while the initial query was in-flight,
            // re-query to catch up.
            if (_writeGeneration != generationBefore) {
              subs.reQueryGeneration++;
              unawaited(_reQuery(key, subs, subs.reQueryGeneration));
            }
          },
          onError: (Object error) {
            for (final sub in subs.controllers) {
              if (!sub.isClosed) sub.addError(error);
            }
            _removeStream(key);
          },
        );

    return subscriberStream;
  }

  Future<void> _reQuery(int key, StreamSubscribers subs, int generation) async {
    try {
      final cached = _cache.get(key);
      if (cached == null) return; // entry was removed

      final pool = await _pool();
      final (rows, newHash) = await pool.selectIfChanged(
        cached.sql, cached.params, cached.resultHash,
      );
      if (subs.reQueryGeneration != generation) return;
      if (rows == null) return; // Unchanged.

      // Update cache and emit.
      _cache.updateResult(key, rows, newHash);
      for (final sub in subs.controllers) {
        if (!sub.isClosed) sub.add(rows);
      }
    } catch (e) {
      // Re-query failed — silently drop.
    }
  }

  // ---------------------------------------------------------------------------
  // Subscription management
  // ---------------------------------------------------------------------------

  Stream<List<Map<String, Object?>>> _subscribe(
    int key,
    StreamSubscribers subs,
  ) {
    final controller = StreamController<List<Map<String, Object?>>>();
    subs.controllers.add(controller);

    controller.onCancel = () {
      subs.controllers.remove(controller);
      if (!controller.isClosed) controller.close();
      if (subs.controllers.isEmpty) {
        _removeStream(key);
      }
    };

    // Seed with cached result if available.
    final cached = _cache.get(key);
    if (cached != null) {
      controller.add(cached.result);
    }

    return controller.stream;
  }

  void _removeStream(int key) {
    final subs = _streams.remove(key);
    if (subs == null) return;

    // Unpin the cache entry — it becomes LRU-evictable.
    _cache.unpin(key);

    for (final sub in subs.controllers) {
      if (!sub.isClosed) sub.close();
    }
    subs.controllers.clear();
  }
}

// ---------------------------------------------------------------------------
// Supporting types
// ---------------------------------------------------------------------------

/// Stream subscriber state for a single query. The cached data lives
/// in [QueryCache]; this holds only the subscriber controllers and
/// re-query generation counter.
final class StreamSubscribers {
  final List<StreamController<List<Map<String, Object?>>>> controllers = [];

  /// Per-stream re-query generation. Bumped each time a re-query is dispatched.
  int reQueryGeneration = 0;
}
