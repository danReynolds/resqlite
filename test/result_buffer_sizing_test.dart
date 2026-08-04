/// [EXP-260](../experiments/260-result-list-presize.md) sizes a query's result
/// buffer from the rows the same SQL returned before, so a large result stops
/// doubling its way up from a 256-row allocation.
///
/// A wrong hint can only cost time — the buffer is truncated to the real length
/// either way — so these tests gate the two things that would make it a bug
/// rather than a slowdown: the growth target must never come out *below* what
/// plain doubling would give (a buffer that stops growing loses rows), and a
/// statement whose row count swings between executions must keep returning
/// exactly its own rows.
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/query_decoder.dart'
    show RowSizeMemory, grownSlots, initialResultRows, nextRowHint;
import 'package:test/test.dart';

void main() {
  group('grownSlots', () {
    test('never grows by less than doubling, whatever the hint says', () {
      for (final hint in [0, 1, 10, 256, 1000]) {
        expect(grownSlots(6, 1536, hint), greaterThanOrEqualTo(3072));
      }
    });

    test('jumps straight to the hint when it exceeds doubling', () {
      // 10k rows x 6 columns, from the initial 256-row buffer: one growth
      // instead of the six doublings it would take to get there.
      expect(grownSlots(6, 1536, 10000), 60000);
    });

    test('falls back to doubling once the buffer has passed the hint', () {
      expect(grownSlots(6, 60000, 10000), 120000);
    });
  });

  group('RowSizeMemory', () {
    test('has no opinion until it has seen two executions', () {
      final memory = RowSizeMemory();
      expect(memory.hint, 0);
      memory.record(10000);
      expect(memory.hint, 0);
    });

    test('sizes a stable statement for its own row count plus headroom', () {
      final memory = RowSizeMemory()
        ..record(10000)
        ..record(10000);
      expect(memory.hint, nextRowHint(10000));
      expect(memory.hint, greaterThan(10000));
    });

    test('settles at the small end of a statement that swings', () {
      final memory = RowSizeMemory()..record(8000);
      for (var i = 0; i < 4; i++) {
        memory.record(50);
        expect(memory.hint, nextRowHint(50));
        memory.record(8000);
        expect(memory.hint, nextRowHint(50));
      }
    });
  });

  group('Database result buffer sizing', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('resqlite_presize_');
      db = await Database.open('${tempDir.path}/test.db');
      await db.execute(
        'CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<void> seed(int rows) async {
      const chunk = 500;
      for (var start = 0; start < rows; start += chunk) {
        final end = start + chunk < rows ? start + chunk : rows;
        await db.executeBatch('INSERT INTO items(name) VALUES (?)', [
          for (var r = start; r < end; r++) ['item $r'],
        ]);
      }
    }

    test(
      'a statement whose row count swings returns exactly its rows',
      () async {
        await seed(4000);
        const sql = 'SELECT * FROM items LIMIT ?';
        for (var round = 0; round < 4; round++) {
          for (final limit in [4000, 1, 900, 4000, 50]) {
            final rows = await db.select(sql, [limit]);
            expect(rows.length, limit);
            expect(rows.first['name'], 'item 0');
            expect(rows.last['name'], 'item ${limit - 1}');
          }
        }
      },
    );

    test('a result that outgrows its hint still returns every row', () async {
      const sql = 'SELECT * FROM items';
      // Establish a hint well under what the table will hold, then let the
      // result outgrow it repeatedly so the buffer has to fall back to
      // doubling on top of the hinted size.
      await seed(initialResultRows + 10);
      expect((await db.select(sql)).length, initialResultRows + 10);
      expect((await db.select(sql)).length, initialResultRows + 10);

      var total = initialResultRows + 10;
      for (final added in [500, 2000, 6000]) {
        await seed(added);
        total += added;
        final rows = await db.select(sql);
        expect(rows.length, total);
        expect(rows.last['id'], total);
      }
    });

    test('a shrinking result never returns stale rows', () async {
      await seed(5000);
      const sql = 'SELECT * FROM items';
      expect((await db.select(sql)).length, 5000);
      expect((await db.select(sql)).length, 5000);

      await db.execute('DELETE FROM items WHERE id > 12');
      final rows = await db.select(sql);
      expect(rows.length, 12);
      expect(rows.last['name'], 'item 11');
    });
  });
}
