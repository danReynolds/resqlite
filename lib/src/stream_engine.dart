import 'dart:collection';
import 'dart:async';
import 'dart:typed_data';

import 'dependency_tracking.dart'
    show
        TableColumnDependency,
        FixedTableDependencies,
        TableDependencies,
        TableDependency,
        UnknownTableDependencies;
import 'profile_counters.dart';
import 'profile_mode.dart';
import 'reader/reader_pool.dart';
import 'row_deltas.dart';
import 'stream_ivm.dart';
import 'tracelite_profile.dart';
import 'extensions/set.dart';

/// Hash sentinel stored after an incrementally-patched emission. The
/// native result hash is 63-bit non-negative, so `-1` can never match —
/// the next fallback re-query always decodes and re-emits rather than
/// risking a stale suppression against a pre-patch baseline.
const int _ivmStaleHash = -1;

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

  /// Number of writes that took the conservative all-streams re-query
  /// fallback because native table tracking was unreliable
  /// ([UnknownTableDependencies] — dependency-set overflow or OOM).
  ///
  /// Does not count the benign initial-registration path where a single
  /// new stream's dependencies are not known yet; only whole-index
  /// invalidations. Cumulative for the lifetime of this engine.
  int get unknownDependencyFallbackCount => _unknownDependencyFallbackCount;
  int _unknownDependencyFallbackCount = 0;

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
  ///
  /// [deltas] carries the write cycle's raw row-delta bytes when capture
  /// was reliable (exp 160). Streams admitted for incremental maintenance
  /// consume them to skip or locally patch instead of re-querying; all
  /// other streams ignore them.
  Future<void> onDependencyChanges(
    TableDependencies changes, {
    Uint8List? deltas,
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
    if (kProfileMode) {
      TraceliteProfile.begin(
        TraceliteResqliteSpans.streamInvalidate,
        correlationId: traceCorrelationId,
      );
    }

    try {
      switch (changes) {
        case UnknownTableDependencies():
          _unknownDependencyFallbackCount++;
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

      final deltaBatch = deltas == null ? null : RowDeltaBatch(deltas);
      for (final entry in dirtyEntries) {
        if (deltaBatch != null && _tryIncrementalMaintain(entry, deltaBatch)) {
          continue;
        }
        // This write cycle is bypassing the maintained state (re-query
        // fallback). The state's baseline is now stale relative to the
        // deltas it never saw — and a hash-suppressed re-query would
        // validate emissions without re-syncing it — so drop it; the
        // writer-ordered rebuild/reseed path restores an exact baseline.
        // A maintained state only survives an unbroken chain of cycles
        // it fully processed.
        _dropMaintainedState(entry.ivm);
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

  /// Writer-ordered read used to build IVM caches and aggregate
  /// snapshots. Reads through the writer port are FIFO-ordered against
  /// the write replies that carry row deltas, so a snapshot's position
  /// totally orders it against every delta: writes whose replies were
  /// processed before the snapshot reply are included in it, and all
  /// later deltas apply cleanly on top. (A reader-side snapshot has no
  /// such ordering — it can observe a commit whose delta then lands
  /// after the build, double-applying the write.)
  Future<List<Map<String, Object?>>> Function(
    String sql,
    List<Object?> params,
  )?
  _writerRead;

  /// Wired by [Database] once the writer isolate has spawned. Until (and
  /// unless) attached, full/aggregate admissions are not made and streams
  /// stay on the plain re-query path.
  void attachWriterRead(
    Future<List<Map<String, Object?>>> Function(
      String sql,
      List<Object?> params,
    )
    read,
  ) {
    _writerRead = read;
  }

  /// Per-table admission metadata (`PRAGMA table_info` + the CREATE
  /// statement from sqlite_master, which gates TEXT-equality admission on
  /// the absence of COLLATE clauses), shared across admissions.
  final Map<
    String,
    Future<(List<Map<String, Object?>>, String?)>
  > _tableMetaCache = {};

  Future<(List<Map<String, Object?>>, String?)> _tableMeta(String table) {
    return _tableMetaCache[table] ??= () async {
      final escaped = table.replaceAll('"', '""');
      final info = await _pool.select('PRAGMA table_info("$escaped")');
      final master = await _pool.select(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
        [table],
      );
      final createSql = master.isEmpty ? null : master.first['sql'] as String?;
      return (info, createSql);
    }();
  }

  /// Attempt to maintain [entry]'s cached result from the write cycle's
  /// [batch] instead of re-querying. Returns true when the entry is fully
  /// handled for this cycle (deltas proven irrelevant, or result patched
  /// and emitted).
  bool _tryIncrementalMaintain(StreamEntry entry, RowDeltaBatch batch) {
    final ivm = entry.ivm;
    if (ivm == null || entry.inFlight || entry.dirty) {
      return false;
    }

    final tableDeltas = batch.forTable(ivm.shape.table);
    if (tableDeltas == null || tableDeltas.isEmpty) {
      // Malformed buffer, or the table was reported dirty with no
      // captured rows — either way, trust the dirty set and re-query.
      return false;
    }

    switch (ivm) {
      case IvmSkipState():
        // Tier 1.5: prove all deltas miss, or fall back. There is no
        // cache to drop on a hit.
        if (ivm.apply(tableDeltas) == IvmOutcome.unchanged) {
          if (kProfileMode) ProfileCounters.ivmSkippedTotal++;
          return true;
        }
        if (kProfileMode) ProfileCounters.ivmHitFallbackTotal++;
        return false;

      case IvmFullState():
        if (ivm.rows == null) {
          // Build (or rebuild after a bail/re-query) through the writer
          // so the cache is FIFO-ordered against deltas; until it lands,
          // writes keep falling back to re-query.
          _scheduleFullBuild(entry, ivm);
          return false;
        }
        switch (ivm.apply(tableDeltas)) {
          case IvmOutcome.unchanged:
            if (kProfileMode) ProfileCounters.ivmSkippedTotal++;
            return true;
          case IvmOutcome.applied:
            final visible = ivm.visibleRows();
            // Patches confined to a complete window's invisible tail
            // change the cache but not the emission.
            final previous = entry.lastResult;
            if (previous != null && _sameRowList(previous, visible)) {
              entry.lastResult = visible;
              entry.lastResultHash = _ivmStaleHash;
              entry.lastRowCount = visible.length;
              if (kProfileMode) ProfileCounters.ivmSkippedTotal++;
              return true;
            }
            entry.lastResult = visible;
            entry.lastResultHash = _ivmStaleHash;
            entry.lastRowCount = visible.length;
            entry.emit(visible);
            if (kProfileMode) ProfileCounters.ivmAppliedTotal++;
            return true;
          case IvmOutcome.bail:
            if (kProfileMode) ProfileCounters.ivmBailTotal++;
            return false;
        }

      case IvmAggregateState():
        if (!ivm.seeded) {
          _scheduleAggregateReseed(entry, ivm);
          return false;
        }
        switch (ivm.apply(tableDeltas)) {
          case IvmOutcome.unchanged:
            if (kProfileMode) ProfileCounters.ivmSkippedTotal++;
            return true;
          case IvmOutcome.applied:
            final visible = [ivm.visibleRow()];
            entry.lastResult = visible;
            entry.lastResultHash = _ivmStaleHash;
            entry.lastRowCount = 1;
            entry.emit(visible);
            if (kProfileMode) ProfileCounters.ivmAppliedTotal++;
            return true;
          case IvmOutcome.bail:
            _scheduleAggregateReseed(entry, ivm);
            if (kProfileMode) ProfileCounters.ivmBailTotal++;
            return false;
        }
    }
  }

  /// Drop maintained state whose delta chain has been broken. Skip-only
  /// states carry nothing to drop.
  void _dropMaintainedState(IvmState? state) {
    switch (state) {
      case IvmFullState ivm:
        ivm.rows = null;
        ivm.keys = null;
      case IvmAggregateState ivm:
        ivm.seeded = false;
      case IvmSkipState() || null:
        break;
    }
  }

  /// Rows-identical check by element identity (apply() clones any row it
  /// changes, so identity captures "visibly unchanged" exactly).
  bool _sameRowList(
    List<Map<String, Object?>> a,
    List<Map<String, Object?>> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  /// Try to admit [entry] for incremental maintenance. Best-effort and
  /// asynchronous; until (and unless) it completes, the entry stays on the
  /// plain re-query path.
  Future<void> _admitIvm(StreamEntry entry, String table) async {
    try {
      final (info, createSql) = await _tableMeta(table);
      if (entry.subscribers.isEmpty || entry.ivm != null) return;
      final shape = classifyIvmQuery(
        entry.sql,
        entry.params,
        table,
        info,
        createSql: createSql,
      );
      switch (shape) {
        case null:
          if (kProfileMode) ProfileCounters.ivmRejectedTotal++;
        case IvmFullShape():
          if (_writerRead == null) {
            if (kProfileMode) ProfileCounters.ivmRejectedTotal++;
            return;
          }
          final state = IvmFullState(shape);
          await _buildFullCache(entry, state);
          if (entry.subscribers.isEmpty || entry.ivm != null) return;
          entry.ivm = state;
          if (kProfileMode) ProfileCounters.ivmAdmittedTotal++;
        case IvmSkipShape():
          entry.ivm = IvmSkipState(shape);
          if (kProfileMode) {
            ProfileCounters.ivmAdmittedTotal++;
            ProfileCounters.ivmAdmittedSkipTotal++;
          }
        case IvmAggregateShape():
          if (_writerRead == null) {
            if (kProfileMode) ProfileCounters.ivmRejectedTotal++;
            return;
          }
          final state = IvmAggregateState(shape);
          await _seedAggregate(state, info);
          if (entry.subscribers.isEmpty || entry.ivm != null) return;
          if (state.seeded) {
            entry.ivm = state;
            if (kProfileMode) {
              ProfileCounters.ivmAdmittedTotal++;
              ProfileCounters.ivmAdmittedAggTotal++;
            }
          } else if (kProfileMode) {
            ProfileCounters.ivmRejectedTotal++;
          }
      }
    } catch (_) {
      // Classification is best-effort; the entry stays on re-query.
      if (kProfileMode) ProfileCounters.ivmRejectedTotal++;
    }
  }

  /// Seed (or re-seed) an aggregate state with an exact, writer-ordered
  /// snapshot.
  Future<void> _seedAggregate(
    IvmAggregateState state,
    List<Map<String, Object?>> tableInfo,
  ) async {
    final read = _writerRead;
    if (read == null) return;
    final snapshot = await read(
      buildAggregateSnapshotSql(state.shape, tableInfo),
      const [],
    );
    if (snapshot.length == 1) {
      state.seedFromSnapshot(snapshot.first);
    }
  }

  /// Build a full-maintenance cache with a writer-ordered read of the
  /// entry's own SQL. The result feeds only the cache — emissions remain
  /// reader-driven until deltas start applying.
  Future<void> _buildFullCache(StreamEntry entry, IvmFullState state) async {
    final read = _writerRead;
    if (read == null) return;
    final rows = await read(entry.sql, entry.params);
    state.rebuild(rows);
  }

  /// After a bail or re-query invalidated a full cache, rebuild it
  /// asynchronously off the writer; deltas keep falling back meanwhile.
  void _scheduleFullBuild(StreamEntry entry, IvmFullState state) {
    if (state.buildInFlight) return;
    state.buildInFlight = true;
    unawaited(() async {
      try {
        await _buildFullCache(entry, state);
      } catch (_) {
        // Stay cacheless; the entry keeps re-querying.
      } finally {
        state.buildInFlight = false;
      }
    }());
  }

  /// After an aggregate bail, re-seed asynchronously so a later write can
  /// resume maintenance; re-queries cover the interim.
  void _scheduleAggregateReseed(StreamEntry entry, IvmAggregateState state) {
    if (state.reseedInFlight) return;
    state.reseedInFlight = true;
    unawaited(() async {
      try {
        final (info, _) = await _tableMeta(state.shape.table);
        if (entry.subscribers.isEmpty) return;
        await _seedAggregate(state, info);
      } catch (_) {
        // Stay unseeded; the entry keeps re-querying.
      } finally {
        state.reseedInFlight = false;
      }
    }());
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
    _tableMetaCache.clear();
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

          // Single-table queries are candidates for incremental
          // maintenance (exp 160). Admission is async and best-effort.
          if (tables.length == 1) {
            unawaited(_admitIvm(entry, tables.single.table));
          } else if (kProfileMode) {
            ProfileCounters.ivmRejectedTotal++;
          }
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
      // A fresh query result invalidates the maintained cache; it is
      // rebuilt lazily from lastResult on the next applicable delta.
      // A fresh query result invalidates maintained state; full caches
      // rebuild lazily from lastResult, aggregates re-seed by snapshot.
      switch (entry.ivm) {
        case IvmFullState ivm:
          ivm.rows = null;
          ivm.keys = null;
        case IvmAggregateState ivm:
          ivm.seeded = false;
        case IvmSkipState() || null:
          break;
      }

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

  /// Trace correlation for the write that most recently dirtied this stream.
  ///
  /// Multiple writes may collapse into one re-query; in that case the latest
  /// non-null correlation is retained so the re-query can still be connected
  /// to a triggering write in tracelite.
  int? pendingTraceCorrelationId;

  /// Incremental maintenance state (exp 160). Non-null once the query has
  /// been admitted by the tier-1 classifier; null streams always re-query.
  IvmState? ivm;

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
int _streamKey(String sql, List<Object?> params) {
  return Object.hash(sql, Object.hashAll(params));
}
