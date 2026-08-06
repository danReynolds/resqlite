// ignore_for_file: avoid_print
//
// Focused A/B harness for [EXP-260]: should `decodeQuery`'s result buffer be
// sized from the row count the same SQL last returned?
//
// `decodeQuery` allocates `List<Object?>.filled(colCount * 256, ...)` and
// doubles it whenever a result outgrows it. Doubling copies the whole buffer
// each time, so a result that overshoots the initial size by 2^k pays roughly
// one extra full-buffer copy in total — element by element, with a store
// barrier per slot, into a fresh multi-megabyte array. [EXP-251] put Dart
// result construction at 39-63% of worker wall on large reads without
// splitting out how much of it was that growth.
//
// The candidate remembers, on the main isolate, how many rows each SQL has
// been returning, and sends that with the request so the worker's *first*
// growth jumps straight to the right size instead of doubling its way there.
// The initial allocation is untouched ([EXP-067] measured that shrinking it
// regresses small queries), so a result that never overflows it runs exactly
// the code it runs today.
//
// Lanes:
//
//   int20-10k / int4-5k — PRIMARY. [EXP-251]'s integer shapes, where the
//     buffer is pure Smi slots and growth is the dominant Dart-side cost.
//   mixed6-10k / mixed6-1k — PRIMARY. The repo's canonical 6-column product
//     row, at a row count that overshoots the initial allocation by 39x and by
//     4x respectively.
//   mixed6-200 / point1 — CONTROL *for exp 260*, PRIMARY for exp 264 (see the
//     second block below). Both return fewer rows than the initial buffer
//     holds, so neither ever reaches exp 260's growth path and the
//     decode loop runs byte-identical code in both arms. What they still carry
//     is the pool's per-request bookkeeping, which is the whole cost a small
//     query pays for this. Per the JOURNAL lesson from exp 248 these lanes are
//     the harness's own floor; per exp 254's, a same-sign move across the order
//     flip means the two binaries carry a layout offset and no lane is
//     trustworthy. `point1` times 200 executions per sample because a single
//     point read is a handful of microseconds, where a 1 us stopwatch tick
//     swamps the effect being measured.
//   mispredict-shrink / mispredict-mid — GUARDS. The hint's failure mode is
//     over-allocation: a SQL whose row count swings between executions sizes
//     its buffer for the larger result and throws the excess away. Both lanes
//     run the same `LIMIT ?` statement at 8000 rows (untimed) before each timed
//     sample. `mispredict-shrink` times a 50-row execution behind six 8000-row
//     ones — small enough never to overflow the initial buffer, so it proves
//     the hint cannot inflate a small result no matter how saturated it is.
//     `mispredict-mid` times a 300-row execution in strict alternation — large
//     enough that the hint *is* consulted, so it tests the rule that picks it.
//
// [EXP-264] then took the other end of the same buffer: the *initial*
// allocation, which exp 260 deliberately left alone. `decodeQuery` sizes it at
// `colCount * 256` no matter what the statement returns, so a one-row point
// read allocates and zero-fills 256 rows of slots and throws all but one away.
// The candidate shrinks that allocation — never grows it — for a statement
// whose last two executions both fit, reading the same `RowSizeMemory` but the
// *larger* of the two row counts, clamped at 256 rows. The lane roles invert:
//
//   point1 / point1-wide20 / mixed6-20 / mixed6-200 — PRIMARY for exp 264.
//     Results small enough for the initial allocation to be sized down.
//     `point1-wide20` carries the widest projection, where the fixed
//     allocation wastes the most.
//   int20-10k / int4-5k / mixed6-10k / mixed6-1k — CONTROL for exp 264. All
//     clamp back to the 256-row default, so their initial allocation is
//     unchanged and they read the per-binary layout offset directly (exp 254's
//     lesson).
//   mispredict-shrink / mispredict-mid — GUARD for exp 264 as well: a statement
//     whose row count swings between executions must not be sized down at all.
//   undershoot-jump — GUARD, exp 264's kill lane. The only lane where the
//     initial allocation is sized small and the result then arrives large.
//
// Usage:
//   dart run benchmark/experiments/select_rows_presize.dart \
//     [--warmup=10] [--samples=31] [--lane=int20-10k]
//
// Emits one `shape=... median_us=... samples_us=...` line per lane, so two
// worktree runs can be paired into `benchmark/ab_drift_check.dart` input.
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;

import '../shared/memory_probe.dart';

const _defaultWarmup = 10;
const _defaultSamples = 31;

/// Default number of untimed executions run before each timed sample on a
/// mispredict lane.
const _defaultPoisonWidth = 1;

final class _Lane {
  /// A lane whose table is `id INTEGER PRIMARY KEY` plus [columns] generated
  /// columns all of one affinity — the synthetic width/row-count sweeps.
  const _Lane(
    this.label,
    this.columns,
    this.rows,
    this.cell, {
    this.selectSql = 'SELECT * FROM items',
    this.selectParams = const [],
    this.expectRows,
    this.repeats = 1,
  }) : createSql = null,
       insertSql = null,
       row = null,
       poisonParams = null,
       poisonWidth = _defaultPoisonWidth;

  /// A lane that declares its own schema verbatim, so it can reproduce a
  /// canonical shape rather than approximate one.
  const _Lane.explicit(
    this.label,
    this.rows, {
    required String this.createSql,
    required String this.insertSql,
    required List<Object?> Function(int row) this.row,
    this.selectSql = 'SELECT * FROM items',
    this.selectParams = const [],
    this.poisonParams,
    this.poisonWidth = _defaultPoisonWidth,
    this.expectRows,
    this.repeats = 1,
  }) : columns = 0,
       cell = null;

  final String label;
  final int columns;

  /// Rows seeded into the table.
  final int rows;

  /// Cell value for column [col] of row [row]. Null on explicit lanes.
  final Object? Function(int row, int col)? cell;

  final String? createSql;
  final String? insertSql;
  final List<Object?> Function(int row)? row;

  /// The timed statement and its parameters.
  final String selectSql;
  final List<Object?> selectParams;

  /// Parameters for untimed executions of [selectSql] run before every timed
  /// sample. Used by the mispredict guards to leave the row hint pointing at a
  /// much larger result than the timed query returns.
  final List<Object?>? poisonParams;

  /// How many untimed executions run before each timed sample. 1 gives a
  /// strict large/small alternation; a wider run leaves the hint saturated at
  /// the large end.
  final int poisonWidth;

  /// Rows the timed statement returns, when that differs from [rows].
  final int? expectRows;

  /// Executions inside one timed sample. A point read runs in single-digit
  /// microseconds, where a 1 us stopwatch tick is a 16% swing; batching them
  /// puts the control lane's resolution on the same footing as the others.
  /// Reported medians are per sample, not per execution.
  final int repeats;
}

// The repo's canonical mixed row: 6 columns total (`id INTEGER PRIMARY KEY`,
// 4 TEXT, 1 REAL). Copied verbatim from `benchmark/shared/seeder.dart`, which
// is the source of truth — the neighbouring `select_rows_text_decode.dart` and
// `select_rows_step_row_ffi.dart` keep their own copies the same way, rather
// than importing the seeder and dragging the peer-library imports into a
// focused harness.
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

final _lanes = <_Lane>[
  _Lane('int20-10k', 20, 10000, (r, c) => r * 31 + c),
  _Lane('int4-5k', 4, 5000, (r, c) => r * 31 + c),
  _Lane.explicit(
    'mixed6-10k',
    10000,
    createSql: _standardCreate,
    insertSql: _standardInsert,
    row: _standardRow,
  ),
  _Lane.explicit(
    'mixed6-1k',
    1000,
    createSql: _standardCreate,
    insertSql: _standardInsert,
    row: _standardRow,
  ),
  // CONTROL: 200 rows fit inside the initial buffer, so the growth path — and
  // with it the whole candidate — is unreachable.
  _Lane.explicit(
    'mixed6-200',
    200,
    createSql: _standardCreate,
    insertSql: _standardInsert,
    row: _standardRow,
  ),
  // CONTROL for exp 260, PRIMARY for exp 264: a point read, the shape most
  // sensitive to per-request overhead.
  _Lane.explicit(
    'point1',
    2000,
    createSql: _standardCreate,
    insertSql: _standardInsert,
    row: _standardRow,
    selectSql: 'SELECT * FROM items WHERE id = ?',
    selectParams: [17],
    expectRows: 1,
    repeats: 200,
  ),
  // PRIMARY (exp 264): the same point read on a 20-column row. The fixed
  // initial allocation is `colCount * 256` slots, so what a one-row result
  // wastes scales with the projection width — this is the widest shape the
  // harness carries and therefore the largest saving available.
  _Lane(
    'point1-wide20',
    20,
    2000,
    (r, c) => r * 31 + c,
    selectSql: 'SELECT * FROM items WHERE id = ?',
    selectParams: [17],
    expectRows: 1,
    repeats: 200,
  ),
  // PRIMARY (exp 264): a 20-row page of the canonical row — the shape a paged
  // list view and most reactive streams actually read.
  _Lane.explicit(
    'mixed6-20',
    2000,
    createSql: _standardCreate,
    insertSql: _standardInsert,
    row: _standardRow,
    selectSql: 'SELECT * FROM items LIMIT 20',
    expectRows: 20,
    repeats: 50,
  ),
  // GUARD: the hint is left pointing at 10000 rows before every timed 50-row
  // execution of the same statement. 50 rows never overflow the initial buffer,
  // so a saturated hint must still cost nothing.
  _Lane.explicit(
    'mispredict-shrink',
    10000,
    createSql: _standardCreate,
    insertSql: _standardInsert,
    row: _standardRow,
    selectSql: 'SELECT * FROM items LIMIT ?',
    selectParams: [50],
    poisonParams: [8000],
    poisonWidth: 6,
    expectRows: 50,
  ),
  // GUARD: the same statement alternating between a 300-row and an 8000-row
  // result. Unlike mispredict-shrink the timed query does overflow the initial
  // buffer, so the hint is consulted — this is the lane that tests the hint
  // *rule* rather than the initial allocation.
  _Lane.explicit(
    'mispredict-mid',
    10000,
    createSql: _standardCreate,
    insertSql: _standardInsert,
    row: _standardRow,
    selectSql: 'SELECT * FROM items LIMIT ?',
    selectParams: [300],
    poisonParams: [8000],
    expectRows: 300,
  ),
  // GUARD (exp 264): the mirror image of the two lanes above, and the only
  // lane that can expose a shrunken initial allocation's failure mode. Eight
  // untimed 20-row executions run before each timed sample, which is enough to
  // leave every reader worker's local memory sized for 25 rows; the timed
  // execution then returns 5,000 rows and has to double its way up from there.
  // The pool's growth hint cannot rescue it either — that hint takes the
  // *smaller* of the statement's last two row counts, so the alternation pins
  // it at the 20-row leg. This is the honest worst case for exp 264: the
  // penalty it measures is what a statement pays the one time it jumps from
  // consistently tiny to large.
  _Lane.explicit(
    'undershoot-jump',
    10000,
    createSql: _standardCreate,
    insertSql: _standardInsert,
    row: _standardRow,
    selectSql: 'SELECT * FROM items LIMIT ?',
    selectParams: [5000],
    poisonParams: [20],
    poisonWidth: 8,
    expectRows: 5000,
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
      // Control: the same binary with RSS sampling off, to show the sampling
      // itself does not move the wall numbers it sits beside.
      memory = false;
    } else if (arg.startsWith('--lane=')) {
      only = arg.substring('--lane='.length);
    } else {
      throw ArgumentError('unknown argument: $arg');
    }
  }

  print('=== select() result-buffer pre-sizing focused harness ===');
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
  final temp = await Directory.systemTemp.createTemp('bench_presize_');
  try {
    final db = await resqlite.Database.open('${temp.path}/test.db');

    final String createSql;
    final String insertSql;
    final List<Object?> Function(int row) row;
    if (lane.createSql != null) {
      createSql = lane.createSql!;
      insertSql = lane.insertSql!;
      row = lane.row!;
    } else {
      final cols = [for (var c = 0; c < lane.columns; c++) 'c$c INTEGER'];
      createSql =
          'CREATE TABLE items(id INTEGER PRIMARY KEY, ${cols.join(', ')})';
      final names = [for (var c = 0; c < lane.columns; c++) 'c$c'].join(', ');
      final placeholders = List.filled(lane.columns, '?').join(', ');
      insertSql = 'INSERT INTO items($names) VALUES ($placeholders)';
      row = (r) => [for (var c = 0; c < lane.columns; c++) lane.cell!(r, c)];
    }
    await db.execute(createSql);

    const chunk = 500;
    for (var start = 0; start < lane.rows; start += chunk) {
      final end = start + chunk < lane.rows ? start + chunk : lane.rows;
      await db.executeBatch(insertSql, [
        for (var r = start; r < end; r++) row(r),
      ]);
    }

    final expect = lane.expectRows ?? lane.rows;
    for (var i = 0; i < warmup; i++) {
      await _poison(db, lane);
      await db.select(lane.selectSql, lane.selectParams);
    }

    // Started after seeding and warmup, which sets the baseline for
    // `rss_start_mb` / `rss_growth_mb` only. `max_rss_mb` is a process-lifetime
    // high-water and still includes whatever seeding and warmup peaked at — it
    // is comparable between arms because both pay the same setup, not because
    // the setup is excluded.
    final probe = memory ? MemoryProbe.start() : null;
    final values = <int>[];
    for (var i = 0; i < samples; i++) {
      await _poison(db, lane);
      final sw = Stopwatch()..start();
      for (var n = 0; n < lane.repeats; n++) {
        final result = await db.select(lane.selectSql, lane.selectParams);
        if (result.length != expect) {
          throw StateError(
            'lane ${lane.label} returned ${result.length} rows, want $expect',
          );
        }
      }
      sw.stop();
      values.add(sw.elapsedMicroseconds);
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

Future<void> _poison(resqlite.Database db, _Lane lane) async {
  final params = lane.poisonParams;
  if (params == null) return;
  await Future.wait([
    for (var i = 0; i < lane.poisonWidth; i++)
      db.select(lane.selectSql, params),
  ]);
}

int _percentile(List<int> sorted, double percentile) =>
    sorted[((sorted.length - 1) * percentile).round()];
