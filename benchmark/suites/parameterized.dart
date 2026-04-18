// ignore_for_file: avoid_print
import 'dart:io';

import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../drift/parameterized_db.dart';
import '../shared/config.dart';
import '../shared/peer.dart';
import '../shared/stats.dart';

const _totalRows = 5000;
const _queryIterations = 100;

/// Parameterized queries benchmark: same query with different params.
///
/// Illustrates statement-cache behavior. Every peer with a cache (resqlite
/// via C-level `stmt_cache`, sqlite_async via its prepared-statement
/// pool, drift via `customSelect` reuse) runs the hot loop with the
/// cache active — that's the normal-user path. For sqlite3 specifically
/// we compare TWO variants because users actively choose between them:
///   * `sqlite3 (no cache)` — `db.prepare(sql)` on every call, typical
///     one-off usage
///   * `sqlite3 (cached stmt)` — hoist `db.prepare(sql)` out of the loop,
///     reuse the prepared statement. Best-case sqlite3.
/// This surfaces the latent cost of `db.prepare` across peers that hide
/// it behind their own cache.
Future<String> runParameterizedBenchmark() async {
  final markdown = StringBuffer();
  markdown.writeln('## Parameterized Queries');
  markdown.writeln('');
  markdown.writeln('Same `SELECT WHERE category = ?` query run $_queryIterations times '
      'with different parameter values. Table has $_totalRows rows with an '
      'index on `category` (~500 rows per category).');
  markdown.writeln('');

  final tempDir = await Directory.systemTemp.createTemp('bench_param_');
  try {
    final timings = await _benchmark(tempDir.path);
    printComparisonTable(
      '=== Parameterized: $_queryIterations queries × ~500 rows each ===',
      timings,
    );
    markdown.write(markdownTable(
      '$_queryIterations queries × ~500 rows each',
      timings,
    ));
  } finally {
    await tempDir.delete(recursive: true);
  }

  return markdown.toString();
}

Future<List<BenchmarkTiming>> _benchmark(String dir) async {
  final timings = <BenchmarkTiming>[];

  // --- Peer-driven measurements (resqlite, sqlite_async, drift) -------
  final peers = await PeerSet.open(
    dir,
    // sqlite3 is excluded from the peer set — we bench two hand-rolled
    // sqlite3 variants below to illustrate the cache-vs-no-cache cost.
    require: (p) => p.name != 'sqlite3',
    driftFactory: driftFactoryFor((exec) => ParameterizedDriftDb(exec)),
  );
  try {
    for (final peer in peers.all) {
      await _seedPeer(peer);
    }
    const sql = 'SELECT * FROM items WHERE category = ?';
    for (final peer in peers.all) {
      final t = BenchmarkTiming(peer.label);
      for (var i = 0; i < defaultWarmup; i++) {
        for (var c = 0; c < 10; c++) {
          await peer.select(sql, ['cat_$c']);
        }
      }
      for (var i = 0; i < defaultIterations; i++) {
        final sw = Stopwatch()..start();
        for (var c = 0; c < _queryIterations; c++) {
          await peer.select(sql, ['cat_${c % 10}']);
        }
        sw.stop();
        t.recordWallOnly(sw.elapsedMicroseconds);
      }
      timings.add(t);
    }
  } finally {
    await peers.closeAll();
  }

  // --- sqlite3 variants (hand-rolled, separate file) ------------------
  // Must run on a separate db file from the PeerSet to avoid the
  // PeerSet's sqlite3.db teardown racing with our own open. The db is
  // single-process so the duplicate seed is tolerable.
  final sqlite3Db = sqlite3.sqlite3.open('$dir/sqlite3_param.db');
  try {
    sqlite3Db.execute('PRAGMA journal_mode = WAL');
    _seedSqlite3(sqlite3Db);
    timings.addAll(_measureSqlite3Variants(sqlite3Db));
  } finally {
    sqlite3Db.close();
  }

  return timings;
}

Future<void> _seedPeer(BenchmarkPeer peer) async {
  const createSql = '''
    CREATE TABLE IF NOT EXISTS items(
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      value REAL NOT NULL,
      category TEXT NOT NULL
    )
  ''';
  const indexSql = 'CREATE INDEX IF NOT EXISTS idx_category ON items(category)';
  const insertSql = 'INSERT INTO items(name, value, category) VALUES (?, ?, ?)';

  await peer.execute(createSql);
  await peer.execute(indexSql);
  await peer.executeBatch(insertSql, [
    for (var i = 0; i < _totalRows; i++)
      ['Item $i', i * 1.5, 'cat_${i % 10}'],
  ]);
}

void _seedSqlite3(sqlite3.Database db) {
  const createSql = '''
    CREATE TABLE items(
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      value REAL NOT NULL,
      category TEXT NOT NULL
    )
  ''';
  db.execute(createSql);
  db.execute('CREATE INDEX idx_category ON items(category)');
  db.execute('BEGIN');
  final stmt = db.prepare(
      'INSERT INTO items(name, value, category) VALUES (?, ?, ?)');
  for (var i = 0; i < _totalRows; i++) {
    stmt.execute(['Item $i', i * 1.5, 'cat_${i % 10}']);
  }
  stmt.close();
  db.execute('COMMIT');
}

List<BenchmarkTiming> _measureSqlite3Variants(sqlite3.Database db) {
  const sql = 'SELECT * FROM items WHERE category = ?';

  // --- sqlite3 (re-prepare each time, like typical one-off usage) ---
  final tNoCache = BenchmarkTiming('sqlite3 (no cache)');
  for (var i = 0; i < defaultWarmup; i++) {
    for (var c = 0; c < 10; c++) {
      final stmt = db.prepare(sql);
      stmt.select(['cat_$c']);
      stmt.close();
    }
  }
  for (var i = 0; i < defaultIterations; i++) {
    final sw = Stopwatch()..start();
    for (var c = 0; c < _queryIterations; c++) {
      final stmt = db.prepare(sql);
      stmt.select(['cat_${c % 10}']);
      stmt.close();
    }
    sw.stop();
    tNoCache.recordWallOnly(sw.elapsedMicroseconds);
  }

  // --- sqlite3 (cached statement, best case) ---
  final tCached = BenchmarkTiming('sqlite3 (cached stmt)');
  final cachedStmt = db.prepare(sql);
  for (var i = 0; i < defaultWarmup; i++) {
    for (var c = 0; c < 10; c++) {
      cachedStmt.select(['cat_$c']);
    }
  }
  for (var i = 0; i < defaultIterations; i++) {
    final sw = Stopwatch()..start();
    for (var c = 0; c < _queryIterations; c++) {
      cachedStmt.select(['cat_${c % 10}']);
    }
    sw.stop();
    tCached.recordWallOnly(sw.elapsedMicroseconds);
  }
  cachedStmt.close();

  return [tNoCache, tCached];
}

Future<void> main() async {
  await runParameterizedBenchmark();
}
