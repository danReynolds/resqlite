import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

void main() {
  group('QueryCache', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('resqlite_cache_test_');
      db = await Database.open('${tempDir.path}/test.db');
      await db.execute(
        'CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT, active INTEGER)',
      );
      await db.executeBatch(
        'INSERT INTO users(name, active) VALUES (?, ?)',
        [
          ['Alice', 1],
          ['Bob', 1],
          ['Carol', 0],
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

    // -----------------------------------------------------------------
    // Cache hit behavior
    // -----------------------------------------------------------------

    test('repeated select returns same result from cache', () async {
      final r1 = await db.select('SELECT * FROM users WHERE active = ?', [1]);
      final r2 = await db.select('SELECT * FROM users WHERE active = ?', [1]);

      // Same object identity — served from cache, not re-queried.
      expect(identical(r1, r2), isTrue);
      expect(r1, hasLength(2));
    });

    test('different params are different cache entries', () async {
      final active = await db.select(
        'SELECT * FROM users WHERE active = ?',
        [1],
      );
      final inactive = await db.select(
        'SELECT * FROM users WHERE active = ?',
        [0],
      );

      expect(active, hasLength(2));
      expect(inactive, hasLength(1));
      expect(identical(active, inactive), isFalse);
    });

    // -----------------------------------------------------------------
    // Invalidation
    // -----------------------------------------------------------------

    test('cache is invalidated after write to dependent table', () async {
      final r1 = await db.select('SELECT * FROM users WHERE active = ?', [1]);
      expect(r1, hasLength(2));

      await db.execute(
        'INSERT INTO users(name, active) VALUES (?, ?)',
        ['Dave', 1],
      );

      final r2 = await db.select('SELECT * FROM users WHERE active = ?', [1]);
      expect(r2, hasLength(3));
      // Different object — cache was invalidated, re-queried.
      expect(identical(r1, r2), isFalse);
    });

    test('write to unrelated table does not invalidate cache', () async {
      await db.execute('CREATE TABLE products(id INTEGER PRIMARY KEY, name TEXT)');

      final r1 = await db.select('SELECT * FROM users WHERE active = ?', [1]);

      // Write to products — should not affect users cache.
      await db.execute('INSERT INTO products(name) VALUES (?)', ['Widget']);

      final r2 = await db.select('SELECT * FROM users WHERE active = ?', [1]);
      // Same object — cache was not invalidated.
      expect(identical(r1, r2), isTrue);
    });

    test('executeBatch invalidates cache', () async {
      final r1 = await db.select('SELECT * FROM users');
      expect(r1, hasLength(3));

      await db.executeBatch(
        'INSERT INTO users(name, active) VALUES (?, ?)',
        [
          ['Dave', 1],
          ['Eve', 0],
        ],
      );

      final r2 = await db.select('SELECT * FROM users');
      expect(r2, hasLength(5));
    });

    test('transaction commit invalidates cache', () async {
      final r1 = await db.select('SELECT count(*) as c FROM users');
      expect(r1[0]['c'], 3);

      await db.transaction((tx) async {
        await tx.execute(
          'INSERT INTO users(name, active) VALUES (?, ?)',
          ['Dave', 1],
        );
      });

      final r2 = await db.select('SELECT count(*) as c FROM users');
      expect(r2[0]['c'], 4);
    });

    test('transaction rollback does not invalidate cache', () async {
      final r1 = await db.select('SELECT count(*) as c FROM users');
      expect(r1[0]['c'], 3);

      try {
        await db.transaction((tx) async {
          await tx.execute(
            'INSERT INTO users(name, active) VALUES (?, ?)',
            ['Dave', 1],
          );
          throw StateError('rollback');
        });
      } on StateError {
        // expected
      }

      final r2 = await db.select('SELECT count(*) as c FROM users');
      // Same cached result — rollback didn't dirty any tables.
      expect(identical(r1, r2), isTrue);
      expect(r2[0]['c'], 3);
    });

    // -----------------------------------------------------------------
    // Stream + cache interaction
    // -----------------------------------------------------------------

    test('stream populates cache that select can hit', () async {
      // Start a stream — this runs selectWithDeps and caches the result.
      final stream = db.stream('SELECT * FROM users WHERE active = ?', [1]);
      final firstEmission = await stream.first;
      expect(firstEmission, hasLength(2));

      // select() should hit the cache (pinned by the stream).
      final selected = await db.select(
        'SELECT * FROM users WHERE active = ?',
        [1],
      );
      expect(selected, hasLength(2));
    });

    test('select populates cache that stream can use', () async {
      // select() first — populates cache.
      final selected = await db.select(
        'SELECT * FROM users WHERE active = ?',
        [1],
      );
      expect(selected, hasLength(2));

      // Stream should find the cached result and emit immediately.
      final stream = db.stream('SELECT * FROM users WHERE active = ?', [1]);
      final firstEmission = await stream.first;
      expect(firstEmission, hasLength(2));
    });

    // -----------------------------------------------------------------
    // Large results are not cached
    // -----------------------------------------------------------------

    test('large results are not cached', () async {
      // Insert enough rows to exceed maxCacheableRows (50).
      await db.executeBatch(
        'INSERT INTO users(name, active) VALUES (?, ?)',
        List.generate(60, (i) => ['user_$i', 1]),
      );

      final r1 = await db.select('SELECT * FROM users');
      expect(r1.length, greaterThan(50));

      final r2 = await db.select('SELECT * FROM users');
      // Different objects — not cached due to size.
      expect(identical(r1, r2), isFalse);
      expect(r1.length, r2.length);
    });

    // -----------------------------------------------------------------
    // selectBytes is not affected by cache
    // -----------------------------------------------------------------

    test('selectBytes bypasses cache', () async {
      // select populates cache.
      await db.select('SELECT * FROM users WHERE active = ?', [1]);

      // selectBytes should still work (goes to pool directly).
      final bytes = await db.selectBytes(
        'SELECT * FROM users WHERE active = ?',
        [1],
      );
      expect(bytes.isNotEmpty, isTrue);
    });
  });
}
