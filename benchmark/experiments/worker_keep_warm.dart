// ignore_for_file: avoid_print
//
// [EXP-285] What a parked worker isolate costs, and whether keeping it awake
// buys any of it back.
//
// Exp 284 priced the write hop and found that 5.30 us of the 6.28 us gap
// between `await db.execute(...)` and the identical `executeWrite` run inline
// is the isolate boundary itself. Inside that boundary it measured something
// nobody had looked at: the *same* C call costs 7.612 us on a running isolate
// and 9.380 us on a worker that was parked until the message arrived. About
// 1.8 us of every write is the woken side running cold.
//
// This harness asks whether that 1.8 us is the VM parking the worker's thread
// -- in which case an isolate that never runs out of work never pays it -- or
// residency the wake destroys regardless.
//
// Lanes, all against the same hand-rolled isolate writer exp 284 used as its
// floor (no coalescing pump, no mutex, no dependency harvest, no response
// object; send two parameters, run `executeWrite`, send an int back):
//
//   cold    the worker as written: handle the message, return to the event
//           loop, park until the next one.
//
//   timer   the same worker plus a self-rescheduling zero-duration `Timer`
//           that runs for a bounded window after each request, so the isolate
//           always has a runnable event and the VM never parks its thread.
//           Timers rather than microtasks: a microtask loop would starve the
//           receive port and the request would never be delivered.
//
//   self    the same idea through a cheaper primitive: the worker sends a
//           token to its own receive port instead of scheduling a timer.
//           Tokens and requests share one FIFO queue, so a request that
//           arrives mid-spin waits behind at most one token turn.
//
//   both    `self` on the worker and the same token loop on the calling
//           isolate, which parks awaiting the reply exactly as the worker
//           parks awaiting the request. Two parked sides means two wakes per
//           write, so this lane is the one that prices the whole boundary as
//           scheduling rather than transport.
//
//   inline  the identical `executeWrite` on the calling isolate, the reference
//           both worker lanes are cold against.
//
//   e2e     the shippable half, in the shipping path: two real `Database`s in
//           one process, one whose writer isolate runs the `self` token loop
//           and one whose writer parks as it does on `main`, alternating
//           blocks of `await db.execute(...)`. The floor lanes above answer
//           what the mechanism does; this lane answers what resqlite gets.
//
// Each worker times its own `executeWrite` calls, so the cold tax is measured
// where it lands rather than inferred from the round trip. Process CPU time is
// read through `getrusage` around each block, because the whole question for
// the warm lane is what the wall-clock saving costs in burnt core.
//
// AOT (`dart compile exe` cannot resolve the native asset):
//
//   cp benchmark/experiments/worker_keep_warm.dart bin/exp285_probe.dart
//   dart build cli --target=bin/exp285_probe.dart --output=<dir>
//   <dir>/bundle/bin/exp285_probe --part=all --samples=15 --writes=400

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/native/resqlite_bindings.dart'
    show executeWrite, resqliteClose, resqliteExec, resqliteOpen;
import 'package:resqlite/src/writer/writer.dart' show Writer;

const _createSql =
    'CREATE TABLE IF NOT EXISTS t(id INTEGER PRIMARY KEY, name TEXT NOT NULL, '
    'value REAL NOT NULL)';
const _insertSql = 'INSERT INTO t(name, value) VALUES (?, ?)';

int _sink = 0;

double _median(List<double> xs) {
  final s = List<double>.of(xs)..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

// ---------------------------------------------------------------------------
// Process CPU time. The warm lane's entire cost is burnt core, so it has to be
// measured rather than argued about.
// ---------------------------------------------------------------------------

final class _RUsage extends ffi.Struct {
  @ffi.Int64()
  external int utimeSec;
  @ffi.Int64()
  external int utimeUsec;
  @ffi.Int64()
  external int stimeSec;
  @ffi.Int64()
  external int stimeUsec;
  // The remaining ru_* longs are not read; the struct only needs to be large
  // enough for the kernel to fill.
  @ffi.Array<ffi.Int64>(28)
  external ffi.Array<ffi.Int64> rest;
}

typedef _GetrusageNative = ffi.Int32 Function(ffi.Int32, ffi.Pointer<_RUsage>);
typedef _GetrusageDart = int Function(int, ffi.Pointer<_RUsage>);

final _getrusage = ffi.DynamicLibrary.process()
    .lookupFunction<_GetrusageNative, _GetrusageDart>('getrusage');
final ffi.Pointer<_RUsage> _rusageBuf = calloc<_RUsage>();

/// Whole-process CPU (user + system) in microseconds.
double _cpuMicros() {
  if (_getrusage(0, _rusageBuf) != 0) return 0;
  final r = _rusageBuf.ref;
  return (r.utimeSec + r.stimeSec) * 1e6 + r.utimeUsec + r.stimeUsec;
}

// ---------------------------------------------------------------------------
// The worker.
// ---------------------------------------------------------------------------

/// Token the worker sends to its own port to stay runnable. Requests are
/// `List<Object?>` and shutdown is `null`, so this type is unreachable from
/// the workload and the handler can never mistake one for the other.
final class _Tick {
  const _Tick();
}

/// Keeps the worker's event loop from running dry for a bounded window after
/// each request, so the VM never parks its thread between the requests of a
/// burst. Two primitives, because their cost per turn differs by an order of
/// magnitude: a zero-duration `Timer`, and a message the isolate sends to its
/// own receive port.
final class _KeepWarm {
  _KeepWarm(this.mode, this.windowTicks, this.clock, this.selfPort);

  /// `'timer'` or `'self'`.
  final String mode;
  final int windowTicks;
  final Stopwatch clock;
  final SendPort selfPort;

  bool _running = false;
  int _deadline = 0;
  int _spinStart = 0;
  int ticksSpun = 0;
  int spins = 0;

  /// Called after each request is handled.
  void touch() {
    _deadline = clock.elapsedTicks + windowTicks;
    if (_running) return;
    _running = true;
    _spinStart = clock.elapsedTicks;
    _schedule();
  }

  /// Called when a spin token comes back round.
  void tick() {
    final now = clock.elapsedTicks;
    if (now >= _deadline) {
      _running = false;
      ticksSpun += now - _spinStart;
      return;
    }
    spins++;
    _schedule();
  }

  void _schedule() {
    if (mode == 'timer') {
      Timer.run(tick);
    } else {
      selfPort.send(const _Tick());
    }
  }

  void stop() {
    _deadline = 0;
  }
}

void _floorWorker(List<Object> args) {
  final replyTo = args[0] as SendPort;
  final path = args[1] as String;
  final mode = args[2] as String;
  final warmMicros = args[3] as int;
  final port = RawReceivePort();
  replyTo.send(port.sendPort);

  final pathUtf8 = path.toNativeUtf8();
  final keyUtf8 = ''.toNativeUtf8();
  final handle = resqliteOpen(pathUtf8, 1, keyUtf8);
  calloc.free(pathUtf8);
  calloc.free(keyUtf8);

  final clock = Stopwatch()..start();
  final warm = mode == 'cold'
      ? null
      : _KeepWarm(
          mode,
          warmMicros * clock.frequency ~/ 1000000,
          clock,
          port.sendPort,
        );
  var ticks = 0;
  var count = 0;

  port.handler = (Object? m) {
    if (m is _Tick) {
      warm!.tick();
      return;
    }
    if (m == null) {
      warm?.stop();
      final us = ticks * 1e6 / clock.frequency;
      print(
        'worker mode=$mode window=${warmMicros}us n=$count '
        'sqlite_us_per_write='
        '${(us / count).toStringAsFixed(3)} '
        'spins=${warm?.spins ?? 0} '
        'spun_us=${((warm?.ticksSpun ?? 0) * 1e6 / clock.frequency).round()}',
      );
      resqliteClose(handle);
      port.close();
      replyTo.send('done');
      return;
    }
    final params = m as List<Object?>;
    final t0 = clock.elapsedTicks;
    final r = executeWrite(handle, _insertSql, params);
    ticks += clock.elapsedTicks - t0;
    count++;
    replyTo.send(r.affectedRows);
    warm?.touch();
  };
}

/// A spawned floor worker plus the plumbing to drive it one write at a time.
final class _Worker {
  _Worker(this.label, this.target, this._state);

  final String label;
  final SendPort target;
  final _WorkerState _state;

  Future<double> block(int writes, {_KeepWarm? mainWarm}) async {
    final sw = Stopwatch()..start();
    for (var i = 0; i < writes; i++) {
      final c = Completer<void>();
      _state.pending = c;
      target.send(<Object?>['row', 1.5]);
      mainWarm?.touch();
      await c.future;
    }
    sw.stop();
    mainWarm?.stop();
    return sw.elapsedMicroseconds / writes;
  }

  Future<void> shutdown() async {
    target.send(null);
    await _state.finished.future;
    _state.handshake.close();
  }
}

final class _WorkerState {
  _WorkerState(this.handshake);
  final RawReceivePort handshake;
  final Completer<void> finished = Completer<void>();
  Completer<void>? pending;
}

Future<_Worker> _spawnWorker(
  String label,
  String path,
  String mode,
  int warmMicros,
) async {
  final handshake = RawReceivePort();
  final state = _WorkerState(handshake);
  final ready = Completer<SendPort>();
  handshake.handler = (Object? m) {
    if (m is SendPort) {
      ready.complete(m);
    } else if (m == 'done') {
      state.finished.complete();
    } else {
      state.pending!.complete();
    }
  };
  await Isolate.spawn(
    _floorWorker,
    <Object>[handshake.sendPort, path, mode, warmMicros],
  );
  return _Worker(label, await ready.future, state);
}

// ---------------------------------------------------------------------------

ffi.Pointer<ffi.Void> _prepare(String path) {
  final pathUtf8 = path.toNativeUtf8();
  final keyUtf8 = ''.toNativeUtf8();
  final handle = resqliteOpen(pathUtf8, 1, keyUtf8);
  calloc.free(pathUtf8);
  calloc.free(keyUtf8);
  if (handle == ffi.nullptr) throw StateError('open failed: $path');
  for (final sql in <String>['PRAGMA journal_mode=WAL', _createSql]) {
    final n = sql.toNativeUtf8();
    final rc = resqliteExec(handle, n.cast());
    calloc.free(n);
    if (rc != 0) throw StateError('exec rc=$rc: $sql');
  }
  return handle;
}

double _inlineBlock(ffi.Pointer<ffi.Void> handle, int writes) {
  final sw = Stopwatch()..start();
  for (var i = 0; i < writes; i++) {
    final r = executeWrite(handle, _insertSql, <Object?>['row', 1.5]);
    _sink += r.affectedRows;
  }
  sw.stop();
  return sw.elapsedMicroseconds / writes;
}

/// Microseconds per write for one block of sequential `db.execute`s.
Future<double> _dbBlock(Database db, int writes) async {
  final sw = Stopwatch()..start();
  for (var i = 0; i < writes; i++) {
    final r = await db.execute(_insertSql, <Object?>['row', 1.5]);
    _sink += r.affectedRows;
  }
  sw.stop();
  return sw.elapsedMicroseconds / writes;
}

/// The shipping path: `db.execute` with the writer isolate parked between
/// requests, against the same call with the writer's token loop running.
Future<void> _partE2e(String dir, int writes, int samples, int warmMicros)
    async {
  // The writer isolate spawns lazily on the database's first write, not in
  // `Database.open`, so each handle has to be driven through one write while
  // the window it should capture is still set. Reading the two lanes' spawn
  // order the other way round is what inverted this lane's first result.
  Writer.debugKeepWarmMicros = 0;
  final plain = await Database.open('$dir/e2e-plain.db');
  await plain.execute(_createSql);
  Writer.debugKeepWarmMicros = warmMicros;
  final kept = await Database.open('$dir/e2e-warm.db');
  await kept.execute(_createSql);
  Writer.debugKeepWarmMicros = 0;

  await _dbBlock(plain, writes);
  await _dbBlock(kept, writes);

  final plainWall = <double>[], keptWall = <double>[];
  final plainCpu = <double>[], keptCpu = <double>[];
  for (var s = 0; s < samples; s++) {
    for (final first in <bool>[s.isEven, !s.isEven]) {
      final db = first ? plain : kept;
      final wall = first ? plainWall : keptWall;
      final cpu = first ? plainCpu : keptCpu;
      final c0 = _cpuMicros();
      wall.add(await _dbBlock(db, writes));
      cpu.add((_cpuMicros() - c0) / writes);
    }
  }

  print('lane=e2e-plain us_per_write=${_median(plainWall).toStringAsFixed(3)} '
      'cpu_us_per_write=${_median(plainCpu).toStringAsFixed(3)}');
  print('lane=e2e-warm us_per_write=${_median(keptWall).toStringAsFixed(3)} '
      'cpu_us_per_write=${_median(keptCpu).toStringAsFixed(3)}');

  await plain.close();
  await kept.close();
}

Future<void> main(List<String> args) async {
  var part = 'all';
  var samples = 15;
  var writes = 400;
  var warmMicros = 200;
  for (final a in args) {
    if (a.startsWith('--part=')) part = a.substring(7);
    if (a.startsWith('--samples=')) samples = int.parse(a.substring(10));
    if (a.startsWith('--writes=')) writes = int.parse(a.substring(9));
    if (a.startsWith('--warm-us=')) warmMicros = int.parse(a.substring(10));
  }

  final modes = <String>[
    for (final m in <String>['cold', 'timer', 'self', 'both'])
      if (part == 'all' || part == m) m,
  ];
  final wantInline = part == 'all' || part == 'inline';
  final wantE2e = part == 'all' || part == 'e2e';

  final tmp = await Directory.systemTemp.createTemp('resqlite-exp285-');
  for (final m in modes) {
    resqliteClose(_prepare('${tmp.path}/$m.db'));
  }
  final inlineHandle = _prepare('${tmp.path}/inline.db');

  final workers = <_Worker>[
    for (final m in modes)
      await _spawnWorker(
        m,
        '${tmp.path}/$m.db',
        // 'both' runs the same worker-side loop as 'self'; only the calling
        // isolate differs.
        m == 'both' ? 'self' : m,
        m == 'cold' ? 0 : warmMicros,
      ),
  ];

  // The calling isolate's own token loop, used by the 'both' lane.
  final mainClock = Stopwatch()..start();
  final mainPort = RawReceivePort();
  final mainWarm = _KeepWarm(
    'self',
    warmMicros * mainClock.frequency ~/ 1000000,
    mainClock,
    mainPort.sendPort,
  );
  mainPort.handler = (Object? m) => mainWarm.tick();

  // Warm up every lane that will be measured.
  for (final w in workers) {
    await w.block(writes, mainWarm: w.label == 'both' ? mainWarm : null);
  }
  if (wantInline) _inlineBlock(inlineHandle, writes);

  final wall = <String, List<double>>{for (final m in modes) m: <double>[]};
  final cpu = <String, List<double>>{for (final m in modes) m: <double>[]};
  final inlineWall = <double>[];

  for (var s = 0; s < samples; s++) {
    // Rotate the lane order every sample so no lane always follows the same
    // predecessor's tail state.
    for (var k = 0; k < workers.length; k++) {
      final w = workers[(k + s) % workers.length];
      final c0 = _cpuMicros();
      wall[w.label]!.add(
        await w.block(writes, mainWarm: w.label == 'both' ? mainWarm : null),
      );
      cpu[w.label]!.add((_cpuMicros() - c0) / writes);
    }
    if (wantInline) inlineWall.add(_inlineBlock(inlineHandle, writes));
  }

  for (final m in modes) {
    print('lane=$m us_per_write=${_median(wall[m]!).toStringAsFixed(3)} '
        'cpu_us_per_write=${_median(cpu[m]!).toStringAsFixed(3)}');
  }
  if (wantInline) {
    print('lane=inline us_per_write=${_median(inlineWall).toStringAsFixed(3)}');
  }

  if (wantE2e) await _partE2e(tmp.path, writes, samples, warmMicros);

  print('main-warm spins=${mainWarm.spins} '
      'spun_us=${(mainWarm.ticksSpun * 1e6 / mainClock.frequency).round()}');

  for (final w in workers) {
    await w.shutdown();
  }
  mainPort.close();

  resqliteClose(inlineHandle);
  await tmp.delete(recursive: true);
  if (_sink == -1) print(_sink);
}
