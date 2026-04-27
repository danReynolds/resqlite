// Phase 0 verification for exp-106 polish.
//
// Three black-box scenarios that exercise SQLite's authorizer behavior on
// triggers and FK cascades. The polish design hinges on whether the
// authorizer fires SQLITE_UPDATE events for trigger / cascade-induced
// column writes at the calling stmt's prepare time:
//
//   * If yes → column tracking captures the propagated writes; no
//     additional fallback is needed.
//   * If no → exp-106's column-level dispatch elision can silently
//     drop trigger / cascade-induced re-emissions, and the polish must
//     ship a "trigger-touched stmt → unreliable column set" fallback.
//
// These tests assert that streams DO re-emit in each of the three
// shapes. If they pass, the column dependencies captured during prepare
// are sufficient and the fallback is not needed. If they fail, the
// fallback ships in Phase 1.
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

  Future<void> cancel() => _subscription.cancel();
}

void main() {
  group('Trigger and FK cascade column tracking', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      tempDir = await Directory.systemTemp
          .createTemp('resqlite_trigger_cascade_');
      db = await Database.open('${tempDir.path}/test.db');
      // Required for ON DELETE CASCADE to actually fire.
      await db.execute('PRAGMA foreign_keys = ON');
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

    test(
      'cross-table AFTER UPDATE trigger: stream watching target column re-emits',
      () async {
        await db.execute(
          'CREATE TABLE table_a(id INTEGER PRIMARY KEY, col_x INTEGER NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE table_b(id INTEGER PRIMARY KEY, y INTEGER NOT NULL)',
        );
        await db.execute('''
          CREATE TRIGGER mirror_b_to_a
          AFTER UPDATE OF y ON table_b
          BEGIN
            UPDATE table_a SET col_x = NEW.y WHERE id = OLD.id;
          END;
        ''');
        await db.execute(
          'INSERT INTO table_a(id, col_x) VALUES (?, ?)',
          [1, 100],
        );
        await db.execute(
          'INSERT INTO table_b(id, y) VALUES (?, ?)',
          [1, 200],
        );

        // Stream watches a column on table_a only.
        final probe = _StreamProbe(
          db.stream('SELECT id, col_x FROM table_a WHERE id = 1'),
        );
        final initial = await probe.event(1);
        expect(initial[0]['col_x'], 100);

        // UPDATE table_b → trigger fires → table_a.col_x changes.
        await db.execute('UPDATE table_b SET y = ? WHERE id = ?', [555, 1]);
        final after = await probe.event(2);
        expect(after[0]['col_x'], 555);

        await probe.cancel();
      },
    );

    test(
      'same-table different-column trigger: stream watching col_b re-emits when writer updates col_a',
      () async {
        await db.execute(
          'CREATE TABLE table_t(id INTEGER PRIMARY KEY, col_a INTEGER NOT NULL, col_b INTEGER NOT NULL)',
        );
        await db.execute('''
          CREATE TRIGGER cross_col
          AFTER UPDATE OF col_a ON table_t
          BEGIN
            UPDATE table_t SET col_b = NEW.col_a * 2 WHERE id = NEW.id;
          END;
        ''');
        await db.execute(
          'INSERT INTO table_t(id, col_a, col_b) VALUES (?, ?, ?)',
          [1, 10, 20],
        );

        // Stream watches col_b only.
        final probe = _StreamProbe(
          db.stream('SELECT id, col_b FROM table_t WHERE id = 1'),
        );
        final initial = await probe.event(1);
        expect(initial[0]['col_b'], 20);

        // UPDATE col_a → trigger updates col_b. The dangerous case:
        // writer's preupdate hook only sees col_a in the stmt's
        // dep_columns, so dirty_columns gets (table_t, col_a). The
        // stream's column dep is (table_t, col_b). If column-level
        // dispatch elision uses set intersection, the trigger-induced
        // col_b write is silently lost UNLESS the authorizer captured
        // col_b at prepare time.
        await db.execute(
          'UPDATE table_t SET col_a = ? WHERE id = 1',
          [42],
        );
        final after = await probe.event(2);
        expect(after[0]['col_b'], 84);

        await probe.cancel();
      },
    );

    test(
      'FK ON DELETE CASCADE: stream watching child table re-emits when parent row deleted',
      () async {
        await db.execute(
          'CREATE TABLE parent(id INTEGER PRIMARY KEY, label TEXT NOT NULL)',
        );
        await db.execute('''
          CREATE TABLE child(
            id INTEGER PRIMARY KEY,
            parent_id INTEGER NOT NULL,
            data TEXT NOT NULL,
            FOREIGN KEY(parent_id) REFERENCES parent(id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'INSERT INTO parent(id, label) VALUES (?, ?)',
          [1, 'p1'],
        );
        await db.execute(
          'INSERT INTO child(id, parent_id, data) VALUES (?, ?, ?)',
          [10, 1, 'c1'],
        );
        await db.execute(
          'INSERT INTO child(id, parent_id, data) VALUES (?, ?, ?)',
          [11, 1, 'c2'],
        );

        // Stream watches child only.
        final probe = _StreamProbe(
          db.stream('SELECT id FROM child ORDER BY id'),
        );
        final initial = await probe.event(1);
        expect(initial.length, 2);

        // DELETE FROM parent → cascade deletes both child rows.
        await db.execute('DELETE FROM parent WHERE id = ?', [1]);
        final after = await probe.event(2);
        expect(after, isEmpty);

        await probe.cancel();
      },
    );
  });
}
