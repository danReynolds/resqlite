/// Correctness regression guard for the drift benchmark peer.
///
/// The drift peer has a subtle fairness risk: drift's stream invalidation
/// for `customSelect` only fires when the peer correctly tells drift
/// which tables each write modifies. If the SQL-parsing logic in
/// `DriftPeer._extractWriteTable` ever regresses, drift streams would
/// silently stop invalidating — benchmarks would still run but show
/// misleadingly-fast reactive numbers (all streams emit only their
/// initial row and never update).
///
/// These tests fail loudly in CI before that can happen.
library;
import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import '../benchmark/drift/keyed_pk_db.dart';
import '../benchmark/shared/peer.dart';

void main() {
  group('DriftPeer', () {
    late Directory tempDir;
    late DriftPeer peer;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('drift_peer_test_');
      peer = DriftPeer(driftFactoryFor((exec) => KeyedPkDriftDb(exec)));
      await peer.open('${tempDir.path}/test.db');
      // Drift creates the `items` table automatically from the
      // @DriftDatabase schema — we just need a seed row.
      await peer.execute(
        'INSERT INTO items (id, body, updated_at) VALUES (?, ?, ?)',
        [1, 'initial', 0],
      );
    });

    tearDown(() async {
      await peer.close();
      await tempDir.delete(recursive: true);
    });

    test('select returns seeded row', () async {
      final rows = await peer.select('SELECT * FROM items WHERE id = ?', [1]);
      expect(rows, hasLength(1));
      expect(rows.first['id'], 1);
      expect(rows.first['body'], 'initial');
    });

    test('execute() on INSERT invalidates a watching stream', () async {
      final emissions = <List<Map<String, Object?>>>[];
      final sub = peer
          .watch(
            'SELECT * FROM items ORDER BY id',
            readsFrom: {'items'},
          )
          .listen(emissions.add);

      // Give the stream time to emit its initial row, then write.
      await Future.delayed(const Duration(milliseconds: 50));
      await peer.execute(
        'INSERT INTO items (id, body, updated_at) VALUES (?, ?, ?)',
        [2, 'inserted', 10],
      );

      // Wait for invalidation to settle. A missing readsFrom or a
      // regex regression would leave emissions stuck at 1.
      await Future.delayed(const Duration(milliseconds: 100));
      await sub.cancel();

      expect(emissions.length, greaterThanOrEqualTo(2),
          reason: 'stream should have emitted initial + post-insert values');
      expect(emissions.last, hasLength(2));
      expect(emissions.last.map((r) => r['id']), containsAll([1, 2]));
    });

    test('execute() on UPDATE invalidates a watching stream', () async {
      final emissions = <List<Map<String, Object?>>>[];
      final sub = peer
          .watch(
            'SELECT * FROM items WHERE id = ?',
            params: [1],
            readsFrom: {'items'},
          )
          .listen(emissions.add);

      await Future.delayed(const Duration(milliseconds: 50));
      await peer.execute(
        'UPDATE items SET body = ?, updated_at = ? WHERE id = ?',
        ['updated', 20, 1],
      );

      await Future.delayed(const Duration(milliseconds: 100));
      await sub.cancel();

      expect(emissions.length, greaterThanOrEqualTo(2));
      expect(emissions.last.first['body'], 'updated');
    });

    test('execute() on DELETE invalidates a watching stream', () async {
      final emissions = <List<Map<String, Object?>>>[];
      final sub = peer
          .watch('SELECT * FROM items', readsFrom: {'items'})
          .listen(emissions.add);

      await Future.delayed(const Duration(milliseconds: 50));
      await peer.execute('DELETE FROM items WHERE id = ?', [1]);

      await Future.delayed(const Duration(milliseconds: 100));
      await sub.cancel();

      expect(emissions.length, greaterThanOrEqualTo(2));
      expect(emissions.last, isEmpty);
    });

    test('executeBatch on INSERT invalidates a watching stream', () async {
      final emissions = <List<Map<String, Object?>>>[];
      final sub = peer
          .watch('SELECT * FROM items ORDER BY id', readsFrom: {'items'})
          .listen(emissions.add);

      await Future.delayed(const Duration(milliseconds: 50));
      await peer.executeBatch(
        'INSERT INTO items (id, body, updated_at) VALUES (?, ?, ?)',
        [
          [3, 'b1', 30],
          [4, 'b2', 40],
          [5, 'b3', 50],
        ],
      );

      await Future.delayed(const Duration(milliseconds: 100));
      await sub.cancel();

      // The batch commits once, so we expect initial (1 row) + one
      // post-batch emission (4 rows). Some drift versions may emit
      // extra transient values; we only assert "at least 2" + final
      // value is correct.
      expect(emissions.length, greaterThanOrEqualTo(2));
      expect(emissions.last, hasLength(4));
    });

    test('watch() without readsFrom throws (fairness guard)', () async {
      expect(
        () => peer.watch('SELECT * FROM items').listen((_) {}),
        throwsArgumentError,
      );
    });

    test('_extractWriteTable handles INSERT OR REPLACE', () async {
      // Regression guard: OR REPLACE / OR IGNORE were a common drift
      // benchmark failure mode during development (see Sync Burst merge
      // phase which uses INSERT OR REPLACE).
      final emissions = <List<Map<String, Object?>>>[];
      final sub = peer
          .watch('SELECT * FROM items ORDER BY id', readsFrom: {'items'})
          .listen(emissions.add);

      await Future.delayed(const Duration(milliseconds: 50));
      await peer.execute(
        'INSERT OR REPLACE INTO items (id, body, updated_at) VALUES (?, ?, ?)',
        [1, 'replaced', 99],
      );

      await Future.delayed(const Duration(milliseconds: 100));
      await sub.cancel();

      expect(emissions.length, greaterThanOrEqualTo(2),
          reason: 'INSERT OR REPLACE should invalidate streams');
      expect(emissions.last.first['body'], 'replaced');
    });
  });
}
