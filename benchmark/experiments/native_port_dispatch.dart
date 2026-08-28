// ignore_for_file: avoid_print
//
// Prices the two halves of resqlite's read round trip, so the moonshot in
// [EXP-279] — run the query on a native thread instead of a Dart isolate — can
// be costed before it is built.
//
// Exp 265 measured the `select()` isolate round trip at 6.3 us of an 8.4 us
// canonical point read (claim 265.1) and every candidate since has tried to
// collect it by removing the worker: run the query on the caller (exps 265,
// 269), answer from a cache so no query runs at all (exp 270), or reorder who
// gets the worker first (exp 275). All were rejected. None asked whether the
// worker has to be a *Dart isolate*: a POSIX thread holding a C reader slot
// gives the caller's event loop exactly the same protection, and its completion
// can reach the main isolate through `Dart_PostCObject_DL` on a native port.
//
// Before building any of that, the 6.3 us has to be split. It is two message
// deliveries, and only one of them is avoidable:
//
//   main -> worker    a `SendPort.send` plus the worker isolate waking and
//                     taking an event-loop turn. A native thread replaces this
//                     with an FFI call and a condvar signal.
//   worker -> main    the reply, plus the *main* isolate waking and taking a
//                     turn. Native dispatch still pays this, because the result
//                     still has to arrive as a message on the main isolate.
//
// If the second half is most of the 6.3 us, no dispatch mechanism can help and
// the direction closes for good. That is what `nport-here` measures: a native
// post issued from the calling thread itself, with no sender-side hop of any
// kind in front of it — the price of *receiving* one message on the main
// isolate, alone.
//
// Four lanes, each a sequence of awaited round trips (a read awaits, so the
// pipeline never fills):
//
//   iso-echo      main sends an int to a persistent worker isolate, which
//                 sends one back. The Dart-isolate round trip at its floor.
//   iso-request   the same round trip carrying a `SelectRequest`-shaped object
//                 out — String sql, List parameters, three ints — so the
//                 message-serialisation adder is visible separately.
//   nport-thread  an FFI enqueue onto a native worker thread, which posts an
//                 int back through `Dart_PostCObject_DL`. The candidate.
//   nport-spin    the same native dispatch with the worker thread spinning on
//                 the queue instead of parking on a condvar. It burns a core,
//                 so it is not a shippable design — it is the mechanism's floor,
//                 and it removes "you picked a slow primitive" as an objection.
//   nport-here    the same native post, issued from the calling thread. No
//                 dispatch at all: main-isolate delivery on its own.
//   iso-result    the isolate round trip carrying a point read's *reply* shape
//                 back — six cell values, six column names, and the pool's
//                 `(result, sacrificed, error)` envelope, pre-built on the
//                 worker so only the transfer is timed.
//   iso-full      request object out and result shape back in the same trip:
//                 a point read's whole transport, measured rather than summed.
//   iso-bytes     the `selectBytes` shape — the worker replies with a 256 KB
//                 `Uint8List`, which `SendPort.send` copies into the receiver.
//   nport-bytes   the same payload posted from the native thread as external
//                 typed data: one copy on the sending side and none on the
//                 receiving one. The only leg where native dispatch has a
//                 structural advantage rather than a scheduling one.
//   iso-bytes-heap
//                 the same 256 KB sent as an ordinary heap `Uint8List` instead
//                 of a view over native memory. Backing, not size, is what the
//                 VM's message copy charges for.
//   nport-bytes-nocopy
//                 the ceiling of that advantage: the same post with no copy at
//                 all. Not shippable — a real one would have to hand `json_buf`
//                 itself over and give the connection a new one, losing the
//                 buffer reuse exp 183 depends on — but it bounds the prize.
//
// Two more lanes take the mechanism end to end against a real database, so the
// synthetic figures above can be checked against a query that actually runs:
//
//   iso-query     `db.selectBytes(sql)` exactly as shipped.
//   nport-query   the same SQL serialized by `resqlite_query_bytes` on a native
//                 worker thread, posted back as external typed data. No Dart
//                 isolate between the caller and SQLite.
//
// Both take `--rows=N`, and the pair is only meaningful at matched N. They are
// sequential by construction: the native thread borrows reader slot 0, which no
// Dart reader worker is using while the lane runs.
//
// Read `nport-here` against `iso-echo` for how much of the round trip is
// irreducible, and `nport-thread - nport-here` for what native dispatch costs
// on top of it.
//
// Usage:
//   dart run benchmark/experiments/native_port_dispatch.dart [--samples=15]
//
// Build it AOT for figures comparable with shipped code.
@ffi.DefaultAsset('package:resqlite/src/native/resqlite_bindings.dart')
library;

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:resqlite/resqlite.dart' as resqlite;

@ffi.Native<ffi.IntPtr Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'resqlite_nport_init',
)
external int nportInit(ffi.Pointer<ffi.Void> data);

@ffi.Native<ffi.Void Function(ffi.Int64, ffi.Int64)>(
  symbol: 'resqlite_nport_post_here',
  isLeaf: true,
)
external void nportPostHere(int port, int value);

@ffi.Native<ffi.Int Function(ffi.Int)>(symbol: 'resqlite_nport_start')
external int nportStart(int threads);

@ffi.Native<ffi.Void Function()>(symbol: 'resqlite_nport_stop')
external void nportStop();

@ffi.Native<ffi.Void Function(ffi.Int)>(symbol: 'resqlite_nport_set_spin')
external void nportSetSpin(int budget);

@ffi.Native<ffi.Int Function(ffi.Int64, ffi.Int64)>(
  symbol: 'resqlite_nport_echo',
  isLeaf: true,
)
external int nportEcho(int port, int value);

@ffi.Native<ffi.Int Function(ffi.Int)>(symbol: 'resqlite_nport_prepare_bytes')
external int nportPrepareBytes(int nbytes);

@ffi.Native<ffi.Int Function(ffi.Int64, ffi.Int)>(
  symbol: 'resqlite_nport_bytes',
  isLeaf: true,
)
external int nportBytes(int port, int nbytes);

@ffi.Native<ffi.Int Function(ffi.Int64, ffi.Int)>(
  symbol: 'resqlite_nport_bytes_nocopy',
  isLeaf: true,
)
external int nportBytesNoCopy(int port, int nbytes);

@ffi.Native<
  ffi.Int Function(ffi.Int64, ffi.Pointer<ffi.Void>, ffi.Int, ffi.Pointer<Utf8>)
>(symbol: 'resqlite_nport_query', isLeaf: true)
external int nportQuery(
  int port,
  ffi.Pointer<ffi.Void> db,
  int readerId,
  ffi.Pointer<Utf8> sql,
);

const _iterations = 2000;
const _warmup = 500;

/// Shaped like `SelectRequest`: what the pool actually hands a worker.
final class _Request {
  _Request(this.sql, this.parameters);
  final String sql;
  final List<Object?> parameters;
  final int? traceCorrelationId = null;
  int rowHint = 0;
  int initialRowHint = 0;
}

/// A persistent worker isolate that echoes whatever it is sent, so the lane
/// measures the transport and nothing else.
Future<(SendPort, RawReceivePort)> _spawnEcho() async {
  final ready = Completer<SendPort>.sync();
  final replies = RawReceivePort();
  late final void Function(Object?) deliver;
  replies.handler = (Object? msg) {
    if (msg is SendPort) {
      ready.complete(msg);
      return;
    }
    deliver(msg);
  };
  // The handler is reassigned per lane below; this indirection keeps the port
  // (and therefore the isolate) alive across both isolate lanes.
  deliver = (_) {};
  await Isolate.spawn(_echoEntry, replies.sendPort);
  return (await ready.future, replies);
}

const _resultMarker = 'result';
const _bytesMarker = 'bytes';
const _bytesHeapMarker = 'bytes-heap';

/// Payload size for the two bytes lanes: near the middle of what `selectBytes`
/// carries in the release suite's large-payload lane (exp 175).
const _payloadBytes = 256 * 1024;

/// A point read's reply, in the envelope `_WorkerSlot` receives: one row of six
/// cells plus its column names, and the `(result, sacrificed, error)` record.
final _result = (
  <List<Object?>>[
    <Object?>[1, 'Widget', 19.99, 'A short description', 1, 1735689600000],
  ],
  <String>['id', 'name', 'price', 'description', 'in_stock', 'created_at'],
  false,
  null,
);

/// Stands in for the view over a reader's `json_buf` that `selectBytes` sends:
/// a view over malloc'd memory, not a heap list, because the VM's message copy
/// treats external typed data differently and the whole point is to match what
/// the shipped path actually hands to `SendPort.send`.
final _payload = malloc<ffi.Uint8>(_payloadBytes).asTypedList(_payloadBytes);

/// The same bytes as an ordinary heap list, so the two `iso-bytes` lanes differ
/// only in how the payload is backed.
final _heapPayload = Uint8List(_payloadBytes);

void _echoEntry(SendPort reply) {
  final commands = RawReceivePort();
  commands.handler = (Object? msg) {
    if (msg == null) {
      commands.close();
      return;
    }
    if (msg == _bytesMarker) {
      reply.send(_payload);
      return;
    }
    if (msg == _bytesHeapMarker) {
      reply.send(_heapPayload);
      return;
    }
    if (msg == _resultMarker) {
      // A point read's reply shape, built once so the lane times the transfer
      // and not the decode.
      reply.send(_result);
      return;
    }
    if (msg is _Request) {
      // rowHint == -1 is the `iso-full` lane: object out, result shape back.
      reply.send(msg.rowHint == -1 ? _result : msg.rowHint);
      return;
    }
    // Reply with an int otherwise: the candidate's completion is a scalar
    // token, so the return leg is held constant across the dispatch lanes.
    reply.send(msg);
  };
  reply.send(commands.sendPort);
}

typedef _Lane = Future<int> Function(int n);

Future<int> _runIsolateLane(
  SendPort commands,
  RawReceivePort replies,
  int n,
  String shape,
) async {
  var accumulator = 0;
  Completer<Object?>? pending;
  replies.handler = (Object? msg) => pending!.complete(msg);
  for (var i = 0; i < n; i++) {
    final completer = pending = Completer<Object?>.sync();
    commands.send(switch (shape) {
      'echo' => i,
      'request' || 'full' => _Request(
        'SELECT * FROM products WHERE id = ?',
        <Object?>[i],
      )..rowHint = shape == 'full' ? -1 : i,
      'bytes' => _bytesMarker,
      'bytes-heap' => _bytesHeapMarker,
      _ => _resultMarker,
    });
    final reply = await completer.future;
    accumulator += reply is int ? reply : 1;
  }
  return accumulator;
}

Future<int> _runNativeBytesLane(
  RawReceivePort port,
  int n, {
  bool copy = true,
}) async {
  var accumulator = 0;
  Completer<Object?>? pending;
  port.handler = (Object? msg) => pending!.complete(msg);
  final nativePort = port.sendPort.nativePort;
  for (var i = 0; i < n; i++) {
    final completer = pending = Completer<Object?>.sync();
    final rc = copy
        ? nportBytes(nativePort, _payloadBytes)
        : nportBytesNoCopy(nativePort, _payloadBytes);
    if (rc != 0) {
      throw StateError('native dispatch queue full');
    }
    accumulator += ((await completer.future) as Uint8List).length;
  }
  return accumulator;
}

Future<int> _runNativeLane(
  RawReceivePort port,
  int n, {
  required bool viaThread,
}) async {
  var accumulator = 0;
  Completer<Object?>? pending;
  port.handler = (Object? msg) => pending!.complete(msg);
  final nativePort = port.sendPort.nativePort;
  for (var i = 0; i < n; i++) {
    final completer = pending = Completer<Object?>.sync();
    if (viaThread) {
      if (nportEcho(nativePort, i) != 0) {
        throw StateError('native dispatch queue full');
      }
    } else {
      nportPostHere(nativePort, i);
    }
    accumulator += (await completer.future) as int;
  }
  return accumulator;
}

const _createSql =
    'CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT NOT NULL, '
    'description TEXT NOT NULL, value REAL NOT NULL, category TEXT NOT NULL, '
    'created_at TEXT NOT NULL)';
const _insertSql =
    'INSERT INTO items(name, description, value, category, created_at) '
    'VALUES (?, ?, ?, ?, ?)';
const _selectSql = 'SELECT * FROM items';

Future<resqlite.Database> _seed(String dir, int rows) async {
  final db = await resqlite.Database.open('$dir/exp279.db');
  await db.execute(_createSql);
  for (var i = 0; i < rows; i++) {
    await db.execute(_insertSql, [
      'Item $i',
      'This is a description for item number $i with some padding text to '
          'simulate real data',
      i * 1.5,
      'category_${i % 10}',
      '2026-04-0${(i % 9) + 1}T12:00:00Z',
    ]);
  }
  return db;
}

Future<int> _runIsoQueryLane(resqlite.Database db, int n) async {
  var accumulator = 0;
  for (var i = 0; i < n; i++) {
    accumulator += (await db.selectBytes(_selectSql)).bytes.length;
  }
  return accumulator;
}

Future<int> _runNportQueryLane(
  RawReceivePort port,
  ffi.Pointer<ffi.Void> handle,
  ffi.Pointer<Utf8> sql,
  int n,
) async {
  var accumulator = 0;
  Completer<Object?>? pending;
  port.handler = (Object? msg) => pending!.complete(msg);
  final nativePort = port.sendPort.nativePort;
  for (var i = 0; i < n; i++) {
    final completer = pending = Completer<Object?>.sync();
    if (nportQuery(nativePort, handle, 0, sql) != 0) {
      throw StateError('native dispatch queue full');
    }
    final reply = await completer.future;
    if (reply is! Uint8List) throw StateError('query failed: rc=$reply');
    accumulator += reply.length;
  }
  return accumulator;
}

double _median(List<double> xs) {
  xs.sort();
  return xs[xs.length ~/ 2];
}

Future<void> _report(
  String lane,
  _Lane run,
  int samples,
  int iterations,
  int warmup,
) async {
  await run(warmup);
  final perCall = <double>[];
  for (var s = 0; s < samples; s++) {
    final stopwatch = Stopwatch()..start();
    await run(iterations);
    stopwatch.stop();
    perCall.add(stopwatch.elapsedMicroseconds / iterations);
  }
  final sorted = List<double>.from(perCall)..sort();
  print(
    'lane=$lane us_per_roundtrip=${_median(perCall).toStringAsFixed(3)} '
    'min=${sorted.first.toStringAsFixed(3)} '
    'max=${sorted.last.toStringAsFixed(3)}',
  );
}

Future<void> main(List<String> args) async {
  var samples = 15;
  var threads = 2;
  var rows = 1000;
  var iterations = _iterations;
  var warmup = _warmup;
  var lanes = <String>[
    'iso-echo',
    'iso-request',
    'nport-thread',
    'nport-spin',
    'nport-here',
    'iso-result',
    'iso-full',
    'iso-bytes',
    'nport-bytes',
    'nport-bytes-nocopy',
    'iso-bytes-heap',
  ];
  for (final arg in args) {
    if (arg.startsWith('--samples=')) {
      samples = int.parse(arg.substring('--samples='.length));
    } else if (arg.startsWith('--rows=')) {
      rows = int.parse(arg.substring('--rows='.length));
    } else if (arg.startsWith('--iterations=')) {
      iterations = int.parse(arg.substring('--iterations='.length));
      warmup = iterations ~/ 4;
    } else if (arg.startsWith('--threads=')) {
      threads = int.parse(arg.substring('--threads='.length));
    } else if (arg.startsWith('--lanes=')) {
      lanes = arg.substring('--lanes='.length).split(',');
    } else {
      throw ArgumentError('unknown argument: $arg');
    }
  }

  // Only the two end-to-end lanes need a database; opening one for the
  // mechanism lanes would put four reader isolates on the machine for nothing.
  final needsDb = lanes.contains('iso-query') || lanes.contains('nport-query');

  final rc = nportInit(ffi.NativeApi.initializeApiDLData);
  if (rc != 0) throw StateError('Dart_InitializeApiDL failed: $rc');
  if (nportStart(threads) < 1) {
    throw StateError('native dispatch pool failed to start');
  }
  if (nportPrepareBytes(_payloadBytes) != 0) {
    throw StateError('native payload allocation failed');
  }

  final (commands, replies) = await _spawnEcho();
  final nativePort = RawReceivePort();
  final sqlPtr = _selectSql.toNativeUtf8();
  Directory? tempDir;
  resqlite.Database? db;
  if (needsDb) {
    tempDir = await Directory.systemTemp.createTemp('exp279_');
    db = await _seed(tempDir.path, rows);
  }

  print('=== native-port dispatch price ===');
  print('iterations=$_iterations samples=$samples');
  for (final lane in lanes) {
    switch (lane) {
      case 'iso-echo':
        await _report(
          lane,
          (n) => _runIsolateLane(commands, replies, n, 'echo'),
          samples,
          iterations,
          warmup,
        );
      case 'iso-request':
        await _report(
          lane,
          (n) => _runIsolateLane(commands, replies, n, 'request'),
          samples,
          iterations,
          warmup,
        );
      case 'nport-thread':
        await _report(
          lane,
          (n) => _runNativeLane(nativePort, n, viaThread: true),
          samples,
          iterations,
          warmup,
        );
      case 'nport-spin':
        // Keep the worker threads hot for the duration of this lane only.
        nportSetSpin(200000);
        await _report(
          lane,
          (n) => _runNativeLane(nativePort, n, viaThread: true),
          samples,
          iterations,
          warmup,
        );
        nportSetSpin(0);
      case 'iso-result':
        await _report(
          lane,
          (n) => _runIsolateLane(commands, replies, n, 'result'),
          samples,
          iterations,
          warmup,
        );
      case 'iso-full':
        await _report(
          lane,
          (n) => _runIsolateLane(commands, replies, n, 'full'),
          samples,
          iterations,
          warmup,
        );
      case 'iso-bytes':
        await _report(
          lane,
          (n) => _runIsolateLane(commands, replies, n, 'bytes'),
          samples,
          iterations,
          warmup,
        );
      case 'iso-bytes-heap':
        await _report(
          lane,
          (n) => _runIsolateLane(commands, replies, n, 'bytes-heap'),
          samples,
          iterations,
          warmup,
        );
      case 'iso-query':
        await _report(
          lane,
          (n) => _runIsoQueryLane(db!, n),
          samples,
          iterations,
          warmup,
        );
      case 'nport-query':
        await _report(
          lane,
          (n) => _runNportQueryLane(nativePort, db!.handle.cast(), sqlPtr, n),
          samples,
          iterations,
          warmup,
        );
      case 'nport-bytes':
        await _report(
          lane,
          (n) => _runNativeBytesLane(nativePort, n),
          samples,
          iterations,
          warmup,
        );
      case 'nport-bytes-nocopy':
        await _report(
          lane,
          (n) => _runNativeBytesLane(nativePort, n, copy: false),
          samples,
          iterations,
          warmup,
        );
      case 'nport-here':
        await _report(
          lane,
          (n) => _runNativeLane(nativePort, n, viaThread: false),
          samples,
          iterations,
          warmup,
        );
      default:
        throw ArgumentError('unknown lane: $lane');
    }
  }

  commands.send(null);
  replies.close();
  nativePort.close();
  nportStop();
  calloc.free(sqlPtr);
  if (db != null) await db.close();
  if (tempDir != null) await tempDir.delete(recursive: true);
}
