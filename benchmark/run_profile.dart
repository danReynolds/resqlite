// ignore_for_file: avoid_print
//
// Profile-mode benchmark entry point.
//
// Unlike `run_release.dart` (which runs the pristine peer-comparison
// suite against drift/sqlite_async/sqlite3), this harness runs
// resqlite ONLY under full diagnostic instrumentation:
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
//     - Both sets of memory deltas survive into the output JSON and are
//       diffable via `benchmark/profile/diff.dart`.
//
// Purpose: A/B experiments between a branch and its baseline. Both runs
// use the same profile build, so any diagnostic overhead cancels out
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
import 'package:resqlite/src/profile_counters.dart';
import 'package:resqlite/src/profile_mode.dart';

import 'profile/profile_sample.dart';
import 'profile/profiled_database.dart';

const _singleInsertCount = 100;
const _pointQueryCount = 500;
const _mergeRoundCount = 10;
const _mergeRowsPerRound = 100;

const _warmupIterations = 50;
const _measureIterations = 100;

// Memory stabilization constants. Mirrors release-mode memory.dart.
const _churnSize = 10000;

Future<void> main(List<String> args) async {
  final options = _parseOptions(args);

  print('resqlite Profile-Mode Benchmark');
  print('================================');
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
    await _setupSchema(profiled);
    await _warmup(profiled);

    // Noop first — gives us the dispatch floor. Every subsequent
    // workload's `work_us` is computed relative to this.
    print('=== Workload Z: Noop Baseline (SELECT 1 / UPDATE WHERE 1=0) ===');
    final noop = await _runWorkload(
      name: 'noop',
      profiled: profiled,
      body: (iter) => _workloadNoop(profiled, iter),
    );
    final readerFloor =
        (_summarize(noop.samples)['select'] as Map)['median_us'] as int;
    final writerFloor =
        (_summarize(noop.samples)['execute'] as Map)['median_us'] as int;
    _reportWorkload(noop, readerFloor: null, writerFloor: null);
    print('  reader dispatch floor ≈ $readerFloor μs');
    print('  writer dispatch floor ≈ $writerFloor μs');

    print('');
    print('=== Workload A: Single Inserts ===');
    final singleInsert = await _runWorkload(
      name: 'single_insert',
      profiled: profiled,
      body: (iter) => _workloadSingleInserts(profiled, iter),
    );
    _reportWorkload(singleInsert,
        readerFloor: readerFloor, writerFloor: writerFloor);

    print('');
    print('=== Workload B: Point Queries ===');
    final pointQuery = await _runWorkload(
      name: 'point_query',
      profiled: profiled,
      body: (iter) => _workloadPointQuery(profiled, iter),
    );
    _reportWorkload(pointQuery,
        readerFloor: readerFloor, writerFloor: writerFloor);

    print('');
    print('=== Workload C: Merge Rounds ===');
    final mergeRounds = await _runWorkload(
      name: 'merge_rounds',
      profiled: profiled,
      body: (iter) => _workloadMergeRounds(profiled, iter),
    );
    _reportWorkload(mergeRounds,
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
          'noop': _workloadJson(noop,
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
// Workload execution — captures time + memory together
// ---------------------------------------------------------------------------

/// Results of running a single workload: time samples, RSS deltas, and
/// SQLite per-connection memory counters before/after.
class _WorkloadResult {
  _WorkloadResult({
    required this.name,
    required this.samples,
    required this.rssBeforeMB,
    required this.rssAfterMB,
    required this.diagnosticsBefore,
    required this.diagnosticsAfter,
    required this.countersBefore,
    required this.countersAfter,
  });

  final String name;
  final List<ProfileSample> samples;
  final double rssBeforeMB;
  final double rssAfterMB;
  final Diagnostics diagnosticsBefore;
  final Diagnostics diagnosticsAfter;

  /// Decoder allocation counters snapshotted immediately before the
  /// measured iterations began. Null when `kProfileMode` is false —
  /// the counters don't fire in that mode so their "before" and
  /// "after" values are identical and meaningless.
  final Map<String, int>? countersBefore;

  /// Decoder allocation counters snapshotted immediately after the
  /// measured iterations ended.
  final Map<String, int>? countersAfter;

  double get rssDeltaMB => rssAfterMB - rssBeforeMB;

  Map<String, int>? get counterDelta {
    if (countersBefore == null || countersAfter == null) return null;
    return ProfileCounters.diff(countersBefore!, countersAfter!);
  }
}

/// Runs a workload with memory stabilization before measurement, then
/// takes RSS and Diagnostics snapshots around the measured iterations.
///
/// Memory methodology mirrors release-mode memory.dart:
///   1. Heap-churn to stabilize baseline (drop 10k small Maps).
///   2. Take RSS + Diagnostics snapshot (baseline).
///   3. Run [_measureIterations] iterations of [body].
///   4. Take RSS + Diagnostics snapshot (post).
///
/// Per-call timing is still captured via ProfiledDatabase inside [body].
Future<_WorkloadResult> _runWorkload({
  required String name,
  required ProfiledDatabase profiled,
  required Future<void> Function(int iter) body,
}) async {
  // Stabilize the heap before baseline capture so leftover allocations
  // from prior workloads don't inflate this workload's rss_delta.
  _churnHeap();
  _churnHeap();

  final rssBefore = _rssMB();
  final diagBefore = await profiled.raw.diagnostics();
  final countersBefore = kProfileMode ? ProfileCounters.snapshot() : null;

  profiled.samples.clear();
  for (var iter = 0; iter < _measureIterations; iter++) {
    await body(iter);
  }

  final rssAfter = _rssMB();
  final diagAfter = await profiled.raw.diagnostics();
  final countersAfter = kProfileMode ? ProfileCounters.snapshot() : null;

  return _WorkloadResult(
    name: name,
    samples: List.of(profiled.samples),
    rssBeforeMB: rssBefore,
    rssAfterMB: rssAfter,
    diagnosticsBefore: diagBefore,
    diagnosticsAfter: diagAfter,
    countersBefore: countersBefore,
    countersAfter: countersAfter,
  );
}

double _rssMB() => ProcessInfo.currentRss / (1024 * 1024);

/// Pre-measurement churn loop. Allocates + drops [_churnSize] small maps
/// to stabilize the heap before baseline capture. Without this, heap
/// pages from the prior workload grow the RSS baseline and contaminate
/// the delta.
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
/// per-op wall time minus the appropriate dispatch floor.
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
      if (floor != null)
        'work_us_median': (medianUs - floor).clamp(0, 1 << 30),
      if (floor != null) 'dispatch_floor_us': floor,
    };
  }
  return summary;
}

/// Render Diagnostics to a JSON-friendly map.
Map<String, int> _diagnosticsJson(Diagnostics d) => {
      'sqlite_page_cache_bytes': d.sqlitePageCacheBytes,
      'sqlite_schema_bytes': d.sqliteSchemaBytes,
      'sqlite_stmt_bytes': d.sqliteStmtBytes,
      'wal_bytes': d.walBytes,
    };

/// Compute Diagnostics delta (after minus before) as a JSON-friendly map.
Map<String, int> _diagnosticsDelta(Diagnostics before, Diagnostics after) => {
      'sqlite_page_cache_bytes_delta':
          after.sqlitePageCacheBytes - before.sqlitePageCacheBytes,
      'sqlite_schema_bytes_delta':
          after.sqliteSchemaBytes - before.sqliteSchemaBytes,
      'sqlite_stmt_bytes_delta':
          after.sqliteStmtBytes - before.sqliteStmtBytes,
      'wal_bytes_delta': after.walBytes - before.walBytes,
    };

Map<String, Object?> _workloadJson(
  _WorkloadResult r, {
  required int? readerFloor,
  required int? writerFloor,
}) {
  return {
    'samples': r.samples.map((s) => s.toJson()).toList(),
    'summary': _summarize(r.samples,
        readerFloor: readerFloor, writerFloor: writerFloor),
    'memory': {
      'rss_before_mb': double.parse(r.rssBeforeMB.toStringAsFixed(3)),
      'rss_after_mb': double.parse(r.rssAfterMB.toStringAsFixed(3)),
      'rss_delta_mb': double.parse(r.rssDeltaMB.toStringAsFixed(3)),
      'diagnostics_before': _diagnosticsJson(r.diagnosticsBefore),
      'diagnostics_after': _diagnosticsJson(r.diagnosticsAfter),
      'diagnostics_delta':
          _diagnosticsDelta(r.diagnosticsBefore, r.diagnosticsAfter),
      // Decoder allocation counters. Only populated when kProfileMode
      // is compiled in (otherwise the counters never fire).
      if (r.counterDelta != null) 'allocation_delta': r.counterDelta,
    },
  };
}

void _reportWorkload(
  _WorkloadResult r, {
  required int? readerFloor,
  required int? writerFloor,
}) {
  final summary = _summarize(r.samples,
      readerFloor: readerFloor, writerFloor: writerFloor);
  print('${r.samples.length} samples collected.');
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
  final delta = _diagnosticsDelta(r.diagnosticsBefore, r.diagnosticsAfter);
  print('  memory:        '
      'rss Δ=${r.rssDeltaMB.toStringAsFixed(2)} MB  '
      'page cache Δ=${delta['sqlite_page_cache_bytes_delta']} B  '
      'stmt Δ=${delta['sqlite_stmt_bytes_delta']} B  '
      'wal Δ=${delta['wal_bytes_delta']} B');
  final cdelta = r.counterDelta;
  if (cdelta != null) {
    print('  alloc:         '
        'rows=${cdelta['rows_decoded']}  '
        'cells=${cdelta['cells_decoded']}');
  }
}
