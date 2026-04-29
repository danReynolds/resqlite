import 'dart:collection';
import 'dart:async';

import 'package:meta/meta.dart';

import 'native/resqlite_bindings.dart'
    show
        AllColumnDependencies,
        AllTableDependencies,
        ColumnDependencyMap,
        ColumnDependencies,
        FixedColumnDependencies,
        FixedTableDependencies,
        TableDependencies;
import 'profile_counters.dart';
import 'profile_mode.dart';
import 'reader/reader_pool.dart';

// ---------------------------------------------------------------------------
// Stream dependency tracking contract (experiment 106 polish)
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
// Every uncertainty (overflow, OOM, missing metadata, triggers /
// cascades, virtual tables) routes to a more conservative re-query,
// never to a skipped one.
//
// At the FFI boundary the C-side reliability flags propagate through
// `TableDependencies.all` (table side) and `ColumnDependencies.all`
// (column side). The asymmetry is load-bearing: a table fall-through
// invalidates every stream, while a column fall-through only forces
// re-query for streams that already share dirty tables.

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

  /// Polish (post-2026-04): bucket of stream entries whose table
  /// dependencies could not be captured reliably during the initial
  /// query (read_set overflow / OOM at prepare). Every write — both
  /// concrete table lists and `TableDependencies.all` — invalidates
  /// every entry in this bucket. Column elision is skipped for these
  /// entries because we don't know which tables they depend on, so
  /// columns are meaningless. Empty in the steady-state common case.
  final Set<StreamEntry> _allTableEntries = {};

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
  /// today's table-only behaviour when either side is unknown —
  /// `ColumnDependencies.all` in `dirtyColumns` (writer-side wildcard
  /// for INSERT/DELETE) or a missing entry in the stream's
  /// `columnDependencies` (e.g. legacy streams created before this
  /// experiment landed) both force the re-query.
  ///
  /// Polish (post-2026-04): [dirtyTables] is now a [TableDependencies];
  /// `null` still means "nothing to invalidate" (e.g. inside a
  /// transaction where the writer hasn't published yet),
  /// `TableDependencies.fixed([])` is "no dirty tables this cycle", and
  /// `TableDependencies.all` is the C-side reliability sentinel that forces
  /// every active stream — even the
  /// "all tables" bucket — to invalidate, bypassing the column elision
  /// short-circuit entirely.
  Future<void> invalidate(
    TableDependencies? dirtyTables, [
    ColumnDependencyMap? dirtyColumns,
  ]) async {
    if (_entries.isEmpty || dirtyTables == null) {
      return;
    }

    final dirtyTableList = switch (dirtyTables) {
      AllTableDependencies() => null,
      FixedTableDependencies(:final tables) => tables,
    };

    if (dirtyTableList != null && dirtyTableList.isEmpty) {
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

    if (dirtyTableList == null) {
      // Polish: writer-side reliability tripped — the dirty-table set
      // overflowed / OOMed and we don't know which tables changed.
      // Invalidate every active entry (both `_tableIndex` watchers and
      // the all-tables bucket) and bypass the column-elision check
      // entirely; the check would dereference `dirtyColumns[table]` for
      // tables we can't enumerate, and there's no benefit to elision
      // when we don't know the dirty set.
      dirtyEntries.addAll(_allTableEntries);
      for (final entries in _tableIndex.values) {
        dirtyEntries.addAll(entries);
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
      }
      return;
    }

    // Reader-side "all tables" entries (their own read_set was unreliable
    // when the stream was registered) get invalidated on every write,
    // regardless of which concrete tables are dirty. They bypass the
    // column elision check because their column dependencies are known
    // to be unreliable too — and even if they were reliable, we have
    // no entry-level table set to intersect against.
    dirtyEntries.addAll(_allTableEntries);

    for (final table in dirtyTableList) {
      if (_tableIndex[table] case Set<StreamEntry> entries) {
        dirtyEntries.addAll(entries);
      }
    }

    final intersectionSw = kProfileMode ? Stopwatch() : null;
    var intersectionEntries = 0;
    for (final entry in dirtyEntries) {
      // Polish: all-tables-bucket entries skip column elision — their
      // `columnDependencies` map carries no useful info because the
      // table side was unreliable when the stream was registered.
      final isAllTablesEntry = _allTableEntries.contains(entry);
      // Experiment 106: column-level dispatch elision. Skip the per-stream
      // requery when we know the modified columns can't change the
      // result. This is the writer-side complement to exp 075's hash
      // short-circuit — the hash short-circuit pays the requery cost and
      // suppresses the emission; the column elision skips the requery
      // itself.
      if (dirtyColumns != null && !isAllTablesEntry) {
        if (kProfileMode) {
          intersectionEntries++;
          intersectionSw!.start();
        }
        final affects = _writeAffectsEntry(entry, dirtyTableList, dirtyColumns);
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
  ///
  /// Delegates to [ColumnInvalidationPolicy.affects] which is also the
  /// load-bearing test surface for direct unit coverage of the elision
  /// policy. Black-box "stream emits / doesn't emit" cannot prove
  /// elision because exp 075's hash short-circuit can suppress
  /// emission after a re-query.
  static bool _writeAffectsEntry(
    StreamEntry entry,
    List<String> dirtyTables,
    ColumnDependencyMap dirtyColumns,
  ) => ColumnInvalidationPolicy.affects(entry, dirtyTables, dirtyColumns);

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
    _allTableEntries.clear();
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

        switch (initialTables) {
          case AllTableDependencies():
            // Polish: read_set was unreliable for this stream's initial
            // query — every write must invalidate it. The all-tables
            // bucket short-circuits column elision for this entry too,
            // since the columns map is meaningless without knowing the
            // tables.
            _allTableEntries.add(entry);
            entry.dependencies = const <String>{};
            entry.columnDependencies = const <String, ColumnDependencies>{};
          case FixedTableDependencies(:final tables):
            // Index the entry's table dependencies after its initial query
            // completes.
            for (final table in tables) {
              (_tableIndex[table] ??= {}).add(entry);
            }
            entry.dependencies = tables.toSet();
            // Experiment 106: persist the per-table read-column map for the
            // dispatch elision check on subsequent invalidations.
            entry.columnDependencies = initialColumns;
        }

        entry.lastResult = initialRows;
        entry.lastResultHash = initialHash;
        entry.lastRowCount = initialRowCount;

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
    // Polish: drop from the all-tables bucket too. No-op if the entry
    // was never registered there; the membership check is O(1).
    _allTableEntries.remove(entry);

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
  /// the result). [ColumnDependencies.all] for a table means "any column"
  /// and forces the writer-side dispatch path to re-query unconditionally
  /// for that table. An absent entry behaves the same way per the elision
  /// contract in [StreamEngine.invalidate].
  ColumnDependencyMap columnDependencies;

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

/// Column-level dispatch elision policy (experiment 106 polish).
///
/// Encapsulates the per-entry "should this write invalidate this
/// stream?" decision. Exposed via [@visibleForTesting] so direct unit
/// tests can prove the dispatch policy without going through black-box
/// emission counts (which can be confounded by exp 075's hash
/// short-circuit suppressing emissions for unchanged results).
///
/// The policy is the writer-side complement to the result-change
/// detection: hash short-circuit pays the re-query cost and suppresses
/// the emission; column elision skips the re-query itself when the
/// dirty columns provably can't intersect the stream's read columns
/// for any shared table.
@visibleForTesting
class ColumnInvalidationPolicy {
  const ColumnInvalidationPolicy._();

  /// Return `true` when at least one table in [dirtyTables] is in
  /// [entry]'s dependency set AND the writer's modified columns
  /// intersect the entry's read columns for that table (or either side
  /// carries a wildcard, forcing the re-query).
  ///
  /// Contract:
  ///   * disjoint concrete sets → `false` (elide dispatch)
  ///   * overlapping concrete sets → `true`
  ///   * writer-side `ColumnDependencies.all` (INSERT/DELETE) → `true`
  ///   * reader-side `ColumnDependencies.all` or absent dirty table → `true`
  ///   * dirty table absent from column map (table-only) → `true`
  ///   * dirty table not in entry's deps → continue scanning
  ///
  /// Every uncertainty routes to `true` (re-query). Elision only
  /// happens on the proven-disjoint path.
  static bool affects(
    StreamEntry entry,
    List<String> dirtyTables,
    ColumnDependencyMap dirtyColumns,
  ) {
    final entryDeps = entry.dependencies;
    final entryCols = entry.columnDependencies;
    for (final table in dirtyTables) {
      if (!entryDeps.contains(table)) continue;

      // Writer-side wildcard: INSERT / DELETE / untagged writes — every
      // stream watching this table must re-query because rows may have
      // appeared or disappeared.
      final writerCols = switch (dirtyColumns[table]) {
        AllColumnDependencies() => null,
        FixedColumnDependencies(:final columns) => columns,
        // Table-only invalidation with no column info available — fall
        // back to today's behaviour and re-query.
        null => null,
      };
      if (writerCols == null) return true;

      // Reader-side wildcard or missing column data: degrade safely —
      // re-query the stream.
      final readerCols = switch (entryCols[table]) {
        AllColumnDependencies() => null,
        FixedColumnDependencies(:final columns) => columns,
        null => null,
      };
      if (readerCols == null) return true;

      // Both sides have concrete column sets. Skip the re-query only
      // when they are disjoint.
      for (final c in writerCols) {
        if (readerCols.contains(c)) return true;
      }
    }
    return false;
  }
}
