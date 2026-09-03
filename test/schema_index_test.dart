// The `RowSchema` name index is built on demand, not on the wire ([EXP-281]).
//
// A worker builds one schema per SQL and keeps it, but the schema travels with
// every result, and `SendPort.send` copies a `HashMap` as one object per entry.
// So the load-bearing property is negative — a delivered result carries *no*
// index — and nothing on the public surface can observe it. These tests pin it
// through `resultSetHasNameIndex`, and pin that lookups still behave the same
// whichever side of the lazy build they land on.
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/row.dart' show resultSetHasNameIndex;
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late Database db;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('resqlite_schema_index');
    db = await Database.open('${dir.path}/test.db');
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY,
        name TEXT,
        price REAL,
        description TEXT,
        in_stock INTEGER,
        created_at INTEGER
      )
    ''');
    await db.execute(
      'INSERT INTO products (name, price, description, in_stock, created_at) '
      "VALUES ('Widget', 19.99, 'A short description', 1, 1735689600000)",
    );
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  group('RowSchema lazy index', () {
    test('a delivered result carries no name index', () async {
      final rows = await db.select('SELECT * FROM products');
      expect(resultSetHasNameIndex(rows), isFalse);
    });

    test('column names are not identical to source literals', () async {
      // Why the index still has to exist: decoded names come from
      // `String.fromCharCodes` and are never canonicalized, so the idiomatic
      // `row['name']` misses the identity scan every time.
      final rows = await db.select('SELECT * FROM products');
      expect(identical(rows[0].keys.elementAt(1), 'name'), isFalse);
    });

    test('reading by the schema\'s own name objects never builds one', () async {
      final rows = await db.select('SELECT * FROM products');
      final row = rows[0];
      for (final key in row.keys) {
        expect(row[key], isNotNull);
      }
      row.forEach((key, value) => expect(key, isNotEmpty));
      expect(resultSetHasNameIndex(rows), isFalse);
    });

    test('a literal key builds the index once and resolves correctly', () async {
      final rows = await db.select('SELECT * FROM products');
      expect(rows[0]['name'], 'Widget');
      expect(resultSetHasNameIndex(rows), isTrue);
      // Every column still resolves through the built index.
      expect(rows[0]['id'], 1);
      expect(rows[0]['price'], 19.99);
      expect(rows[0]['in_stock'], 1);
      expect(rows[0]['created_at'], 1735689600000);
    });

    test('an absent key returns null and reports absent', () async {
      final rows = await db.select('SELECT * FROM products');
      expect(rows[0]['nope'], isNull);
      expect(rows[0].containsKey('nope'), isFalse);
      expect(rows[0].containsKey('name'), isTrue);
    });

    test('containsKey alone can build the index', () async {
      final rows = await db.select('SELECT * FROM products');
      expect(rows[0].containsKey('description'), isTrue);
      expect(resultSetHasNameIndex(rows), isTrue);
    });

    test('a wide result resolves past the identity-scan width', () async {
      final columns = List<String>.generate(40, (i) => 'c$i');
      await db.execute(
        'CREATE TABLE wide (${columns.map((c) => '$c INTEGER').join(', ')})',
      );
      await db.execute(
        'INSERT INTO wide (${columns.join(', ')}) '
        'VALUES (${List.filled(40, '1').join(', ')})',
      );
      final rows = await db.select('SELECT * FROM wide');
      expect(resultSetHasNameIndex(rows), isFalse);
      expect(rows[0]['c39'], 1);
      expect(rows[0]['c0'], 1);
      expect(rows[0]['absent'], isNull);
      expect(resultSetHasNameIndex(rows), isTrue);
    });

    test('a stream emission carries no index either', () async {
      final rows = await db.stream('SELECT * FROM products').first;
      expect(resultSetHasNameIndex(rows), isFalse);
      expect(rows[0]['name'], 'Widget');
    });

    test('a hand-built RowSchema behaves the same', () {
      final schema = RowSchema(const ['a', 'b', 'c']);
      expect(schema.columnCount, 3);
      expect(schema.indexOf('b'), 1);
      expect(schema.indexOf('z'), -1);
      expect(schema.containsName('c'), isTrue);
      expect(schema.containsName('z'), isFalse);
    });
  });
}
