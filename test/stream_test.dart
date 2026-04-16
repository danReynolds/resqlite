import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

final class _EventWaiter<T> {
  _EventWaiter(this.count, this.completer);

  final int count;
  final Completer<T> completer;
}

final class _StreamProbe<T> {
  _StreamProbe(Stream<T> stream) {
    _subscription = stream.listen(
      (event) {
        _events.add(event);
        final ready = _waiters.where((waiter) => waiter.count <= _events.length);
        for (final waiter in ready.toList()) {
          _waiters.remove(waiter);
          if (!waiter.completer.isCompleted) {
            waiter.completer.complete(_events[waiter.count - 1]);
          }
        }
      },
      onError: (error, stackTrace) {
        lastError = error;
      },
      onDone: () {
        if (!_done.isCompleted) _done.complete();
      },
    );
  }

  final _events = <T>[];
  final _waiters = <_EventWaiter<T>>[];
  final _done = Completer<void>();
  late final StreamSubscription<T> _subscription;
  Object? lastError;

  List<T> get events => List.unmodifiable(_events);

  Future<T> event(
    int count, {
    Duration timeout = const Duration(seconds: 2),
  }) {
    if (_events.length >= count) {
      return Future.value(_events[count - 1]);
    }

    final completer = Completer<T>();
    final waiter = _EventWaiter<T>(count, completer);
    _waiters.add(waiter);
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _waiters.remove(waiter);
        throw TimeoutException('Timed out waiting for event $count');
      },
    );
  }

  Future<void> expectNoAdditionalEvents(Duration duration) async {
    try {
      final event = await this.event(_events.length + 1, timeout: duration);
      fail('Unexpected additional stream event: $event');
    } on TimeoutException {
      // Expected: no event arrived within the window.
    }
  }

  Future<void> waitForDone({
    Duration timeout = const Duration(seconds: 2),
  }) {
    return _done.future.timeout(timeout);
  }

  Future<void> cancel() => _subscription.cancel();
}

void main() {
  group('Database.stream', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('resqlite_stream_test_');
      db = await Database.open('${tempDir.path}/test.db');
      await db.execute(
        'CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT NOT NULL, value INTEGER NOT NULL)',
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

    test('emits initial results', () async {
      await db.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['alice', 1]);
      await db.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['bob', 2]);

      final stream = db.stream('SELECT name FROM items ORDER BY id');
      final first = await stream.first;

      expect(first, hasLength(2));
      expect(first[0]['name'], 'alice');
      expect(first[1]['name'], 'bob');
    });

    test('re-emits after write to dependent table', () async {
      await db.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['alice', 1]);

      final probe = _StreamProbe(db.stream('SELECT name FROM items ORDER BY id'));

      final initialRows = await probe.event(1);
      expect(initialRows, hasLength(1));

      // Write to the table — should trigger re-emission.
      await db.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['bob', 2]);

      final updatedRows = await probe.event(2);
      expect(probe.events, hasLength(2));
      expect(updatedRows, hasLength(2));
      expect(updatedRows[1]['name'], 'bob');

      await probe.cancel();
    });

    test('does not re-emit for writes to unrelated tables', () async {
      await db.execute('CREATE TABLE other(id INTEGER PRIMARY KEY, data TEXT)');
      await db.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['alice', 1]);

      final probe = _StreamProbe(db.stream('SELECT name FROM items ORDER BY id'));
      await probe.event(1);
      expect(probe.events, hasLength(1));

      // Write to a different table — should NOT trigger re-emission.
      await db.execute('INSERT INTO other(data) VALUES (?)', ['unrelated']);

      await probe.expectNoAdditionalEvents(const Duration(milliseconds: 150));
      expect(probe.events, hasLength(1)); // Still just the initial emission.

      await probe.cancel();
    });

    test('stream with parameters', () async {
      await db.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['alice', 1]);
      await db.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['bob', 2]);
      await db.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['charlie', 1]);

      final stream = db.stream(
        'SELECT name FROM items WHERE value = ? ORDER BY name',
        [1],
      );
      final first = await stream.first;

      expect(first, hasLength(2));
      expect(first[0]['name'], 'alice');
      expect(first[1]['name'], 'charlie');
    });

    test('recreated parameterized stream still re-emits after update', () async {
      await db.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['alice', 1]);
      await db.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['bob', 2]);

      Future<void> expectRoundTrip(int id, int expectedValue) async {
        final initial = Completer<void>();
        final updated = Completer<void>();
        final results = <List<Map<String, Object?>>>[];

        final sub = db
            .stream('SELECT id, name, value FROM items WHERE id = ?', [id])
            .listen((rows) {
              results.add(rows);
              if (!initial.isCompleted) {
                initial.complete();
                return;
              }
              if (!updated.isCompleted) {
                updated.complete();
              }
            });

        await initial.future.timeout(const Duration(seconds: 2));
        expect(results, hasLength(1));
        expect(results[0], hasLength(1));
        expect(results[0][0]['id'], id);

        await db.execute('UPDATE items SET value = ? WHERE id = ?', [
          expectedValue,
          id,
        ]);

        await updated.future.timeout(const Duration(seconds: 2));
        expect(results, hasLength(2));
        expect(results[1][0]['value'], expectedValue);

        await sub.cancel();
      }

      // First run prepares and caches the statement shape.
      await expectRoundTrip(1, 11);
      // Second run reuses the same SQL shape with a different parameter.
      await expectRoundTrip(2, 22);
    });

    test('deduplicates same query', () async {
      await db.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['alice', 1]);

      const sql = 'SELECT name FROM items ORDER BY id';

      final stream1 = db.stream(sql);
      final stream2 = db.stream(sql);

      final result1 = await stream1.first;
      final result2 = await stream2.first;

      // Both should get the same data.
      expect(result1, hasLength(1));
      expect(result2, hasLength(1));
      expect(result1[0]['name'], 'alice');
      expect(result2[0]['name'], 'alice');
    });

    test('empty result stream', () async {
      final stream = db.stream('SELECT * FROM items');
      final first = await stream.first;

      expect(first, isEmpty);
    });

    test('re-emits after batch write', () async {
      final probe = _StreamProbe(db.stream('SELECT COUNT(*) as cnt FROM items'));
      final initialRows = await probe.event(1);
      expect(initialRows[0]['cnt'], 0);

      // Batch insert.
      await db.executeBatch(
        'INSERT INTO items(name, value) VALUES (?, ?)',
        [['a', 1], ['b', 2], ['c', 3]],
      );

      final updatedRows = await probe.event(2);
      expect(probe.events, hasLength(2));
      expect(updatedRows[0]['cnt'], 3);

      await probe.cancel();
    });

    test('re-emits after transaction', () async {
      final probe = _StreamProbe(db.stream('SELECT COUNT(*) as cnt FROM items'));
      await probe.event(1);
      expect(probe.events, hasLength(1));

      await db.transaction((tx) async {
        await tx.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['a', 1]);
        await tx.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['b', 2]);
      });

      final updatedRows = await probe.event(2);
      expect(probe.events, hasLength(2));
      expect(updatedRows[0]['cnt'], 2);

      await probe.cancel();
    });

    test('re-emits after transaction read observes uncommitted write', () async {
      final initial = Completer<void>();
      final updated = Completer<void>();
      final counts = <int>[];

      final sub = db.stream('SELECT COUNT(*) as cnt FROM items').listen((rows) {
        final count = rows[0]['cnt'] as int;
        counts.add(count);
        if (!initial.isCompleted) {
          initial.complete();
          return;
        }
        if (!updated.isCompleted) {
          updated.complete();
        }
      });

      await initial.future.timeout(const Duration(seconds: 2));
      expect(counts, [0]);

      final txCount = await db.transaction((tx) async {
        await tx.execute('INSERT INTO items(name, value) VALUES (?, ?)', [
          'inside_tx',
          1,
        ]);
        final rows = await tx.select('SELECT COUNT(*) as cnt FROM items');
        return rows[0]['cnt'] as int;
      });

      expect(txCount, 1);

      await updated.future.timeout(const Duration(seconds: 2));
      expect(counts, [0, 1]);

      await sub.cancel();
    });

    test('does not re-emit when data unchanged (result-change detection)', () async {
      await db.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['alice', 1]);
      await db.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['bob', 2]);

      final probe = _StreamProbe(
        db.stream('SELECT name, value FROM items ORDER BY id'),
      );
      final initialRows = await probe.event(1);
      expect(initialRows, hasLength(2));

      // Write that doesn't actually change any data: SET value = value.
      await db.execute('UPDATE items SET value = value WHERE id = 1');

      await probe.expectNoAdditionalEvents(const Duration(milliseconds: 200));
      expect(probe.events, hasLength(1)); // Still just initial.

      await probe.cancel();
    });

    test('re-emits when data actually changes after no-op write', () async {
      await db.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['alice', 1]);

      final probe = _StreamProbe(
        db.stream('SELECT name, value FROM items ORDER BY id'),
      );
      await probe.event(1);
      expect(probe.events, hasLength(1));

      // No-op write — should be suppressed.
      await db.execute('UPDATE items SET value = value WHERE id = 1');
      await probe.expectNoAdditionalEvents(const Duration(milliseconds: 150));
      expect(probe.events, hasLength(1)); // Suppressed.

      // Real write — should trigger emission.
      await db.execute('UPDATE items SET value = 99 WHERE id = 1');
      final updatedRows = await probe.event(2);
      expect(probe.events, hasLength(2));
      expect(updatedRows[0]['value'], 99);

      await probe.cancel();
    });

    test('10+ concurrent streams all emit and re-emit', () async {
      // Regression test for thread pool exhaustion when many streams
      // are invalidated simultaneously.
      const streamCount = 15;

      // Insert initial data.
      for (var i = 0; i < 50; i++) {
        await db.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['item_$i', i]);
      }

      final initialCompleters = <int, Completer<void>>{};
      final reEmitCompleters = <int, Completer<void>>{};
      final subs = <StreamSubscription>[];

      for (var i = 0; i < streamCount; i++) {
        initialCompleters[i] = Completer<void>();
        reEmitCompleters[i] = Completer<void>();
        final idx = i;
        var emitCount = 0;

        // Each stream has unique SQL so no deduplication.
        final stream = db.stream(
          "SELECT COUNT(*) as cnt, '$i' as sid FROM items",
        );

        subs.add(stream.listen((rows) {
          emitCount++;
          if (emitCount == 1 && !initialCompleters[idx]!.isCompleted) {
            initialCompleters[idx]!.complete();
          } else if (emitCount >= 2 && !reEmitCompleters[idx]!.isCompleted) {
            reEmitCompleters[idx]!.complete();
          }
        }));
      }

      // All initial emissions should arrive.
      await Future.wait(
        initialCompleters.values.map((c) => c.future),
      ).timeout(const Duration(seconds: 5));

      // Write to trigger re-emission for all streams.
      await db.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['trigger', 0]);

      // All re-emissions should arrive.
      await Future.wait(
        reEmitCompleters.values.map((c) => c.future),
      ).timeout(const Duration(seconds: 5));

      for (final s in subs) {
        await s.cancel();
      }
    });

    test('stream entry is removed from registry after last listener cancels', () async {
      await db.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['alice', 1]);

      final registry = db.streamEngine;
      expect(registry.length, 0);

      // Create a stream and listen.
      final probe = _StreamProbe(db.stream('SELECT name FROM items ORDER BY id'));
      await probe.event(1);
      expect(registry.length, 1);

      // Cancel the subscription — entry should be cleaned up.
      await probe.cancel();
      expect(registry.length, 0);
    });

    test('stream entry persists while at least one listener remains', () async {
      await db.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['alice', 1]);

      final registry = db.streamEngine;
      const sql = 'SELECT name FROM items ORDER BY id';

      // Create two subscriptions to the same stream (deduplicated).
      final probe1 = _StreamProbe(db.stream(sql));
      await probe1.event(1);
      expect(registry.length, 1);

      final probe2 = _StreamProbe(db.stream(sql));
      await probe2.event(1);
      expect(registry.length, 1); // Still just one entry (deduplicated).

      // Cancel first subscription — entry should remain (second listener still active).
      await probe1.cancel();
      expect(registry.length, 1);

      // Cancel second subscription — entry should be removed.
      await probe2.cancel();
      expect(registry.length, 0);
    });

    test('stream can be re-created after cleanup', () async {
      await db.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['alice', 1]);

      final registry = db.streamEngine;
      const sql = 'SELECT name FROM items ORDER BY id';

      // Create, listen, cancel.
      final probe1 = _StreamProbe(db.stream(sql));
      await probe1.event(1);
      expect(registry.length, 1);

      await probe1.cancel();
      expect(registry.length, 0);

      // Create again — should work and register a new entry.
      final stream2 = db.stream(sql);
      final result = await stream2.first;
      expect(result, hasLength(1));
      expect(result[0]['name'], 'alice');
    });

    test('does not re-emit after rolled-back transaction', () async {
      await db.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['initial', 1]);

      final probe = _StreamProbe(db.stream('SELECT COUNT(*) as cnt FROM items'));
      final initialRows = await probe.event(1);
      expect(initialRows[0]['cnt'], 1);

      // Rolled-back transaction — should NOT trigger re-emission.
      try {
        await db.transaction((tx) async {
          await tx.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['ghost', 2]);
          throw StateError('rollback');
        });
      } catch (_) {}

      await probe.expectNoAdditionalEvents(const Duration(milliseconds: 150));
      expect(probe.events, hasLength(1)); // Still just initial.

      await probe.cancel();
    });

    test('rapid sequential writes converge to latest state', () async {
      // Exercises the re-query generation logic: many writes fire many
      // concurrent re-queries. Only the result from the latest snapshot
      // should be emitted — no stale intermediate states.
      final initial = Completer<void>();
      final results = <int>[];
      final completer = Completer<void>();

      final sub = db.stream('SELECT COUNT(*) as cnt FROM items').listen((rows) {
        final count = rows[0]['cnt'] as int;
        results.add(count);
        if (!initial.isCompleted) {
          initial.complete();
        }
        if (count == 20) completer.complete();
      });

      await initial.future.timeout(const Duration(seconds: 2));
      expect(results, isNotEmpty);
      expect(results.first, 0);

      // Fire 20 sequential writes as fast as possible.
      for (var i = 0; i < 20; i++) {
        await db.execute(
          'INSERT INTO items(name, value) VALUES (?, ?)',
          ['item_$i', i],
        );
      }

      // Wait for the stream to catch up.
      await completer.future.timeout(const Duration(seconds: 5));

      // The final emission must be 20. Intermediate emissions are allowed
      // but must be monotonically non-decreasing (no stale snapshots).
      expect(results.last, 20);
      for (var i = 1; i < results.length; i++) {
        expect(results[i], greaterThanOrEqualTo(results[i - 1]),
            reason: 'emission $i (${results[i]}) < emission ${i - 1} (${results[i - 1]}) — stale snapshot');
      }

      await sub.cancel();
    });

    test('stream with invalid SQL propagates error', () async {
      final stream = db.stream('SELECT * FROM nonexistent_table');

      // The stream should emit a typed query error, not hang forever.
      await expectLater(
        stream.first,
        throwsA(isA<ResqliteQueryException>()),
      );
    });

    test('stream error cleans up entry', () async {
      final engine = db.streamEngine;
      final stream = db.stream('SELECT * FROM nonexistent_table');

      // Listen to consume the error (otherwise it's unhandled).
      final completer = Completer<void>();
      final sub = stream.listen(
        (_) {},
        onError: (e) {
          if (!completer.isCompleted) completer.complete();
        },
      );

      await completer.future.timeout(const Duration(seconds: 2));

      // Entry should be cleaned up after the error.
      expect(engine.length, 0);

      await sub.cancel();
    });

    test('re-query failure after initial success propagates error and recovers', () async {
      await db.execute('INSERT INTO items(name, value) VALUES (?, ?)', [
        'alice',
        1,
      ]);

      final initial = Completer<void>();
      final recovered = Completer<void>();
      final errorReceived = Completer<void>();
      final results = <List<Map<String, Object?>>>[];
      Object? streamError;

      final sub = db.stream('SELECT name FROM items ORDER BY id').listen(
        (rows) {
          results.add(rows);
          if (!initial.isCompleted) {
            initial.complete();
            return;
          }
          if (!recovered.isCompleted) {
            recovered.complete();
          }
        },
        onError: (error, stackTrace) {
          streamError = error;
          if (!errorReceived.isCompleted) errorReceived.complete();
        },
      );

      await initial.future.timeout(const Duration(seconds: 2));
      expect(results, hasLength(1));
      expect(results[0][0]['name'], 'alice');

      // Break the query by renaming the column it selects.
      await db.execute('ALTER TABLE items RENAME COLUMN name TO title');
      db.streamEngine.handleDirtyTables(['items']);

      // Error should be delivered to onError, not swallowed.
      await errorReceived.future.timeout(const Duration(seconds: 2));
      expect(streamError, isA<ResqliteQueryException>());
      expect(results, hasLength(1)); // No data emission during failure.

      // Fix the schema and insert — stream should recover.
      streamError = null;
      await db.execute('ALTER TABLE items RENAME COLUMN title TO name');
      await db.execute('INSERT INTO items(name, value) VALUES (?, ?)', [
        'bob',
        2,
      ]);

      await recovered.future.timeout(const Duration(seconds: 2));
      expect(streamError, isNull); // No new errors after recovery.
      expect(results, hasLength(2));
      expect(results[1].map((row) => row['name']), ['alice', 'bob']);

      await sub.cancel();
    });

    test('many rapid writes to same table with active stream', () async {
      // Stress test: 50 writes in quick succession with an active stream.
      // The stream must converge to the correct final state.
      final initial = Completer<void>();
      final results = <int>[];
      final completer = Completer<void>();

      final sub = db.stream('SELECT COUNT(*) as cnt FROM items').listen((rows) {
        results.add(rows[0]['cnt'] as int);
        if (!initial.isCompleted) {
          initial.complete();
        }
        if (results.last == 50) completer.complete();
      });

      await initial.future.timeout(const Duration(seconds: 2));

      // Batch the writes to go even faster.
      await db.executeBatch(
        'INSERT INTO items(name, value) VALUES (?, ?)',
        List.generate(50, (i) => ['item_$i', i]),
      );

      await completer.future.timeout(const Duration(seconds: 5));
      expect(results.last, 50);

      await sub.cancel();
    });

    test('close closes active streams and clears registry', () async {
      await db.execute('INSERT INTO items(name, value) VALUES (?, ?)', [
        'alice',
        1,
      ]);

      final initial = Completer<void>();
      final done = Completer<void>();

      final sub = db.stream('SELECT name FROM items ORDER BY id').listen(
        (_) {
          if (!initial.isCompleted) initial.complete();
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
      );

      await initial.future.timeout(const Duration(seconds: 2));
      expect(db.streamEngine.length, 1);

      await db.close();

      await done.future.timeout(const Duration(seconds: 2));
      expect(db.streamEngine.length, 0);

      await sub.cancel();
    });
  });
}
