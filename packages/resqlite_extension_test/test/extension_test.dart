import 'dart:ffi';
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite_js/resqlite_js.dart';
import 'package:resqlite_vector/resqlite_vector.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('resqlite_ext_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test(
    'loads vector extension on every connection for the opened database',
    () async {
      final plain = await Database.open('${tempDir.path}/plain.db');
      addTearDown(plain.close);

      await expectLater(
        plain.select('SELECT vector_version() AS version'),
        throwsA(isA<ResqliteQueryException>()),
      );

      final db = await Database.open(
        '${tempDir.path}/vector.db',
        extensions: [sqliteVectorExtension(), sqliteVectorExtension()],
      );
      addTearDown(db.close);

      final firstVector = sqliteVectorExtension();
      final secondVector = sqliteVectorExtension();
      expect(
        firstVector.entrypointAddress.address,
        secondVector.entrypointAddress.address,
      );
      expect(firstVector, isNot(secondVector));
      expect(firstVector.debugName, 'sqlite_vector');

      final version = await db.select('SELECT vector_version() AS version');
      expect(version.single['version'], isA<String>());

      await db.execute('CREATE TABLE items (embedding BLOB)');
      await db.execute(
        'INSERT INTO items (embedding) VALUES (vector_as_f32(?))',
        ['[1.0, 2.0, 3.0, 4.0]'],
      );
      final stored = await db.select(
        'SELECT typeof(embedding) AS type FROM items',
      );
      expect(stored.single['type'], 'blob');

      final stillPlain = await Database.open('${tempDir.path}/still_plain.db');
      addTearDown(stillPlain.close);

      await expectLater(
        stillPlain.select('SELECT vector_version() AS version'),
        throwsA(isA<ResqliteQueryException>()),
      );
    },
  );

  test('runs extension setup SQL on writer and reader connections', () async {
    final db = await Database.open(
      '${tempDir.path}/setup_all.db',
      extensions: [
        sqliteVectorExtension(
          onRegister: (ext) {
            ext.execute('CREATE TEMP TABLE setup_all(value TEXT)');
          },
        ),
      ],
    );
    addTearDown(db.close);

    await db.execute('INSERT INTO setup_all(value) VALUES (?)', ['writer']);

    for (var i = 0; i < 8; i++) {
      final rows = await db.select(
        "SELECT name FROM sqlite_temp_master WHERE type = 'table' AND name = ?",
        ['setup_all'],
      );
      expect(rows.single['name'], 'setup_all');
    }
  });

  test('runs setup SQL only on the requested connection scope', () async {
    final db = await Database.open(
      '${tempDir.path}/setup_scope.db',
      extensions: [
        sqliteVectorExtension(
          onRegister: (ext) {
            ext.execute(
              'CREATE TEMP TABLE writer_only(value TEXT)',
              scope: ResqliteConnectionScope.writer,
            );
            ext.execute(
              'CREATE TEMP TABLE readers_only(value TEXT)',
              scope: ResqliteConnectionScope.readers,
            );
          },
        ),
      ],
    );
    addTearDown(db.close);

    await db.execute('INSERT INTO writer_only(value) VALUES (?)', ['ok']);
    await expectLater(
      db.execute('INSERT INTO readers_only(value) VALUES (?)', ['missing']),
      throwsA(isA<ResqliteQueryException>()),
    );

    for (var i = 0; i < 8; i++) {
      final readerRows = await db.select(
        "SELECT name FROM sqlite_temp_master WHERE type = 'table' AND name = ?",
        ['readers_only'],
      );
      expect(readerRows.single['name'], 'readers_only');

      final writerRows = await db.select(
        "SELECT name FROM sqlite_temp_master WHERE type = 'table' AND name = ?",
        ['writer_only'],
      );
      expect(writerRows, isEmpty);
    }
  });

  test('preserves setup from duplicate extension entrypoints', () async {
    final db = await Database.open(
      '${tempDir.path}/setup_duplicates.db',
      extensions: [
        sqliteVectorExtension(
          onRegister: (ext) {
            ext.execute('CREATE TEMP TABLE setup_a(value TEXT)');
          },
        ),
        sqliteVectorExtension(
          onRegister: (ext) {
            ext.execute('CREATE TEMP TABLE setup_b(value TEXT)');
          },
        ),
      ],
    );
    addTearDown(db.close);

    for (final table in ['setup_a', 'setup_b']) {
      await db.execute('INSERT INTO $table(value) VALUES (?)', ['writer']);
      final rows = await db.select(
        "SELECT name FROM sqlite_temp_master WHERE type = 'table' AND name = ?",
        [table],
      );
      expect(rows.single['name'], table);
    }
  });

  test(
    'reports setup failures with extension and connection context',
    () async {
      await expectLater(
        Database.open(
          '${tempDir.path}/setup_failure.db',
          extensions: [
            sqliteVectorExtension(
              onRegister: (ext) {
                ext.execute('SELECT 1; SELECT 2');
              },
            ),
          ],
        ),
        throwsA(
          isA<ResqliteConnectionException>()
              .having((e) => e.message, 'message', contains('sqlite_vector'))
              .having(
                (e) => e.message,
                'message',
                contains('writer connection'),
              )
              .having(
                (e) => e.message,
                'message',
                contains('exactly one statement'),
              )
              .having(
                (e) => e.message,
                'message',
                contains('SELECT 1; SELECT 2'),
              ),
        ),
      );
    },
  );

  test('runs onRegister setup in extension list order', () async {
    final db = await Database.open(
      '${tempDir.path}/setup_order.db',
      extensions: [
        sqliteVectorExtension(
          onRegister: (ext) {
            ext.execute(
              'CREATE TEMP TABLE registration_order(value TEXT)',
              scope: ResqliteConnectionScope.writer,
            );
            ext.execute(
              'INSERT INTO registration_order(value) VALUES (?)',
              parameters: ['vector'],
              scope: ResqliteConnectionScope.writer,
            );
          },
        ),
        sqliteJsExtension(
          onRegister: (ext) {
            ext.execute(
              'INSERT INTO registration_order(value) VALUES (?)',
              parameters: ['js'],
              scope: ResqliteConnectionScope.writer,
            );
          },
        ),
      ],
    );
    addTearDown(db.close);

    final values = await db.transaction((tx) {
      return tx.select('SELECT value FROM registration_order ORDER BY rowid');
    });
    expect(values.map((row) => row['value']), ['vector', 'js']);
  });

  test('initializes configured vector indexes on every connection', () async {
    final path = '${tempDir.path}/vector_index.db';
    final bootstrap = await Database.open(
      path,
      extensions: [sqliteVectorExtension()],
    );
    await bootstrap.execute(
      'CREATE TABLE items(id INTEGER PRIMARY KEY, embedding BLOB)',
    );
    await bootstrap.close();

    final db = await Database.open(
      path,
      extensions: [
        sqliteVectorExtension(
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

    await db.execute('INSERT INTO items(embedding) VALUES (vector_as_f32(?))', [
      '[1.0, 2.0, 3.0, 4.0]',
    ]);
    final rows = await db.select(
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
    expect(rows.single['id'], 1);
  });

  test('loads an unrelated extension through the same pattern', () async {
    final db = await Database.open(
      '${tempDir.path}/js.db',
      extensions: [
        sqliteJsExtension(
          onRegister: (ext) {
            ext.execute('CREATE TEMP TABLE js_setup(value TEXT)');
          },
        ),
      ],
    );
    addTearDown(db.close);

    final rows = await db.select('SELECT js_version() AS version');
    expect(rows.single['version'], isA<String>());

    await db.execute('CREATE TABLE scripts (value TEXT)');
    await db.execute('INSERT INTO scripts (value) VALUES (js_version())');
    final stored = await db.select('SELECT value FROM scripts');
    expect(stored.single['value'], isA<String>());

    await db.execute('INSERT INTO js_setup(value) VALUES (?)', ['writer']);
    for (var i = 0; i < 8; i++) {
      final setupRows = await db.select(
        "SELECT name FROM sqlite_temp_master WHERE type = 'table' AND name = ?",
        ['js_setup'],
      );
      expect(setupRows.single['name'], 'js_setup');
    }
  });

  test('loads an extension from a dynamic library symbol', () async {
    final vectorLibraryPath = _vectorLibraryPath();
    if (vectorLibraryPath == null) {
      markTestSkipped('No checked-in vector binary for ${Abi.current()}.');
      return;
    }

    final vectorLibrary = File(vectorLibraryPath);
    if (!vectorLibrary.existsSync()) {
      markTestSkipped('Missing vector binary: ${vectorLibrary.path}');
      return;
    }

    final db = await Database.open(
      '${tempDir.path}/vector_library.db',
      extensions: [
        ResqliteExtension.inLibrary(
          DynamicLibrary.open(vectorLibrary.absolute.path),
          'sqlite3_vector_init',
          name: 'sqlite_vector',
        ),
      ],
    );
    addTearDown(db.close);

    final version = await db.select('SELECT vector_version() AS version');
    expect(version.single['version'], isA<String>());
  });
}

String? _vectorLibraryPath() {
  final abi = Abi.current();
  if (abi == Abi.macosArm64) {
    return '../resqlite_vector/native_libraries/mac/vector_mac_arm64.dylib';
  }
  if (abi == Abi.macosX64) {
    return '../resqlite_vector/native_libraries/mac/vector_mac_x64.dylib';
  }
  if (abi == Abi.linuxArm64) {
    return '../resqlite_vector/native_libraries/linux/vector_linux_arm64.so';
  }
  if (abi == Abi.linuxX64) {
    return '../resqlite_vector/native_libraries/linux/vector_linux_x64.so';
  }
  if (abi == Abi.windowsX64) {
    return '../resqlite_vector/native_libraries/windows/vector_windows_x64.dll';
  }
  return null;
}
