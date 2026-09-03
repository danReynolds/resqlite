// ignore_for_file: avoid_print
//
// End-to-end A/B for the lazy `RowSchema` name index ([EXP-281]).
//
// `schema_index_transfer.dart` prices the mechanism in isolation: the eager
// `HashMap` costs 0.15 us of hop at six columns and 1.7 us at forty, and
// building one on demand costs 95 ns to 620 ns. This harness checks that
// arithmetic against real reads, where the saving is a fraction of a whole
// query and the build lands on whichever caller looks a column up by name.
//
// Lanes, and what each is for:
//
//   point1          Sequentially awaited point reads of a six-column row, the
//                   result discarded. PRIMARY: the canonical read shape, and
//                   the pure wire saving with no lookup on either arm.
//   point1-literal  The same read, then every cell fetched as `row['name']`
//                   with a source literal — what application code writes, and
//                   the pattern that pays for the build. The candidate has to
//                   stay ahead here or the saving is borrowed, not earned.
//   point1-interned The same read consumed through `row.keys`, which re-feeds
//                   the schema's own name objects and never leaves the identity
//                   scan. The index is never built on either arm.
//   wide21          Twenty-one columns, discarded. Where the eager map is
//                   worth ~1.1 us of hop.
//   wide21-literal  Twenty-one columns consumed by literal, so the build is
//                   322 ns against a saving seven times larger.
//   wide40          Forty columns, discarded. The far end of the effect.
//   rows1k-literal  One thousand six-column rows consumed by literal: 6,000
//                   lookups against one build. The amortization check.
//   bytes1          GUARD: the same point read through `selectBytes`, which
//                   builds no `RowSchema` at all. Must read neutral — anything
//                   it moves is apparatus, not this change.
//   writes          GUARD: a small batch write, which never crosses a schema.
//   lookup-*        `RowSchema.indexOf` alone, no database and no isolate, at
//                   200,000 lookups against one schema so the one-time build
//                   amortizes away and only the steady-state probe is left.
//                   GUARD on the lazy field: a per-lookup tax here is paid on
//                   every cell of every large result, and would swallow a
//                   once-per-read saving. `-literal` is a caller's own string,
//                   `-interned` the schema's own name object, `-miss` a column
//                   that is not there.
//
// Usage:
//   dart run benchmark/experiments/schema_index_read_ab.dart \
//     [--samples=41] [--warmup=8] [--lane=point1]
//
// Build it AOT (`dart build cli`) for figures comparable with shipped code.
import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;

const _wideColumns = 20;
const _wideColumnsFar = 40;

/// Rows seeded into every lane's table.
const _seedRows = 2000;

final class _Lane {
  const _Lane(
    this.name, {
    required this.sql,
    this.params = const [],
    this.expectRows = 1,
    this.repeats = 200,
    this.columns = 0,
    this.consume = _Consume.none,
    this.bytes = false,
    this.write = false,
  });

  final String name;
  final String sql;
  final List<Object?> params;
  final int expectRows;

  /// Reads per timed unit, so a lane's unit is large enough to time cleanly.
  final int repeats;

  /// Extra INTEGER columns beyond `id`; 0 uses the standard six-column row.
  final int columns;
  final _Consume consume;
  final bool bytes;
  final bool write;
}

/// How a lane reads the cells it just fetched — the axis the lazy index is
/// actually sensitive to.
enum _Consume {
  /// Only the row count is read; no column is ever looked up by name.
  none,

  /// `row['literal']` for every column: misses the identity scan, so the
  /// candidate builds its index here.
  literal,

  /// `row[k] for k in row.keys`: the schema's own name objects, so the
  /// identity scan resolves every lookup and no index is ever built.
  interned,
}

const _standardColumns = <String>[
  'id',
  'name',
  'category',
  'price',
  'in_stock',
  'created_at',
];

const _standardCreate = '''
  CREATE TABLE items(
    id INTEGER PRIMARY KEY,
    name TEXT,
    category TEXT,
    price REAL,
    in_stock INTEGER,
    created_at INTEGER
  )
''';

const _standardInsert =
    'INSERT INTO items(name, category, price, in_stock, created_at) '
    'VALUES (?, ?, ?, ?, ?)';

List<Object?> _standardRow(int r) => [
  'item_$r',
  'cat_${r % 8}',
  r * 1.5,
  r % 2,
  1700000000000 + r,
];

const _lanes = <_Lane>[
  _Lane('point1', sql: 'SELECT * FROM items WHERE id = ?', params: [17]),
  _Lane(
    'point1-literal',
    sql: 'SELECT * FROM items WHERE id = ?',
    params: [17],
    consume: _Consume.literal,
  ),
  _Lane(
    'point1-interned',
    sql: 'SELECT * FROM items WHERE id = ?',
    params: [17],
    consume: _Consume.interned,
  ),
  _Lane(
    'wide21',
    sql: 'SELECT * FROM items WHERE id = ?',
    params: [17],
    columns: _wideColumns,
  ),
  _Lane(
    'wide21-literal',
    sql: 'SELECT * FROM items WHERE id = ?',
    params: [17],
    columns: _wideColumns,
    consume: _Consume.literal,
  ),
  _Lane(
    'wide40',
    sql: 'SELECT * FROM items WHERE id = ?',
    params: [17],
    columns: _wideColumnsFar,
  ),
  _Lane(
    'rows1k-literal',
    sql: 'SELECT * FROM items LIMIT 1000',
    expectRows: 1000,
    repeats: 5,
    consume: _Consume.literal,
  ),
  // GUARD: no RowSchema is built on this path at all.
  _Lane(
    'bytes1',
    sql: 'SELECT * FROM items WHERE id = ?',
    params: [17],
    bytes: true,
  ),
  // GUARD: the write path never crosses a schema.
  _Lane('writes', sql: _standardInsert, repeats: 20, write: true),
];

/// Lookup guard lanes: `<key kind>-<columns>`.
const _lookupLanes = <String>[
  'lookup-literal-6',
  'lookup-interned-6',
  'lookup-miss-6',
  'lookup-literal-21',
  'lookup-interned-21',
  'lookup-literal-40',
];

const _lookupIterations = 200000;

/// Column names as a real read produces them: decoded per query and never
/// canonicalized, so a caller's literal of the same text is a different object.
List<String> _decodedNames(int columns) => List<String>.generate(
  columns,
  (i) => String.fromCharCodes('column_name_$i'.codeUnits),
  growable: false,
);

/// Times `RowSchema.indexOf` directly, in nanoseconds per lookup.
double _runLookup(String lane, int iterations) {
  final parts = lane.split('-');
  final kind = parts[1];
  final columns = int.parse(parts[2]);
  final schema = resqlite.RowSchema(_decodedNames(columns));
  final keys = switch (kind) {
    'interned' => schema.names,
    'miss' => List<String>.generate(columns, (i) => 'absent_column_$i'),
    _ => List<String>.generate(columns, (i) => 'column_name_$i'),
  };
  final stopwatch = Stopwatch()..start();
  var found = 0;
  for (var i = 0; i < iterations; i++) {
    found += schema.indexOf(keys[i % columns]);
  }
  stopwatch.stop();
  _sink += found + iterations;
  return stopwatch.elapsedMicroseconds * 1000 / iterations;
}

int _sink = 0;

void _check(_Lane lane, int got, int want) {
  if (got != want) {
    throw StateError('${lane.name}: expected $want rows, got $got');
  }
}

List<String> _columnNamesFor(_Lane lane) => lane.columns == 0
    ? _standardColumns
    : ['id', for (var c = 0; c < lane.columns; c++) 'c$c'];

Future<void> _unit(
  resqlite.Database db,
  _Lane lane,
  List<String> literals,
) async {
  for (var n = 0; n < lane.repeats; n++) {
    if (lane.write) {
      await db.executeBatch(lane.sql, [
        for (var r = 0; r < 20; r++) _standardRow(_seedRows + r),
      ]);
      continue;
    }
    if (lane.bytes) {
      final result = await db.selectBytes(lane.sql, lane.params);
      _check(lane, result.rowCount, lane.expectRows);
      _sink += result.bytes.length;
      continue;
    }
    final rows = await db.select(lane.sql, lane.params);
    _check(lane, rows.length, lane.expectRows);
    switch (lane.consume) {
      case _Consume.none:
        _sink += rows.length;
      case _Consume.literal:
        for (final row in rows) {
          for (final name in literals) {
            if (row[name] != null) _sink++;
          }
        }
      case _Consume.interned:
        for (final row in rows) {
          for (final key in row.keys) {
            if (row[key] != null) _sink++;
          }
        }
    }
  }
}

Future<List<double>> _runLane(
  _Lane lane, {
  required int warmup,
  required int samples,
}) async {
  final temp = await Directory.systemTemp.createTemp('bench_schema_index_');
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
      final defs = [for (var c = 0; c < lane.columns; c++) 'c$c INTEGER'];
      createSql =
          'CREATE TABLE items(id INTEGER PRIMARY KEY, ${defs.join(', ')})';
      final names = [for (var c = 0; c < lane.columns; c++) 'c$c'].join(', ');
      final placeholders = List.filled(lane.columns, '?').join(', ');
      insertSql = 'INSERT INTO items($names) VALUES ($placeholders)';
      row = (r) => [for (var c = 0; c < lane.columns; c++) r * 31 + c];
    }
    await db.execute(createSql);
    const chunk = 500;
    for (var start = 0; start < _seedRows; start += chunk) {
      final end = start + chunk < _seedRows ? start + chunk : _seedRows;
      await db.executeBatch(insertSql, [
        for (var r = start; r < end; r++) row(r),
      ]);
    }

    // Literals of the same text as the column names, allocated here rather
    // than read off a row: a decoded name is never identical to one.
    final literals = [
      for (final name in _columnNamesFor(lane)) String.fromCharCodes(name.runes),
    ];

    for (var i = 0; i < warmup; i++) {
      await _unit(db, lane, literals);
    }
    final timings = <double>[];
    for (var s = 0; s < samples; s++) {
      final stopwatch = Stopwatch()..start();
      await _unit(db, lane, literals);
      stopwatch.stop();
      timings.add(stopwatch.elapsedMicroseconds / lane.repeats);
    }
    await db.close();
    return timings;
  } finally {
    temp.deleteSync(recursive: true);
  }
}

double _median(List<double> xs) {
  final sorted = List<double>.from(xs)..sort();
  return sorted[sorted.length ~/ 2];
}

Future<void> main(List<String> args) async {
  var warmup = 8;
  var samples = 41;
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

  print('=== schema index read A/B ===');
  print('warmup=$warmup samples=$samples');
  for (final lane in _lookupLanes) {
    if (only != null && lane != only) continue;
    _runLookup(lane, _lookupIterations ~/ 4);
    final timings = <double>[];
    for (var s = 0; s < samples; s++) {
      timings.add(_runLookup(lane, _lookupIterations));
    }
    final sorted = List<double>.from(timings)..sort();
    print(
      'lane=$lane ns_per_lookup=${_median(sorted).toStringAsFixed(2)} '
      'min=${sorted.first.toStringAsFixed(2)} '
      'max=${sorted.last.toStringAsFixed(2)}',
    );
  }
  for (final lane in _lanes) {
    if (only != null && lane.name != only) continue;
    final timings = await _runLane(lane, warmup: warmup, samples: samples);
    final sorted = List<double>.from(timings)..sort();
    print(
      'lane=${lane.name} us_per_read=${_median(sorted).toStringAsFixed(3)} '
      'min=${sorted.first.toStringAsFixed(3)} '
      'max=${sorted.last.toStringAsFixed(3)}',
    );
  }
  if (_sink == 0 && only != 'writes') {
    throw StateError('unreachable: results were never consumed');
  }
}
