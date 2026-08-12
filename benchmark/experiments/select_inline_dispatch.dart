// ignore_for_file: avoid_print
//
// Focused A/B harness for where a `select()` runs ([EXP-265], [EXP-269]).
//
// Both inline-routing candidates were REJECTED, and on current main every lane
// below runs the ordinary worker path. This remains mechanism evidence and a
// partial gate for future read-*routing* work — a different question from
// harnesses that measure only what a read costs rather than where it runs.
//
// Exp 269 adds the three lanes exp 265 named — `blob1-5mb`, `scan-count` and
// `frame-jitter` — but its own rejection shows the set is still incomplete.
// These lanes cover a large result cell, work spread over many VM operations,
// and yielding across a chain of cheap reads. They do not cover work hidden
// inside one SQLite operation, cold preparation, callbacks, or VFS/busy waits.
// Run `select_inline_opaque_work.dart` before trusting a successor. The first
// two lanes here fail against `archive/exp-265`, which is why they remain.
//
// Every read resqlite serves crosses to a reader isolate and back. That hop is
// scheduling, not work: the request is copied to a worker, the worker steps and
// decodes, and the result is copied back. For a large result the copy is the
// dominant term and the pool is earning its keep. For a point read there is
// almost nothing to copy, and the surrounding experiments have said so
// repeatedly without measuring it — exp 264 put a point read at 5-8 us "most of
// which is the isolate round trip", and exps 209/239/258 each closed a candidate
// against a "round-trip floor" no one had priced.
//
// The lanes below price it, by comparing a build that sends every read to a
// worker against one that runs statements it already knows are small on the
// calling isolate.
//
//   point1 / point1-wide20     One row at 6 and 21 columns. Primary: the least
//     work a query can do, so the largest share of the hop. Batched 200x per
//     sample, since one read lands in single-digit microseconds where a 1 us
//     stopwatch tick is a 16% swing.
//   page20 / page64            A paged list view, and the same at the row cap.
//     Primary, and together with point1 they show whether the win decays with
//     result size or with the cap.
//   point-under-load           One point read issued while four 1,000-row reads
//     hold the whole pool. Primary: the hop's cost is not only its own latency
//     but the queue in front of it, which a read that never enters the queue
//     does not pay. This is the shape a UI hits when a list refresh and a tap
//     land in the same frame.
//   concurrent8               Eight distinct point reads issued together.
//     GUARD, and the one that can kill the idea: four workers run four of them
//     at once, while a caller that runs them itself runs them one after another.
//   mixed6-1k / int20-10k     SHARED-PATH CONTROLS. Both return far more rows
//     than the cap allows and finish on workers, but the exp 269 candidate also
//     changed that worker decode loop: every row sees the cap comparison and
//     every TEXT/BLOB cell sees byte accounting. They therefore expose shared
//     overhead and binary drift; they are not byte-identical controls.
//   cap-abort                 GUARD for the mispredict: a statement whose first
//     two executions return one row and whose third returns 400, so the decode
//     starts on the calling isolate, gives up past the cap, and re-runs on a
//     worker. Each sample uses a fresh SQL string, because a high-water mark
//     makes the abort once-per-statement — measured any other way the lane goes
//     inert after its first sample.
//   blob1-5mb                 GUARD, added by exp 269. `SELECT * FROM photos
//     WHERE id = ?` over rows holding a 5 MB image. One row forever, so no
//     row-count history ever stops it — this is the shape that killed exp 265,
//     where the blob was copied onto the calling isolate unchecked at any size.
//     Exp 269 aborted the first large attempt and then dispatched this SQL to a
//     worker. Because the generic harness warms before timing, the samples see
//     post-latch dispatch rather than the inline abort itself.
//   scan-count                GUARD, added by exp 269, for work that happens
//     before the first row. Exp 265 named `count(*)` for this and it is the
//     wrong query: SQLite answers a bare `count(*)` with one `OP_Count` opcode,
//     so it is genuinely cheap and correctly runs inline. A filtered count is
//     the real shape — one small row after a full scan. Exp 269 aborted it on
//     the VM-step cap; warmup means timed samples see post-latch dispatch.
//   frame-jitter              GUARD, added by exp 269, and the only lane here
//     that measures latency rather than throughput. An inline read never yields,
//     so an awaited chain of them drains as one uninterruptible microtask block
//     and a frame callback cannot run until it ends. The sample value is the
//     WORST lateness a 60 Hz timer suffers while reads are issued continuously
//     for `_frameLaneMs`, so this lane is the one that can reject the design on
//     jank even while every throughput lane improves. It establishes whether
//     a chain of cheap reads yields; it does not bound one opaque read.
//
// Usage:
//   dart run benchmark/experiments/select_inline_dispatch.dart \
//     [--warmup=10] [--samples=31] [--lane=point1] [--no-memory]
//
// Emits one `shape=... median_us=... samples_us=...` line per lane, so two
// worktree runs can be paired into `benchmark/ab_drift_check.dart` input.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart' as resqlite;

import '../shared/memory_probe.dart';

const _defaultWarmup = 10;
const _defaultSamples = 31;

/// What a lane does inside one timed sample.
enum _Mode {
  /// Execute the lane's statement [_Lane.repeats] times.
  plain,

  /// Saturate the pool with [_backgroundReaders] large reads, then execute the
  /// lane's statement while they are still outstanding.
  underLoad,

  /// Issue [_Lane.repeats] distinct point statements together and await them
  /// as a group.
  concurrent,

  /// Arm a never-before-seen statement with two one-row executions, then time
  /// one execution that returns far more rows than the cap allows.
  capAbort,

  /// Issue reads continuously for [_frameLaneMs] while a 60 Hz timer runs, and
  /// report the worst lateness that timer suffers rather than read throughput.
  frameJitter,
}

/// How long one `frame-jitter` sample issues reads for. Three 60 Hz frames, so
/// the lane always contains frame deadlines a read chain can miss.
const int _frameLaneMs = 50;

/// The 60 Hz frame interval the `frame-jitter` lane holds a timer to.
const int _frameIntervalUs = 16667;

/// Bytes per row in the `blob1-5mb` lane — well past both the inline byte cap
/// (64 KB) and the blob wrap threshold (256 KB), so the two arms must differ in
/// what they do rather than only in how fast they do it.
const int _largeBlobBytes = 5 * 1024 * 1024;

/// Enough large reads outstanding to occupy every worker in the largest pool
/// `Database.open` will build (four).
const int _backgroundReaders = 4;

/// Groups of concurrent reads per `concurrent8` sample. One group lands around
/// 30 us, where a 1 us stopwatch tick is already 3% — too coarse for the lane
/// that has to decide whether losing pool parallelism costs anything.
const int _concurrentRounds = 10;

/// What the lane's table holds.
enum _Schema {
  /// The repo's canonical mixed row, or [_Lane.columns] INTEGER columns beside
  /// `id` when that is non-zero.
  standard,

  /// `id INTEGER PRIMARY KEY, img BLOB` with [_largeBlobBytes] per row.
  largeBlob,
}

final class _Lane {
  const _Lane(
    this.label, {
    required this.rows,
    this.columns = 0,
    this.schema = _Schema.standard,
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

  final _Schema schema;

  final String selectSql;
  final List<Object?> selectParams;

  /// Rows the timed statement returns, when that differs from [rows].
  final int? expectRows;

  /// Executions inside one timed sample. Reported medians are per sample.
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
    columns: 20,
    selectSql: 'SELECT * FROM items WHERE id = ?',
    selectParams: [17],
    expectRows: 1,
    repeats: 200,
  ),
  _Lane(
    'page20',
    rows: 2000,
    selectSql: 'SELECT * FROM items LIMIT 20',
    expectRows: 20,
    repeats: 50,
  ),
  _Lane(
    'page64',
    rows: 2000,
    selectSql: 'SELECT * FROM items LIMIT 64',
    expectRows: 64,
    repeats: 20,
  ),
  _Lane(
    'point-under-load',
    rows: 1000,
    selectSql: 'SELECT * FROM items WHERE id = ?',
    selectParams: [17],
    expectRows: 1,
    repeats: 10,
    mode: _Mode.underLoad,
  ),
  _Lane(
    'concurrent8',
    rows: 2000,
    selectSql: 'SELECT * FROM items WHERE id = ?',
    expectRows: 1,
    repeats: 8,
    mode: _Mode.concurrent,
  ),
  // SHARED-PATH CONTROLS: both finish on workers, but exp 269's cap accounting
  // also changed the worker decoder, so the arms are not byte-identical.
  _Lane('mixed6-1k', rows: 1000),
  _Lane('int20-10k', rows: 10000, columns: 20),
  // GUARD: fresh statement per sample, armed small, timed large.
  _Lane(
    'cap-abort',
    rows: 2000,
    selectSql: 'SELECT * FROM items LIMIT ?',
    selectParams: [400],
    expectRows: 400,
    mode: _Mode.capAbort,
  ),
  // GUARD (exp 269): one row, 5 MB of it. Permanently high-water 1.
  _Lane(
    'blob1-5mb',
    rows: 8,
    schema: _Schema.largeBlob,
    selectSql: 'SELECT * FROM items WHERE id = ?',
    selectParams: [3],
    expectRows: 1,
    repeats: 4,
  ),
  // GUARD (exp 269): one row out, a full scan in. A bare `count(*)` is one
  // opcode, so the predicate is what makes the work real.
  _Lane(
    'scan-count',
    rows: 20000,
    selectSql: "SELECT count(*) FROM items WHERE description LIKE '%9997%'",
    expectRows: 1,
    repeats: 4,
  ),
  // GUARD (exp 269): latency, not throughput. Sample value is the worst frame
  // lateness in microseconds, so lower is still better.
  _Lane(
    'frame-jitter',
    rows: 2000,
    selectSql: 'SELECT * FROM items WHERE id = ?',
    selectParams: [17],
    expectRows: 1,
    mode: _Mode.frameJitter,
  ),
];

/// Monotonic counter making every `cap-abort` statement a distinct SQL string.
/// A trailing comment changes the text without changing the plan.
int _abortSeq = 0;

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

  print('=== select() inline-vs-dispatch focused harness ===');
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
  final temp = await Directory.systemTemp.createTemp('bench_inline_');
  try {
    final db = await resqlite.Database.open('${temp.path}/test.db');

    final String createSql;
    final String insertSql;
    final List<Object?> Function(int row) row;
    if (lane.schema == _Schema.largeBlob) {
      createSql = 'CREATE TABLE items(id INTEGER PRIMARY KEY, img BLOB)';
      insertSql = 'INSERT INTO items(img) VALUES (?)';
      final image = Uint8List(_largeBlobBytes);
      row = (_) => [image];
    } else if (lane.columns == 0) {
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

    // 5 MB a row: batching these the way the other lanes do would build a
    // 4 GB parameter matrix.
    final chunk = lane.schema == _Schema.largeBlob ? 1 : 500;
    for (var start = 0; start < lane.rows; start += chunk) {
      final end = start + chunk < lane.rows ? start + chunk : lane.rows;
      await db.executeBatch(insertSql, [
        for (var r = start; r < end; r++) row(r),
      ]);
    }

    // Warmup doubles as arming: a statement is not eligible to run inline until
    // the pool has watched it twice, so a lane measured without warmup would
    // measure the dispatch path in both arms.
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
/// Each mode times only the reads under test: the pool-saturating reads of
/// `underLoad` and the arming executions of `capAbort` are issued outside the
/// stopwatch, so the number is the latency of the read whose route changed.
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
        for (var i = 0; i < _backgroundReaders; i++)
          db.select('SELECT * FROM items'),
      ];
      final sw = Stopwatch()..start();
      for (var n = 0; n < lane.repeats; n++) {
        _check(
          lane,
          await db.select(lane.selectSql, lane.selectParams),
          expect,
        );
      }
      sw.stop();
      await Future.wait(background);
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

    case _Mode.capAbort:
      // Fresh statement, so this sample sees the same first-large-result cost
      // the previous one did. Armed with two one-row executions, which is what
      // makes the pool believe the third is worth running inline.
      final sql = 'SELECT * FROM items LIMIT ? -- a${_abortSeq++}';
      await db.select(sql, [1]);
      await db.select(sql, [1]);
      final sw = Stopwatch()..start();
      _check(lane, await db.select(sql, lane.selectParams), expect);
      sw.stop();
      return sw.elapsedMicroseconds;

    case _Mode.frameJitter:
      // Not a duration: the returned number is how late the frame timer was at
      // its worst, so it is still "lower is better" but it is a latency, and
      // the two arms do different amounts of reading inside the same window.
      var worstLateUs = 0;
      var ticks = 0;
      final sw = Stopwatch()..start();
      final frames = Timer.periodic(
        const Duration(microseconds: _frameIntervalUs),
        (_) {
          ticks++;
          final late = sw.elapsedMicroseconds - ticks * _frameIntervalUs;
          if (late > worstLateUs) worstLateUs = late;
        },
      );
      while (sw.elapsedMicroseconds < _frameLaneMs * 1000) {
        _check(
          lane,
          await db.select(lane.selectSql, lane.selectParams),
          expect,
        );
      }
      frames.cancel();
      // A deadline the read chain blocked straight through never gets a
      // callback, so it is invisible above and has to be charged here.
      final pending = sw.elapsedMicroseconds - (ticks + 1) * _frameIntervalUs;
      sw.stop();
      return pending > worstLateUs ? pending : worstLateUs;
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
