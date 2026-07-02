// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart' as resqlite;
import 'package:resqlite/src/native/resqlite_bindings.dart';

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
///   dart run benchmark/experiments/batch_param_flatten.dart --text-mode=nullable-ascii
///   dart run benchmark/experiments/batch_param_flatten.dart --cell-mode=blob --blob-bytes=256
///   dart run benchmark/experiments/batch_param_flatten.dart --cell-mode=blob --blob-mode=reused --measure=marshal
const _defaultWarmup = 8;
const _defaultIterations = 30;
const _batchSizes = [100, 1000, 10000];
const _paramWidths = [2, 8, 20];
const _textModes = {'ascii', 'unicode', 'emoji', 'nul', 'nullable-ascii'};
const _cellModes = {'mixed', 'blob'};
const _blobModes = {'fresh', 'reused'};
const _measures = {'execute', 'marshal'};

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);

  print('');
  print('=== Batch Param Flatten Benchmark ===');
  print('');
  print('Warmup: ${options.warmup}');
  print('Iterations: ${options.iterations}');
  print('Text mode: ${options.textMode}');
  print('Cell mode: ${options.cellMode}');
  print('Blob bytes: ${options.blobBytes}');
  print('Blob mode: ${options.blobMode}');
  print('Measure: ${options.measure}');
  print('');

  for (final paramWidth in _paramWidths) {
    for (final batchSize in _batchSizes) {
      await _runBatchShape(
        batchSize: batchSize,
        paramWidth: paramWidth,
        warmup: options.warmup,
        iterations: options.iterations,
        textMode: options.textMode,
        cellMode: options.cellMode,
        blobBytes: options.blobBytes,
        blobMode: options.blobMode,
        measure: options.measure,
      );
    }
  }
}

Future<void> _runBatchShape({
  required int batchSize,
  required int paramWidth,
  required int warmup,
  required int iterations,
  required String textMode,
  required String cellMode,
  required int blobBytes,
  required String blobMode,
  required String measure,
}) async {
  if (measure == 'marshal') {
    _runMarshalShape(
      batchSize: batchSize,
      paramWidth: paramWidth,
      warmup: warmup,
      iterations: iterations,
      textMode: textMode,
      cellMode: cellMode,
      blobBytes: blobBytes,
      blobMode: blobMode,
    );
    return;
  }

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
        textMode,
        cellMode,
        blobBytes,
        blobMode,
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

void _runMarshalShape({
  required int batchSize,
  required int paramWidth,
  required int warmup,
  required int iterations,
  required String textMode,
  required String cellMode,
  required int blobBytes,
  required String blobMode,
}) {
  final paramSets = _buildParamSets(
    batchSize,
    paramWidth,
    textMode,
    cellMode,
    blobBytes,
    blobMode,
  );

  for (var i = 0; i < warmup; i++) {
    final buf = allocateBatchParams(paramSets);
    freeParamBuffer(buf);
  }

  final timings = <int>[];
  for (var i = 0; i < iterations; i++) {
    final sw = Stopwatch()..start();
    final buf = allocateBatchParams(paramSets);
    freeParamBuffer(buf);
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
  String textMode,
  String cellMode,
  int blobBytes,
  String blobMode,
) => [
  for (var row = 0; row < batchSize; row++)
    [
      for (var col = 0; col < paramWidth; col++)
        _valueFor(row, col, textMode, cellMode, blobBytes, blobMode),
    ],
];

String _sqliteTypeFor(int col, String cellMode) => switch (cellMode) {
  'blob' => 'BLOB',
  _ => _mixedSqliteTypeFor(col),
};

String _mixedSqliteTypeFor(int col) => switch (col % 4) {
  0 => 'TEXT',
  1 => 'INTEGER',
  2 => 'REAL',
  _ => 'BLOB',
};

Object? _valueFor(
  int row,
  int col,
  String textMode,
  String cellMode,
  int blobBytes,
  String blobMode,
) => switch (cellMode) {
  'blob' => _blobValueFor(row, col, blobBytes, blobMode),
  _ => _mixedValueFor(row, col, textMode),
};

Object? _mixedValueFor(int row, int col, String textMode) => switch (col % 4) {
  0 => _textValueFor(row, col, textMode),
  1 => row * 31 + col,
  2 => row * 1.5 + col / 10,
  _ => _freshBlob(row, col, 4),
};

Object? _textValueFor(int row, int col, String textMode) => switch (textMode) {
  'ascii' => 'item_${row}_$col',
  'unicode' => '項目_${row}_列_${col}_東京',
  'emoji' => 'item_${row}_${col}_🎉🚀',
  'nul' => 'item_${row}\u0000$col',
  'nullable-ascii' => row == 0 ? null : 'item_${row}_$col',
  _ => throw StateError('unsupported text mode $textMode'),
};

final _reusedBlobsBySize = <int, Uint8List>{};

Uint8List _blobValueFor(int row, int col, int bytes, String blobMode) {
  if (blobMode == 'reused') {
    return _reusedBlobsBySize.putIfAbsent(bytes, () => _freshBlob(0, 0, bytes));
  }
  return _freshBlob(row, col, bytes);
}

Uint8List _freshBlob(int row, int col, int bytes) {
  final out = Uint8List(bytes);
  for (var i = 0; i < bytes; i++) {
    out[i] = (row * 31 + col * 17 + i) & 0xff;
  }
  return out;
}

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
    required this.blobBytes,
    required this.blobMode,
    required this.measure,
  });

  final int warmup;
  final int iterations;
  final String textMode;
  final String cellMode;
  final int blobBytes;
  final String blobMode;
  final String measure;

  static _Options parse(List<String> args) {
    var warmup = _defaultWarmup;
    var iterations = _defaultIterations;
    var textMode = 'ascii';
    var cellMode = 'mixed';
    var blobBytes = 4;
    var blobMode = 'fresh';
    var measure = 'execute';
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
      } else if (arg.startsWith('--blob-bytes=')) {
        blobBytes = int.parse(arg.substring('--blob-bytes='.length));
        if (blobBytes < 0) {
          stderr.writeln('blob bytes must be non-negative');
          exit(2);
        }
      } else if (arg.startsWith('--blob-mode=')) {
        blobMode = arg.substring('--blob-mode='.length);
        if (!_blobModes.contains(blobMode)) {
          stderr.writeln(
            'Unknown blob mode: $blobMode '
            '(expected one of ${_blobModes.join(', ')})',
          );
          exit(2);
        }
      } else if (arg.startsWith('--measure=')) {
        measure = arg.substring('--measure='.length);
        if (!_measures.contains(measure)) {
          stderr.writeln(
            'Unknown measure: $measure '
            '(expected one of ${_measures.join(', ')})',
          );
          exit(2);
        }
      } else if (arg == '--help' || arg == '-h') {
        print(
          'Usage: dart run benchmark/experiments/batch_param_flatten.dart '
          '[--warmup=N] [--iterations=N] '
          '[--text-mode=${_textModes.join('|')}] '
          '[--cell-mode=${_cellModes.join('|')}] '
          '[--blob-bytes=N] '
          '[--blob-mode=${_blobModes.join('|')}] '
          '[--measure=${_measures.join('|')}]',
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
      blobBytes: blobBytes,
      blobMode: blobMode,
      measure: measure,
    );
  }
}
