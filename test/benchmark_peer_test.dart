/// Unit tests for the `BenchmarkPeer` interface and its three
/// implementations.
///
/// These tests verify *behavior*, not timing (per METHODOLOGY.md §
/// "Adding a workload — Definition of Done"). A silent measurement bug
/// — a peer whose `select()` returns zero rows because of a type cast
/// error, or a `watch()` that never emits — would invalidate every
/// benchmark result built on top of the adapter. These tests catch that.
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import '../benchmark/shared/peer.dart';

void main() {
  group('BenchmarkPeer contract', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('peer_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } on PathNotFoundException {
          // ignore
        }
      }
    });

    for (final factory in _factories) {
      final name = factory.name;

      group('$name adapter', () {
        late BenchmarkPeer peer;

        setUp(() async {
          peer = factory.build();
          await peer.open('${tempDir.path}/$name.db');
        });

        tearDown(() async {
          await peer.close();
        });

        test('reports the expected identifier', () {
          expect(peer.name, equals(name));
        });

        test('capabilities match the adapter contract', () {
          expect(peer.hasBatch, isTrue);
          switch (name) {
            case 'sqlite3':
              expect(peer.isSynchronous, isTrue);
              expect(peer.hasStreams, isFalse);
            case 'resqlite':
            case 'sqlite_async':
              expect(peer.isSynchronous, isFalse);
              expect(peer.hasStreams, isTrue);
          }
        });

        test('execute + select round-trips a row', () async {
          await peer.execute('CREATE TABLE t(id INTEGER PRIMARY KEY, '
              'name TEXT NOT NULL, value REAL NOT NULL)');
          await peer.execute('INSERT INTO t(name, value) VALUES (?, ?)',
              ['first', 1.5]);

          final rows = await peer.select('SELECT id, name, value FROM t');
          expect(rows, hasLength(1));
          expect(rows[0]['id'], equals(1));
          expect(rows[0]['name'], equals('first'));
          expect(rows[0]['value'], equals(1.5));
        });

        test('executeBatch inserts all param sets in one transaction',
            () async {
          await peer.execute('CREATE TABLE t(id INTEGER PRIMARY KEY, '
              'value INTEGER NOT NULL)');
          await peer.executeBatch('INSERT INTO t(value) VALUES (?)', [
            [10],
            [20],
            [30],
          ]);

          final rows = await peer.select('SELECT value FROM t ORDER BY id');
          expect(rows.map((r) => r['value']).toList(),
              equals([10, 20, 30]));
        });

        test('executeBatch rolls back on malformed SQL without leaking '
            'an open transaction', () async {
          await peer.execute('CREATE TABLE t(id INTEGER PRIMARY KEY, '
              'value INTEGER NOT NULL)');
          // Malformed SQL — prepare() throws on this.
          await expectLater(
            peer.executeBatch('INSERT garbage INTO t VALUES (?)', [
              [1],
            ]),
            throwsA(anything),
          );
          // Adapter must not be stuck inside an open transaction; a
          // subsequent write should succeed. Before the fix, sqlite3
          // raised "cannot start a transaction within a transaction"
          // here because the failing prepare() skipped the ROLLBACK.
          await peer.execute('INSERT INTO t(value) VALUES (?)', [42]);
          final rows = await peer.select('SELECT value FROM t');
          expect(rows.single['value'], equals(42));
        });

        test('parameterized select handles nulls, ints, doubles, strings',
            () async {
          await peer.execute('CREATE TABLE t(id INTEGER PRIMARY KEY, '
              'a INTEGER, b REAL, c TEXT)');
          await peer.execute(
              'INSERT INTO t(a, b, c) VALUES (?, ?, ?)', [null, 2.5, 'hello']);

          final rows =
              await peer.select('SELECT a, b, c FROM t WHERE id = ?', [1]);
          expect(rows, hasLength(1));
          expect(rows[0]['a'], isNull);
          expect(rows[0]['b'], equals(2.5));
          expect(rows[0]['c'], equals('hello'));
        });
      });
    }
  });

  group('PeerSet', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('peerset_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } on PathNotFoundException {
          // ignore
        }
      }
    });

    test('open() brings up all three peers and close() shuts them down',
        () async {
      final peers = await PeerSet.open(tempDir.path);
      try {
        expect(peers.all, hasLength(3));
        expect(peers.all.map((p) => p.name).toSet(),
            equals({'resqlite', 'sqlite3', 'sqlite_async'}));

        // Every peer must be able to run a trivial query right after open.
        for (final peer in peers.all) {
          await peer.execute('CREATE TABLE t(id INTEGER PRIMARY KEY)');
          await peer.execute('INSERT INTO t(id) VALUES (?)', [42]);
          final rows = await peer.select('SELECT id FROM t');
          expect(rows.single['id'], equals(42),
              reason: '${peer.name} select round-trip failed');
        }
      } finally {
        await peers.closeAll();
      }
    });

    test('require: reactive filter excludes sqlite3', () async {
      final peers = await PeerSet.open(
        tempDir.path,
        require: (p) => p.hasStreams,
      );
      try {
        expect(peers.all, hasLength(2));
        expect(peers.all.map((p) => p.name).toSet(),
            equals({'resqlite', 'sqlite_async'}));
      } finally {
        await peers.closeAll();
      }
    });
  });

  group('Reactive watch', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('peer_watch_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } on PathNotFoundException {
          // ignore
        }
      }
    });

    test('reactive peers emit initial results and react to writes',
        () async {
      for (final factory in _reactiveFactories) {
        final peer = factory.build();
        await peer.open('${tempDir.path}/${factory.name}_watch.db');
        try {
          await peer.execute('CREATE TABLE items(id INTEGER PRIMARY KEY, '
              'name TEXT NOT NULL)');
          await peer.executeBatch('INSERT INTO items(name) VALUES (?)',
              [['a'], ['b']]);

          final received = <List<Map<String, Object?>>>[];
          final sub = peer
              .watch('SELECT id, name FROM items ORDER BY id')
              .listen(received.add);

          // Drain initial emission (under a timeout to prevent hangs on
          // adapter bugs).
          await _waitUntil(
            () => received.isNotEmpty,
            timeout: const Duration(seconds: 2),
            description: '${factory.name} initial emission',
          );
          expect(received.first, hasLength(2));

          // Trigger a re-emission via a write on the same table.
          await peer
              .execute('INSERT INTO items(name) VALUES (?)', ['c']);

          await _waitUntil(
            () => received.length >= 2,
            timeout: const Duration(seconds: 2),
            description: '${factory.name} re-emission on write',
          );
          expect(received.last, hasLength(3));

          await sub.cancel();
        } finally {
          await peer.close();
        }
      }
    });

    test('sqlite3 watch() throws UnsupportedError', () async {
      final peer = Sqlite3Peer();
      await peer.open('${tempDir.path}/sqlite3_watch.db');
      try {
        expect(() => peer.watch('SELECT 1'),
            throwsA(isA<UnsupportedError>()));
      } finally {
        await peer.close();
      }
    });
  });
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final class _PeerFactory {
  _PeerFactory(this.name, this.build);
  final String name;
  final BenchmarkPeer Function() build;
}

final List<_PeerFactory> _factories = [
  _PeerFactory('resqlite', ResqlitePeer.new),
  _PeerFactory('sqlite3', Sqlite3Peer.new),
  _PeerFactory('sqlite_async', SqliteAsyncPeer.new),
];

final List<_PeerFactory> _reactiveFactories =
    _factories.where((f) {
  // Rebuild once to check the flag without holding onto the peer.
  final sample = f.build();
  return sample.hasStreams;
}).toList();

/// Poll [predicate] every 10 ms until it returns true or [timeout] elapses.
Future<void> _waitUntil(
  bool Function() predicate, {
  required Duration timeout,
  required String description,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for: $description');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
