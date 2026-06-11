// Profile-mode audit: sustained concurrent reads vs reader-pool size
// (exp 162).
//
// Fills the long-open stream-rerun-dispatch candidate ("a long-running
// concurrent-reads workload that sustains parked dispatchers past pool
// size", added 2026-04-30 after exp 115): N read clients loop point and
// range selects with no streams and no writes, so column elision and
// hash suppression cannot elide anything — every request must cross the
// pool. Reports throughput plus the exp 115 dispatcher counters, the
// non-wall-time gate exp 114/105 lacked.
//
// Run (one pool size per invocation; the cap is compile-time):
//   dart run -DRESQLITE_PROFILE=true [-DRESQLITE_READER_CAP=n] \
//     benchmark/profile/sustained_concurrent_reads_audit.dart
//
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/profile_counters.dart';

const _rows = 5000;
const _clientCounts = [8, 16, 32];
const _opsPerClient = 400;

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('resqlite_screads_');
  final db = await Database.open('${dir.path}/t.db');
  await db.execute(
    'CREATE TABLE items(id INTEGER PRIMARY KEY, grp INTEGER NOT NULL, '
    'body TEXT NOT NULL)',
  );
  await db.executeBatch('INSERT INTO items(id, grp, body) VALUES (?, ?, ?)', [
    for (var i = 1; i <= _rows; i++) [i, i % 50, 'body_$i' * 4],
  ]);

  const cap = int.fromEnvironment('RESQLITE_READER_CAP');
  print('# Sustained concurrent reads (pool cap: '
      '${cap > 0 ? cap : 'default'})\n');
  print('| clients | ops | wall ms | ops/ms | parked_total | max_parked '
      '| wake_retries |');
  print('|---:|---:|---:|---:|---:|---:|---:|');

  for (final clients in _clientCounts) {
    // Warmup pass so statement caches and schema caches are hot.
    await Future.wait([
      for (var c = 0; c < clients; c++) _client(db, c, 40),
    ]);

    ProfileCounters.reset();
    final sw = Stopwatch()..start();
    await Future.wait([
      for (var c = 0; c < clients; c++) _client(db, c, _opsPerClient),
    ]);
    sw.stop();
    final snap = ProfileCounters.snapshot();
    final ops = clients * _opsPerClient;
    print(
      '| $clients | $ops | ${(sw.elapsedMicroseconds / 1000).toStringAsFixed(2)} '
      '| ${(ops / (sw.elapsedMicroseconds / 1000)).toStringAsFixed(1)} '
      '| ${snap['dispatcher_parked_total']} '
      '| ${snap['dispatcher_max_parked_concurrent']} '
      '| ${snap['dispatcher_wake_retry_total']} |',
    );
  }

  await db.close();
  await dir.delete(recursive: true);
  exit(0);
}

Future<void> _client(Database db, int id, int ops) async {
  final prng = math.Random(id * 7919 + 17);
  for (var i = 0; i < ops; i++) {
    if (i % 4 == 0) {
      await db.select(
        'SELECT id, grp, body FROM items WHERE grp = ? LIMIT 20',
        [prng.nextInt(50)],
      );
    } else {
      await db.select('SELECT id, body FROM items WHERE id = ?', [
        prng.nextInt(_rows) + 1,
      ]);
    }
  }
}
