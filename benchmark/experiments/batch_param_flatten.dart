// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart' as resqlite;

/// Focused benchmark for the Dart-side `executeBatch` parameter-flatten step.
///
/// The benchmark prebuilds the nested `paramSets` list outside the timed
/// region. Each timed sample deletes previous rows, then measures only one
/// `executeBatch` call against a fixed statement shape. This keeps the signal
/// centered on writer-isolate batch preparation + SQLite batch execution.
///
/// Usage:
///   dart run benchmark/experiments/batch_param_flatten.dart
///   dart run benchmark/experiments/batch_param_flatten.dart --iterations=80
///   dart run benchmark/experiments/batch_param_flatten.dart --text-mode=unicode
///   dart run benchmark/experiments/batch_param_flatten.dart \
///     --cell-mode=blob --blob-size=256
///
/// `--cell-mode=mixed` keeps the historical 25%/25%/25%/25% TEXT/INT/REAL/BLOB
/// shape (exp 113 / 125 / 126). `--cell-mode=blob` switches to BLOB-only
/// columns, sized by `--blob-size`, so future runs can answer the
/// parameter-encoding-and-binding open question: "Are there remaining
/// blob-heavy parameter shapes where encoding, not SQLite stepping, dominates?"
/// ([EXP-138](../../experiments/138-blob-param-shape-audit.md)).
const _defaultWarmup = 8;
const _defaultIterations = 30;
const _defaultBlobSize = 4;
const _batchSizes = [100, 1000, 10000];
const _paramWidths = [2, 8, 20];
const _textModes = {'ascii', 'unicode', 'emoji', 'nul'};
const _cellModes = {'mixed', 'blob'};

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);

  print('');
  print('=== Batch Param Flatten Benchmark ===');
  print('');
  print('Warmup: ${options.warmup}');
  print('Iterations: ${options.iterations}');
  print('Cell mode: ${options.cellMode}');
  if (options.cellMode == 'blob') {
    print('Blob size: ${options.blobSize} bytes');
  } else {
    print('Text mode: ${options.textMode}');
  }
  print('');

  for (final paramWidth in _paramWidths) {
    for (final batchSize in _batchSizes) {
      await _runBatchShape(
        batchSize: batchSize,
        paramWidth: paramWidth,
        warmup: options.warmup,
        iterations: options.iterations,
        cellMode: options.cellMode,
        textMode: options.textMode,
        blobSize: options.blobSize,
      );
    }
  }
}

Future<void> _runBatchShape({
  required int batchSize,
  required int paramWidth,
  required int warmup,
  required int iterations,
  required String cellMode,
  required String textMode,
  required int blobSize,
}) async {
  final tempDir = await Directory.systemTemp.createTemp(
    'bench_batch_flatten_${paramWidth}_',
  );
  try {
    final db = await resqlite.Database.open('${tempDir.path}/test.db');
    try {
      await db.execute(_createTableSql(paramWidth, cellMode));

      final paramSets = _buildParamSets(
        batchSize,
        paramWidth,
        cellMode,
        textMode,
        blobSize,
      );
      final insertSql = _insertSql(paramWidth);

      for (var i = 0; i < warmup; i++) {
        await db.execute('DELETE FROM items');
        await db.executeBatch(insertSql, paramSets);
      }

      final timings = <int>[];
      for (var i = 0; i < iterations; i++) {
        await db.execute('DELETE FROM items');
        final sw = Stopwatch()..start();
        await db.executeBatch(insertSql, paramSets);
        sw.stop();
        timings.add(sw.elapsedMicroseconds);
      }

      timings.sort();
      final p50 = _percentile(timings, 0.50) / 1000.0;
      final p90 = _percentile(timings, 0.90) / 1000.0;
      final p99 = _percentile(timings, 0.99) / 1000.0;
      final min = timings.first / 1000.0;
      final max = timings.last / 1000.0;

      print('--- $batchSize rows x $paramWidth params ---');
      print('  min: ${min.toStringAsFixed(3)} ms');
      print('  p50: ${p50.toStringAsFixed(3)} ms');
      print('  p90: ${p90.toStringAsFixed(3)} ms');
      print('  p99: ${p99.toStringAsFixed(3)} ms');
      print('  max: ${max.toStringAsFixed(3)} ms');
      print('');
    } finally {
      await db.close();
    }
  } finally {
    await tempDir.delete(recursive: true);
  }
}

String _createTableSql(int paramWidth, String cellMode) {
  final columns = [
    'id INTEGER PRIMARY KEY',
    for (var i = 0; i < paramWidth; i++) 'c$i ${_sqliteTypeFor(i, cellMode)}',
  ];
  return 'CREATE TABLE items(${columns.join(', ')})';
}

String _insertSql(int paramWidth) {
  final columns = [for (var i = 0; i < paramWidth; i++) 'c$i'];
  final placeholders = [for (var i = 0; i < paramWidth; i++) '?'];
  return 'INSERT INTO items(${columns.join(', ')}) '
      'VALUES (${placeholders.join(', ')})';
}

List<List<Object?>> _buildParamSets(
  int batchSize,
  int paramWidth,
  String cellMode,
  String textMode,
  int blobSize,
) => [
  for (var row = 0; row < batchSize; row++)
    [
      for (var col = 0; col < paramWidth; col++)
        _valueFor(row, col, cellMode, textMode, blobSize),
    ],
];

String _sqliteTypeFor(int col, String cellMode) {
  if (cellMode == 'blob') return 'BLOB';
  return switch (col % 4) {
    0 => 'TEXT',
    1 => 'INTEGER',
    2 => 'REAL',
    _ => 'BLOB',
  };
}

Object? _valueFor(
  int row,
  int col,
  String cellMode,
  String textMode,
  int blobSize,
) {
  if (cellMode == 'blob') return _blobValueFor(row, col, blobSize);
  return switch (col % 4) {
    0 => _textValueFor(row, col, textMode),
    1 => row * 31 + col,
    2 => row * 1.5 + col / 10,
    _ => _smallBlobValue(row, col),
  };
}

Uint8List _smallBlobValue(int row, int col) =>
    Uint8List.fromList([row & 0xff, (row >> 8) & 0xff, col & 0xff, 0xA5]);

/// Deterministic blob of `size` bytes for `--cell-mode=blob`. Content
/// varies with `row` and `col` so the SQLite engine cannot collapse
/// values into a shared cached representation (which would understate
/// per-row encoding cost).
Uint8List _blobValueFor(int row, int col, int size) {
  final bytes = Uint8List(size);
  // Two-byte seed from row+col plus a position-dependent step so each
  // byte differs from its neighbours. Cheap to fill but enough variation
  // to avoid any all-zero buffer optimization in SQLite or page-store
  // compaction.
  final seedLo = (row & 0xff) ^ (col & 0xff);
  final seedHi = ((row >> 8) & 0xff) ^ ((col >> 1) & 0xff);
  for (var i = 0; i < size; i++) {
    bytes[i] = (seedLo + i * 13 + (seedHi ^ (i >> 3))) & 0xff;
  }
  return bytes;
}

String _textValueFor(int row, int col, String textMode) => switch (textMode) {
  'ascii' => 'item_${row}_$col',
  'unicode' => '項目_${row}_列_${col}_東京',
  'emoji' => 'item_${row}_${col}_🎉🚀',
  'nul' => 'item_${row}\u0000$col',
  _ => throw StateError('unsupported text mode $textMode'),
};

int _percentile(List<int> sorted, double p) {
  if (sorted.isEmpty) return 0;
  final idx = ((sorted.length - 1) * p.clamp(0.0, 1.0)).round();
  return sorted[idx];
}

final class _Options {
  const _Options({
    required this.warmup,
    required this.iterations,
    required this.textMode,
    required this.cellMode,
    required this.blobSize,
  });

  final int warmup;
  final int iterations;
  final String textMode;
  final String cellMode;
  final int blobSize;

  static _Options parse(List<String> args) {
    var warmup = _defaultWarmup;
    var iterations = _defaultIterations;
    var textMode = 'ascii';
    var cellMode = 'mixed';
    var blobSize = _defaultBlobSize;
    for (final arg in args) {
      if (arg.startsWith('--warmup=')) {
        warmup = int.parse(arg.substring('--warmup='.length));
      } else if (arg.startsWith('--iterations=')) {
        iterations = int.parse(arg.substring('--iterations='.length));
      } else if (arg.startsWith('--text-mode=')) {
        textMode = arg.substring('--text-mode='.length);
        if (!_textModes.contains(textMode)) {
          stderr.writeln(
            'Unknown text mode: $textMode '
            '(expected one of ${_textModes.join(', ')})',
          );
          exit(2);
        }
      } else if (arg.startsWith('--cell-mode=')) {
        cellMode = arg.substring('--cell-mode='.length);
        if (!_cellModes.contains(cellMode)) {
          stderr.writeln(
            'Unknown cell mode: $cellMode '
            '(expected one of ${_cellModes.join(', ')})',
          );
          exit(2);
        }
      } else if (arg.startsWith('--blob-size=')) {
        blobSize = int.parse(arg.substring('--blob-size='.length));
        if (blobSize <= 0) {
          stderr.writeln('--blob-size must be positive (got $blobSize)');
          exit(2);
        }
      } else if (arg == '--help' || arg == '-h') {
        print(
          'Usage: dart run benchmark/experiments/batch_param_flatten.dart '
          '[--warmup=N] [--iterations=N] '
          '[--text-mode=${_textModes.join('|')}] '
          '[--cell-mode=${_cellModes.join('|')}] '
          '[--blob-size=N]',
        );
        exit(0);
      } else {
        stderr.writeln('Unknown argument: $arg');
        exit(2);
      }
    }
    return _Options(
      warmup: warmup,
      iterations: iterations,
      textMode: textMode,
      cellMode: cellMode,
      blobSize: blobSize,
    );
  }
}
