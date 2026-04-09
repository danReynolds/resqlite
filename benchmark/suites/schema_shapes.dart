// ignore_for_file: avoid_print
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:sqlite_async/sqlite_async.dart' as sqlite_async;

import '../shared/config.dart';
import '../shared/seeder.dart';
import '../shared/stats.dart';

const _rowCount = 1000;

/// Schema shapes benchmark: how different data profiles affect performance.
Future<String> runSchemaShapesBenchmark() async {
  final markdown = StringBuffer();
  markdown.writeln('## Schema Shapes (1000 rows)');
  markdown.writeln('');
  markdown.writeln('Tests performance across different column counts and data types.');
  markdown.writeln('');

  for (final shape in _shapes) {
    final tempDir = await Directory.systemTemp.createTemp('bench_shape_');
    try {
      final timings = await _benchmarkShape(tempDir.path, shape);
      printComparisonTable(
        '=== Schema: ${shape.name} ===',
        timings,
      );
      markdown.write(markdownTable(shape.name, timings));
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  return markdown.toString();
}

final class _Shape {
  const _Shape({
    required this.name,
    required this.createSql,
    required this.insertSql,
    required this.selectSql,
    required this.rowBuilder,
  });

  final String name;
  final String createSql;
  final String insertSql;
  final String selectSql;
  final List<Object?> Function(int i) rowBuilder;
}

final _shapes = <_Shape>[
  _Shape(
    name: 'Narrow (2 cols: id + int)',
    createSql: 'CREATE TABLE t(id INTEGER PRIMARY KEY, value INTEGER NOT NULL)',
    insertSql: 'INSERT INTO t(value) VALUES (?)',
    selectSql: 'SELECT * FROM t',
    rowBuilder: (i) => [i * 7],
  ),
  _Shape(
    name: 'Wide (20 cols: mixed types)',
    createSql: '''CREATE TABLE t(
      id INTEGER PRIMARY KEY,
      c1 INTEGER, c2 INTEGER, c3 INTEGER, c4 INTEGER,
      c5 REAL, c6 REAL, c7 REAL, c8 REAL,
      c9 TEXT, c10 TEXT, c11 TEXT, c12 TEXT,
      c13 INTEGER, c14 REAL, c15 TEXT, c16 INTEGER,
      c17 TEXT, c18 REAL, c19 INTEGER
    )''',
    insertSql:
        'INSERT INTO t(c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,c11,c12,c13,c14,c15,c16,c17,c18,c19) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
    selectSql: 'SELECT * FROM t',
    rowBuilder: (i) => [
      i, i + 1, i + 2, i + 3,
      i * 0.1, i * 0.2, i * 0.3, i * 0.4,
      'str_$i', 'text_${i % 100}', 'val_${i % 50}', 'data_$i',
      i * 10, i * 0.5, 'more_$i', i * 100,
      'field_${i % 20}', i * 1.1, i * 3,
    ],
  ),
  _Shape(
    name: 'Text-heavy (4 long TEXT cols)',
    createSql: '''CREATE TABLE t(
      id INTEGER PRIMARY KEY,
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      summary TEXT NOT NULL,
      notes TEXT NOT NULL,
      score REAL NOT NULL,
      count INTEGER NOT NULL
    )''',
    insertSql: 'INSERT INTO t(title, body, summary, notes, score, count) VALUES (?,?,?,?,?,?)',
    selectSql: 'SELECT * FROM t',
    rowBuilder: (i) => [
      'Title for item number $i which is fairly long to simulate real content',
      'This is the body text for item $i. It contains multiple sentences to simulate a real document body. '
          'Additional text is included here to make the string substantially longer than a typical short field. '
          'Row index is $i and this field should be at least 200 characters long.',
      'Summary of item $i with moderate length content for benchmark purposes and some padding',
      'Notes about item $i: category=${i % 10}, priority=${i % 5}, status=active, last_updated=2026-01-01',
      i * 1.5,
      i * 3,
    ],
  ),
  _Shape(
    name: 'Numeric-heavy (5 numeric cols)',
    createSql: '''CREATE TABLE t(
      id INTEGER PRIMARY KEY,
      a INTEGER NOT NULL,
      b INTEGER NOT NULL,
      c REAL NOT NULL,
      d REAL NOT NULL,
      e INTEGER NOT NULL,
      label TEXT NOT NULL
    )''',
    insertSql: 'INSERT INTO t(a, b, c, d, e, label) VALUES (?,?,?,?,?,?)',
    selectSql: 'SELECT * FROM t',
    rowBuilder: (i) => [i * 7, i * 13, i * 0.333, i * 1.414, i * 99, 'n$i'],
  ),
  _Shape(
    name: 'Nullable (50% NULLs)',
    createSql: '''CREATE TABLE t(
      id INTEGER PRIMARY KEY,
      name TEXT,
      value REAL,
      tag TEXT,
      count INTEGER,
      note TEXT,
      score REAL
    )''',
    insertSql: 'INSERT INTO t(name, value, tag, count, note, score) VALUES (?,?,?,?,?,?)',
    selectSql: 'SELECT * FROM t',
    rowBuilder: (i) => [
      i.isEven ? 'name_$i' : null,
      i % 3 == 0 ? i * 1.5 : null,
      i % 4 == 0 ? 'tag_${i % 10}' : null,
      i.isOdd ? i * 2 : null,
      i % 5 == 0 ? 'note for row $i' : null,
      i % 3 != 0 ? i * 0.7 : null,
    ],
  ),
];

Future<List<BenchmarkTiming>> _benchmarkShape(String dir, _Shape shape) async {
  final resqliteDb = await resqlite.Database.open('$dir/resqlite.db');
  final sqlite3Db = sqlite3.sqlite3.open('$dir/sqlite3.db');
  sqlite3Db.execute('PRAGMA journal_mode = WAL');
  final asyncDb = sqlite_async.SqliteDatabase(path: '$dir/async.db');
  await asyncDb.initialize();

  await seedResqlite(
    resqliteDb, _rowCount,
    createSql: shape.createSql,
    insertSql: shape.insertSql,
    rowBuilder: shape.rowBuilder,
  );
  seedSqlite3(
    sqlite3Db, _rowCount,
    createSql: shape.createSql,
    insertSql: shape.insertSql,
    rowBuilder: shape.rowBuilder,
  );
  await seedSqliteAsync(
    asyncDb, _rowCount,
    createSql: shape.createSql,
    insertSql: shape.insertSql,
    rowBuilder: shape.rowBuilder,
  );

  final sql = shape.selectSql;

  // --- resqlite ---
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

  // --- sqlite3 ---
  final tSqlite3 = BenchmarkTiming('sqlite3');
  for (var i = 0; i < defaultWarmup; i++) {
    final stmt = sqlite3Db.prepare(sql);
    _consume(stmt.select());
    stmt.dispose();
  }
  for (var i = 0; i < defaultIterations; i++) {
    final sw = Stopwatch()..start();
    final stmt = sqlite3Db.prepare(sql);
    _consume(stmt.select());
    stmt.dispose();
    sw.stop();
    tSqlite3.recordWallOnly(sw.elapsedMicroseconds);
  }

  // --- sqlite_async ---
  final tAsync = BenchmarkTiming('sqlite_async');
  for (var i = 0; i < defaultWarmup; i++) {
    _consume(await asyncDb.getAll(sql));
  }
  for (var i = 0; i < defaultIterations; i++) {
    final swWall = Stopwatch()..start();
    final r = await asyncDb.getAll(sql);
    final swMain = Stopwatch()..start();
    _consume(r);
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

void _consume(Iterable<Map<String, dynamic>> rows) {
  for (final row in rows) {
    for (final key in row.keys) {
      row[key];
    }
  }
}

Future<void> main() async {
  await runSchemaShapesBenchmark();
}
