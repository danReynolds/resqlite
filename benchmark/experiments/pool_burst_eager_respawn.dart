// EXP-244: 8-request / 4-worker barrier burst — does sacrifice's respawn gap
// create a replacement-capacity hole, and does eager respawn close it?
//
// Peer-recommended design (2026-07-22): the pool already has a precise
// observable boundary — dispatch queue-wait (workerAssignedAt -
// requestEnqueuedAt) — that SQLite decode cannot contaminate. Per burst, fire 8
// identical large (sacrificing) selects simultaneously against a production
// 4-worker pool: requests 1-4 grab the workers, 5-8 park. The first four do
// equivalent decode work; the difference the parked four see is almost entirely
// whether their predecessor's slot became reusable immediately (send) or after a
// respawn gap (sacrifice). Reset the pool (reopen the DB) between bursts so no
// respawn debt carries across the treatment unit.
//
// Two lanes, one process each (compile-time define):
//   send             : -DRESQLITE_SACRIFICE_THRESHOLD=1099511627776  (never sacrifices)
//   sacrifice-current: (default)
//
// A third lane, sacrifice-eager (start the replacement spawn before completing
// the caller), was measured and rejected — it was equivalent to sacrifice-current
// on both metrics; its prototype is reverted. To reproduce it, re-apply the eager
// reorder in `_WorkerSlot`'s sacrifice branch behind a `RESQLITE_EAGER_RESPAWN`
// define (see experiments/244-pool-burst-eager-respawn.md).
//
// queue-wait is read from ReaderPool.debugDispatchTimings — [enqUs, assignedUs]
// per dispatch (VM-timeline µs) — set only around the barrier, so it holds
// exactly the 8 barrier dispatches. The 4 largest per burst are the parked 5-8.
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/reader/read_worker.dart' show sacrificeByteThreshold;
import 'package:resqlite/src/reader/reader_pool.dart' show ReaderPool;

const _bursts = 40;
const _rows = 5000; // full-scan result comfortably exceeds the 256 KB threshold
const _warmup = 12;

String get _lane =>
    sacrificeByteThreshold > (1 << 40) ? 'send' : 'sacrifice-current';

double _pct(List<double> xs, double p) {
  final s = [...xs]..sort();
  return s[(p * (s.length - 1)).round()];
}

Future<void> main() async {
  final lane = _lane;
  final parkedWaits = <double>[]; // µs, queue-wait of the 4 parked (5-8)
  final immediateWaits = <double>[]; // µs, queue-wait of the 4 that grabbed a slot
  final makespans = <double>[]; // µs, barrier release -> all 8 complete
  var sawFourWorkers = true;

  final q = 'SELECT a, b, s, u FROM t';

  for (var b = 0; b < _bursts; b++) {
    final tmp = await Directory.systemTemp.createTemp('resqlite-exp244-');
    final db = await Database.open('${tmp.path}/b.db');
    await db.execute('CREATE TABLE t(a INTEGER, b INTEGER, s TEXT, u TEXT)');
    await db.executeBatch(
      'INSERT INTO t(a, b, s, u) VALUES (?, ?, ?, ?)',
      [
        for (var i = 0; i < _rows; i++)
          [
            i,
            i * 3,
            'row_$i payload text long enough to inflate the result buffer well '
                'past the sacrifice threshold when scanned in full',
            'category_${i % 16}',
          ],
      ],
    );
    // Warm: spawn + warm all readers before the barrier so queue-wait measures
    // replacement capacity, not cold-start.
    for (var w = 0; w < _warmup; w++) {
      await db.select('SELECT a FROM t LIMIT 1');
    }

    // Barrier: fire 8 without awaiting; all 8 `_dispatch` entries run
    // synchronously now (recording enqUs), four grab workers, four park.
    ReaderPool.debugDispatchTimings = <List<int>>[];
    final t0 = DateTime.now().microsecondsSinceEpoch;
    final futures = [for (var i = 0; i < 8; i++) db.select(q)];
    await Future.wait(futures);
    final t1 = DateTime.now().microsecondsSinceEpoch;
    final timings = ReaderPool.debugDispatchTimings!;
    ReaderPool.debugDispatchTimings = null;

    if (timings.length != 8) {
      stdout.writeln('WARN burst $b recorded ${timings.length} dispatches (!=8)');
    }
    final waits = [for (final e in timings) (e[1] - e[0]).toDouble()]..sort();
    // Four smallest = grabbed a worker immediately; four largest = parked.
    final split = waits.length - 4;
    immediateWaits.addAll(waits.sublist(0, split));
    parkedWaits.addAll(waits.sublist(split));
    makespans.add((t1 - t0).toDouble());
    // Sanity: the four "immediate" should be near-zero; if not, the pool wasn't
    // 4 workers (this box should clamp to 4).
    if (waits[split - 1] > 2000) sawFourWorkers = false;

    await db.close();
    await tmp.delete(recursive: true);
  }

  stdout.writeln('lane=$lane bursts=$_bursts '
      '(parked samples=${parkedWaits.length}; 4-worker pool=$sawFourWorkers)');
  stdout.writeln('  parked queue-wait µs   '
      'p50=${_pct(parkedWaits, .5).toStringAsFixed(1)} '
      'p95=${_pct(parkedWaits, .95).toStringAsFixed(1)} '
      'p99=${_pct(parkedWaits, .99).toStringAsFixed(1)}');
  stdout.writeln('  immediate queue-wait µs '
      'p50=${_pct(immediateWaits, .5).toStringAsFixed(1)} '
      'p95=${_pct(immediateWaits, .95).toStringAsFixed(1)}');
  stdout.writeln('  burst makespan µs       '
      'p50=${_pct(makespans, .5).toStringAsFixed(1)} '
      'p95=${_pct(makespans, .95).toStringAsFixed(1)}');
}
