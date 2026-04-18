/// Peer abstraction for cross-library benchmarks.
///
/// Every workload that compares resqlite against peers uses this interface
/// instead of hand-rolling per-peer setup. This enforces:
///
///   1. Same schema, same data, same parameter values across all peers
///      (see METHODOLOGY.md § Fair comparison protocol).
///   2. Single place to update on peer version upgrades.
///   3. Capability-based filtering: a reactive workload can request only
///      peers with [BenchmarkPeer.hasStreams], and non-reactive peers are
///      cleanly excluded from the comparison rather than silently failing.
///
/// The interface deliberately does NOT abstract the timing loop. Workloads
/// keep their own timing logic (warmup, iterations, wall vs main split)
/// because that logic is workload-specific and must remain visible to
/// reviewers.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart' as drift_native;
import 'package:resqlite/resqlite.dart' as resqlite;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:sqlite_async/sqlite_async.dart' as sqlite_async;

// ---------------------------------------------------------------------------
// Peer interface
// ---------------------------------------------------------------------------

/// A single library's adapter for the benchmark harness.
///
/// Each implementation wraps the library's native API with a uniform
/// async surface. Synchronous libraries (`sqlite3.dart`) still return
/// Futures — see [isSynchronous] for why this matters for timing.
abstract class BenchmarkPeer {
  /// Short stable identifier. Used in metric keys, log output, and capability
  /// filters. Must match one of: `resqlite`, `sqlite3`, `sqlite_async`.
  String get name;

  /// Human-readable label for markdown result tables — the peer /
  /// library name only (`resqlite`, `sqlite3`, `sqlite_async`), with no
  /// operation or method suffix. Workloads that want to include the
  /// method in the label (to match older suites like `select_maps.dart`
  /// which emit `resqlite select()`) can concatenate `peer.label` with
  /// a workload-specific suffix; scenario workloads with per-op-type
  /// subsections typically use `peer.label` directly because the
  /// subsection heading already carries the op context.
  String get label;

  /// True if this library is purely synchronous under the hood. Used by
  /// timing code to decide whether to record "main isolate time" as equal
  /// to wall time ([BenchmarkTiming.recordWallOnly]) or to measure the
  /// post-return consumption cost separately.
  bool get isSynchronous;

  /// True if this library supports reactive streams via [watch].
  bool get hasStreams;

  /// True if this library supports a single-statement-many-params batch API.
  /// All three current peers have some form of this; the flag exists for
  /// forward compatibility with peers that might not.
  bool get hasBatch;

  // --------------------------------------------------------------------- //
  // Lifecycle
  // --------------------------------------------------------------------- //

  /// Open a database at [path]. Must be called before any other method.
  /// The path may be an absolute filesystem path or `:memory:` for in-memory
  /// databases.
  Future<void> open(String path);

  /// Close the database and release all resources. After this, further calls
  /// throw [StateError].
  Future<void> close();

  // --------------------------------------------------------------------- //
  // Operations
  // --------------------------------------------------------------------- //

  /// Execute a statement that returns no rows (DDL, INSERT, UPDATE, DELETE).
  Future<void> execute(String sql, [List<Object?> params = const []]);

  /// Execute a single statement across many parameter sets inside one
  /// transaction. Required for realistic seed + bulk-write workloads.
  ///
  /// Peers without a native batch API emulate this with an explicit
  /// BEGIN + prepared statement + COMMIT.
  Future<void> executeBatch(String sql, List<List<Object?>> paramSets);

  /// Run a SELECT and return all rows materialized as `List<Map<String,
  /// Object?>>`. Workloads doing per-row iteration should do it inside
  /// their main-isolate timing block to measure materialization cost.
  Future<List<Map<String, Object?>>> select(String sql,
      [List<Object?> params = const []]);

  /// Create a reactive query stream. Must throw [UnsupportedError] when
  /// [hasStreams] is false. Implementations should disable any library-side
  /// throttling so invalidation engines are compared directly.
  ///
  /// [readsFrom] lists the table names the query reads. resqlite and
  /// sqlite_async extract this from the SQL via the authorizer hook, so
  /// they ignore the parameter. **Drift** has no such introspection for
  /// `customSelect` — it needs the table set passed explicitly, or
  /// streams never invalidate. Workloads using [watch] must pass
  /// [readsFrom] correctly; an incorrect or missing set silently breaks
  /// drift's results without crashing. See the [DriftPeer] stream test
  /// for the regression guard.
  Stream<List<Map<String, Object?>>> watch(
    String sql, {
    List<Object?> params = const [],
    Set<String> readsFrom = const {},
  });
}

// ---------------------------------------------------------------------------
// resqlite
// ---------------------------------------------------------------------------

final class ResqlitePeer implements BenchmarkPeer {
  resqlite.Database? _db;

  @override
  String get name => 'resqlite';

  @override
  String get label => 'resqlite';

  @override
  bool get isSynchronous => false;

  @override
  bool get hasStreams => true;

  @override
  bool get hasBatch => true;

  @override
  Future<void> open(String path) async {
    _db = await resqlite.Database.open(path);
  }

  @override
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  resqlite.Database get _requireDb =>
      _db ?? (throw StateError('ResqlitePeer not open'));

  @override
  Future<void> execute(String sql, [List<Object?> params = const []]) async {
    await _requireDb.execute(sql, params);
  }

  @override
  Future<void> executeBatch(
      String sql, List<List<Object?>> paramSets) async {
    await _requireDb.executeBatch(sql, paramSets);
  }

  @override
  Future<List<Map<String, Object?>>> select(String sql,
      [List<Object?> params = const []]) async {
    return _requireDb.select(sql, params);
  }

  @override
  Stream<List<Map<String, Object?>>> watch(
    String sql, {
    List<Object?> params = const [],
    Set<String> readsFrom = const {}, // ignored — resqlite extracts from SQL.
  }) {
    return _requireDb.stream(sql, params);
  }
}

// ---------------------------------------------------------------------------
// sqlite3.dart (synchronous FFI)
// ---------------------------------------------------------------------------

final class Sqlite3Peer implements BenchmarkPeer {
  sqlite3.Database? _db;

  @override
  String get name => 'sqlite3';

  @override
  String get label => 'sqlite3';

  @override
  bool get isSynchronous => true;

  @override
  bool get hasStreams => false;

  @override
  bool get hasBatch => true;

  @override
  Future<void> open(String path) async {
    final db = sqlite3.sqlite3.open(path);
    // Normalize PRAGMAs across peers for fair cross-library comparison.
    // See benchmark/SCOPE.md § "PRAGMA normalization across peers" — all
    // four peers run at WAL + synchronous=NORMAL:
    //   * resqlite: baked in via SQLITE_DEFAULT_WAL_SYNCHRONOUS=1
    //     compile flag (native/resqlite.c), automatic for WAL connections
    //   * sqlite_async: default via SqliteOptions
    //     (synchronous: SqliteSynchronous.normal)
    //   * sqlite3.dart: explicit PRAGMA here
    //   * drift: explicit PRAGMA in driftFactoryFor's setup callback
    // Without this normalization, sqlite3 and drift would pay an extra
    // fsync per commit vs resqlite and sqlite_async, making small-write
    // comparisons a measurement of fsync policy rather than of
    // library overhead.
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA synchronous = NORMAL');
    _db = db;
  }

  @override
  Future<void> close() async {
    _db?.close();
    _db = null;
  }

  sqlite3.Database get _requireDb =>
      _db ?? (throw StateError('Sqlite3Peer not open'));

  @override
  Future<void> execute(String sql, [List<Object?> params = const []]) async {
    _requireDb.execute(sql, params);
  }

  @override
  Future<void> executeBatch(
      String sql, List<List<Object?>> paramSets) async {
    final db = _requireDb;
    db.execute('BEGIN');
    // Prepare is INSIDE the rollback-catch block — if the SQL is
    // malformed, prepare() throws while BEGIN is still open. Without
    // this guard, the transaction leaks and every subsequent op on
    // this peer sees "cannot start a transaction within a transaction".
    sqlite3.PreparedStatement? stmt;
    try {
      stmt = db.prepare(sql);
      for (final params in paramSets) {
        stmt.execute(params);
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      stmt?.close();
    }
  }

  @override
  Future<List<Map<String, Object?>>> select(String sql,
      [List<Object?> params = const []]) async {
    final result = _requireDb.select(sql, params);
    // sqlite3.dart returns ResultSet (Iterable<Map<String, dynamic>>).
    // Cast to Object? shape for interface compatibility; values are
    // runtime-identical (Dart dynamic and Object? differ only at compile
    // time), so no runtime cost.
    return [for (final row in result) Map<String, Object?>.from(row)];
  }

  @override
  Stream<List<Map<String, Object?>>> watch(
    String sql, {
    List<Object?> params = const [],
    Set<String> readsFrom = const {},
  }) {
    throw UnsupportedError('sqlite3.dart does not support reactive streams');
  }
}

// ---------------------------------------------------------------------------
// sqlite_async (PowerSync)
// ---------------------------------------------------------------------------

final class SqliteAsyncPeer implements BenchmarkPeer {
  sqlite_async.SqliteDatabase? _db;

  @override
  String get name => 'sqlite_async';

  @override
  String get label => 'sqlite_async';

  @override
  bool get isSynchronous => false;

  @override
  bool get hasStreams => true;

  @override
  bool get hasBatch => true;

  @override
  Future<void> open(String path) async {
    final db = sqlite_async.SqliteDatabase(path: path);
    await db.initialize();
    _db = db;
  }

  @override
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  sqlite_async.SqliteDatabase get _requireDb =>
      _db ?? (throw StateError('SqliteAsyncPeer not open'));

  @override
  Future<void> execute(String sql, [List<Object?> params = const []]) async {
    await _requireDb.execute(sql, params);
  }

  @override
  Future<void> executeBatch(
      String sql, List<List<Object?>> paramSets) async {
    await _requireDb.executeBatch(sql, paramSets);
  }

  @override
  Future<List<Map<String, Object?>>> select(String sql,
      [List<Object?> params = const []]) async {
    final result = await _requireDb.getAll(sql, params);
    return [for (final row in result) Map<String, Object?>.from(row)];
  }

  @override
  Stream<List<Map<String, Object?>>> watch(
    String sql, {
    List<Object?> params = const [],
    Set<String> readsFrom = const {}, // ignored — sqlite_async extracts from SQL.
  }) {
    // Throttle disabled for fair comparison — see METHODOLOGY.md.
    return _requireDb
        .watch(sql, parameters: params, throttle: Duration.zero)
        .map((rs) =>
            [for (final row in rs) Map<String, Object?>.from(row)]);
  }
}

// ---------------------------------------------------------------------------
// drift (via customSelect + customUpdate + codegen-produced GeneratedDatabase)
// ---------------------------------------------------------------------------

/// Factory type for producing a scenario-specific drift database.
///
/// Each scenario ships its own `@DriftDatabase(tables: [...])` class
/// under `benchmark/drift/` which codegen materializes. The factory
/// constructs that scenario's database using
/// [drift_native.NativeDatabase.createInBackground] so drift runs in
/// its own isolate (fair comparison with resqlite's writer isolate).
typedef DriftDbFactory = drift.GeneratedDatabase Function(String path);

/// Adapter for [`drift`](https://pub.dev/packages/drift) v2.x.
///
/// Benchmarks drift idiomatically via the codegen-produced database
/// class. Uses `customSelect` / `customUpdate` / `customInsert` with
/// explicit `readsFrom` and auto-extracted `updates` sets — both raw
/// and DSL paths end up running the same prepared SQL at runtime, and
/// `customSelect` is the documented drift-community path for queries
/// that would be awkward to express via the DSL. Choosing it here is
/// about keeping the adapter generic (one class handles every scenario
/// without per-scenario DSL code), not about a performance advantage
/// over the DSL.
///
/// Preserves drift's invalidation semantics: streams invalidate on
/// relevant writes exactly as they would for a user-written drift app.
///
/// `customStatement` is explicitly NOT used for writes — it skips
/// `StreamQueryStore` notification, which would silently break every
/// reactive benchmark. See `test/benchmark_drift_peer_test.dart` for
/// the regression guard.
final class DriftPeer implements BenchmarkPeer {
  DriftPeer(this._factory);

  final DriftDbFactory _factory;

  drift.GeneratedDatabase? _db;

  @override
  String get name => 'drift';

  @override
  String get label => 'drift';

  @override
  bool get isSynchronous => false;

  @override
  bool get hasStreams => true;

  @override
  bool get hasBatch => true;

  /// Lookup from table SQL-name (`'messages'`) to the drift table
  /// descriptor the `StreamQueryStore` uses for invalidation.
  /// Rebuilt per [open] because tables belong to a specific opened db.
  Map<String, drift.ResultSetImplementation> _tableByName = const {};

  @override
  Future<void> open(String path) async {
    _db = _factory(path);
    // PRAGMAs run inside the drift isolate's `setup:` callback (see
    // `driftFactoryFor`) so they're applied before the migrator opens
    // the database. No need to re-apply here — doing so would just add
    // an isolate round-trip for no effect.

    // Build the table lookup from the db's registered table set. Drift
    // exposes this via `allTables` on `GeneratedDatabase`. Keys are the
    // SQL-side table names (lowercased via `entityName`), not the
    // Dart class names like `$ItemsTable`.
    _tableByName = {
      for (final t in _db!.allTables) t.entityName.toLowerCase(): t,
    };
  }

  @override
  Future<void> close() async {
    await _db?.close();
    _db = null;
    _tableByName = const {};
  }

  drift.GeneratedDatabase get _requireDb =>
      _db ?? (throw StateError('DriftPeer not open'));

  @override
  Future<void> execute(String sql, [List<Object?> params = const []]) async {
    final db = _requireDb;
    final writeTable = _extractWriteTable(sql);

    if (writeTable == null) {
      // DDL (CREATE TABLE etc) or anything we can't classify — no stream
      // notification needed. `customStatement` is correct here.
      await db.customStatement(sql, params);
      return;
    }

    final resolved = _tableByName[writeTable];
    if (resolved == null) {
      throw StateError(
        'DriftPeer write targets unknown table "$writeTable". '
        'Either the scenario\'s @DriftDatabase is missing this table, '
        'or _extractWriteTable parsed the SQL incorrectly. SQL: $sql',
      );
    }

    // customUpdate/customInsert handle BOTH the execution AND the stream
    // notification. Using them is what keeps drift streams fair vs the
    // other peers' auto-tracking invalidation engines.
    if (_isInsertSql(sql)) {
      await db.customInsert(
        sql,
        variables: _toVariables(params),
        updates: {resolved},
      );
    } else {
      await db.customUpdate(
        sql,
        variables: _toVariables(params),
        updates: {resolved},
      );
    }
  }

  @override
  Future<void> executeBatch(
      String sql, List<List<Object?>> paramSets) async {
    final db = _requireDb;
    final writeTable = _extractWriteTable(sql);
    final resolved = writeTable == null ? null : _tableByName[writeTable];
    if (writeTable != null && resolved == null) {
      throw StateError(
        'DriftPeer batch targets unknown table "$writeTable". SQL: $sql',
      );
    }

    // drift's `batch()` runs all operations in a single transaction and
    // notifies streams once at the end — exactly the semantics we want
    // for a fair executeBatch comparison. Batch only exposes
    // `customStatement`, not `customInsert/customUpdate`, but it accepts
    // an `updates` list for stream notification.
    final updates = resolved == null
        ? const <drift.TableUpdate>[]
        : [drift.TableUpdate(resolved.entityName)];
    await db.batch((b) {
      for (final params in paramSets) {
        b.customStatement(sql, params, updates);
      }
    });
  }

  @override
  Future<List<Map<String, Object?>>> select(String sql,
      [List<Object?> params = const []]) async {
    final rows = await _requireDb
        .customSelect(sql, variables: _toVariables(params))
        .get();
    return [for (final r in rows) Map<String, Object?>.from(r.data)];
  }

  @override
  Stream<List<Map<String, Object?>>> watch(
    String sql, {
    List<Object?> params = const [],
    Set<String> readsFrom = const {},
  }) {
    final resolved = <drift.ResultSetImplementation>{
      for (final name in readsFrom)
        if (_tableByName[name] != null) _tableByName[name]!,
    };
    if (resolved.length != readsFrom.length) {
      final missing = readsFrom.where((n) => !_tableByName.containsKey(n));
      throw StateError(
        'DriftPeer.watch: tables $missing not registered on this drift '
        'db. The scenario\'s @DriftDatabase is missing them. Registered: '
        '${_tableByName.keys.toList()}',
      );
    }
    if (resolved.isEmpty) {
      // Without readsFrom, drift's customSelect stream never invalidates
      // — which would silently produce misleadingly-fast numbers. Fail
      // loudly at setup time rather than at analysis time.
      throw ArgumentError(
        'DriftPeer.watch requires readsFrom for streams to invalidate. '
        'Scenarios must pass the set of table names their SQL reads.',
      );
    }
    return _requireDb
        .customSelect(
          sql,
          variables: _toVariables(params),
          readsFrom: resolved,
        )
        .watch()
        .map((rs) => [for (final r in rs) Map<String, Object?>.from(r.data)]);
  }

  // --- SQL extraction helpers -----------------------------------------

  /// Matches the target table of a single-table write statement. Our
  /// benchmark corpus uses only simple INSERT/UPDATE/DELETE forms so a
  /// regex is sufficient and testable. If this ever stops being true,
  /// swap in drift's `package:sqlparser` for full parse.
  static final RegExp _writeTableRegex = RegExp(
    r'^\s*'
    // INSERT [OR REPLACE|IGNORE|ABORT|FAIL|ROLLBACK] INTO <table>
    // | UPDATE [OR ...] <table>
    // | DELETE FROM <table>
    r'(?:INSERT(?:\s+OR\s+(?:REPLACE|IGNORE|ABORT|FAIL|ROLLBACK))?\s+INTO'
    r'|UPDATE(?:\s+OR\s+(?:REPLACE|IGNORE|ABORT|FAIL|ROLLBACK))?'
    r'|DELETE\s+FROM)'
    r'\s+["`]?(\w+)["`]?',
    caseSensitive: false,
  );

  static String? _extractWriteTable(String sql) {
    final m = _writeTableRegex.firstMatch(sql);
    return m?.group(1)?.toLowerCase();
  }

  static final RegExp _insertRegex =
      RegExp(r'^\s*INSERT\b', caseSensitive: false);

  static bool _isInsertSql(String sql) => _insertRegex.hasMatch(sql);

  /// Wrap a raw value list as drift variables. Drift's `Variable<T>`
  /// expects a typed value; type-switch on the runtime type gives
  /// correct binding without runtime reflection.
  static List<drift.Variable> _toVariables(List<Object?> params) {
    return [
      for (final p in params)
        if (p == null)
          // Drift's Variable<T> requires T extends Object, but the
          // generic type is only used for type-directed binding — null
          // values are special-cased in the binder regardless of T.
          // Picking `int` here is arbitrary; any non-nullable T works.
          const drift.Variable<int>(null)
        else if (p is int)
          drift.Variable<int>(p)
        else if (p is double)
          drift.Variable<double>(p)
        else if (p is String)
          drift.Variable<String>(p)
        else if (p is bool)
          drift.Variable<bool>(p)
        else if (p is List<int>)
          drift.Variable<Uint8List>(Uint8List.fromList(p))
        else
          throw ArgumentError(
              'DriftPeer: unsupported parameter type ${p.runtimeType} '
              'for value $p'),
    ];
  }
}

/// Helper for scenarios to construct a [DriftPeer] with a standard
/// isolate-backed drift database. Scenarios provide the per-scenario
/// constructor closure (e.g. `(exec) => KeyedPkDriftDb(exec)`).
DriftDbFactory driftFactoryFor(
  drift.GeneratedDatabase Function(drift.QueryExecutor executor) dbCtor,
) {
  return (String path) => dbCtor(
        drift_native.NativeDatabase.createInBackground(
          File(path),
          // Drift's `setup:` runs once when the background isolate opens
          // the db, before any migrator or app query — the idiomatic
          // place to configure PRAGMAs.
          //
          // Normalize to match other peers: WAL mode + synchronous=NORMAL.
          // See benchmark/SCOPE.md § "PRAGMA normalization across peers"
          // and the comment on `Sqlite3Peer.open` for why this matters
          // for cross-library fairness.
          setup: (rawDb) {
            rawDb.execute('PRAGMA journal_mode = WAL');
            rawDb.execute('PRAGMA synchronous = NORMAL');
          },
        ),
      );
}

// ---------------------------------------------------------------------------
// PeerSet — convenience for opening all applicable peers on the same tempdir
// ---------------------------------------------------------------------------

/// A collection of [BenchmarkPeer]s opened on separate database files in a
/// shared temp directory. Handles setup + teardown uniformly so workloads
/// don't reimplement the per-peer open dance.
///
/// Usage:
/// ```dart
/// // 3 peers (resqlite, sqlite3, sqlite_async):
/// final peers = await PeerSet.open(tempDir.path);
///
/// // 4 peers including drift — scenario provides its own drift schema:
/// final peers = await PeerSet.open(
///   tempDir.path,
///   driftFactory: driftFactoryFor((exec) => ChatSimDriftDb(exec)),
/// );
/// try {
///   for (final peer in peers.all) {
///     // seed and benchmark
///   }
/// } finally {
///   await peers.closeAll();
/// }
/// ```
final class PeerSet {
  PeerSet._(this.all);

  /// All peers in this set, in a stable order. With no drift factory:
  /// [resqlite, sqlite3, sqlite_async]. With a drift factory: append
  /// drift at the end. Order matters for deterministic chart series
  /// ordering in the dashboard.
  final List<BenchmarkPeer> all;

  /// Open one of each peer type on separate db files inside [tempDirPath].
  /// Each peer gets `<tempDirPath>/<peer.name>.db`.
  ///
  /// [require] optionally filters to peers that satisfy a predicate. For
  /// example, `require: (p) => p.hasStreams` opens only reactive peers.
  ///
  /// [driftFactory] — if provided, a [DriftPeer] is added to the set
  /// using this factory. Scenarios wanting drift coverage must supply
  /// their scenario-specific drift database factory (typically
  /// `driftFactoryFor((exec) => MyScenarioDriftDb(exec))`). If omitted,
  /// drift is not included — useful for scenarios where drift cannot
  /// participate (none currently; all 7 scenarios include it).
  static Future<PeerSet> open(
    String tempDirPath, {
    bool Function(BenchmarkPeer peer)? require,
    DriftDbFactory? driftFactory,
  }) async {
    // Create the target directory if it's missing — scenarios that
    // pass a nested subdir path (e.g. `$tempDir/single`) otherwise trip
    // over a peer.open() that can't write its db file into a
    // non-existent parent.
    final tempDir = Directory(tempDirPath);
    if (!tempDir.existsSync()) {
      await tempDir.create(recursive: true);
    }
    final candidates = <BenchmarkPeer>[
      ResqlitePeer(),
      Sqlite3Peer(),
      SqliteAsyncPeer(),
      if (driftFactory != null) DriftPeer(driftFactory),
    ];
    final chosen =
        require == null ? candidates : candidates.where(require).toList();
    final opened = <BenchmarkPeer>[];
    try {
      for (final peer in chosen) {
        await peer.open('$tempDirPath/${peer.name}.db');
        opened.add(peer);
      }
    } catch (e) {
      // On failure, close whatever we already opened so we don't leak FDs.
      for (final p in opened) {
        await p.close().catchError((_) {});
      }
      rethrow;
    }
    return PeerSet._(opened);
  }

  /// Peers supporting reactive streams. Empty if none match.
  Iterable<BenchmarkPeer> get reactive => all.where((p) => p.hasStreams);

  /// Close every peer in the set, ignoring individual close errors so that
  /// a partial failure doesn't prevent cleanup of the rest.
  Future<void> closeAll() async {
    for (final peer in all) {
      try {
        await peer.close();
      } catch (_) {
        // Swallow per-peer close errors; a leak here is worse than a
        // noisy stack trace masking the original benchmark result.
      }
    }
  }
}
