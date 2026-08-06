// ignore_for_file: avoid_print
//
// Focused A/B harness for the `select()` result buffer: how it is sized at
// allocation and how it grows ([EXP-260], [EXP-264]).
//
// `decodeQuery` allocates `List<Object?>.filled(colCount * 256, ...)` and doubles
// it whenever a result outgrows it. Both ends cost real time. Doubling copies the
// whole buffer each time, element by element with a store barrier per slot, so a
// result that overshoots by 2^k pays roughly one extra full-buffer copy. And the
// fixed 256-row allocation is mostly waste for a small result — a one-row read of
// a 21-column table zero-fills 5,376 slots to keep 21.
//
// Sizing either end from a per-SQL memory of past row counts is what the lanes
// below gate. The roles invert between the two ends, so each lane is labelled for
// both:
//
//   int20-10k / int4-5k         Integer shapes where the buffer is pure Smi slots
//     and growth dominates the Dart-side cost. Primary for growth; control for
//     the initial allocation, which clamps to the same 256 rows in both arms.
//   mixed6-10k / mixed6-1k      The canonical 6-column product row, overshooting
//     the initial allocation by 39x and 4x. Same roles.
//   mixed6-200                  Fits inside the initial buffer, and sizes to 250
//     rows against 256 — inert for both ends, so it reads the harness floor.
//     Batched 20x per sample: one 200-row read lands near 50 us, where a 1 us
//     tick is 2% and cannot resolve a sub-microsecond effect.
//   point1 / point1-wide20      One row, at 6 and 21 columns. Primary for the
//     initial allocation, where the waste scales with projection width; control
//     for growth, which they never reach. Batched 200x per sample.
//   mixed6-20                   A 20-row page, the shape a paged list view reads.
//   mispredict-shrink / -mid    A `LIMIT ?` statement whose row count swings
//     between 8,000 and a small leg. Guards that a swinging statement is neither
//     over-allocated at the growth step nor sized down at the initial one.
//   undershoot-jump / -mid      A statement that returns thousands after a burst
//     of 20-row executions. Guards the initial allocation's failure mode. The two
//     sit on opposite sides of the doubling chain's landing point (from 25 rows
//     5,000 lands on 6,400 where 256 lands on 8,192, so the shrunken arm wins;
//     3,300 lands on 6,400 against 4,096, so it loses), which is what stops the
//     pair reporting whichever alignment happens to flatter.
//   hint-thrash-fits / -overflows
//     The same read behind 20 or 40 never-before-seen SQL strings, which claim
//     slots in the pool's 32-entry row-size memory. The only lanes exercising
//     more distinct statements than the pool can remember; every other lane uses
//     a handful, so a per-SQL memory can stop working and nothing moves. 20 fits
//     inside the capacity and 40 does not, so the pair separates an eviction
//     policy problem from a capacity one.
//
// Two shape constraints worth keeping. Every timed statement stays below
// `sacrificeSlotThreshold` (32,768 slots) unless the lane is deliberately
// measuring the sacrifice path, because crossing it respawns a reader worker and
// swamps everything else. And any lane whose per-read cost is dominated by other
// allocation — `mixed6-20`'s 80 Strings, say — cannot resolve a fraction of a
// microsecond, so a small effect there is drift, not a result.
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
    this.thrashWidth = 0,
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
       cell = null,
       thrashWidth = 0;

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

  /// Distinct *SQL strings* executed, untimed, before each timed sample.
  ///
  /// Unlike [poisonWidth], which re-executes [selectSql] with different
  /// parameters, each of these is a fresh SQL string that has never been seen
  /// before, so it claims a new slot in `ReaderPool._rowHints` (capacity 32).
  /// This is the only thing in the suite that exercises having more distinct
  /// statements in play than the pool can remember — the gap that let exp 264
  /// widen eviction pressure on exp 260's growth hint without any lane noticing.
  final int thrashWidth;
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
    // See the header: 50 us per read cannot resolve a sub-microsecond effect.
    repeats: 20,
  ),
  // The shape most sensitive to per-request overhead.
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
  // The widest projection the harness carries, so the largest saving available:
  // a one-row result wastes `colCount * 255` slots.
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
  // The shape a paged list view and most reactive streams read.
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
  // Eight untimed 20-row executions before each timed sample leave the pool's
  // memory sized for 25 rows; the timed execution then returns thousands and has
  // to double up from there. The pool's growth hint cannot soften it either — it
  // takes the smaller of the last two row counts, which the alternation pins at
  // the 20-row leg. See the header for why there are two of these.
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
  _Lane.explicit(
    'undershoot-mid',
    10000,
    createSql: _standardCreate,
    insertSql: _standardInsert,
    row: _standardRow,
    selectSql: 'SELECT * FROM items LIMIT ?',
    selectParams: [3300],
    poisonParams: [20],
    poisonWidth: 8,
    expectRows: 3300,
  ),
  // Timed statement is exp 260's int4-5k shape at 25,000 slots, deliberately
  // below `sacrificeSlotThreshold` so a worker respawn cannot swamp the effect.
  // The growth hint is worth ~40% of this read, which is what the filler
  // statements can take away. See the header for what the two widths separate.
  _Lane(
    'hint-thrash-fits',
    4,
    5000,
    (r, c) => r * 31 + c,
    expectRows: 5000,
    thrashWidth: 20,
  ),
  _Lane(
    'hint-thrash-overflows',
    4,
    5000,
    (r, c) => r * 31 + c,
    expectRows: 5000,
    thrashWidth: 40,
  ),
];

/// Monotonic counter making every thrash filler statement a distinct SQL string.
/// A trailing comment changes the text without changing the plan, so a filler
/// costs a prepare and a slot and nothing else.
int _thrashSeq = 0;

/// Execute [width] never-before-seen SQL strings, untimed, so they claim slots
/// in `ReaderPool._rowHints`.
Future<void> _thrash(resqlite.Database db, int width) async {
  for (var i = 0; i < width; i++) {
    await db.select('SELECT id FROM items WHERE id = ? -- f${_thrashSeq++}', [
      1,
    ]);
  }
}

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
      await _thrash(db, lane.thrashWidth);
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
      await _thrash(db, lane.thrashWidth);
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
