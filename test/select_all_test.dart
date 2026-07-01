import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

Future<Database> _open() async {
  final dir = await Directory.systemTemp.createTemp('resqlite_selectall_');
  addTearDown(() => dir.delete(recursive: true));
  final db = await Database.open('${dir.path}/t.db');
  await db.execute(
    'CREATE TABLE items(id INTEGER PRIMARY KEY, body TEXT NOT NULL, n INTEGER NOT NULL)',
  );
  await db.execute(
    'CREATE TABLE counters(name TEXT PRIMARY KEY, value INTEGER NOT NULL)',
  );
  await db.execute('INSERT INTO items(id, body, n) VALUES (?, ?, ?)', [
    1,
    'ada',
    10,
  ]);
  await db.execute('INSERT INTO items(id, body, n) VALUES (?, ?, ?)', [
    2,
    'grace',
    20,
  ]);
  await db.execute('INSERT INTO counters(name, value) VALUES (?, ?)', [
    'items',
    2,
  ]);
  addTearDown(db.close);
  return db;
}

void main() {
  test('selectAll returns per-statement results in order', () async {
    final db = await _open();
    final results = await db.selectAll([
      const ReadStatement('SELECT body FROM items WHERE id = ?', [1]),
      const ReadStatement('SELECT COUNT(*) AS c FROM items'),
      const ReadStatement('SELECT value FROM counters WHERE name = ?', [
        'items',
      ]),
    ]);
    expect(results, hasLength(3));
    expect(results[0].single['body'], 'ada');
    expect(results[1].single['c'], 2);
    expect(results[2].single['value'], 2);
  });

  test('selectAll with an empty list returns an empty list', () async {
    final db = await _open();
    final results = await db.selectAll(const []);
    expect(results, isEmpty);
  });

  test('selectAll aborts on a failing statement with its own SQL', () async {
    final db = await _open();
    Object? caught;
    try {
      await db.selectAll([
        const ReadStatement('SELECT body FROM items WHERE id = ?', [1]),
        const ReadStatement('SELECT * FROM does_not_exist'),
        const ReadStatement('SELECT n FROM items WHERE id = ?', [2]),
      ]);
    } catch (e) {
      caught = e;
    }
    expect(caught, isA<ResqliteQueryException>());
    final err = caught as ResqliteQueryException;
    expect(err.sql, 'SELECT * FROM does_not_exist');
  });

  test('selectAll inside a transaction sees uncommitted writes', () async {
    final db = await _open();
    final results = await db.transaction((tx) async {
      await tx.execute('INSERT INTO items(id, body, n) VALUES (?, ?, ?)', [
        3,
        'linus',
        30,
      ]);
      return db.selectAll([
        const ReadStatement('SELECT body FROM items WHERE id = ?', [3]),
        const ReadStatement('SELECT COUNT(*) AS c FROM items'),
      ]);
    });
    expect(results[0].single['body'], 'linus');
    expect(results[1].single['c'], 3);
  });
}
