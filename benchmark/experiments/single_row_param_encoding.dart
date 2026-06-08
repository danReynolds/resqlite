// ignore_for_file: avoid_print
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;

/// Focused benchmark for the Dart-side `allocateParams` single-row encoder.
///
/// `allocateParams` runs on every parameterized read and every single-row
/// write (the wide-batch encoder used by `executeBatch` has its own gated fast
/// paths from exp 113 / exp 125 / exp 126). Each iteration measures one
/// `execute()` or `select()` call against a fixed statement shape so the
/// signal is centered on parameter encoding plus its surrounding
/// writer / reader-pool round-trip.
///
/// Usage:
///   dart run benchmark/experiments/single_row_param_encoding.dart
///   dart run benchmark/experiments/single_row_param_encoding.dart --iterations=80
///   dart run benchmark/experiments/single_row_param_encoding.dart --text-mode=unicode
const _defaultWarmup = 8;
const _defaultIterations = 30;
const _defaultBatchSize = 200;
const _textModes = {'ascii', 'unicode'};

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);

  print('');
  print('=== Single Row Param Encoding Benchmark ===');
  print('');
  print('Warmup: ${options.warmup}');
  print('Iterations: ${options.iterations}');
  print('Calls per timed sample: ${options.batchSize}');
  print('Text mode: ${options.textMode}');
  print('');

  await _runInsertShape(
    shape: 'INSERT name+value (1 string + 1 double)',
    warmup: options.warmup,
    iterations: options.iterations,
    callsPerSample: options.batchSize,
    paramBuilder: (i) => ['item_$i', i * 1.5],
    sql: 'INSERT INTO t(name, value) VALUES (?, ?)',
    createSql:
        'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT NOT NULL, value REAL NOT NULL)',
  );

  await _runInsertShape(
    shape: 'INSERT name only (1 string)',
    warmup: options.warmup,
    iterations: options.iterations,
    callsPerSample: options.batchSize,
    paramBuilder: (i) => ['item_$i'],
    sql: 'INSERT INTO t(name) VALUES (?)',
    createSql:
        'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
  );

  await _runInsertShape(
    shape: 'INSERT three strings',
    warmup: options.warmup,
    iterations: options.iterations,
    callsPerSample: options.batchSize,
    paramBuilder: (i) =>
        _buildThreeStringRow(i, options.textMode),
    sql: 'INSERT INTO t(a, b, c) VALUES (?, ?, ?)',
    createSql:
        'CREATE TABLE t(id INTEGER PRIMARY KEY, a TEXT, b TEXT, c TEXT)',
  );

  await _runSelectShape(
    shape: 'SELECT category = ? (1 ASCII string param)',
    warmup: options.warmup,
    iterations: options.iterations,
    callsPerSample: options.batchSize,
    paramBuilder: (i) => ['cat_${i % 10}'],
    selectSql: 'SELECT id FROM items WHERE category = ?',
    seedFn: _seedCategoryTable,
  );
}

List<Object?> _buildThreeStringRow(int i, String textMode) {
  switch (textMode) {
    case 'unicode':
      return ['café_$i', 'mañana_$i', 'naïve_$i'];
    case 'ascii':
    default:
      return ['alpha_$i', 'beta_$i', 'gamma_$i'];
  }
}

Future<void> _runInsertShape({
  required String shape,
  required int warmup,
  required int iterations,
  required int callsPerSample,
  required List<Object?> Function(int i) paramBuilder,
  required String sql,
  required String createSql,
}) async {
  final tempDir = await Directory.systemTemp.createTemp(
    'bench_single_row_param_',
  );
  try {
    final db = await resqlite.Database.open('${tempDir.path}/test.db');
    try {
      await db.execute(createSql);

      // Build params outside the timed region.
      final params = [
        for (var i = 0; i < callsPerSample; i++) paramBuilder(i),
      ];

      for (var w = 0; w < warmup; w++) {
        await db.execute('DELETE FROM t');
        for (var i = 0; i < callsPerSample; i++) {
          await db.execute(sql, params[i]);
        }
      }

      final timings = <int>[];
      for (var iter = 0; iter < iterations; iter++) {
        await db.execute('DELETE FROM t');
        final sw = Stopwatch()..start();
        for (var i = 0; i < callsPerSample; i++) {
          await db.execute(sql, params[i]);
        }
        sw.stop();
        timings.add(sw.elapsedMicroseconds);
      }

      timings.sort();
      final p50 = timings[timings.length ~/ 2];
      final p10 = timings[timings.length ~/ 10];
      final p90 = timings[(timings.length * 9) ~/ 10];
      print(
        '${shape.padRight(54)} '
        'p50=${(p50 / 1000).toStringAsFixed(2)} ms  '
        'p10=${(p10 / 1000).toStringAsFixed(2)}  '
        'p90=${(p90 / 1000).toStringAsFixed(2)} '
        '(n=${timings.length})',
      );
    } finally {
      await db.close();
    }
  } finally {
    await tempDir.delete(recursive: true);
  }
}

Future<void> _runSelectShape({
  required String shape,
  required int warmup,
  required int iterations,
  required int callsPerSample,
  required List<Object?> Function(int i) paramBuilder,
  required String selectSql,
  required Future<void> Function(resqlite.Database db) seedFn,
}) async {
  final tempDir = await Directory.systemTemp.createTemp(
    'bench_single_row_param_sel_',
  );
  try {
    final db = await resqlite.Database.open('${tempDir.path}/test.db');
    try {
      await seedFn(db);

      final params = [
        for (var i = 0; i < callsPerSample; i++) paramBuilder(i),
      ];

      for (var w = 0; w < warmup; w++) {
        for (var i = 0; i < callsPerSample; i++) {
          await db.select(selectSql, params[i]);
        }
      }

      final timings = <int>[];
      for (var iter = 0; iter < iterations; iter++) {
        final sw = Stopwatch()..start();
        for (var i = 0; i < callsPerSample; i++) {
          await db.select(selectSql, params[i]);
        }
        sw.stop();
        timings.add(sw.elapsedMicroseconds);
      }

      timings.sort();
      final p50 = timings[timings.length ~/ 2];
      final p10 = timings[timings.length ~/ 10];
      final p90 = timings[(timings.length * 9) ~/ 10];
      print(
        '${shape.padRight(54)} '
        'p50=${(p50 / 1000).toStringAsFixed(2)} ms  '
        'p10=${(p10 / 1000).toStringAsFixed(2)}  '
        'p90=${(p90 / 1000).toStringAsFixed(2)} '
        '(n=${timings.length})',
      );
    } finally {
      await db.close();
    }
  } finally {
    await tempDir.delete(recursive: true);
  }
}

Future<void> _seedCategoryTable(resqlite.Database db) async {
  await db.execute('''
    CREATE TABLE items(
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      value REAL NOT NULL,
      category TEXT NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_category ON items(category)',
  );
  await db.executeBatch(
    'INSERT INTO items(name, value, category) VALUES (?, ?, ?)',
    [
      for (var i = 0; i < 5000; i++)
        ['Item $i', i * 1.5, 'cat_${i % 10}'],
    ],
  );
}

class _Options {
  _Options({
    required this.warmup,
    required this.iterations,
    required this.batchSize,
    required this.textMode,
  });

  final int warmup;
  final int iterations;
  final int batchSize;
  final String textMode;

  static _Options parse(List<String> args) {
    var warmup = _defaultWarmup;
    var iterations = _defaultIterations;
    var batchSize = _defaultBatchSize;
    var textMode = 'ascii';
    for (final arg in args) {
      if (arg.startsWith('--warmup=')) {
        warmup = int.parse(arg.substring('--warmup='.length));
      } else if (arg.startsWith('--iterations=')) {
        iterations = int.parse(arg.substring('--iterations='.length));
      } else if (arg.startsWith('--batch-size=')) {
        batchSize = int.parse(arg.substring('--batch-size='.length));
      } else if (arg.startsWith('--text-mode=')) {
        textMode = arg.substring('--text-mode='.length);
        if (!_textModes.contains(textMode)) {
          throw ArgumentError('Unknown text mode: $textMode');
        }
      }
    }
    return _Options(
      warmup: warmup,
      iterations: iterations,
      batchSize: batchSize,
      textMode: textMode,
    );
  }
}
