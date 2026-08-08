/// Routing and correctness for the main-isolate inline read path
/// ([EXP-265](../experiments/265-inline-main-isolate-select.md)).
///
/// A `select()` returns the same result whichever isolate ran it, which is what
/// makes the optimization safe and also what makes it invisible — so these tests
/// read `ReaderPool.inlineSelectTotal` / `inlineAbortTotal` to assert the route,
/// and assert the rows separately.
///
/// The pools here are spawned directly rather than taken from the [Database],
/// which is how `reader_pool_test.dart` reaches pool internals too.
import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/reader/read_worker.dart' show inlineRowMax;
import 'package:resqlite/src/reader/reader_pool.dart';
import 'package:test/test.dart';

Future<void> _seed(Database db, int count) async {
  await db.execute('''
    CREATE TABLE items(
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      note TEXT NOT NULL,
      value REAL NOT NULL
    )
  ''');
  await db.executeBatch(
    'INSERT INTO items(name, note, value) VALUES (?, ?, ?)',
    List.generate(count, (i) => ['item_$i', 'note for item $i', i * 1.5]),
  );
}

void main() {
  group('inline main-isolate select', () {
    late Directory tempDir;
    late Database db;
    late ReaderPool pool;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('resqlite_inline_test_');
      db = await Database.open('${tempDir.path}/test.db');
      pool = await ReaderPool.spawn(db.handle.address, 2);
    });

    tearDown(() async {
      await pool.close();
      await db.close();
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } on PathNotFoundException {
          // ignore
        }
      }
    });

    // -------------------------------------------------------------------
    // Routing
    // -------------------------------------------------------------------

    test('a statement is watched twice before it runs inline', () async {
      await _seed(db, 100);
      const sql = 'SELECT * FROM items WHERE id = ?';

      await pool.select(sql, [3]);
      expect(pool.inlineSelectTotal, 0, reason: 'one observation is not two');
      await pool.select(sql, [3]);
      expect(pool.inlineSelectTotal, 0);

      await pool.select(sql, [3]);
      expect(pool.inlineSelectTotal, 1);
    });

    test('a large statement never runs inline', () async {
      await _seed(db, 500);
      const sql = 'SELECT * FROM items';

      for (var i = 0; i < 5; i++) {
        expect(await pool.select(sql), hasLength(500));
      }
      expect(pool.inlineSelectTotal, 0);
      expect(pool.inlineAbortTotal, 0);
    });

    test('the row cap is the boundary, not an approximation', () async {
      await _seed(db, 500);
      const sql = 'SELECT * FROM items LIMIT ?';

      // Arm at the cap exactly: eligible, and the decode reaches the last
      // allowed row without tripping.
      for (var i = 0; i < 3; i++) {
        expect(await pool.select(sql, [inlineRowMax]), hasLength(inlineRowMax));
      }
      expect(pool.inlineSelectTotal, greaterThan(0));
      expect(pool.inlineAbortTotal, 0);

      // One row past it, on the same statement, is handed back.
      expect(await pool.select(sql, [inlineRowMax + 1]), hasLength(inlineRowMax + 1));
      expect(pool.inlineAbortTotal, 1);
    });

    test('a statement that outgrows the cap gives up inline for good', () async {
      await _seed(db, 500);
      const sql = 'SELECT * FROM items LIMIT ?';

      for (var i = 0; i < 3; i++) {
        await pool.select(sql, [1]);
      }
      expect(pool.inlineSelectTotal, greaterThan(0));

      // Every row survives the abort — the fallback re-runs from the start
      // rather than resuming a half-decoded result.
      expect(await pool.select(sql, [400]), hasLength(400));
      expect(pool.inlineAbortTotal, 1);

      // The high-water mark now exceeds the cap, so the small leg does not
      // re-arm it and the abort is paid once per statement, not per swing.
      final inlineBefore = pool.inlineSelectTotal;
      for (var i = 0; i < 5; i++) {
        await pool.select(sql, [1]);
      }
      expect(pool.inlineSelectTotal, inlineBefore);
      expect(pool.inlineAbortTotal, 1);
    });

    // -------------------------------------------------------------------
    // The abandoned statement
    // -------------------------------------------------------------------

    test('an aborted inline read does not pin the connection snapshot', () async {
      await _seed(db, 500);
      const swinging = 'SELECT * FROM items LIMIT ?';
      for (var i = 0; i < 3; i++) {
        await pool.select(swinging, [1]);
      }
      expect(await pool.select(swinging, [400]), hasLength(400));
      expect(pool.inlineAbortTotal, 1);

      // Written after the abort. A statement abandoned mid-iteration holds its
      // connection's read transaction open, and every later read on that
      // connection would then be served from the pre-write snapshot — so the
      // third execution below, the first to run inline, is the one that fails
      // if the abort path forgets to reset.
      await db.execute(
        'INSERT INTO items(id, name, note, value) VALUES (?, ?, ?, ?)',
        [90001, 'after', 'written after the abort', 1.0],
      );

      const point = 'SELECT name FROM items WHERE id = 90001';
      for (var i = 0; i < 3; i++) {
        final rows = await pool.select(point);
        expect(rows, hasLength(1), reason: 'execution $i saw a stale snapshot');
        expect(rows.first['name'], 'after');
      }
      expect(pool.inlineSelectTotal, greaterThan(0));
    });

    // -------------------------------------------------------------------
    // Values decode identically on either route
    // -------------------------------------------------------------------

    test('inline results carry the same values as worker results', () async {
      await db.execute('''
        CREATE TABLE cells(
          id INTEGER PRIMARY KEY,
          i INTEGER, r REAL, ascii TEXT, unicode TEXT, b BLOB, n TEXT
        )
      ''');
      final blob = Uint8List.fromList(List.generate(300, (i) => i % 256));
      await db.execute(
        'INSERT INTO cells(id, i, r, ascii, unicode, b, n) '
        'VALUES (1, ?, ?, ?, ?, ?, NULL)',
        [-42, 1.5, 'plain ascii', 'héllo 世界 🎉', blob],
      );

      const sql = 'SELECT * FROM cells WHERE id = 1';
      final fromWorker = await pool.select(sql);
      await pool.select(sql);
      final beforeInline = pool.inlineSelectTotal;
      final fromMain = await pool.select(sql);
      expect(pool.inlineSelectTotal, beforeInline + 1);

      for (final row in [fromWorker.first, fromMain.first]) {
        expect(row['i'], -42);
        expect(row['r'], 1.5);
        expect(row['ascii'], 'plain ascii');
        expect(row['unicode'], 'héllo 世界 🎉');
        expect(row['b'], isA<Uint8List>());
        expect(row['b'], blob);
        expect(row['n'], isNull);
      }
    });

    test('a blob past the transfer threshold decodes inline', () async {
      // Above `BlobTransfer.cellThreshold`, where the worker path wraps the
      // cell in TransferableTypedData for the hop. Inline has no hop, so it
      // must produce the Uint8List directly rather than leave a wrapper for a
      // materialize step that no longer runs.
      await db.execute('CREATE TABLE big(id INTEGER PRIMARY KEY, b BLOB)');
      final blob = Uint8List.fromList(
        List.generate(512 * 1024, (i) => (i * 7) % 256),
      );
      await db.execute('INSERT INTO big(id, b) VALUES (1, ?)', [blob]);

      const sql = 'SELECT b FROM big WHERE id = 1';
      for (var i = 0; i < 3; i++) {
        final rows = await pool.select(sql);
        expect(rows.first['b'], isA<Uint8List>());
        expect(rows.first['b'], blob);
      }
      expect(pool.inlineSelectTotal, greaterThan(0));
    });

    test('the shipped Database.select path returns inline results', () async {
      // The pools above are spawned by hand; this one is the pool
      // `Database.open` built, on the reader connection it reserved.
      await _seed(db, 100);
      const sql = 'SELECT id, name FROM items WHERE id = ?';
      for (var i = 0; i < 5; i++) {
        final rows = await db.select(sql, [7]);
        expect(rows, hasLength(1));
        // `id` is 1-based and the generated names are 0-based.
        expect(rows.first['name'], 'item_6');
      }
    });

    test('a query error still throws, whatever the pool remembers', () async {
      await _seed(db, 10);
      // A statement that fails to prepare is never recorded, so it can never
      // become inline-eligible — the guard is that repetition does not change
      // the exception.
      for (var i = 0; i < 3; i++) {
        expect(
          () => pool.select('SELECT * FROM no_such_table'),
          throwsA(isA<ResqliteQueryException>()),
        );
      }
    });
  });
}
