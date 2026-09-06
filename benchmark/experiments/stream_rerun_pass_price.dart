// ignore_for_file: avoid_print
@ffi.DefaultAsset('package:resqlite/src/native/resqlite_bindings.dart')

/// [EXP-283] Prices the two SQLite passes a *changed* stream rerun makes.
///
/// `executeQueryIfChanged` hashes the bound statement to completion, and when
/// the hash moves it steps the same statement a second time to build the Dart
/// result. The one-pass decoder `decodeQueryWithInitialHash` (exp 097, shipped
/// for initial stream registration) does both in one step pass. This harness
/// prices all three against each other on stream-shaped queries, with no pool,
/// no isolates and no message hop, so the prize is readable directly.
///
///   hash        — `resqlite_query_hash`, the unchanged-rerun cost
///   decode      — `decodeQuery`, the second pass a changed rerun adds
///   hash+decode — what a changed rerun costs today
///   onepass     — `decodeQueryWithInitialHash`, what it would cost instead
library;

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:resqlite/src/native/request_cache.dart';
import 'package:resqlite/src/native/resqlite_bindings.dart';
import 'package:resqlite/src/query_decoder.dart';

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

@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>)>(
  symbol: 'resqlite_exec',
  isLeaf: true,
)
external int resqliteExecRaw(
  ffi.Pointer<ffi.Void> db,
  ffi.Pointer<ffi.Void> sql,
);

void main(List<String> args) {
  var samples = 15;
  var iterations = 400;
  for (final arg in args) {
    if (arg.startsWith('--samples=')) {
      samples = int.parse(arg.substring('--samples='.length));
    } else if (arg.startsWith('--iterations=')) {
      iterations = int.parse(arg.substring('--iterations='.length));
    }
  }
  _lane('fanout-100x2', 100, _fanoutSchema, _fanoutSql, samples, iterations);
  _lane('feed-50x4', 50, _feedSchema, _feedSql, samples, iterations);
  _lane('point-1x3', 1, _pointSchema, _pointSql, samples, iterations);
  _lane('wide-1000x2', 1000, _fanoutSchema, _fanoutSql, samples, iterations);
}

const _fanoutSchema =
    'CREATE TABLE items(id INTEGER PRIMARY KEY, owner_id INTEGER NOT NULL, '
    'value INTEGER);';
const _fanoutSql = 'SELECT id, value FROM items ORDER BY id';

const _feedSchema =
    'CREATE TABLE items(id INTEGER PRIMARY KEY, owner_id INTEGER NOT NULL, '
    'value INTEGER, body TEXT NOT NULL);';
const _feedSql = 'SELECT id, value, body, owner_id FROM items ORDER BY id';

const _pointSchema =
    'CREATE TABLE items(id INTEGER PRIMARY KEY, owner_id INTEGER NOT NULL, '
    'value INTEGER);';
const _pointSql = 'SELECT id, owner_id, value FROM items WHERE id = 1';

void _lane(
  String label,
  int rows,
  String schema,
  String sql,
  int samples,
  int iterations,
) {
  final dir = Directory.systemTemp.createTempSync('exp283_pass_');
  final pathNative = '${dir.path}/t.db'.toNativeUtf8();
  final db = resqliteOpen(pathNative, 1, ffi.nullptr.cast());
  calloc.free(pathNative);
  if (db == ffi.nullptr) throw StateError('open failed');
  try {
    _exec(db, schema);
    final insert = StringBuffer('BEGIN;');
    for (var i = 1; i <= rows; i++) {
      if (schema == _feedSchema) {
        insert.write(
          "INSERT INTO items(id, owner_id, value, body) "
          "VALUES ($i, ${i % 7}, $i, 'body text for row $i');",
        );
      } else {
        insert.write(
          'INSERT INTO items(id, owner_id, value) VALUES ($i, ${i % 7}, $i);',
        );
      }
    }
    insert.write('COMMIT;');
    _exec(db, insert.toString());

    final stmt = resqliteStmtAcquireWriter(
      db,
      cachedSqlUtf8(sql).cast(),
      ffi.nullptr.cast(),
      0,
    );
    if (stmt == ffi.nullptr) throw StateError('acquire failed');

    // Warm the schema cache, the cell buffer and the row-size memory so no
    // lane pays a first-execution cost the others do not.
    for (var i = 0; i < 50; i++) {
      callQueryHash(stmt);
      decodeQuery(stmt, sql);
      decodeQueryWithInitialHash(stmt, sql);
    }

    final hash = <double>[];
    final decode = <double>[];
    final onepass = <double>[];
    for (var s = 0; s < samples; s++) {
      // Rotate arm order per sample so drift lands on every arm equally.
      final order = [0, 1, 2];
      final rot = s % 3;
      for (var r = 0; r < rot; r++) {
        order.add(order.removeAt(0));
      }
      for (final arm in order) {
        final sw = Stopwatch()..start();
        for (var i = 0; i < iterations; i++) {
          switch (arm) {
            case 0:
              callQueryHash(stmt);
            case 1:
              decodeQuery(stmt, sql);
            case 2:
              decodeQueryWithInitialHash(stmt, sql);
          }
        }
        sw.stop();
        final us = sw.elapsedMicroseconds / iterations;
        switch (arm) {
          case 0:
            hash.add(us);
          case 1:
            decode.add(us);
          case 2:
            onepass.add(us);
        }
      }
    }
    final h = _median(hash);
    final d = _median(decode);
    final o = _median(onepass);
    final today = h + d;
    print(
      '$label rows=$rows  '
      'hash=${h.toStringAsFixed(2)}us  '
      'decode=${d.toStringAsFixed(2)}us  '
      'hash+decode=${today.toStringAsFixed(2)}us  '
      'onepass=${o.toStringAsFixed(2)}us  '
      'saved=${(today - o).toStringAsFixed(2)}us '
      '(${(100 * (today - o) / today).toStringAsFixed(1)}% of a changed rerun) '
      'miss_tax=${(o - h).toStringAsFixed(2)}us '
      '(${(100 * (o - h) / h).toStringAsFixed(1)}% of an unchanged rerun)',
    );
  } finally {
    resqliteClose(db);
    dir.deleteSync(recursive: true);
  }
}

double _median(List<double> xs) {
  final s = [...xs]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

void _exec(ffi.Pointer<ffi.Void> db, String sql) {
  final native = sql.toNativeUtf8();
  final rc = resqliteExecRaw(db, native.cast());
  calloc.free(native);
  if (rc != 0) throw StateError('exec failed ($rc): $sql');
}
