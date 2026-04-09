// ignore_for_file: avoid_print
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:sqlite_async/sqlite_async.dart' as sqlite_async;

import '../shared/config.dart';
import '../shared/seeder.dart';
import '../shared/stats.dart';

/// Core maps benchmark: select → iterate all fields.
Future<String> runSelectMapsBenchmark() async {
  final markdown = StringBuffer();
  markdown.writeln('## Select → Maps');
  markdown.writeln('');
  markdown.writeln('Query returns `List<Map<String, Object?>>`, caller iterates every field.');
  markdown.writeln('');

  for (final rowCount in standardRowCounts) {
    final tempDir = await Directory.systemTemp.createTemp('bench_maps_');
    try {
      final timings = await _benchmarkAtSize(tempDir.path, rowCount);
      printComparisonTable('=== Select Maps: $rowCount rows ===', timings);
      markdown.write(markdownTable('$rowCount rows', timings));
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  return markdown.toString();
}

Future<List<BenchmarkTiming>> _benchmarkAtSize(
  String dir,
  int rowCount,
) async {
  // --- Open databases ---
  final resqliteDb = await resqlite.Database.open('$dir/resqlite.db');
  final sqlite3Db = sqlite3.sqlite3.open('$dir/sqlite3.db');
  sqlite3Db.execute('PRAGMA journal_mode = WAL');
  final asyncDb = sqlite_async.SqliteDatabase(path: '$dir/async.db');
  await asyncDb.initialize();

  // --- Seed identical data ---
  await seedResqlite(resqliteDb, rowCount);
  seedSqlite3(sqlite3Db, rowCount);
  await seedSqliteAsync(asyncDb, rowCount);

  const sql = standardSelectSql;

  // --- resqlite select() ---
  final tResqlite = BenchmarkTiming('resqlite select()');
  for (var i = 0; i < defaultWarmup; i++) {
    final r = await resqliteDb.select(sql);
    _consumeRows(r);
  }
  for (var i = 0; i < defaultIterations; i++) {
    final swWall = Stopwatch()..start();
    final r = await resqliteDb.select(sql);
    final swMain = Stopwatch()..start();
    _consumeRows(r);
    swMain.stop();
    swWall.stop();
    tResqlite.record(
      wallMicroseconds: swWall.elapsedMicroseconds,
      mainMicroseconds: swMain.elapsedMicroseconds,
    );
  }

  // --- sqlite3 select() ---
  final tSqlite3 = BenchmarkTiming('sqlite3 select()');
  for (var i = 0; i < defaultWarmup; i++) {
    final stmt = sqlite3Db.prepare(sql);
    _consumeSqlite3Rows(stmt.select());
    stmt.dispose();
  }
  for (var i = 0; i < defaultIterations; i++) {
    final sw = Stopwatch()..start();
    final stmt = sqlite3Db.prepare(sql);
    _consumeSqlite3Rows(stmt.select());
    stmt.dispose();
    sw.stop();
    tSqlite3.recordWallOnly(sw.elapsedMicroseconds);
  }

  // --- sqlite_async getAll() ---
  final tAsync = BenchmarkTiming('sqlite_async getAll()');
  for (var i = 0; i < defaultWarmup; i++) {
    final r = await asyncDb.getAll(sql);
    _consumeSqlite3Rows(r);
  }
  for (var i = 0; i < defaultIterations; i++) {
    final swWall = Stopwatch()..start();
    final r = await asyncDb.getAll(sql);
    final swMain = Stopwatch()..start();
    _consumeSqlite3Rows(r);
    swMain.stop();
    swWall.stop();
    tAsync.record(
      wallMicroseconds: swWall.elapsedMicroseconds,
      mainMicroseconds: swMain.elapsedMicroseconds,
    );
  }

  // --- Cleanup ---
  await resqliteDb.close();
  sqlite3Db.dispose();
  await asyncDb.close();

  return [tResqlite, tSqlite3, tAsync];
}

void _consumeRows(List<Map<String, Object?>> rows) {
  for (final row in rows) {
    for (final key in row.keys) {
      row[key];
    }
  }
}

void _consumeSqlite3Rows(Iterable<Map<String, dynamic>> rows) {
  for (final row in rows) {
    for (final key in row.keys) {
      row[key];
    }
  }
}

// Allow running standalone.
Future<void> main() async {
  await runSelectMapsBenchmark();
}
