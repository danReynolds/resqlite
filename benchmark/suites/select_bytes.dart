// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:sqlite_async/sqlite_async.dart' as sqlite_async;

import '../shared/config.dart';
import '../shared/seeder.dart';
import '../shared/stats.dart';

/// Bytes benchmark: query → JSON bytes (for HTTP response).
Future<String> runSelectBytesBenchmark() async {
  final markdown = StringBuffer();
  markdown.writeln('## Select → JSON Bytes');
  markdown.writeln('');
  markdown.writeln('Query result serialized to JSON-encoded `Uint8List` for HTTP response.');
  markdown.writeln('');

  for (final rowCount in standardRowCounts) {
    final tempDir = await Directory.systemTemp.createTemp('bench_bytes_');
    try {
      final timings = await _benchmarkAtSize(tempDir.path, rowCount);
      printComparisonTable('=== Select Bytes: $rowCount rows ===', timings);
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
  final resqliteDb = await resqlite.Database.open('$dir/resqlite.db');
  final sqlite3Db = sqlite3.sqlite3.open('$dir/sqlite3.db');
  sqlite3Db.execute('PRAGMA journal_mode = WAL');
  final asyncDb = sqlite_async.SqliteDatabase(path: '$dir/async.db');
  await asyncDb.initialize();

  await seedResqlite(resqliteDb, rowCount);
  seedSqlite3(sqlite3Db, rowCount);
  await seedSqliteAsync(asyncDb, rowCount);

  const sql = standardSelectSql;

  // --- resqlite selectBytes() ---
  final tResqlite = BenchmarkTiming('resqlite selectBytes()');
  for (var i = 0; i < defaultWarmup; i++) {
    await resqliteDb.selectBytes(sql);
  }
  for (var i = 0; i < defaultIterations; i++) {
    final swWall = Stopwatch()..start();
    final bytes = await resqliteDb.selectBytes(sql);
    final swMain = Stopwatch()..start();
    bytes.length; // force reference
    swMain.stop();
    swWall.stop();
    tResqlite.record(
      wallMicroseconds: swWall.elapsedMicroseconds,
      mainMicroseconds: swMain.elapsedMicroseconds,
    );
  }

  // --- sqlite3 + jsonEncode ---
  final tSqlite3 = BenchmarkTiming('sqlite3 + jsonEncode');
  for (var i = 0; i < defaultWarmup; i++) {
    final stmt = sqlite3Db.prepare(sql);
    utf8.encode(jsonEncode(
      stmt.select().map((r) => Map<String, Object?>.from(r)).toList(),
    ));
    stmt.dispose();
  }
  for (var i = 0; i < defaultIterations; i++) {
    final sw = Stopwatch()..start();
    final stmt = sqlite3Db.prepare(sql);
    utf8.encode(jsonEncode(
      stmt.select().map((r) => Map<String, Object?>.from(r)).toList(),
    ));
    stmt.dispose();
    sw.stop();
    tSqlite3.recordWallOnly(sw.elapsedMicroseconds);
  }

  // --- sqlite_async + jsonEncode ---
  final tAsync = BenchmarkTiming('sqlite_async + jsonEncode');
  for (var i = 0; i < defaultWarmup; i++) {
    final r = await asyncDb.getAll(sql);
    utf8.encode(jsonEncode(
      r.map((row) => Map<String, Object?>.from(row)).toList(),
    ));
  }
  for (var i = 0; i < defaultIterations; i++) {
    final swWall = Stopwatch()..start();
    final r = await asyncDb.getAll(sql);
    final swMain = Stopwatch()..start();
    utf8.encode(jsonEncode(
      r.map((row) => Map<String, Object?>.from(row)).toList(),
    ));
    swMain.stop();
    swWall.stop();
    tAsync.record(
      wallMicroseconds: swWall.elapsedMicroseconds,
      mainMicroseconds: swMain.elapsedMicroseconds,
    );
  }

  await resqliteDb.close();
  sqlite3Db.dispose();
  await asyncDb.close();

  return [tResqlite, tSqlite3, tAsync];
}

Future<void> main() async {
  await runSelectBytesBenchmark();
}
