// ignore_for_file: avoid_print
/// Phase 1 harness for experiment 080 — dispatch-budget research pass.
///
/// Runs the three workloads where resqlite currently trails sqlite3 on
/// the public dashboard (single insert, point query, merge rounds)
/// under a [ProfiledDatabase] wrapper that records per-call wall time.
/// Pairs with `Timeline.startSync` markers inside the writer and reader
/// isolates (gated by `kProfileMode`) — run with `dart --observe` and
/// `-DRESQLITE_PROFILE=true` to get the cross-isolate breakdown in
/// DevTools.
///
/// Output: writes `benchmark/profile/results/dispatch_budget_TIMESTAMP.json`
/// with per-call samples + aggregate percentile summary. Diff two such
/// JSONs with `benchmark/profile/diff.dart` to reproduce the findings
/// in `experiments/080-dispatch-budget.md`. For memory-axis experiments
/// use `benchmark/run_profile.dart` instead — it's the superset of
/// this harness and includes RSS + SQLite + allocation diagnostics.
///
/// Usage:
///   dart run benchmark/profile/dispatch_budget.dart
///
/// With profiler:
///   dart --observe --profile-period=100 \
///     -DRESQLITE_PROFILE=true benchmark/profile/dispatch_budget.dart
///
/// Then open the service URL (printed by --observe) in DevTools →
/// Performance tab → record during the workload.
library;

import 'dart:convert';
import 'dart:io';

import 'package:resqlite/resqlite.dart';

import 'profile_sample.dart';
import 'profiled_database.dart';
import 'workloads.dart';

Future<void> main() async {
  final tempDir = await Directory.systemTemp.createTemp('exp080_');
  final db = await Database.open('${tempDir.path}/test.db');
  final profiled = ProfiledDatabase(db);

  try {
    await setupSchema(profiled);
    await warmup(profiled);

    // --- Workload Z: noop baseline — measures pure round-trip floor ---
    // `SELECT 1` does no table I/O and returns one row. Whatever time
    // this takes is ~100% dispatch overhead (main → writer/reader →
    // main). Any real workload's time minus this baseline = actual SQL
    // + Dart-side materialization work.
    print('');
    print('=== Workload Z: Noop Baseline (SELECT 1) ===');
    profiled.samples.clear();
    for (var iter = 0; iter < measureIterations; iter++) {
      await workloadNoop(profiled, iter);
    }
    final zSamples = List.of(profiled.samples);
    _reportWorkload('noop', zSamples);
    final zSummary = summarizeSamples(zSamples);
    final readerFloor = (zSummary['select'] as Map)['median_us'] as int;
    final writerFloor = (zSummary['execute'] as Map)['median_us'] as int;
    print('  → reader dispatch floor ≈ $readerFloor μs / round-trip');
    print('  → writer dispatch floor ≈ $writerFloor μs / round-trip');

    print('');
    print('=== Workload A: Single Inserts (100 sequential) ===');
    profiled.samples.clear();
    for (var iter = 0; iter < measureIterations; iter++) {
      await workloadSingleInserts(profiled, iter);
    }
    final aSamples = List.of(profiled.samples);
    _reportWorkload('single_insert', aSamples);

    print('');
    print('=== Workload B: Point Queries (500 hot-loop) ===');
    profiled.samples.clear();
    for (var iter = 0; iter < measureIterations; iter++) {
      await workloadPointQuery(profiled, iter);
    }
    final bSamples = List.of(profiled.samples);
    _reportWorkload('point_query', bSamples);

    print('');
    print('=== Workload C: Merge Rounds (10 × 100 rows) ===');
    profiled.samples.clear();
    for (var iter = 0; iter < measureIterations; iter++) {
      await workloadMergeRounds(profiled, iter);
    }
    final cSamples = List.of(profiled.samples);
    _reportWorkload('merge_rounds', cSamples);

    // Persist the full sample set for downstream analysis. diff.dart
    // reads these JSON files for pairwise experiment deltas.
    final outDir = Directory('benchmark/profile/results');
    if (!outDir.existsSync()) await outDir.create(recursive: true);
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final outPath = '${outDir.path}/dispatch_budget_$timestamp.json';
    await File(outPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'generated_at': DateTime.now().toIso8601String(),
        'iterations': measureIterations,
        'noop_floors': {
          'reader_us': readerFloor,
          'writer_us': writerFloor,
        },
        'workloads': {
          'noop': {
            'samples': zSamples.map((s) => s.toJson()).toList(),
            'summary': summarizeSamples(zSamples),
          },
          'single_insert': {
            'samples': aSamples.map((s) => s.toJson()).toList(),
            'summary': summarizeSamples(
              aSamples,
              readerFloor: readerFloor,
              writerFloor: writerFloor,
            ),
          },
          'point_query': {
            'samples': bSamples.map((s) => s.toJson()).toList(),
            'summary': summarizeSamples(
              bSamples,
              readerFloor: readerFloor,
              writerFloor: writerFloor,
            ),
          },
          'merge_rounds': {
            'samples': cSamples.map((s) => s.toJson()).toList(),
            'summary': summarizeSamples(
              cSamples,
              readerFloor: readerFloor,
              writerFloor: writerFloor,
            ),
          },
        },
      }),
    );
    print('');
    print('Results written to: $outPath');
    print('');
    print('For the cross-isolate breakdown, rerun under');
    print('  dart --observe --profile-period=100 \\');
    print('    -DRESQLITE_PROFILE=true benchmark/profile/dispatch_budget.dart');
    print('and capture the timeline in DevTools Performance tab. Look for');
    print('`writer.handle.*` and `reader.handle.*` spans.');
    print('');
    print('To diff this against another run:');
    print('  dart run benchmark/profile/diff.dart <baseline.json> $outPath');
  } finally {
    await profiled.close();
    await tempDir.delete(recursive: true);
  }
}

void _reportWorkload(String name, List<ProfileSample> samples) {
  final summary = summarizeSamples(samples);
  print('${samples.length} samples collected.');
  for (final entry in summary.entries) {
    final s = entry.value! as Map<String, Object?>;
    print('  ${entry.key.padRight(14)} '
        'count=${s['count']} '
        'min=${s['min_us']}μs '
        'median=${s['median_us']}μs '
        'p90=${s['p90_us']}μs '
        'p99=${s['p99_us']}μs '
        'max=${s['max_us']}μs');
  }
}
