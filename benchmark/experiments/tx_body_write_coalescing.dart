// Benchmark: transaction body write coalescing (exp 213 moonshot).
//
// Attacks the assumption that every `await tx.execute(...)` inside
// `db.transaction((tx) async {...})` requires its own writer round-trip.
// The candidate buffers concurrent (Future.wait pattern) execute calls in
// the Transaction and flushes them as a single MultiExecuteRequest against
// the still-open transaction.
//
// Four shapes, run identically on baseline and candidate checkouts:
//
// 1. tx-sequential-await — `await tx.execute(...)` per write inside one
//    transaction. Load-bearing guardrail: this is the common pattern and
//    the candidate must not regress it (the buffered path adds a
//    schedule-microtask hop before the send).
// 2. tx-burst-future-wait — `await Future.wait([tx.execute(...), ...])`
//    inside one transaction. Moonshot target: N round-trips ought to
//    collapse toward 1 because all N are buffered in the same microtask.
// 3. tx-single-write — one execute per transaction. Edge case: verifies
//    the buffered singleton path stays close to the pre-213 single-send
//    cost.
// 4. tx-interleaved-select — execute + select interleaved inside one
//    transaction. Verifies the explicit-flush-before-select path preserves
//    read-your-writes semantics without pathological overhead.

import 'dart:io';

import 'package:resqlite/resqlite.dart';

const _rounds = 7;
const _sequentialTxCount = 100;
const _sequentialWritesPerTx = 20;
const _burstTxCount = 20;
const _burstWritesPerTx = 100;
const _singleTxCount = 1000;
const _interleavedTxCount = 50;
const _interleavedWritesPerTx = 10;

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('resqlite_tx_coalesce_');

  print('=== Transaction body write coalescing (exp 213 moonshot) ===\n');

  final seq = <int>[];
  final burst = <int>[];
  final single = <int>[];
  final interleaved = <int>[];

  for (var round = 0; round < _rounds; round++) {
    seq.add(await _sequentialAwaitRound(dir.path, round));
    burst.add(await _burstFutureWaitRound(dir.path, round));
    single.add(await _singleWriteRound(dir.path, round));
    interleaved.add(await _interleavedSelectRound(dir.path, round));
  }

  _report(
    'tx-sequential-await ($_sequentialTxCount tx x $_sequentialWritesPerTx)',
    seq,
  );
  _report(
    'tx-burst-future-wait ($_burstTxCount tx x $_burstWritesPerTx)',
    burst,
  );
  _report('tx-single-write ($_singleTxCount tx x 1)', single);
  _report(
    'tx-interleaved-select ($_interleavedTxCount tx x $_interleavedWritesPerTx w/select)',
    interleaved,
  );

  await dir.delete(recursive: true);
  exit(0);
}

const _createSql =
    'CREATE TABLE items(id INTEGER PRIMARY KEY, body TEXT NOT NULL, n INTEGER NOT NULL)';
const _insertSql = 'INSERT INTO items(body, n) VALUES (?, ?)';
const _countSql = 'SELECT COUNT(*) AS c FROM items';

Future<Database> _freshDb(String dirPath, String label) async {
  final db = await Database.open('$dirPath/$label.db');
  await db.execute(_createSql);
  return db;
}

Future<int> _sequentialAwaitRound(String dirPath, int round) async {
  final db = await _freshDb(dirPath, 'seq_$round');
  final sw = Stopwatch()..start();
  for (var t = 0; t < _sequentialTxCount; t++) {
    await db.transaction((tx) async {
      for (var i = 0; i < _sequentialWritesPerTx; i++) {
        await tx.execute(_insertSql, ['row_${t}_$i', i]);
      }
    });
  }
  sw.stop();
  await db.close();
  return sw.elapsedMicroseconds;
}

Future<int> _burstFutureWaitRound(String dirPath, int round) async {
  final db = await _freshDb(dirPath, 'burst_$round');
  final sw = Stopwatch()..start();
  for (var t = 0; t < _burstTxCount; t++) {
    await db.transaction((tx) async {
      await Future.wait([
        for (var i = 0; i < _burstWritesPerTx; i++)
          tx.execute(_insertSql, ['row_${t}_$i', i]),
      ]);
    });
  }
  sw.stop();
  await db.close();
  return sw.elapsedMicroseconds;
}

Future<int> _singleWriteRound(String dirPath, int round) async {
  final db = await _freshDb(dirPath, 'single_$round');
  final sw = Stopwatch()..start();
  for (var t = 0; t < _singleTxCount; t++) {
    await db.transaction((tx) async {
      await tx.execute(_insertSql, ['row_$t', t]);
    });
  }
  sw.stop();
  await db.close();
  return sw.elapsedMicroseconds;
}

Future<int> _interleavedSelectRound(String dirPath, int round) async {
  final db = await _freshDb(dirPath, 'interleaved_$round');
  final sw = Stopwatch()..start();
  for (var t = 0; t < _interleavedTxCount; t++) {
    await db.transaction((tx) async {
      for (var i = 0; i < _interleavedWritesPerTx; i++) {
        await tx.execute(_insertSql, ['row_${t}_$i', i]);
        // The select forces a flush of any buffered writes so uncommitted
        // rows are visible — exercises the drain-before-read path.
        await tx.select(_countSql);
      }
    });
  }
  sw.stop();
  await db.close();
  return sw.elapsedMicroseconds;
}

void _report(String name, List<int> roundsUs) {
  final sorted = [...roundsUs]..sort();
  final median = sorted[sorted.length ~/ 2];
  final ms = (median / 1000).toStringAsFixed(3);
  final all = roundsUs.map((us) => (us / 1000).toStringAsFixed(3)).join(', ');
  print('$name: median ${ms}ms  rounds [$all]ms');
}
