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
///
/// Each test uses [_waitForEmission] — a short-poll with a budget — to
/// wait for the post-write emission rather than fixed `Future.delayed`
/// sleeps. Fixed sleeps race on CI runners under load; polling keeps
/// the test passing on a fast machine (tight convergence) while giving
/// a slow machine room to breathe, and a real invalidation regression
/// still fails within the budget.
library;
import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import '../benchmark/drift/keyed_pk_db.dart';
import '../benchmark/shared/peer.dart';

/// Wait until [emissions.length] reaches [target], or the budget
/// expires. Used instead of a fixed `Future.delayed` to make the
/// stream-invalidation tests stable on loaded CI while still failing
/// fast when invalidation is genuinely broken.
Future<void> _waitForEmission(
  List<List<Map<String, Object?>>> emissions, {
  required int target,
  Duration budget = const Duration(seconds: 2),
  String? description,
}) async {
  final deadline = DateTime.now().add(budget);
  while (emissions.length < target && DateTime.now().isBefore(deadline)) {
    // Short pull interval. 10 ms is small enough to resolve quickly on
    // a fast machine, large enough that a slow machine doesn't burn
    // the CPU polling.
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  if (emissions.length < target) {
    fail(
      '${description ?? "stream"}: expected ≥ $target emissions within '
      '${budget.inMilliseconds}ms; got ${emissions.length}. '
      'This usually means drift stream invalidation broke — a write '
      'fired but no re-query followed.',
    );
  }
}

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

      // Wait for initial emission (target=1), then write, then wait
      // for post-invalidation emission (target=2). Polling tolerates
      // CI runner variance without hiding real regressions.
      await _waitForEmission(emissions,
          target: 1, description: 'initial emission');
      await peer.execute(
        'INSERT INTO items (id, body, updated_at) VALUES (?, ?, ?)',
        [2, 'inserted', 10],
      );
      await _waitForEmission(emissions,
          target: 2, description: 'emission after INSERT');
      await sub.cancel();

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

      await _waitForEmission(emissions,
          target: 1, description: 'initial emission');
      await peer.execute(
        'UPDATE items SET body = ?, updated_at = ? WHERE id = ?',
        ['updated', 20, 1],
      );
      await _waitForEmission(emissions,
          target: 2, description: 'emission after UPDATE');
      await sub.cancel();

      expect(emissions.last.first['body'], 'updated');
    });

    test('execute() on DELETE invalidates a watching stream', () async {
      final emissions = <List<Map<String, Object?>>>[];
      final sub = peer
          .watch('SELECT * FROM items', readsFrom: {'items'})
          .listen(emissions.add);

      await _waitForEmission(emissions,
          target: 1, description: 'initial emission');
      await peer.execute('DELETE FROM items WHERE id = ?', [1]);
      await _waitForEmission(emissions,
          target: 2, description: 'emission after DELETE');
      await sub.cancel();

      expect(emissions.last, isEmpty);
    });

    test('executeBatch on INSERT invalidates a watching stream', () async {
      final emissions = <List<Map<String, Object?>>>[];
      final sub = peer
          .watch('SELECT * FROM items ORDER BY id', readsFrom: {'items'})
          .listen(emissions.add);

      await _waitForEmission(emissions,
          target: 1, description: 'initial emission');
      await peer.executeBatch(
        'INSERT INTO items (id, body, updated_at) VALUES (?, ?, ?)',
        [
          [3, 'b1', 30],
          [4, 'b2', 40],
          [5, 'b3', 50],
        ],
      );
      // Drift's batch commits once, so we expect a single post-batch
      // emission. Some drift versions may emit extras; accept ≥ 2.
      await _waitForEmission(emissions,
          target: 2, description: 'emission after batch');
      await sub.cancel();

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

      await _waitForEmission(emissions,
          target: 1, description: 'initial emission');
      await peer.execute(
        'INSERT OR REPLACE INTO items (id, body, updated_at) VALUES (?, ?, ?)',
        [1, 'replaced', 99],
      );
      await _waitForEmission(emissions,
          target: 2, description: 'emission after INSERT OR REPLACE');
      await sub.cancel();

      expect(emissions.last.first['body'], 'replaced');
    });
  });
}
