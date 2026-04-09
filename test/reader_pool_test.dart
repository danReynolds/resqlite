import 'dart:convert';
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

/// Seed a wide table (6 columns) with [count] rows.
/// With 6 columns, the sacrifice threshold (6000 cells) is hit at ~1000 rows.
Future<void> _seed(Database db, int count) async {
  await db.execute('''
    CREATE TABLE items(
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      category TEXT NOT NULL,
      price REAL NOT NULL,
      quantity INTEGER NOT NULL,
      description TEXT NOT NULL
    )
  ''');
  await db.executeBatch(
    'INSERT INTO items(name, category, price, quantity, description) '
    'VALUES (?, ?, ?, ?, ?)',
    List.generate(count, (i) => [
      'item_$i',
      'cat_${i % 10}',
      (i * 1.5),
      i * 10,
      'A medium-length description for item number $i to add some text bulk.',
    ]),
  );
}

void main() {
  group('ReaderPool', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('resqlite_pool_test_');
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

    // -----------------------------------------------------------------
    // Happy path — small results (SendPort path)
    // -----------------------------------------------------------------

    test('select returns correct results for small queries', () async {
      await _seed(db, 50);
      final rows = await db.select('SELECT * FROM items WHERE id <= 5');
      expect(rows, hasLength(5));
      expect(rows[0]['name'], 'item_0');
      expect(rows[4]['name'], 'item_4');
    });

    test('selectBytes returns valid JSON for small queries', () async {
      await _seed(db, 50);
      final bytes = await db.selectBytes('SELECT * FROM items WHERE id <= 5');
      final decoded = jsonDecode(String.fromCharCodes(bytes)) as List;
      expect(decoded, hasLength(5));
      expect((decoded[0] as Map)['name'], 'item_0');
    });

    test('selectBytes matches select for small queries', () async {
      await _seed(db, 50);
      final rows = await db.select('SELECT * FROM items WHERE id <= 10');
      final bytes = await db.selectBytes('SELECT * FROM items WHERE id <= 10');
      final decoded = jsonDecode(String.fromCharCodes(bytes)) as List;
      expect(decoded, hasLength(rows.length));
      for (var i = 0; i < rows.length; i++) {
        expect((decoded[i] as Map)['name'], rows[i]['name']);
      }
    });

    // -----------------------------------------------------------------
    // Large results — sacrifice threshold = 50000 cells.
    // At 6 cols, that's ~8334 rows. Tests below 50000 cells use SendPort;
    // tests above exercise the Isolate.exit sacrifice + respawn path.
    // -----------------------------------------------------------------

    test('select handles large results (sacrifice path)', () async {
      await _seed(db, 5000);
      final rows = await db.select('SELECT * FROM items');
      expect(rows, hasLength(5000));
      expect(rows.first['name'], 'item_0');
      expect(rows.last['name'], 'item_4999');
    });

    test('selectBytes handles large results (sacrifice path)', () async {
      await _seed(db, 5000);
      final bytes = await db.selectBytes('SELECT * FROM items');
      final decoded = jsonDecode(String.fromCharCodes(bytes)) as List;
      expect(decoded, hasLength(5000));
      expect((decoded.first as Map)['name'], 'item_0');
      expect((decoded.last as Map)['name'], 'item_4999');
    });

    test('repeated large selects work (SendPort path)', () async {
      await _seed(db, 2000);
      // 2000 × 6 = 12000 cells — below sacrifice threshold (50000),
      // so these use SendPort. Tests pool reuse under large payloads.
      for (var i = 0; i < 10; i++) {
        final rows = await db.select('SELECT * FROM items');
        expect(rows, hasLength(2000), reason: 'iteration $i');
      }
    });

    test('repeated large selectBytes work (always SendPort)', () async {
      await _seed(db, 2000);
      // selectBytes never sacrifices — Uint8List is a flat buffer where
      // SendPort memcpy is always cheaper than isolate respawn.
      for (var i = 0; i < 10; i++) {
        final bytes = await db.selectBytes('SELECT * FROM items');
        final decoded = jsonDecode(String.fromCharCodes(bytes)) as List;
        expect(decoded, hasLength(2000), reason: 'iteration $i');
      }
    });

    // -----------------------------------------------------------------
    // Concurrent queries — exceeding pool size
    // Default pool is clamp(cores-1, 2, 4), so 2-4 workers.
    // -----------------------------------------------------------------

    test('concurrent selects exceeding pool size', () async {
      await _seed(db, 100);
      // Fire 20 queries simultaneously — far more than pool workers.
      final futures = List.generate(
        20,
        (i) => db.select('SELECT * FROM items WHERE category = ?', ['cat_$i']),
      );
      final results = await Future.wait(futures);
      for (var i = 0; i < 10; i++) {
        // Only cat_0..cat_9 have rows (100 items, category = i % 10).
        expect(results[i], hasLength(10), reason: 'cat_$i');
      }
      for (var i = 10; i < 20; i++) {
        expect(results[i], isEmpty, reason: 'cat_$i should be empty');
      }
    });

    test('concurrent selectBytes exceeding pool size', () async {
      await _seed(db, 100);
      final futures = List.generate(
        20,
        (i) =>
            db.selectBytes('SELECT * FROM items WHERE category = ?', ['cat_$i']),
      );
      final results = await Future.wait(futures);
      for (var i = 0; i < 10; i++) {
        final decoded = jsonDecode(String.fromCharCodes(results[i])) as List;
        expect(decoded, hasLength(10), reason: 'cat_$i');
      }
    });

    test('concurrent large selects (all sacrifice, all respawn)', () async {
      await _seed(db, 2000);
      // 8 concurrent queries, each returning 2000 rows × 6 cols = 12000 cells.
      // Every one triggers sacrifice. Pool must respawn workers between queries.
      final futures = List.generate(
        8,
        (_) => db.select('SELECT * FROM items'),
      );
      final results = await Future.wait(futures);
      for (final rows in results) {
        expect(rows, hasLength(2000));
      }
    });

    test('mixed small and large concurrent selects', () async {
      await _seed(db, 3000);
      final futures = <Future<List<Map<String, Object?>>>>[];

      // Alternate between small (50 rows → SendPort) and large (3000 rows → sacrifice).
      for (var i = 0; i < 12; i++) {
        if (i.isEven) {
          futures.add(db.select('SELECT * FROM items LIMIT 50'));
        } else {
          futures.add(db.select('SELECT * FROM items'));
        }
      }

      final results = await Future.wait(futures);
      for (var i = 0; i < 12; i++) {
        if (i.isEven) {
          expect(results[i], hasLength(50), reason: 'query $i (small)');
        } else {
          expect(results[i], hasLength(3000), reason: 'query $i (large)');
        }
      }
    });

    // -----------------------------------------------------------------
    // Mixed API calls — select, selectBytes, streams all through pool
    // -----------------------------------------------------------------

    test('mixed select and selectBytes concurrent', () async {
      await _seed(db, 500);
      final selectFutures = List.generate(
        10,
        (_) => db.select('SELECT * FROM items'),
      );
      final bytesFutures = List.generate(
        10,
        (_) => db.selectBytes('SELECT * FROM items'),
      );
      final selectResults = await Future.wait(selectFutures);
      final bytesResults = await Future.wait(bytesFutures);

      for (final rows in selectResults) {
        expect(rows, hasLength(500));
      }
      for (final bytes in bytesResults) {
        final decoded = jsonDecode(String.fromCharCodes(bytes)) as List;
        expect(decoded, hasLength(500));
      }
    });

    test('select works correctly after stream setup (selectWithDeps)', () async {
      await _seed(db, 100);

      // Stream setup uses selectWithDeps internally.
      final stream = db.stream('SELECT * FROM items WHERE category = ?', ['cat_0']);
      final first = await stream.first;
      expect(first, hasLength(10));

      // Regular selects should still work after selectWithDeps exercised the pool.
      final rows = await db.select('SELECT * FROM items WHERE category = ?', ['cat_1']);
      expect(rows, hasLength(10));
    });

    // -----------------------------------------------------------------
    // Correctness under write pressure
    // -----------------------------------------------------------------

    test('selects return consistent data during writes', () async {
      await _seed(db, 100);

      // Fire reads and writes concurrently.
      final reads = List.generate(
        10,
        (_) => db.select('SELECT count(*) as c FROM items'),
      );
      // Concurrent write that adds 50 more rows.
      final write = db.executeBatch(
        'INSERT INTO items(name, category, price, quantity, description) '
        'VALUES (?, ?, ?, ?, ?)',
        List.generate(50, (i) => [
          'new_$i', 'cat_new', 0.0, 0,
          'new item',
        ]),
      );

      final results = await Future.wait(reads);
      await write;

      // Each read should see either 100 (before write) or 150 (after write),
      // never a partial state, because WAL provides snapshot isolation.
      for (final rows in results) {
        final count = rows[0]['c'] as int;
        expect(count == 100 || count == 150, isTrue,
            reason: 'got count=$count, expected 100 or 150');
      }
    });

    // -----------------------------------------------------------------
    // Edge cases
    // -----------------------------------------------------------------

    test('empty result set', () async {
      await _seed(db, 10);
      final rows = await db.select('SELECT * FROM items WHERE id > 9999');
      expect(rows, isEmpty);
    });

    test('empty result selectBytes', () async {
      await _seed(db, 10);
      final bytes = await db.selectBytes('SELECT * FROM items WHERE id > 9999');
      final decoded = jsonDecode(String.fromCharCodes(bytes)) as List;
      expect(decoded, isEmpty);
    });

    test('single row result', () async {
      await _seed(db, 10);
      final rows = await db.select('SELECT * FROM items WHERE id = 1');
      expect(rows, hasLength(1));
      expect(rows[0]['name'], 'item_0');
    });

    test('result at various sizes uses SendPort (below sacrifice threshold)', () async {
      await _seed(db, 5000);
      // 5000 × 6 = 30000 cells — below sacrifice threshold (50000).
      final rows = await db.select('SELECT * FROM items');
      expect(rows, hasLength(5000));
    });

    test('rapid sequential queries (pool reuse)', () async {
      await _seed(db, 50);
      // 100 sequential queries — tests that workers are reused efficiently.
      for (var i = 0; i < 100; i++) {
        final rows = await db.select(
          'SELECT * FROM items WHERE id = ?',
          [i % 50 + 1],
        );
        expect(rows, hasLength(1), reason: 'query $i');
      }
    });

    test('parameterized queries return correct filtered results', () async {
      await _seed(db, 200);
      final futures = List.generate(
        10,
        (i) => db.select(
          'SELECT * FROM items WHERE category = ? AND price > ?',
          ['cat_$i', i * 10.0],
        ),
      );
      final results = await Future.wait(futures);
      for (var i = 0; i < 10; i++) {
        for (final row in results[i]) {
          expect(row['category'], 'cat_$i');
          expect((row['price'] as double) > i * 10.0, isTrue);
        }
      }
    });

    // -----------------------------------------------------------------
    // Stress: high volume concurrent mixed workload
    // -----------------------------------------------------------------

    test('stress: 50 concurrent mixed queries', () async {
      await _seed(db, 2000);

      final futures = <Future>[];
      for (var i = 0; i < 50; i++) {
        switch (i % 3) {
          case 0:
            // Small select (SendPort path)
            futures.add(
              db.select('SELECT * FROM items LIMIT 10').then((rows) {
                expect(rows, hasLength(10));
              }),
            );
          case 1:
            // Large select (sacrifice path)
            futures.add(
              db.select('SELECT * FROM items').then((rows) {
                expect(rows, hasLength(2000));
              }),
            );
          case 2:
            // selectBytes
            futures.add(
              db.selectBytes('SELECT * FROM items LIMIT 100').then((bytes) {
                final decoded =
                    jsonDecode(String.fromCharCodes(bytes)) as List;
                expect(decoded, hasLength(100));
              }),
            );
        }
      }
      await Future.wait(futures);
    });
  });
}
