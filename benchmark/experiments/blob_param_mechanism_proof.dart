// Mechanism-proof harness for exp 234 — no resqlite imports, pure dart:isolate.
//
// The end-to-end A/B showed *that* TransferableTypedData wins at 256-512 KB;
// this harness proves *why*, by measuring each mechanism claim separately:
//
//   1. `SendPort.send([blob])` copies ON THE SENDER: send() is synchronous,
//      so its own wall time must scale linearly with blob size if (and only
//      if) the copy runs inside the call on the calling thread.
//   2. `SendPort.send(ttd)` is a pointer MOVE: its wall time must stay flat
//      across sizes.
//   3. `fromList` is the candidate's one copy: linear, comparable to a plain
//      memcpy (`Uint8List.fromList` is the heap-copy reference lane).
//   4. `materialize()` is a zero-copy view: flat across sizes (measured on
//      the worker, reported back).
//   5. Both receivers pay the same first-touch cost (reported back).
//
// GC-pressure mode (claim 6): `gc-burst-direct` / `gc-burst-ttd` fire 400
// sends of a 512 KB blob and exit; run each under `dart --disable-dart-dev
// --verbose_gc` and compare GC counts and pause totals. Direct sends allocate
// every payload on the shared GC heap; ttd payloads live in malloc'd external
// memory. The observed difference is mostly per-GC cost, not count — direct
// scavenges must evacuate live payloads, ttd collections are cheap ticks.
// (Real-path per-lane attribution: blob_param_gc_split.dart.)
//
//   dart benchmark/experiments/blob_param_mechanism_proof.dart
//   dart --disable-dart-dev --verbose_gc \
//       benchmark/experiments/blob_param_mechanism_proof.dart gc-burst-direct
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

const _sizes = <int>[64 * 1024, 256 * 1024, 1024 * 1024, 4 * 1024 * 1024];

int _itersFor(int size) => size >= 1024 * 1024 ? 40 : 150;

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first.startsWith('gc-burst')) {
    await _gcBurst(direct: args.first == 'gc-burst-direct');
    return;
  }
  await _mechanismTables();
}

// ---------------------------------------------------------------------------
// Worker
// ---------------------------------------------------------------------------

Object? sink; // keep-alive target so copies aren't optimized away

double _touchUs(Uint8List b) {
  final sw = Stopwatch()..start();
  var fold = 0;
  for (var i = 0; i < b.length; i += 512) {
    fold ^= b[i];
  }
  sw.stop();
  sink = fold;
  return sw.elapsedTicks * 1e6 / sw.frequency;
}

// Mirrors the real writer consumption path: allocateParams bulk-copies the
// param bytes into the native arena via setRange. The strided _touchUs loop
// is deliberately kept too (polymorphic per-element access), but this is the
// receive-side cost that actually matters for resqlite.
Uint8List _setRangeScratch = Uint8List(0);

double _setRangeUs(Uint8List b) {
  if (_setRangeScratch.length < b.length) {
    _setRangeScratch = Uint8List(b.length);
  }
  final sw = Stopwatch()..start();
  _setRangeScratch.setRange(0, b.length, b);
  sw.stop();
  return sw.elapsedTicks * 1e6 / sw.frequency;
}

void _worker(SendPort main) {
  final port = ReceivePort();
  main.send(port.sendPort);
  port.listen((msg) {
    final list = msg as List<Object?>;
    switch (list[0] as String) {
      case 'direct':
        final bytes = list[1] as Uint8List;
        main.send(['ack', -1.0, _touchUs(bytes), _setRangeUs(bytes)]);
      case 'ttd':
        final sw = Stopwatch()..start();
        final bytes =
            (list[1] as TransferableTypedData).materialize().asUint8List();
        sw.stop();
        final matUs = sw.elapsedTicks * 1e6 / sw.frequency;
        main.send(['ack', matUs, _touchUs(bytes), _setRangeUs(bytes)]);
      case 'stop':
        port.close();
    }
  });
}

// ---------------------------------------------------------------------------
// Part A/B: per-call costs
// ---------------------------------------------------------------------------

final class _WorkerHandle {
  _WorkerHandle(this.port, this.acks, this.rp);
  final SendPort port;
  final Stream<List<Object?>> acks;
  final ReceivePort rp;

  // Close the main-isolate port so the process can exit; without this the
  // open ReceivePort keeps the VM alive after the tables are printed.
  void dispose() {
    port.send(['stop']);
    rp.close();
  }
}

Future<_WorkerHandle> _spawnWorker() async {
  final rp = ReceivePort();
  final ready = Completer<SendPort>();
  final acks = StreamController<List<Object?>>.broadcast();
  rp.listen((msg) {
    if (msg is SendPort) {
      ready.complete(msg);
    } else {
      acks.add(msg as List<Object?>);
    }
  });
  await Isolate.spawn(_worker, rp.sendPort);
  return _WorkerHandle(await ready.future, acks.stream, rp);
}

double _median(List<double> xs) {
  xs.sort();
  return xs[xs.length ~/ 2];
}

Future<void> _mechanismTables() async {
  final w = await _spawnWorker();

  stdout.writeln('per-call costs, median µs (main-isolate columns are the '
      'synchronous wall of that single call)\n');
  stdout.writeln('| Size | heapCopy | fromList | send(blob) | send(ttd) '
      '| materialize | touch(direct) | touch(ttd) '
      '| setRange(direct) | setRange(ttd) |');
  stdout.writeln('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|');

  for (final size in _sizes) {
    final iters = _itersFor(size);
    final blob = _makeBlob(size);

    // Warmup all paths (JIT).
    for (var i = 0; i < 10; i++) {
      sink = Uint8List.fromList(blob);
      w.port.send(['direct', blob]);
      w.port.send(['ttd', TransferableTypedData.fromList([blob])]);
    }
    await w.acks.take(20).drain<void>();

    // Reference: plain Dart-heap alloc+memcpy of the same bytes.
    final heapCopy = <double>[];
    for (var i = 0; i < iters; i++) {
      final sw = Stopwatch()..start();
      sink = Uint8List.fromList(blob);
      sw.stop();
      heapCopy.add(sw.elapsedTicks * 1e6 / sw.frequency);
    }

    // Candidate copy: fromList (keep the ttds — they feed the send lane).
    final fromList = <double>[];
    final ttds = <TransferableTypedData>[];
    for (var i = 0; i < iters; i++) {
      final sw = Stopwatch()..start();
      final t = TransferableTypedData.fromList([blob]);
      sw.stop();
      fromList.add(sw.elapsedTicks * 1e6 / sw.frequency);
      ttds.add(t);
    }

    // Baseline transport: synchronous wall of send([blob]) itself.
    final sendDirect = <double>[];
    for (var i = 0; i < iters; i++) {
      final sw = Stopwatch()..start();
      w.port.send(['direct', blob]);
      sw.stop();
      sendDirect.add(sw.elapsedTicks * 1e6 / sw.frequency);
      if (i % 16 == 15) await w.acks.take(16).drain<void>();
    }
    final directAcks = await w.acks.take(iters % 16).toList();

    // Candidate transport: synchronous wall of send(ttd) itself.
    final sendTtd = <double>[];
    final ttdAckFuture = w.acks.take(iters).toList();
    for (final t in ttds) {
      final sw = Stopwatch()..start();
      w.port.send(['ttd', t]);
      sw.stop();
      sendTtd.add(sw.elapsedTicks * 1e6 / sw.frequency);
    }
    final ttdAcks = await ttdAckFuture;

    final materialize = [for (final a in ttdAcks) a[1] as double];
    final touchTtd = [for (final a in ttdAcks) a[2] as double];
    final touchDirect = [for (final a in directAcks) a[2] as double];
    final setRangeTtd = [for (final a in ttdAcks) a[3] as double];
    final setRangeDirect = [for (final a in directAcks) a[3] as double];

    stdout.writeln('| ${_sizeLabel(size)} '
        '| ${_median(heapCopy).toStringAsFixed(1)} '
        '| ${_median(fromList).toStringAsFixed(1)} '
        '| ${_median(sendDirect).toStringAsFixed(1)} '
        '| ${_median(sendTtd).toStringAsFixed(1)} '
        '| ${_median(materialize).toStringAsFixed(1)} '
        '| ${touchDirect.isEmpty ? '-' : _median(touchDirect).toStringAsFixed(1)} '
        '| ${_median(touchTtd).toStringAsFixed(1)} '
        '| ${setRangeDirect.isEmpty ? '-' : _median(setRangeDirect).toStringAsFixed(1)} '
        '| ${_median(setRangeTtd).toStringAsFixed(1)} |');
  }

  w.dispose();
}

// ---------------------------------------------------------------------------
// GC burst mode
// ---------------------------------------------------------------------------

Future<void> _gcBurst({required bool direct}) async {
  final w = await _spawnWorker();
  final blob = _makeBlob(512 * 1024);
  const n = 400;
  var acked = 0;
  final done = Completer<void>();
  w.acks.listen((_) {
    if (++acked == n) done.complete();
  });
  for (var i = 0; i < n; i++) {
    if (direct) {
      w.port.send(['direct', blob]);
    } else {
      w.port.send(['ttd', TransferableTypedData.fromList([blob])]);
    }
    if (i % 16 == 15) await Future<void>.delayed(Duration.zero);
  }
  await done.future;
  w.dispose();
  stdout.writeln('gc-burst ${direct ? 'direct' : 'ttd'}: $n sends complete');
}

// ---------------------------------------------------------------------------

Uint8List _makeBlob(int size) {
  final b = Uint8List(size);
  for (var i = 0; i < size; i++) {
    b[i] = (i * 31 + 7) & 0xFF;
  }
  return b;
}

String _sizeLabel(int bytes) =>
    bytes >= 1024 * 1024 ? '${bytes ~/ (1024 * 1024)}MB' : '${bytes ~/ 1024}KB';
