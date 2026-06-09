import 'dart:collection';
import 'dart:async';

import 'dependency_tracking.dart'
    show
        TableColumnDependency,
        FixedTableDependencies,
        RowIdentity,
        TableDependencies,
        TableDependency,
        UnknownTableDependencies;
import 'profile_counters.dart';
import 'profile_mode.dart';
import 'reader/reader_pool.dart';
import 'tracelite_profile.dart';
import 'extensions/set.dart';

// ---------------------------------------------------------------------------
// Stream dependency tracking contract
// ([EXP-106](../../experiments/106-column-level-deps.md) polish)
// ---------------------------------------------------------------------------
//
// Stream dependency tracking is layered:
//
//   * Table dependencies are the correctness source of truth.
//     A stream watches a known set of tables, or — if tracking is
//     unavailable for any reason — every table.
//   * Column dependencies are an optimization layer that can elide
//     re-query dispatch when a write provably touches no projected
//     column. Column information is precise or absent. Absent column
//     information always falls back to table-level re-query for the
//     known dirty tables.
//
// Every uncertainty inside the table-backed dependency path (overflow, OOM,
// missing metadata, triggers / cascades) routes to a more conservative
// re-query, never to a skipped one. Direct virtual-table / FTS writes are a
// known boundary: SQLite's preupdate hook does not report those writes, so
// streams that depend only on virtual tables are not automatically invalidated.
//
// At the FFI boundary the C-side table reliability flags propagate through
// `TableDependencies.unknown`. Per-table column fallbacks use a plain
// `TableDependency(table)`, which only forces re-query for streams that already
// share that table.

/// Stream engine — reactive query lifecycle.
///
/// Manages the full lifecycle of reactive streams: registration,
/// deduplication, initial query with dependency tracking, write
/// invalidation, re-query with result-change detection, and
/// per-subscriber buffered delivery.
final class StreamEngine {
  StreamEngine(this._pool);

  final ReaderPool _pool;

  /// The index of streamed queries by their hash key.
  final Map<int, StreamEntry> _entries = {};

  /// Entries whose table dependencies are not available yet, or are
  /// permanently unknown because native tracking fell back.
  final Set<StreamEntry> _unknownDepsEntries = {};

  /// Index of tables to the set of stream entries that depend on that table.
  final Map<String, Set<StreamEntry>> _tableIndex = {};

  /// Index of explicit row-observed entries by table and primary key.
  final Map<String, Map<Object, Set<StreamEntry>>> _rowIndex = {};

  /// Stream entries scheduled to be requeried when an available reader opens up.
  final _requeryQueue = LinkedHashSet<StreamEntry>();

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
    RowIdentity? rowObservation,
  ]) {
    final key = _streamKey(sql, parameters, rowObservation);

    // If there is already a stream entry for this query, then subscribe to it.
    if (_entries[key] case StreamEntry entry) {
      return _subscribe(entry);
    }

    // Otherwise, create the stream and execute its initial query.
    return _createStream(key, sql, parameters, rowObservation);
  }

  /// Apply table dependency updates from a write.
  ///
  /// [TableDependencies.none] means there are no stream-visible changes for
  /// this writer response. [TableDependencies.unknown] means native dirty-table
  /// tracking was unreliable, so every active stream must re-query.
  Future<void> onDependencyChanges(
    TableDependencies changes, {
    Iterable<RowIdentity> rowChanges = const [],
    int? traceCorrelationId,
  }) async {
    if (_entries.isEmpty) {
      return;
    }

    if (changes case FixedTableDependencies(
      :final tables,
    ) when tables.isEmpty) {
      return;
    }

    // Profile-mode instrumentation.
    final invalidateSw = kProfileMode ? (Stopwatch()..start()) : null;
    final intersectionSw = kProfileMode ? Stopwatch() : null;
    var intersectionEntries = 0;
    final dirtyEntries = <StreamEntry>{};
    final rowChangesByTable = _rowChangesByTable(rowChanges);
    if (kProfileMode) {
      TraceliteProfile.begin(
        TraceliteResqliteSpans.streamInvalidate,
        correlationId: traceCorrelationId,
      );
    }

    try {
      switch (changes) {
        case UnknownTableDependencies():
          dirtyEntries.addAll(_unknownDepsEntries);
          for (final entries in _tableIndex.values) {
            dirtyEntries.addAll(entries);
          }
        case FixedTableDependencies(tables: final deps):
          dirtyEntries.addAll(_unknownDepsEntries);

          for (final dep in deps) {
            if (_tableIndex[dep.table] case Set<StreamEntry> entries) {
              final candidates = _candidateEntriesFor(
                dep.table,
                entries,
                rowChangesByTable[dep.table],
              );
              switch (dep) {
                case TableColumnDependency(columns: final changedCols):
                  for (final entry in candidates) {
                    switch (entry.dependencies[dep.table]) {
                      case TableColumnDependency(columns: final entryCols):
                        bool intersects;
                        if (kProfileMode) {
                          intersectionEntries++;
                          intersectionSw!.start();
                          intersects = entryCols.intersects(changedCols);
                          intersectionSw.stop();
                        } else {
                          intersects = entryCols.intersects(changedCols);
                        }
                        if (intersects) {
                          dirtyEntries.add(entry);
                        }
                      case TableDependency _:
                        dirtyEntries.add(entry);
                    }
                  }
                case TableDependency():
                  dirtyEntries.addAll(candidates);
              }
            }
          }
      }

      for (final entry in dirtyEntries) {
        entry.dirty = true;
        if (traceCorrelationId != null) {
          entry.pendingTraceCorrelationId = traceCorrelationId;
        }
        if (!entry.inFlight) {
          _requeryQueue.add(entry);
        }
      }

      _flushQueue();
    } finally {
      if (kProfileMode) {
        invalidateSw!.stop();
        ProfileCounters.invalidateUs += invalidateSw.elapsedMicroseconds;
        ProfileCounters.invalidateCount++;
        ProfileCounters.intersectionUs += intersectionSw!.elapsedMicroseconds;
        ProfileCounters.intersectionEntries += intersectionEntries;
        TraceliteProfile.end(
          TraceliteResqliteSpans.streamInvalidate,
          args: [dirtyEntries.length, intersectionEntries],
          correlationId: traceCorrelationId,
        );
        TraceliteProfile.counter(
          TraceliteResqliteCounters.invalidateUs,
          ProfileCounters.invalidateUs,
          correlationId: traceCorrelationId,
        );
        TraceliteProfile.counter(
          TraceliteResqliteCounters.invalidateCount,
          ProfileCounters.invalidateCount,
          correlationId: traceCorrelationId,
        );
        TraceliteProfile.counter(
          TraceliteResqliteCounters.intersectionUs,
          ProfileCounters.intersectionUs,
          correlationId: traceCorrelationId,
        );
        TraceliteProfile.counter(
          TraceliteResqliteCounters.intersectionEntries,
          ProfileCounters.intersectionEntries,
          correlationId: traceCorrelationId,
        );
      }
    }
  }

  void _flushQueue() {
    if (_requeryQueue.isEmpty) {
      return;
    }

    final dequeued = _requeryQueue.take(_pool.availableWorkerCount).toList();

    for (final entry in dequeued) {
      _requery(entry);
      _requeryQueue.remove(entry);
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
    _unknownDepsEntries.clear();
    _rowIndex.clear();
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
    RowIdentity? rowObservation,
  ) {
    final entry = _entries[key] = StreamEntry(
      key: key,
      sql: sql,
      params: params,
      rowObservation: rowObservation,
    );
    entry.inFlight = true;

    // The entry is considered dependent on all tables until its initial query
    // result with its dependencies returns.
    _unknownDepsEntries.add(entry);

    // Subscribe immediately — buffered controller queues events until listened.
    final subscriberStream = _subscribe(entry);

    Future.sync(() async {
      try {
        final result = await _pool.selectWithDeps(sql, params);

        // Cancelled before query finished.
        if (entry.subscribers.isEmpty) {
          return;
        }

        final (initialRows, dependencies, initialHash, initialRowCount) =
            result;

        entry.lastResult = initialRows;
        entry.lastResultHash = initialHash;
        entry.lastRowCount = initialRowCount;

        if (dependencies case FixedTableDependencies(tables: final tables)) {
          _unknownDepsEntries.remove(entry);

          for (final dependency in tables) {
            (_tableIndex[dependency.table] ??= {}).add(entry);
          }
          entry.dependencies = {
            for (final dependency in tables) dependency.table: dependency,
          };
          _indexRowObservation(entry);
        }

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
      }
    });

    return subscriberStream;
  }

  /// Re-query a single stream on the reader pool.
  Future<void> _requery(StreamEntry entry) async {
    final traceCorrelationId = entry.pendingTraceCorrelationId;
    entry.pendingTraceCorrelationId = null;
    try {
      entry.inFlight = true;
      entry.dirty = false;

      final (rows, newHash, newRowCount) = await _pool.selectIfChanged(
        entry.sql,
        entry.params,
        entry.lastResultHash,
        entry.lastRowCount,
        traceCorrelationId,
      );

      // If the entry has already been marked dirty again from an invalidation that ocurred
      // while it was requerying, then this intermediate result should be discarded and instead
      // the entry should be re-scheduled for requery.
      if (entry.dirty) {
        if (entry.pendingTraceCorrelationId == null) {
          entry.pendingTraceCorrelationId = traceCorrelationId;
        }
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
    for (final table in entry.dependencies.keys) {
      _tableIndex[table]?.remove(entry);
    }
    if (entry.rowObservation case RowIdentity row) {
      _rowIndex[row.table]?[row.primaryKey]?.remove(entry);
    }
    // No-op if the entry was never registered there; the membership check is
    // O(1).
    _unknownDepsEntries.remove(entry);

    // Close any remaining subscriber controllers.
    for (final sub in entry.subscribers) {
      if (!sub.isClosed) sub.close();
    }
    entry.subscribers.clear();
  }

  Map<String, Set<Object>> _rowChangesByTable(Iterable<RowIdentity> rows) {
    final byTable = <String, Set<Object>>{};
    for (final row in rows) {
      (byTable[row.table] ??= {}).add(row.primaryKey);
    }
    return byTable;
  }

  Iterable<StreamEntry> _candidateEntriesFor(
    String table,
    Set<StreamEntry> tableEntries,
    Set<Object>? changedPrimaryKeys,
  ) {
    if (changedPrimaryKeys == null) {
      return tableEntries;
    }

    final candidates = <StreamEntry>{};

    for (final entry in tableEntries) {
      final row = entry.rowObservation;
      if (row == null || row.table != table) {
        candidates.add(entry);
      }
    }

    final tableRows = _rowIndex[table];
    if (tableRows != null) {
      for (final primaryKey in changedPrimaryKeys) {
        if (tableRows[primaryKey] case Set<StreamEntry> entries) {
          candidates.addAll(entries);
        }
      }
    }

    return candidates;
  }

  void _indexRowObservation(StreamEntry entry) {
    final row = entry.rowObservation;
    if (row == null || !entry.dependencies.containsKey(row.table)) {
      return;
    }
    final byPrimaryKey = _rowIndex[row.table] ??= {};
    (byPrimaryKey[row.primaryKey] ??= {}).add(entry);
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
    this.rowObservation,
    this.dependencies = const {},
  });

  /// Hash key identifying this stream (derived from SQL + params).
  final int key;

  /// The SQL query for this stream.
  final String sql;

  /// Bind parameters for the query.
  final List<Object?> params;

  /// Optional explicit row identity for keyed row-observer experiments.
  final RowIdentity? rowObservation;

  /// Table dependencies of the query, keyed by table name for invalidation.
  ///
  /// A plain [TableDependency] falls back to table-level invalidation.
  /// [TableColumnDependency] carries precise column detail for dispatch
  /// elision.
  Map<String, TableDependency> dependencies = const {};

  /// Per-subscriber buffered controllers. Each subscriber gets their own
  /// non-broadcast StreamController that buffers events, eliminating the
  /// race condition where broadcast controllers silently drop events
  /// when no listener is attached (async* generator gap).
  final List<StreamController<List<Map<String, Object?>>>> subscribers = [];

  /// The most recently emitted result, used to seed new subscribers.
  List<Map<String, Object?>>? lastResult;

  /// Hash of the last emitted result, for change detection.
  int lastResultHash = 0;

  /// Row count of the last emitted result
  /// ([EXP-077](../../experiments/077-cheap-check-first-sweep.md)). -1 means
  /// "no baseline yet" — the initial query hasn't returned. Passed into
  /// `selectIfChanged` so the worker can short-circuit hashing once it
  /// knows the fresh row count diverges.
  int lastRowCount = -1;

  /// Whether the stream is dirty and needs to be requeried.
  bool dirty = false;

  /// Whether the stream is currently being queried (and we are waiting for the result).
  bool inFlight = false;

  /// Trace correlation for the write that most recently dirtied this stream.
  ///
  /// Multiple writes may collapse into one re-query; in that case the latest
  /// non-null correlation is retained so the re-query can still be connected
  /// to a triggering write in tracelite.
  int? pendingTraceCorrelationId;

  @override
  int get hashCode => key;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! StreamEntry) return false;
    return key == other.key;
  }

  void emit(List<Map<String, Object?>> rows) {
    // [EXP-136](../../experiments/136-completion-microtask-counter.md):
    // sub-counter of `completionHandlerUs` covering the subscriber
    // fanout cost — `controller.add` schedules a microtask per
    // subscriber, so the inline wall here is the loop plus the
    // `StreamController.add` synchronous portion (event enqueue, not
    // listener callback). Profile-mode only.
    final emitSw = kProfileMode ? (Stopwatch()..start()) : null;
    for (final sub in subscribers) {
      if (!sub.isClosed) sub.add(rows);
    }
    if (kProfileMode) {
      emitSw!.stop();
      ProfileCounters.streamEmitUs += emitSw.elapsedMicroseconds;
      ProfileCounters.streamEmitCount++;
    }
  }

  void emitError(Object e, StackTrace? st) {
    for (final sub in subscribers) {
      if (!sub.isClosed) sub.addError(e, st);
    }
  }
}

/// Compute a stable hash key for a stream query.
int _streamKey(String sql, List<Object?> params, RowIdentity? rowObservation) {
  return Object.hash(sql, Object.hashAll(params), rowObservation);
}
