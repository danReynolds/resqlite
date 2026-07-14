@ffi.DefaultAsset('package:resqlite/src/native/resqlite_bindings.dart')
library;

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:resqlite/src/native/request_cache.dart';
import 'package:resqlite/src/native/resqlite_bindings.dart';
import 'package:resqlite/src/query_decoder.dart';
import 'package:resqlite/src/reader/read_worker.dart';
import 'package:test/test.dart';

@ffi.Native<
  ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Uint8>,
    ffi.Int,
  )
>(symbol: 'resqlite_stmt_acquire_writer', isLeaf: true)
external ffi.Pointer<ffi.Void> resqliteStmtAcquireWriter(
  ffi.Pointer<ffi.Void> db,
  ffi.Pointer<ffi.Void> sql,
  ffi.Pointer<ffi.Uint8> params,
  int paramCount,
);

void main() {
  test('one-pass initial stream hash matches hash-only pass', () {
    final dir = Directory.systemTemp.createTempSync('resqlite_decoder_test_');
    final pathNative = '${dir.path}/hash.db'.toNativeUtf8();
    final db = resqliteOpen(pathNative, 2, ffi.nullptr.cast());
    calloc.free(pathNative);

    expect(db, isNot(ffi.nullptr));

    try {
      _exec(
        db,
        'CREATE TABLE mixed('
        'id INTEGER PRIMARY KEY, '
        'label TEXT, '
        'amount REAL, '
        'payload BLOB, '
        'optional TEXT'
        ');'
        "INSERT INTO mixed(label, amount, payload, optional) "
        "VALUES ('héllo 🚀', 1.25, x'010203FF', NULL);"
        "INSERT INTO mixed(label, amount, payload, optional) "
        "VALUES ('', -3.5, x'', 'present');",
      );

      const sql =
          'SELECT label, amount, payload, optional FROM mixed ORDER BY id';
      final stmt = resqliteStmtAcquireWriter(
        db,
        cachedSqlUtf8(sql).cast(),
        ffi.nullptr.cast(),
        0,
      );

      expect(
        stmt,
        isNot(ffi.nullptr),
        reason: resqliteErrmsg(db).toDartString(),
      );

      final (raw, initialHash) = decodeQueryWithInitialHash(stmt, sql);
      final (hashOnly, rowCount) = callQueryHash(stmt, -1);

      expect(rowCount, raw.rowCount);
      expect(initialHash, hashOnly);
      expect(raw.rowCount, 2);
      expect(raw.values[0], 'héllo 🚀');
      expect(raw.values[1], 1.25);
      expect(raw.values[2], isA<Uint8List>());
      expect(raw.values[2] as Uint8List, [1, 2, 3, 255]);
      expect(raw.values[3], isNull);
      expect(raw.values[4], '');
      expect(raw.values[5], -3.5);
      expect(raw.values[6], isA<Uint8List>());
      expect(raw.values[6] as Uint8List, isEmpty);
      expect(raw.values[7], 'present');
    } finally {
      resqliteClose(db);
      dir.deleteSync(recursive: true);
    }
  });

  test('grow-then-no-op keeps a canonical selectIfChanged hash', () {
    final dir = Directory.systemTemp.createTempSync('resqlite_decoder_test_');
    final pathNative = '${dir.path}/growth.db'.toNativeUtf8();
    final db = resqliteOpen(pathNative, 1, ffi.nullptr.cast());
    calloc.free(pathNative);

    expect(db, isNot(ffi.nullptr));

    try {
      _exec(
        db,
        'CREATE TABLE items(id INTEGER PRIMARY KEY, value TEXT);'
        "INSERT INTO items(value) VALUES ('one');",
      );

      const sql = 'SELECT id, value FROM items ORDER BY id';
      final (_, _, initialHash, initialCount) = executeQueryWithDeps(
        db.address,
        0,
        sql,
        const [],
      );

      _exec(db, "INSERT INTO items(value) VALUES ('two')");
      final (grownHash, grownCount, grownRaw) = executeQueryIfChanged(
        db.address,
        0,
        sql,
        const [],
        initialHash,
        initialCount,
      );

      expect(grownRaw, isNotNull);
      expect(grownCount, 2);

      final (sameHash, sameCount, sameRaw) = executeQueryIfChanged(
        db.address,
        0,
        sql,
        const [],
        grownHash,
        grownCount,
      );

      expect(sameRaw, isNull);
      expect(sameHash, grownHash);
      expect(sameCount, grownCount);
    } finally {
      resqliteClose(db);
      dir.deleteSync(recursive: true);
    }
  });
}

void _exec(ffi.Pointer<ffi.Void> db, String sql) {
  final sqlNative = sql.toNativeUtf8();
  try {
    final rc = resqliteExec(db, sqlNative);
    if (rc != 0) {
      fail('sqlite exec failed: ${resqliteErrmsg(db).toDartString()}');
    }
  } finally {
    calloc.free(sqlNative);
  }
}
