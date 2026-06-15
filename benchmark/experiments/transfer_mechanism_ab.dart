// exp 174 follow-up probe: is true zero-copy worth it over the one-copy send?
//
// `selectBytes` (exp 174) sends a Uint8List VIEW over the reader's native
// json_buf; SendPort copies it once into a stable Dart-owned buffer on main.
// The obvious "go further" idea is true zero-copy: malloc a FRESH native
// buffer per query, send only (address, len), and have main wrap it with a
// NativeFinalizer (GC frees the native memory) — zero bytes copied across
// the port. This harness measures whether that pays.
//
// A (current): worker reuses one native buffer (models json_buf), fills it
//   (production), sends a view -> SendPort copies len bytes -> main gets a
//   fresh Dart-heap Uint8List.
// B (zero-copy): worker mallocs a FRESH buffer per query, fills it, sends
//   (address, len) -> main wraps a view (no copy) and frees it. NOTE: this
//   frees explicitly (B's BEST case); the real design needs a NativeFinalizer,
//   which adds GC-timed native frees on top.
//
// Finding (651KB, load ~4): break-even, trending slightly worse for B — the
// saved memcpy is eaten by per-query malloc/free + page faults on the fresh
// buffer, and both paths allocate `len` anyway. The copy was never the
// bottleneck; exp 174's win was the eliminated respawn. Zero-copy might edge
// ahead only for very large payloads (>~10MB) where the fixed mmap cost
// amortizes — but the safety/complexity/GC-pressure downsides stand.
//
//   dart run benchmark/experiments/transfer_mechanism_ab.dart [bytes]
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

void _worker(SendPort toMain) {
  final inbox = ReceivePort();
  toMain.send(inbox.sendPort);
  Pointer<Uint8>? reused;
  inbox.listen((msg) {
    final (int mode, int len, SendPort reply) = msg as (int, int, SendPort);
    if (mode == 2) {
      if (reused != null) malloc.free(reused!);
      inbox.close();
      return;
    }
    if (mode == 0) {
      reused ??= malloc.allocate<Uint8>(len);
      reused!.asTypedList(len).fillRange(0, len, 0x41); // production
      reply.send(reused!.asTypedList(len)); // SendPort copies len bytes
    } else {
      final p = malloc.allocate<Uint8>(len); // fresh per query
      p.asTypedList(len).fillRange(0, len, 0x41);
      reply.send((p.address, len)); // address only
    }
  });
}

Future<void> main(List<String> args) async {
  final len = args.isNotEmpty ? int.parse(args.first) : 651781;
  const iters = 1500, rounds = 6, warm = 200;

  final from = ReceivePort();
  await Isolate.spawn(_worker, from.sendPort);
  late SendPort wp;
  Completer<Object?>? pending;
  from.listen((m) {
    if (m is SendPort) {
      wp = m;
      pending!.complete();
    } else {
      final c = pending!;
      pending = null;
      c.complete(m);
    }
  });
  pending = Completer();
  await pending!.future;

  Future<int> trip(int mode) async {
    pending = Completer<Object?>();
    wp.send((mode, len, from.sendPort));
    final r = await pending!.future;
    var s = 0;
    if (mode == 0) {
      final u = r as Uint8List;
      for (var i = 0; i < len; i += 4096) {
        s += u[i]; // touch one byte/page (models the caller using the bytes)
      }
    } else {
      final (int addr, int l) = r as (int, int);
      final p = Pointer<Uint8>.fromAddress(addr);
      final v = p.asTypedList(l);
      for (var i = 0; i < l; i += 4096) {
        s += v[i];
      }
      malloc.free(p); // explicit free (B best case; real B uses NativeFinalizer)
    }
    return s;
  }

  Future<double> bench(int mode) async {
    for (var i = 0; i < warm; i++) {
      await trip(mode);
    }
    final meds = <double>[];
    for (var r = 0; r < rounds; r++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < iters; i++) {
        await trip(mode);
      }
      sw.stop();
      meds.add(sw.elapsedMicroseconds / iters);
    }
    meds.sort();
    return meds[meds.length ~/ 2];
  }

  stdout.writeln('=== transfer mechanism A/B (${len}B payload, round-trip per query) ===');
  for (var pass = 1; pass <= 3; pass++) {
    final firstMode = pass.isOdd ? 0 : 1;
    final r1 = await bench(firstMode);
    final r2 = await bench(firstMode == 0 ? 1 : 0);
    final a = firstMode == 0 ? r1 : r2;
    final b = firstMode == 0 ? r2 : r1;
    stdout.writeln(
      'pass$pass  A(copy)=${a.toStringAsFixed(1)}us  '
      'B(zerocopy)=${b.toStringAsFixed(1)}us  B/A=${(b / a * 100).toStringAsFixed(0)}%',
    );
  }
  wp.send((2, 0, from.sendPort));
  from.close();
}
