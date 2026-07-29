import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

/// Coverage for exp 180 cross-call request batching: concurrently-issued
/// standalone execute() calls are coalesced into one MultiExecuteRequest and
/// run as independent autocommits on the worker. These tests pin the behavior
/// that must stay identical to sending each write individually — correct
/// per-call results, per-statement failure isolation, trigger/FK effects, and
/// stream invalidation.
void main() {
  group('write coalescing (exp 180)', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('resqlite_coalesce_');
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

    test(
      'a concurrent burst all commits with correct per-call results',
      () async {
        const n = 64;
        final results = await Future.wait([
          for (var i = 0; i < n; i++)
            db.execute('INSERT INTO items(name) VALUES (?)', ['row_$i']),
        ]);

        // Each call gets its own WriteResult: affectedRows == 1 and a distinct,
        // monotonically increasing lastInsertId (issue order preserved).
        for (var i = 0; i < n; i++) {
          expect(results[i].affectedRows, 1);
          expect(results[i].lastInsertId, i + 1);
        }

        final rows = await db.select('SELECT id, name FROM items ORDER BY id');
        expect(rows, hasLength(n));
        expect(rows.first['name'], 'row_0');
        expect(rows.last['name'], 'row_${n - 1}');
      },
    );

    test(
      'a failing statement in the burst fails only its own caller',
      () async {
        // Interleave valid inserts with NOT NULL violations (odd rows bind
        // NULL) in one coalesced group: failures must reject only their own
        // futures while the valid writes still commit.
        final outcomes = await Future.wait([
          for (var i = 0; i < 10; i++)
            db
                .execute('INSERT INTO items(name) VALUES (?)', [
                  i.isEven ? 'ok_$i' : null,
                ])
                .then<Object>((r) => r, onError: (Object e) => e),
        ]);

        for (var i = 0; i < 10; i++) {
          if (i.isEven) {
            expect(
              outcomes[i],
              isA<WriteResult>(),
              reason: 'even insert $i should succeed',
            );
          } else {
            expect(
              outcomes[i],
              isA<ResqliteException>(),
              reason: 'odd insert $i should fail (NOT NULL)',
            );
          }
        }

        final rows = await db.select('SELECT name FROM items ORDER BY id');
        expect(rows.map((r) => r['name']), [
          'ok_0',
          'ok_2',
          'ok_4',
          'ok_6',
          'ok_8',
        ]);
      },
    );

    test('coalesced writes invalidate watching streams', () async {
      final counts = db
          .stream('SELECT COUNT(*) AS c FROM items')
          .map((rows) => rows.first['c'] as int);

      // emitsThrough waits for the post-burst count, tolerating the initial 0
      // and any intermediate emissions — no fixed-delay sleeps, so it can't
      // flake under load.
      final reachedEight = expectLater(counts, emitsThrough(8));

      await Future.wait([
        for (var i = 0; i < 8; i++)
          db.execute('INSERT INTO items(name) VALUES (?)', ['s_$i']),
      ]);

      await reachedEight;
    });

    test(
      'constraint errors preserve later cascades, triggers, and streams',
      () async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('CREATE TABLE parent(id INTEGER PRIMARY KEY)');
        await db.execute(
          'CREATE TABLE child('
          'id INTEGER PRIMARY KEY, '
          'parent_id INTEGER NOT NULL REFERENCES parent(id) ON DELETE CASCADE)',
        );
        await db.execute(
          'CREATE TABLE delete_audit('
          'id INTEGER PRIMARY KEY, parent_id INTEGER NOT NULL)',
        );
        await db.execute(
          'CREATE TRIGGER block_parent_two BEFORE DELETE ON parent '
          'WHEN old.id = 2 BEGIN '
          "SELECT RAISE(ABORT, 'blocked two'); END",
        );
        await db.execute(
          'CREATE TRIGGER block_parent_four BEFORE DELETE ON parent '
          'WHEN old.id = 4 BEGIN '
          "SELECT RAISE(ABORT, 'blocked four'); END",
        );
        await db.execute(
          'CREATE TRIGGER audit_parent_delete AFTER DELETE ON parent '
          'BEGIN INSERT INTO delete_audit(parent_id) VALUES (old.id); END',
        );
        for (var id = 1; id <= 5; id++) {
          await db.execute('INSERT INTO parent(id) VALUES (?)', [id]);
          await db.execute('INSERT INTO child(id, parent_id) VALUES (?, ?)', [
            id,
            id,
          ]);
        }

        final childReachedTwo = expectLater(
          db
              .stream('SELECT COUNT(*) AS c FROM child')
              .map((rows) => rows.single['c'] as int),
          emitsThrough(2),
        );
        final auditReachedThree = expectLater(
          db
              .stream('SELECT COUNT(*) AS c FROM delete_audit')
              .map((rows) => rows.single['c'] as int),
          emitsThrough(3),
        );

        const deleteSql = 'DELETE FROM parent WHERE id = ?';
        final outcomes = await Future.wait([
          for (var id = 1; id <= 5; id++)
            db
                .execute(deleteSql, [id])
                .then<Object>((result) => result, onError: (Object e) => e),
        ]);

        expect(outcomes[0], isA<WriteResult>());
        expect(outcomes[2], isA<WriteResult>());
        expect(outcomes[4], isA<WriteResult>());
        for (final (index, id, message) in [
          (1, 2, 'blocked two'),
          (3, 4, 'blocked four'),
        ]) {
          final error = outcomes[index] as ResqliteQueryException;
          expect(error.message, message);
          expect(error.sql, deleteSql);
          expect(error.parameters, [id]);
          expect(error.sqliteCode, 19); // SQLITE_CONSTRAINT
        }

        await childReachedTwo;
        await auditReachedThree;
        final parents = await db.select('SELECT id FROM parent ORDER BY id');
        final children = await db.select(
          'SELECT parent_id FROM child ORDER BY parent_id',
        );
        final audit = await db.select(
          'SELECT parent_id FROM delete_audit ORDER BY parent_id',
        );
        expect(parents.map((row) => row['id']), [2, 4]);
        expect(children.map((row) => row['parent_id']), [2, 4]);
        expect(audit.map((row) => row['parent_id']), [1, 3, 5]);
      },
    );
  });
}
