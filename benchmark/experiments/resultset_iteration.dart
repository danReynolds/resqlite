// ignore_for_file: avoid_print

import 'package:resqlite/resqlite.dart';

import '../shared/config.dart';
import '../shared/stats.dart';

const _defaultRows = 10000;
const _defaultColumns = 8;
const _defaultPasses = 100;

int _sink = 0;

enum _Case {
  forInLength('for-in length'),
  forInLookup('for-in lookup'),
  forEachLength('forEach length'),
  forEachLookup('forEach lookup'),
  indexedLength('indexed length'),
  indexedLookup('indexed lookup');

  const _Case(this.label);

  final String label;
}

final class _Config {
  _Config({
    required this.rows,
    required this.columns,
    required this.passes,
    required this.warmup,
    required this.iterations,
  });

  final int rows;
  final int columns;
  final int passes;
  final int warmup;
  final int iterations;
}

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  final config = _parseArgs(args);
  final resultSet = _buildResultSet(config.rows, config.columns);

  print('');
  print('=== ResultSet Iteration ===');
  print(
    'Rows: ${config.rows}, columns: ${config.columns}, '
    'passes/sample: ${config.passes}',
  );
  print('Warmup: ${config.warmup}, iterations: ${config.iterations}');
  print(
    'Measures main-isolate iteration overhead on the lazy ResultSet/Row shape.',
  );
  print('');
  print('| Case | p50 (ms) | p90 (ms) | p99 (ms) | max (ms) |');
  print('|---|---:|---:|---:|---:|');

  for (final benchmarkCase in _Case.values) {
    final timing = BenchmarkTiming(benchmarkCase.label);

    for (var i = 0; i < config.warmup; i++) {
      _runCase(resultSet, benchmarkCase, config.passes);
    }

    for (var i = 0; i < config.iterations; i++) {
      final sw = Stopwatch()..start();
      _runCase(resultSet, benchmarkCase, config.passes);
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

  if (_sink == 0x7fffffff) {
    print('ignore $_sink');
  }
}

_Config _parseArgs(List<String> args) {
  var rows = _defaultRows;
  var columns = _defaultColumns;
  var passes = _defaultPasses;
  var warmup = defaultWarmup;
  var iterations = defaultIterations;

  for (final arg in args) {
    if (arg.startsWith('--rows=')) {
      rows = _parsePositiveInt(arg, '--rows=');
    } else if (arg.startsWith('--columns=')) {
      columns = _parsePositiveInt(arg, '--columns=');
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
    columns: columns,
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
    'Usage: dart run benchmark/experiments/resultset_iteration.dart '
    '[--rows=N] [--columns=N] [--passes=N] '
    '[--warmup=N] [--iterations=N]',
  );
}

ResultSet _buildResultSet(int rows, int columns) {
  final schema = RowSchema(
    List<String>.generate(columns, (i) => 'c$i', growable: false),
  );
  final values = List<Object?>.filled(rows * columns, null);
  var write = 0;
  for (var row = 0; row < rows; row++) {
    for (var column = 0; column < columns; column++) {
      values[write++] = row + column;
    }
  }
  return ResultSet(values, schema, rows);
}

void _runCase(ResultSet rows, _Case benchmarkCase, int passes) {
  switch (benchmarkCase) {
    case _Case.forInLength:
      for (var pass = 0; pass < passes; pass++) {
        for (final row in rows) {
          _sink ^= row.length;
        }
      }
      return;
    case _Case.forInLookup:
      for (var pass = 0; pass < passes; pass++) {
        for (final row in rows) {
          _sink ^= row['c0'] as int;
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
    case _Case.forEachLookup:
      for (var pass = 0; pass < passes; pass++) {
        rows.forEach((row) {
          _sink ^= row['c0'] as int;
        });
      }
      return;
    case _Case.indexedLength:
      for (var pass = 0; pass < passes; pass++) {
        for (var i = 0; i < rows.length; i++) {
          _sink ^= rows[i].length;
        }
      }
      return;
    case _Case.indexedLookup:
      for (var pass = 0; pass < passes; pass++) {
        for (var i = 0; i < rows.length; i++) {
          _sink ^= rows[i]['c0'] as int;
        }
      }
      return;
  }
}
