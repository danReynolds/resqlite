// Focused workload for exp 195 — `selectBytes()` repeated against the same
// prepared SQL with small rowsets, where the per-query first-row pre-encode
// work and the per-query `tokens_buf` malloc/free pair are a larger fraction
// of total wall.
//
// Exp 190 amortized the column-name token emission within a single query
// (one buf_write per column per row instead of comma + json_write_string +
// colon). The per-query token buffer was still re-built and re-malloc'd on
// every `selectBytes()` call. Exp 195 caches the encoded tokens on the
// cached statement entry so re-executions reuse them.
//
// The release-suite Select Bytes 1K-row lane and exp 190's `wide_cols.dart`
// 10K-row shapes do not isolate this signal — the per-row stepping cost
// dominates wall time. The shapes below report median microseconds per call
// over thousands of repeats so the per-query amortization shows up at
// microsecond granularity rather than disappearing inside the millisecond
// reporting floor of the existing harness.
//
//   dart run benchmark/experiments/select_bytes_repeated_calls.dart
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
  // Primary lanes: tiny rowsets where the per-query setup (token buffer
  // malloc + first-row pre-encode walk) is a significant share of wall.
  _Shape('1 row × 8 int cols', 1, 8, true),
  _Shape('1 row × 20 int cols', 1, 20, true),
  _Shape('1 row × 8 mixed cols', 1, 8, false),
  _Shape('10 rows × 8 int cols', 10, 8, true),
  _Shape('10 rows × 20 int cols', 10, 20, true),
  _Shape('100 rows × 8 int cols', 100, 8, true),
  // Guards: larger rowsets where amortization has nothing to claw back
  // relative to per-row work, so the lane should stay flat.
  _Shape('1000 rows × 8 int cols', 1000, 8, true),
];

const _callsPerSample = 1000;
const _samples = 11;

Future<void> main() async {
  final tmp = await Directory.systemTemp.createTemp('resqlite-exp195-');
  final dbPath = '${tmp.path}/exp195.db';
  final db = await Database.open(dbPath);

  stdout.writeln(
    'selectBytes repeated calls — '
    '$_callsPerSample calls/sample, $_samples samples\n',
  );
  stdout.writeln('| Shape | Median µs/call | Min | Max | Bytes |');
  stdout.writeln('|---|---|---|---|---|');

  for (final shape in _shapes) {
    await _setupShape(db, shape);
    final sql = _selectSql(shape);
    // Warm up: statement cache, page cache, json_buf capacity.
    for (var i = 0; i < 16; i++) {
      await db.selectBytes(sql);
    }
    final probe = (await db.selectBytes(sql)).bytes;

    final medians = <double>[];
    for (var s = 0; s < _samples; s++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < _callsPerSample; i++) {
        await db.selectBytes(sql);
      }
      sw.stop();
      medians.add(sw.elapsedMicroseconds / _callsPerSample);
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

  final valueLists = <List<Object?>>[];
  for (var r = 0; r < shape.rows; r++) {
    final row = <Object?>[];
    for (var i = 0; i < shape.cols; i++) {
      final isText = !shape.intsOnly && (i % 3) == 0;
      row.add(isText ? 'v$r-$i' : r * 1000 + i);
    }
    valueLists.add(row);
  }

  final placeholders = List.filled(shape.cols, '?').join(', ');
  await db.executeBatch(
    'INSERT INTO t VALUES ($placeholders)',
    valueLists,
  );
}

String _selectSql(_Shape shape) {
  final cols = StringBuffer();
  for (var i = 0; i < shape.cols; i++) {
    if (i > 0) cols.write(', ');
    cols.write('c$i');
  }
  return 'SELECT $cols FROM t';
}
