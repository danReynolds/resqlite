import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

/// Deterministic stream probe — avoids timing-sensitive Future.delayed waits.
/// Collects emissions and lets tests await the Nth event by count, or assert
/// that no further events arrive within a timeout window.
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

  /// Waits for the [count]-th emission (1-indexed). Returns immediately if
  /// that emission already arrived.
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

  /// Asserts that no additional stream event arrives within [duration].
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

    // =================================================================
    // Write lock — concurrent writes are serialized
    // =================================================================

    test('concurrent executes are serialized and do not interleave', () async {
      // Launch 20 inserts concurrently via Future.wait. The write lock
      // ensures they execute one at a time — none should fail or produce
      // duplicate IDs.
      final futures = List.generate(
        20,
        (i) => db.execute('INSERT INTO items(name) VALUES (?)', ['item_$i']),
      );
      await Future.wait(futures);

      final rows = await db.select('SELECT count(*) as c FROM items');
      expect(rows[0]['c'], 20);
    });

    test('execute waits for an in-flight transaction to finish', () async {
      // A transaction holds the write lock for its entire duration.
      // A concurrent db.execute() must wait — it should not slip
      // inside the transaction or execute before it commits.
      final txFuture = db.transaction((tx) async {
        await tx.execute('INSERT INTO items(name) VALUES (?)', ['inside_tx']);
        await Future<void>.delayed(Duration.zero); // yield to scheduler
        await tx.execute('INSERT INTO items(name) VALUES (?)', ['inside_tx_2']);
      });

      // Launched after txFuture but before it completes.
      final executeFuture = db.execute(
        'INSERT INTO items(name) VALUES (?)',
        ['outside_tx'],
      );

      await Future.wait([txFuture, executeFuture]);

      final rows = await db.select('SELECT name FROM items ORDER BY id');
      expect(rows, hasLength(3));
      // Transaction rows come first because it held the lock.
      expect(rows[0]['name'], 'inside_tx');
      expect(rows[1]['name'], 'inside_tx_2');
      expect(rows[2]['name'], 'outside_tx');
    });

    test('concurrent transactions run one at a time', () async {
      // Two transactions launched concurrently. The write lock ensures
      // tx2 does not start until tx1 has committed.
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

      expect(order.indexOf('tx1_end'), lessThan(order.indexOf('tx2_start')));

      final rows = await db.select('SELECT name FROM items ORDER BY id');
      expect(rows, hasLength(2));
    });

    // =================================================================
    // Zone-based transparent routing — db.* calls inside a transaction
    // body are automatically routed through the active Transaction.
    // =================================================================

    test('db.execute() inside a transaction routes through tx', () async {
      // Calling db.execute() (not tx.execute()) inside a transaction body
      // should transparently route through the transaction via the Zone,
      // rather than deadlocking on the write lock.
      await db.transaction((tx) async {
        await db.execute('INSERT INTO items(name) VALUES (?)', ['via_db']);
        // The insert should be visible within the same transaction.
        final rows = await tx.select('SELECT name FROM items');
        expect(rows, hasLength(1));
        expect(rows[0]['name'], 'via_db');
      });

      // Committed — visible outside the transaction.
      final rows = await db.select('SELECT name FROM items');
      expect(rows, hasLength(1));
    });

    test('db.select() inside a transaction sees uncommitted writes', () async {
      // Calling db.select() inside a transaction body should route through
      // the writer connection (tx.select), so it sees uncommitted writes
      // from earlier in the same transaction.
      await db.transaction((tx) async {
        await tx.execute('INSERT INTO items(name) VALUES (?)', ['uncommitted']);

        // db.select() would normally go to the reader pool and NOT see
        // uncommitted writes. Inside a transaction Zone it routes through
        // tx.select() instead.
        final rows = await db.select('SELECT name FROM items');
        expect(rows, hasLength(1));
        expect(rows[0]['name'], 'uncommitted');
      });
    });

    test('db.transaction() inside a transaction nests via savepoint', () async {
      // Calling db.transaction() (not tx.transaction()) inside a transaction
      // body should nest as a SAVEPOINT via the Zone routing, rather than
      // deadlocking on the write lock.
      await db.transaction((tx) async {
        await tx.execute('INSERT INTO items(name) VALUES (?)', ['outer']);

        await db.transaction((inner) async {
          await inner.execute('INSERT INTO items(name) VALUES (?)', ['inner']);
        });
      });

      final rows = await db.select('SELECT name FROM items ORDER BY id');
      expect(rows, hasLength(2));
      expect(rows[0]['name'], 'outer');
      expect(rows[1]['name'], 'inner');
    });

    test('db.executeBatch() inside a transaction routes through tx', () async {
      // Calling db.executeBatch() inside a transaction body should route
      // through tx.executeBatch(), which loops individual executes on the
      // writer connection. The enclosing transaction provides atomicity.
      await db.transaction((tx) async {
        await db.executeBatch(
          'INSERT INTO items(name) VALUES (?)',
          [['a'], ['b'], ['c']],
        );
        // All three should be visible within the transaction.
        final rows = await tx.select('SELECT name FROM items ORDER BY id');
        expect(rows, hasLength(3));
      });

      // Committed — all visible outside.
      final rows = await db.select('SELECT name FROM items ORDER BY id');
      expect(rows, hasLength(3));
      expect(rows[0]['name'], 'a');
      expect(rows[1]['name'], 'b');
      expect(rows[2]['name'], 'c');
    });

    test('tx.executeBatch() works directly', () async {
      // Calling executeBatch on the Transaction instance itself.
      await db.transaction((tx) async {
        await tx.executeBatch(
          'INSERT INTO items(name) VALUES (?)',
          [['x'], ['y']],
        );
      });

      final rows = await db.select('SELECT name FROM items ORDER BY id');
      expect(rows, hasLength(2));
      expect(rows[0]['name'], 'x');
      expect(rows[1]['name'], 'y');
    });

    test('executeBatch inside nested transaction rolls back on throw', () async {
      // A batch insert inside a nested transaction that throws should
      // roll back only the nested portion.
      await db.transaction((tx) async {
        await tx.execute('INSERT INTO items(name) VALUES (?)', ['outer']);

        try {
          await tx.transaction((inner) async {
            await inner.executeBatch(
              'INSERT INTO items(name) VALUES (?)',
              [['inner_a'], ['inner_b']],
            );
            throw StateError('rollback inner');
          });
        } on StateError {
          // expected
        }
      });

      // Only the outer row survives.
      final rows = await db.select('SELECT name FROM items ORDER BY id');
      expect(rows, hasLength(1));
      expect(rows[0]['name'], 'outer');
    });

    test('executeBatch with empty paramSets is a no-op', () async {
      // Empty batch should not throw or insert anything.
      await db.transaction((tx) async {
        await tx.executeBatch('INSERT INTO items(name) VALUES (?)', []);
      });

      final rows = await db.select('SELECT name FROM items');
      expect(rows, isEmpty);
    });

    // =================================================================
    // Nested transactions — explicit nesting with SAVEPOINTs
    // =================================================================

    test('inner transaction commits when outer commits', () async {
      // Both levels insert a row. When the outer transaction commits,
      // both rows are persisted.
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

    test('inner rollback only undoes inner changes', () async {
      // The inner transaction throws, rolling back its SAVEPOINT.
      // The outer transaction's insert survives and commits.
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

        // Outer should still see its own insert, but not the rolled-back one.
        final rows = await tx.select('SELECT name FROM items ORDER BY id');
        expect(rows, hasLength(1));
        expect(rows[0]['name'], 'outer');
      });

      final rows = await db.select('SELECT name FROM items ORDER BY id');
      expect(rows, hasLength(1));
      expect(rows[0]['name'], 'outer');
    });

    test('outer rollback undoes everything including committed inner', () async {
      // The inner transaction commits (RELEASE SAVEPOINT), but then the
      // outer transaction throws — ROLLBACK undoes all changes including
      // the inner's.
      try {
        await db.transaction((tx) async {
          await tx.execute('INSERT INTO items(name) VALUES (?)', ['outer']);

          await tx.transaction((inner) async {
            await inner.execute(
              'INSERT INTO items(name) VALUES (?)',
              ['inner'],
            );
          });

          throw StateError('rollback outer');
        });
      } on StateError {
        // expected
      }

      final rows = await db.select('SELECT name FROM items ORDER BY id');
      expect(rows, isEmpty);
    });

    test('transaction body exception rolls back and rethrows', () async {
      // A non-StateError exception should still trigger rollback and
      // propagate to the caller.
      await expectLater(
        db.transaction((tx) async {
          await tx.execute('INSERT INTO items(name) VALUES (?)', ['doomed']);
          throw FormatException('bad data');
        }),
        throwsA(isA<FormatException>()),
      );

      // Rolled back — nothing persisted.
      final rows = await db.select('SELECT name FROM items');
      expect(rows, isEmpty);
    });

    test('three levels of nesting commit correctly', () async {
      // Verifies SAVEPOINT depth tracking works beyond two levels:
      // level 0 = BEGIN IMMEDIATE, level 1 = SAVEPOINT s1, level 2 = SAVEPOINT s2.
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

    test('middle-level rollback undoes it and its children', () async {
      // Three levels: outer commits, middle throws after inner commits.
      // ROLLBACK TO s1 undoes both level_1 and level_2, but level_0
      // survives.
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

    // =================================================================
    // Stream invalidation — streams should fire once on commit, not
    // per statement, and should not fire on rollback.
    // =================================================================

    test('stream fires once after nested transaction commits', () async {
      // A transaction with a nested inner transaction inserts two rows.
      // The stream should emit exactly one update (on outer commit),
      // not one per statement or per nesting level.
      final probe = _StreamProbe(
        db.stream('SELECT name FROM items ORDER BY id'),
      );

      await probe.event(1); // initial emission (empty table)

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
      // Seed one row, wait for the stream to emit it, then roll back
      // a transaction that inserts another row. The stream should not
      // fire again — rolled-back writes produce no dirty tables.
      await db.execute('INSERT INTO items(name) VALUES (?)', ['seed']);

      final probe = _StreamProbe(
        db.stream('SELECT name FROM items ORDER BY id'),
      );

      await probe.event(1); // initial emission (seed row)

      try {
        await db.transaction((tx) async {
          await tx.execute('INSERT INTO items(name) VALUES (?)', ['doomed']);
          throw StateError('rollback');
        });
      } on StateError {
        // expected
      }

      await probe.expectNoAdditionalEvents(const Duration(milliseconds: 150));

      await probe.cancel();
    });
  });
}
