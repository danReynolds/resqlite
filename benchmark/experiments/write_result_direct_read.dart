// Focused workload for write-result decoding inside `executeWrite()`.
//
// `executeWrite()` receives a 16-byte native `resqlite_write_result` struct
// for every writer request. Exp 214 uses this harness to measure whether
// reading those scalar fields directly from the native pointer is visible
// against the writer round-trip floor.
//
//   dart run benchmark/experiments/write_result_direct_read.dart
import 'dart:io';

import 'package:resqlite/resqlite.dart';

const _callsPerSample = 2000;
const _samples = 13;

enum _Shape {
  noopUpdate('noop update', 'UPDATE items SET id = id WHERE 1 = 0'),
  pointUpdate(
    'point update',
    'UPDATE items SET value = value + 1 WHERE id = 1',
  ),
  paramUpdate(
    'param update',
    'UPDATE items SET value = ? WHERE id = 1',
    parameterized: true,
  );

  const _Shape(this.label, this.sql, {this.parameterized = false});

  final String label;
  final String sql;
  final bool parameterized;
}

Future<void> main() async {
  final tmp = await Directory.systemTemp.createTemp('resqlite-exp214-');
  final db = await Database.open('${tmp.path}/exp214.db');

  try {
    await db.execute(
      'CREATE TABLE items(id INTEGER PRIMARY KEY, value INTEGER NOT NULL)',
    );
    await db.execute('INSERT INTO items(id, value) VALUES (1, 0)');

    stdout.writeln(
      'write result direct read - '
      '$_callsPerSample calls/sample, $_samples samples\n',
    );
    stdout.writeln('| Shape | Median us/call | Min | Max |');
    stdout.writeln('|---|---:|---:|---:|');

    for (final shape in _Shape.values) {
      await _warm(db, shape);

      final medians = <double>[];
      for (var s = 0; s < _samples; s++) {
        final sw = Stopwatch()..start();
        for (var i = 0; i < _callsPerSample; i++) {
          await _execute(db, shape, i);
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
        '| ${medians.last.toStringAsFixed(3)} |',
      );
    }
  } finally {
    await db.close();
    await tmp.delete(recursive: true);
  }
}

Future<void> _warm(Database db, _Shape shape) async {
  for (var i = 0; i < 128; i++) {
    await _execute(db, shape, i);
  }
}

Future<void> _execute(Database db, _Shape shape, int i) {
  if (shape.parameterized) {
    return db.execute(shape.sql, [i]);
  }
  return db.execute(shape.sql);
}
