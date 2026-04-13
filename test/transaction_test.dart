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
      final ready = _waiters.where((w) => w.count <= _events.length).toList();
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

    test(
        'close() during contention rejects queued writers without '
        'hanging', () async {
      // Exercises the _ensureOpen() re-check inside _withWriteLock that
      // wakes after an awaited lock completes. Without it, writers queued
      // on the write lock when close() fires would wake, create a fresh
      // lock, and send an ExecuteRequest to a writer isolate whose
      // receive port is about to close — hanging forever.
      //
      // Single synchronous turn:
      //   - W1 enters _withWriteLock, acquires the lock, sends its
      //     ExecuteRequest to the writer, then awaits.
      //   - W2, W3 enter _withWriteLock and await W1's lock.future.
      //   - close() sets _closed=true and enqueues CloseRequest on the
      //     writer (after W1's ExecuteRequest).
      //
      // Later:
      //   - Writer processes W1, replies. W1's body returns, lock
      //     releases, W2 and W3 wake from their await.
      //   - On wake they re-run _ensureOpen(), see _closed, and throw
      //     ResqliteConnectionException.
      //   - Writer processes CloseRequest and shuts down.
      //
      // Per-future timeouts turn a regression into a deterministic test
      // failure instead of a stuck suite.
      final w1 = db.execute('INSERT INTO items(name) VALUES (?)', ['w1']);
      final w2 = db.execute('INSERT INTO items(name) VALUES (?)', ['w2']);
      final w3 = db.execute('INSERT INTO items(name) VALUES (?)', ['w3']);
      final closeFuture = db.close();

      // W1 was in-flight before close(); it completes normally.
      await w1.timeout(const Duration(seconds: 2));

      // W2 and W3 were still queued on the write lock when close() ran.
      await expectLater(
        w2.timeout(const Duration(seconds: 2)),
        throwsA(isA<ResqliteConnectionException>()),
      );
      await expectLater(
        w3.timeout(const Duration(seconds: 2)),
        throwsA(isA<ResqliteConnectionException>()),
      );

      await closeFuture.timeout(const Duration(seconds: 2));
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
      // through tx.executeBatch(), which sends a single BatchRequest to the
      // writer isolate. The writer detects the active transaction and runs
      // the batch without its own BEGIN/COMMIT — the enclosing transaction
      // provides atomicity.
      await db.transaction((tx) async {
        await db.executeBatch(
          'INSERT INTO items(name) VALUES (?)',
          [
            ['a'],
            ['b'],
            ['c']
          ],
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
          [
            ['x'],
            ['y']
          ],
        );
      });

      final rows = await db.select('SELECT name FROM items ORDER BY id');
      expect(rows, hasLength(2));
      expect(rows[0]['name'], 'x');
      expect(rows[1]['name'], 'y');
    });

    test('executeBatch rejects non-uniform parameter row lengths', () async {
      // The C-level batch runner treats the flattened param array as a
      // fixed-shape matrix (setCount × paramCount). Non-uniform rows
      // would either silently truncate or read past the allocated buffer
      // depending on which direction the shape drifts. Guard at the
      // Dart layer before any native allocation.
      expect(
        () => db.executeBatch(
          'INSERT INTO items(id, name) VALUES (?, ?)',
          [
            [1, 'a'],
            [2], // short row
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => db.executeBatch(
          'INSERT INTO items(id, name) VALUES (?, ?)',
          [
            [1, 'a'],
            [2, 'b', 'c'], // long row
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
      // Uniform rows pass.
      await db.executeBatch(
        'INSERT INTO items(id, name) VALUES (?, ?)',
        [
          [1, 'a'],
          [2, 'b'],
        ],
      );
      final rows = await db.select('SELECT id, name FROM items ORDER BY id');
      expect(rows, hasLength(2));
    });

    test('executeBatch inside nested transaction rolls back on throw',
        () async {
      // A batch insert inside a nested transaction that throws should
      // roll back only the nested portion.
      await db.transaction((tx) async {
        await tx.execute('INSERT INTO items(name) VALUES (?)', ['outer']);

        try {
          await tx.transaction((inner) async {
            await inner.executeBatch(
              'INSERT INTO items(name) VALUES (?)',
              [
                ['inner_a'],
                ['inner_b']
              ],
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

    test('outer rollback undoes everything including committed inner',
        () async {
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

    // =================================================================
    // State consistency after commit / rollback failures — `txDepth`
    // on the writer isolate must always match SQLite's real depth
    // even when COMMIT or RELEASE fails, otherwise the next caller
    // issues the wrong kind of transaction control.
    // =================================================================

    test('database is usable after a deferred-FK commit failure', () async {
      // Set up a parent/child schema with a DEFERRABLE INITIALLY DEFERRED
      // foreign key. Deferred constraints are checked at COMMIT time, so
      // inserting a child with a non-existent parent succeeds inside the
      // transaction but fails at commit, which is exactly the error path
      // we want to exercise on the writer isolate.
      await db.execute('PRAGMA foreign_keys = ON');
      await db.execute('CREATE TABLE parent(id INTEGER PRIMARY KEY)');
      await db.execute('''
        CREATE TABLE child(
          id INTEGER PRIMARY KEY,
          pid INTEGER NOT NULL,
          FOREIGN KEY (pid) REFERENCES parent(id) DEFERRABLE INITIALLY DEFERRED
        )
      ''');

      // The commit must throw — the insert targets a non-existent parent
      // and the deferred FK check fails at COMMIT time.
      await expectLater(
        db.transaction((tx) async {
          await tx.execute('INSERT INTO child(pid) VALUES (?)', [999]);
        }),
        throwsA(isA<Exception>()),
      );

      // After the failed commit, both the write lock and the writer's
      // txDepth must be back to zero. A fresh top-level transaction
      // should open BEGIN IMMEDIATE (not SAVEPOINT s1) and commit
      // normally.
      await db.execute('INSERT INTO parent(id) VALUES (?)', [1]);
      await db.transaction((tx) async {
        await tx.execute('INSERT INTO child(pid) VALUES (?)', [1]);
      });

      final rows = await db.select(
        'SELECT pid FROM child ORDER BY id',
      );
      expect(rows, hasLength(1));
      expect(rows[0]['pid'], 1);
    });

    // =================================================================
    // Structured error propagation — the writer isolate must marshal
    // ResqliteQueryException / ResqliteTransactionException back to the
    // main isolate with sqliteCode, sql, parameters, and operation
    // intact, rather than collapsing everything into a stringified
    // message the user cannot programmatically inspect.
    // =================================================================

    // =================================================================
    // WriteResult accuracy — affected row counts and last-insert IDs
    // must be populated for both the parameterized and unparameterized
    // execute paths. The unparameterized path used to hardcode zero.
    // =================================================================

    test(
        'db.execute without parameters returns accurate affectedRows '
        'and lastInsertId', () async {
      // Seed with a parameterized insert so we have a known
      // last_insert_rowid baseline.
      final seed = await db.execute(
        'INSERT INTO items(name) VALUES (?)',
        ['seed'],
      );
      expect(seed.affectedRows, 1);
      expect(seed.lastInsertId, greaterThan(0));

      // Unparameterized INSERT — used to hit the empty-params fast
      // path that hardcoded WriteResult(0, 0).
      final inserted = await db.execute(
        "INSERT INTO items(name) VALUES ('no_params')",
      );
      expect(inserted.affectedRows, 1);
      expect(inserted.lastInsertId, greaterThan(seed.lastInsertId));

      // Unparameterized DELETE should report the real deleted count.
      final deleted = await db.execute(
        "DELETE FROM items WHERE name IN ('seed', 'no_params')",
      );
      expect(deleted.affectedRows, 2);

      // DDL: SQLite's sqlite3_changes() counter is not touched by
      // CREATE TABLE, so affectedRows surfaces the previous DML count.
      // We only assert the call doesn't crash — users who care about
      // "rows affected by this call" shouldn't be calling execute with
      // DDL and then reading affectedRows, which matches native
      // sqlite3_changes behavior.
      await db.execute('CREATE TABLE extra(id INTEGER PRIMARY KEY)');
    });

    test('db.execute supports multi-statement SQL without parameters',
        () async {
      // The unparameterized path uses sqlite3_exec which walks the
      // string statement-by-statement. The parameterized path only
      // runs the first statement (sqlite3_prepare limitation). This
      // test exists to document the distinction and prevent a
      // refactor from collapsing the two paths.
      await db.execute('''
        CREATE TABLE a(id INTEGER PRIMARY KEY);
        CREATE TABLE b(id INTEGER PRIMARY KEY);
      ''');
      // Both tables should exist.
      await db.execute('INSERT INTO a(id) VALUES (1)');
      await db.execute('INSERT INTO b(id) VALUES (1)');
      final rowsA = await db.select('SELECT id FROM a');
      final rowsB = await db.select('SELECT id FROM b');
      expect(rowsA, hasLength(1));
      expect(rowsB, hasLength(1));
    });

    test(
        'ResqliteQueryException surfaces sqliteCode for constraint '
        'violations', () async {
      // UNIQUE PK violation → SQLITE_CONSTRAINT = 19.
      await db.execute('INSERT INTO items(id, name) VALUES (?, ?)', [1, 'a']);
      try {
        await db.execute('INSERT INTO items(id, name) VALUES (?, ?)', [1, 'b']);
        fail('expected constraint violation');
      } on ResqliteQueryException catch (e) {
        expect(e.sqliteCode, 19);
        // Message should be the raw SQLite text, not double-prefixed.
        expect(e.message, isNot(contains('ResqliteQueryException')));
        expect(e.message, isNot(contains('execute failed:')));
        expect(e.sql, 'INSERT INTO items(id, name) VALUES (?, ?)');
        expect(e.parameters, [1, 'b']);
      }
    });

    test('ResqliteQueryException surfaces sqliteCode for batch failures',
        () async {
      await db
          .execute('INSERT INTO items(id, name) VALUES (?, ?)', [1, 'seed']);
      try {
        await db.executeBatch(
          'INSERT INTO items(id, name) VALUES (?, ?)',
          [
            [2, 'a'],
            [1, 'b'], // duplicates the seed row → constraint violation
            [3, 'c'],
          ],
        );
        fail('expected constraint violation');
      } on ResqliteQueryException catch (e) {
        expect(e.sqliteCode, 19);
        expect(e.sql, 'INSERT INTO items(id, name) VALUES (?, ?)');
      }

      // Entire batch rolls back atomically → only the seed row survives.
      final rows = await db.select('SELECT id FROM items ORDER BY id');
      expect(rows, hasLength(1));
      expect(rows[0]['id'], 1);
    });

    test(
        'ResqliteTransactionException surfaces sqliteCode and operation '
        'on commit failure', () async {
      await db.execute('PRAGMA foreign_keys = ON');
      await db.execute('CREATE TABLE parent(id INTEGER PRIMARY KEY)');
      await db.execute('''
        CREATE TABLE child(
          id INTEGER PRIMARY KEY,
          pid INTEGER NOT NULL,
          FOREIGN KEY (pid) REFERENCES parent(id) DEFERRABLE INITIALLY DEFERRED
        )
      ''');

      try {
        await db.transaction((tx) async {
          await tx.execute('INSERT INTO child(pid) VALUES (?)', [999]);
        });
        fail('expected commit failure');
      } on ResqliteTransactionException catch (e) {
        expect(e.operation, 'commit');
        // SQLITE_CONSTRAINT (19) or a SQLITE_CONSTRAINT_FOREIGNKEY
        // extended code (787). We accept either — which one SQLite
        // returns depends on the build's extended-result-code flag.
        expect(
          e.sqliteCode,
          anyOf(equals(19), equals(787)),
          reason: 'expected SQLITE_CONSTRAINT or extended FOREIGN KEY code, '
              'got ${e.sqliteCode}',
        );
      }
    });

    // =================================================================
    // Leaked Transaction rejection — a Transaction reference carried out
    // of the body must not silently execute against the writer.
    // =================================================================

    test('Transaction methods throw StateError after the body returns',
        () async {
      Transaction? leaked;
      await db.transaction((tx) async {
        leaked = tx;
        await tx.execute('INSERT INTO items(name) VALUES (?)', ['ok']);
      });
      expect(leaked, isNotNull);

      // Every entry point must reject.
      expect(
        () => leaked!.execute('INSERT INTO items(name) VALUES (?)', ['late']),
        throwsA(isA<StateError>()),
      );
      expect(
        () => leaked!.select('SELECT * FROM items'),
        throwsA(isA<StateError>()),
      );
      expect(
        () => leaked!.executeBatch(
          'INSERT INTO items(name) VALUES (?)',
          [
            ['x'],
            ['y']
          ],
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        () => leaked!.transaction((_) async {}),
        throwsA(isA<StateError>()),
      );

      // And the write that ran inside the body is still the only one
      // persisted — the leaked calls never reached SQLite.
      final rows = await db.select('SELECT name FROM items');
      expect(rows, hasLength(1));
      expect(rows[0]['name'], 'ok');
    });

    test('Leaked Transaction from rollback is also rejected', () async {
      // Even if the transaction body throws (so the outer tx rolls back),
      // the Transaction object must still be deactivated — otherwise a
      // leaked reference could run autocommit writes on the writer and
      // skip stream invalidation.
      Transaction? leaked;
      try {
        await db.transaction((tx) async {
          leaked = tx;
          throw StateError('abort');
        });
      } on StateError {
        // expected
      }
      expect(leaked, isNotNull);
      expect(
        () => leaked!.execute('INSERT INTO items(name) VALUES (?)', ['late']),
        throwsA(isA<StateError>()),
      );
    });

    // =================================================================
    // FIFO fairness — the write-lock comment promises arrival-order
    // service. Assert it observationally.
    // =================================================================

    test('write lock serves concurrent writers in FIFO order', () async {
      // Launch 10 inserts in a single synchronous turn so their arrival
      // order on the lock is deterministic. Each inserts a name encoding
      // its launch index, and we read them back ordered by rowid (which
      // is the real execution order on the writer connection).
      final futures = <Future<WriteResult>>[];
      for (var i = 0; i < 10; i++) {
        futures.add(
          db.execute('INSERT INTO items(name) VALUES (?)', ['launch_$i']),
        );
      }
      await Future.wait(futures);

      final rows = await db.select('SELECT name FROM items ORDER BY id');
      expect(rows, hasLength(10));
      for (var i = 0; i < 10; i++) {
        expect(
          rows[i]['name'],
          'launch_$i',
          reason: 'row $i should be launch_$i but was ${rows[i]['name']}',
        );
      }
    });

    // =================================================================
    // Close during an in-flight transaction — close() must *drain*
    // rather than pull the writer out from under the transaction body.
    // =================================================================

    test('close() drains an in-flight read before freeing the handle',
        () async {
      // Prime the pool with a dummy read so `_readers` resolves in a
      // single microtask on the real read below — we need the read to
      // reach `pool.select` (and dispatch to a worker) *before* close
      // runs, otherwise it will bail out at the pool's closed-check.
      await db.select('SELECT 1');

      // Seed enough rows that the SELECT actually spends measurable
      // time in C, giving close() a chance to race against the read.
      // Without the reader-pool drain, resqliteClose(_handle) could
      // run while the worker is still stepping over the SQLite handle,
      // causing a use-after-free in native code.
      final seeds = [
        for (var i = 0; i < 5000; i++) ['row_$i'],
      ];
      await db.executeBatch('INSERT INTO items(name) VALUES (?)', seeds);

      // Launch the read, then *yield to the macrotask queue* so its
      // pending microtask (the `await _readers` continuation) runs and
      // the read gets dispatched to a worker isolate. Only then do we
      // call close() — at which point close's reader-pool drain should
      // wait for the in-flight slot's pending completer before closing.
      final readFuture = db.select('SELECT name FROM items ORDER BY id');
      await Future<void>.delayed(Duration.zero);
      final closeFuture = db.close();

      final rows = await readFuture.timeout(const Duration(seconds: 5));
      expect(rows, hasLength(5000));
      await closeFuture.timeout(const Duration(seconds: 5));
    });

    test('close() drains an in-flight transaction body', () async {
      // Start a transaction whose body intentionally awaits an external
      // completer we control. While that's yielded, call close() from
      // another code path. Expectations:
      //
      // 1. The in-flight transaction body can still use its tx object
      //    to issue writes after the yield — close() is waiting for
      //    the write lock to release.
      // 2. The transaction commits successfully.
      // 3. close() then completes.
      final resume = Completer<void>();
      final txFuture = db.transaction((tx) async {
        await tx.execute('INSERT INTO items(name) VALUES (?)', ['before']);
        // Yield to the event loop so close() can run.
        await resume.future;
        // This must still work even though close() has run and set
        // _closed=true — the writer isolate stays alive until we release
        // the write lock.
        await tx.execute('INSERT INTO items(name) VALUES (?)', ['after']);
      });

      // Give the transaction body a chance to park on `resume.future`.
      await Future<void>.delayed(Duration.zero);

      // Kick off close — this sets _closed and waits for the write lock.
      final closeFuture = db.close();

      // Let the body finish.
      resume.complete();

      // Both futures resolve cleanly; no hang.
      await txFuture.timeout(const Duration(seconds: 2));
      await closeFuture.timeout(const Duration(seconds: 2));
    });

    test('close() during worker spawn waits for spawn to finish', () async {
      // Open a second database and immediately close it before making
      // any read or write call. The writer and reader-pool isolates are
      // spawned lazily in the background; close() must wait for both
      // spawns to settle before freeing the native handle, otherwise
      // the spawned isolates would hold a Pointer to a freed SQLite
      // connection and either leak or crash on first touch.
      final spawnRaceDir =
          await Directory.systemTemp.createTemp('resqlite_spawn_race_');
      try {
        final db2 = await Database.open('${spawnRaceDir.path}/race.db');
        // No operations in between — the pool and writer are still
        // spawning asynchronously when we call close().
        await db2.close().timeout(const Duration(seconds: 5));
        // The database is closed cleanly; subsequent operations throw.
        expect(
          () => db2.execute('CREATE TABLE t(id INTEGER)'),
          throwsA(isA<ResqliteConnectionException>()),
        );
      } finally {
        if (await spawnRaceDir.exists()) {
          await spawnRaceDir.delete(recursive: true);
        }
      }
    });

    test('close() is idempotent under concurrent callers', () async {
      // Two concurrent calls to close() should share the same
      // in-progress future. Without the _closeFuture cache, the second
      // caller would return immediately (seeing _closed=true) while the
      // first was still mid-shutdown, causing callers that awaited the
      // second to race with teardown.
      final f1 = db.close();
      final f2 = db.close();
      final f3 = db.close();
      await Future.wait([f1, f2, f3]).timeout(const Duration(seconds: 2));
      // After any of them resolves, the database is closed.
      expect(
        () => db.execute('INSERT INTO items(name) VALUES (?)', ['late']),
        throwsA(isA<ResqliteConnectionException>()),
      );
    });

    // =================================================================
    // Concurrent transactions on two independent Databases — they each
    // have their own writer isolate and write lock, so they should run
    // in parallel without interference.
    // =================================================================

    test(
        'two databases run transactions concurrently without '
        'interference', () async {
      final dbB = await Database.open('${tempDir.path}/parallel.db');
      await dbB.execute(
        'CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );

      try {
        // Launch transactions on both databases in the same synchronous
        // turn. If the write lock or Zone key leaked between instances
        // they would interfere. With proper instance isolation each
        // completes on its own writer.
        final txA = db.transaction((tx) async {
          for (var i = 0; i < 10; i++) {
            await tx.execute(
              'INSERT INTO items(name) VALUES (?)',
              ['A_$i'],
            );
          }
        });
        final txB = dbB.transaction((tx) async {
          for (var i = 0; i < 10; i++) {
            await tx.execute(
              'INSERT INTO items(name) VALUES (?)',
              ['B_$i'],
            );
          }
        });

        await Future.wait([txA, txB]);

        final rowsA = await db.select('SELECT name FROM items ORDER BY id');
        expect(rowsA, hasLength(10));
        for (var i = 0; i < 10; i++) {
          expect(rowsA[i]['name'], 'A_$i');
        }

        final rowsB = await dbB.select('SELECT name FROM items ORDER BY id');
        expect(rowsB, hasLength(10));
        for (var i = 0; i < 10; i++) {
          expect(rowsB[i]['name'], 'B_$i');
        }
      } finally {
        await dbB.close();
      }
    });

    test(
        'nested transaction followed by commit failure leaves writer '
        'depth at zero', () async {
      // Outer transaction with a successful inner savepoint; outer commit
      // fails at deferred FK check time. This exercises the full depth-0
      // recovery path after a nested RELEASE succeeded (so `txDepth` was
      // bumped up and back down) and then the outer COMMIT failed.
      //
      // Crucially we follow the failure with *another* top-level
      // transaction — the bug this catches is the writer isolate
      // preserving stale `txDepth > 0` after a commit failure, in which
      // case the next BeginRequest would issue a SAVEPOINT against a
      // non-existent transaction instead of BEGIN IMMEDIATE.
      await db.execute('PRAGMA foreign_keys = ON');
      await db.execute('CREATE TABLE parent(id INTEGER PRIMARY KEY)');
      await db.execute('''
        CREATE TABLE child(
          id INTEGER PRIMARY KEY,
          pid INTEGER NOT NULL,
          FOREIGN KEY (pid) REFERENCES parent(id) DEFERRABLE INITIALLY DEFERRED
        )
      ''');

      await expectLater(
        db.transaction((tx) async {
          await tx.execute('INSERT INTO child(pid) VALUES (?)', [999]);
          await tx.transaction((inner) async {
            // Inner insert is fine on its own — the deferred FK only
            // trips at the outermost commit.
            await inner.execute('INSERT INTO parent(id) VALUES (?)', [1]);
          });
        }),
        throwsA(isA<Exception>()),
      );

      // A brand-new top-level transaction must start cleanly. Under the
      // stale-depth bug, this would send SAVEPOINT s1 against no active
      // transaction and either fail or silently corrupt state.
      await db.transaction((tx) async {
        await tx.execute('INSERT INTO parent(id) VALUES (?)', [2]);
        await tx.execute('INSERT INTO child(pid) VALUES (?)', [2]);
      });

      final children = await db.select('SELECT pid FROM child ORDER BY id');
      expect(children, hasLength(1));
      expect(children[0]['pid'], 2);

      final parents = await db.select('SELECT id FROM parent ORDER BY id');
      expect(parents, hasLength(1));
      expect(parents[0]['id'], 2);
    });
  });
}
