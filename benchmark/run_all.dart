// ignore_for_file: avoid_print
import 'dart:io' show Directory, File, exit;
import 'dart:math' as math;

import 'shared/parse_results.dart';
import 'suites/concurrent_reads.dart';
import 'suites/parameterized.dart';
import 'suites/point_query.dart';
import 'suites/scaling.dart';
import 'suites/schema_shapes.dart';
import 'suites/select_bytes.dart';
import 'suites/select_maps.dart';
import 'suites/streaming.dart';
import 'suites/writes.dart';

Future<void> main(List<String> args) async {
  final options = _parseOptions(args);
  final resultsDir = Directory('benchmark/results');
  final compareFile = _resolveComparisonFile(resultsDir, options.compareToPath);

  final runMarkdowns = <String>[];
  final runMetrics = <Map<String, double>>[];

  print('resqlite Comprehensive Benchmark Suite');
  print('=====================================');
  print('');
  print('Label: ${options.label}');
  print('Repeats: ${options.repeatCount}');
  if (compareFile != null) {
    print('Compare to: ${compareFile.path}');
  } else {
    print('Compare to: none');
  }
  print('');

  for (var i = 0; i < options.repeatCount; i++) {
    if (options.repeatCount > 1) {
      print('--- Repeat ${i + 1}/${options.repeatCount} ---');
    }
    final markdown = await _runSuiteOnce();
    runMarkdowns.add(markdown);
    runMetrics.add(extractResqliteMedians(markdown));
  }

  final representativeMarkdown = runMarkdowns.last;
  final currentAggregates = _aggregateRunMetrics(runMetrics);

  final markdown = StringBuffer()
    ..writeln('# resqlite Benchmark Results')
    ..writeln()
    ..writeln('Generated: ${DateTime.now().toIso8601String()}')
    ..writeln()
    ..writeln('Libraries compared:')
    ..writeln('- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy')
    ..writeln('- **sqlite3** — raw FFI, synchronous, per-cell column reads')
    ..writeln('- **sqlite_async** — PowerSync, async connection pool')
    ..writeln()
    ..writeln('Run settings:')
    ..writeln('- Label: `${options.label}`')
    ..writeln('- Repeats: `${options.repeatCount}`')
    ..writeln(
      '- Comparison baseline: `${compareFile?.path.split('/').last ?? 'none'}`',
    )
    ..writeln()
    ..write(representativeMarkdown);

  if (options.repeatCount > 1) {
    markdown.writeln(_renderRepeatStability(currentAggregates));
  }

  if (compareFile != null) {
    final comparison = _generateComparison(
      currentAggregates,
      compareFile.readAsStringSync(),
      compareFile.path.split('/').last,
    );
    markdown.writeln(comparison);
    print(comparison);
  } else {
    markdown.writeln('## Comparison');
    markdown.writeln();
    markdown.writeln('No comparison baseline found. Use `--compare-to=...` or keep a prior run in `benchmark/results`.');
    markdown.writeln();
  }

  final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
  final resultsFile = File('${resultsDir.path}/$timestamp-${options.label}.md');
  await resultsFile.writeAsString(markdown.toString());

  print('');
  print('Results saved to: ${resultsFile.path}');

  if (options.hardwareSummary) {
    _printHardwareSummary(currentAggregates, options.label);
  }

  // Force exit — persistent writer isolate and sqlite_async connections
  // can keep the event loop alive.
  exit(0);
}

void _printHardwareSummary(
  Map<String, _AggregateStats> metrics,
  String label,
) {
  // Use section-specific prefixes to avoid ambiguity
  // (e.g. 'resqlite select' would match both select() and selectBytes()).
  // The [main] suffix is at the end of the full key, so we need to match
  // both the section substring and the suffix independently.
  double? _median(String substring, {bool main = false}) {
    for (final key in metrics.keys) {
      if (!key.contains(substring)) continue;
      if (main && !key.endsWith('[main]')) continue;
      if (!main && key.endsWith('[main]')) continue;
      return metrics[key]!.median;
    }
    return null;
  }

  String _ms(String substring, {bool main = false}) =>
      _median(substring, main: main)?.toStringAsFixed(2) ?? '?';

  String _worker(String substring) {
    final wall = _median(substring);
    final mainVal = _median(substring, main: true);
    if (wall == null || mainVal == null) return '?';
    return (wall - mainVal).toStringAsFixed(2);
  }

  var pointDisplay = '?';
  for (final key in metrics.keys) {
    if (key.contains('resqlite qps')) {
      final qps = metrics[key]!.median.round();
      pointDisplay = '${(qps / 1000).round()}K';
      break;
    }
  }

  final date = DateTime.now().toIso8601String().split('T').first;

  print('');
  print('=== Hardware Summary ===');
  print('Copy these rows into the matching tables in');
  print('benchmark/HARDWARE_RESULTS.md and submit a PR.');
  print('');

  print('Devices:');
  print('| $label | [CPU] | [OS] | [Dart] | $date | @[github] |');
  print('');

  void _printTimingRows(
    String sectionName,
    List<String> substrings,
  ) {
    print('| $label | wall '
        '| ${substrings.map((s) => _ms(s)).join(' | ')} |');
    print('| $label | main '
        '| ${substrings.map((s) => _ms(s, main: true)).join(' | ')} |');
    print('| $label | worker '
        '| ${substrings.map(_worker).join(' | ')} |');
  }

  print('Select → Maps (ms):');
  _printTimingRows('Select → Maps', [
    'Maps / 10 rows',
    'Maps / 100 rows',
    'Maps / 1000 rows',
    'Maps / 10000 rows',
  ]);
  print('');

  print('Select → JSON Bytes (ms):');
  _printTimingRows('Select → JSON Bytes', [
    'Bytes / 10 rows',
    'Bytes / 100 rows',
    'Bytes / 1000 rows',
    'Bytes / 10000 rows',
  ]);
  print('');

  print('Point Query:');
  print('| $label | $pointDisplay |');
  print('');

  print('Batch Insert (ms):');
  _printTimingRows('Batch Insert', [
    'Batch Insert (100 rows)',
    'Batch Insert (1000 rows)',
    'Batch Insert (10000 rows)',
  ]);
  print('');

  print('Concurrent Reads (ms):');
  print('| $label '
      '| ${_ms("concurrent 1x")} '
      '| ${_ms("concurrent 2x")} '
      '| ${_ms("concurrent 4x")} '
      '| ${_ms("concurrent 8x")} |');
  print('');

  print('Transaction (ms):');
  print('| $label | ${_ms("Interactive Transaction")} |');
  print('');

  print('Stream Reactivity (ms):');
  print('| $label '
      '| ${_ms("Invalidation Latency")} '
      '| ${_ms("Fan-out (10 streams)")} |');
}

Future<String> _runSuiteOnce() async {
  final markdown = StringBuffer();

  print('[1/9] Select → Maps...');
  markdown.write(await runSelectMapsBenchmark());

  print('[2/9] Select → Bytes...');
  markdown.write(await runSelectBytesBenchmark());

  print('[3/9] Schema Shapes...');
  markdown.write(await runSchemaShapesBenchmark());

  print('[4/9] Scaling...');
  markdown.write(await runScalingBenchmark());

  print('[5/9] Concurrent Reads...');
  markdown.write(await runConcurrentReadsBenchmark());

  print('[6/9] Point Query...');
  markdown.write(await runPointQueryBenchmark());

  print('[7/9] Parameterized Queries...');
  markdown.write(await runParameterizedBenchmark());

  print('[8/9] Writes...');
  markdown.write(await runWritesBenchmark());

  print('[9/9] Streaming...');
  markdown.write(await runStreamingBenchmark());

  return markdown.toString();
}

final class _RunAllOptions {
  const _RunAllOptions({
    required this.label,
    required this.repeatCount,
    required this.compareToPath,
    required this.hardwareSummary,
  });

  final String label;
  final int repeatCount;
  final String? compareToPath;
  final bool hardwareSummary;
}

_RunAllOptions _parseOptions(List<String> args) {
  var label = 'unlabeled';
  var repeatCount = 1;
  String? compareToPath;
  var hardwareSummary = false;

  for (final arg in args) {
    if (arg.startsWith('--repeat=')) {
      repeatCount = int.parse(arg.substring('--repeat='.length));
    } else if (arg.startsWith('--compare-to=')) {
      compareToPath = arg.substring('--compare-to='.length);
    } else if (arg == '--hardware-summary') {
      hardwareSummary = true;
    } else if (arg == '--help' || arg == '-h') {
      _printUsageAndExit();
    } else if (!arg.startsWith('--')) {
      label = arg;
    } else {
      throw ArgumentError('Unknown argument: $arg');
    }
  }

  if (repeatCount < 1) {
    throw ArgumentError('--repeat must be >= 1');
  }

  return _RunAllOptions(
    label: label,
    repeatCount: repeatCount,
    compareToPath: compareToPath,
    hardwareSummary: hardwareSummary,
  );
}

void _printUsageAndExit() {
  print('Usage: dart run benchmark/run_all.dart [label] [--repeat=N] [--compare-to=PATH] [--hardware-summary]');
  print('');
  print('  --repeat=N           Run the suite N times (default: 1)');
  print('  --compare-to=PATH    Compare against a specific baseline results file');
  print('  --hardware-summary   Print a copy-pasteable row for HARDWARE_RESULTS.md');
  exit(0);
}

File? _resolveComparisonFile(Directory resultsDir, String? explicitPath) {
  if (explicitPath != null && explicitPath.isNotEmpty) {
    final file = File(explicitPath);
    if (!file.existsSync()) {
      throw ArgumentError('Comparison file not found: $explicitPath');
    }
    return file;
  }
  return _findPreviousResults(resultsDir);
}

/// Find the most recent .md file in the results directory.
File? _findPreviousResults(Directory dir) {
  if (!dir.existsSync()) return null;

  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.md') && !f.path.endsWith('.gitkeep'))
      .toList()
    ..sort((a, b) => b.path.compareTo(a.path)); // newest first

  return files.isNotEmpty ? files.first : null;
}

// extractResqliteMedians() is imported from shared/parse_results.dart.

Map<String, _AggregateStats> _aggregateRunMetrics(
  List<Map<String, double>> runMetrics,
) {
  final buckets = <String, List<double>>{};
  for (final run in runMetrics) {
    for (final entry in run.entries) {
      buckets.putIfAbsent(entry.key, () => <double>[]).add(entry.value);
    }
  }
  return {
    for (final entry in buckets.entries) entry.key: _AggregateStats(entry.value),
  };
}

final class _AggregateStats {
  static const double minimumComparisonThresholdPct = 10.0;
  static const double minimumComparisonThresholdMs = 0.02;

  _AggregateStats(List<double> values)
      : runs = List<double>.from(values)..sort();

  final List<double> runs;

  double get median => _median(runs);
  double get min => runs.first;
  double get max => runs.last;
  double get rangePct => median == 0 ? 0 : ((max - min) / median) * 100;
  double get madPct {
    if (runs.length == 1 || median == 0) return 0;
    final deviations = [
      for (final value in runs) (value - median).abs(),
    ]..sort();
    return (_median(deviations) / median) * 100;
  }

  String get stability {
    if (runs.length == 1) return 'single run';
    if (madPct <= 3) return 'stable';
    if (madPct <= 8) return 'moderate';
    return 'noisy';
  }

  double get comparisonThresholdPct =>
      math.max(minimumComparisonThresholdPct, madPct * 3.0);
}

double _median(List<double> sortedValues) {
  if (sortedValues.isEmpty) return 0;
  final mid = sortedValues.length ~/ 2;
  if (sortedValues.length.isOdd) return sortedValues[mid];
  return (sortedValues[mid - 1] + sortedValues[mid]) / 2;
}

String _renderRepeatStability(Map<String, _AggregateStats> aggregates) {
  final buf = StringBuffer();
  buf.writeln('## Repeat Stability');
  buf.writeln();
  buf.writeln('These rows summarize resqlite wall medians across repeated full-suite runs.');
  buf.writeln('Use this section to judge whether small deltas are real or just noise.');
  buf.writeln();
  buf.writeln('| Benchmark | Median (ms) | Min | Max | Range | MAD | Stability |');
  buf.writeln('|---|---|---|---|---|---|---|');

  final keys = aggregates.keys.toList()..sort();
  for (final key in keys) {
    final stats = aggregates[key]!;
    final shortKey = key.length > 70 ? '${key.substring(0, 67)}...' : key;
    buf.writeln(
      '| $shortKey '
      '| ${stats.median.toStringAsFixed(2)} '
      '| ${stats.min.toStringAsFixed(2)} '
      '| ${stats.max.toStringAsFixed(2)} '
      '| ${stats.rangePct.toStringAsFixed(1)}% '
      '| ${stats.madPct.toStringAsFixed(1)}% '
      '| ${stats.stability} |',
    );
  }
  buf.writeln();
  return buf.toString();
}

/// Generate a comparison summary between current and previous results.
String _generateComparison(
  Map<String, _AggregateStats> current,
  String previousContent,
  String previousFileName,
) {
  final previous = extractResqliteMedians(previousContent);

  if (current.isEmpty || previous.isEmpty) {
    return '## Comparison\n\nCould not parse results for comparison.\n';
  }

  final buf = StringBuffer();
  buf.writeln('## Comparison vs Previous Run');
  buf.writeln();
  buf.writeln('Previous: `$previousFileName`');
  buf.writeln();
  buf.writeln('| Benchmark | Previous (ms) | Current med (ms) | Delta | Noise threshold | Stability | Status |');
  buf.writeln('|---|---|---|---|---|---|---|');

  var wins = 0;
  var regressions = 0;
  var neutral = 0;

  final allKeys = current.keys
      .where(previous.containsKey)
      .toList()
    ..sort();

  for (final key in allKeys) {
    final prev = previous[key]!;
    final stats = current[key]!;
    final curr = stats.median;
    final delta = curr - prev;
    final pct = prev > 0 ? (delta / prev * 100) : 0.0;
    final thresholdPct = stats.comparisonThresholdPct;
    final thresholdMs = math.max(
      _AggregateStats.minimumComparisonThresholdMs,
      math.max(prev, curr) * (thresholdPct / 100),
    );

    // For most metrics lower is better (ms), but for throughput metrics
    // (qps) higher is better — invert the comparison.
    final higherIsBetter = key.contains('qps');
    final improvementDelta = higherIsBetter ? -delta : delta;

    String status;
    if (improvementDelta < -thresholdMs) {
      status = '🟢 Win (${pct.toStringAsFixed(0)}%)';
      wins++;
    } else if (improvementDelta > thresholdMs) {
      status = '🔴 Regression (${pct > 0 ? '+' : ''}${pct.toStringAsFixed(0)}%)';
      regressions++;
    } else {
      status = stats.runs.length > 1
          ? '⚪ Within noise'
          : '⚪ Neutral';
      neutral++;
    }

    final shortKey = key.length > 60 ? '${key.substring(0, 57)}...' : key;
    buf.writeln(
      '| $shortKey '
      '| ${prev.toStringAsFixed(2)} '
      '| ${curr.toStringAsFixed(2)} '
      '| ${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(2)} '
      '| ±${thresholdPct.toStringAsFixed(0)}% / ±${thresholdMs.toStringAsFixed(2)} ms '
      '| ${stats.stability} '
      '| $status |',
    );
  }

  buf.writeln();
  buf.writeln('**Summary:** $wins wins, $regressions regressions, $neutral neutral');
  buf.writeln();
  buf.writeln(
    'Comparison threshold uses `max(10%, 3 × current MAD%)`, '
    'plus an absolute floor of `±0.02 ms`.',
  );
  buf.writeln(
    'That keeps stable cases sensitive while treating noisy and ultra-fast cases '
    'more conservatively.',
  );
  buf.writeln();

  if (regressions > 0) {
    buf.writeln('⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.');
  } else if (wins > 0) {
    buf.writeln('✅ **No regressions beyond noise.** $wins benchmarks improved.');
  } else {
    buf.writeln('✅ **No changes beyond noise.**');
  }
  buf.writeln();

  return buf.toString();
}
