// EXP-246 A/B: slot-count vs byte-count sacrifice trigger, end-to-end.
//   baseline (bytes):  dart run benchmark/experiments/slot_sacrifice_ab.dart
//   candidate (slots): dart run -DRESQLITE_SLOT_TRIGGER=true ...
//
// Exp 245 measured that SendPort.send's copy cost tracks the flat-list SLOT
// COUNT (rows x cols), not payload bytes — strings/immutable leaves are shared
// on send for free, and Isolate.exit only overtakes send past ~48k slots. So
// the byte trigger misroutes big-STRING results (few slots, many bytes) into a
// needless sacrifice + reader respawn. This A/B confirms the slot trigger fixes
// the routing (sacrifice count) without regressing end-to-end latency.
//
// Shapes (per select):
//   bigstr : 4 rows x 1 TEXT x 100KB = 4 slots, ~400KB bytes   -> MISROUTE
//   band   : 10k rows x 4 int cols   = 40k slots, ~320KB bytes -> byte sacrifices,
//            but Exp A says send wins below the ~48k-slot crossover
//   large  : 10k rows x 20 int cols  = 200k slots, ~1.6MB      -> both sacrifice
//   medium : 5k rows x 4 int cols    = 20k slots, ~160KB       -> both send
//   small  : 100 rows x 4 int cols   = 400 slots               -> both send
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/reader/read_worker.dart' show kSlotSacrificeTrigger;
import 'package:resqlite/src/reader/reader_pool.dart' show ReaderPool;

const _warmup = 20;
const _iters = 200;
const _samples = 9;

double _median(List<double> xs) {
  final s = [...xs]..sort();
  return s[s.length ~/ 2];
}

Future<void> main() async {
  final lane = kSlotSacrificeTrigger ? 'slots' : 'bytes';
  final tmp = await Directory.systemTemp.createTemp('resqlite-exp246-');
  final db = await Database.open('${tmp.path}/a.db');

  // Wide numeric table.
  final cols = [for (var c = 0; c < 20; c++) 'c$c'];
  await db.execute('CREATE TABLE t(${cols.map((c) => '$c INTEGER').join(', ')})');
  final ph = List.filled(20, '?').join(', ');
  await db.executeBatch(
    'INSERT INTO t(${cols.join(', ')}) VALUES ($ph)',
    [for (var r = 0; r < 10000; r++) [for (var c = 0; c < 20; c++) r * 20 + c]],
  );

  // Big-string table: 4 rows x one 100 KB TEXT column.
  final big = String.fromCharCodes(List.filled(100 * 1024, 65));
  await db.execute('CREATE TABLE ts(s TEXT)');
  await db.executeBatch('INSERT INTO ts(s) VALUES (?)', [for (var i = 0; i < 4; i++) [big]]);

  final shapes = <String, String>{
    'bigstr': 'SELECT s FROM ts',
    'band': 'SELECT c0, c1, c2, c3 FROM t',
    'large': 'SELECT ${cols.join(', ')} FROM t',
    'medium': 'SELECT c0, c1, c2, c3 FROM t LIMIT 5000',
    'small': 'SELECT c0, c1, c2, c3 FROM t LIMIT 100',
  };

  stdout.writeln('| lane | shape | median µs/select | sacrifices/select |');
  stdout.writeln('|---|---|---:|---:|');

  for (final entry in shapes.entries) {
    final sql = entry.value;
    for (var i = 0; i < _warmup; i++) {
      await db.select(sql);
    }
    ReaderPool.debugSacrificeCount = 0;
    final med = <double>[];
    for (var s = 0; s < _samples; s++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < _iters; i++) {
        await db.select(sql);
      }
      sw.stop();
      med.add(sw.elapsedMicroseconds / _iters);
    }
    final sacPerSelect =
        ReaderPool.debugSacrificeCount / (_samples * _iters);
    stdout.writeln('| $lane | ${entry.key} '
        '| ${_median(med).toStringAsFixed(1)} '
        '| ${sacPerSelect.toStringAsFixed(2)} |');
  }

  await db.close();
  await tmp.delete(recursive: true);
}
