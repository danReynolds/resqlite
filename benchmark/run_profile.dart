// ignore_for_file: avoid_print
//
// Legacy profile JSON compatibility harness.
//
// The preferred experiment-profile entry point is now
// `benchmark/profile/run_tracelite_profile.dart`. That wrapper runs this
// harness to preserve the old JSON shape, then adds the tracelite region,
// workload summaries, insights, graph data, and parity diff that new
// experiments should use.
//
// This direct harness still runs resqlite ONLY under full diagnostic
// instrumentation:
//
//   TIME
//     - `ProfiledDatabase` wraps every call with per-op Stopwatch timing.
//     - Timeline markers inside the writer and reader isolates are compiled
//       in when run with `-DRESQLITE_PROFILE=true` — visible in DevTools.
//     - A `noop` baseline workload (SELECT 1 / UPDATE WHERE 1=0) is always
//       run first, and `work_us = total_us - noop_median_us` is computed
//       for every other workload. Lets you say "this experiment saved
//       X μs of work on top of Y μs of unavoidable dispatch."
//
//   MEMORY
//     - `ProcessInfo.currentRss` captured before and after each workload,
//       with heap-churn preamble for stability (same methodology as the
//       release-mode memory suite). `rss_delta_mb` tells you how much
//       process memory each workload retained.
//     - `Database.diagnostics()` captured before and after — exposes
//       SQLite-specific counters (page cache, schema, stmt cache, WAL
//       sidecar size). Per-SQLite counters are exact, unlike RSS which
//       is a lower bound.
//     - ProfileCounters snapshot decode counters per workload. Useful
//       for memory-axis work where RSS and SQLite diagnostics do not
//       explain Dart-side materialization cost.
//
// Purpose: compatibility with old A/B experiment notes and diff tools that
// need the historical `profile.json` shape. Both runs use the same profile
// build, so any diagnostic overhead cancels out in the delta.
//
// Usage:
//
//   # Preferred trace-backed workflow for new experiments:
//   dart run benchmark/profile/run_tracelite_profile.dart \
//     --tracelite-root=/path/to/tracelite \
//     --label=exp-N
//
//   # Direct legacy JSON workflow, when an old note/tool requires it:
//   dart run -DRESQLITE_PROFILE=true benchmark/run_profile.dart \
//     --out=benchmark/profile/results/baseline.json
//
//   # Experiment branch
//   dart run -DRESQLITE_PROFILE=true benchmark/run_profile.dart \
//     --out=benchmark/profile/results/exp-N.json
//
//   # Compare
//   dart run benchmark/profile/diff.dart \
//     benchmark/profile/results/baseline.json \
//     benchmark/profile/results/exp-N.json
//
// With --observe for DevTools cross-isolate timeline:
//   dart --observe --profile-period=100 \
//     -DRESQLITE_PROFILE=true benchmark/run_profile.dart
//
// See benchmark/EXPERIMENTS.md for the full migration workflow.

import 'dart:convert';
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/profile_counters.dart';
import 'package:resqlite/src/profile_mode.dart';
import 'package:resqlite/src/tracelite_profile.dart';

import 'profile/profile_reporting.dart';
import 'profile/profiled_database.dart';
import 'profile/workloads.dart';
import 'shared/benchmark_environment.dart';

// Memory stabilization churn size. Matches release-mode memory.dart.
const int _churnSize = 10000;

Future<void> main(List<String> args) async {
  final options = _parseOptions(args);
  final environment = await collectBenchmarkEnvironment(
    extra: {'benchmarkMode': 'profile', 'profileModeEnabled': kProfileMode},
  );

  print('resqlite Legacy Profile JSON Compatibility Harness');
  print('==================================================');
  print('');
  print('Primary workflow for new profile experiments:');
  print('  dart run benchmark/profile/run_tracelite_profile.dart \\');
  print('    --tracelite-root=/path/to/tracelite --label=exp-N');
  print('');
  print(
    'This direct command is retained for old JSON A/B diffs and parity checks.',
  );
  print('');
  if (!kProfileMode) {
    print('⚠  kProfileMode=false (Timeline markers tree-shaken out).');
    print('   ProfiledDatabase per-call timing + memory capture still');
    print('   work, but you will not see writer.handle.* / reader.handle.*');
    print('   spans in DevTools. Rerun with -DRESQLITE_PROFILE=true.');
    print('');
  } else {
    print('kProfileMode=true — Timeline markers active.');
    print('');
  }

  final tempDir = await Directory.systemTemp.createTemp('run_profile_');
  final db = await Database.open('${tempDir.path}/test.db');
  final profiled = ProfiledDatabase(db);

  try {
    await setupSchema(profiled);
    await warmup(profiled);

    // Noop first — gives us the dispatch floor. Every subsequent
    // workload's `work_us_median` is computed relative to this.
    print('=== Workload Z: Noop Baseline (SELECT 1 / UPDATE WHERE 1=0) ===');
    final noop = await _runWorkload(
      name: 'noop',
      profiled: profiled,
      body: (iter) => workloadNoop(profiled, iter),
    );
    final noopSummary = summarizeSamples(noop.samples);
    final readerFloor = (noopSummary['select'] as Map)['median_us'] as int;
    final writerFloor = (noopSummary['execute'] as Map)['median_us'] as int;
    _reportWorkload(noop, readerFloor: null, writerFloor: null);
    print('  reader dispatch floor ≈ $readerFloor μs');
    print('  writer dispatch floor ≈ $writerFloor μs');

    print('');
    print('=== Workload A: Single Inserts ===');
    final singleInsert = await _runWorkload(
      name: 'single_insert',
      profiled: profiled,
      body: (iter) => workloadSingleInserts(profiled, iter),
    );
    _reportWorkload(
      singleInsert,
      readerFloor: readerFloor,
      writerFloor: writerFloor,
    );

    print('');
    print('=== Workload B: Point Queries ===');
    final pointQuery = await _runWorkload(
      name: 'point_query',
      profiled: profiled,
      body: (iter) => workloadPointQuery(profiled, iter),
    );
    _reportWorkload(
      pointQuery,
      readerFloor: readerFloor,
      writerFloor: writerFloor,
    );

    print('');
    print('=== Workload C: Merge Rounds ===');
    final mergeRounds = await _runWorkload(
      name: 'merge_rounds',
      profiled: profiled,
      body: (iter) => workloadMergeRounds(profiled, iter),
    );
    _reportWorkload(
      mergeRounds,
      readerFloor: readerFloor,
      writerFloor: writerFloor,
    );

    // Persist the whole thing. diff.dart reads these JSON files.
    final outPath = options.outPath ?? _defaultOutPath();
    final outDir = File(outPath).parent;
    if (!outDir.existsSync()) outDir.createSync(recursive: true);

    await File(outPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'generated_at': DateTime.now().toIso8601String(),
        'environment': environment,
        'profile_mode_enabled': kProfileMode,
        'iterations': measureIterations,
        'noop_floors': {'reader_us': readerFloor, 'writer_us': writerFloor},
        'workloads': {
          'noop': profileWorkloadArtifact(
            noop,
            readerFloor: null,
            writerFloor: null,
          ),
          'single_insert': profileWorkloadArtifact(
            singleInsert,
            readerFloor: readerFloor,
            writerFloor: writerFloor,
          ),
          'point_query': profileWorkloadArtifact(
            pointQuery,
            readerFloor: readerFloor,
            writerFloor: writerFloor,
          ),
          'merge_rounds': profileWorkloadArtifact(
            mergeRounds,
            readerFloor: readerFloor,
            writerFloor: writerFloor,
          ),
        },
      }),
    );

    print('');
    print('Results written to: $outPath');
    print('');
    print('To compare against another run:');
    print('  dart run benchmark/profile/diff.dart <baseline.json> $outPath');
    if (kProfileMode) {
      print('');
      print('For DevTools cross-isolate timeline, rerun under:');
      print('  dart --observe --profile-period=100 \\');
      print('    -DRESQLITE_PROFILE=true benchmark/run_profile.dart');
    }
    print('');
    print('For tracelite workload summaries, insights, graph data, and parity');
    print(
      'evidence, use benchmark/profile/run_tracelite_profile.dart instead.',
    );
  } finally {
    await profiled.close();
    await tempDir.delete(recursive: true);
  }
}

// ---------------------------------------------------------------------------
// Workload execution — captures time + memory together
// ---------------------------------------------------------------------------

/// Runs a workload with memory stabilization before measurement, then
/// takes RSS and Diagnostics snapshots around the measured iterations.
///
/// Memory methodology mirrors release-mode `memory.dart`:
///   1. Heap-churn to stabilize baseline (drop 10k small Maps).
///   2. Take RSS + Diagnostics + counter snapshot (baseline).
///   3. Run [measureIterations] iterations of [body].
///   4. Take RSS + Diagnostics + counter snapshot (post).
Future<ProfileWorkloadResult> _runWorkload({
  required String name,
  required ProfiledDatabase profiled,
  required Future<void> Function(int iter) body,
  int iterations = measureIterations,
}) async {
  // Stabilize the heap before baseline capture so leftover allocations
  // from prior workloads don't inflate this workload's rss_delta. Two
  // churn passes — the first may miss pages that only surface after a
  // minor GC; the second pass runs with a stabler baseline.
  _churnHeap();
  _churnHeap();

  final rssBeforeBytes = _rssBytes();
  final rssBefore = _rssMB(rssBeforeBytes);
  final diagBefore = await profiled.raw.diagnostics();
  final countersBefore = kProfileMode ? ProfileCounters.snapshot() : null;
  final traceCorrelationId =
      TraceliteProfile.isEnabled ? TraceliteProfile.nextCorrelationId() : null;
  final traceNameId =
      traceCorrelationId == null ? null : TraceliteProfile.internString(name);
  if (traceCorrelationId != null) {
    TraceliteProfile.diagnostics(diagBefore, correlationId: traceCorrelationId);
    if (countersBefore != null) {
      TraceliteProfile.profileCounters(
        countersBefore,
        correlationId: traceCorrelationId,
      );
    }
  }
  var peakRssBytes = rssBeforeBytes;

  profiled.samples.clear();
  Future<void> runMeasuredLoop() async {
    for (var iter = 0; iter < iterations; iter++) {
      await body(iter);
      final rssNow = _rssBytes();
      if (rssNow > peakRssBytes) peakRssBytes = rssNow;
    }
  }

  if (traceCorrelationId == null) {
    await runMeasuredLoop();
  } else {
    await TraceliteProfile.traceAsync(
      TraceliteResqliteSpans.profileWorkload,
      runMeasuredLoop,
      correlationId: traceCorrelationId,
      beginArgs: [traceNameId!, iterations],
      endArgs: (_) => [profiled.samples.length],
    );
  }

  final rssAfterBytes = _rssBytes();
  final rssAfter = _rssMB(rssAfterBytes);
  final diagAfter = await profiled.raw.diagnostics();
  final countersAfter = kProfileMode ? ProfileCounters.snapshot() : null;
  if (traceCorrelationId != null) {
    TraceliteProfile.diagnostics(diagAfter, correlationId: traceCorrelationId);
    if (countersAfter != null) {
      TraceliteProfile.profileCounters(
        countersAfter,
        correlationId: traceCorrelationId,
      );
    }
    TraceliteProfile.rss(
      beforeBytes: rssBeforeBytes,
      afterBytes: rssAfterBytes,
      peakBytes: peakRssBytes,
      correlationId: traceCorrelationId,
    );
  }

  return ProfileWorkloadResult(
    name: name,
    iterations: iterations,
    samples: List.of(profiled.samples),
    rssBeforeMB: rssBefore,
    rssAfterMB: rssAfter,
    rssPeakMB: _rssMB(peakRssBytes),
    diagnosticsBefore: diagBefore,
    diagnosticsAfter: diagAfter,
    countersBefore: countersBefore,
    countersAfter: countersAfter,
  );
}

int _rssBytes() => ProcessInfo.currentRss;

double _rssMB(int bytes) => bytes / (1024 * 1024);

/// Pre-measurement churn loop. Allocates + drops small maps to stabilize
/// the heap before baseline capture. Without this, heap pages retained
/// by the prior workload grow the RSS baseline and contaminate the
/// delta.
void _churnHeap() {
  final junk = <Map<String, Object?>>[];
  for (var i = 0; i < _churnSize; i++) {
    junk.add({'a': i, 'b': 'x$i', 'c': i * 1.5});
  }
  junk.clear();
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

class _Options {
  _Options({this.outPath});
  final String? outPath;
}

_Options _parseOptions(List<String> args) {
  String? outPath;
  for (final arg in args) {
    if (arg.startsWith('--out=')) {
      outPath = arg.substring('--out='.length);
    } else if (arg == '--help' || arg == '-h') {
      print(
        'Usage: dart run -DRESQLITE_PROFILE=true '
        'benchmark/run_profile.dart [--out=PATH]',
      );
      print('');
      print('Legacy compatibility harness for old profile JSON A/B diffs.');
      print('Prefer the trace-backed wrapper for new profile experiments:');
      print('  dart run benchmark/profile/run_tracelite_profile.dart \\');
      print('    --tracelite-root=/path/to/tracelite --label=exp-N');
      print('');
      print('  --out=PATH   Write legacy profile JSON to PATH. Defaults to');
      print(
        '               benchmark/profile/results/run_profile_TIMESTAMP.json',
      );
      print('');
      print('See benchmark/EXPERIMENTS.md for the migration workflow.');
      exit(0);
    } else {
      stderr.writeln('Unknown argument: $arg');
      exit(2);
    }
  }
  return _Options(outPath: outPath);
}

String _defaultOutPath() {
  final ts =
      DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
  return 'benchmark/profile/results/run_profile_$ts.json';
}

// ---------------------------------------------------------------------------
// Reporting + JSON emission
// ---------------------------------------------------------------------------

/// Render Diagnostics to a JSON-friendly map.
void _reportWorkload(
  ProfileWorkloadResult r, {
  required int? readerFloor,
  required int? writerFloor,
}) {
  print(
    formatProfileWorkloadReport(
      r,
      readerFloor: readerFloor,
      writerFloor: writerFloor,
    ),
  );
}
