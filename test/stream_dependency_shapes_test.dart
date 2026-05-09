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
      // Expected.
    }
  }

  Future<void> cancel() => _subscription.cancel();
}

void main() {
  group('Database.stream dependency shapes', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      tempDir = await Directory.systemTemp
          .createTemp('resqlite_stream_dependency_shapes_');
      db = await Database.open('${tempDir.path}/test.db');
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

    test('join query re-emits when either base table changes', () async {
      await db.execute(
        'CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE posts(id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL, title TEXT NOT NULL)',
      );
      await db.execute('INSERT INTO users(id, name) VALUES (?, ?)', [1, 'Ada']);
      await db.execute(
        'INSERT INTO posts(id, user_id, title) VALUES (?, ?, ?)',
        [1, 1, 'First'],
      );

      final probe = _StreamProbe(
        db.stream(
          'SELECT posts.id, users.name, posts.title '
          'FROM posts JOIN users ON users.id = posts.user_id '
          'ORDER BY posts.id',
        ),
      );

      final initial = await probe.event(1);
      expect(initial, hasLength(1));
      expect(initial[0]['name'], 'Ada');

      await db.execute('UPDATE users SET name = ? WHERE id = ?', ['Grace', 1]);
      final afterUserUpdate = await probe.event(2);
      expect(afterUserUpdate[0]['name'], 'Grace');

      await db.execute(
        'INSERT INTO posts(id, user_id, title) VALUES (?, ?, ?)',
        [2, 1, 'Second'],
      );
      final afterPostInsert = await probe.event(3);
      expect(afterPostInsert, hasLength(2));
      expect(afterPostInsert[1]['title'], 'Second');

      await probe.cancel();
    });

    test('subquery query re-emits when inner table changes', () async {
      await db.execute(
        'CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE refs(item_id INTEGER PRIMARY KEY)',
      );
      await db.execute('INSERT INTO items(id, name) VALUES (?, ?)', [1, 'alpha']);
      await db.execute('INSERT INTO items(id, name) VALUES (?, ?)', [2, 'beta']);
      await db.execute('INSERT INTO refs(item_id) VALUES (?)', [1]);

      final probe = _StreamProbe(
        db.stream(
          'SELECT name FROM items '
          'WHERE id IN (SELECT item_id FROM refs) '
          'ORDER BY id',
        ),
      );

      final initial = await probe.event(1);
      expect(initial.map((row) => row['name']), ['alpha']);

      await db.execute('INSERT INTO refs(item_id) VALUES (?)', [2]);
      final updated = await probe.event(2);
      expect(updated.map((row) => row['name']), ['alpha', 'beta']);

      await probe.cancel();
    });

    test('view query re-emits when base table changes', () async {
      await db.execute(
        'CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT NOT NULL, active INTEGER NOT NULL)',
      );
      await db.execute(
        'CREATE VIEW active_items AS '
        'SELECT id, name FROM items WHERE active = 1',
      );
      await db.execute(
        'INSERT INTO items(id, name, active) VALUES (?, ?, ?)',
        [1, 'alpha', 1],
      );
      await db.execute(
        'INSERT INTO items(id, name, active) VALUES (?, ?, ?)',
        [2, 'beta', 0],
      );

      final probe = _StreamProbe(
        db.stream('SELECT id, name FROM active_items ORDER BY id'),
      );

      final initial = await probe.event(1);
      expect(initial.map((row) => row['name']), ['alpha']);

      await db.execute('UPDATE items SET active = 1 WHERE id = ?', [2]);
      final updated = await probe.event(2);
      expect(updated.map((row) => row['name']), ['alpha', 'beta']);

      await probe.cancel();
    });

    test('cte query re-emits when underlying table changes', () async {
      await db.execute(
        'CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT NOT NULL, active INTEGER NOT NULL)',
      );
      await db.execute(
        'INSERT INTO items(id, name, active) VALUES (?, ?, ?)',
        [1, 'alpha', 1],
      );
      await db.execute(
        'INSERT INTO items(id, name, active) VALUES (?, ?, ?)',
        [2, 'beta', 0],
      );

      final probe = _StreamProbe(
        db.stream(
          'WITH active_items AS ('
          '  SELECT id, name FROM items WHERE active = 1'
          ') '
          'SELECT id, name FROM active_items ORDER BY id',
        ),
      );

      final initial = await probe.event(1);
      expect(initial.map((row) => row['name']), ['alpha']);

      await db.execute('UPDATE items SET active = 1 WHERE id = ?', [2]);
      final updated = await probe.event(2);
      expect(updated.map((row) => row['name']), ['alpha', 'beta']);

      await probe.cancel();
    });

    test('does not over-fire on unrelated table for shaped queries', () async {
      await db.execute(
        'CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE posts(id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL, title TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE audit(id INTEGER PRIMARY KEY, body TEXT NOT NULL)',
      );
      await db.execute('INSERT INTO users(id, name) VALUES (?, ?)', [1, 'Ada']);
      await db.execute(
        'INSERT INTO posts(id, user_id, title) VALUES (?, ?, ?)',
        [1, 1, 'First'],
      );

      final probe = _StreamProbe(
        db.stream(
          'SELECT posts.id, users.name, posts.title '
          'FROM posts JOIN users ON users.id = posts.user_id',
        ),
      );

      await probe.event(1);
      await db.execute('INSERT INTO audit(body) VALUES (?)', ['noop']);
      await probe.expectNoAdditionalEvents(const Duration(milliseconds: 150));

      await probe.cancel();
    });
  });
}
