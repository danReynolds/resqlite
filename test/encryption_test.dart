import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

// 256-bit key (32 bytes = 64 hex chars).
const _testKey =
    'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

const _wrongKey =
    'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

void main() {
  group('Encryption', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('resqlite_enc_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } on PathNotFoundException {
          // ignore
        }
      }
    });

    test('encrypted database can read and write', () async {
      final db = await Database.open(
        '${tempDir.path}/encrypted.db',
        encryptionKey: _testKey,
      );

      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );
      await db.execute('INSERT INTO t(name) VALUES (?)', ['secret_data']);

      final rows = await db.select('SELECT name FROM t');
      expect(rows, hasLength(1));
      expect(rows[0]['name'], 'secret_data');

      await db.close();
    });

    test('encrypted database persists after close and reopen', () async {
      final path = '${tempDir.path}/persist.db';

      // Write with encryption.
      final db1 = await Database.open(path, encryptionKey: _testKey);
      await db1.execute('CREATE TABLE t(id INTEGER PRIMARY KEY, val TEXT)');
      await db1.execute('INSERT INTO t(val) VALUES (?)', ['persistent']);
      await db1.close();

      // Reopen with same key — data should be there.
      final db2 = await Database.open(path, encryptionKey: _testKey);
      final rows = await db2.select('SELECT val FROM t');
      expect(rows, hasLength(1));
      expect(rows[0]['val'], 'persistent');
      await db2.close();
    });

    test('wrong key fails to open encrypted database', () async {
      final path = '${tempDir.path}/wrongkey.db';

      // Create encrypted database.
      final db1 = await Database.open(path, encryptionKey: _testKey);
      await db1.execute('CREATE TABLE t(id INTEGER PRIMARY KEY)');
      await db1.close();

      // Try to open with wrong key — should fail.
      expect(
        () => Database.open(path, encryptionKey: _wrongKey),
        throwsA(isA<ResqliteConnectionException>()),
      );
    });

    test('encrypted file has no SQLite header (proves encryption)', () async {
      final path = '${tempDir.path}/noheader.db';

      final db = await Database.open(path, encryptionKey: _testKey);
      await db.execute('CREATE TABLE t(id INTEGER PRIMARY KEY, val TEXT)');
      await db.execute('INSERT INTO t(val) VALUES (?)', ['secret']);
      await db.close();

      // An encrypted database file does NOT start with "SQLite format 3\0"
      // which is the standard 16-byte SQLite header. This proves the file
      // is encrypted at rest.
      final header = await File(path).openRead(0, 16).first;
      final headerString = String.fromCharCodes(header);
      expect(headerString.startsWith('SQLite format 3'), isFalse);
    });

    test('database file is not readable as plain text', () async {
      final path = '${tempDir.path}/opaque.db';

      final db = await Database.open(path, encryptionKey: _testKey);
      await db.execute('CREATE TABLE t(id INTEGER PRIMARY KEY, secret TEXT)');
      await db.execute('INSERT INTO t(secret) VALUES (?)', [
        'this should not appear in raw bytes',
      ]);
      await db.close();

      // Read the raw file bytes — should NOT contain our plaintext.
      final rawBytes = await File(path).readAsBytes();
      final rawString = String.fromCharCodes(rawBytes);
      expect(rawString.contains('this should not appear'), isFalse);
      // Also check it doesn't have the SQLite header magic.
      expect(rawString.startsWith('SQLite format 3'), isFalse);
    });

    test('encrypted database supports all operations', () async {
      final db = await Database.open(
        '${tempDir.path}/full.db',
        encryptionKey: _testKey,
      );

      await db.execute(
        'CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT, value REAL)',
      );

      // Batch write.
      await db.executeBatch(
        'INSERT INTO items(name, value) VALUES (?, ?)',
        [['alice', 1.5], ['bob', 2.5], ['charlie', 3.5]],
      );

      // Select.
      final rows = await db.select('SELECT * FROM items ORDER BY id');
      expect(rows, hasLength(3));

      // SelectBytes.
      final bytes = await db.selectBytes('SELECT * FROM items ORDER BY id');
      expect(bytes.isNotEmpty, isTrue);

      // Transaction.
      final count = await db.transaction((tx) async {
        await tx.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['dave', 4.5]);
        final r = await tx.select('SELECT COUNT(*) as cnt FROM items');
        return r[0]['cnt'] as int;
      });
      expect(count, 4);

      // Stream.
      final stream = db.stream('SELECT COUNT(*) as cnt FROM items');
      final first = await stream.first;
      expect(first[0]['cnt'], 4);

      await db.close();
    });
  });
}
