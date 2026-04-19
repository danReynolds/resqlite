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
// Per workload, prints four blocks when the data is present:
//
//   TIME        p50 / p90 / p99 / max / work (μs median)
//   MEMORY      RSS delta (MB) — end-of-workload process RSS
//   SQLITE      page cache, schema, stmt, WAL bytes — per-connection counters
//   ALLOC       rows / cells — decoder counters from
//               `lib/src/profile_counters.dart`. Only emitted when the
//               harness compiled with -DRESQLITE_PROFILE=true.
//
// Missing blocks are simply skipped (graceful fallback for older JSONs
// from dispatch_budget.dart that don't carry memory fields).
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
    print('or benchmark/profile/dispatch_budget.dart. Newer run_profile.dart');
    print('JSONs also carry RSS + SQLite memory deltas; those sections are');
    print('skipped gracefully when absent.');
    exit(args.contains('--help') || args.contains('-h') ? 0 : 2);
  }

  final baseline = await _loadJson(args[0]);
  final candidate = await _loadJson(args[1]);

  print('Baseline:  ${args[0]}');
  print('Candidate: ${args[1]}');
  print('');

  final workloadsA = baseline['workloads'] as Map<String, dynamic>? ?? {};
  final workloadsB = candidate['workloads'] as Map<String, dynamic>? ?? {};

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
  print('## $workload');
  _printTimeDiff(baseline, candidate);
  _printMemoryDiff(baseline, candidate);
}

// ---------------------------------------------------------------------------
// TIME block
// ---------------------------------------------------------------------------

void _printTimeDiff(
  Map<String, dynamic> baseline,
  Map<String, dynamic> candidate,
) {
  final sumA = baseline['summary'] as Map<String, dynamic>? ?? {};
  final sumB = candidate['summary'] as Map<String, dynamic>? ?? {};
  if (sumA.isEmpty || sumB.isEmpty) return;

  final ops = {...sumA.keys, ...sumB.keys}.toList()..sort();
  for (final op in ops) {
    final a = sumA[op] as Map<String, dynamic>?;
    final b = sumB[op] as Map<String, dynamic>?;
    if (a == null || b == null) {
      print('  $op: one side missing');
      continue;
    }
    print('  TIME $op:');
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

// ---------------------------------------------------------------------------
// MEMORY block (RSS + SQLite counters). Gracefully absent on older JSONs.
// ---------------------------------------------------------------------------

void _printMemoryDiff(
  Map<String, dynamic> baseline,
  Map<String, dynamic> candidate,
) {
  final memA = baseline['memory'] as Map<String, dynamic>?;
  final memB = candidate['memory'] as Map<String, dynamic>?;
  if (memA == null || memB == null) return;

  // Process RSS delta — lower bound on allocation volume. Exp 055-style
  // columnar-type experiments show large improvements in this column
  // that are invisible to time-based benchmarks.
  final rssA = (memA['rss_delta_mb'] as num?)?.toDouble();
  final rssB = (memB['rss_delta_mb'] as num?)?.toDouble();
  if (rssA != null && rssB != null) {
    print('  MEMORY (process RSS):');
    final d = rssB - rssA;
    final pct = rssA == 0 ? 0.0 : (d / rssA * 100);
    print('    rss Δ '
        '${rssA.toStringAsFixed(2).padLeft(6)} MB → '
        '${rssB.toStringAsFixed(2).padLeft(6)} MB  '
        '${_signedMB(d).padLeft(8)}  '
        '(${_signedPct(pct)})');
  }

  // SQLite per-connection counters — exact, unlike RSS. Useful for
  // distinguishing "our schema cache grew" from "Dart heap grew."
  final diagDeltaA = memA['diagnostics_delta'] as Map<String, dynamic>?;
  final diagDeltaB = memB['diagnostics_delta'] as Map<String, dynamic>?;
  if (diagDeltaA != null && diagDeltaB != null) {
    print('  SQLITE (per-connection counters, per-workload delta):');
    const counters = [
      ('sqlite_page_cache_bytes_delta', 'page cache'),
      ('sqlite_schema_bytes_delta', 'schema'),
      ('sqlite_stmt_bytes_delta', 'stmt'),
      ('wal_bytes_delta', 'wal'),
    ];
    for (final (key, label) in counters) {
      final av = (diagDeltaA[key] as num?)?.toInt();
      final bv = (diagDeltaB[key] as num?)?.toInt();
      if (av == null || bv == null) continue;
      final d = bv - av;
      final pct = av == 0 ? 0.0 : (d / av * 100);
      print('    ${label.padRight(10)} '
          '${_formatBytes(av).padLeft(10)} → '
          '${_formatBytes(bv).padLeft(10)}  '
          '${_signed(d).padLeft(10)} B  '
          '(${_signedPct(pct)})');
    }
  }

  // Decoder allocation counters — only present when profile-mode build
  // was used. Useful for memory experiments: a change that decodes the
  // same workload with fewer rows/cells indicates an allocation win.
  final allocA = memA['allocation_delta'] as Map<String, dynamic>?;
  final allocB = memB['allocation_delta'] as Map<String, dynamic>?;
  if (allocA != null && allocB != null) {
    print('  ALLOC (decoder counters, per-workload delta):');
    const counters = [
      ('rows_decoded', 'rows'),
      ('cells_decoded', 'cells'),
    ];
    for (final (key, label) in counters) {
      final av = (allocA[key] as num?)?.toInt();
      final bv = (allocB[key] as num?)?.toInt();
      if (av == null || bv == null) continue;
      final d = bv - av;
      final pct = av == 0 ? 0.0 : (d / av * 100);
      print('    ${label.padRight(14)} '
          '${av.toString().padLeft(10)} → '
          '${bv.toString().padLeft(10)}  '
          '${_signed(d).padLeft(12)}  '
          '(${_signedPct(pct)})');
    }
  }
}

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

String _signed(int n) => n >= 0 ? '+$n' : '$n';

String _signedPct(double pct) {
  final rounded = pct.toStringAsFixed(1);
  return pct >= 0 ? '+$rounded%' : '$rounded%';
}

String _signedMB(double mb) {
  final rounded = mb.toStringAsFixed(2);
  return mb >= 0 ? '+$rounded MB' : '$rounded MB';
}

String _formatBytes(int bytes) {
  final abs = bytes.abs();
  if (abs < 1024) return '${bytes} B';
  if (abs < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}
