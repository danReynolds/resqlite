// EXP-251: where does a large select's worker-side time actually go?
//
// The transfer arc (exp 244/245/246) established transfer is ~6-12% of a large
// select; this decomposes the rest. All lanes run on ONE isolate against a
// direct native handle — no pool, no isolate hop — so `full - step` is a
// focused estimate rather than a subtraction from unrelated benchmarks:
//
//   step   : resqliteStepRow loop over the shared cell buffer. SQLite
//            execution + buffer fill; zero Dart values or per-cell Dart work.
//   full   : executeQuery — step + Dart decode into the flat values list.
//   bytes  : executeQueryBytes — the native query + JSON path (the
//            "don't build Dart objects" whole-path reference point).
//
//   decode/result construction estimate = full − step.
//
// An end-to-end db.select() phase on the same table gives the denominator for
// share-of-wall claims; transfer for these shapes is known from exp 245.
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/native/request_cache.dart' show cachedSqlUtf8;
import 'package:resqlite/src/native/resqlite_bindings.dart'
    show
        allocateParams,
        freeParams,
        resqliteClose,
        resqliteErrmsg,
        resqliteExec,
        resqliteOpen;
import 'package:resqlite/src/query_decoder.dart';
import 'package:resqlite/src/reader/read_worker.dart'
    show executeQuery, executeQueryBytes;

@ffi.Native<
  ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>,
    ffi.Int,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Uint8>,
    ffi.Int,
  )
>(
  symbol: 'resqlite_stmt_acquire_on',
  isLeaf: true,
  assetId: 'package:resqlite/src/native/resqlite_bindings.dart',
)
external ffi.Pointer<ffi.Void> _stmtAcquireOn(
  ffi.Pointer<ffi.Void> db,
  int readerId,
  ffi.Pointer<ffi.Void> sql,
  ffi.Pointer<ffi.Uint8> params,
  int paramCount,
);

int _sink = 0;

/// Step lane: SQLite executes every row into the shared cell buffer, but no
/// Dart value is ever materialized and no synthetic per-cell Dart work is
/// added. The native call still fills the same shared cell buffer as `full`.
int _stepOnly(int handleAddr, String sql) {
  final db = ffi.Pointer<ffi.Void>.fromAddress(handleAddr);
  final sqlNative = cachedSqlUtf8(sql);
  final paramsNative = allocateParams(const []);
  try {
    final stmt = _stmtAcquireOn(db, 0, sqlNative.cast(), paramsNative, 0);
    if (stmt == ffi.nullptr) {
      throw StateError(resqliteErrmsg(db).toDartString());
    }
    final colCount = sqlite3ColumnCount(stmt);
    final buf = ensureCellBuffer(colCount);
    var rows = 0;
    var rc = resqliteStepRow(stmt, colCount, buf);
    while (rc == sqliteRow) {
      rows++;
      rc = resqliteStepRow(stmt, colCount, buf);
    }
    if (rc != sqliteDone) {
      throw StateError(
        'sqlite3_step failed with code $rc: '
        '${resqliteErrmsg(db).toDartString()}',
      );
    }
    return rows;
  } finally {
    freeParams(paramsNative, const []);
  }
}

double _median(List<double> xs) {
  xs.sort();
  return xs[xs.length ~/ 2];
}

/// Times the lanes interleaved — every round runs each lane once, rotating
/// which lane goes first — so slow drift (thermal, background load, allocator
/// state) lands on all lanes equally instead of on whichever block ran last.
/// Sequential per-lane blocks measured `step` slower than `full` (a strict
/// superset of its work), which is how you know blocks don't work here.
List<double> _benchInterleaved(
  List<void Function()> lanes, {
  int iters = 6,
  int rounds = 15,
}) {
  for (final lane in lanes) {
    for (var w = 0; w < 6; w++) {
      lane();
    }
  }
  final samples = List.generate(lanes.length, (_) => <double>[]);
  for (var r = 0; r < rounds; r++) {
    for (var k = 0; k < lanes.length; k++) {
      final lane = (r + k) % lanes.length; // rotate starting lane per round
      final sw = Stopwatch()..start();
      for (var i = 0; i < iters; i++) {
        lanes[lane]();
      }
      sw.stop();
      samples[lane].add(sw.elapsedMicroseconds / iters);
    }
  }
  return [for (final s in samples) _median(s)];
}

Future<void> main() async {
  final tmp = await Directory.systemTemp.createTemp('resqlite-exp251-');
  final path = '${tmp.path}/d.db';

  final pathUtf8 = path.toNativeUtf8();
  final keyUtf8 = ''.toNativeUtf8();
  final handle = resqliteOpen(pathUtf8, 1, keyUtf8);
  calloc.free(pathUtf8);
  calloc.free(keyUtf8);
  if (handle == ffi.nullptr) throw StateError('open failed');
  final addr = handle.address;

  void exec(String sql) {
    final s = sql.toNativeUtf8();
    final rc = resqliteExec(handle, s.cast());
    calloc.free(s);
    if (rc != 0) throw StateError('exec rc=$rc: $sql');
  }

  // Population (WITH RECURSIVE keeps it one statement each).
  exec('PRAGMA journal_mode=WAL');
  exec(
    'CREATE TABLE n20(${List.generate(20, (c) => 'c$c INTEGER').join(', ')})',
  );
  exec(
    'WITH RECURSIVE cnt(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM cnt WHERE x<10000) '
    'INSERT INTO n20 SELECT ${List.generate(20, (c) => 'x*${c + 1}').join(', ')} FROM cnt',
  );
  exec(
    'CREATE TABLE m8(a INTEGER, b INTEGER, c INTEGER, d INTEGER, '
    's TEXT, t TEXT, u TEXT, v TEXT)',
  );
  exec(
    "WITH RECURSIVE cnt(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM cnt WHERE x<10000) "
    "INSERT INTO m8 SELECT x, x*3, x/2, -x, "
    "'row_' || x || ' name field with some descriptive text', "
    "'category_' || (x % 20), 'status_' || (x % 5), 'tag_' || x FROM cnt",
  );
  exec('CREATE TABLE n4(a INTEGER, b INTEGER, c INTEGER, d INTEGER)');
  exec(
    'WITH RECURSIVE cnt(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM cnt WHERE x<5000) '
    'INSERT INTO n4 SELECT x, x*3, x/2, -x FROM cnt',
  );
  exec('CREATE TABLE t1(s TEXT)');
  exec(
    "WITH RECURSIVE cnt(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM cnt WHERE x<5000) "
    "INSERT INTO t1 SELECT 'row_' || x || '_' || "
    "'${'p' * 180}' FROM cnt",
  );

  final shapes = <String, (String, int)>{
    'n20 (10k x 20 int, 200k slots)': ('SELECT * FROM n20', 10000),
    'm8 (10k x 4 int + 4 text, 80k slots)': ('SELECT * FROM m8', 10000),
    'n4 (5k x 4 int, 20k slots)': ('SELECT * FROM n4', 5000),
    't1 (5k x 1 x ~190B text, 5k slots)': ('SELECT * FROM t1', 5000),
  };

  stdout.writeln(
    '| shape | step µs | full µs | decode/result build µs | bytes µs |',
  );
  stdout.writeln('|---|---:|---:|---:|---:|');
  final fullByShape = <String, double>{};
  for (final e in shapes.entries) {
    final (sql, expectRows) = e.value;
    final got = _stepOnly(addr, sql);
    if (got != expectRows) throw StateError('${e.key}: $got rows');
    final [step, full, bytes] = _benchInterleaved([
      () => _stepOnly(addr, sql),
      () => _sink ^= executeQuery(addr, 0, sql, const []).values.length,
      () => _sink ^= executeQueryBytes(addr, 0, sql, const []).bytes.length,
    ]);
    fullByShape[e.key] = full;
    stdout.writeln(
      '| ${e.key} | ${step.toStringAsFixed(1)} '
      '| ${full.toStringAsFixed(1)} | ${(full - step).toStringAsFixed(1)} '
      '| ${bytes.toStringAsFixed(1)} |',
    );
  }
  resqliteClose(handle);

  // End-to-end denominator on the same file, through the real pool.
  stdout.writeln(
    '\n| shape | end-to-end select() µs | worker full µs | share |',
  );
  stdout.writeln('|---|---:|---:|---:|');
  final db = await Database.open(path);
  for (final e in shapes.entries) {
    final (sql, _) = e.value;
    for (var w = 0; w < 10; w++) {
      await db.select(sql);
    }
    final med = <double>[];
    for (var s = 0; s < 9; s++) {
      const iters = 15;
      final sw = Stopwatch()..start();
      for (var i = 0; i < iters; i++) {
        _sink ^= (await db.select(sql)).length;
      }
      sw.stop();
      med.add(sw.elapsedMicroseconds / iters);
    }
    final e2e = _median(med);
    final full = fullByShape[e.key]!;
    stdout.writeln(
      '| ${e.key} | ${e2e.toStringAsFixed(1)} '
      '| ${full.toStringAsFixed(1)} | ${(100 * full / e2e).toStringAsFixed(0)}% |',
    );
  }
  await db.close();
  if (_sink == -1) stdout.writeln('$_sink');
  await tmp.delete(recursive: true);
}
