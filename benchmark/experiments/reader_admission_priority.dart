// ignore_for_file: avoid_print
//
// Focused A/B harness for reader-pool *admission* ([EXP-275]).
//
// Every other harness in this directory measures what a read costs. This one
// measures what a read WAITS for. `ReaderPool._dispatch` takes the first free
// worker and otherwise parks on a FIFO queue, so a point read that arrives
// while four 1,000-row reads hold the pool waits for one of them to finish —
// exp 265 measured 533-1169 us of waiting in front of an 8 us read, and closed
// as the "admission" half of the round-trip price that exps 244/245/246 held
// constant by design.
//
// The candidate gives dispatch the cost signal exps 260/264 built for buffer
// sizing: `_rowHints[sql].highWater`, a main-isolate memory of how many rows
// each statement has ever returned, available BEFORE the request is sent. Two
// arms use it — a cheap waiter is woken ahead of costly ones (bounded by
// `maxCheapSkips`), and a costly read is refused the pool's last free worker
// while cheap reads are recent (bounded by `reserveWindow` and
// `maxReservationDenials`).
//
//   point-under-load    PRIMARY, and the reservation's target. ONE point read
//     issued while four 1,000-row reads hold every worker. Exp 265's lane of
//     the same name, minus its inline execution: the question here is whether
//     the wait can be removed without moving SQLite to the caller. Only the
//     first read is timed — see [_underLoadTrailingReads] for why summing ten
//     the way exp 265 did hides the answer here.
//   mixed-queue         PRIMARY, and the priority queue's target. Eight large
//     reads are issued, then eight point reads, all outstanding together. The
//     sample is when the POINT reads finish. Under FIFO each one waits behind
//     four more large reads it has nothing to do with; the shape a UI hits when
//     a list refresh is already in flight and the user taps something.
//   bulk4-mixed         LOAD-BEARING GUARD, and the price. Four concurrent
//     1,000-row reads, issued on a pool that just served a point read so the
//     reservation is armed. Only three run at a time, so this lane is where
//     holding a worker back is paid for. A win on the two primaries that is
//     funded entirely out of this lane is a trade between two callers, not an
//     improvement.
//   bulk4-cold          CONTROL for the hysteresis. The same four concurrent
//     large reads with no cheap read anywhere in the lane, so `reserveWindow`
//     must have switched the reservation off and the lane must be neutral. If
//     it moves with `bulk4-mixed`, the reservation is unconditional.
//   costly-latency      GUARD for starvation. One large read issued into a
//     continuous chain of point reads; the sample is the LARGE read's own
//     latency. `maxCheapSkips` is what bounds it, so this lane is what proves
//     the bound is real rather than asserted.
//   point1              CONTROL. Sequential point reads on an idle pool, where
//     no waiter ever parks and the only difference is the classification work
//     added to the dispatch fast path.
//   int20-10k           CONTROL. One 10k x 20 read at a time on an idle pool.
//   concurrent8-cheap   CONTROL. Eight point reads together and nothing else.
//     Every waiter is cheap, so there is no reordering available and the lane
//     isolates whatever the split waiter queues cost by themselves.
//
// Usage:
//   dart run benchmark/experiments/reader_admission_priority.dart \
//     [--warmup=10] [--samples=31] [--lane=point-under-load] [--no-memory]
//
// Emits one `shape=... median_us=... samples_us=...` line per lane, so two
// worktree runs can be paired into `benchmark/ab_drift_check.dart` input.
import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;

import '../shared/memory_probe.dart';

const _defaultWarmup = 10;
const _defaultSamples = 31;

/// Rows the large reads in every mixed lane return. Well past the 64-row cheap
/// cap, and the size exp 265 used for the same background load.
const int _largeRows = 1000;

/// Enough large reads outstanding to occupy every worker in the largest pool
/// `Database.open` will build (four).
const int _poolWidth = 4;

/// Point reads issued after the timed one in a `point-under-load` sample, to
/// drain the lane the way a real caller would.
///
/// Only the FIRST is timed. Exp 265's lane of this name timed ten and reported
/// their sum, which was right for a candidate that took all ten off the pool
/// but hides this one: sticky dispatch ([EXP-266]) parks the whole sequential
/// run on whichever worker frees first, so from the second read on the pool is
/// no longer saturated and both arms cost the same ~20 us. Summing ten dilutes
/// the one read that waits by nine that do not.
const int _underLoadTrailingReads = 9;

/// Large reads issued ahead of the point reads in `mixed-queue`. Twice the pool
/// width, so four run immediately and four park in front of the point reads.
const int _queuedLarge = 8;

/// Point reads issued behind them, and the ones the sample times.
const int _queuedPoint = 8;

/// Point reads kept in flight around the timed large read in `costly-latency`.
const int _starvationCheapReads = 16;

/// Groups of concurrent point reads per `concurrent8-cheap` sample.
const int _concurrentRounds = 10;

enum _Mode {
  /// Execute the lane's statement [_Lane.repeats] times.
  plain,

  /// Saturate the pool with large reads, then time point reads issued while
  /// they are still outstanding.
  underLoad,

  /// Queue large reads ahead of point reads and time when the point reads
  /// finish.
  mixedQueue,

  /// Time four concurrent large reads, having first issued a point read so the
  /// reservation is armed.
  bulkMixed,

  /// Time four concurrent large reads with no cheap read anywhere in the lane.
  bulkCold,

  /// Time one large read issued into a continuous chain of point reads.
  costlyLatency,

  /// Issue [_Lane.repeats] distinct point statements together, [_concurrentRounds]
  /// times.
  concurrent,
}

final class _Lane {
  const _Lane(
    this.label, {
    required this.rows,
    this.columns = 0,
    this.selectSql = 'SELECT * FROM items',
    this.selectParams = const [],
    this.expectRows,
    this.repeats = 1,
    this.mode = _Mode.plain,
  });

  final String label;

  /// Rows seeded into the table.
  final int rows;

  /// Generated INTEGER columns beside `id`, or 0 for the canonical mixed row.
  final int columns;

  final String selectSql;
  final List<Object?> selectParams;

  /// Rows the timed statement returns, when that differs from [rows].
  final int? expectRows;

  /// Executions inside one timed sample. Reported medians are per sample.
  final int repeats;

  final _Mode mode;
}

// The repo's canonical mixed row, copied verbatim from `benchmark/shared/seeder.dart`
// the way the neighbouring focused harnesses do rather than importing the seeder
// and dragging its peer-library imports into a focused binary.
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

const _pointSql = 'SELECT * FROM items WHERE id = ?';
const _largeSql = 'SELECT * FROM items';

final _lanes = <_Lane>[
  // PRIMARY: the reservation's target.
  _Lane(
    'point-under-load',
    rows: _largeRows,
    selectSql: _pointSql,
    selectParams: [17],
    expectRows: 1,
    mode: _Mode.underLoad,
  ),
  // PRIMARY: the priority queue's target.
  _Lane(
    'mixed-queue',
    rows: _largeRows,
    selectSql: _pointSql,
    selectParams: [17],
    expectRows: 1,
    mode: _Mode.mixedQueue,
  ),
  // LOAD-BEARING GUARD: what the reservation costs.
  _Lane('bulk4-mixed', rows: _largeRows, mode: _Mode.bulkMixed),
  // CONTROL: the same burst with the reservation disarmed.
  _Lane('bulk4-cold', rows: _largeRows, mode: _Mode.bulkCold),
  // GUARD: the starvation bound.
  _Lane('costly-latency', rows: _largeRows, mode: _Mode.costlyLatency),
  // CONTROLS: idle pool, no waiter ever parks.
  _Lane(
    'point1',
    rows: 2000,
    selectSql: _pointSql,
    selectParams: [17],
    expectRows: 1,
    repeats: 200,
  ),
  _Lane('int20-10k', rows: 10000, columns: 20),
  _Lane(
    'concurrent8-cheap',
    rows: 2000,
    selectSql: _pointSql,
    expectRows: 1,
    repeats: 8,
    mode: _Mode.concurrent,
  ),
];

Future<void> main(List<String> args) async {
  var warmup = _defaultWarmup;
  var samples = _defaultSamples;
  var memory = true;
  String? only;
  for (final arg in args) {
    if (arg.startsWith('--warmup=')) {
      warmup = int.parse(arg.substring('--warmup='.length));
    } else if (arg.startsWith('--samples=')) {
      samples = int.parse(arg.substring('--samples='.length));
    } else if (arg == '--no-memory') {
      memory = false;
    } else if (arg.startsWith('--lane=')) {
      only = arg.substring('--lane='.length);
    } else {
      throw ArgumentError('unknown argument: $arg');
    }
  }

  print('=== reader-pool admission focused harness ===');
  print('warmup=$warmup samples=$samples');
  for (final lane in _lanes) {
    if (only != null && lane.label != only) continue;
    await _runLane(
      lane,
      warmup: warmup,
      samples: samples,
      laneIsolated: only != null,
      memory: memory,
    );
  }
}

Future<void> _runLane(
  _Lane lane, {
  required int warmup,
  required int samples,
  required bool laneIsolated,
  required bool memory,
}) async {
  final temp = await Directory.systemTemp.createTemp('bench_admission_');
  try {
    final db = await resqlite.Database.open('${temp.path}/test.db');

    final String createSql;
    final String insertSql;
    final List<Object?> Function(int row) row;
    if (lane.columns == 0) {
      createSql = _standardCreate;
      insertSql = _standardInsert;
      row = _standardRow;
    } else {
      final cols = [for (var c = 0; c < lane.columns; c++) 'c$c INTEGER'];
      createSql =
          'CREATE TABLE items(id INTEGER PRIMARY KEY, ${cols.join(', ')})';
      final names = [for (var c = 0; c < lane.columns; c++) 'c$c'].join(', ');
      final placeholders = List.filled(lane.columns, '?').join(', ');
      insertSql = 'INSERT INTO items($names) VALUES ($placeholders)';
      row = (r) => [for (var c = 0; c < lane.columns; c++) r * 31 + c];
    }
    await db.execute(createSql);

    for (var start = 0; start < lane.rows; start += 500) {
      final end = start + 500 < lane.rows ? start + 500 : lane.rows;
      await db.executeBatch(insertSql, [
        for (var r = start; r < end; r++) row(r),
      ]);
    }

    // Warmup doubles as arming: a statement is not classified cheap until the
    // pool has watched it return rows at least once, so a lane measured without
    // warmup would measure the cost-blind path in both arms.
    for (var i = 0; i < warmup; i++) {
      await _sample(db, lane);
    }

    final probe = memory ? MemoryProbe.start() : null;
    final values = <int>[];
    for (var i = 0; i < samples; i++) {
      final elapsed = await _sample(db, lane);
      values.add(elapsed);
      // Outside the stopwatch: a currentRss read costs ~700 ns.
      probe?.sample();
    }
    final reading = probe?.finish(laneIsolated: laneIsolated);
    await db.close();

    final sorted = [...values]..sort();
    print(
      'shape=${lane.label} '
      'median_us=${_percentile(sorted, 0.50)} '
      'p10_us=${_percentile(sorted, 0.10)} '
      'p90_us=${_percentile(sorted, 0.90)} '
      '${reading == null ? '' : '${reading.format()} '}'
      'samples_us=${values.join(',')}',
    );
  } finally {
    await temp.delete(recursive: true);
  }
}

/// Run one sample of [lane] and return its elapsed microseconds.
///
/// Every mode times only the reads under test. Pool-saturating reads, arming
/// reads, and the drain of anything still outstanding all sit outside the
/// stopwatch, so the number is the latency of the read whose admission changed.
Future<int> _sample(resqlite.Database db, _Lane lane) async {
  final expect = lane.expectRows ?? lane.rows;

  switch (lane.mode) {
    case _Mode.plain:
      final sw = Stopwatch()..start();
      for (var n = 0; n < lane.repeats; n++) {
        _check(
          lane,
          await db.select(lane.selectSql, lane.selectParams),
          expect,
        );
      }
      sw.stop();
      return sw.elapsedMicroseconds;

    case _Mode.underLoad:
      final background = [
        for (var i = 0; i < _poolWidth; i++) db.select(_largeSql),
      ];
      // Only the first read is timed: it is the only one issued into a
      // saturated pool. See [_underLoadTrailingReads].
      final sw = Stopwatch()..start();
      _check(lane, await db.select(lane.selectSql, lane.selectParams), expect);
      sw.stop();
      for (var n = 0; n < _underLoadTrailingReads; n++) {
        _check(
          lane,
          await db.select(lane.selectSql, lane.selectParams),
          expect,
        );
      }
      await Future.wait(background);
      return sw.elapsedMicroseconds;

    case _Mode.mixedQueue:
      // Large reads first so the point reads arrive behind a queue that is
      // already four deep, which is what FIFO admission makes them pay for.
      final large = [
        for (var i = 0; i < _queuedLarge; i++) db.select(_largeSql),
      ];
      final sw = Stopwatch()..start();
      final points = await Future.wait([
        for (var n = 0; n < _queuedPoint; n++)
          db.select(lane.selectSql, lane.selectParams),
      ]);
      sw.stop();
      for (final result in points) {
        _check(lane, result, expect);
      }
      await Future.wait(large);
      return sw.elapsedMicroseconds;

    case _Mode.bulkMixed:
      // One point read first: it is what arms the reservation, since a pool
      // that has not seen a cheap read recently does not hold a worker back.
      await db.select(_pointSql, const [17]);
      final sw = Stopwatch()..start();
      final results = await Future.wait([
        for (var i = 0; i < _poolWidth; i++) db.select(_largeSql),
      ]);
      sw.stop();
      for (final result in results) {
        _check(lane, result, expect);
      }
      return sw.elapsedMicroseconds;

    case _Mode.bulkCold:
      final sw = Stopwatch()..start();
      final results = await Future.wait([
        for (var i = 0; i < _poolWidth; i++) db.select(_largeSql),
      ]);
      sw.stop();
      for (final result in results) {
        _check(lane, result, expect);
      }
      return sw.elapsedMicroseconds;

    case _Mode.costlyLatency:
      // The point reads are issued first and keep arriving, so the large read
      // spends its whole wait behind statements the candidate prefers. The
      // sample is the large read's own latency, which is what the skip bound
      // has to keep finite.
      final cheap = [
        for (var i = 0; i < _starvationCheapReads; i++)
          db.select(_pointSql, [17 + (i % 8)]),
      ];
      final sw = Stopwatch()..start();
      final result = await db.select(_largeSql);
      sw.stop();
      _check(lane, result, expect);
      await Future.wait(cheap);
      return sw.elapsedMicroseconds;

    case _Mode.concurrent:
      final sw = Stopwatch()..start();
      for (var round = 0; round < _concurrentRounds; round++) {
        final results = await Future.wait([
          for (var n = 0; n < lane.repeats; n++)
            db.select('SELECT * FROM items WHERE id = ? -- c$n', [17 + n]),
        ]);
        for (final result in results) {
          _check(lane, result, expect);
        }
      }
      sw.stop();
      return sw.elapsedMicroseconds;
  }
}

void _check(_Lane lane, List<Map<String, Object?>> result, int expect) {
  if (result.length != expect) {
    throw StateError(
      'lane ${lane.label} returned ${result.length} rows, want $expect',
    );
  }
}

int _percentile(List<int> sorted, double percentile) =>
    sorted[((sorted.length - 1) * percentile).round()];
