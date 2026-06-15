// Benchmark: long-text 32KB unchanged-fanout (exp 170).
//
// Targets `resqlite_query_hash`'s `fnv_combine_bytes` byte-stream loop.
// 8 unchanged streams each hash 64 rows of 32KB TEXT cells per writer
// invalidation; the loop body runs 4096 8-byte chunks per cell, so the
// whole burst hashes ~16 MB. Used as the A/B harness for the exp 170
// 16-byte fold vs the baseline 8-byte fold (exp 110) inherited from the
// `fnv_combine_bytes` path.
//
// Run the same script on both baseline and candidate checkouts. Compare
// the medians across rounds.

// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';

const _rounds = 9;
const _warmup = 2;
const _unchangedStreamCount = 8;
const _rowCount = 64;
const _cellBytes = 32 * 1024;

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('resqlite_long_text32_');

  print('=== Long-text 32KB unchanged-fanout (exp 170) ===');
  print(
    '$_unchangedStreamCount unchanged streams '
    'x $_rowCount rows x ${_cellBytes ~/ 1024} KB TEXT, '
    '$_warmup warmup + $_rounds measured rounds',
  );
  print('');

  final measured = <int>[];
  for (var round = 0; round < _warmup + _rounds; round++) {
    final us = await _roundUs(dir.path, round);
    final tag = round < _warmup ? 'warmup' : 'round ${round - _warmup}';
    print('$tag : ${(us / 1000).toStringAsFixed(3)} ms');
    if (round >= _warmup) measured.add(us);
  }

  measured.sort();
  final median = measured[measured.length ~/ 2];
  final p90 = measured[(measured.length * 9) ~/ 10];
  final min = measured.first;
  final max = measured.last;

  print('');
  print('--- Results ---');
  print('median: ${(median / 1000).toStringAsFixed(3)} ms');
  print('p90   : ${(p90 / 1000).toStringAsFixed(3)} ms');
  print('min   : ${(min / 1000).toStringAsFixed(3)} ms');
  print('max   : ${(max / 1000).toStringAsFixed(3)} ms');

  await dir.delete(recursive: true);
  exit(0);
}

Future<int> _roundUs(String dirPath, int round) async {
  final db = await Database.open('$dirPath/r$round.db');
  await db.execute(
    'CREATE TABLE long_items32('
    'id INTEGER PRIMARY KEY, body TEXT NOT NULL, marker INTEGER NOT NULL)',
  );
  const insertSql =
      'INSERT INTO long_items32(id, body, marker) VALUES (?, ?, ?)';
  await db.executeBatch(insertSql, [
    for (var i = 0; i < _rowCount; i++)
      [i, _payload(_cellBytes, i), i],
  ]);

  final unchangedEmissions = List<int>.filled(_unchangedStreamCount, 0);
  final unchangedReady = <Completer<void>>[
    for (var i = 0; i < _unchangedStreamCount; i++) Completer<void>(),
  ];
  final unchangedSubs = <StreamSubscription>[];

  for (var s = 0; s < _unchangedStreamCount; s++) {
    final sub = db
        .stream(
          'SELECT id, body, $s as sid FROM long_items32 '
          'WHERE id < $_rowCount ORDER BY id',
        )
        .listen((_) {
          unchangedEmissions[s]++;
          if (!unchangedReady[s].isCompleted) unchangedReady[s].complete();
        });
    unchangedSubs.add(sub);
  }

  // Barrier stream: registered after the unchanged streams. Its result
  // changes on every insert, so its second emission proves the rerun
  // wave has reached the main isolate.
  final barrierReady = Completer<void>();
  Completer<void>? waitBarrier;
  final barrierSub = db.stream('SELECT id, body FROM long_items32 ORDER BY id')
      .listen((_) {
        if (!barrierReady.isCompleted) {
          barrierReady.complete();
        } else if (waitBarrier != null && !waitBarrier.isCompleted) {
          waitBarrier.complete();
        }
      });

  await Future.wait(unchangedReady.map((c) => c.future))
      .timeout(const Duration(seconds: 60));
  await barrierReady.future.timeout(const Duration(seconds: 60));

  final before = List<int>.from(unchangedEmissions);
  waitBarrier = Completer<void>();

  final sw = Stopwatch()..start();
  final newId = 1_000_000 + round;
  await db.execute(insertSql, [newId, _payload(_cellBytes, newId), round]);
  await waitBarrier.future.timeout(const Duration(seconds: 60));
  sw.stop();

  for (var s = 0; s < _unchangedStreamCount; s++) {
    if (unchangedEmissions[s] != before[s]) {
      throw StateError('Unchanged stream $s emitted unexpectedly.');
    }
  }

  await barrierSub.cancel();
  for (final sub in unchangedSubs) {
    await sub.cancel();
  }
  await db.close();

  return sw.elapsedMicroseconds;
}

String _payload(int targetBytes, int seed) {
  final prefix = 'seed_$seed:';
  const chunk = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final buffer = StringBuffer(prefix);
  while (buffer.length < targetBytes) {
    buffer.write(chunk);
  }
  return buffer.toString().substring(0, targetBytes);
}
