// ignore_for_file: avoid_print
@ffi.DefaultAsset('package:resqlite/src/native/resqlite_bindings.dart')
library;

// Prices the one mechanism that could close the hazard
// `select_cache_foreign_writer.dart` demonstrates
// ([EXP-270](../../experiments/270-read-result-cache.md)).
//
// A `select()` result cache is wrong whenever a connection other than this
// `Database` commits, because resqlite's invalidation only ever hears about its
// own writes. SQLite already answers exactly that question: `PRAGMA
// data_version` is a counter that changes when the database file is modified by
// *any other* connection. If reading it on the calling isolate were cheap and
// bounded, a cache hit could validate itself and the hazard would close.
//
// So this measures the primitive rather than assuming its cost, in the two
// conditions that matter:
//
//   idle       nothing else touching the file — the cost a hit would pay every
//              time, which has to stay well under the ~4-5 us round trip the
//              cache exists to avoid or there is nothing left to win.
//   contended  a second connection committing continuously — because the read
//              transaction `PRAGMA data_version` opens is where a bounded median
//              can still hide an unbounded tail. Reader connections carry a
//              5-second busy timeout.
//
// The probe runs the pragma on the main isolate against a dedicated handle no
// worker touches, which is what a validating cache would have to do.
//
// Usage:
//   dart run benchmark/experiments/select_cache_data_version.dart [--samples=2000]
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:resqlite/resqlite.dart' as resqlite;
import 'package:resqlite/src/native/resqlite_bindings.dart';

// Same private binding `read_worker.dart` uses; redeclared here because the
// probe drives a reader connection directly from the main isolate.
@ffi.Native<
  ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>,
    ffi.Int,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Uint8>,
    ffi.Int,
  )
>(symbol: 'resqlite_stmt_acquire_on', isLeaf: true)
external ffi.Pointer<ffi.Void> _stmtAcquireOn(
  ffi.Pointer<ffi.Void> db,
  int readerId,
  ffi.Pointer<ffi.Void> sql,
  ffi.Pointer<ffi.Uint8> params,
  int paramCount,
);

const _pragma = 'PRAGMA data_version';

/// The timed operation: acquire the cached statement, step it, and let C
/// serialize the single INTEGER cell. This is the floor for asking SQLite
/// whether anything changed — a validating cache could not do less.
int _stepDataVersion(ffi.Pointer<ffi.Void> handle) =>
    queryBytes(handle, 0, _pragma, const []).length;

int _readDataVersion(ffi.Pointer<ffi.Void> handle) {
  final buffer = queryBytes(handle, 0, _pragma, const []);
  final json = utf8.decode(buffer.ptr.asTypedList(buffer.length));
  final decoded = jsonDecode(json) as List<Object?>;
  return (decoded.first as Map<String, Object?>)['data_version']! as int;
}

Future<void> main(List<String> args) async {
  var samples = 2000;
  for (final arg in args) {
    if (arg.startsWith('--samples=')) {
      samples = int.parse(arg.substring('--samples='.length));
    } else {
      throw ArgumentError('unknown argument: $arg');
    }
  }

  final temp = await Directory.systemTemp.createTemp('bench_data_version_');
  try {
    final path = '${temp.path}/test.db';
    final owner = await resqlite.Database.open(path);
    await owner.execute('CREATE TABLE items(id INTEGER PRIMARY KEY, v TEXT)');
    await owner.execute('INSERT INTO items(id, v) VALUES (1, ?)', ['a']);

    // The connection a validating cache would consult: reader 0 of a handle
    // this isolate owns outright.
    final probe = await resqlite.Database.open(path);
    final handle = probe.handle;
    // Prepare once, so the measured cost is stepping a cached statement.
    final sqlNative = _pragma.toNativeUtf8();
    _stmtAcquireOn(handle, 0, sqlNative.cast(), ffi.nullptr, 0);
    final warm = _readDataVersion(handle);
    print('data_version (warm) = $warm');

    // Warm the path before timing: this probe is about the steady-state cost.
    for (var i = 0; i < 200; i++) {
      _stepDataVersion(handle);
    }
    print(_measure('idle', samples, () => _stepDataVersion(handle)));

    // A foreign connection committing continuously, so the pragma's read
    // transaction contends with real WAL activity.
    final writer = await resqlite.Database.open(path);
    var stop = false;
    final churn = () async {
      var n = 0;
      while (!stop) {
        await writer.execute('UPDATE items SET v = ? WHERE id = 1', [
          'v${n++}',
        ]);
      }
      return n;
    }();
    // Let the writer get going before sampling.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final line = _measure('contended', samples, () => _stepDataVersion(handle));
    stop = true;
    final writes = await churn;
    print(line);
    print('foreign commits during the contended phase: $writes');

    final observed = _readDataVersion(handle);
    print(
      'data_version moved under foreign writes: ${observed != warm} '
      '($warm -> $observed)',
    );

    await writer.close();
    await probe.close();
    await owner.close();
  } finally {
    await temp.delete(recursive: true);
  }
}

String _measure(String label, int samples, int Function() body) {
  final values = <int>[];
  final sw = Stopwatch();
  for (var i = 0; i < samples; i++) {
    sw
      ..reset()
      ..start();
    body();
    sw.stop();
    values.add(sw.elapsedMicroseconds);
  }
  values.sort();
  int at(double p) => values[((values.length - 1) * p).round()];
  return 'phase=$label samples=$samples p50_us=${at(0.50)} '
      'p90_us=${at(0.90)} p99_us=${at(0.99)} max_us=${values.last}';
}
