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
///
/// [EXP-264](../experiments/264-initial-alloc-size-memory.md) added the other
/// end of the same buffer — the initial allocation, sized down for a statement
/// that keeps returning few rows — so the same "a wrong answer may cost time,
/// never rows" contract is gated here for both.
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/query_decoder.dart'
    show
        RowSizeMemory,
        grownSlots,
        initialResultRows,
        initialRowsFor,
        initialSlotRows,
        nextRowHint;
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

  // [EXP-264] adds the initial-allocation end of the same memory. Its risk is
  // the mirror image of the growth hint's: sizing the *first* buffer too small
  // costs doublings, so it takes the largest row count ever seen and can only
  // ever shrink the allocation below the fixed default.
  group('initialRowsFor', () {
    test('never exceeds the fixed default, however large the result', () {
      for (final rows in [initialResultRows, 300, 10000, 1 << 30]) {
        expect(initialRowsFor(rows), initialResultRows);
      }
    });

    test('always leaves room for at least one row', () {
      expect(initialRowsFor(0), 1);
      expect(initialRowsFor(-1), 1);
    });

    test('sizes a small result for itself plus headroom', () {
      expect(initialRowsFor(20), nextRowHint(20));
      expect(initialRowsFor(20), greaterThan(20));
      expect(initialRowsFor(20), lessThan(initialResultRows));
    });
  });

  group('RowSizeMemory.initialRows', () {
    test('has no opinion until it has seen two executions', () {
      final memory = RowSizeMemory();
      expect(initialSlotRows(0, memory), initialResultRows);
      memory.record(1);
      expect(initialSlotRows(0, memory), initialResultRows);
      memory.record(1);
      expect(initialSlotRows(0, memory), lessThan(initialResultRows));
    });

    test('takes the high-water mark, where the growth hint takes the low', () {
      final memory = RowSizeMemory()
        ..record(1)
        ..record(40);
      expect(memory.hint, nextRowHint(1));
      expect(memory.initialRows, nextRowHint(40));
    });

    // The failure a sliding window cannot avoid: the two executions before a
    // large one are both small, so a window of two sizes the large result from
    // a tiny buffer. A high-water mark is raised once and never falls back.
    test('one large result disables the shrink for good', () {
      final memory = RowSizeMemory()
        ..record(20)
        ..record(20);
      expect(initialSlotRows(0, memory), nextRowHint(20));
      memory.record(8000);
      for (var i = 0; i < 8; i++) {
        memory.record(20);
        expect(initialSlotRows(0, memory), initialResultRows);
      }
    });

    test('a statement that swings keeps the full default allocation', () {
      final memory = RowSizeMemory()..record(8000);
      for (var i = 0; i < 4; i++) {
        memory.record(50);
        expect(initialSlotRows(0, memory), initialResultRows);
        memory.record(8000);
        expect(initialSlotRows(0, memory), initialResultRows);
      }
    });

    test('a stable small statement settles below the default', () {
      final memory = RowSizeMemory();
      for (var i = 0; i < 4; i++) {
        memory.record(1);
      }
      expect(initialSlotRows(0, memory), nextRowHint(1));
    });
  });

  // A reader worker sees only a sample of a statement's executions, and is
  // destroyed outright when it decodes a result over `sacrificeSlotThreshold`,
  // so its own high-water mark both lags and resets. The pool's — taken on the
  // main isolate, which sees every execution and outlives every worker — must
  // therefore win outright over any local memory.
  group('initialSlotRows precedence', () {
    test("the caller's hint wins over a local memory that disagrees", () {
      final localSaysTiny = RowSizeMemory()
        ..record(1)
        ..record(1);
      expect(
        initialSlotRows(initialResultRows, localSaysTiny),
        initialResultRows,
      );
      expect(initialSlotRows(40, localSaysTiny), 40);
    });

    test('a local memory is consulted only when the caller has no opinion', () {
      final local = RowSizeMemory()
        ..record(8)
        ..record(8);
      expect(initialSlotRows(0, local), nextRowHint(8));
      // A reader that is handed no hint and no local memory (the pool's first
      // execution of a SQL) falls back to the fixed default.
      expect(initialSlotRows(0, null), initialResultRows);
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
        const sql = 'SELECT * FROM items ORDER BY id LIMIT ?';
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
      const sql = 'SELECT * FROM items ORDER BY id';
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

    // [EXP-264]: the initial allocation is sized down only after a statement
    // has twice returned few rows, so the case that has to hold is the jump
    // back up — a tiny first buffer that then has to hold thousands of rows.
    test(
      'a statement that jumps from tiny to large still returns every row',
      () async {
        await seed(5000);
        const sql = 'SELECT * FROM items ORDER BY id LIMIT ?';
        for (var round = 0; round < 3; round++) {
          for (var i = 0; i < 6; i++) {
            expect((await db.select(sql, [1])).length, 1);
          }
          final rows = await db.select(sql, [5000]);
          expect(rows.length, 5000);
          expect(rows.first['name'], 'item 0');
          expect(rows.last['name'], 'item 4999');
        }
      },
    );

    test('an empty result decodes and then grows correctly', () async {
      const sql = 'SELECT * FROM items ORDER BY id';
      for (var i = 0; i < 6; i++) {
        expect((await db.select(sql)).length, 0);
      }
      await seed(700);
      final rows = await db.select(sql);
      expect(rows.length, 700);
      expect(rows.last['name'], 'item 699');
    });

    test('a shrinking result never returns stale rows', () async {
      await seed(5000);
      const sql = 'SELECT * FROM items ORDER BY id';
      expect((await db.select(sql)).length, 5000);
      expect((await db.select(sql)).length, 5000);

      await db.execute('DELETE FROM items WHERE id > 12');
      final rows = await db.select(sql);
      expect(rows.length, 12);
      expect(rows.last['name'], 'item 11');
    });
  });
}
