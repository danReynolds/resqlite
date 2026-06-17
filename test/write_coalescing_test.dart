import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

/// Coverage for exp 180 cross-call request batching: concurrently-issued
/// standalone execute() calls are coalesced into one MultiExecuteRequest and
/// run as independent autocommits on the worker. These tests pin the behavior
/// that must stay identical to sending each write individually — correct
/// per-call results, per-statement failure isolation, and stream invalidation.
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
  });
}
