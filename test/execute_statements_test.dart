import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

void main() {
  group('executeStatements moonshot prototype', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'resqlite_execute_statements_',
      );
      db = await Database.open('${tempDir.path}/test.db');
      await db.execute(
        'CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE counters(name TEXT PRIMARY KEY, value INTEGER NOT NULL)',
      );
      await db.execute('INSERT INTO counters(name, value) VALUES (?, ?)', [
        'items',
        0,
      ]);
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

    test('applies heterogeneous statements atomically', () async {
      final results = await db.executeStatements([
        const WriteStatement('INSERT INTO items(name) VALUES (?)', ['Ada']),
        const WriteStatement(
          'UPDATE counters SET value = value + 1 WHERE name = ?',
          ['items'],
        ),
      ]);

      expect(results, hasLength(2));
      expect(results[0].affectedRows, 1);
      expect(results[1].affectedRows, 1);

      final rows = await db.select('SELECT name FROM items');
      expect(rows.single['name'], 'Ada');
      final counters = await db.select('SELECT value FROM counters');
      expect(counters.single['value'], 1);
    });

    test('rolls back the full batch on statement error', () async {
      await expectLater(
        db.executeStatements([
          const WriteStatement('INSERT INTO items(name) VALUES (?)', ['Ada']),
          const WriteStatement('INSERT INTO items(name) VALUES (?)', [null]),
          const WriteStatement(
            'UPDATE counters SET value = value + 1 WHERE name = ?',
            ['items'],
          ),
        ]),
        throwsA(isA<ResqliteQueryException>()),
      );

      final rows = await db.select('SELECT * FROM items');
      expect(rows, isEmpty);
      final counters = await db.select('SELECT value FROM counters');
      expect(counters.single['value'], 0);
    });

    test('invalidates streams once after commit', () async {
      final counts = db
          .stream('SELECT COUNT(*) AS c FROM items')
          .map((rows) => rows.first['c'] as int);
      final iterator = StreamIterator<int>(counts);

      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current, 0);

      await db.executeStatements([
        const WriteStatement('INSERT INTO items(name) VALUES (?)', ['Ada']),
        const WriteStatement('INSERT INTO items(name) VALUES (?)', ['Grace']),
      ]);

      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current, 2);
      await iterator.cancel();
    });

    test('works inside an existing transaction', () async {
      await db.transaction((tx) async {
        await tx.executeStatements([
          const WriteStatement('INSERT INTO items(name) VALUES (?)', ['Ada']),
          const WriteStatement(
            'UPDATE counters SET value = value + 1 WHERE name = ?',
            ['items'],
          ),
        ]);
        final inside = await tx.select('SELECT COUNT(*) AS c FROM items');
        expect(inside.single['c'], 1);
      });

      final counters = await db.select('SELECT value FROM counters');
      expect(counters.single['value'], 1);
    });
  });
}
