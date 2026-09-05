// ignore_for_file: avoid_print
//
// Focused A/B harness for what a reader reply is *shaped* as ([EXP-282]).
//
// Every reply a reader worker sends travelled in a `(result, sacrificed,
// error)` record, and three of the four request types wrapped their payload in
// a second record inside it. `read_request_residual.dart` measured what that
// costs: a message whose object graph contains a record anywhere is ~1 us more
// expensive to deliver than the same message built from ordinary objects, and
// the penalty is paid once per message rather than once per record. The
// candidate replaces every record on the reader's reply path with a small
// final class. Nothing about the public API, the results, or the request path
// changes.
//
// Lanes, and what each is for:
//
//   point1          PRIMARY. Sequentially awaited point reads of one long-warm
//     statement — the smallest read the library has, so the largest share of
//     the reply's fixed cost. Batched, since one read lands in single-digit
//     microseconds where a 1 us stopwatch tick is a 16% swing.
//   point1-wide20   The same at 21 columns. The saving is per *message*, not
//     per cell, so this should move by the same absolute amount as `point1`
//     and therefore by a smaller percentage.
//   rows20          A 20-row page, the shape a paged list view reads.
//   rows1k          1,000 rows. DILUTION CHECK: a fixed per-reply saving has
//     to shrink to near nothing here, and if it does not, the mechanism is not
//     what this experiment claims.
//   bytes1          PRIMARY for the second path. `selectBytes` wrapped a
//     *named* record inside the envelope record, so its reply carried two.
//     Because the penalty is once per message, removing both is worth the same
//     ~1 us as removing one — this lane is where that prediction is tested.
//   bytes1k         The same at 1,000 rows: dilution for the bytes path.
//   stream-rerun    The `selectIfChanged` path, which fires on every stream
//     re-query. One stream over a table, N writes, timed to the last emission.
//   writes          CONTROL with a computable ceiling of zero: the writer path
//     already replies with classes (`ExecuteResponse`, `BatchResponse`) and is
//     untouched by the diff. Whatever this lane does is what the collection
//     cannot resolve.
//   rows10k         GUARD. 60,000 slots, above `sacrificeSlotThreshold`, so
//     every timed read leaves by `Isolate.exit` instead of `send`. That path
//     is zero-copy and should not care what the envelope is; this lane proves
//     the change did not break it and does not secretly depend on it.
//
// Usage:
//   dart run benchmark/experiments/reader_reply_envelope_ab.dart \
//     [--warmup=8] [--samples=41] [--lane=point1]
//
// Build both arms AOT from separate worktrees with `dart build cli` and run
// one lane per process; nothing here toggles in-process.
import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;

const _defaultWarmup = 8;
const _defaultSamples = 41;

const _wideColumns = 20;

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

enum _Kind { select, bytes, streamRerun, write }

final class _Lane {
  const _Lane(
    this.label, {
    required this.rows,
    this.kind = _Kind.select,
    this.sql = 'SELECT * FROM items WHERE id = ?',
    this.params = const [17],
    this.expectRows = 1,
    this.repeats = 1,
    this.wide = false,
  });

  final String label;
  final int rows;
  final _Kind kind;
  final String sql;
  final List<Object?> params;
  final int expectRows;

  /// Units of work inside one timed sample.
  final int repeats;

  /// Seed the 21-column INTEGER table instead of the canonical mixed row.
  final bool wide;
}

final _lanes = <_Lane>[
  _Lane('point1', rows: 2000, repeats: 200),
  _Lane('point1-wide20', rows: 2000, repeats: 200, wide: true),
  _Lane(
    'rows20',
    rows: 2000,
    sql: 'SELECT * FROM items LIMIT 20',
    params: const [],
    expectRows: 20,
    repeats: 50,
  ),
  _Lane(
    'rows1k',
    rows: 2000,
    sql: 'SELECT * FROM items LIMIT 1000',
    params: const [],
    expectRows: 1000,
    repeats: 5,
  ),
  _Lane('bytes1', rows: 2000, kind: _Kind.bytes, repeats: 200),
  _Lane(
    'bytes1k',
    rows: 2000,
    kind: _Kind.bytes,
    sql: 'SELECT * FROM items LIMIT 1000',
    params: const [],
    expectRows: 1000,
    repeats: 5,
  ),
  _Lane(
    'stream-rerun',
    rows: 500,
    kind: _Kind.streamRerun,
    sql: 'SELECT * FROM items WHERE category = ?',
    params: const ['category_3'],
    expectRows: 50,
    repeats: 20,
  ),
  // CONTROL: the writer path replies with classes already.
  _Lane('writes', rows: 200, kind: _Kind.write, repeats: 50),
  // GUARD: leaves by Isolate.exit, not send.
  _Lane(
    'rows10k',
    rows: 10000,
    sql: 'SELECT * FROM items',
    params: const [],
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

  print('=== reader reply envelope focused harness ===');
  print('warmup=$warmup samples=$samples');
  for (final lane in _lanes) {
    if (only != null && lane.label != only) continue;
    await _runLane(lane, warmup: warmup, samples: samples);
  }
}

Future<void> _runLane(
  _Lane lane, {
  required int warmup,
  required int samples,
}) async {
  final temp = await Directory.systemTemp.createTemp('bench_reply_');
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
      await _sample(db, lane, insertSql, row);
    }

    final values = <int>[];
    for (var i = 0; i < samples; i++) {
      final sw = Stopwatch()..start();
      await _sample(db, lane, insertSql, row);
      sw.stop();
      values.add(sw.elapsedMicroseconds);
    }
    await db.close();

    final sorted = [...values]..sort();
    print(
      'shape=${lane.label} '
      'median_us=${_percentile(sorted, 0.50)} '
      'p10_us=${_percentile(sorted, 0.10)} '
      'p90_us=${_percentile(sorted, 0.90)} '
      'samples_us=${values.join(',')}',
    );
  } finally {
    await temp.delete(recursive: true);
  }
}

int _writeSeq = 0;

/// The `stream-rerun` lane's write: always in the category the stream watches,
/// so every write changes the watched result by exactly one row.
const _streamInsert =
    'INSERT INTO items(name, description, value, category, created_at) '
    "VALUES (?, ?, ?, 'category_3', ?)";
List<Object?> _streamRow(int i) => [
  'Item $i',
  'This is a description for item number $i with some padding text to '
      'simulate real data',
  i * 1.5,
  '2026-04-0${(i % 9) + 1}T12:00:00Z',
];

Future<void> _sample(
  resqlite.Database db,
  _Lane lane,
  String insertSql,
  List<Object?> Function(int row) row,
) async {
  switch (lane.kind) {
    case _Kind.select:
      for (var n = 0; n < lane.repeats; n++) {
        _check(lane, (await db.select(lane.sql, lane.params)).length);
      }
    case _Kind.bytes:
      for (var n = 0; n < lane.repeats; n++) {
        _check(lane, (await db.selectBytes(lane.sql, lane.params)).rowCount);
      }
    case _Kind.write:
      for (var n = 0; n < lane.repeats; n++) {
        await db.execute(insertSql, row(_writeSeq++));
      }
    case _Kind.streamRerun:
      // One stream over the table, then [_Lane.repeats] writes that all match
      // it. The sample ends when an emission carries every one of them.
      //
      // Counting *emissions* would not work: the stream engine coalesces
      // re-queries, so N writes produce an unpredictable number of them.
      // Waiting on the row count instead makes the lane measure the same work
      // in both arms however the coalescing falls.
      final before = (await db.select(lane.sql, lane.params)).length;
      final target = before + lane.repeats;
      final seen = Completer<void>();
      var last = before;
      final sub = db.stream(lane.sql, lane.params).listen((rows) {
        last = rows.length;
        if (last >= target && !seen.isCompleted) seen.complete();
      });
      for (var n = 0; n < lane.repeats; n++) {
        await db.execute(_streamInsert, _streamRow(_writeSeq++));
      }
      await seen.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw StateError(
          '${lane.label}: stalled at $last rows, wanted $target',
        ),
      );
      await sub.cancel();
  }
}

void _check(_Lane lane, int got) {
  if (got != lane.expectRows) {
    throw StateError(
      '${lane.label}: expected ${lane.expectRows} rows, got $got',
    );
  }
}

int _percentile(List<int> sorted, double p) {
  if (sorted.isEmpty) return 0;
  final index = ((sorted.length - 1) * p).round();
  return sorted[index];
}
