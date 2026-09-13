// ignore_for_file: avoid_print
@ffi.DefaultAsset('package:resqlite/src/native/resqlite_bindings.dart')
/// Prices what a stream rerun pays for running on a connection whose WAL
/// snapshot moved since its last read.
///
/// In WAL mode, a connection that begins a read transaction after another
/// connection committed finds the wal-index header changed and discards its
/// entire page cache (`pagerBeginReadTransaction` -> `pager_reset`). resqlite
/// runs stream reruns on reader connections. The first read on each connection
/// whose cached WAL header is stale begins cold; later reads under the same
/// header remain warm. The after-* lanes measure that transition directly.
/// Its fan-out incidence depends on commit and reader-dispatch scheduling. The
/// writer's own cache is not reset by its own commits.
///
/// Each lane is one hash pass (`resqlite_query_hash`, the unchanged-rerun
/// cost) timed alone; the write that precedes it in the `after-*` lanes is
/// outside the stopwatch.
///
///   reader/warm         no write between passes (control / same-header reuse)
///   reader/after-noise  a commit to an unrelated table between passes
///   reader/after-items  a commit to the queried table between passes
///   writer/warm         same pass on the writer connection, no writes
///   writer/after-items  same pass on the writer connection after its own commit
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
external ffi.Pointer<ffi.Void> _acquireWriter(
  ffi.Pointer<ffi.Void> db,
  ffi.Pointer<ffi.Void> sql,
  ffi.Pointer<ffi.Uint8> params,
  int paramCount,
);

@ffi.Native<
  ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>,
    ffi.Int,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Uint8>,
    ffi.Int,
  )
>(symbol: 'resqlite_stmt_acquire_on', isLeaf: true)
external ffi.Pointer<ffi.Void> _acquireOn(
  ffi.Pointer<ffi.Void> db,
  int readerId,
  ffi.Pointer<ffi.Void> sql,
  ffi.Pointer<ffi.Uint8> params,
  int paramCount,
);

void main(List<String> args) {
  var samples = 15;
  var iterations = 300;
  var checkpoint = true;
  int? readerMmap;
  int? writerMmap;
  for (final arg in args) {
    if (arg.startsWith('--samples=')) {
      samples = int.parse(arg.substring('--samples='.length));
    } else if (arg.startsWith('--iterations=')) {
      iterations = int.parse(arg.substring('--iterations='.length));
    } else if (arg == '--no-checkpoint') {
      checkpoint = false;
    } else if (arg.startsWith('--reader-mmap=')) {
      readerMmap = int.parse(arg.substring('--reader-mmap='.length));
    } else if (arg.startsWith('--writer-mmap=')) {
      writerMmap = int.parse(arg.substring('--writer-mmap='.length));
    }
  }
  print(
    'checkpoint-after-seed=$checkpoint samples=$samples '
    'iterations=$iterations reader-mmap=${readerMmap ?? "default"} '
    'writer-mmap=${writerMmap ?? "default"}',
  );
  _readerMmap = readerMmap;
  _writerMmap = writerMmap;
  _lane(
    'point-1x3',
    100,
    'SELECT id, owner_id, value FROM items WHERE id = 7',
    samples,
    iterations,
    checkpoint,
  );
  _lane(
    'partition-14x2',
    100,
    'SELECT id, value FROM items WHERE owner_id = 3 ORDER BY id',
    samples,
    iterations,
    checkpoint,
  );
  _lane(
    'scan-1000x2',
    1000,
    'SELECT id, value FROM items ORDER BY id',
    samples,
    iterations,
    checkpoint,
  );
  // 10,000 rows, 200 owners: a 50-row page whose rows sit ~200 rows apart,
  // so the index walk touches ~50 distinct table leaf pages.
  _lane(
    'page-50x3-of-10k',
    10000,
    'SELECT id, value, body FROM items WHERE owner_id = 3 ORDER BY id '
        'LIMIT 50',
    samples,
    iterations,
    checkpoint,
  );
  _lane(
    'scan-1000x2-of-10k',
    10000,
    'SELECT id, value FROM items ORDER BY id LIMIT 1000',
    samples,
    iterations,
    checkpoint,
  );
  _lane(
    'full-10kx4',
    10000,
    'SELECT id, owner_id, value, body FROM items ORDER BY id',
    samples,
    iterations ~/ 4,
    checkpoint,
  );
}

int? _readerMmap;
int? _writerMmap;

const _schema =
    'CREATE TABLE items(id INTEGER PRIMARY KEY, owner_id INTEGER NOT NULL, '
    'value INTEGER, body TEXT NOT NULL); '
    'CREATE INDEX items_owner ON items(owner_id); '
    'CREATE TABLE noise(id INTEGER PRIMARY KEY, v INTEGER);'
    'INSERT INTO noise(id, v) VALUES (1, 0);';

const _noiseWrite = 'UPDATE noise SET v = v + 1 WHERE id = 1';
const _itemsWrite = 'UPDATE items SET value = value + 1 WHERE id = 1';

void _lane(
  String label,
  int rows,
  String sql,
  int samples,
  int iterations,
  bool checkpoint,
) {
  final dir = Directory.systemTemp.createTempSync('exp289_snap_');
  final pathNative = '${dir.path}/t.db'.toNativeUtf8();
  final db = resqliteOpen(pathNative, 2, ffi.nullptr.cast());
  calloc.free(pathNative);
  if (db == ffi.nullptr) throw StateError('open failed');
  try {
    _exec(db, _schema);
    final insert = StringBuffer('BEGIN;');
    final owners = rows >= 10000 ? 200 : 7;
    for (var i = 1; i <= rows; i++) {
      insert.write(
        'INSERT INTO items(id, owner_id, value, body) '
        "VALUES ($i, ${i % owners}, $i, 'body text for row number $i');",
      );
    }
    insert.write('COMMIT;');
    _exec(db, insert.toString());
    if (checkpoint) _exec(db, 'PRAGMA wal_checkpoint(TRUNCATE)');
    if (_readerMmap case final m?) _setup(db, 'PRAGMA mmap_size = $m', 2);
    if (_writerMmap case final m?) _setup(db, 'PRAGMA mmap_size = $m', 1);

    final sqlNative = cachedSqlUtf8(sql).cast<ffi.Void>();
    final readerStmt = _acquireOn(db, 0, sqlNative, ffi.nullptr.cast(), 0);
    final writerStmt = _acquireWriter(db, sqlNative, ffi.nullptr.cast(), 0);
    if (readerStmt == ffi.nullptr || writerStmt == ffi.nullptr) {
      throw StateError('acquire failed');
    }

    for (var i = 0; i < 50; i++) {
      callQueryHash(readerStmt);
      callQueryHash(writerStmt);
    }

    const arms = [
      'reader/warm',
      'reader/after-noise',
      'reader/after-items',
      'writer/warm',
      'writer/after-items',
    ];
    final results = {for (final a in arms) a: <double>[]};
    for (var s = 0; s < samples; s++) {
      final order = List<int>.generate(arms.length, (i) => i);
      for (var r = 0; r < s % arms.length; r++) {
        order.add(order.removeAt(0));
      }
      for (final arm in order) {
        var total = 0;
        final sw = Stopwatch();
        final freq = sw.frequency;
        for (var i = 0; i < iterations; i++) {
          switch (arm) {
            case 1:
              _exec(db, _noiseWrite);
            case 2:
            case 4:
              _exec(db, _itemsWrite);
          }
          final stmt = arm < 3 ? readerStmt : writerStmt;
          sw
            ..reset()
            ..start();
          callQueryHash(stmt);
          sw.stop();
          total += sw.elapsedTicks;
        }
        results[arms[arm]]!.add(total * 1e6 / freq / iterations);
      }
    }
    final warm = _median(results['reader/warm']!);
    print('== $label rows=$rows');
    for (final a in arms) {
      final m = _median(results[a]!);
      print(
        '  ${a.padRight(20)} ${m.toStringAsFixed(2)} us  '
        '(${(m - warm) >= 0 ? '+' : ''}${(m - warm).toStringAsFixed(2)} us vs '
        'reader/warm, ${(100 * (m - warm) / warm).toStringAsFixed(0)}%)',
      );
    }
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

void _setup(ffi.Pointer<ffi.Void> db, String sql, int scope) {
  final native = sql.toNativeUtf8();
  final rc = resqliteRunConnectionSetup(db, native, ffi.nullptr, 0, scope);
  calloc.free(native);
  if (rc != 0) throw StateError('setup failed ($rc): $sql');
}

void _exec(ffi.Pointer<ffi.Void> db, String sql) {
  final native = sql.toNativeUtf8();
  final rc = resqliteExec(db, native);
  calloc.free(native);
  if (rc != 0) throw StateError('exec failed ($rc): $sql');
}
