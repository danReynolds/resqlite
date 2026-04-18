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
  Stream<List<Map<String, Object?>>> watch(String sql,
      [List<Object?> params = const []]);
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
  Stream<List<Map<String, Object?>>> watch(String sql,
      [List<Object?> params = const []]) {
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
    // Match resqlite's default mode for fair comparison.
    db.execute('PRAGMA journal_mode = WAL');
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
  Stream<List<Map<String, Object?>>> watch(String sql,
      [List<Object?> params = const []]) {
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
  Stream<List<Map<String, Object?>>> watch(String sql,
      [List<Object?> params = const []]) {
    // Throttle disabled for fair comparison — see METHODOLOGY.md.
    return _requireDb
        .watch(sql, parameters: params, throttle: Duration.zero)
        .map((rs) =>
            [for (final row in rs) Map<String, Object?>.from(row)]);
  }
}

// ---------------------------------------------------------------------------
// PeerSet — convenience for opening all applicable peers on the same tempdir
// ---------------------------------------------------------------------------

/// A collection of [BenchmarkPeer]s opened on separate database files in a
/// shared temp directory. Handles setup + teardown uniformly so workloads
/// don't reimplement the triple-open dance.
///
/// Usage:
/// ```dart
/// final peers = await PeerSet.open(tempDir.path);
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

  /// All peers in this set, in a stable order (resqlite, sqlite3, sqlite_async).
  final List<BenchmarkPeer> all;

  /// Open one of each peer type on separate db files inside [tempDirPath].
  /// Each peer gets `<tempDirPath>/<peer.name>.db`.
  ///
  /// [require] optionally filters to peers that satisfy a predicate. For
  /// example, `require: (p) => p.hasStreams` opens only reactive peers.
  static Future<PeerSet> open(
    String tempDirPath, {
    bool Function(BenchmarkPeer peer)? require,
  }) async {
    final candidates = <BenchmarkPeer>[
      ResqlitePeer(),
      Sqlite3Peer(),
      SqliteAsyncPeer(),
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
