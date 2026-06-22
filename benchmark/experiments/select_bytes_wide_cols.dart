// Focused workload for exp 190 — `selectBytes()` on rowsets where the
// native JSON encoder spends a non-trivial fraction of wall on column-
// name emission. Exercises shapes where per-row, per-column work
// compounds: many rows × moderate columns, and short integer values
// (so column names are a larger relative share of bytes written).
//
// The encoder change pre-builds each column's `"name":` / `,"name":`
// token once at first-row time so subsequent rows write a single
// `buf_write` per column instead of comma + `json_write_string` (SWAR
// scan + escape walk) + colon.
//
//   dart run benchmark/experiments/select_bytes_wide_cols.dart
//
// Reports median ms per `selectBytes()` call across several
// rows × column-count shapes.
import 'dart:io';

import 'package:resqlite/resqlite.dart';

class _Shape {
  const _Shape(this.label, this.rows, this.cols, this.intsOnly);
  final String label;
  final int rows;
  final int cols;
  final bool intsOnly;
}

const _shapes = <_Shape>[
  // Many rows, moderate columns, INT values: maximizes per-row-per-col
  // column-name emission share of total bytes written.
  _Shape('10k rows × 8 int cols', 10000, 8, true),
  _Shape('10k rows × 20 int cols', 10000, 20, true),
  // Same shape but with a few short text columns to broaden coverage.
  _Shape('10k rows × 8 mixed cols', 10000, 8, false),
  _Shape('10k rows × 20 mixed cols', 10000, 20, false),
  // Control: narrow shape where column-name share is small relative to
  // payload bytes / per-row constant overhead.
  _Shape('10k rows × 2 int cols', 10000, 2, true),
  // Regression guards: tiny rowsets where the new per-query token
  // pre-encode pass (one extra buf_init + a write per column at first-
  // row time) is pure overhead and the per-row savings have nothing
  // to amortize against.
  _Shape('1 row × 5 mixed cols', 1, 5, false),
  _Shape('100 rows × 5 mixed cols', 100, 5, false),
];

const _callsPerSample = 5;
const _samples = 11;

Future<void> main() async {
  final tmp = await Directory.systemTemp.createTemp('resqlite-exp190-');
  final dbPath = '${tmp.path}/exp190.db';
  final db = await Database.open(dbPath);

  stdout.writeln(
    'selectBytes wide-cols — $_callsPerSample calls/sample, $_samples samples\n',
  );
  stdout.writeln('| Shape | Median ms/call | Min | Max | Bytes |');
  stdout.writeln('|---|---|---|---|---|');

  for (final shape in _shapes) {
    await _setupShape(db, shape);
    final sql = _selectSql(shape);
    // Warm up: statement cache, page cache, json_buf capacity.
    for (var i = 0; i < 3; i++) {
      await db.selectBytes(sql);
    }
    final probe = await db.selectBytes(sql);

    final medians = <double>[];
    for (var s = 0; s < _samples; s++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < _callsPerSample; i++) {
        await db.selectBytes(sql);
      }
      sw.stop();
      medians.add(sw.elapsedMicroseconds / 1000.0 / _callsPerSample);
    }
    medians.sort();
    final med = medians[medians.length ~/ 2];
    stdout.writeln(
      '| ${shape.label} '
      '| ${med.toStringAsFixed(3)} '
      '| ${medians.first.toStringAsFixed(3)} '
      '| ${medians.last.toStringAsFixed(3)} '
      '| ${probe.length} |',
    );
    await db.execute('DROP TABLE t');
  }

  await db.close();
  await tmp.delete(recursive: true);
}

Future<void> _setupShape(Database db, _Shape shape) async {
  final cols = StringBuffer();
  for (var i = 0; i < shape.cols; i++) {
    if (i > 0) cols.write(', ');
    final isText = !shape.intsOnly && (i % 3) == 0;
    cols.write('c$i ${isText ? 'TEXT' : 'INTEGER'}');
  }
  await db.execute('CREATE TABLE t($cols)');
  final placeholders = List.filled(shape.cols, '?').join(', ');
  final insertSql = 'INSERT INTO t VALUES ($placeholders)';
  // Populate.
  final params = <List<Object?>>[];
  for (var r = 0; r < shape.rows; r++) {
    final row = <Object?>[];
    for (var c = 0; c < shape.cols; c++) {
      final isText = !shape.intsOnly && (c % 3) == 0;
      row.add(isText ? 'v$r-$c' : r * 31 + c);
    }
    params.add(row);
  }
  await db.executeBatch(insertSql, params);
}

String _selectSql(_Shape shape) {
  final cols = StringBuffer();
  for (var i = 0; i < shape.cols; i++) {
    if (i > 0) cols.write(', ');
    cols.write('c$i');
  }
  return 'SELECT $cols FROM t';
}
