// Benchmark: writer round-trip overhead and pipelining (exp 159).
//
// Three shapes, run identically on baseline and candidate checkouts:
//
// 1. sequential-awaited — `await db.execute(...)` per write. Measures the
//    per-round-trip floor: persistent reply port, cached worker SendPort,
//    and sync completion engage here; pipelining cannot (the caller never
//    has two writes outstanding).
// 2. concurrent-burst — `Future.wait` over a burst of independent
//    `db.execute(...)` calls. With send-gated locking the requests queue
//    on the worker's port back-to-back, overlapping worker-side execution
//    with main-isolate reply processing. This is the pipelining shape.
// 3. transaction-guardrail — transactions hold the lock across their whole
//    round-trip exactly as before; this shape exists to catch regressions.

import 'dart:io';

import 'package:resqlite/resqlite.dart';

const _rounds = 7;
const _sequentialWrites = 2000;
const _burstSize = 200;
const _burstsPerRound = 10;
const _txPerRound = 50;
const _writesPerTx = 10;

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('resqlite_pipelining_');

  print('=== Writer pipelining experiment (exp 159) ===\n');

  final sequential = <int>[];
  final burst = <int>[];
  final tx = <int>[];

  for (var round = 0; round < _rounds; round++) {
    sequential.add(await _sequentialRound(dir.path, round));
    burst.add(await _burstRound(dir.path, round));
    tx.add(await _txRound(dir.path, round));
  }

  _report('sequential-awaited ($_sequentialWrites writes)', sequential);
  _report('concurrent-burst ($_burstsPerRound x $_burstSize writes)', burst);
  _report('transaction-guardrail ($_txPerRound tx x $_writesPerTx)', tx);

  await dir.delete(recursive: true);
  exit(0);
}

const _createSql =
    'CREATE TABLE items(id INTEGER PRIMARY KEY, body TEXT NOT NULL, n INTEGER NOT NULL)';
const _insertSql = 'INSERT INTO items(body, n) VALUES (?, ?)';

Future<Database> _freshDb(String dirPath, String label) async {
  final db = await Database.open('$dirPath/$label.db');
  await db.execute(_createSql);
  return db;
}

Future<int> _sequentialRound(String dirPath, int round) async {
  final db = await _freshDb(dirPath, 'seq_$round');
  final sw = Stopwatch()..start();
  for (var i = 0; i < _sequentialWrites; i++) {
    await db.execute(_insertSql, ['row_$i', i]);
  }
  sw.stop();
  await db.close();
  return sw.elapsedMicroseconds;
}

Future<int> _burstRound(String dirPath, int round) async {
  final db = await _freshDb(dirPath, 'burst_$round');
  final sw = Stopwatch()..start();
  for (var b = 0; b < _burstsPerRound; b++) {
    await Future.wait([
      for (var i = 0; i < _burstSize; i++)
        db.execute(_insertSql, ['row_${b}_$i', i]),
    ]);
  }
  sw.stop();
  await db.close();
  return sw.elapsedMicroseconds;
}

Future<int> _txRound(String dirPath, int round) async {
  final db = await _freshDb(dirPath, 'tx_$round');
  final sw = Stopwatch()..start();
  for (var t = 0; t < _txPerRound; t++) {
    await db.transaction((txn) async {
      for (var i = 0; i < _writesPerTx; i++) {
        await txn.execute(_insertSql, ['row_${t}_$i', i]);
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
  print('$name: median ${ms}ms  rounds [${all}]ms');
}
