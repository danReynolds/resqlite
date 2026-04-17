// ignore_for_file: avoid_print

/// Repro harness for the A11b iter-2 drain pathology — runs the same
/// shape that originally timed out at 30+ seconds on iteration 2 and
/// prints per-iteration drain timings. With the coalescing fix, every
/// iteration should drain quickly.
///
/// Run:
///   dart run tool/verify_coalescing_fix.dart
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:resqlite/resqlite.dart';

const _streamCount = 100;
const _itemCount = 10000;
const _writeCount = 200;
const _iterations = 3;

Future<void> main() async {
  print('Verifying invalidation coalescing fix');
  print('Pre-fix expectation: iter 0 fast (~50ms), iter 1+ blow up');
  print('Post-fix expectation: every iteration drains quickly');
  print('=' * 60);

  final tempDir = await Directory.systemTemp.createTemp('verify_coalesce_');
  try {
    final db = await Database.open('${tempDir.path}/test.db');
    try {
      await _seed(db);

      for (var iter = 0; iter < _iterations; iter++) {
        final (drainMs, writeBurstMs) = await _singleIteration(iter);
        print('iter $iter  drain=${drainMs}ms  writes=${writeBurstMs}ms');
      }
    } finally {
      await db.close();
    }
  } finally {
    await tempDir.delete(recursive: true);
  }
}

late Database _db;

Future<void> _seed(Database db) async {
  _db = db;
  await db.execute('CREATE TABLE items('
      'id INTEGER PRIMARY KEY, '
      'owner_id INTEGER NOT NULL, '
      'value INTEGER NOT NULL)');
  await db.execute('CREATE INDEX items_owner ON items(owner_id)');
  final itemsPerOwner = _itemCount ~/ _streamCount;
  await db.executeBatch(
    'INSERT INTO items(owner_id, value) VALUES (?, ?)',
    [
      for (var i = 0; i < _itemCount; i++)
        [(i ~/ itemsPerOwner) + 1, 0],
    ],
  );
}

Future<(int drainMs, int writeBurstMs)> _singleIteration(int iter) async {
  final prng = math.Random(0xBEEF ^ iter);
  final emitCounts = List<int>.filled(_streamCount, 0);
  final subs = <StreamSubscription<List<Map<String, Object?>>>>[];

  final drainSw = Stopwatch()..start();
  for (var i = 0; i < _streamCount; i++) {
    final idx = i;
    final sub = _db
        .stream(
          'SELECT id, value FROM items WHERE owner_id = ? ORDER BY id',
          [i + 1],
        )
        .listen((_) => emitCounts[idx]++);
    subs.add(sub);
  }

  final drainDeadline = DateTime.now().add(const Duration(minutes: 2));
  while (!emitCounts.every((c) => c >= 1)) {
    if (DateTime.now().isAfter(drainDeadline)) {
      drainSw.stop();
      print('  TIMEOUT in iter $iter after ${drainSw.elapsedMilliseconds}ms');
      for (final sub in subs) await sub.cancel();
      return (-1, 0);
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  drainSw.stop();
  final drainMs = drainSw.elapsedMilliseconds;

  final writeSw = Stopwatch()..start();
  for (var w = 0; w < _writeCount; w++) {
    final id = prng.nextInt(_itemCount) + 1;
    await _db
        .execute('UPDATE items SET value = ? WHERE id = ?', [w, id]);
  }

  // Settle.
  var lastSum = emitCounts.reduce((a, b) => a + b);
  const quietWindow = Duration(milliseconds: 200);
  final quietDeadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(quietDeadline)) {
    await Future<void>.delayed(quietWindow);
    final nowSum = emitCounts.reduce((a, b) => a + b);
    if (nowSum == lastSum) break;
    lastSum = nowSum;
  }
  writeSw.stop();

  for (final sub in subs) await sub.cancel();
  return (drainMs, writeSw.elapsedMilliseconds);
}
