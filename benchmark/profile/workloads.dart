/// Shared workload definitions, schema setup, and stats helpers for the
/// profile-mode harnesses (`dispatch_budget.dart`, `run_profile.dart`).
///
/// Kept in one place so both entry points measure identical work, any
/// workload change lands in a single file, and percentile / aggregate
/// reporting follows a single convention.
library;

import 'dart:math' as math;
import 'dart:async';

import 'profile_sample.dart';
import 'profiled_database.dart';

// ---------------------------------------------------------------------------
// Workload sizing
// ---------------------------------------------------------------------------

/// Inserts per measured iteration of `workloadSingleInserts`.
const int singleInsertCount = 100;

/// Point-query hits per measured iteration of `workloadPointQuery`.
const int pointQueryCount = 500;

/// Batches per measured iteration of `workloadMergeRounds`.
const int mergeRoundCount = 10;

/// Rows per batch inside `workloadMergeRounds`.
const int mergeRowsPerRound = 100;

/// Noop op count per iteration — 100 reads + 100 writes.
const int noopOpsPerSide = 100;

/// Seed row count used by [setupSchema] so point queries always hit
/// the table. Kept small enough to fit comfortably in SQLite's default
/// page cache.
const int seedRowCount = 1000;

/// Warmup iterations before timed measurement.
const int warmupIterations = 50;

/// Measured iterations per workload.
const int measureIterations = 100;

/// Rows in the numeric-heavy table used for exp-055-style memory scans.
const int numericSeedRowCount = 10000;

/// Full-table numeric scans per measured iteration.
const int numericScanCount = 10;

/// Distinct raw SQL strings rotated by [workloadSqlDiversity].
const int sqlDiversityDistinct = 64;

/// Loops over the [sqlDiversityDistinct] query set per measured iteration.
const int sqlDiversityLoops = 8;

/// Streams held open during the disjoint/overlap write workloads.
const int streamFanoutCount = 10;

/// Writes issued per stream-profile workload iteration.
const int streamWriteCount = 200;

// ---------------------------------------------------------------------------
// Percentile + summary helpers
// ---------------------------------------------------------------------------

/// Returns the [p]th percentile of [sorted] (a pre-sorted list of
/// integer microsecond samples).
///
/// Uses the `(n-1) * p` rounded index convention — the same formula
/// used by `benchmark/experiments/checkpoint_policy.dart:_percentileMs`,
/// which is also one step rounded from
/// `benchmark/head_to_head_worker.dart:_percentile` (linear interpolation
/// variant). Aligning on one convention keeps all profile-mode numbers
/// directly comparable to existing experiment outputs.
///
/// [p] is clamped to `[0, 1]`. Returns 0 for empty input.
int percentileUs(List<int> sorted, double p) {
  if (sorted.isEmpty) return 0;
  final clamped = p.clamp(0.0, 1.0);
  final idx = ((sorted.length - 1) * clamped).round();
  return sorted[idx];
}

/// Per-op aggregate statistics for a set of [ProfileSample]s.
///
/// Returns a map keyed by op name (`select`, `execute`, `executeBatch`),
/// where each value is a map of count/min/median/p90/p99/max/mean plus —
/// when [readerFloor] and/or [writerFloor] are supplied — a
/// `work_us_median` column that subtracts the dispatch floor from the
/// op's median total time. The work column is clamped at zero (a
/// negative value means the workload ran below the noop floor — noise).
Map<String, Object?> summarizeSamples(
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
    final medianUs = percentileUs(sorted, 0.50);
    summary[entry.key] = {
      'count': sorted.length,
      'min_us': sorted.first,
      'median_us': medianUs,
      'p90_us': percentileUs(sorted, 0.90),
      'p99_us': percentileUs(sorted, 0.99),
      'max_us': sorted.last,
      'mean_us': (sorted.reduce((a, b) => a + b) / sorted.length).round(),
      if (floor != null)
        'work_us_median': math.max(0, medianUs - floor),
      if (floor != null) 'dispatch_floor_us': floor,
    };
  }
  return summary;
}

// ---------------------------------------------------------------------------
// Schema + warmup
// ---------------------------------------------------------------------------

/// Installs the shared `items` table and seeds it with [seedRowCount]
/// rows. Must be called once before [warmup] or any workload.
Future<void> setupSchema(ProfiledDatabase db) async {
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
  await db.raw.execute('''
    CREATE TABLE wide(
      id INTEGER PRIMARY KEY,
      a TEXT NOT NULL,
      b TEXT NOT NULL,
      c TEXT NOT NULL,
      d TEXT NOT NULL
    )
  ''');
  await db.raw.execute('''
    CREATE TABLE metrics(
      id INTEGER PRIMARY KEY,
      n0 INTEGER NOT NULL,
      n1 INTEGER NOT NULL,
      n2 INTEGER NOT NULL,
      n3 INTEGER NOT NULL,
      f0 REAL NOT NULL,
      f1 REAL NOT NULL,
      f2 REAL NOT NULL,
      f3 REAL NOT NULL
    )
  ''');
  await db.raw.executeBatch(
    'INSERT INTO items(name, description, value, category, created_at) '
    'VALUES (?, ?, ?, ?, ?)',
    [
      for (var i = 0; i < seedRowCount; i++)
        [
          'Item $i',
          'desc-$i padded to ~80 chars so decode has real work to do',
          i * 1.5,
          'cat-${i % 10}',
          '2026-04-18T12:00:00Z',
        ],
    ],
  );
  await db.raw.executeBatch(
    'INSERT INTO wide(id, a, b, c, d) VALUES (?, ?, ?, ?, ?)',
    [
      for (var i = 0; i < 2000; i++) [i, 'a$i', 'b$i', 'c$i', 'd$i'],
    ],
  );
  await db.raw.executeBatch(
    'INSERT INTO metrics(id, n0, n1, n2, n3, f0, f1, f2, f3) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      for (var i = 0; i < numericSeedRowCount; i++)
        [
          i,
          i,
          i * 2,
          i * 3,
          i * 4,
          i / 10.0,
          i / 20.0,
          i / 30.0,
          i / 40.0,
        ],
    ],
  );
}

/// Primes the stmt cache, reader pool, and JIT before measurement.
/// Uses `db.raw` so warmup calls don't contaminate sample lists.
Future<void> warmup(ProfiledDatabase db) async {
  for (var i = 0; i < warmupIterations; i++) {
    await db.raw.select('SELECT * FROM items WHERE id = ?', [1]);
    await db.raw.execute(
      'INSERT INTO items(name, description, value, category, created_at) '
      'VALUES (?, ?, ?, ?, ?)',
      ['warm', 'w', 0.0, 'c', 't'],
    );
  }
  await db.raw.execute('DELETE FROM items WHERE id > $seedRowCount');
}

// ---------------------------------------------------------------------------
// Workloads
// ---------------------------------------------------------------------------

/// Noop baseline — measures the pure dispatch floor.
///
/// `SELECT 1 AS x` returns one constant row and does no table I/O —
/// its time is ~100% reader-side round-trip. `UPDATE ... WHERE 1=0`
/// acquires the writer mutex, runs the authorizer / preupdate-hook
/// setup, commits a no-op WAL frame, and responds — ~100% writer-side
/// round-trip with no dirty tables and no stream invalidation.
Future<void> workloadNoop(ProfiledDatabase db, int iter) async {
  for (var i = 0; i < noopOpsPerSide; i++) {
    await db.select('SELECT 1 AS x', const [], 'iter$iter-r');
  }
  for (var i = 0; i < noopOpsPerSide; i++) {
    await db.execute(
      'UPDATE items SET id = id WHERE 1 = 0',
      const [],
      'iter$iter-w',
    );
  }
}

/// [singleInsertCount] sequential INSERTs. Cleans up at the end of
/// each iteration so the table size stays constant across iterations.
Future<void> workloadSingleInserts(ProfiledDatabase db, int iter) async {
  for (var i = 0; i < singleInsertCount; i++) {
    await db.execute(
      'INSERT INTO items(name, description, value, category, created_at) '
      'VALUES (?, ?, ?, ?, ?)',
      ['s$i', 'd$i', i * 1.5, 'c', 't'],
      'iter$iter',
    );
  }
  await db.raw.execute('DELETE FROM items WHERE id > $seedRowCount');
}

/// [pointQueryCount] PK lookups hitting the seeded rows in a
/// round-robin pattern. No modifications — pure reader-side hot loop.
Future<void> workloadPointQuery(ProfiledDatabase db, int iter) async {
  for (var i = 0; i < pointQueryCount; i++) {
    await db.select(
      'SELECT * FROM items WHERE id = ?',
      [(i % seedRowCount) + 1],
      'iter$iter',
    );
  }
}

/// [mergeRoundCount] batches of [mergeRowsPerRound] `INSERT OR REPLACE`
/// rows each. Cleans up at end of iteration so table size is constant.
Future<void> workloadMergeRounds(ProfiledDatabase db, int iter) async {
  for (var r = 0; r < mergeRoundCount; r++) {
    final rows = [
      for (var i = 0; i < mergeRowsPerRound; i++)
        [
          2 * seedRowCount + r * mergeRowsPerRound + i,
          'm$r-$i',
          'd',
          i * 1.5,
          'c',
          't',
        ],
    ];
    await db.executeBatch(
      'INSERT OR REPLACE INTO items'
      '(id, name, description, value, category, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      rows,
      tag: 'iter$iter round$r',
    );
  }
  await db.raw.execute('DELETE FROM items WHERE id > $seedRowCount');
}

/// Numeric-heavy full-table scans for exp 055-style memory and transfer work.
///
/// This intentionally returns a wide numeric result-set so branch-to-branch
/// diffs can look at:
/// - time
/// - RSS / peak RSS
/// - rows/cells decoded
///
/// Any future columnar-storage experiment should move the memory numbers
/// more than the time numbers here.
Future<void> workloadNumericScan(ProfiledDatabase db, int iter) async {
  for (var i = 0; i < numericScanCount; i++) {
    await db.select(
      'SELECT id, n0, n1, n2, n3, f0, f1, f2, f3 '
      'FROM metrics ORDER BY id',
      const [],
      'iter$iter',
    );
  }
}

/// Rotates through many distinct but same-length SQL strings to stress the
/// stmt-cache lookup / eviction path (exp 071 / 069 revisit harness).
Future<void> workloadSqlDiversity(ProfiledDatabase db, int iter) async {
  for (var loop = 0; loop < sqlDiversityLoops; loop++) {
    for (var i = 0; i < sqlDiversityDistinct; i++) {
      final id = (i % 64) + 1;
      await db.select(
        'SELECT value FROM items WHERE id = ${id.toString().padLeft(4, '0')}',
        const [],
        'iter$iter',
      );
    }
  }
}

/// Projection-disjoint writes against active streams.
///
/// The result bytes stay unchanged, so current main should show:
/// - many reruns started
/// - many `stream_results_unchanged`
/// - zero `stream_emits_delivered`
///
/// A future exp-052 branch with writer-side column precision should cut
/// reruns themselves, not just emissions.
Future<void> workloadStreamDisjointWrites(ProfiledDatabase db, int iter) async {
  await _workloadStreamWrites(db, iter, disjoint: true);
}

/// Projection-overlapping writes against active streams.
///
/// Control case for [workloadStreamDisjointWrites] — reruns and emissions
/// should both happen because projected column `a` changes.
Future<void> workloadStreamOverlapWrites(ProfiledDatabase db, int iter) async {
  await _workloadStreamWrites(db, iter, disjoint: false);
}

Future<void> _workloadStreamWrites(
  ProfiledDatabase db,
  int iter, {
  required bool disjoint,
}) async {
  final ready = <Completer<void>>[
    for (var i = 0; i < streamFanoutCount; i++) Completer<void>(),
  ];
  final subs = <StreamSubscription<List<Map<String, Object?>>>>[];

  for (var i = 0; i < streamFanoutCount; i++) {
    final watchQuery =
        'SELECT id, a, b, $i as sid FROM wide WHERE id < 1000 ORDER BY id';
    subs.add(
      db.raw.stream(watchQuery).listen((_) {
        if (!ready[i].isCompleted) ready[i].complete();
      }),
    );
  }

  await Future.wait(ready.map((c) => c.future));

  final sql =
      disjoint ? 'UPDATE wide SET c = ? WHERE id = ?' : 'UPDATE wide SET a = ? WHERE id = ?';
  final prefix = disjoint ? 'd' : 'z';
  for (var i = 0; i < streamWriteCount; i++) {
    await db.execute(sql, ['$prefix-$iter-$i', i], 'iter$iter');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }
  await Future<void>.delayed(const Duration(milliseconds: 50));

  for (final sub in subs) {
    await sub.cancel();
  }
}
