import 'dart:collection';
import 'dart:async';

import 'dependency_tracking.dart'
    show
        TableColumnDependency,
        FixedTableDependencies,
        TableDependencies,
        TableDependency,
        UnknownTableDependencies;
import 'extensions/set.dart';
import 'profile_counters.dart';
import 'profile_mode.dart';
import 'reader/reader_pool.dart';

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
  ]) {
    final key = _streamKey(sql, parameters);

    // If there is already a stream entry for this query, then subscribe to it.
    if (_entries[key] case StreamEntry entry) {
      return _subscribe(entry);
    }

    // Otherwise, create the stream and execute its initial query.
    return _createStream(key, sql, parameters);
  }

  /// Apply table dependency updates from a write.
  ///
  /// [TableDependencies.none] means there are no stream-visible changes for
  /// this writer response. [TableDependencies.unknown] means native dirty-table
  /// tracking was unreliable, so every active stream must re-query.
  Future<void> onDependencyChanges(TableDependencies changes) async {
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
            switch (dep) {
              case TableColumnDependency(columns: final changedCols):
                for (final entry in entries) {
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
                dirtyEntries.addAll(entries);
            }
          }
        }
    }

    for (final entry in dirtyEntries) {
      entry.dirty = true;
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

    // The entry is considered dependent on all tables until its initial query
    // result with its dependencies returns.
    _unknownDepsEntries.add(entry);

    // Subscribe immediately — buffered controller queues events until listened.
    final subscriberStream = _subscribe(entry);

    Future.sync(() async {
      // Profile-mode wall split: start the stopwatch once the await
      // returns, so the timed segment is the synchronous main-isolate
      // work the event loop runs in response to the initial query
      // reply - dependency-set wiring, dirty/requeue scheduling, and
      // `entry.emit(initialRows)` to subscribers. Pairs with
      // `_requery`'s post-await stopwatch to measure the completion-
      // side scheduling cost exp 120 / exp 121 left as an open
      // counter for `stream-rerun-dispatch`. See
      // `experiments/124-stream-completion-counter.md`.
      Stopwatch? completionSw;
      try {
        final result = await _pool.selectWithDeps(sql, params);

        // Cancelled before query finished.
        if (entry.subscribers.isEmpty) {
          return;
        }
        // Stopwatch starts only after the cancellation fast-path so a
        // cancelled-before-initial-emit stream does not inflate the
        // per-completion average with the cost of just the
        // `subscribers.isEmpty` check.
        if (kProfileMode) completionSw = Stopwatch()..start();

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
        if (kProfileMode && completionSw != null) {
          completionSw.stop();
          ProfileCounters.streamCompletionUs +=
              completionSw.elapsedMicroseconds;
          ProfileCounters.streamCompletionCount++;
        }
      }
    });

    return subscriberStream;
  }

  /// Re-query a single stream on the reader pool.
  Future<void> _requery(StreamEntry entry) async {
    // Profile-mode wall split: timed segment starts once the
    // reader-pool await returns and includes the trailing
    // `_flushQueue` kickoff in the finally - that is what the main
    // isolate event loop runs synchronously when a stream re-query
    // reply lands. Per-completion segment count drives the per-write
    // average reported by `experiments/124-stream-completion-counter.md`.
    Stopwatch? completionSw;
    try {
      entry.inFlight = true;
      entry.dirty = false;

      final (rows, newHash, newRowCount) = await _pool.selectIfChanged(
        entry.sql,
        entry.params,
        entry.lastResultHash,
        entry.lastRowCount,
      );
      if (kProfileMode) completionSw = Stopwatch()..start();

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
      if (kProfileMode && completionSw != null) {
        completionSw.stop();
        ProfileCounters.streamCompletionUs +=
            completionSw.elapsedMicroseconds;
        ProfileCounters.streamCompletionCount++;
      }
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
    // No-op if the entry was never registered there; the membership check is
    // O(1).
    _unknownDepsEntries.remove(entry);

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
