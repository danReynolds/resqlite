// ignore_for_file: avoid_print
/// Phase 1 harness for experiment 080 — dispatch-budget research pass.
///
/// Runs the three workloads where resqlite currently trails sqlite3 on
/// the public dashboard (single insert, point query, merge rounds) under
/// a [ProfiledDatabase] wrapper that records per-call wall time. Pairs
/// with `Timeline.startSync` markers inside the writer and reader
/// isolates (dart:developer) — run with `dart --observe` to get the
/// cross-isolate breakdown in DevTools.
///
/// Output: writes `benchmark/profile/results/dispatch_budget_TIMESTAMP.json`
/// with per-call samples + aggregate percentile summary. Feed this into
/// `aggregate_budget.dart` (or read manually) to produce the findings
/// in `experiments/080-dispatch-budget.md`.
///
/// Usage:
///   dart run benchmark/profile/dispatch_budget.dart
///
/// With profiler:
///   dart --observe --profile-period=100 benchmark/profile/dispatch_budget.dart
///
/// Then open the service URL (printed by --observe) in DevTools →
/// Performance tab → record during the workload.
library;

import 'dart:convert';
import 'dart:io';

import 'package:resqlite/resqlite.dart';

import 'profile_sample.dart';
import 'profiled_database.dart';

// ---------------------------------------------------------------------------
// Workload parameters (small enough to run quickly under the profiler)
// ---------------------------------------------------------------------------

const _singleInsertCount = 100;
const _pointQueryCount = 500;
const _mergeRoundCount = 10;
const _mergeRowsPerRound = 100;

const _warmupIterations = 50;
const _measureIterations = 100;

Future<void> main() async {
  final tempDir = await Directory.systemTemp.createTemp('exp080_');
  final db = await Database.open('${tempDir.path}/test.db');
  final profiled = ProfiledDatabase(db);

  try {
    await _setupSchema(profiled);
    await _warmup(profiled);

    // --- Workload Z: noop baseline — measures pure round-trip floor ---
    // `SELECT 1` does no table I/O and returns one row. Whatever time
    // this takes is ~100% dispatch overhead (main → writer/reader →
    // main). Any real workload's time minus this baseline = actual SQL
    // + Dart-side materialization work.
    print('');
    print('=== Workload Z: Noop Baseline (SELECT 1) ===');
    profiled.samples.clear();
    for (var iter = 0; iter < _measureIterations; iter++) {
      await _workloadNoop(profiled, iter);
    }
    final zSamples = List.of(profiled.samples);
    _reportWorkload('noop', zSamples);
    final zSummary = _summarize(zSamples);
    final readerFloor = (zSummary['select'] as Map)['median_us'] as int;
    final writerFloor = (zSummary['execute'] as Map)['median_us'] as int;
    print('  → reader dispatch floor ≈ $readerFloor μs / round-trip');
    print('  → writer dispatch floor ≈ $writerFloor μs / round-trip');

    print('');
    print('=== Workload A: Single Inserts (100 sequential) ===');
    profiled.samples.clear();
    for (var iter = 0; iter < _measureIterations; iter++) {
      await _workloadSingleInserts(profiled, iter);
    }
    final aSamples = List.of(profiled.samples);
    _reportWorkload('single_insert', aSamples);

    print('');
    print('=== Workload B: Point Queries (500 hot-loop) ===');
    profiled.samples.clear();
    for (var iter = 0; iter < _measureIterations; iter++) {
      await _workloadPointQuery(profiled, iter);
    }
    final bSamples = List.of(profiled.samples);
    _reportWorkload('point_query', bSamples);

    print('');
    print('=== Workload C: Merge Rounds (10 × 100 rows) ===');
    profiled.samples.clear();
    for (var iter = 0; iter < _measureIterations; iter++) {
      await _workloadMergeRounds(profiled, iter);
    }
    final cSamples = List.of(profiled.samples);
    _reportWorkload('merge_rounds', cSamples);

    // Persist the full sample set for downstream analysis + potential
    // re-aggregation with different percentile cutoffs.
    final outDir = Directory('benchmark/profile/results');
    if (!outDir.existsSync()) await outDir.create(recursive: true);
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final outPath = '${outDir.path}/dispatch_budget_$timestamp.json';
    await File(outPath).writeAsString(const JsonEncoder.withIndent('  ').convert({
      'generated_at': DateTime.now().toIso8601String(),
      'iterations': _measureIterations,
      'workloads': {
        'single_insert': {
          'samples': aSamples.map((s) => s.toJson()).toList(),
          'summary': _summarize(aSamples),
        },
        'point_query': {
          'samples': bSamples.map((s) => s.toJson()).toList(),
          'summary': _summarize(bSamples),
        },
        'merge_rounds': {
          'samples': cSamples.map((s) => s.toJson()).toList(),
          'summary': _summarize(cSamples),
        },
      },
    }));
    print('');
    print('Results written to: $outPath');
    print('');
    print('For the cross-isolate breakdown, rerun under');
    print('  dart --observe --profile-period=100 benchmark/profile/dispatch_budget.dart');
    print('and capture the timeline in DevTools Performance tab. Look for');
    print('`writer.handle.*` and `reader.handle.*` spans.');
  } finally {
    await profiled.close();
    await tempDir.delete(recursive: true);
  }
}

// ---------------------------------------------------------------------------
// Setup + warmup
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
  // Seed 1000 rows for point-query workload.
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
  // Prime the stmt cache, reader pool, etc.
  for (var i = 0; i < _warmupIterations; i++) {
    await db.raw.select('SELECT * FROM items WHERE id = ?', [1]);
    await db.raw.execute('INSERT INTO items(name, description, value, '
        'category, created_at) VALUES (?, ?, ?, ?, ?)',
        ['warm', 'w', 0.0, 'c', 't']);
  }
  await db.raw.execute('DELETE FROM items WHERE id > 1000');
}

// ---------------------------------------------------------------------------
// Workloads
// ---------------------------------------------------------------------------

Future<void> _workloadNoop(ProfiledDatabase db, int iter) async {
  // Reader-side floor: `SELECT 1` returns one constant row, no table I/O.
  for (var i = 0; i < 100; i++) {
    await db.select('SELECT 1 AS x', const [], 'iter$iter-r');
  }
  // Writer-side floor: `UPDATE ... WHERE 1=0` matches zero rows but
  // still acquires the writer mutex, sends a message, does authorizer /
  // preupdate-hook setup, commits (or no-ops the WAL frame), and
  // responds. Empty dirtyTables — no stream invalidation cost.
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
  // Clean up between iterations so the table stays the same size.
  await db.raw.execute('DELETE FROM items WHERE id > 1000');
}

Future<void> _workloadPointQuery(ProfiledDatabase db, int iter) async {
  for (var i = 0; i < _pointQueryCount; i++) {
    await db.select('SELECT * FROM items WHERE id = ?',
        [(i % 1000) + 1], 'iter$iter');
  }
}

Future<void> _workloadMergeRounds(ProfiledDatabase db, int iter) async {
  // Each iteration = 10 batches of 100 INSERT OR REPLACE rows.
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
// Aggregation + reporting
// ---------------------------------------------------------------------------

Map<String, Object?> _summarize(List<ProfileSample> samples) {
  if (samples.isEmpty) return {};
  final microsByOp = <String, List<int>>{};
  for (final s in samples) {
    microsByOp.putIfAbsent(s.op, () => []).add(s.totalMicros);
  }
  final summary = <String, Object?>{};
  for (final entry in microsByOp.entries) {
    final sorted = List<int>.from(entry.value)..sort();
    summary[entry.key] = {
      'count': sorted.length,
      'min_us': sorted.first,
      'median_us': sorted[sorted.length ~/ 2],
      'p90_us': sorted[(sorted.length * 0.9).floor().clamp(0, sorted.length - 1)],
      'p99_us': sorted[(sorted.length * 0.99).floor().clamp(0, sorted.length - 1)],
      'max_us': sorted.last,
      'mean_us':
          (sorted.reduce((a, b) => a + b) / sorted.length).round(),
    };
  }
  return summary;
}

void _reportWorkload(String name, List<ProfileSample> samples) {
  final summary = _summarize(samples);
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
