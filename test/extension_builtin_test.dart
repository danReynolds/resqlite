import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

void main() {
  test('enables documented built-in SQLite capabilities', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'resqlite_builtin_ext_',
    );
    final db = await Database.open('${tempDir.path}/builtins.db');
    addTearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    await db.execute('CREATE VIRTUAL TABLE docs USING fts5(title, body)');
    await db.execute('INSERT INTO docs(title, body) VALUES (?, ?)', [
      'SQLite',
      'resqlite includes FTS5 support',
    ]);
    final ftsRows = await db.select(
      'SELECT title FROM docs WHERE docs MATCH ?',
      ['FTS5'],
    );
    expect(ftsRows.single['title'], 'SQLite');

    final jsonRows = await db.select(
      r'''
      SELECT
        json_extract(?, '$.name') AS name,
        json_each.value AS count
      FROM json_each(?)
      WHERE json_each.key = 'count'
      ''',
      ['{"name":"Ada"}', '{"count":7}'],
    );
    expect(jsonRows.single['name'], 'Ada');
    expect(jsonRows.single['count'], 7);

    final mathRows = await db.select(
      'SELECT sqrt(9.0) AS root, pow(2.0, 5.0) AS power, sin(0.0) AS sine',
    );
    expect(mathRows.single['root'], 3.0);
    expect(mathRows.single['power'], 32.0);
    expect(mathRows.single['sine'], 0.0);
  });
}
