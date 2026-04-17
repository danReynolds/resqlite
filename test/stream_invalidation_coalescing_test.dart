/// Tests for the per-stream in-flight re-query coalescing added to
/// `StreamEngine` — formerly every write fan-out dispatched one
/// `pool.selectIfChanged` per active stream *per write*. On a 100-stream
/// × 200-write workload that queues up to 20,000 pool dispatches and
/// saturates the reader pool for tens of seconds, starving subsequent
/// fresh subscriptions.
///
/// With coalescing: at most one in-flight re-query per stream entry.
/// Additional invalidations during a re-query flag the entry for a
/// single follow-up on completion, which re-reads the latest state.
///
/// These tests verify two things:
///
///   1. **Correctness**: intervening writes during an in-flight
///      re-query are still visible in a subsequent emission. No update
///      is lost by the coalescing.
///
///   2. **Regression** (the original bug): a write burst followed by a
///      fresh stream subscription should not pay minutes of pool
///      backlog. A hard timeout fails loudly if the bug regresses.
library;

import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

void main() {
  group('Stream invalidation coalescing', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('resqlite_coalesce_test_');
      db = await Database.open('${tempDir.path}/test.db');
      await db.execute('CREATE TABLE items('
          'id INTEGER PRIMARY KEY, '
          'name TEXT NOT NULL, '
          'value INTEGER NOT NULL)');
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } on PathNotFoundException {
          // ignore
        }
      }
    });

    test('coalescing does not lose updates — multiple writes during an '
        'in-flight re-query still surface the latest state', () async {
      await db.execute(
          'INSERT INTO items(name, value) VALUES (?, ?)', ['row', 0]);

      final stream = db.stream('SELECT value FROM items WHERE id = ?', [1]);
      final values = <int>[];
      final sub = stream.listen((rows) {
        if (rows.isNotEmpty) {
          values.add(rows.first['value'] as int);
        }
      });

      // Drain initial emission.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(values, isNotEmpty);
      final firstEmitValue = values.first;
      expect(firstEmitValue, equals(0));

      // Fire a tight burst of writes. At least one should coalesce
      // (arrive while the prior re-query is still dispatching). The
      // coalescer must guarantee the final emission reflects the last
      // write's value (100), even though intermediate re-queries were
      // skipped.
      for (var i = 1; i <= 100; i++) {
        await db.execute('UPDATE items SET value = ? WHERE id = ?', [i, 1]);
      }

      // Wait for the stream to settle.
      final deadline =
          DateTime.now().add(const Duration(seconds: 10));
      while (values.isEmpty || values.last != 100) {
        if (DateTime.now().isAfter(deadline)) {
          fail('stream never emitted the final value (100); '
              'emitted: $values');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      // The final emitted value must be 100. The number of intermediate
      // emissions is implementation-dependent (may be as few as 1 if
      // all writes coalesced into a single re-query) — we don't assert
      // it here because that's the whole point of coalescing: reduce
      // wasted work.
      expect(values.last, equals(100));
      await sub.cancel();
    });

    test('write burst does not leave pool backlog that starves fresh '
        'subscriptions (regression for A11b iter-2 drain)', () async {
      // Seed a table with many rows and many keys so the workload
      // shape matches A11b: multiple disjoint streams, many writes.
      for (var i = 1; i <= 200; i++) {
        await db.execute(
          'INSERT INTO items(name, value) VALUES (?, ?)',
          ['k_${i % 20}', 0], // 20 groups, 200 rows, 10 rows/group
        );
      }

      // Phase 1: subscribe 20 streams, each watching a distinct group.
      // Matches A11b's "N streams each watching a distinct partition".
      final firstWaveCounts = List<int>.filled(20, 0);
      final firstWaveSubs =
          <StreamSubscription<List<Map<String, Object?>>>>[];
      for (var k = 0; k < 20; k++) {
        final idx = k;
        final sub = db
            .stream('SELECT id FROM items WHERE name = ?', ['k_$k'])
            .listen((_) => firstWaveCounts[idx]++);
        firstWaveSubs.add(sub);
      }

      // Drain initial emissions.
      var firstDrainDeadline =
          DateTime.now().add(const Duration(seconds: 5));
      while (!firstWaveCounts.every((c) => c >= 1)) {
        if (DateTime.now().isAfter(firstDrainDeadline)) {
          fail('initial drain of first wave timed out');
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      // Phase 2: write burst. Without coalescing, this queues
      // O(writes × streams) re-queries in the pool.
      for (var i = 0; i < 50; i++) {
        await db.execute(
            'UPDATE items SET value = value + 1 WHERE id = ?', [(i % 200) + 1]);
      }

      // Phase 3: cancel the first wave — entries are removed from
      // the engine, but fire-and-forget re-queries would still hold
      // the reader pool unless coalescing capped them.
      for (final sub in firstWaveSubs) {
        await sub.cancel();
      }

      // Phase 4: subscribe a fresh wave. Time how long until these
      // all emit. Pre-fix this would take 30+ seconds on a 4-worker
      // pool due to the write-burst backlog. Post-fix: sub-second.
      final freshCounts = List<int>.filled(20, 0);
      final freshSubs =
          <StreamSubscription<List<Map<String, Object?>>>>[];
      final sw = Stopwatch()..start();
      for (var k = 0; k < 20; k++) {
        final idx = k;
        final sub = db
            .stream('SELECT id FROM items WHERE name = ?', ['k_$k'])
            .listen((_) => freshCounts[idx]++);
        freshSubs.add(sub);
      }

      final hardDeadline =
          DateTime.now().add(const Duration(seconds: 15));
      while (!freshCounts.every((c) => c >= 1)) {
        if (DateTime.now().isAfter(hardDeadline)) {
          sw.stop();
          fail('Fresh wave drain timed out at '
              '${sw.elapsedMilliseconds}ms — pool is likely starved by '
              're-query backlog from the write burst. This is the '
              'exact bug A11b exposed; coalescing should cap in-flight '
              're-queries at 1 per stream.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      sw.stop();

      // Generous ceiling — on M1 Pro the fresh drain is ~10-50ms with
      // coalescing, vs 30+ seconds without. 5 seconds guards against
      // the original pathology while leaving headroom for slower CI.
      expect(
        sw.elapsedMilliseconds,
        lessThan(5000),
        reason: 'Fresh-subscription drain after a write burst should '
            'not be dominated by leftover re-query work — coalescing '
            'should cap in-flight re-queries to at most one per stream.',
      );

      for (final sub in freshSubs) {
        await sub.cancel();
      }
    });
  });
}
