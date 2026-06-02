// ignore_for_file: avoid_print
//
// Legacy profile JSON multi-run A/B aggregator.
//
// New profile experiments should use `benchmark/profile/run_tracelite_profile.dart`.
// That wrapper writes tracelite artifacts plus the legacy JSON shape this tool
// still aggregates. Single-run p99/max numbers from the legacy JSON can be
// noisy — one GC pause or scheduler quirk can swing them 20 % or more. This
// tool takes N baseline runs and N candidate runs, computes the MEDIAN of each
// percentile across runs on each side, and prints candidate-median minus
// baseline-median. That answers "are the tail wins robust?" rather than "did we
// win this particular run?".
//
// Methodology note: we deliberately take `median(p99 across runs)` rather
// than `p99(all samples pooled)` or `mean(p99 across runs)`. The median
// across runs ignores run-to-run outliers that are themselves noise,
// which is exactly what we want when interpreting "is this change real?"
// instead of "what is the absolute tail?".
//
// It also reports the coefficient of variation (stddev / mean) of each
// percentile across the baseline runs, to make it obvious when a metric
// is too noisy for the median to be meaningful.
//
// Usage:
//   dart run benchmark/profile/diff_multirun.dart \
//     --baseline='benchmark/profile/results/baseline-exp088-run*.json' \
//     --candidate='benchmark/profile/results/exp-088-run*.json'
//
// Or explicitly:
//   dart run benchmark/profile/diff_multirun.dart \
//     --baseline=a1.json,a2.json,a3.json \
//     --candidate=b1.json,b2.json,b3.json
//
// Exit code 0 regardless of outcome — this is a reporting tool.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

Future<void> main(List<String> args) async {
  String? baselineArg;
  String? candidateArg;
  for (final a in args) {
    if (a.startsWith('--baseline=')) {
      baselineArg = a.substring('--baseline='.length);
    } else if (a.startsWith('--candidate=')) {
      candidateArg = a.substring('--candidate='.length);
    } else if (a == '--help' || a == '-h') {
      _printUsage();
      exit(0);
    }
  }

  if (baselineArg == null || candidateArg == null) {
    _printUsage();
    exit(2);
  }

  final baselineFiles = _resolveFiles(baselineArg);
  final candidateFiles = _resolveFiles(candidateArg);

  if (baselineFiles.isEmpty || candidateFiles.isEmpty) {
    stderr.writeln('No baseline or candidate files matched.');
    exit(1);
  }

  print('Baseline runs (${baselineFiles.length}):');
  for (final f in baselineFiles) {
    print('  $f');
  }
  print('Candidate runs (${candidateFiles.length}):');
  for (final f in candidateFiles) {
    print('  $f');
  }
  print('');

  final baselineRuns = baselineFiles.map(_loadJson).toList();
  final candidateRuns = candidateFiles.map(_loadJson).toList();

  // Collect the union of workloads and operations seen across all runs.
  final workloadOps = <String, Set<String>>{};
  for (final run in [...baselineRuns, ...candidateRuns]) {
    final workloads = run['workloads'] as Map<String, dynamic>? ?? {};
    workloads.forEach((wl, info) {
      final sum = (info as Map<String, dynamic>)['summary']
          as Map<String, dynamic>?;
      if (sum == null) return;
      workloadOps.putIfAbsent(wl, () => <String>{}).addAll(sum.keys);
    });
  }
  final sortedWorkloads = workloadOps.keys.toList()..sort();

  const metricKeys = <(String, String)>[
    ('median_us', 'p50'),
    ('p90_us', 'p90'),
    ('p99_us', 'p99'),
    ('max_us', 'max'),
    ('work_us_median', 'work'),
  ];

  print('# Multi-run medians of percentiles');
  print('');
  print('Each cell: median across ${baselineFiles.length} runs on the '
      'baseline side, median across ${candidateFiles.length} runs on the '
      'candidate side.');
  print('CV (coefficient of variation) = stddev/mean of the per-run values '
      'on the baseline side — gives a sense of how noisy the metric itself '
      'is on this bench.');
  print('');

  for (final wl in sortedWorkloads) {
    final ops = workloadOps[wl]!.toList()..sort();
    for (final op in ops) {
      print('## $wl · $op');
      print('');
      print('| metric | baseline median | candidate median | Δ | Δ% | baseline CV |');
      print('|---|---:|---:|---:|---:|---:|');
      for (final (key, label) in metricKeys) {
        final bValues = _collectPerRun(baselineRuns, wl, op, key);
        final cValues = _collectPerRun(candidateRuns, wl, op, key);
        if (bValues.isEmpty || cValues.isEmpty) continue;
        final bMed = _median(bValues);
        final cMed = _median(cValues);
        final delta = cMed - bMed;
        final pct = bMed == 0 ? 0.0 : (delta / bMed * 100);
        final cv = _coefficientOfVariation(bValues);
        print('| $label '
            '| ${bMed.toStringAsFixed(1)} μs '
            '| ${cMed.toStringAsFixed(1)} μs '
            '| ${_signedFixed(delta)} μs '
            '| ${_signedPct(pct)} '
            '| ${(cv * 100).toStringAsFixed(1)}% |');
      }
      print('');

      // Show the raw per-run values so the reader can sanity-check the
      // median. Especially useful for max/p99 where one bad run will
      // visibly dominate the mean but not the median.
      print('Per-run values (baseline / candidate):');
      print('');
      print('| metric | baseline runs | candidate runs |');
      print('|---|---|---|');
      for (final (key, label) in metricKeys) {
        final bValues = _collectPerRun(baselineRuns, wl, op, key);
        final cValues = _collectPerRun(candidateRuns, wl, op, key);
        if (bValues.isEmpty || cValues.isEmpty) continue;
        String fmt(List<double> xs) =>
            xs.map((v) => v.toStringAsFixed(0)).join(', ');
        print('| $label | ${fmt(bValues)} | ${fmt(cValues)} |');
      }
      print('');
    }
  }

  // noop_floors (dispatch baseline) — not per-workload; just show medians.
  print('## noop_floors (dispatch baseline)');
  print('');
  print('| metric | baseline median | candidate median | Δ |');
  print('|---|---:|---:|---:|');
  final floorKeys = <String>{};
  for (final run in [...baselineRuns, ...candidateRuns]) {
    final floors = run['noop_floors'] as Map<String, dynamic>?;
    if (floors != null) floorKeys.addAll(floors.keys);
  }
  for (final key in floorKeys.toList()..sort()) {
    final bValues = baselineRuns
        .map((r) => (r['noop_floors'] as Map<String, dynamic>?)?[key])
        .whereType<num>()
        .map((n) => n.toDouble())
        .toList();
    final cValues = candidateRuns
        .map((r) => (r['noop_floors'] as Map<String, dynamic>?)?[key])
        .whereType<num>()
        .map((n) => n.toDouble())
        .toList();
    if (bValues.isEmpty || cValues.isEmpty) continue;
    final bMed = _median(bValues);
    final cMed = _median(cValues);
    final delta = cMed - bMed;
    print('| $key '
        '| ${bMed.toStringAsFixed(1)} μs '
        '| ${cMed.toStringAsFixed(1)} μs '
        '| ${_signedFixed(delta)} μs |');
  }
}

List<double> _collectPerRun(
  List<Map<String, dynamic>> runs,
  String wl,
  String op,
  String key,
) {
  final out = <double>[];
  for (final run in runs) {
    final workloads = run['workloads'] as Map<String, dynamic>? ?? {};
    final info = workloads[wl] as Map<String, dynamic>?;
    final summary = info?['summary'] as Map<String, dynamic>?;
    final opMap = summary?[op] as Map<String, dynamic>?;
    final v = opMap?[key];
    if (v is num) out.add(v.toDouble());
  }
  return out;
}

double _median(List<double> xs) {
  if (xs.isEmpty) return double.nan;
  final sorted = [...xs]..sort();
  final n = sorted.length;
  if (n.isOdd) return sorted[n ~/ 2];
  return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

double _coefficientOfVariation(List<double> xs) {
  if (xs.length < 2) return 0.0;
  final mean = xs.reduce((a, b) => a + b) / xs.length;
  if (mean == 0) return 0.0;
  final variance =
      xs.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
          xs.length;
  final stddev = sqrt(variance);
  return stddev / mean;
}

List<String> _resolveFiles(String spec) {
  // Support comma-separated explicit paths OR a single glob. We use a
  // tiny glob that only expands `*` to any run of non-slash characters.
  if (spec.contains(',')) {
    return spec.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }
  if (!spec.contains('*')) return [spec];

  final slashIdx = spec.lastIndexOf('/');
  final dirPath = slashIdx >= 0 ? spec.substring(0, slashIdx) : '.';
  final pattern = slashIdx >= 0 ? spec.substring(slashIdx + 1) : spec;
  final regex = RegExp('^${RegExp.escape(pattern).replaceAll(r'\*', '[^/]*')}\$');

  final dir = Directory(dirPath);
  if (!dir.existsSync()) return const [];
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => regex.hasMatch(f.path.split('/').last))
      .map((f) => f.path)
      .toList()
    ..sort();
  return files;
}

Map<String, dynamic> _loadJson(String path) {
  final f = File(path);
  if (!f.existsSync()) {
    stderr.writeln('File not found: $path');
    exit(1);
  }
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

String _signedFixed(double v) {
  final s = v.toStringAsFixed(1);
  return v >= 0 ? '+$s' : s;
}

String _signedPct(double pct) {
  final s = pct.toStringAsFixed(1);
  return pct >= 0 ? '+$s%' : '$s%';
}

void _printUsage() {
  print('Usage: dart run benchmark/profile/diff_multirun.dart \\');
  print('  --baseline=<glob-or-comma-list> \\');
  print('  --candidate=<glob-or-comma-list>');
  print('');
  print('Example:');
  print('  dart run benchmark/profile/diff_multirun.dart \\');
  print("    --baseline='benchmark/profile/results/baseline-exp088-run*.json' \\");
  print("    --candidate='benchmark/profile/results/exp-088-run*.json'");
}
