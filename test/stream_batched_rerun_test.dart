// [EXP-287] Guards the batched stream-rerun dispatch path.
//
// Under fan-out (more dirty streams than reader workers) reruns are packed
// into one message per worker, and each changed member replies on its own.
// That path has a window the scalar path does not: a write can land on the
// main isolate while the worker is still stepping the rest of the batch, so
// `onDependencyChanges` sees members that are `inFlight` and skips queueing
// them. Every one of those has to be picked up when the batch finishes —
// including the *unchanged* members, which send no reply at all and so have
// no other moment where anything notices them.

import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

/// Polls [condition] until it holds or the deadline passes, yielding to the
/// event loop between checks so stream emissions can land.
Future<void> pumpUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  group('batched stream reruns', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('resqlite_exp287_');
      db = await Database.open('${tempDir.path}/test.db');
      await db.execute(
        'CREATE TABLE items('
        'id INTEGER PRIMARY KEY, owner_id INTEGER NOT NULL, value INTEGER)',
      );
      await db.executeBatch('INSERT INTO items(owner_id, value) VALUES (?, ?)', [
        for (var owner = 1; owner <= 20; owner++)
          for (var r = 0; r < 5; r++) [owner, 0],
      ]);
    });

    tearDown(() async {
      await db.close();
      await tempDir.delete(recursive: true);
    });

    test('every stream converges after a burst that overlaps its own reruns',
        () async {
      const owners = 20;
      final latest = <int, List<Map<String, Object?>>>{};
      final subs = <StreamSubscription<Object?>>[];
      for (var owner = 1; owner <= owners; owner++) {
        final o = owner;
        subs.add(
          db
              .stream(
                'SELECT id, value FROM items WHERE owner_id = ? ORDER BY id',
                [o],
              )
              .listen((rows) => latest[o] = rows),
        );
      }
      await pumpUntil(() => latest.length == owners);

      // Three overlapping waves. Each wave dirties all 20 streams — well past
      // the pool size, so the engine batches — and the next wave is issued
      // while the previous one's batches are still in flight.
      for (var wave = 1; wave <= 3; wave++) {
        await Future.wait([
          for (var owner = 1; owner <= owners; owner++)
            db.execute(
              'UPDATE items SET value = ? WHERE owner_id = ? AND id = '
              '(SELECT MIN(id) FROM items WHERE owner_id = ?)',
              [wave, owner, owner],
            ),
        ]);
      }

      final expected = <int, List<Map<String, Object?>>>{};
      for (var owner = 1; owner <= owners; owner++) {
        expected[owner] = await db.select(
          'SELECT id, value FROM items WHERE owner_id = ? ORDER BY id',
          [owner],
        );
      }

      await pumpUntil(() {
        for (var owner = 1; owner <= owners; owner++) {
          final rows = latest[owner];
          if (rows == null) return false;
          if (rows.first['value'] != expected[owner]!.first['value']) {
            return false;
          }
        }
        return true;
      });

      for (var owner = 1; owner <= owners; owner++) {
        expect(latest[owner], equals(expected[owner]), reason: 'owner $owner');
      }
      for (final sub in subs) {
        await sub.cancel();
      }
    });

    test('a stream whose result never changes still stops re-querying',
        () async {
      // The unchanged members are the ones with no reply; make sure their
      // bookkeeping still settles rather than looping forever.
      final emissions = <int>[];
      final subs = <StreamSubscription<Object?>>[];
      for (var owner = 1; owner <= 20; owner++) {
        subs.add(
          db
              .stream('SELECT COUNT(*) c FROM items WHERE owner_id = ?', [owner])
              .listen((_) => emissions.add(owner)),
        );
      }
      await pumpUntil(() => emissions.length == 20);
      emissions.clear();

      // Value-only writes: every COUNT(*) stream re-runs and none changes.
      await Future.wait([
        for (var owner = 1; owner <= 20; owner++)
          db.execute('UPDATE items SET value = value + 1 WHERE owner_id = ?', [
            owner,
          ]),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(emissions, isEmpty);

      for (final sub in subs) {
        await sub.cancel();
      }
    });
  });
}
