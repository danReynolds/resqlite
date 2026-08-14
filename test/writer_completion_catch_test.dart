import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/profile_mode.dart';
import 'package:resqlite/src/writer/writer.dart';
import 'package:test/test.dart';

void main() {
  group('writer completion catch (exp 271)', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('resqlite_catch_');
      db = await Database.open('${tempDir.path}/test.db');
      await db.execute(
        'CREATE TABLE items(id INTEGER PRIMARY KEY, value INTEGER NOT NULL)',
      );
      WriterCompletionCatchDiagnostics.reset();
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'sequential catches preserve results and canonical reply FIFO',
      () async {
        for (var id = 1; id <= 200; id++) {
          final result = await db.execute(
            'INSERT INTO items(id, value) VALUES (?, ?)',
            [id, id * 10],
          );
          expect(result.affectedRows, 1);
          expect(result.lastInsertId, id);

          if (id % 17 == 0) {
            await expectLater(
              db.execute('INSERT INTO items(id, value) VALUES (?, ?)', [id, 0]),
              throwsA(isA<ResqliteQueryException>()),
            );
          }
        }

        // Let every canonical reply drain its caught completer tombstone, then
        // prove the next request is still matched to the correct FIFO entry.
        await Future<void>.delayed(Duration.zero);
        final update = await db.execute(
          'UPDATE items SET value = value + 1 WHERE id = 200',
        );
        expect(update.affectedRows, 1);
        expect(
          (await db.select('SELECT COUNT(*) AS c FROM items')).single['c'],
          200,
        );

        if (WriterCompletionCatchDiagnostics.enabled) {
          if (kProfileMode) {
            expect(WriterCompletionCatchDiagnostics.attempts, 0);
          } else {
            expect(WriterCompletionCatchDiagnostics.attempts, greaterThan(0));
            expect(WriterCompletionCatchDiagnostics.hits, greaterThan(0));
            expect(WriterCompletionCatchDiagnostics.misses, greaterThan(0));
          }
        }
      },
    );

    test('an active stream bypasses the completion mailbox', () async {
      await db.execute('INSERT INTO items(id, value) VALUES (1, 0)');
      final values = <int>[];
      final reached = Completer<void>();
      final subscription = db
          .stream('SELECT value FROM items WHERE id = 1')
          .listen((rows) {
            final value = rows.single['value'] as int;
            values.add(value);
            if (value == 20 && !reached.isCompleted) reached.complete();
          });
      try {
        while (values.isEmpty) {
          await Future<void>.delayed(Duration.zero);
        }
        WriterCompletionCatchDiagnostics.reset();
        for (var i = 0; i < 20; i++) {
          await db.execute('UPDATE items SET value = value + 1 WHERE id = 1');
        }
        await reached.future.timeout(const Duration(seconds: 5));
        expect(values.last, 20);
        if (WriterCompletionCatchDiagnostics.enabled) {
          expect(WriterCompletionCatchDiagnostics.attempts, 0);
        }
      } finally {
        await subscription.cancel();
      }
    });

    test(
      'a stream registered after a slow scalar send catches the write',
      () async {
        const rowCount = 20000;
        await db.executeBatch(
          'INSERT INTO items(id, value) VALUES (?, ?)',
          <List<Object?>>[
            for (var id = 1; id <= rowCount; id++) <Object?>[id, 0],
          ],
        );
        WriterCompletionCatchDiagnostics.reset();

        final write = db.execute(
          'UPDATE items SET value = value + 1 WHERE id <= ?',
          const <Object?>[rowCount],
        );
        // The execute continuation sends and exhausts its bounded poll before
        // this timer event registers the first stream.
        await Future<void>.delayed(Duration.zero);

        final totals = <int>[];
        final reachedFinal = Completer<void>();
        final subscription = db
            .stream('SELECT SUM(value) AS total FROM items')
            .listen((rows) {
              final total = rows.single['total'] as int;
              totals.add(total);
              if (total == rowCount && !reachedFinal.isCompleted) {
                reachedFinal.complete();
              }
            });
        try {
          expect((await write).affectedRows, rowCount);
          await reachedFinal.future.timeout(const Duration(seconds: 5));
          expect(totals.last, rowCount);
          if (WriterCompletionCatchDiagnostics.enabled && !kProfileMode) {
            expect(WriterCompletionCatchDiagnostics.attempts, 1);
            expect(WriterCompletionCatchDiagnostics.hits, 0);
            expect(WriterCompletionCatchDiagnostics.misses, 1);
          }
        } finally {
          await subscription.cancel();
        }
      },
    );

    test('close drains caught tombstones before freeing the mailbox', () async {
      for (var id = 1; id <= 100; id++) {
        await db.execute('INSERT INTO items(id, value) VALUES (?, ?)', [
          id,
          id,
        ]);
      }
      await db.close();

      final reopened = await Database.open('${tempDir.path}/test.db');
      try {
        expect(
          (await reopened.select(
            'SELECT COUNT(*) AS c FROM items',
          )).single['c'],
          100,
        );
      } finally {
        await reopened.close();
      }
    });
  });
}
