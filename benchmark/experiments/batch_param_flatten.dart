// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart' as resqlite;
import 'package:resqlite/src/native/resqlite_bindings.dart' as native;

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
///   dart run benchmark/experiments/batch_param_flatten.dart --blob-bytes=256 --blob-mode=reused
///   dart run benchmark/experiments/batch_param_flatten.dart --measure=marshal
const _defaultWarmup = 8;
const _defaultIterations = 30;
const _defaultBlobBytes = 4;
const _batchSizes = [100, 1000, 10000];
const _paramWidths = [2, 8, 20];
const _textModes = {'ascii', 'unicode', 'emoji', 'nul'};
const _blobModes = {'fresh', 'reused'};
const _measureModes = {'execute', 'marshal'};

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);

  print('');
  print('=== Batch Param Flatten Benchmark ===');
  print('');
  print('Warmup: ${options.warmup}');
  print('Iterations: ${options.iterations}');
  print('Text mode: ${options.textMode}');
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
  required int blobBytes,
  required String blobMode,
  required String measure,
}) async {
  final paramSets = _buildParamSets(
    batchSize,
    paramWidth,
    textMode,
    blobBytes,
    blobMode,
  );

  if (measure == 'marshal') {
    _runMarshalShape(
      batchSize: batchSize,
      paramWidth: paramWidth,
      warmup: warmup,
      iterations: iterations,
      paramSets: paramSets,
    );
    return;
  }

  final tempDir = await Directory.systemTemp.createTemp(
    'bench_batch_flatten_${paramWidth}_',
  );
  try {
    final db = await resqlite.Database.open('${tempDir.path}/test.db');
    try {
      await db.execute(_createTableSql(paramWidth));

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

      _printTimings(batchSize, paramWidth, timings);
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
  required List<List<Object?>> paramSets,
}) {
  for (var i = 0; i < warmup; i++) {
    final buf = native.allocateBatchParams(paramSets);
    native.freeParamBuffer(buf);
  }

  final timings = <int>[];
  for (var i = 0; i < iterations; i++) {
    final sw = Stopwatch()..start();
    final buf = native.allocateBatchParams(paramSets);
    native.freeParamBuffer(buf);
    sw.stop();
    timings.add(sw.elapsedMicroseconds);
  }

  _printTimings(batchSize, paramWidth, timings);
}

void _printTimings(int batchSize, int paramWidth, List<int> timings) {
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

String _createTableSql(int paramWidth) {
  final columns = [
    'id INTEGER PRIMARY KEY',
    for (var i = 0; i < paramWidth; i++) 'c$i ${_sqliteTypeFor(i)}',
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
  int blobBytes,
  String blobMode,
) => [
  for (var row = 0; row < batchSize; row++)
    [
      for (var col = 0; col < paramWidth; col++)
        _valueFor(row, col, textMode, blobBytes, blobMode),
    ],
];

String _sqliteTypeFor(int col) => switch (col % 4) {
  0 => 'TEXT',
  1 => 'INTEGER',
  2 => 'REAL',
  _ => 'BLOB',
};

Object? _valueFor(
  int row,
  int col,
  String textMode,
  int blobBytes,
  String blobMode,
) => switch (col % 4) {
  0 => _textValueFor(row, col, textMode),
  1 => row * 31 + col,
  2 => row * 1.5 + col / 10,
  _ => _blobValueFor(row, col, blobBytes, blobMode),
};

String _textValueFor(int row, int col, String textMode) => switch (textMode) {
  'ascii' => 'item_${row}_$col',
  'unicode' => '項目_${row}_列_${col}_東京',
  'emoji' => 'item_${row}_${col}_🎉🚀',
  'nul' => 'item_${row}\u0000$col',
  _ => throw StateError('unsupported text mode $textMode'),
};

Uint8List _blobValueFor(int row, int col, int blobBytes, String blobMode) {
  if (blobMode == 'reused') {
    return _reusedBlobFor(col, row.isEven ? 0 : 1, blobBytes);
  }
  return _makeBlob(row, col, blobBytes);
}

final _reusedBlobs = <String, Uint8List>{};

Uint8List _reusedBlobFor(int col, int slot, int blobBytes) {
  final key = '$col:$slot:$blobBytes';
  return _reusedBlobs.putIfAbsent(key, () => _makeBlob(slot, col, blobBytes));
}

Uint8List _makeBlob(int row, int col, int blobBytes) {
  final bytes = Uint8List(blobBytes);
  for (var i = 0; i < blobBytes; i++) {
    bytes[i] = (row * 31 + col * 17 + i) & 0xff;
  }
  return bytes;
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
    required this.blobBytes,
    required this.blobMode,
    required this.measure,
  });

  final int warmup;
  final int iterations;
  final String textMode;
  final int blobBytes;
  final String blobMode;
  final String measure;

  static _Options parse(List<String> args) {
    var warmup = _defaultWarmup;
    var iterations = _defaultIterations;
    var textMode = 'ascii';
    var blobBytes = _defaultBlobBytes;
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
      } else if (arg.startsWith('--blob-bytes=')) {
        blobBytes = int.parse(arg.substring('--blob-bytes='.length));
        if (blobBytes < 0) {
          stderr.writeln('Blob bytes must be non-negative: $blobBytes');
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
        if (!_measureModes.contains(measure)) {
          stderr.writeln(
            'Unknown measure mode: $measure '
            '(expected one of ${_measureModes.join(', ')})',
          );
          exit(2);
        }
      } else if (arg == '--help' || arg == '-h') {
        print(
          'Usage: dart run benchmark/experiments/batch_param_flatten.dart '
          '[--warmup=N] [--iterations=N] '
          '[--text-mode=${_textModes.join('|')}] '
          '[--blob-bytes=N] [--blob-mode=${_blobModes.join('|')}] '
          '[--measure=${_measureModes.join('|')}]',
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
      blobBytes: blobBytes,
      blobMode: blobMode,
      measure: measure,
    );
  }
}
