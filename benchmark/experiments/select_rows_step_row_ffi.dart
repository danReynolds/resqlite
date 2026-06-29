// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;

import '../shared/stats.dart';

/// Focused A/B harness for the [EXP-205] per-cell `sqlite3_column_value` reuse
/// in `resqlite_step_row`. Exercises the rows path (`Database.select`) rather
/// than the JSON encoder path that exp 203 already optimized.
///
/// Lane choice: the FFI saving per cell is two `columnMem` invocations
/// (`column_type` + the typed getter, or three for TEXT). The win is largest
/// when the per-cell *work* is small — i.e. INTEGER/FLOAT-heavy schemas, where
/// the FFI fraction of `resqlite_step_row` wall is highest. Wide rows
/// (20 cols) magnify the per-cell cost relative to per-row step overhead.
///
/// Two control lanes:
///   1. Mixed (default schema): 6 cols of strings + reals; FFI saving is
///      smaller relative to text decode cost on the Dart side, so a near-zero
///      delta here is the expected control.
///   2. Wide-text: 20 cols of short strings; same control purpose but stresses
///      the 3-FFI TEXT cell path so the candidate's larger saving applies.
const _warmup = 30;
const _iterations = 200;

double _median(List<double> xs) {
  xs.sort();
  final n = xs.length;
  return n.isOdd ? xs[n ~/ 2] : (xs[n ~/ 2 - 1] + xs[n ~/ 2]) / 2;
}

final class _Case {
  const _Case(this.label, this.createSql, this.insertSql, this.row);

  final String label;
  final String createSql;
  final String insertSql;
  final List<Object?> Function(int i) row;
}

const _intHeavy20Create = '''
  CREATE TABLE items(
    c0 INTEGER PRIMARY KEY,
    c1 INTEGER, c2 INTEGER, c3 INTEGER, c4 INTEGER, c5 INTEGER,
    c6 INTEGER, c7 INTEGER, c8 INTEGER, c9 INTEGER, c10 INTEGER,
    c11 INTEGER, c12 INTEGER, c13 INTEGER, c14 INTEGER, c15 INTEGER,
    c16 INTEGER, c17 INTEGER, c18 INTEGER, c19 INTEGER
  )
''';
const _intHeavy20Insert =
    'INSERT INTO items(c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, '
    'c11, c12, c13, c14, c15, c16, c17, c18, c19) VALUES (?, ?, ?, ?, ?, ?, '
    '?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
List<Object?> _intHeavy20Row(int i) => [
      for (var j = 1; j < 20; j++) i * 31 + j,
    ];

const _intHeavy8Create = '''
  CREATE TABLE items(
    c0 INTEGER PRIMARY KEY,
    c1 INTEGER, c2 INTEGER, c3 INTEGER, c4 INTEGER, c5 INTEGER, c6 INTEGER,
    c7 INTEGER
  )
''';
const _intHeavy8Insert =
    'INSERT INTO items(c1, c2, c3, c4, c5, c6, c7) VALUES (?, ?, ?, ?, ?, ?, ?)';
List<Object?> _intHeavy8Row(int i) => [
      for (var j = 1; j < 8; j++) i * 31 + j,
    ];

const _wideText20Create = '''
  CREATE TABLE items(
    c0 INTEGER PRIMARY KEY,
    c1 TEXT, c2 TEXT, c3 TEXT, c4 TEXT, c5 TEXT,
    c6 TEXT, c7 TEXT, c8 TEXT, c9 TEXT, c10 TEXT,
    c11 TEXT, c12 TEXT, c13 TEXT, c14 TEXT, c15 TEXT,
    c16 TEXT, c17 TEXT, c18 TEXT, c19 TEXT
  )
''';
const _wideText20Insert =
    'INSERT INTO items(c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, '
    'c11, c12, c13, c14, c15, c16, c17, c18, c19) VALUES (?, ?, ?, ?, ?, ?, '
    '?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
List<Object?> _wideText20Row(int i) => [
      for (var j = 1; j < 20; j++) 's_${i}_$j',
    ];

const _standardCreate = '''
  CREATE TABLE items(
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    value REAL NOT NULL,
    category TEXT NOT NULL,
    created_at TEXT NOT NULL
  )
''';
const _standardInsert =
    'INSERT INTO items(name, description, value, category, created_at) '
    'VALUES (?, ?, ?, ?, ?)';
List<Object?> _standardRow(int i) => [
      'Item $i',
      'desc for $i',
      i * 1.5,
      'cat_${i % 10}',
      '2026-04-01T12:00:00Z',
    ];

const _cases = <_Case>[
  _Case('10k x 8 INTEGER', _intHeavy8Create, _intHeavy8Insert, _intHeavy8Row),
  _Case(
    '10k x 20 INTEGER',
    _intHeavy20Create,
    _intHeavy20Insert,
    _intHeavy20Row,
  ),
  _Case('10k x 20 short TEXT', _wideText20Create, _wideText20Insert,
      _wideText20Row),
  _Case('10k x 6 mixed (default)', _standardCreate, _standardInsert,
      _standardRow),
];

const _rowCount = 10000;

Future<void> main() async {
  print('=== select() rows-path step_row FFI focused harness ===');
  print('rows=$_rowCount, warmup=$_warmup, iterations=$_iterations');
  print('');
  print('| Lane | p50 (ms) | p90 (ms) |');
  print('|---|---:|---:|');
  for (final c in _cases) {
    final tempDir = await Directory.systemTemp.createTemp(
      'bench_step_row_ffi_',
    );
    try {
      final db = await resqlite.Database.open('${tempDir.path}/test.db');
      await db.execute(c.createSql);
      for (var i = 0; i < _rowCount; i++) {
        await db.execute(c.insertSql, c.row(i));
      }

      const sql = 'SELECT * FROM items';
      for (var i = 0; i < _warmup; i++) {
        await db.select(sql);
      }

      final samples = <double>[];
      for (var i = 0; i < _iterations; i++) {
        final sw = Stopwatch()..start();
        await db.select(sql);
        sw.stop();
        samples.add(sw.elapsedMicroseconds / 1000.0);
      }
      samples.sort();
      final p50 = _median(List.of(samples));
      final p90 = samples[(samples.length * 0.9).floor()];
      print('| ${c.label} | ${p50.toStringAsFixed(3)} | '
          '${p90.toStringAsFixed(3)} |');
      await db.close();
    } finally {
      await tempDir.delete(recursive: true);
    }
  }
  // Silence unused-import warning if BenchmarkTiming isn't used downstream.
  // ignore: unused_local_variable
  final _ = BenchmarkTiming;
}
