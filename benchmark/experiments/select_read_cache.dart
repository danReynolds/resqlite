// ignore_for_file: avoid_print
//
// Focused A/B harness for a main-isolate `select()` result cache
// ([EXP-270](../../experiments/270-read-result-cache.md)).
//
// The cache was REJECTED, and on current main every lane below runs the ordinary
// worker path, so the two arms are identical. This remains mechanism evidence
// for how much of a hot read is the isolate round trip, and the guard set for
// any future work that remembers a read result instead of re-executing it —
// but run `select_cache_foreign_writer.dart` first. It is the lane that killed
// exp 270 and no timing here can see what it sees.
//
// Every read resqlite serves crosses to a reader isolate and back, and exp 265
// priced that hop at most of a hot point read. Exp 269 tried to remove it by
// running the statement on the calling isolate and was rejected: arbitrary
// SQLite work cannot be bounded there. Remembering a result the database has
// not changed removes the same hop while running no SQLite at all, so the lanes
// below ask a different question — not "what does the hop cost" but "what does
// remembering cost when it does not pay off".
//
// That is where the interesting lanes are. The hit lanes only confirm a
// mechanism that has already been measured twice. The lanes that decide the
// experiment are the ones where the cache can only lose:
//
//   point1-repeat / point1-wide20   PRIMARY. The same one-row read, over and
//     over, with nothing writing. Everything after the first execution is a map
//     lookup. This is the ceiling, not a representative workload.
//   point1-params                   PRIMARY. Eight ids cycled through one
//     statement, so the cache holds eight entries and every read still hits.
//     Closer to a list screen re-reading rows it has already shown.
//   page20-repeat                   PRIMARY. A 20-row page repeated; shows
//     whether the win tracks the hop (flat) or the result size (grows).
//   read-write-alternate            GUARD, and the one that can kill the idea.
//     One write, one read, forever. Every read misses, every write invalidates,
//     and the entry is stored only to be dropped. A cache is pure overhead here
//     and this is what an actively-edited screen looks like.
//   churn-unique                    GUARD. Every read is a statement never seen
//     before, so nothing can ever hit and every read pays the describe. The
//     adversarial lane exp 267 taught: a cache's cost has to be measured where
//     no cache of any size could help.
//   uncacheable-fn                  GUARD. `random()` puts this statement on
//     the permanent refusal list after one execution, so the lane measures the
//     steady-state cost of *being refused* — one map lookup per read.
//   mixed6-1k                       GUARD. 1,000 rows is past the retention cap,
//     so the statement is refused after its first result and every later read
//     stops at the description lookup.
//   concurrent8                     GUARD. A write, then eight identical point
//     reads issued together. None of the eight can see another's result, so all
//     eight miss and all eight dispatch: the cache deliberately does not
//     coalesce in-flight duplicates, and this lane is where that costs.
//
// Emits one `shape=... median_us=... samples_us=...` line per lane, so two
// worktree runs can be paired into `benchmark/ab_drift_check.dart` input.
//
// Usage:
//   dart run benchmark/experiments/select_read_cache.dart \
//     [--warmup=10] [--samples=31] [--lane=point1-repeat] [--no-memory]
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;

import '../shared/memory_probe.dart';

const _defaultWarmup = 10;
const _defaultSamples = 31;

/// Distinct ids the `point1-params` lane cycles through. Under the retention
/// cap, so every one of them stays resident.
const int _paramCycle = 8;

/// Concurrent reads issued as one group, and groups per sample.
const int _concurrentReads = 8;
const int _concurrentRounds = 10;

enum _Mode {
  /// Execute the lane's statement [_Lane.repeats] times.
  plain,

  /// Execute the lane's statement [_Lane.repeats] times, cycling the bound id
  /// over [_paramCycle] values.
  cycledParams,

  /// Alternate one write and one read [_Lane.repeats] times. Both are timed:
  /// the invalidation the write triggers is part of what a cache costs.
  readWrite,

  /// Execute a statement never seen before on every read.
  churn,

  /// Invalidate, then issue [_concurrentReads] identical point reads together.
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
  final int rows;

  /// Generated INTEGER columns beside `id`, or 0 for the canonical mixed row.
  final int columns;

  final String selectSql;
  final List<Object?> selectParams;
  final int? expectRows;
  final int repeats;
  final _Mode mode;
}

// The repo's canonical mixed row: `id INTEGER PRIMARY KEY`, 4 TEXT, 1 REAL.
// Copied verbatim from `benchmark/shared/seeder.dart` the way the neighbouring
// focused harnesses do, rather than importing the seeder and dragging its
// peer-library imports into a focused binary.
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
  _Lane(
    'point1-repeat',
    rows: 2000,
    selectSql: 'SELECT * FROM items WHERE id = ?',
    selectParams: [17],
    expectRows: 1,
    repeats: 200,
  ),
  _Lane(
    'point1-wide20',
    rows: 2000,
    columns: 20,
    selectSql: 'SELECT * FROM items WHERE id = ?',
    selectParams: [17],
    expectRows: 1,
    repeats: 200,
  ),
  _Lane(
    'point1-params',
    rows: 2000,
    selectSql: 'SELECT * FROM items WHERE id = ?',
    expectRows: 1,
    repeats: 200,
    mode: _Mode.cycledParams,
  ),
  _Lane(
    'page20-repeat',
    rows: 2000,
    selectSql: 'SELECT * FROM items LIMIT 20',
    expectRows: 20,
    repeats: 50,
  ),
  // GUARD: the cache can only lose here.
  _Lane(
    'read-write-alternate',
    rows: 2000,
    selectSql: 'SELECT * FROM items WHERE id = ?',
    selectParams: [17],
    expectRows: 1,
    repeats: 20,
    mode: _Mode.readWrite,
  ),
  // GUARD: nothing ever repeats, so every read pays the describe.
  _Lane(
    'churn-unique',
    rows: 2000,
    selectSql: 'SELECT * FROM items WHERE id = ?',
    selectParams: [17],
    expectRows: 1,
    repeats: 20,
    mode: _Mode.churn,
  ),
  // GUARD: refused for good after one execution.
  _Lane(
    'uncacheable-fn',
    rows: 2000,
    selectSql: 'SELECT random() AS r, id FROM items WHERE id = ?',
    selectParams: [17],
    expectRows: 1,
    repeats: 200,
  ),
  // GUARD: past the retention cap, so described once and refused by size.
  _Lane('mixed6-1k', rows: 1000, repeats: 1),
  // GUARD: eight in flight at once, none of which can see another's result.
  _Lane(
    'concurrent8',
    rows: 2000,
    selectSql: 'SELECT * FROM items WHERE id = ?',
    selectParams: [17],
    expectRows: 1,
    mode: _Mode.concurrent,
  ),
];

/// Makes every `churn-unique` statement a distinct SQL string. A trailing
/// comment changes the text without changing the plan.
int _churnSeq = 0;

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

  print('=== select() read-cache focused harness ===');
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
  final temp = await Directory.systemTemp.createTemp('bench_read_cache_');
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

    // Warmup doubles as arming: a statement's first execution is the one that
    // describes it, so a lane measured without warmup would charge the describe
    // to the candidate and nothing to the baseline.
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

    case _Mode.cycledParams:
      final sw = Stopwatch()..start();
      for (var n = 0; n < lane.repeats; n++) {
        _check(
          lane,
          await db.select(lane.selectSql, [17 + (n % _paramCycle)]),
          expect,
        );
      }
      sw.stop();
      return sw.elapsedMicroseconds;

    case _Mode.readWrite:
      final sw = Stopwatch()..start();
      for (var n = 0; n < lane.repeats; n++) {
        await db.execute('UPDATE items SET value = value + 1 WHERE id = ?', [
          17,
        ]);
        _check(
          lane,
          await db.select(lane.selectSql, lane.selectParams),
          expect,
        );
      }
      sw.stop();
      return sw.elapsedMicroseconds;

    case _Mode.churn:
      final sw = Stopwatch()..start();
      for (var n = 0; n < lane.repeats; n++) {
        final sql = '${lane.selectSql} -- u${_churnSeq++}';
        _check(lane, await db.select(sql, lane.selectParams), expect);
      }
      sw.stop();
      return sw.elapsedMicroseconds;

    case _Mode.concurrent:
      final sw = Stopwatch()..start();
      for (var round = 0; round < _concurrentRounds; round++) {
        // Without this the first round fills the entry and the other nine are
        // pure hits, which is the wrong question. Invalidating first puts the
        // lane where the design is weakest: eight identical reads are in flight
        // together, none of them can see another's result, and nothing
        // coalesces them.
        await db.execute('UPDATE items SET value = value + 1 WHERE id = ?', [
          17,
        ]);
        final results = await Future.wait([
          for (var n = 0; n < _concurrentReads; n++)
            db.select(lane.selectSql, lane.selectParams),
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
