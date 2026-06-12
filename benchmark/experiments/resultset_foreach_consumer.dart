// ignore_for_file: avoid_print

import 'dart:io';

import 'package:resqlite/resqlite.dart';

import '../shared/config.dart';
import '../shared/seeder.dart';
import '../shared/stats.dart';

const _defaultRows = 10000;
const _defaultPasses = 100;

int _sink = 0;

enum _Case {
  forInLookup('for-in lookup'),
  forEachLookup('forEach lookup'),
  indexedLookup('indexed lookup'),
  forEachLength('forEach length');

  const _Case(this.label);

  final String label;
}

final class _Config {
  const _Config({
    required this.rows,
    required this.passes,
    required this.warmup,
    required this.iterations,
  });

  final int rows;
  final int passes;
  final int warmup;
  final int iterations;
}

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  final config = _parseArgs(args);
  final tempDir = await Directory.systemTemp.createTemp(
    'resqlite_resultset_foreach_',
  );
  try {
    final dbPath = '${tempDir.path}/bench.db';
    final db = await Database.open(dbPath);
    try {
      await seedResqlite(db, config.rows);

      print('');
      print('=== ResultSet forEach consumer ===');
      print(
        'Rows: ${config.rows}, columns: 6, passes/sample: ${config.passes}',
      );
      print('Warmup: ${config.warmup}, iterations: ${config.iterations}');
      print(
        'Rows are produced by Database.select() before each timed consumer pass.',
      );
      print('');
      print('| Case | p50 (ms) | p90 (ms) | p99 (ms) | max (ms) |');
      print('|---|---:|---:|---:|---:|');

      for (final benchmarkCase in _Case.values) {
        final timing = BenchmarkTiming(benchmarkCase.label);
        for (var i = 0; i < config.warmup; i++) {
          final rows = await db.select(standardSelectSql);
          _runCase(rows, benchmarkCase, config.passes);
        }

        for (var i = 0; i < config.iterations; i++) {
          final rows = await db.select(standardSelectSql);
          final sw = Stopwatch()..start();
          _runCase(rows, benchmarkCase, config.passes);
          sw.stop();
          timing.recordWallOnly(sw.elapsedMicroseconds);
        }

        print(
          '| ${benchmarkCase.label} '
          '| ${timing.wall.medianMs.toStringAsFixed(3)} '
          '| ${timing.wall.p90Ms.toStringAsFixed(3)} '
          '| ${timing.wall.p99Ms.toStringAsFixed(3)} '
          '| ${timing.wall.maxMs.toStringAsFixed(3)} |',
        );
      }
    } finally {
      await db.close();
    }
  } finally {
    await tempDir.delete(recursive: true);
  }

  if (_sink == 0x7fffffff) {
    print('ignore $_sink');
  }
}

_Config _parseArgs(List<String> args) {
  var rows = _defaultRows;
  var passes = _defaultPasses;
  var warmup = defaultWarmup;
  var iterations = defaultIterations;

  for (final arg in args) {
    if (arg.startsWith('--rows=')) {
      rows = _parsePositiveInt(arg, '--rows=');
    } else if (arg.startsWith('--passes=')) {
      passes = _parsePositiveInt(arg, '--passes=');
    } else if (arg.startsWith('--warmup=')) {
      warmup = _parsePositiveInt(arg, '--warmup=');
    } else if (arg.startsWith('--iterations=')) {
      iterations = _parsePositiveInt(arg, '--iterations=');
    } else {
      throw ArgumentError('Unknown argument: $arg');
    }
  }

  return _Config(
    rows: rows,
    passes: passes,
    warmup: warmup,
    iterations: iterations,
  );
}

int _parsePositiveInt(String arg, String prefix) {
  final value = int.tryParse(arg.substring(prefix.length));
  if (value == null || value <= 0) {
    throw ArgumentError('$prefix expects a positive integer.');
  }
  return value;
}

void _printUsage() {
  print(
    'Usage: dart run benchmark/experiments/resultset_foreach_consumer.dart '
    '[--rows=N] [--passes=N] [--warmup=N] [--iterations=N]',
  );
}

void _runCase(
  List<Map<String, Object?>> rows,
  _Case benchmarkCase,
  int passes,
) {
  switch (benchmarkCase) {
    case _Case.forInLookup:
      for (var pass = 0; pass < passes; pass++) {
        for (final row in rows) {
          _sink ^= row['name'].hashCode;
        }
      }
      return;
    case _Case.forEachLookup:
      for (var pass = 0; pass < passes; pass++) {
        rows.forEach((row) {
          _sink ^= row['name'].hashCode;
        });
      }
      return;
    case _Case.indexedLookup:
      for (var pass = 0; pass < passes; pass++) {
        for (var i = 0; i < rows.length; i++) {
          _sink ^= rows[i]['name'].hashCode;
        }
      }
      return;
    case _Case.forEachLength:
      for (var pass = 0; pass < passes; pass++) {
        rows.forEach((row) {
          _sink ^= row.length;
        });
      }
      return;
  }
}
