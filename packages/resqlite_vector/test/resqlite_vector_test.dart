import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite_vector/resqlite_vector.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('resqlite_vector_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('enables vector functions and configured vector search', () async {
    final plain = await Database.open('${tempDir.path}/plain.db');
    addTearDown(plain.close);

    await expectLater(
      plain.select('SELECT vector_version() AS version'),
      throwsA(isA<ResqliteQueryException>()),
    );

    final path = '${tempDir.path}/vector.db';
    final bootstrap = await Database.open(path);
    await bootstrap.execute(
      'CREATE TABLE items(id INTEGER PRIMARY KEY, embedding BLOB)',
    );
    await bootstrap.close();

    final db = await Database.open(
      path,
      extensions: [
        SqliteVectorExtension(
          indexes: [
            SqliteVectorIndex(
              table: 'items',
              column: 'embedding',
              dimension: 4,
            ),
          ],
        ),
      ],
    );
    addTearDown(db.close);

    final version = await db.select('SELECT vector_version() AS version');
    expect(version.single['version'], isA<String>());

    await db.execute('INSERT INTO items(embedding) VALUES (vector_as_f32(?))', [
      '[1.0, 2.0, 3.0, 4.0]',
    ]);

    final stored = await db.select(
      'SELECT typeof(embedding) AS type FROM items',
    );
    expect(stored.single['type'], 'blob');

    final matches = await db.select(
      '''
      SELECT i.id, v.distance
      FROM items AS i
      JOIN vector_full_scan(
        'items',
        'embedding',
        vector_as_f32(?),
        1
      ) AS v ON i.rowid = v.rowid
      ''',
      ['[1.0, 2.0, 3.0, 4.0]'],
    );
    expect(matches.single['id'], 1);
    expect(matches.single['distance'], isA<num>());
  });
}
