// ignore_for_file: avoid_print
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:sqlite_async/sqlite_async.dart' as sqlite_async;

import '../shared/config.dart';
import '../shared/stats.dart';

const _totalRows = 5000;
const _queryIterations = 100;

/// Parameterized queries benchmark: same query with different params.
/// Shows statement cache benefit (resqlite caches in C, sqlite3 must re-prepare).
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
  final resqliteDb = await resqlite.Database.open('$dir/resqlite.db');
  final sqlite3Db = sqlite3.sqlite3.open('$dir/sqlite3.db');
  sqlite3Db.execute('PRAGMA journal_mode = WAL');
  final asyncDb = sqlite_async.SqliteDatabase(path: '$dir/async.db');
  await asyncDb.initialize();

  // Seed with categories 0-9 (each ~500 rows).
  const createSql = '''
    CREATE TABLE items(
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      value REAL NOT NULL,
      category TEXT NOT NULL
    )
  ''';
  const indexSql = 'CREATE INDEX idx_category ON items(category)';
  const insertSql = 'INSERT INTO items(name, value, category) VALUES (?, ?, ?)';

  await resqliteDb.execute(createSql);
  await resqliteDb.execute(indexSql);
  sqlite3Db.execute(createSql);
  sqlite3Db.execute(indexSql);
  await asyncDb.execute(createSql);
  await asyncDb.execute(indexSql);

  for (var i = 0; i < _totalRows; i++) {
    final params = <Object?>['Item $i', i * 1.5, 'cat_${i % 10}'];
    await resqliteDb.execute(insertSql, params);
    sqlite3Db.execute(insertSql, params);
  }
  await asyncDb.executeBatch(insertSql, [
    for (var i = 0; i < _totalRows; i++)
      ['Item $i', i * 1.5, 'cat_${i % 10}'],
  ]);

  const sql = 'SELECT * FROM items WHERE category = ?';

  // --- resqlite ---
  final tResqlite = BenchmarkTiming('resqlite select()');
  for (var i = 0; i < defaultWarmup; i++) {
    for (var c = 0; c < 10; c++) {
      await resqliteDb.select(sql, ['cat_$c']);
    }
  }
  for (var i = 0; i < defaultIterations; i++) {
    final sw = Stopwatch()..start();
    for (var c = 0; c < _queryIterations; c++) {
      await resqliteDb.select(sql, ['cat_${c % 10}']);
    }
    sw.stop();
    tResqlite.recordWallOnly(sw.elapsedMicroseconds);
  }

  // --- sqlite3 (re-prepare each time, like a typical usage) ---
  final tSqlite3NoCach = BenchmarkTiming('sqlite3 (no cache)');
  for (var i = 0; i < defaultWarmup; i++) {
    for (var c = 0; c < 10; c++) {
      final stmt = sqlite3Db.prepare(sql);
      stmt.select(['cat_$c']);
      stmt.dispose();
    }
  }
  for (var i = 0; i < defaultIterations; i++) {
    final sw = Stopwatch()..start();
    for (var c = 0; c < _queryIterations; c++) {
      final stmt = sqlite3Db.prepare(sql);
      stmt.select(['cat_${c % 10}']);
      stmt.dispose();
    }
    sw.stop();
    tSqlite3NoCach.recordWallOnly(sw.elapsedMicroseconds);
  }

  // --- sqlite3 (cached statement, best case) ---
  final tSqlite3Cached = BenchmarkTiming('sqlite3 (cached stmt)');
  final cachedStmt = sqlite3Db.prepare(sql);
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
    tSqlite3Cached.recordWallOnly(sw.elapsedMicroseconds);
  }
  cachedStmt.dispose();

  // --- sqlite_async ---
  final tAsync = BenchmarkTiming('sqlite_async getAll()');
  for (var i = 0; i < defaultWarmup; i++) {
    for (var c = 0; c < 10; c++) {
      await asyncDb.getAll(sql, ['cat_$c']);
    }
  }
  for (var i = 0; i < defaultIterations; i++) {
    final sw = Stopwatch()..start();
    for (var c = 0; c < _queryIterations; c++) {
      await asyncDb.getAll(sql, ['cat_${c % 10}']);
    }
    sw.stop();
    tAsync.recordWallOnly(sw.elapsedMicroseconds);
  }

  await resqliteDb.close();
  sqlite3Db.dispose();
  await asyncDb.close();

  return [tResqlite, tSqlite3NoCach, tSqlite3Cached, tAsync];
}

Future<void> main() async {
  await runParameterizedBenchmark();
}
