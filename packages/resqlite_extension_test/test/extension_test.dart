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

      expect(sqliteVectorExtension(), sqliteVectorExtension());
      expect(sqliteVectorExtension().debugName, 'sqlite_vector');

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

  test('loads an unrelated extension through the same pattern', () async {
    final db = await Database.open(
      '${tempDir.path}/js.db',
      extensions: [sqliteJsExtension()],
    );
    addTearDown(db.close);

    final rows = await db.select('SELECT js_version() AS version');
    expect(rows.single['version'], isA<String>());

    await db.execute('CREATE TABLE scripts (value TEXT)');
    await db.execute('INSERT INTO scripts (value) VALUES (js_version())');
    final stored = await db.select('SELECT value FROM scripts');
    expect(stored.single['value'], isA<String>());
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
