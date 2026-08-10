// ignore_for_file: avoid_print
//
// Focused A/B harness for statement-cache *capacity* ([EXP-267]).
//
// Three caches in the read path are keyed by SQL text and bounded: the C
// per-connection prepared-statement cache (`STMT_CACHE_MAX`), the per-worker
// Dart `schemaCache`, and the pool's row-size memory. When this harness was
// written all three were capped at 32 entries; exp 267 raised them to 128, and
// the lane names below still bracket the original cap because that is where
// the effect was measured.
// Every benchmark in the repo, release and focused alike, uses under ten
// distinct SQL strings, so none of them has ever put a single one of those
// caches under pressure. Exp 071 and exp 073 each rejected a cache change for
// exactly that reason and each closed by asking for this workload — "64
// rotating query shapes, cache at capacity" — before any cache-sizing
// experiment was attempted. It was never built.
//
// What makes the gap load-bearing now is exp 266. Under the round-robin
// dispatch it replaced, a cycle of D distinct statements was *partitioned*
// across the four reader workers — each cache saw roughly D/4 of them, so a
// 128-statement application still fit. Sticky dispatch sends a sequential read
// loop to one worker, so one cache now sees all D. The cap did not move; the
// workload that reaches it did.
//
// The access pattern matters as much as the count. These caches evict at the
// front (`entries[0]`) and promote on hit, which is approximately LRU — the
// worst possible policy for a cyclic scan. At D <= 32 every read hits; at
// D = 33 the entry each read needs is the one the previous miss just evicted,
// so the hit rate collapses to zero. The expectation is a cliff, not a slope.
//
// Lanes, and what each is for:
//
//   rotate8              D distinct statements executed round-robin, differing
//   rotate24             only by a trailing comment so the plan, the schema and
//     the row count are identical and the only thing D changes is how many
//     cache identities the workload carries. CONTROLS: both fit inside 32, so
//     the changed path is unreachable and they must read neutral.
//   rotate32             Exactly at the cap. Boundary: still fits, by one.
//   rotate40             PRIMARY. Just past the cap, where LRU turns cyclic
//   rotate64             access into a total miss. The three widths bracket
//   rotate128            how far past the cliff the cost keeps growing; 64 is
//     the shape exp 071 named.
//   point1               One long-warm statement, 256 sequential executions.
//     CONTROL for the *candidate's* cost rather than the baseline's: raising a
//     cap lengthens `stmt_cache_lookup_entry`'s linear scan, and this lane
//     holds a one-entry cache, so it must not move.
//   churn-unique         256 statements per sample, none ever repeated.
//     ADVERSARIAL GUARD: no cache of any size can help, so the candidate can
//     only add scan length and eviction work here. This is the lane that can
//     reject a larger cap.
//
// Every sample performs the same ~256 reads regardless of D, so a sample is
// ~2 ms in every lane and no lane is decided by stopwatch resolution
// ([EXP-264](../../experiments/264-initial-alloc-size-memory.md)).
//
// Usage:
//   dart run benchmark/experiments/stmt_cache_pressure.dart \
//     [--warmup=5] [--samples=41] [--lane=rotate64]
//
// Emits one `shape=... median_us=... samples_us=...` line per lane, so two
// worktree runs pair into `benchmark/ab_drift_check.dart` input.
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;

import '../shared/memory_probe.dart';

const _defaultWarmup = 5;
const _defaultSamples = 41;

/// Reads per timed sample, held constant across lanes so the sample duration
/// does not vary with the lane's statement count.
const _readsPerSample = 256;

final class _Lane {
  const _Lane(this.label, {required this.distinct, this.unique = false});

  final String label;

  /// How many distinct SQL strings the lane cycles through. For [unique]
  /// lanes this is ignored — every read gets its own string.
  final int distinct;

  /// Mint a never-before-seen statement for every read instead of cycling a
  /// fixed set. No cache can hit, at any capacity.
  final bool unique;

  /// Full cycles per sample, chosen so every lane issues [_readsPerSample]
  /// reads.
  int get cycles {
    final n = _readsPerSample ~/ distinct;
    return n < 1 ? 1 : n;
  }
}

// The repo's canonical mixed row: 6 columns total (`id INTEGER PRIMARY KEY`,
// 4 TEXT, 1 REAL), copied verbatim from `benchmark/shared/seeder.dart` the way
// the neighbouring focused harnesses do.
const _standardCreate = '''
  CREATE TABLE items(
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    value REAL NOT NULL,
    category TEXT NOT NULL,
    created_at TEXT NOT NULL
  )
''';
const _standardInsert =
    'INSERT INTO items(name, description, value, category, created_at) '
    'VALUES (?, ?, ?, ?, ?)';
List<Object?> _standardRow(int i) => [
  'Item $i',
  'This is a description for item number $i with some padding text to '
      'simulate real data',
  i * 1.5,
  'category_${i % 10}',
  '2026-04-0${(i % 9) + 1}T12:00:00Z',
];

const _rows = 2000;

/// The one statement every lane runs. A trailing comment gives it a distinct
/// cache identity without changing the parse, the plan or the result, so a
/// lane's `distinct` count is the only variable.
const _baseSql = 'SELECT * FROM items WHERE id = ?';
const _params = [17];

final _lanes = <_Lane>[
  // CONTROLS: inside the cap, so no eviction happens in either arm.
  _Lane('rotate8', distinct: 8),
  _Lane('rotate24', distinct: 24),
  // Boundary: exactly the cap.
  _Lane('rotate32', distinct: 32),
  // PRIMARIES: past the cap, where cyclic access defeats LRU completely.
  _Lane('rotate40', distinct: 40),
  _Lane('rotate64', distinct: 64),
  _Lane('rotate128', distinct: 128),
  // CONTROL for the candidate's own cost: a one-entry cache, 256 executions.
  _Lane('point1', distinct: 1),
  // ADVERSARIAL GUARD: nothing is ever reused, so a bigger cache is pure cost.
  _Lane('churn-unique', distinct: _readsPerSample, unique: true),
];

Future<void> main(List<String> args) async {
  var warmup = _defaultWarmup;
  var samples = _defaultSamples;
  String? only;
  for (final arg in args) {
    if (arg.startsWith('--warmup=')) {
      warmup = int.parse(arg.substring('--warmup='.length));
    } else if (arg.startsWith('--samples=')) {
      samples = int.parse(arg.substring('--samples='.length));
    } else if (arg.startsWith('--lane=')) {
      only = arg.substring('--lane='.length);
    } else {
      throw ArgumentError('unknown argument: $arg');
    }
  }

  print('=== statement cache pressure focused harness ===');
  print('warmup=$warmup samples=$samples reads_per_sample=$_readsPerSample');
  for (final lane in _lanes) {
    if (only != null && lane.label != only) continue;
    await _runLane(
      lane,
      warmup: warmup,
      samples: samples,
      laneIsolated: only != null,
    );
  }
}

Future<void> _runLane(
  _Lane lane, {
  required int warmup,
  required int samples,
  required bool laneIsolated,
}) async {
  final temp = await Directory.systemTemp.createTemp('bench_stmt_cap_');
  try {
    final db = await resqlite.Database.open('${temp.path}/test.db');
    await db.execute(_standardCreate);

    const chunk = 500;
    for (var start = 0; start < _rows; start += chunk) {
      final end = start + chunk < _rows ? start + chunk : _rows;
      await db.executeBatch(_standardInsert, [
        for (var r = start; r < end; r++) _standardRow(r),
      ]);
    }

    // The cycled statements, minted once so warmup establishes the steady
    // state the timed samples measure: at D <= cap every entry is resident,
    // and past it the cycle is already thrashing before the first sample.
    final cycle = lane.unique
        ? const <String>[]
        : [for (var i = 0; i < lane.distinct; i++) '$_baseSql -- q$i'];

    for (var i = 0; i < warmup; i++) {
      await _sample(db, lane, cycle);
    }

    final probe = MemoryProbe.start();
    final values = <int>[];
    for (var i = 0; i < samples; i++) {
      final sw = Stopwatch()..start();
      await _sample(db, lane, cycle);
      sw.stop();
      values.add(sw.elapsedMicroseconds);
      // Outside the stopwatch: a currentRss read costs ~700 ns.
      probe.sample();
    }
    final reading = probe.finish(laneIsolated: laneIsolated);
    await db.close();

    final sorted = [...values]..sort();
    print(
      'shape=${lane.label} '
      'median_us=${_percentile(sorted, 0.50)} '
      'p10_us=${_percentile(sorted, 0.10)} '
      'p90_us=${_percentile(sorted, 0.90)} '
      '${reading.format()} '
      'samples_us=${values.join(',')}',
    );
  } finally {
    await temp.delete(recursive: true);
  }
}

/// Monotonic counter behind the never-repeated statements of the churn lane.
int _uniqueSeq = 0;

/// One timed sample: [_readsPerSample] point reads, spread over the lane's
/// statement set.
Future<void> _sample(
  resqlite.Database db,
  _Lane lane,
  List<String> cycle,
) async {
  if (lane.unique) {
    for (var n = 0; n < _readsPerSample; n++) {
      await _read(db, '$_baseSql -- u${_uniqueSeq++}');
    }
    return;
  }
  for (var c = 0; c < lane.cycles; c++) {
    for (final sql in cycle) {
      await _read(db, sql);
    }
  }
}

Future<void> _read(resqlite.Database db, String sql) async {
  final rows = await db.select(sql, _params);
  if (rows.length != 1) {
    throw StateError('expected 1 row from "$sql", got ${rows.length}');
  }
}

int _percentile(List<int> sorted, double percentile) =>
    sorted[((sorted.length - 1) * percentile).round()];
