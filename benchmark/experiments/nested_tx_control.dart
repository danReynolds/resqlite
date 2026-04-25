import 'dart:io';

import 'package:resqlite/resqlite.dart';

Future<void> main(List<String> args) async {
  final repeats = int.parse(_arg(args, '--repeats') ?? '7');
  final cycles = int.parse(_arg(args, '--cycles') ?? '500');
  final tempDir = await Directory.systemTemp.createTemp('resqlite_nested_tx_');
  final db = await Database.open('${tempDir.path}/bench.db');

  try {
    await db.execute('CREATE TABLE items(id INTEGER PRIMARY KEY, n INTEGER)');
    await db.execute('INSERT INTO items(n) VALUES (0)');

    await _nestedCommit(db, 25);
    await _nestedRollback(db, 25);

    final commitSamples = <double>[];
    final rollbackSamples = <double>[];

    for (var r = 0; r < repeats; r++) {
      var sw = Stopwatch()..start();
      await _nestedCommit(db, cycles);
      sw.stop();
      commitSamples.add(sw.elapsedMicroseconds / 1000);

      sw = Stopwatch()..start();
      await _nestedRollback(db, cycles);
      sw.stop();
      rollbackSamples.add(sw.elapsedMicroseconds / 1000);
    }

    _print('nested_commit', commitSamples, cycles);
    _print('nested_rollback', rollbackSamples, cycles);
  } finally {
    await db.close();
    await tempDir.delete(recursive: true);
  }
}

Future<void> _nestedCommit(Database db, int cycles) async {
  await db.transaction((tx) async {
    for (var i = 0; i < cycles; i++) {
      await tx.transaction((inner) async {
        await inner.execute('UPDATE items SET n = n + 1 WHERE id = 1');
      });
    }
  });
}

Future<void> _nestedRollback(Database db, int cycles) async {
  await db.transaction((tx) async {
    for (var i = 0; i < cycles; i++) {
      try {
        await tx.transaction((inner) async {
          await inner.execute('UPDATE items SET n = n + 1 WHERE id = 1');
          throw const _Rollback();
        });
      } on _Rollback {
        // Expected: measure SAVEPOINT + ROLLBACK TO + RELEASE overhead.
      }
    }
  });
}

void _print(String name, List<double> samples, int cycles) {
  samples.sort();
  final median = samples[samples.length ~/ 2];
  final perCycleUs = median * 1000 / cycles;
  stdout.writeln(
    '${name.padRight(16)} median=${median.toStringAsFixed(3)}ms '
    'per_cycle=${perCycleUs.toStringAsFixed(2)}us '
    'min=${samples.first.toStringAsFixed(3)}ms '
    'max=${samples.last.toStringAsFixed(3)}ms',
  );
}

String? _arg(List<String> args, String name) {
  final prefix = '$name=';
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  return null;
}

final class _Rollback {
  const _Rollback();
}
