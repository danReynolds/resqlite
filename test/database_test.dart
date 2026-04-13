import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

void main() {
  group('Database', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('resqlite_test_');
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

    // ----- Basic lifecycle -----

    test('immediate close is safe and idempotent', () async {
      final openCloseDir = await Directory.systemTemp.createTemp(
        'resqlite_open_close_',
      );

      try {
        for (var i = 0; i < 5; i++) {
          final openCloseDb = await Database.open(
            '${openCloseDir.path}/test_$i.db',
          );

          await openCloseDb.close();
          await openCloseDb.close();

          expect(
            () => openCloseDb.select('SELECT 1'),
            throwsA(isA<ResqliteConnectionException>()),
            reason: 'iteration $i',
          );
        }
      } finally {
        if (await openCloseDir.exists()) {
          await openCloseDir.delete(recursive: true);
        }
      }
    });

    // ----- Execute -----

    test('execute INSERT returns affected rows and last insert ID', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );
      final r1 = await db.execute(
        'INSERT INTO t(name) VALUES (?)',
        ['hello'],
      );
      expect(r1.affectedRows, 1);
      expect(r1.lastInsertId, 1);

      final r2 = await db.execute(
        'INSERT INTO t(name) VALUES (?)',
        ['world'],
      );
      expect(r2.affectedRows, 1);
      expect(r2.lastInsertId, 2);
    });

    test('execute UPDATE returns affected rows', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );
      await db.execute('INSERT INTO t(name) VALUES (?)', ['alice']);
      await db.execute('INSERT INTO t(name) VALUES (?)', ['bob']);
      await db.execute('INSERT INTO t(name) VALUES (?)', ['charlie']);

      final result = await db.execute(
        'UPDATE t SET name = ? WHERE id > ?',
        ['updated', 1],
      );
      expect(result.affectedRows, 2);
    });

    test('execute DELETE returns affected rows', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );
      await db.execute('INSERT INTO t(name) VALUES (?)', ['alice']);
      await db.execute('INSERT INTO t(name) VALUES (?)', ['bob']);
      await db.execute('INSERT INTO t(name) VALUES (?)', ['charlie']);

      final result = await db.execute('DELETE FROM t WHERE id <= ?', [2]);
      expect(result.affectedRows, 2);

      final rows = await db.select('SELECT * FROM t');
      expect(rows, hasLength(1));
      expect(rows[0]['name'], 'charlie');
    });

    test('execute DDL returns zero affected rows', () async {
      final result = await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY)',
      );
      expect(result.affectedRows, 0);
    });

    test('readers see committed writes', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );
      await db.execute('INSERT INTO t(name) VALUES (?)', ['alice']);

      // select() uses reader pool — should see the committed write.
      final rows = await db.select('SELECT * FROM t');
      expect(rows, hasLength(1));
      expect(rows[0]['name'], 'alice');
    });

    test('execute with invalid SQL throws', () async {
      expect(
        () => db.execute('INSERT INTO nonexistent(x) VALUES (?)', [1]),
        throwsA(isA<ResqliteQueryException>()),
      );
    });

    // ----- Select -----

    test('execute + select', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );
      await db.execute('INSERT INTO t(name) VALUES (?)', ['hello']);
      await db.execute('INSERT INTO t(name) VALUES (?)', ['world']);

      final rows = await db.select('SELECT * FROM t ORDER BY id');
      expect(rows, hasLength(2));
      expect(rows[0]['name'], 'hello');
      expect(rows[1]['name'], 'world');
    });

    test('select with all column types', () async {
      await db.execute('''
        CREATE TABLE types(
          id INTEGER PRIMARY KEY,
          int_val INTEGER,
          real_val REAL,
          text_val TEXT,
          blob_val BLOB,
          null_val TEXT
        )
      ''');
      await db.execute(
        'INSERT INTO types(int_val, real_val, text_val, blob_val, null_val) '
        'VALUES (?, ?, ?, ?, ?)',
        [42, 3.14, 'hello', Uint8List.fromList([1, 2, 3]), null],
      );

      final rows = await db.select('SELECT * FROM types');
      expect(rows, hasLength(1));
      final row = rows[0];
      expect(row['id'], 1);
      expect(row['int_val'], 42);
      expect(row['real_val'], closeTo(3.14, 0.001));
      expect(row['text_val'], 'hello');
      expect(row['blob_val'], [1, 2, 3]);
      expect(row['null_val'], isNull);
    });

    test('select empty result', () async {
      await db.execute('CREATE TABLE t(id INTEGER PRIMARY KEY)');
      final rows = await db.select('SELECT * FROM t');
      expect(rows, isEmpty);
    });

    test('select with unicode strings', () async {
      await db.execute('CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT)');
      await db.execute('INSERT INTO t(name) VALUES (?)', ['日本語']);
      await db.execute('INSERT INTO t(name) VALUES (?)', ['emoji 🎉']);
      await db.execute('INSERT INTO t(name) VALUES (?)', ['مرحبا']);

      final rows = await db.select('SELECT name FROM t ORDER BY id');
      expect(rows[0]['name'], '日本語');
      expect(rows[1]['name'], 'emoji 🎉');
      expect(rows[2]['name'], 'مرحبا');
    });

    test('select with parameterized query', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT, active INTEGER)',
      );
      await db.execute(
        'INSERT INTO t(name, active) VALUES (?, ?)',
        ['alice', 1],
      );
      await db.execute(
        'INSERT INTO t(name, active) VALUES (?, ?)',
        ['bob', 0],
      );
      await db.execute(
        'INSERT INTO t(name, active) VALUES (?, ?)',
        ['charlie', 1],
      );

      final rows = await db.select(
        'SELECT name FROM t WHERE active = ? ORDER BY name',
        [1],
      );
      expect(rows, hasLength(2));
      expect(rows[0]['name'], 'alice');
      expect(rows[1]['name'], 'charlie');
    });

    test('repeated cached selects preserve text and blob parameters', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, tag TEXT, payload BLOB)',
      );
      final blob = Uint8List.fromList(List.generate(32, (i) => i));
      final otherBlob = Uint8List.fromList(List.generate(32, (i) => 255 - i));
      await db.execute(
        'INSERT INTO t(tag, payload) VALUES (?, ?)',
        ['target', blob],
      );
      await db.execute(
        'INSERT INTO t(tag, payload) VALUES (?, ?)',
        ['other', otherBlob],
      );

      const sql = 'SELECT tag FROM t WHERE tag = ? AND payload = ?';
      for (var i = 0; i < 10; i++) {
        final rows = await db.select(sql, ['target', blob]);
        expect(rows, hasLength(1), reason: 'iteration $i');
        expect(rows[0]['tag'], 'target');
      }
    });

    test('row implements Map interface', () async {
      await db.execute('CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT)');
      await db.execute('INSERT INTO t(name) VALUES (?)', ['test']);

      final rows = await db.select('SELECT * FROM t');
      final row = rows[0];

      expect(row.containsKey('id'), isTrue);
      expect(row.containsKey('name'), isTrue);
      expect(row.containsKey('nonexistent'), isFalse);
      expect(row.containsValue('test'), isTrue);
      expect(row.containsValue('missing'), isFalse);
      expect(row.keys.toList(), ['id', 'name']);
      expect(row.values.toList(), [1, 'test']);
      expect(row.entries.length, 2);
      final entries = row.entries.toList();
      expect(entries, hasLength(2));
      expect(entries[0].key, 'id');
      expect(entries[0].value, 1);
      expect(entries[1].key, 'name');
      expect(entries[1].value, 'test');

      final seen = <String, Object?>{};
      row.forEach((key, value) {
        seen[key] = value;
      });
      expect(seen, {'id': 1, 'name': 'test'});
      expect(Map<String, Object?>.from(row), {'id': 1, 'name': 'test'});
    });

    // ----- selectBytes -----

    test('selectBytes returns valid JSON', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT, value REAL)',
      );
      await db.execute(
        'INSERT INTO t(name, value) VALUES (?, ?)',
        ['alpha', 1.5],
      );
      await db.execute(
        'INSERT INTO t(name, value) VALUES (?, ?)',
        ['beta', 2.5],
      );

      final bytes = await db.selectBytes('SELECT * FROM t ORDER BY id');
      final decoded = jsonDecode(utf8.decode(bytes)) as List<dynamic>;
      expect(decoded, hasLength(2));
      expect((decoded[0] as Map)['name'], 'alpha');
      expect((decoded[1] as Map)['name'], 'beta');
    });

    test('selectBytes empty result', () async {
      await db.execute('CREATE TABLE t(id INTEGER PRIMARY KEY)');
      final bytes = await db.selectBytes('SELECT * FROM t');
      expect(utf8.decode(bytes), '[]');
    });

    test('selectBytes with JSON special characters', () async {
      await db.execute('CREATE TABLE t(id INTEGER PRIMARY KEY, val TEXT)');
      await db.execute('INSERT INTO t(val) VALUES (?)', [
        'quote"slash\\newline\ntab\t',
      ]);

      final bytes = await db.selectBytes('SELECT val FROM t');
      final decoded = jsonDecode(utf8.decode(bytes)) as List<dynamic>;
      expect(
        (decoded[0] as Map)['val'],
        'quote"slash\\newline\ntab\t',
      );
    });

    test('selectBytes matches jsonEncode of select', () async {
      await db.execute('''
        CREATE TABLE items(
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL,
          value REAL NOT NULL,
          category TEXT
        )
      ''');
      for (var i = 0; i < 50; i++) {
        await db.execute(
          'INSERT INTO items(name, value, category) VALUES (?, ?, ?)',
          ['item_$i', i * 1.5, i % 3 == 0 ? null : 'cat_${i % 5}'],
        );
      }

      final rows = await db.select('SELECT * FROM items ORDER BY id');
      final bytesFromSelect = utf8.encode(jsonEncode(rows));

      final bytesFromSelectBytes =
          await db.selectBytes('SELECT * FROM items ORDER BY id');

      final fromSelect = jsonDecode(utf8.decode(bytesFromSelect));
      final fromBytes = jsonDecode(utf8.decode(bytesFromSelectBytes));
      expect(fromBytes, equals(fromSelect));
    });

    test('repeated selectBytes preserves text and blob parameters', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, tag TEXT, payload BLOB)',
      );
      final blob = Uint8List.fromList(List.generate(48, (i) => i % 17));
      await db.execute(
        'INSERT INTO t(tag, payload) VALUES (?, ?)',
        ['target', blob],
      );

      const sql = 'SELECT tag FROM t WHERE tag = ? AND payload = ?';
      for (var i = 0; i < 10; i++) {
        final bytes = await db.selectBytes(sql, ['target', blob]);
        final decoded = jsonDecode(utf8.decode(bytes)) as List<dynamic>;
        expect(decoded, hasLength(1), reason: 'iteration $i');
        expect((decoded[0] as Map)['tag'], 'target');
      }
    });

    test('selectBytes encodes blobs as base64', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, data BLOB)',
      );

      // Test various sizes: empty, 1 byte (padding ==), 2 bytes (padding =),
      // 3 bytes (no padding), and a larger payload.
      final cases = <(String, Uint8List, String)>[
        ('empty', Uint8List(0), ''),
        ('1 byte', Uint8List.fromList([0xDE]), '3g=='),
        ('2 bytes', Uint8List.fromList([0xDE, 0xAD]), '3q0='),
        ('3 bytes', Uint8List.fromList([0xDE, 0xAD, 0xBE]), '3q2+'),
        (
          '6 bytes',
          Uint8List.fromList([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x21]),
          'SGVsbG8h',
        ),
      ];

      for (final (label, blob, expectedB64) in cases) {
        await db.execute('DELETE FROM t');
        await db.execute('INSERT INTO t(data) VALUES (?)', [blob]);

        final bytes = await db.selectBytes('SELECT data FROM t');
        final decoded = jsonDecode(utf8.decode(bytes)) as List<dynamic>;
        final value = (decoded[0] as Map)['data'] as String;
        expect(value, expectedB64, reason: label);

        // Round-trip: decode the base64 back and compare to original bytes.
        if (blob.isNotEmpty) {
          expect(base64Decode(value), blob, reason: '$label round-trip');
        }
      }
    });

    // ----- executeBatch -----

    test('executeBatch inserts multiple rows', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );

      await db.executeBatch(
        'INSERT INTO t(name) VALUES (?)',
        [['alice'], ['bob'], ['charlie']],
      );

      final rows = await db.select('SELECT name FROM t ORDER BY id');
      expect(rows, hasLength(3));
      expect(rows[0]['name'], 'alice');
      expect(rows[1]['name'], 'bob');
      expect(rows[2]['name'], 'charlie');
    });

    test('executeBatch with empty list does nothing', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );

      await db.executeBatch('INSERT INTO t(name) VALUES (?)', []);

      final rows = await db.select('SELECT * FROM t');
      expect(rows, isEmpty);
    });

    test('executeBatch with large batch', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, value INTEGER NOT NULL)',
      );

      await db.executeBatch(
        'INSERT INTO t(value) VALUES (?)',
        [for (var i = 0; i < 1000; i++) [i]],
      );

      final rows = await db.select('SELECT COUNT(*) as cnt FROM t');
      expect(rows[0]['cnt'], 1000);
    });

    test('executeBatch with multiple columns', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT NOT NULL, value REAL NOT NULL)',
      );

      await db.executeBatch(
        'INSERT INTO t(name, value) VALUES (?, ?)',
        [
          ['alice', 1.5],
          ['bob', 2.5],
          ['charlie', 3.5],
        ],
      );

      final rows = await db.select('SELECT * FROM t ORDER BY id');
      expect(rows, hasLength(3));
      expect(rows[1]['name'], 'bob');
      expect(rows[1]['value'], closeTo(2.5, 0.001));
    });

    test('executeBatch rolls back on error', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );

      expect(
        () => db.executeBatch(
          'INSERT INTO t(name) VALUES (?)',
          [['alice'], [null], ['charlie']],
        ),
        throwsA(isA<ResqliteQueryException>()),
      );

      final rows = await db.select('SELECT * FROM t');
      expect(rows, isEmpty);
    });

    // ----- Transactions -----

    test('transaction commits on success', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );

      await db.transaction((tx) async {
        await tx.execute('INSERT INTO t(name) VALUES (?)', ['alice']);
        await tx.execute('INSERT INTO t(name) VALUES (?)', ['bob']);
      });

      final rows = await db.select('SELECT name FROM t ORDER BY id');
      expect(rows, hasLength(2));
      expect(rows[0]['name'], 'alice');
      expect(rows[1]['name'], 'bob');
    });

    test('transaction rolls back on error', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );

      expect(
        () => db.transaction((tx) async {
          await tx.execute('INSERT INTO t(name) VALUES (?)', ['alice']);
          throw StateError('intentional error');
        }),
        throwsA(isA<StateError>()),
      );

      final rows = await db.select('SELECT * FROM t');
      expect(rows, isEmpty);
    });

    test('transaction reads see uncommitted writes', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );
      await db.execute('INSERT INTO t(name) VALUES (?)', ['existing']);

      final result = await db.transaction((tx) async {
        await tx.execute('INSERT INTO t(name) VALUES (?)', ['new_row']);
        final rows = await tx.select('SELECT COUNT(*) as cnt FROM t');
        return rows[0]['cnt'] as int;
      });

      expect(result, 2);
    });

    test('transaction returns value', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );

      final lastId = await db.transaction((tx) async {
        final r = await tx.execute(
          'INSERT INTO t(name) VALUES (?)',
          ['alice'],
        );
        return r.lastInsertId;
      });

      expect(lastId, 1);
    });

    test('empty transaction commits cleanly', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );

      await db.transaction((tx) async {
        // No operations.
      });

      // DB should be in clean state.
      final rows = await db.select('SELECT * FROM t');
      expect(rows, isEmpty);
    });

    test('sequential transactions work', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );

      await db.transaction((tx) async {
        await tx.execute('INSERT INTO t(name) VALUES (?)', ['first']);
      });

      await db.transaction((tx) async {
        await tx.execute('INSERT INTO t(name) VALUES (?)', ['second']);
      });

      final rows = await db.select('SELECT name FROM t ORDER BY id');
      expect(rows, hasLength(2));
      expect(rows[0]['name'], 'first');
      expect(rows[1]['name'], 'second');
    });

    test('transaction with multiple tables', () async {
      await db.execute('CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT)');
      await db.execute('CREATE TABLE posts(id INTEGER PRIMARY KEY, user_id INTEGER, title TEXT)');

      await db.transaction((tx) async {
        final r = await tx.execute(
          'INSERT INTO users(name) VALUES (?)',
          ['alice'],
        );
        await tx.execute(
          'INSERT INTO posts(user_id, title) VALUES (?, ?)',
          [r.lastInsertId, 'Hello World'],
        );
      });

      final users = await db.select('SELECT * FROM users');
      final posts = await db.select('SELECT * FROM posts');
      expect(users, hasLength(1));
      expect(posts, hasLength(1));
      expect(posts[0]['user_id'], users[0]['id']);
    });

    test('error mid-transaction rolls back all changes', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );

      expect(
        () => db.transaction((tx) async {
          await tx.execute('INSERT INTO t(name) VALUES (?)', ['alice']);
          await tx.execute('INSERT INTO t(name) VALUES (?)', ['bob']);
          // This should fail — name is NOT NULL.
          await tx.execute('INSERT INTO t(name) VALUES (?)', [null]);
        }),
        throwsA(isA<ResqliteQueryException>()),
      );

      // All three inserts should be rolled back.
      final rows = await db.select('SELECT * FROM t');
      expect(rows, isEmpty);
    });

    // ----- Transaction reads (exercises writer-side decode path) -----

    test('transaction select returns many rows with correct types', () async {
      await db.execute('''
        CREATE TABLE items(
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL,
          price REAL NOT NULL,
          data BLOB
        )
      ''');
      await db.executeBatch(
        'INSERT INTO items(name, price, data) VALUES (?, ?, ?)',
        [for (var i = 0; i < 500; i++) [
          'item_$i', i * 1.5, null,
        ]],
      );

      final rows = await db.transaction((tx) async {
        return await tx.select('SELECT * FROM items ORDER BY id');
      });

      expect(rows, hasLength(500));
      expect(rows.first['name'], 'item_0');
      expect(rows.first['price'], 0.0);
      expect(rows.last['name'], 'item_499');
      expect(rows.last['price'], 499 * 1.5);
    });

    test('transaction select sees uncommitted batch writes', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, val TEXT NOT NULL)',
      );

      final result = await db.transaction((tx) async {
        // Write 200 rows, then read them back inside the same transaction.
        for (var i = 0; i < 200; i++) {
          await tx.execute('INSERT INTO t(val) VALUES (?)', ['row_$i']);
        }
        return await tx.select('SELECT * FROM t ORDER BY id');
      });

      expect(result, hasLength(200));
      expect(result.first['val'], 'row_0');
      expect(result.last['val'], 'row_199');
    });

    test('transaction select with unicode and blob types', () async {
      await db.execute('''
        CREATE TABLE mixed(
          id INTEGER PRIMARY KEY,
          label TEXT NOT NULL,
          payload BLOB
        )
      ''');

      final rows = await db.transaction((tx) async {
        await tx.execute(
          'INSERT INTO mixed(label, payload) VALUES (?, ?)',
          ['日本語テスト', Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF])],
        );
        await tx.execute(
          'INSERT INTO mixed(label, payload) VALUES (?, ?)',
          ['émojis 🎉🚀', Uint8List.fromList([1, 2, 3])],
        );
        return await tx.select('SELECT * FROM mixed ORDER BY id');
      });

      expect(rows, hasLength(2));
      expect(rows[0]['label'], '日本語テスト');
      expect(rows[0]['payload'], [0xDE, 0xAD, 0xBE, 0xEF]);
      expect(rows[1]['label'], 'émojis 🎉🚀');
    });

    // ----- Concurrent reads + writes -----

    test('reads work during sequential writes', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );
      await db.execute('INSERT INTO t(name) VALUES (?)', ['initial']);

      // Multiple writes then reads — ensures reader pool and writer don't interfere.
      for (var i = 0; i < 10; i++) {
        await db.execute('INSERT INTO t(name) VALUES (?)', ['row_$i']);
      }

      final rows = await db.select('SELECT COUNT(*) as cnt FROM t');
      expect(rows[0]['cnt'], 11);
    });

    test('concurrent select and execute', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, value INTEGER NOT NULL)',
      );
      await db.executeBatch(
        'INSERT INTO t(value) VALUES (?)',
        [for (var i = 0; i < 100; i++) [i]],
      );

      // Fire reads and writes concurrently.
      final results = await Future.wait([
        db.select('SELECT COUNT(*) as cnt FROM t'),
        db.execute('INSERT INTO t(value) VALUES (?)', [999]),
        db.select('SELECT COUNT(*) as cnt FROM t'),
        db.execute('INSERT INTO t(value) VALUES (?)', [998]),
        db.select('SELECT COUNT(*) as cnt FROM t'),
      ]);

      // Reads should return valid results (exact count depends on timing).
      for (final r in results) {
        if (r is List<Map<String, Object?>>) {
          final cnt = r[0]['cnt'] as int;
          expect(cnt, greaterThanOrEqualTo(100));
        }
      }
    });

    // ----- Closed database -----

    test('operations on closed database throw ResqliteConnectionException', () async {
      final closedDir = await Directory.systemTemp.createTemp('resqlite_closed_');
      final closedDb = await Database.open('${closedDir.path}/test.db');
      await closedDb.close();

      expect(
        () => closedDb.select('SELECT 1'),
        throwsA(isA<ResqliteConnectionException>()),
      );
      expect(
        () => closedDb.selectBytes('SELECT 1'),
        throwsA(isA<ResqliteConnectionException>()),
      );
      expect(
        () => closedDb.execute('CREATE TABLE t(id INTEGER)'),
        throwsA(isA<ResqliteConnectionException>()),
      );
      expect(
        () => closedDb.stream('SELECT 1'),
        throwsA(isA<ResqliteConnectionException>()),
      );

      await closedDir.delete(recursive: true);
    });
  });
}
