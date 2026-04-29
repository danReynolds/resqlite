// ignore_for_file: avoid_print
import 'dart:io';

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
const _defaultWarmup = 8;
const _defaultIterations = 30;
const _batchSizes = [100, 1000, 10000];

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);

  print('');
  print('=== Batch Param Flatten Benchmark ===');
  print('');
  print('Warmup: ${options.warmup}');
  print('Iterations: ${options.iterations}');
  print('');

  for (final batchSize in _batchSizes) {
    await _runBatchSize(
      batchSize: batchSize,
      warmup: options.warmup,
      iterations: options.iterations,
    );
  }
}

Future<void> _runBatchSize({
  required int batchSize,
  required int warmup,
  required int iterations,
}) async {
  final tempDir = await Directory.systemTemp.createTemp('bench_batch_flatten_');
  try {
    final db = await resqlite.Database.open('${tempDir.path}/test.db');
    try {
      await db.execute(
        'CREATE TABLE items('
        'id INTEGER PRIMARY KEY, '
        'name TEXT NOT NULL, '
        'value REAL NOT NULL'
        ')',
      );

      final List<List<Object?>> paramSets = [
        for (var i = 0; i < batchSize; i++) <Object?>['item_$i', i * 1.5],
      ];
      const insertSql = 'INSERT INTO items(name, value) VALUES (?, ?)';

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

      print('--- $batchSize rows x 2 params ---');
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

int _percentile(List<int> sorted, double p) {
  if (sorted.isEmpty) return 0;
  final idx = ((sorted.length - 1) * p.clamp(0.0, 1.0)).round();
  return sorted[idx];
}

final class _Options {
  const _Options({required this.warmup, required this.iterations});

  final int warmup;
  final int iterations;

  static _Options parse(List<String> args) {
    var warmup = _defaultWarmup;
    var iterations = _defaultIterations;
    for (final arg in args) {
      if (arg.startsWith('--warmup=')) {
        warmup = int.parse(arg.substring('--warmup='.length));
      } else if (arg.startsWith('--iterations=')) {
        iterations = int.parse(arg.substring('--iterations='.length));
      } else if (arg == '--help' || arg == '-h') {
        print(
          'Usage: dart run benchmark/experiments/batch_param_flatten.dart '
          '[--warmup=N] [--iterations=N]',
        );
        exit(0);
      } else {
        stderr.writeln('Unknown argument: $arg');
        exit(2);
      }
    }
    return _Options(warmup: warmup, iterations: iterations);
  }
}
