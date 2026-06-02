import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite_js/resqlite_js.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('resqlite_js_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('enables JS functions and package setup', () async {
    final plain = await Database.open('${tempDir.path}/plain.db');
    addTearDown(plain.close);

    await expectLater(
      plain.select('SELECT js_version() AS version'),
      throwsA(isA<ResqliteQueryException>()),
    );

    final db = await Database.open(
      '${tempDir.path}/js.db',
      extensions: [
        SqliteJsExtension(
          onRegister: (ext) {
            ext.execute('CREATE TEMP TABLE js_setup(value TEXT)');
          },
        ),
      ],
    );
    addTearDown(db.close);

    final rows = await db.select('SELECT js_version() AS version');
    expect(rows.single['version'], isA<String>());

    await db.execute('CREATE TABLE scripts(value TEXT)');
    await db.execute('INSERT INTO scripts(value) VALUES (js_version())');

    final stored = await db.select('SELECT value FROM scripts');
    expect(stored.single['value'], rows.single['version']);

    await db.execute('INSERT INTO js_setup(value) VALUES (?)', ['writer']);
    final setupRows = await db.select(
      "SELECT name FROM sqlite_temp_master WHERE type = 'table' AND name = ?",
      ['js_setup'],
    );
    expect(setupRows.single['name'], 'js_setup');
  });
}
