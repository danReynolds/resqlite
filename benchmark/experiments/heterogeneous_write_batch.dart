// Focused benchmark for exp 208: explicit heterogeneous write batching.
//
// Compares the current public way to apply many different write statements in
// one transaction (interactive transaction + await tx.execute per statement)
// against the prototype one-request statement batch.

import 'dart:io';

import 'package:resqlite/resqlite.dart';

const _rounds = 7;
const _pairsPerRound = 200;

Future<void> main(List<String> args) async {
  final order = _parseOrder(args);
  final dir = await Directory.systemTemp.createTemp('resqlite_hetero_batch_');
  try {
    print('=== Heterogeneous write batch experiment (exp 208) ===');
    print('order: $order');
    print('rounds: $_rounds; statements per round: ${_pairsPerRound * 2}\n');

    final transactionLoop = <int>[];
    final statementBatch = <int>[];

    for (var round = 0; round < _rounds; round++) {
      if (order == _Order.transactionFirst) {
        transactionLoop.add(await _transactionLoopRound(dir.path, round));
        statementBatch.add(await _statementBatchRound(dir.path, round));
      } else {
        statementBatch.add(await _statementBatchRound(dir.path, round));
        transactionLoop.add(await _transactionLoopRound(dir.path, round));
      }
    }

    _report(
      'transaction loop (${_pairsPerRound * 2} statements)',
      transactionLoop,
    );
    _report(
      'statement batch (${_pairsPerRound * 2} statements)',
      statementBatch,
    );
  } finally {
    await dir.delete(recursive: true);
  }
}

enum _Order { transactionFirst, batchFirst }

_Order _parseOrder(List<String> args) {
  for (final arg in args) {
    if (arg == '--order=transaction-first') return _Order.transactionFirst;
    if (arg == '--order=batch-first') return _Order.batchFirst;
  }
  return _Order.transactionFirst;
}

Future<Database> _freshDb(String dirPath, String label) async {
  final db = await Database.open('$dirPath/$label.db');
  await db.execute(
    'CREATE TABLE items(id INTEGER PRIMARY KEY, body TEXT NOT NULL, n INTEGER NOT NULL)',
  );
  await db.execute(
    'CREATE TABLE counters(name TEXT PRIMARY KEY, value INTEGER NOT NULL)',
  );
  await db.execute('INSERT INTO counters(name, value) VALUES (?, ?)', [
    'items',
    0,
  ]);
  return db;
}

List<WriteStatement> _statements() {
  return [
    for (var i = 0; i < _pairsPerRound; i++) ...[
      WriteStatement('INSERT INTO items(body, n) VALUES (?, ?)', ['row_$i', i]),
      const WriteStatement(
        'UPDATE counters SET value = value + 1 WHERE name = ?',
        ['items'],
      ),
    ],
  ];
}

Future<int> _transactionLoopRound(String dirPath, int round) async {
  final db = await _freshDb(dirPath, 'tx_$round');
  final statements = _statements();
  final sw = Stopwatch()..start();
  await db.transaction((tx) async {
    final results = <WriteResult>[];
    for (final statement in statements) {
      results.add(await tx.execute(statement.sql, statement.parameters));
    }
    if (results.length != statements.length) {
      throw StateError('missing transaction-loop results');
    }
  });
  sw.stop();
  await _verify(db);
  await db.close();
  return sw.elapsedMicroseconds;
}

Future<int> _statementBatchRound(String dirPath, int round) async {
  final db = await _freshDb(dirPath, 'batch_$round');
  final statements = _statements();
  final sw = Stopwatch()..start();
  final results = await db.executeStatements(statements);
  sw.stop();
  if (results.length != statements.length) {
    throw StateError('missing statement-batch results');
  }
  await _verify(db);
  await db.close();
  return sw.elapsedMicroseconds;
}

Future<void> _verify(Database db) async {
  final itemRows = await db.select('SELECT COUNT(*) AS c FROM items');
  final counterRows = await db.select(
    'SELECT value FROM counters WHERE name = ?',
    ['items'],
  );
  if (itemRows.single['c'] != _pairsPerRound ||
      counterRows.single['value'] != _pairsPerRound) {
    throw StateError('verification failed');
  }
}

void _report(String name, List<int> roundsUs) {
  final sorted = [...roundsUs]..sort();
  final median = sorted[sorted.length ~/ 2];
  final ms = (median / 1000).toStringAsFixed(3);
  final all = roundsUs.map((us) => (us / 1000).toStringAsFixed(3)).join(', ');
  print('$name: median ${ms}ms  rounds [${all}]ms');
}
