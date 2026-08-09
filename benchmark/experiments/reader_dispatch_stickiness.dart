// ignore_for_file: avoid_print
//
// Focused A/B harness for *which* reader worker a read is dispatched to
// ([EXP-266]).
//
// `ReaderPool._dispatch` scans the worker slots starting at a cursor it
// advances on every attempt, so consecutive reads deliberately rotate across
// the whole pool even when the pool is completely idle. Nothing is shared
// between workers: each is its own isolate, with its own SQLite connection and
// page cache, its own C statement-cache slot, its own Dart schema cache and
// cell buffer, its own heap — and, the term this harness is really aimed at,
// its own OS thread. A sequentially awaited read loop under round-robin
// therefore hands each request to a different, recently-idle thread.
//
// The candidate starts the scan at the slot that served the *previous* read
// instead of the next one. A busy preferred slot still walks forward, so a
// saturated pool spreads exactly as before; only an idle pool's choice changes.
//
// Lanes, and what each is for:
//
//   first4-newsql        Four sequential reads of a SQL string no worker has
//   first8-newsql        ever seen, timed from the first. PRIMARY. Round-robin
//   first32-newsql       makes each of the four workers prepare the statement,
//     build its schema and warm its page cache; stickiness makes one worker do
//     it once. This is the shape an application actually has — a screen issues
//     a handful of reads per statement — and the one a steady-state lane of
//     8,000 identical reads cannot see, because by then every worker is warm.
//     The three widths bracket where the fixed warm-up stops mattering.
//   point1               Sequentially awaited point reads of one long-warm
//     statement — steady state, where only per-request locality is left.
//   point1-wide20        The same, 21 columns, so a larger reply crosses.
//   mixed6-20            A 20-row page, the shape a paged list view reads.
//   mixed6-1k            1,000 rows: per-request cost is now a small fraction,
//     so the effect should shrink here if the mechanism is what it claims.
//   alternating-sql      Two distinct statements alternating, sequentially. Any
//     per-worker warm state (schema cache, C statement cache, page cache) has
//     to serve two SQLs on one worker instead of one SQL on four.
//   bytes-first8-newsql  first8-newsql through `selectBytes`, which opts out of
//     stickiness. GUARD: must read neutral, because both arms round-robin it.
//   conc4                Four concurrent reads awaited together — exactly pool
//     size. GUARD: the pool must still hand these to four different workers.
//   conc8                Eight concurrent reads, so dispatch parks. GUARD:
//     backpressure and wake ordering must be unchanged.
//   mixed6-10k           60,000 slots, above `sacrificeSlotThreshold`, so every
//     timed read ends its worker and respawns it. GUARD: the preferred slot is
//     the one that keeps dying, and the scan must fall through cleanly.
//
// Usage:
//   dart run benchmark/experiments/reader_dispatch_stickiness.dart \
//     [--warmup=10] [--samples=41] [--lane=point1]
//
// Emits one `shape=... median_us=... samples_us=...` line per lane, so two
// worktree runs pair into `benchmark/ab_drift_check.dart` input.
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;

import '../shared/memory_probe.dart';

const _defaultWarmup = 10;
const _defaultSamples = 41;

final class _Lane {
  const _Lane(
    this.label, {
    required this.rows,
    required this.selectSql,
    this.selectParams = const [],
    this.altSql,
    this.altParams = const [],
    this.altExpectRows,
    required this.expectRows,
    this.repeats = 1,
    this.concurrency = 1,
    this.wide = false,
    this.freshSql = false,
    this.bytes = false,
  });

  final String label;

  /// Rows seeded into the table.
  final int rows;

  /// The timed statement and its parameters.
  final String selectSql;
  final List<Object?> selectParams;

  /// A second statement interleaved with [selectSql], for the lane that asks
  /// whether one worker can hold two SQLs' warm state as cheaply as four
  /// workers hold one each.
  final String? altSql;
  final List<Object?> altParams;
  final int? altExpectRows;

  final int expectRows;

  /// Executions inside one timed sample. A point read runs in single-digit
  /// microseconds, where a 1 us stopwatch tick is a 16% swing.
  final int repeats;

  /// Reads issued together without awaiting between them. 1 is the sequential
  /// shape the candidate targets; anything above pool size makes dispatch park.
  final int concurrency;

  /// Seed the 21-column INTEGER table instead of the canonical mixed row.
  final bool wide;

  /// Read through `selectBytes` instead of `select`. That path opts out of
  /// stickiness — its per-connection `json_buf` is only reclaimed by a later,
  /// smaller read on the same connection — so a bytes lane is a guard that the
  /// opt-out really is the pre-266 round-robin and not a slow middle ground.
  final bool bytes;

  /// Give every timed sample its own never-before-seen SQL string, so the
  /// sample measures a statement's first [repeats] executions rather than its
  /// ten-thousandth. A trailing comment changes the text without changing the
  /// plan, so the only thing a fresh string costs is the warm-up itself.
  final bool freshSql;
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

const _wideColumns = 20;

final _lanes = <_Lane>[
  // PRIMARY: a statement's first few executions, which is what an application
  // screen actually issues. Under round-robin all four workers pay the
  // prepare / schema-build / page-warm; under stickiness one worker pays once.
  _Lane(
    'first4-newsql',
    rows: 2000,
    selectSql: 'SELECT * FROM items WHERE id = ?',
    selectParams: [17],
    expectRows: 1,
    repeats: 4,
    freshSql: true,
  ),
  _Lane(
    'first8-newsql',
    rows: 2000,
    selectSql: 'SELECT * FROM items WHERE id = ?',
    selectParams: [17],
    expectRows: 1,
    repeats: 8,
    freshSql: true,
  ),
  // CONTROL for the pair above: by 32 executions the fixed warm-up is spread
  // thin enough that the lane should read close to steady state.
  _Lane(
    'first32-newsql',
    rows: 2000,
    selectSql: 'SELECT * FROM items WHERE id = ?',
    selectParams: [17],
    expectRows: 1,
    repeats: 32,
    freshSql: true,
  ),
  // GUARD: the same shape through the path that keeps round-robin.
  _Lane(
    'bytes-first8-newsql',
    rows: 2000,
    selectSql: 'SELECT * FROM items WHERE id = ?',
    selectParams: [17],
    expectRows: 1,
    repeats: 8,
    freshSql: true,
    bytes: true,
  ),
  _Lane(
    'point1',
    rows: 2000,
    selectSql: 'SELECT * FROM items WHERE id = ?',
    selectParams: [17],
    expectRows: 1,
    repeats: 200,
  ),
  _Lane(
    'point1-wide20',
    rows: 2000,
    wide: true,
    selectSql: 'SELECT * FROM items WHERE id = ?',
    selectParams: [17],
    expectRows: 1,
    repeats: 200,
  ),
  _Lane(
    'mixed6-20',
    rows: 2000,
    selectSql: 'SELECT * FROM items LIMIT 20',
    expectRows: 20,
    repeats: 50,
  ),
  _Lane(
    'mixed6-1k',
    rows: 2000,
    selectSql: 'SELECT * FROM items LIMIT 1000',
    expectRows: 1000,
    repeats: 5,
  ),
  _Lane(
    'alternating-sql',
    rows: 2000,
    selectSql: 'SELECT * FROM items WHERE id = ?',
    selectParams: [17],
    expectRows: 1,
    altSql: 'SELECT id, name FROM items WHERE category = ? LIMIT 10',
    altParams: ['category_3'],
    altExpectRows: 10,
    repeats: 100,
  ),
  // GUARD: exactly pool size, issued together.
  _Lane(
    'conc4',
    rows: 2000,
    selectSql: 'SELECT * FROM items WHERE id = ?',
    selectParams: [17],
    expectRows: 1,
    repeats: 50,
    concurrency: 4,
  ),
  // GUARD: twice pool size, so dispatch parks on `_dispatchWaiters`.
  _Lane(
    'conc8',
    rows: 2000,
    selectSql: 'SELECT * FROM items WHERE id = ?',
    selectParams: [17],
    expectRows: 1,
    repeats: 25,
    concurrency: 8,
  ),
  // GUARD: 10,000 x 6 = 60,000 slots, above `sacrificeSlotThreshold`, so each
  // timed read ends its worker. The preferred slot is the one that keeps dying.
  _Lane(
    'mixed6-10k',
    rows: 10000,
    selectSql: 'SELECT * FROM items',
    expectRows: 10000,
  ),
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

  print('=== reader dispatch stickiness focused harness ===');
  print('warmup=$warmup samples=$samples');
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
  final temp = await Directory.systemTemp.createTemp('bench_dispatch_');
  try {
    final db = await resqlite.Database.open('${temp.path}/test.db');

    final String createSql;
    final String insertSql;
    final List<Object?> Function(int row) row;
    if (lane.wide) {
      final cols = [for (var c = 0; c < _wideColumns; c++) 'c$c INTEGER'];
      createSql =
          'CREATE TABLE items(id INTEGER PRIMARY KEY, ${cols.join(', ')})';
      final names = [for (var c = 0; c < _wideColumns; c++) 'c$c'].join(', ');
      final placeholders = List.filled(_wideColumns, '?').join(', ');
      insertSql = 'INSERT INTO items($names) VALUES ($placeholders)';
      row = (r) => [for (var c = 0; c < _wideColumns; c++) r * 31 + c];
    } else {
      createSql = _standardCreate;
      insertSql = _standardInsert;
      row = _standardRow;
    }
    await db.execute(createSql);

    const chunk = 500;
    for (var start = 0; start < lane.rows; start += chunk) {
      final end = start + chunk < lane.rows ? start + chunk : lane.rows;
      await db.executeBatch(insertSql, [
        for (var r = start; r < end; r++) row(r),
      ]);
    }

    for (var i = 0; i < warmup; i++) {
      await _sample(db, lane);
    }

    // Stickiness concentrates a statement's warm state on one worker instead of
    // duplicating it across four, so peak RSS is expected to fall or hold; this
    // is here to catch the reverse ([EXP-261](../../experiments/261-focused-memory-guard.md)).
    final probe = MemoryProbe.start();
    final values = <int>[];
    for (var i = 0; i < samples; i++) {
      final sql = lane.freshSql ? '${lane.selectSql} -- f${_freshSeq++}' : null;
      final sw = Stopwatch()..start();
      await _sample(db, lane, sql);
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

/// Monotonic counter making every fresh-SQL sample a distinct statement.
int _freshSeq = 0;

/// One timed sample: [_Lane.repeats] units of the lane's work, against [sql]
/// when the lane mints a fresh statement per sample and [_Lane.selectSql]
/// otherwise.
Future<void> _sample(resqlite.Database db, _Lane lane, [String? sql]) async {
  if (sql == null && lane.freshSql) {
    sql = '${lane.selectSql} -- w${_freshSeq++}';
  }
  for (var n = 0; n < lane.repeats; n++) {
    if (sql == null) {
      await _once(db, lane);
    } else if (lane.bytes) {
      _check(
        lane,
        (await db.selectBytes(sql, lane.selectParams)).rowCount,
        lane.expectRows,
      );
    } else {
      _check(
        lane,
        (await db.select(sql, lane.selectParams)).length,
        lane.expectRows,
      );
    }
  }
}

/// One unit of the lane's work: [_Lane.concurrency] reads issued together, or
/// the sequential statement pair on the alternating lane.
Future<void> _once(resqlite.Database db, _Lane lane) async {
  if (lane.concurrency > 1) {
    final results = await Future.wait([
      for (var i = 0; i < lane.concurrency; i++)
        db.select(lane.selectSql, lane.selectParams),
    ]);
    for (final result in results) {
      _check(lane, result.length, lane.expectRows);
    }
    return;
  }

  _check(
    lane,
    (await db.select(lane.selectSql, lane.selectParams)).length,
    lane.expectRows,
  );

  final altSql = lane.altSql;
  if (altSql != null) {
    _check(
      lane,
      (await db.select(altSql, lane.altParams)).length,
      lane.altExpectRows!,
    );
  }
}

void _check(_Lane lane, int got, int want) {
  if (got != want) {
    throw StateError('lane ${lane.label} returned $got rows, want $want');
  }
}

int _percentile(List<int> sorted, double percentile) =>
    sorted[((sorted.length - 1) * percentile).round()];
