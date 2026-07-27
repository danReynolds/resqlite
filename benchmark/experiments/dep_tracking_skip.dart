// Benchmark: dep-tracking skip when no stream consumers (exp 182).
//
// Three shapes, run identically on baseline and candidate checkouts.
// Each shape opens ONE database per shape (not per round), warms up,
// then measures `_rounds` independent timing iterations against that
// same database. This isolates the per-write savings from the
// per-database open/close cost, which dominates the variance in tighter
// shapes.

import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';

const _rounds = 9;
const _warmupRounds = 3;
const _sequentialWrites = 2000;
const _wideBatchRows = 10000;
const _wideBatchParams = 20;
const _streamGuardWrites = 1000;

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('resqlite_dep_skip_');

  print('=== Dep-tracking skip experiment (exp 182) ===\n');

  print(await _sequentialAwaitedShape(dir.path));
  print(await _wideBatchShape(dir.path));
  print(await _txLoopShape(dir.path));
  print(await _streamGuardShape(dir.path));

  await dir.delete(recursive: true);
  exit(0);
}

const _txWritesPerTx = 100;
const _txCount = 50;

Future<String> _txLoopShape(String dirPath) async {
  final db = await Database.open('$dirPath/txloop.db');
  await db.execute(_itemsCreate);
  for (var w = 0; w < _warmupRounds; w++) {
    for (var t = 0; t < _txCount; t++) {
      await db.transaction((tx) async {
        for (var i = 0; i < _txWritesPerTx; i++) {
          await tx.execute(_itemsInsert, ['row_${t}_$i', i]);
        }
      });
    }
    await db.execute('DELETE FROM items');
  }
  final timings = <int>[];
  for (var r = 0; r < _rounds; r++) {
    final sw = Stopwatch()..start();
    for (var t = 0; t < _txCount; t++) {
      await db.transaction((tx) async {
        for (var i = 0; i < _txWritesPerTx; i++) {
          await tx.execute(_itemsInsert, ['row_${t}_$i', i]);
        }
      });
    }
    sw.stop();
    timings.add(sw.elapsedMicroseconds);
    await db.execute('DELETE FROM items');
  }
  await db.close();
  return _format(
    'tx-loop-no-streams ($_txCount tx x $_txWritesPerTx writes)',
    timings,
  );
}

const _itemsCreate =
    'CREATE TABLE items(id INTEGER PRIMARY KEY, body TEXT NOT NULL, n INTEGER NOT NULL)';
const _itemsInsert = 'INSERT INTO items(body, n) VALUES (?, ?)';

Future<String> _sequentialAwaitedShape(String dirPath) async {
  final db = await Database.open('$dirPath/seq.db');
  await db.execute(_itemsCreate);
  // Warmup.
  for (var w = 0; w < _warmupRounds; w++) {
    for (var i = 0; i < _sequentialWrites; i++) {
      await db.execute(_itemsInsert, ['row_${w}_$i', i]);
    }
    await db.execute('DELETE FROM items');
  }
  final timings = <int>[];
  for (var r = 0; r < _rounds; r++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < _sequentialWrites; i++) {
      await db.execute(_itemsInsert, ['row_${r}_$i', i]);
    }
    sw.stop();
    timings.add(sw.elapsedMicroseconds);
    await db.execute('DELETE FROM items');
  }
  await db.close();
  return _format(
    'sequential-awaited ($_sequentialWrites writes, no streams)',
    timings,
  );
}

String _wideCreate() {
  final cols = [
    for (var i = 0; i < _wideBatchParams; i++) 'c$i TEXT',
  ].join(', ');
  return 'CREATE TABLE wide(id INTEGER PRIMARY KEY, $cols)';
}

String _wideInsert() {
  final cols = [for (var i = 0; i < _wideBatchParams; i++) 'c$i'].join(', ');
  final qs = List.filled(_wideBatchParams, '?').join(', ');
  return 'INSERT INTO wide($cols) VALUES ($qs)';
}

List<Object?> _wideRow(int i) {
  return [for (var p = 0; p < _wideBatchParams; p++) 'r${i}_c$p'];
}

Future<String> _wideBatchShape(String dirPath) async {
  final db = await Database.open('$dirPath/wide.db');
  await db.execute(_wideCreate());
  final insertSql = _wideInsert();
  final rows = [for (var i = 0; i < _wideBatchRows; i++) _wideRow(i)];
  for (var w = 0; w < _warmupRounds; w++) {
    await db.executeBatch(insertSql, rows);
    await db.execute('DELETE FROM wide');
  }
  final timings = <int>[];
  for (var r = 0; r < _rounds; r++) {
    final sw = Stopwatch()..start();
    await db.executeBatch(insertSql, rows);
    sw.stop();
    timings.add(sw.elapsedMicroseconds);
    await db.execute('DELETE FROM wide');
  }
  await db.close();
  return _format(
    'wide-batch-no-streams ($_wideBatchRows rows x $_wideBatchParams params)',
    timings,
  );
}

Future<String> _streamGuardShape(String dirPath) async {
  final db = await Database.open('$dirPath/guard.db');
  await db.execute(_itemsCreate);
  final sub = db.stream('SELECT COUNT(*) AS n FROM items').listen((_) {});
  // Allow the stream's initial query to settle before timing.
  await Future<void>.delayed(const Duration(milliseconds: 50));
  for (var w = 0; w < _warmupRounds; w++) {
    for (var i = 0; i < _streamGuardWrites; i++) {
      await db.execute(_itemsInsert, ['row_${w}_$i', i]);
    }
    await db.execute('DELETE FROM items');
  }
  final timings = <int>[];
  for (var r = 0; r < _rounds; r++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < _streamGuardWrites; i++) {
      await db.execute(_itemsInsert, ['row_${r}_$i', i]);
    }
    sw.stop();
    timings.add(sw.elapsedMicroseconds);
    await db.execute('DELETE FROM items');
  }
  await sub.cancel();
  await db.close();
  return _format(
    'with-streams guardrail ($_streamGuardWrites writes, 1 stream)',
    timings,
  );
}

String _format(String name, List<int> roundsUs) {
  final sorted = [...roundsUs]..sort();
  final median = sorted[sorted.length ~/ 2];
  final ms = (median / 1000).toStringAsFixed(3);
  final all = roundsUs.map((us) => (us / 1000).toStringAsFixed(3)).join(', ');
  return '$name: median ${ms}ms  rounds [${all}]ms';
}
