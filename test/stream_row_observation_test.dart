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
    _subscription = stream.listen((event) {
      _events.add(event);
      final ready = _waiters.where((waiter) => waiter.count <= _events.length);
      for (final waiter in ready.toList()) {
        _waiters.remove(waiter);
        if (!waiter.completer.isCompleted) {
          waiter.completer.complete(_events[waiter.count - 1]);
        }
      }
    });
  }

  final _events = <T>[];
  final _waiters = <_EventWaiter<T>>[];
  late final StreamSubscription<T> _subscription;

  Future<T> event(int count, {Duration timeout = const Duration(seconds: 2)}) {
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
      // Expected.
    }
  }

  Future<void> cancel() => _subscription.cancel();
}

void main() {
  group('explicit stream row observation', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'resqlite_stream_row_observation_',
      );
      db = await Database.open('${tempDir.path}/test.db');
      await db.execute(
        'CREATE TABLE items('
        'id INTEGER PRIMARY KEY, '
        'body TEXT NOT NULL, '
        'updated_at INTEGER NOT NULL'
        ')',
      );
      await db.executeBatch(
        'INSERT INTO items(id, body, updated_at) VALUES (?, ?, ?)',
        [
          [1, 'one', 0],
          [2, 'two', 0],
        ],
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

    test('explicit row miss stays quiet while row hit emits', () async {
      final probe = _StreamProbe(
        db.streamWithRowObservation(
          'SELECT id, body, updated_at FROM items WHERE id = ?',
          parameters: const [1],
          row: const RowIdentity(table: 'items', primaryKey: 1),
        ),
      );

      final initial = await probe.event(1);
      expect(initial.single['body'], 'one');

      await db.executeWithRowChanges(
        'UPDATE items SET body = ?, updated_at = ? WHERE id = ?',
        parameters: const ['two updated', 1, 2],
        rowChanges: const [RowIdentity(table: 'items', primaryKey: 2)],
      );
      await probe.expectNoAdditionalEvents(const Duration(milliseconds: 150));

      await db.executeWithRowChanges(
        'UPDATE items SET body = ?, updated_at = ? WHERE id = ?',
        parameters: const ['one updated', 2, 1],
        rowChanges: const [RowIdentity(table: 'items', primaryKey: 1)],
      );
      final updated = await probe.event(2);
      expect(updated.single['body'], 'one updated');

      await probe.cancel();
    });

    test('ordinary writes stay conservative and correct', () async {
      final probe = _StreamProbe(
        db.streamWithRowObservation(
          'SELECT id, body, updated_at FROM items WHERE id = ?',
          parameters: const [1],
          row: const RowIdentity(table: 'items', primaryKey: 1),
        ),
      );

      await probe.event(1);

      await db.execute(
        'UPDATE items SET body = ?, updated_at = ? WHERE id = ?',
        const ['two updated', 1, 2],
      );
      await probe.expectNoAdditionalEvents(const Duration(milliseconds: 150));

      await db.execute(
        'UPDATE items SET body = ?, updated_at = ? WHERE id = ?',
        const ['one updated', 2, 1],
      );
      final updated = await probe.event(2);
      expect(updated.single['body'], 'one updated');

      await probe.cancel();
    });

    test(
      'row hint is ignored when query dependencies do not include table',
      () async {
        final probe = _StreamProbe(
          db.streamWithRowObservation(
            'SELECT id, body, updated_at FROM items WHERE id = ?',
            parameters: const [1],
            row: const RowIdentity(table: 'other_items', primaryKey: 1),
          ),
        );

        await probe.event(1);

        await db.executeWithRowChanges(
          'UPDATE items SET body = ?, updated_at = ? WHERE id = ?',
          parameters: const ['one updated', 1, 1],
          rowChanges: const [RowIdentity(table: 'items', primaryKey: 2)],
        );

        final updated = await probe.event(2);
        expect(updated.single['body'], 'one updated');

        await probe.cancel();
      },
    );

    test('row-change writes are rejected inside transactions', () async {
      await expectLater(
        db.transaction((_) async {
          await db.executeWithRowChanges(
            'UPDATE items SET body = ? WHERE id = ?',
            parameters: const ['one updated', 1],
            rowChanges: const [RowIdentity(table: 'items', primaryKey: 1)],
          );
        }),
        throwsStateError,
      );
    });
  });
}
