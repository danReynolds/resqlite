// Focused workload for exp 189 — nested transaction savepoint-name
// compression. It measures the SAVEPOINT / RELEASE / ROLLBACK TO control path
// directly, with and without writes, so the best-case string-control effect is
// separated from the realistic nested-write rows already in the release suite.
//
//   dart run benchmark/experiments/savepoint_name_compression.dart
import 'dart:io';

import 'package:resqlite/resqlite.dart';

const _samples = 17;
const _warmup = 3;
const _emptyFanout = 500;
const _writeFanout = 100;
const _deepRepeats = 100;
const _depth = 5;

const _createSql =
    'CREATE TABLE items(id INTEGER PRIMARY KEY, value INTEGER NOT NULL)';
const _insertSql = 'INSERT INTO items(value) VALUES (?)';

Future<void> main() async {
  final tmp = await Directory.systemTemp.createTemp('resqlite-exp189-');
  final db = await Database.open('${tmp.path}/exp189.db');
  await db.execute(_createSql);

  stdout.writeln('savepoint name compression — $_samples samples\n');
  stdout.writeln('| Case | Median ms | Min | Max |');
  stdout.writeln('|---|---:|---:|---:|');

  await _measure(db, 'empty fanout x$_emptyFanout', () async {
    await db.transaction((tx) async {
      for (var i = 0; i < _emptyFanout; i++) {
        await tx.transaction((_) async {});
      }
    });
  });

  await _measure(db, 'write fanout x$_writeFanout', () async {
    await db.transaction((tx) async {
      for (var i = 0; i < _writeFanout; i++) {
        await tx.transaction((inner) async {
          await inner.execute(_insertSql, [i]);
        });
      }
    });
    await db.execute('DELETE FROM items');
  });

  await _measure(db, 'rollback fanout x$_writeFanout', () async {
    await db.transaction((tx) async {
      for (var i = 0; i < _writeFanout; i++) {
        try {
          await tx.transaction((inner) async {
            await inner.execute(_insertSql, [i]);
            throw StateError('rollback $i');
          });
        } on StateError {
          // Expected: each inner savepoint rolls back independently.
        }
      }
    });
    await db.execute('DELETE FROM items');
  });

  await _measure(db, 'deep chain $_deepRepeats x depth=$_depth', () async {
    await db.transaction((tx) async {
      for (var i = 0; i < _deepRepeats; i++) {
        await _deep(tx, 1);
      }
    });
    await db.execute('DELETE FROM items');
  });

  await db.close();
  await tmp.delete(recursive: true);
}

Future<void> _measure(
  Database db,
  String label,
  Future<void> Function() body,
) async {
  for (var i = 0; i < _warmup; i++) {
    await body();
  }

  final samples = <double>[];
  for (var i = 0; i < _samples; i++) {
    final sw = Stopwatch()..start();
    await body();
    sw.stop();
    samples.add(sw.elapsedMicroseconds / 1000.0);
  }

  samples.sort();
  final median = samples[samples.length ~/ 2];
  stdout.writeln(
    '| $label | ${median.toStringAsFixed(3)} '
    '| ${samples.first.toStringAsFixed(3)} '
    '| ${samples.last.toStringAsFixed(3)} |',
  );
}

Future<void> _deep(Transaction tx, int level) {
  if (level == _depth) {
    return tx.transaction((inner) => inner.execute(_insertSql, [level]));
  }
  return tx.transaction((inner) => _deep(inner, level + 1));
}
