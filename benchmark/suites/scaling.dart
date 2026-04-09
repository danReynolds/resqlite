// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:sqlite_async/sqlite_async.dart' as sqlite_async;

import '../shared/config.dart';
import '../shared/seeder.dart';
import '../shared/stats.dart';

const _rowCounts = [10, 50, 100, 500, 1000, 2000, 5000, 10000, 20000];

/// Scaling benchmark: how performance changes with result size.
Future<String> runScalingBenchmark() async {
  final markdown = StringBuffer();
  markdown.writeln('## Scaling (10 → 20,000 rows)');
  markdown.writeln('');
  markdown.writeln('Shows how each library scales with result size. Identifies the crossover '
      'point where resqlite\'s isolate overhead becomes negligible.');
  markdown.writeln('');

  // Maps scaling.
  markdown.writeln('### Maps (select → iterate all fields)');
  markdown.writeln('');
  markdown.writeln(
    '| Rows | resqlite wall | resqlite main | sqlite3 wall | sqlite_async wall |',
  );
  markdown.writeln('|---|---|---|---|---|');

  print('');
  print('=== Scaling: Maps ===');
  print('${'Rows'.padLeft(8)}  ${'resqlite wall'.padLeft(14)}  '
      '${'resqlite main'.padLeft(14)}  ${'sqlite3 wall'.padLeft(14)}  '
      '${'async wall'.padLeft(14)}');
  print('-' * 72);

  for (final rowCount in _rowCounts) {
    final tempDir = await Directory.systemTemp.createTemp('bench_scale_');
    try {
      final r = await _benchmarkMaps(tempDir.path, rowCount);
      print(
        '${rowCount.toString().padLeft(8)}  '
        '${fmtMs(r.resqlite.wall.medianMs)} ms  '
        '${fmtMs(r.resqlite.main.medianMs)} ms  '
        '${fmtMs(r.sqlite3.wall.medianMs)} ms  '
        '${fmtMs(r.async_.wall.medianMs)} ms',
      );
      markdown.writeln(
        '| $rowCount '
        '| ${r.resqlite.wall.medianMs.toStringAsFixed(2)} '
        '| ${r.resqlite.main.medianMs.toStringAsFixed(2)} '
        '| ${r.sqlite3.wall.medianMs.toStringAsFixed(2)} '
        '| ${r.async_.wall.medianMs.toStringAsFixed(2)} |',
      );
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  // Bytes scaling.
  markdown.writeln('');
  markdown.writeln('### Bytes (selectBytes → JSON)');
  markdown.writeln('');
  markdown.writeln(
    '| Rows | resqlite wall | sqlite3+json wall | async+json wall |',
  );
  markdown.writeln('|---|---|---|---|');

  print('');
  print('=== Scaling: Bytes ===');
  print('${'Rows'.padLeft(8)}  ${'resqlite wall'.padLeft(14)}  '
      '${'sqlite3+json'.padLeft(14)}  ${'async+json'.padLeft(14)}');
  print('-' * 52);

  for (final rowCount in _rowCounts) {
    final tempDir = await Directory.systemTemp.createTemp('bench_scale_b_');
    try {
      final r = await _benchmarkBytes(tempDir.path, rowCount);
      print(
        '${rowCount.toString().padLeft(8)}  '
        '${fmtMs(r.resqlite.wall.medianMs)} ms  '
        '${fmtMs(r.sqlite3.wall.medianMs)} ms  '
        '${fmtMs(r.async_.wall.medianMs)} ms',
      );
      markdown.writeln(
        '| $rowCount '
        '| ${r.resqlite.wall.medianMs.toStringAsFixed(2)} '
        '| ${r.sqlite3.wall.medianMs.toStringAsFixed(2)} '
        '| ${r.async_.wall.medianMs.toStringAsFixed(2)} |',
      );
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  markdown.writeln('');
  return markdown.toString();
}

final class _ScaleResult {
  _ScaleResult(this.resqlite, this.sqlite3, this.async_);
  final BenchmarkTiming resqlite;
  final BenchmarkTiming sqlite3;
  final BenchmarkTiming async_;
}

Future<_ScaleResult> _benchmarkMaps(String dir, int rowCount) async {
  final resqliteDb = await resqlite.Database.open('$dir/resqlite.db');
  final sqlite3Db = sqlite3.sqlite3.open('$dir/sqlite3.db');
  sqlite3Db.execute('PRAGMA journal_mode = WAL');
  final asyncDb = sqlite_async.SqliteDatabase(path: '$dir/async.db');
  await asyncDb.initialize();

  await seedResqlite(resqliteDb, rowCount);
  seedSqlite3(sqlite3Db, rowCount);
  await seedSqliteAsync(asyncDb, rowCount);

  const sql = standardSelectSql;

  final tResqlite = BenchmarkTiming('resqlite');
  for (var i = 0; i < defaultWarmup; i++) {
    _consume(await resqliteDb.select(sql));
  }
  for (var i = 0; i < defaultIterations; i++) {
    final swWall = Stopwatch()..start();
    final r = await resqliteDb.select(sql);
    final swMain = Stopwatch()..start();
    _consume(r);
    swMain.stop();
    swWall.stop();
    tResqlite.record(
      wallMicroseconds: swWall.elapsedMicroseconds,
      mainMicroseconds: swMain.elapsedMicroseconds,
    );
  }

  final tSqlite3 = BenchmarkTiming('sqlite3');
  for (var i = 0; i < defaultWarmup; i++) {
    final stmt = sqlite3Db.prepare(sql);
    _consume(stmt.select());
    stmt.close();
  }
  for (var i = 0; i < defaultIterations; i++) {
    final sw = Stopwatch()..start();
    final stmt = sqlite3Db.prepare(sql);
    _consume(stmt.select());
    stmt.close();
    sw.stop();
    tSqlite3.recordWallOnly(sw.elapsedMicroseconds);
  }

  final tAsync = BenchmarkTiming('sqlite_async');
  for (var i = 0; i < defaultWarmup; i++) {
    _consume(await asyncDb.getAll(sql));
  }
  for (var i = 0; i < defaultIterations; i++) {
    final swWall = Stopwatch()..start();
    final rows = await asyncDb.getAll(sql);
    final swMain = Stopwatch()..start();
    _consume(rows);
    swMain.stop();
    swWall.stop();
    tAsync.record(
      wallMicroseconds: swWall.elapsedMicroseconds,
      mainMicroseconds: swMain.elapsedMicroseconds,
    );
  }

  await resqliteDb.close();
  sqlite3Db.close();
  await asyncDb.close();

  return _ScaleResult(tResqlite, tSqlite3, tAsync);
}

Future<_ScaleResult> _benchmarkBytes(String dir, int rowCount) async {
  final resqliteDb = await resqlite.Database.open('$dir/resqlite.db');
  final sqlite3Db = sqlite3.sqlite3.open('$dir/sqlite3.db');
  sqlite3Db.execute('PRAGMA journal_mode = WAL');
  final asyncDb = sqlite_async.SqliteDatabase(path: '$dir/async.db');
  await asyncDb.initialize();

  await seedResqlite(resqliteDb, rowCount);
  seedSqlite3(sqlite3Db, rowCount);
  await seedSqliteAsync(asyncDb, rowCount);

  const sql = standardSelectSql;

  final tResqlite = BenchmarkTiming('resqlite');
  for (var i = 0; i < defaultWarmup; i++) {
    await resqliteDb.selectBytes(sql);
  }
  for (var i = 0; i < defaultIterations; i++) {
    final sw = Stopwatch()..start();
    await resqliteDb.selectBytes(sql);
    sw.stop();
    tResqlite.recordWallOnly(sw.elapsedMicroseconds);
  }

  final tSqlite3 = BenchmarkTiming('sqlite3');
  for (var i = 0; i < defaultWarmup; i++) {
    final stmt = sqlite3Db.prepare(sql);
    utf8.encode(jsonEncode(
      stmt.select().map((r) => Map<String, Object?>.from(r)).toList(),
    ));
    stmt.close();
  }
  for (var i = 0; i < defaultIterations; i++) {
    final sw = Stopwatch()..start();
    final stmt = sqlite3Db.prepare(sql);
    utf8.encode(jsonEncode(
      stmt.select().map((r) => Map<String, Object?>.from(r)).toList(),
    ));
    stmt.close();
    sw.stop();
    tSqlite3.recordWallOnly(sw.elapsedMicroseconds);
  }

  final tAsync = BenchmarkTiming('sqlite_async');
  for (var i = 0; i < defaultWarmup; i++) {
    final r = await asyncDb.getAll(sql);
    utf8.encode(jsonEncode(
      r.map((row) => Map<String, Object?>.from(row)).toList(),
    ));
  }
  for (var i = 0; i < defaultIterations; i++) {
    final sw = Stopwatch()..start();
    final r = await asyncDb.getAll(sql);
    utf8.encode(jsonEncode(
      r.map((row) => Map<String, Object?>.from(row)).toList(),
    ));
    sw.stop();
    tAsync.recordWallOnly(sw.elapsedMicroseconds);
  }

  await resqliteDb.close();
  sqlite3Db.close();
  await asyncDb.close();

  return _ScaleResult(tResqlite, tSqlite3, tAsync);
}

void _consume(Iterable<Map<String, dynamic>> rows) {
  for (final row in rows) {
    for (final key in row.keys) {
      row[key];
    }
  }
}

Future<void> main() async {
  await runScalingBenchmark();
}
