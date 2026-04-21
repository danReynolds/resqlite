import 'dart:collection';
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

  /// Invalidate all streams dependent on the given tables, scheduling them for requery.
  Future<void> invalidate(List<String>? dirtyTables) async {
    if (_entries.isEmpty || dirtyTables == null || dirtyTables.isEmpty) {
      return;
    }

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

    for (final entry in dirtyEntries) {
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
  }

  Future<void> _flushQueue() async {
    if (_requeryQueue.isEmpty) {
      return;
    }

    final pool = await _pool;
    while (_requeryQueue.isNotEmpty && pool.hasAvailableWorker) {
      final entry = _requeryQueue.first;
      _requeryQueue.remove(entry);
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

        final (initialRows, initialTables, initialHash, initialRowCount) =
            result;

        // Index the entry's table dependencies after its initial query completes.
        for (final table in initialTables) {
          (_tableIndex[table] ??= {}).add(entry);
        }

        entry.lastResult = initialRows;
        entry.lastResultHash = initialHash;
        entry.lastRowCount = initialRowCount;
        entry.dependencies = initialTables.toSet();

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
  });

  /// Hash key identifying this stream (derived from SQL + params).
  final int key;

  /// The SQL query for this stream.
  final String sql;

  /// Bind parameters for the query.
  final List<Object?> params;

  /// The table dependencies of the query.
  Set<String> dependencies;

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
