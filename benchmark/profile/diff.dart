// ignore_for_file: avoid_print
//
// A/B diff tool for profile-mode benchmark runs.
//
// Reads two JSON files produced by `benchmark/run_profile.dart` (or
// `dispatch_budget.dart`) and prints a side-by-side delta table.
//
// Usage:
//   dart run benchmark/profile/diff.dart <baseline.json> <candidate.json>
//
// Output: one table per workload, with columns:
//   p50 / p90 / p99 / max / work (μs median)
//   baseline / candidate / Δμs / Δ%
//
// Exit code is 0 regardless of outcome — this is a reporting tool,
// not a pass/fail gate. The experimenter interprets the deltas against
// their hypothesis.

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length != 2 || args.contains('--help') || args.contains('-h')) {
    print('Usage: dart run benchmark/profile/diff.dart '
        '<baseline.json> <candidate.json>');
    print('');
    print('Both files should be produced by benchmark/run_profile.dart');
    print('or benchmark/profile/dispatch_budget.dart.');
    exit(args.contains('--help') || args.contains('-h') ? 0 : 2);
  }

  final baseline = await _loadJson(args[0]);
  final candidate = await _loadJson(args[1]);

  print('Baseline:  ${args[0]}');
  print('Candidate: ${args[1]}');
  print('');

  final workloadsA = baseline['workloads'] as Map<String, dynamic>? ?? {};
  final workloadsB = candidate['workloads'] as Map<String, dynamic>? ?? {};

  // Union of workload keys so we don't silently drop a workload that
  // only one side ran.
  final allWorkloads = {...workloadsA.keys, ...workloadsB.keys}.toList()..sort();

  var anyDiff = false;
  for (final wl in allWorkloads) {
    final a = workloadsA[wl] as Map<String, dynamic>?;
    final b = workloadsB[wl] as Map<String, dynamic>?;
    if (a == null) {
      print('## $wl  (baseline has no data)');
      continue;
    }
    if (b == null) {
      print('## $wl  (candidate has no data)');
      continue;
    }
    anyDiff = true;
    _printWorkloadDiff(wl, a, b);
    print('');
  }

  if (!anyDiff) {
    print('(no overlapping workloads between baseline and candidate)');
  }

  // Floor deltas — useful to know whether the dispatch baseline itself
  // shifted between runs (Dart VM version, OS state, etc.)
  final floorsA = baseline['noop_floors'] as Map<String, dynamic>?;
  final floorsB = candidate['noop_floors'] as Map<String, dynamic>?;
  if (floorsA != null && floorsB != null) {
    print('## noop_floors (dispatch baseline)');
    for (final key in {...floorsA.keys, ...floorsB.keys}) {
      final av = (floorsA[key] as num?)?.toInt();
      final bv = (floorsB[key] as num?)?.toInt();
      if (av == null || bv == null) continue;
      final d = bv - av;
      final pct = av == 0 ? 0.0 : (d / av * 100);
      print('  ${key.padRight(18)}  $av → $bv  '
          '(${_signed(d)}μs, ${_signedPct(pct)})');
    }
  }
}

Future<Map<String, dynamic>> _loadJson(String path) async {
  final f = File(path);
  if (!f.existsSync()) {
    stderr.writeln('File not found: $path');
    exit(1);
  }
  final raw = await f.readAsString();
  return jsonDecode(raw) as Map<String, dynamic>;
}

void _printWorkloadDiff(
  String workload,
  Map<String, dynamic> baseline,
  Map<String, dynamic> candidate,
) {
  final sumA = baseline['summary'] as Map<String, dynamic>? ?? {};
  final sumB = candidate['summary'] as Map<String, dynamic>? ?? {};

  print('## $workload');
  final ops = {...sumA.keys, ...sumB.keys}.toList()..sort();

  for (final op in ops) {
    final a = sumA[op] as Map<String, dynamic>?;
    final b = sumB[op] as Map<String, dynamic>?;
    if (a == null || b == null) {
      print('  $op: one side missing');
      continue;
    }
    print('  $op:');
    const metrics = [
      ('median_us', 'p50'),
      ('p90_us', 'p90'),
      ('p99_us', 'p99'),
      ('max_us', 'max'),
      ('work_us_median', 'work'),
    ];
    for (final (key, label) in metrics) {
      final av = (a[key] as num?)?.toInt();
      final bv = (b[key] as num?)?.toInt();
      if (av == null || bv == null) continue;
      final d = bv - av;
      final pct = av == 0 ? 0.0 : (d / av * 100);
      print('    ${label.padRight(5)} '
          '${av.toString().padLeft(6)}μs → '
          '${bv.toString().padLeft(6)}μs  '
          '${_signed(d).padLeft(6)}μs  '
          '(${_signedPct(pct)})');
    }
  }
}

String _signed(int n) => n >= 0 ? '+$n' : '$n';

String _signedPct(double pct) {
  final rounded = pct.toStringAsFixed(1);
  return pct >= 0 ? '+$rounded%' : '$rounded%';
}
