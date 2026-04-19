// ignore_for_file: avoid_print
//
// Profile-mode benchmark entry point.
//
// Unlike `run_release.dart` (which runs the pristine peer-comparison
// suite against drift/sqlite_async/sqlite3), this harness runs
// resqlite ONLY under diagnostic instrumentation:
//
//   - `ProfiledDatabase` wraps every call with per-op Stopwatch timing.
//   - Timeline markers inside the writer and reader isolates are compiled
//     in when run with `-DRESQLITE_PROFILE=true` — visible in DevTools.
//   - A `noop` baseline workload (SELECT 1 / UPDATE WHERE 1=0) is always
//     run first, and `work_us = total_us - noop_median_us` is computed
//     for every other workload. Lets you say "this experiment saved
//     X μs of work on top of Y μs of unavoidable dispatch."
//
// Purpose: A/B experiments between a branch and its baseline. Both runs
// use the same profile build, so the diagnostic overhead cancels out
// in the delta — what you see is the signal of the change under test.
//
// Usage:
//
//   # Baseline
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
// See benchmark/EXPERIMENTS.md for the full workflow.

import 'dart:convert';
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/profile_mode.dart';

import 'profile/profile_sample.dart';
import 'profile/profiled_database.dart';

const _singleInsertCount = 100;
const _pointQueryCount = 500;
const _mergeRoundCount = 10;
const _mergeRowsPerRound = 100;

const _warmupIterations = 50;
const _measureIterations = 100;

Future<void> main(List<String> args) async {
  final options = _parseOptions(args);

  print('resqlite Profile-Mode Benchmark');
  print('================================');
  print('');
  if (!kProfileMode) {
    print('⚠  kProfileMode=false (Timeline markers tree-shaken out).');
    print('   ProfiledDatabase per-call timing still works, but you will');
    print('   not see writer.handle.* / reader.handle.* spans in DevTools.');
    print('   Rerun with -DRESQLITE_PROFILE=true to enable them.');
    print('');
  } else {
    print('kProfileMode=true — Timeline markers active.');
    print('');
  }

  final tempDir = await Directory.systemTemp.createTemp('run_profile_');
  final db = await Database.open('${tempDir.path}/test.db');
  final profiled = ProfiledDatabase(db);

  try {
    await _setupSchema(profiled);
    await _warmup(profiled);

    // Noop first — gives us the dispatch floor. Every subsequent
    // workload's `work_us` is computed relative to this.
    print('=== Workload Z: Noop Baseline (SELECT 1 / UPDATE WHERE 1=0) ===');
    profiled.samples.clear();
    for (var iter = 0; iter < _measureIterations; iter++) {
      await _workloadNoop(profiled, iter);
    }
    final noopSamples = List.of(profiled.samples);
    final noopSummary = _summarize(noopSamples);
    final readerFloor = (noopSummary['select'] as Map)['median_us'] as int;
    final writerFloor = (noopSummary['execute'] as Map)['median_us'] as int;
    _reportWorkload('noop', noopSamples, readerFloor: null, writerFloor: null);
    print('  reader dispatch floor ≈ $readerFloor μs');
    print('  writer dispatch floor ≈ $writerFloor μs');

    print('');
    print('=== Workload A: Single Inserts ===');
    profiled.samples.clear();
    for (var iter = 0; iter < _measureIterations; iter++) {
      await _workloadSingleInserts(profiled, iter);
    }
    final singleInsert = List.of(profiled.samples);
    _reportWorkload('single_insert', singleInsert,
        readerFloor: readerFloor, writerFloor: writerFloor);

    print('');
    print('=== Workload B: Point Queries ===');
    profiled.samples.clear();
    for (var iter = 0; iter < _measureIterations; iter++) {
      await _workloadPointQuery(profiled, iter);
    }
    final pointQuery = List.of(profiled.samples);
    _reportWorkload('point_query', pointQuery,
        readerFloor: readerFloor, writerFloor: writerFloor);

    print('');
    print('=== Workload C: Merge Rounds ===');
    profiled.samples.clear();
    for (var iter = 0; iter < _measureIterations; iter++) {
      await _workloadMergeRounds(profiled, iter);
    }
    final mergeRounds = List.of(profiled.samples);
    _reportWorkload('merge_rounds', mergeRounds,
        readerFloor: readerFloor, writerFloor: writerFloor);

    // Persist the whole thing. diff.dart reads these JSON files.
    final outPath = options.outPath ?? _defaultOutPath();
    final outDir = File(outPath).parent;
    if (!outDir.existsSync()) outDir.createSync(recursive: true);

    await File(outPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'generated_at': DateTime.now().toIso8601String(),
        'profile_mode_enabled': kProfileMode,
        'iterations': _measureIterations,
        'noop_floors': {
          'reader_us': readerFloor,
          'writer_us': writerFloor,
        },
        'workloads': {
          'noop': _workloadJson(noopSamples,
              readerFloor: null, writerFloor: null),
          'single_insert': _workloadJson(singleInsert,
              readerFloor: readerFloor, writerFloor: writerFloor),
          'point_query': _workloadJson(pointQuery,
              readerFloor: readerFloor, writerFloor: writerFloor),
          'merge_rounds': _workloadJson(mergeRounds,
              readerFloor: readerFloor, writerFloor: writerFloor),
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
  } finally {
    await profiled.close();
    await tempDir.delete(recursive: true);
  }
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
      print('Usage: dart run -DRESQLITE_PROFILE=true '
          'benchmark/run_profile.dart [--out=PATH]');
      print('');
      print('  --out=PATH   Write rich JSON to PATH. Defaults to');
      print('               benchmark/profile/results/run_profile_TIMESTAMP.json');
      print('');
      print('See benchmark/EXPERIMENTS.md for the A/B workflow.');
      exit(0);
    } else {
      stderr.writeln('Unknown argument: $arg');
      exit(2);
    }
  }
  return _Options(outPath: outPath);
}

String _defaultOutPath() {
  final ts = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '-')
      .split('.')
      .first;
  return 'benchmark/profile/results/run_profile_$ts.json';
}

// ---------------------------------------------------------------------------
// Setup + workloads (kept in sync with dispatch_budget.dart)
// ---------------------------------------------------------------------------

Future<void> _setupSchema(ProfiledDatabase db) async {
  await db.raw.execute('''
    CREATE TABLE items(
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT NOT NULL,
      value REAL NOT NULL,
      category TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');
  await db.raw.executeBatch(
    'INSERT INTO items(name, description, value, category, created_at) '
    'VALUES (?, ?, ?, ?, ?)',
    [
      for (var i = 0; i < 1000; i++)
        [
          'Item $i',
          'desc-$i padded to ~80 chars so decode has real work to do',
          i * 1.5,
          'cat-${i % 10}',
          '2026-04-18T12:00:00Z',
        ],
    ],
  );
}

Future<void> _warmup(ProfiledDatabase db) async {
  for (var i = 0; i < _warmupIterations; i++) {
    await db.raw.select('SELECT * FROM items WHERE id = ?', [1]);
    await db.raw.execute(
        'INSERT INTO items(name, description, value, category, created_at) '
        'VALUES (?, ?, ?, ?, ?)',
        ['warm', 'w', 0.0, 'c', 't']);
  }
  await db.raw.execute('DELETE FROM items WHERE id > 1000');
}

Future<void> _workloadNoop(ProfiledDatabase db, int iter) async {
  for (var i = 0; i < 100; i++) {
    await db.select('SELECT 1 AS x', const [], 'iter$iter-r');
  }
  for (var i = 0; i < 100; i++) {
    await db.execute('UPDATE items SET id = id WHERE 1 = 0',
        const [], 'iter$iter-w');
  }
}

Future<void> _workloadSingleInserts(ProfiledDatabase db, int iter) async {
  for (var i = 0; i < _singleInsertCount; i++) {
    await db.execute(
      'INSERT INTO items(name, description, value, category, created_at) '
      'VALUES (?, ?, ?, ?, ?)',
      ['s$i', 'd$i', i * 1.5, 'c', 't'],
      'iter$iter',
    );
  }
  await db.raw.execute('DELETE FROM items WHERE id > 1000');
}

Future<void> _workloadPointQuery(ProfiledDatabase db, int iter) async {
  for (var i = 0; i < _pointQueryCount; i++) {
    await db.select('SELECT * FROM items WHERE id = ?',
        [(i % 1000) + 1], 'iter$iter');
  }
}

Future<void> _workloadMergeRounds(ProfiledDatabase db, int iter) async {
  for (var r = 0; r < _mergeRoundCount; r++) {
    final rows = [
      for (var i = 0; i < _mergeRowsPerRound; i++)
        [
          2000 + r * _mergeRowsPerRound + i,
          'm$r-$i',
          'd',
          i * 1.5,
          'c',
          't',
        ],
    ];
    await db.executeBatch(
      'INSERT OR REPLACE INTO items(id, name, description, value, category, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      rows,
      tag: 'iter$iter round$r',
    );
  }
  await db.raw.execute('DELETE FROM items WHERE id > 1000');
}

// ---------------------------------------------------------------------------
// Summary + reporting
// ---------------------------------------------------------------------------

/// Compute per-op aggregate statistics. Includes `work_us_median` — the
/// per-op wall time minus the appropriate dispatch floor. That gives a
/// pure "time spent actually doing work" number, which is what you want
/// to compare across experiments on the dispatch hot path.
Map<String, Object?> _summarize(
  List<ProfileSample> samples, {
  int? readerFloor,
  int? writerFloor,
}) {
  if (samples.isEmpty) return {};
  final microsByOp = <String, List<int>>{};
  for (final s in samples) {
    microsByOp.putIfAbsent(s.op, () => []).add(s.totalMicros);
  }
  final summary = <String, Object?>{};
  for (final entry in microsByOp.entries) {
    final sorted = List<int>.from(entry.value)..sort();
    final floor = entry.key == 'select' ? readerFloor : writerFloor;
    final medianUs = sorted[sorted.length ~/ 2];
    summary[entry.key] = {
      'count': sorted.length,
      'min_us': sorted.first,
      'median_us': medianUs,
      'p90_us':
          sorted[(sorted.length * 0.9).floor().clamp(0, sorted.length - 1)],
      'p99_us':
          sorted[(sorted.length * 0.99).floor().clamp(0, sorted.length - 1)],
      'max_us': sorted.last,
      'mean_us': (sorted.reduce((a, b) => a + b) / sorted.length).round(),
      // work_us_median = median total time minus dispatch floor for the
      // relevant path. Null for the noop workload itself (no meaningful
      // "work" to subtract from). Clamped at zero — negative values mean
      // this workload ran faster than the noop floor (noise).
      if (floor != null)
        'work_us_median': (medianUs - floor).clamp(0, 1 << 30),
      if (floor != null) 'dispatch_floor_us': floor,
    };
  }
  return summary;
}

Map<String, Object?> _workloadJson(
  List<ProfileSample> samples, {
  required int? readerFloor,
  required int? writerFloor,
}) {
  return {
    'samples': samples.map((s) => s.toJson()).toList(),
    'summary': _summarize(samples,
        readerFloor: readerFloor, writerFloor: writerFloor),
  };
}

void _reportWorkload(
  String name,
  List<ProfileSample> samples, {
  required int? readerFloor,
  required int? writerFloor,
}) {
  final summary = _summarize(samples,
      readerFloor: readerFloor, writerFloor: writerFloor);
  print('${samples.length} samples collected.');
  for (final entry in summary.entries) {
    final s = entry.value! as Map<String, Object?>;
    final workPart = s.containsKey('work_us_median')
        ? ' work=${s['work_us_median']}μs'
        : '';
    print('  ${entry.key.padRight(14)} '
        'count=${s['count']} '
        'min=${s['min_us']}μs '
        'p50=${s['median_us']}μs '
        'p90=${s['p90_us']}μs '
        'p99=${s['p99_us']}μs '
        'max=${s['max_us']}μs'
        '$workPart');
  }
}
