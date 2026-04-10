import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

/// Deterministic stream probe — avoids timing-sensitive Future.delayed waits.
final class _StreamProbe<T> {
  _StreamProbe(Stream<T> stream) {
    _subscription = stream.listen((event) {
      _events.add(event);
      final ready =
          _waiters.where((w) => w.count <= _events.length).toList();
      for (final w in ready) {
        _waiters.remove(w);
        if (!w.completer.isCompleted) {
          w.completer.complete(_events[w.count - 1]);
        }
      }
    });
  }

  final _events = <T>[];
  final _waiters = <_EventWaiter<T>>[];
  late final StreamSubscription<T> _subscription;

  Future<T> event(
    int count, {
    Duration timeout = const Duration(seconds: 2),
  }) {
    if (_events.length >= count) return Future.value(_events[count - 1]);
    final completer = Completer<T>();
    _waiters.add(_EventWaiter(count, completer));
    return completer.future.timeout(timeout, onTimeout: () {
      throw TimeoutException('Timed out waiting for event $count');
    });
  }

  Future<void> expectNoAdditionalEvents(Duration duration) async {
    try {
      final event = await this.event(_events.length + 1, timeout: duration);
      fail('Unexpected additional stream event: $event');
    } on TimeoutException {
      // Expected: no event arrived within the window.
    }
  }

  Future<void> cancel() => _subscription.cancel();
}

final class _EventWaiter<T> {
  _EventWaiter(this.count, this.completer);
  final int count;
  final Completer<T> completer;
}

void main() {
  group('Write lock and nested transactions', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('resqlite_tx_test_');
      db = await Database.open('${tempDir.path}/test.db');
      await db.execute(
        'CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );
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

    // -----------------------------------------------------------------
    // Write lock — concurrent writes are serialized
    // -----------------------------------------------------------------

    test('concurrent executes do not interleave', () async {
      // Fire many concurrent inserts — they should all succeed without
      // interfering with each other.
      final futures = List.generate(
        20,
        (i) => db.execute('INSERT INTO items(name) VALUES (?)', ['item_$i']),
      );
      await Future.wait(futures);

      final rows = await db.select('SELECT count(*) as c FROM items');
      expect(rows[0]['c'], 20);
    });

    test('concurrent execute does not run inside a transaction', () async {
      // Start a transaction with a delay. A concurrent execute should
      // wait for the transaction to finish, not slip inside it.
      final txFuture = db.transaction((tx) async {
        await tx.execute('INSERT INTO items(name) VALUES (?)', ['inside_tx']);
        // Yield to let the concurrent execute attempt to run.
        await Future<void>.delayed(Duration.zero);
        await tx.execute('INSERT INTO items(name) VALUES (?)', ['inside_tx_2']);
      });

      // This execute should wait for the transaction to finish.
      final executeFuture = db.execute(
        'INSERT INTO items(name) VALUES (?)',
        ['outside_tx'],
      );

      await Future.wait([txFuture, executeFuture]);

      final rows = await db.select('SELECT name FROM items ORDER BY id');
      expect(rows, hasLength(3));
      // Transaction items should be first (transaction held the lock).
      expect(rows[0]['name'], 'inside_tx');
      expect(rows[1]['name'], 'inside_tx_2');
      expect(rows[2]['name'], 'outside_tx');
    });

    test('concurrent transactions are serialized', () async {
      final order = <String>[];

      final tx1 = db.transaction((tx) async {
        order.add('tx1_start');
        await tx.execute('INSERT INTO items(name) VALUES (?)', ['tx1']);
        await Future<void>.delayed(Duration.zero);
        order.add('tx1_end');
      });

      final tx2 = db.transaction((tx) async {
        order.add('tx2_start');
        await tx.execute('INSERT INTO items(name) VALUES (?)', ['tx2']);
        order.add('tx2_end');
      });

      await Future.wait([tx1, tx2]);

      // tx2 should not start until tx1 finishes.
      expect(order.indexOf('tx1_end'), lessThan(order.indexOf('tx2_start')));

      final rows = await db.select('SELECT name FROM items ORDER BY id');
      expect(rows, hasLength(2));
    });

    // -----------------------------------------------------------------
    // Nested transactions — explicit nesting with savepoints
    // -----------------------------------------------------------------

    test('nested transaction commits with outer', () async {
      await db.transaction((tx) async {
        await tx.execute('INSERT INTO items(name) VALUES (?)', ['outer']);
        await tx.transaction((inner) async {
          await inner.execute('INSERT INTO items(name) VALUES (?)', ['inner']);
        });
      });

      final rows = await db.select('SELECT name FROM items ORDER BY id');
      expect(rows, hasLength(2));
      expect(rows[0]['name'], 'outer');
      expect(rows[1]['name'], 'inner');
    });

    test('nested transaction rollback only undoes inner changes', () async {
      await db.transaction((tx) async {
        await tx.execute('INSERT INTO items(name) VALUES (?)', ['outer']);

        try {
          await tx.transaction((inner) async {
            await inner.execute(
              'INSERT INTO items(name) VALUES (?)',
              ['inner'],
            );
            throw StateError('rollback inner');
          });
        } on StateError {
          // expected
        }

        // Outer transaction should still see its own insert.
        final rows = await tx.select('SELECT name FROM items ORDER BY id');
        expect(rows, hasLength(1));
        expect(rows[0]['name'], 'outer');
      });

      // After outer commits, only 'outer' is persisted.
      final rows = await db.select('SELECT name FROM items ORDER BY id');
      expect(rows, hasLength(1));
      expect(rows[0]['name'], 'outer');
    });

    test('outer rollback undoes everything including committed inner', () async {
      try {
        await db.transaction((tx) async {
          await tx.execute('INSERT INTO items(name) VALUES (?)', ['outer']);

          // Inner commits successfully.
          await tx.transaction((inner) async {
            await inner.execute(
              'INSERT INTO items(name) VALUES (?)',
              ['inner'],
            );
          });

          // But outer throws — everything rolls back.
          throw StateError('rollback outer');
        });
      } on StateError {
        // expected
      }

      final rows = await db.select('SELECT name FROM items ORDER BY id');
      expect(rows, isEmpty);
    });

    test('double nesting works', () async {
      await db.transaction((tx) async {
        await tx.execute('INSERT INTO items(name) VALUES (?)', ['level_0']);

        await tx.transaction((inner1) async {
          await inner1.execute(
            'INSERT INTO items(name) VALUES (?)',
            ['level_1'],
          );

          await inner1.transaction((inner2) async {
            await inner2.execute(
              'INSERT INTO items(name) VALUES (?)',
              ['level_2'],
            );
          });
        });
      });

      final rows = await db.select('SELECT name FROM items ORDER BY id');
      expect(rows, hasLength(3));
      expect(rows[0]['name'], 'level_0');
      expect(rows[1]['name'], 'level_1');
      expect(rows[2]['name'], 'level_2');
    });

    test('double nesting rollback at middle level', () async {
      await db.transaction((tx) async {
        await tx.execute('INSERT INTO items(name) VALUES (?)', ['level_0']);

        try {
          await tx.transaction((inner1) async {
            await inner1.execute(
              'INSERT INTO items(name) VALUES (?)',
              ['level_1'],
            );

            await inner1.transaction((inner2) async {
              await inner2.execute(
                'INSERT INTO items(name) VALUES (?)',
                ['level_2'],
              );
            });

            // Rollback inner1 — undoes both level_1 and level_2.
            throw StateError('rollback inner1');
          });
        } on StateError {
          // expected
        }
      });

      final rows = await db.select('SELECT name FROM items ORDER BY id');
      expect(rows, hasLength(1));
      expect(rows[0]['name'], 'level_0');
    });

    // -----------------------------------------------------------------
    // Stream invalidation with nested transactions
    // -----------------------------------------------------------------

    test('stream fires after nested transaction commits', () async {
      final probe = _StreamProbe(
        db.stream('SELECT name FROM items ORDER BY id'),
      );

      // Wait for initial emission (empty table).
      await probe.event(1);

      await db.transaction((tx) async {
        await tx.execute('INSERT INTO items(name) VALUES (?)', ['outer']);
        await tx.transaction((inner) async {
          await inner.execute('INSERT INTO items(name) VALUES (?)', ['inner']);
        });
      });

      final rows = await probe.event(2);
      expect(rows, hasLength(2));

      await probe.cancel();
    });

    test('stream does not fire after rolled-back transaction', () async {
      await db.execute('INSERT INTO items(name) VALUES (?)', ['seed']);

      final probe = _StreamProbe(
        db.stream('SELECT name FROM items ORDER BY id'),
      );

      // Wait for initial emission (seed row).
      await probe.event(1);

      try {
        await db.transaction((tx) async {
          await tx.execute('INSERT INTO items(name) VALUES (?)', ['doomed']);
          throw StateError('rollback');
        });
      } on StateError {
        // expected
      }

      // No additional emission should fire — rolled-back writes don't
      // trigger stream invalidation.
      await probe.expectNoAdditionalEvents(const Duration(milliseconds: 150));

      await probe.cancel();
    });
  });
}
