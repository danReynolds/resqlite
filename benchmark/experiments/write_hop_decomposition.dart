// ignore_for_file: avoid_print
//
// [EXP-284] Where a standalone `db.execute()` actually spends its time.
//
// The release suite's `Single Inserts (100 sequential)` lane is the one public
// row where resqlite loses to a peer: 1.577 ms against raw `sqlite3`'s 0.934 ms
// for the same 100 inserts on the same schema, with the same journal mode and
// the same `synchronous` setting (benchmark/SCOPE.md). That is ~15.8 us per
// write against ~9.3 us, so ~6.4 us per write is resqlite's own overhead.
//
// Ten experiments have proposed a mechanism for that overhead (151, 159, 170,
// 171, 182, 197, 214, 215, 257, 271) and nine were rejected. None of them
// measured where the 6.4 us goes first. Exp 282 did exactly that for the *read*
// hop and its parting lesson was that an echo-isolate ladder cannot size a
// shipping message while a Stopwatch in the real path settles it in one run.
// This harness is that instrument for the write path.
//
// Parts:
//
//   e2e     `await db.execute(...)` sequentially, against the identical insert
//           run inline on the calling isolate through the same native entry
//           point the writer uses. `hop = writer - inline`, and `inline` is the
//           closest thing in this repo to what the `sqlite3` peer does.
//
//   insitu  the same sequential writes with the in-situ probes on. Main-side
//           slices are printed here; the writer-isolate slices are printed by
//           the writer itself when the database closes (`writerprobe ...`).
//
//   tax     the price of one `Stopwatch.elapsedTicks` read, so the probe's own
//           cost can be subtracted from the slices above rather than assumed
//           negligible.
//
//   floor   the same insert through a hand-rolled isolate writer that has none
//           of resqlite's machinery — no coalescing pump, no mutex, no
//           dependency harvest, no response object, no completer queue. Just
//           send the parameters, run `executeWrite` on the other side, send an
//           int back. Whatever this lane costs is the floor any isolate-backed
//           write path has to pay; whatever resqlite costs above it is the part
//           an experiment could hope to collect.
//
//   wake    what the synchronous `SendPort.send` call itself is buying. The
//           same message is sent to a target that is parked waiting for it and
//           to one that is already busy draining a queue, plus to a port in the
//           sending isolate where no isolate can need waking at all. If the
//           three agree, `send` is paying for the object graph; if the parked
//           lane is the expensive one, `send` is paying to wake a thread.
//
// Usage:
//   dart build cli --target=bin/exp284_probe.dart --output=<dir>
//   <dir>/bundle/bin/exp284_probe --part=all --samples=15 --writes=400

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/native/resqlite_bindings.dart'
    show executeWrite, resqliteClose, resqliteExec, resqliteOpen;
import 'package:resqlite/src/write_probe.dart';

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

/// Microseconds per write for one block of [writes] sequential `db.execute`s.
Future<double> _writerBlock(Database db, int writes) async {
  final sw = Stopwatch()..start();
  for (var i = 0; i < writes; i++) {
    final r = await db.execute(_insertSql, <Object?>['row', 1.5]);
    _sink += r.affectedRows;
  }
  sw.stop();
  return sw.elapsedMicroseconds / writes;
}

/// Microseconds per write for the same insert run inline on this isolate.
double _inlineBlock(ffi.Pointer<ffi.Void> handle, int writes) {
  final sw = Stopwatch()..start();
  for (var i = 0; i < writes; i++) {
    final r = executeWrite(handle, _insertSql, <Object?>['row', 1.5]);
    _sink += r.affectedRows;
  }
  sw.stop();
  return sw.elapsedMicroseconds / writes;
}

Future<void> _partE2e(
  Database db,
  ffi.Pointer<ffi.Void> handle,
  int writes,
  int samples,
) async {
  WriteProbe.enabled = false;
  await _writerBlock(db, writes);
  _inlineBlock(handle, writes);

  final writer = <double>[];
  final inline = <double>[];
  for (var s = 0; s < samples; s++) {
    if (s.isEven) {
      writer.add(await _writerBlock(db, writes));
      inline.add(_inlineBlock(handle, writes));
    } else {
      inline.add(_inlineBlock(handle, writes));
      writer.add(await _writerBlock(db, writes));
    }
  }
  final w = _median(writer);
  final i = _median(inline);
  print('lane=writer us_per_write=${w.toStringAsFixed(3)}');
  print('lane=inline us_per_write=${i.toStringAsFixed(3)}');
  print('hop us_per_write=${(w - i).toStringAsFixed(3)}');
}

Future<void> _partInsitu(Database db, int writes, int samples) async {
  WriteProbe.enabled = true;
  // Warm, then measure: the accumulators are reset after the warm block so the
  // reported slices come from steady state.
  await _writerBlock(db, writes);
  WriteProbe.reset();

  final totals = <double>[];
  for (var s = 0; s < samples; s++) {
    totals.add(await _writerBlock(db, writes));
  }
  final freq = WriteProbe.clock.frequency;
  double us(int ticks) => ticks * 1e6 / freq / WriteProbe.count;
  print(
    'mainprobe n=${WriteProbe.count} '
    'enqueue=${us(WriteProbe.enqueueTicks).toStringAsFixed(3)} '
    'build=${us(WriteProbe.buildTicks).toStringAsFixed(3)} '
    'send=${us(WriteProbe.sendTicks).toStringAsFixed(3)} '
    'away=${us(WriteProbe.awayTicks).toStringAsFixed(3)} '
    'finish=${us(WriteProbe.finishTicks).toStringAsFixed(3)}',
  );
  print(
    'insitu us_per_write=${_median(totals).toStringAsFixed(3)} '
    'probed=true',
  );
  WriteProbe.enabled = false;
}

void _partTax(int iterations, int samples) {
  final clock = WriteProbe.clock;
  final ns = <double>[];
  for (var s = 0; s < samples + 3; s++) {
    final sw = Stopwatch()..start();
    var acc = 0;
    for (var i = 0; i < iterations; i++) {
      acc += clock.elapsedTicks;
    }
    sw.stop();
    _sink += acc & 1;
    if (s >= 3) ns.add(sw.elapsedMicroseconds * 1000 / iterations);
  }
  print('lane=clock-read ns_per_call=${_median(ns).toStringAsFixed(1)}');
}

/// Message shape matching what a standalone write actually sends: a SQL
/// string, a two-slot parameter list, and a nullable correlation id.
final class _ReqLike {
  _ReqLike(this.sql, this.params, this.correlationId);
  final String sql;
  final List<Object?> params;
  final int? correlationId;
}

void _wakeEcho(List<Object> args) {
  final replyTo = args[0] as SendPort;
  final port = RawReceivePort();
  replyTo.send(port.sendPort);
  port.handler = (Object? m) {
    if (m == null) {
      port.close();
      return;
    }
    // Reply only when asked to, so the busy lane can queue without a round
    // trip per message.
    if (m is int && m == -1) replyTo.send(0);
  };
}

Future<void> _partWake(int iterations, int samples) async {
  final handshake = RawReceivePort();
  final ready = Completer<SendPort>();
  final replies = <Completer<void>>[];
  handshake.handler = (Object? m) {
    if (m is SendPort) {
      ready.complete(m);
    } else if (replies.isNotEmpty) {
      replies.removeAt(0).complete();
    }
  };
  await Isolate.spawn(_wakeEcho, <Object>[handshake.sendPort]);
  final target = await ready.future;

  final clock = WriteProbe.clock;
  final local = RawReceivePort();
  local.handler = (Object? m) {};
  final localPort = local.sendPort;

  _ReqLike req() => _ReqLike(_insertSql, <Object?>['row', 1.5], null);

  // Parked target: one message, then wait for its reply, so the isolate is
  // asleep again before the next send.
  Future<double> parked() async {
    var ticks = 0;
    for (var i = 0; i < iterations; i++) {
      final m = req();
      final t0 = clock.elapsedTicks;
      target.send(m);
      ticks += clock.elapsedTicks - t0;
      final c = Completer<void>();
      replies.add(c);
      target.send(-1);
      await c.future;
    }
    return ticks * 1e6 / clock.frequency / iterations;
  }

  // Busy target: a backlog is already queued, so the receiver is running.
  Future<double> busy() async {
    var ticks = 0;
    for (var i = 0; i < iterations; i++) {
      target.send(req());
    }
    for (var i = 0; i < iterations; i++) {
      final m = req();
      final t0 = clock.elapsedTicks;
      target.send(m);
      ticks += clock.elapsedTicks - t0;
    }
    final c = Completer<void>();
    replies.add(c);
    target.send(-1);
    await c.future;
    return ticks * 1e6 / clock.frequency / iterations;
  }

  // Same-isolate port: the graph copy happens, no isolate can need waking.
  double self() {
    var ticks = 0;
    for (var i = 0; i < iterations; i++) {
      final m = req();
      final t0 = clock.elapsedTicks;
      localPort.send(m);
      ticks += clock.elapsedTicks - t0;
    }
    return ticks * 1e6 / clock.frequency / iterations;
  }

  // Warm.
  await parked();
  await busy();
  self();

  final p = <double>[], b = <double>[], sf = <double>[];
  for (var s = 0; s < samples; s++) {
    p.add(await parked());
    b.add(await busy());
    sf.add(self());
  }
  print('lane=send-parked us_per_send=${_median(p).toStringAsFixed(3)}');
  print('lane=send-busy us_per_send=${_median(b).toStringAsFixed(3)}');
  print('lane=send-self us_per_send=${_median(sf).toStringAsFixed(3)}');

  target.send(null);
  local.close();
  handshake.close();
}

void _floorWorker(List<Object> args) {
  final replyTo = args[0] as SendPort;
  final path = args[1] as String;
  final port = RawReceivePort();
  replyTo.send(port.sendPort);

  final pathUtf8 = path.toNativeUtf8();
  final keyUtf8 = ''.toNativeUtf8();
  final handle = resqliteOpen(pathUtf8, 1, keyUtf8);
  calloc.free(pathUtf8);
  calloc.free(keyUtf8);

  final clock = Stopwatch()..start();
  var ticks = 0;
  var count = 0;

  port.handler = (Object? m) {
    if (m == null) {
      print('floorworker n=$count sqlite=$ticks freq=${clock.frequency}');
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
  };
}

Future<void> _partFloor(String dir, int writes, int samples) async {
  final path = '$dir/floor.db';
  final pathUtf8 = path.toNativeUtf8();
  final keyUtf8 = ''.toNativeUtf8();
  final setup = resqliteOpen(pathUtf8, 1, keyUtf8);
  calloc.free(pathUtf8);
  calloc.free(keyUtf8);
  for (final sql in <String>['PRAGMA journal_mode=WAL', _createSql]) {
    final n = sql.toNativeUtf8();
    resqliteExec(setup, n.cast());
    calloc.free(n);
  }
  resqliteClose(setup);

  final handshake = RawReceivePort();
  final ready = Completer<SendPort>();
  Completer<void>? pending;
  final finished = Completer<void>();
  handshake.handler = (Object? m) {
    if (m is SendPort) {
      ready.complete(m);
    } else if (m == 'done') {
      finished.complete();
    } else {
      pending!.complete();
    }
  };
  await Isolate.spawn(_floorWorker, <Object>[handshake.sendPort, path]);
  final target = await ready.future;

  Future<double> block() async {
    final sw = Stopwatch()..start();
    for (var i = 0; i < writes; i++) {
      final c = Completer<void>();
      pending = c;
      target.send(<Object?>['row', 1.5]);
      await c.future;
    }
    sw.stop();
    return sw.elapsedMicroseconds / writes;
  }

  await block();
  final xs = <double>[];
  for (var s = 0; s < samples; s++) {
    xs.add(await block());
  }
  print('lane=floor-hop us_per_write=${_median(xs).toStringAsFixed(3)}');

  target.send(null);
  await finished.future;
  handshake.close();
}

Future<void> main(List<String> args) async {
  var part = 'all';
  var samples = 15;
  var writes = 400;
  for (final a in args) {
    if (a.startsWith('--part=')) part = a.substring(7);
    if (a.startsWith('--samples=')) samples = int.parse(a.substring(10));
    if (a.startsWith('--writes=')) writes = int.parse(a.substring(9));
  }

  if (part == 'tax' || part == 'all') {
    _partTax(200000, samples);
  }
  if (part == 'tax') return;

  if (part == 'wake' || part == 'all') {
    await _partWake(2000, samples);
  }
  if (part == 'wake') return;

  final tmp = await Directory.systemTemp.createTemp('resqlite-exp284-');
  final path = '${tmp.path}/d.db';

  final pathUtf8 = path.toNativeUtf8();
  final keyUtf8 = ''.toNativeUtf8();
  final handle = resqliteOpen(pathUtf8, 1, keyUtf8);
  calloc.free(pathUtf8);
  calloc.free(keyUtf8);
  if (handle == ffi.nullptr) throw StateError('open failed');

  void exec(String sql) {
    final s = sql.toNativeUtf8();
    final rc = resqliteExec(handle, s.cast());
    calloc.free(s);
    if (rc != 0) throw StateError('exec rc=$rc: $sql');
  }

  exec('PRAGMA journal_mode=WAL');
  exec(_createSql);

  if (part == 'floor' || part == 'all') {
    await _partFloor(tmp.path, writes, samples);
  }

  final db = await Database.open(path);
  if (part == 'e2e' || part == 'all') {
    await _partE2e(db, handle, writes, samples);
  }
  if (part == 'insitu' || part == 'all') {
    await _partInsitu(db, writes, samples);
  }
  await db.close();

  resqliteClose(handle);
  await tmp.delete(recursive: true);
  if (_sink == -1) print(_sink);
}
