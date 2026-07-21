// Focused transport microbenchmark for exp 234 — parameter-encoding-and-binding.
//
// The parameter-encoding direction's open question: "Are there remaining
// blob-heavy parameter shapes where encoding, not SQLite stepping, dominates?"
//
// A blob param on the write path is copied three times before it lands in a
// database page:
//   1. main -> writer isolate, when `SendPort.send(request)` copies the
//      request graph (including the Uint8List blob bytes) via the VM's
//      object-graph copy — one copy, on the sender, landing on the shared GC
//      heap (Dart SDK `runtime/vm/object_graph_copy.cc`; blobs too large for
//      the copier's fast-path new-space allocation redo the copy on a slow
//      path in 100 KB safepoint-polled chunks);
//   2. writer -> native param arena, in `allocateParams` (`view.setRange`);
//   3. arena -> SQLite b-tree page, inside `sqlite3_step`.
//
// This harness isolates hop (1): wrapping large blob params in
// `TransferableTypedData` replaces the graph copy with a `fromList` memcpy
// into malloc'd external memory plus a constant-time ownership move — same
// copy count, GC-invisible destination. exp 005 rejected a Dart *binary
// codec* for structured map *results*; it did not test raw `Uint8List`
// *parameter* transport, where there is nothing to encode — so this is a
// distinct question. (Per-claim attribution of where the costs actually
// live: blob_param_mechanism_proof.dart.)
//
// It measures, for a range of blob sizes, the main-side round-trip wall of:
//   (a) SendPort.send([blob])                 — the current mechanism
//   (b) SendPort.send(TransferableTypedData)  — candidate, worker materializes
// The worker touches every transferred byte (xor-fold) so the transfer cannot
// be optimized away and the receive-side cost of each mechanism is included.
//
// It also reports the isolated main-side cost of `TransferableTypedData.fromList`
// itself — the candidate's one copy; if it approached the round-trip cost the
// wrap would trade the send-copy for a fromList-copy and net nothing.
//
//   dart run benchmark/experiments/blob_param_transport_ab.dart
//
// Reports median us/round-trip per size for each mechanism, plus fromList cost.
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

const _sizes = <int>[
  4 * 1024,
  64 * 1024,
  256 * 1024,
  1024 * 1024,
  4 * 1024 * 1024,
];

const _roundTripsPerSample = 200;
const _samples = 11;
const _warmup = 40;

Future<void> main() async {
  final resultPort = ReceivePort();
  final ready = Completer<SendPort>();
  final replies = StreamController<int>.broadcast();
  resultPort.listen((msg) {
    if (msg is SendPort) {
      ready.complete(msg);
    } else if (msg is int) {
      replies.add(msg);
    }
  });

  await Isolate.spawn(_worker, resultPort.sendPort);
  final workerPort = await ready.future;

  // One outstanding round-trip at a time (mirrors the writer's serialized
  // request/reply protocol), so the wall we measure is a true round-trip.
  Future<void> roundTrip(Object? payload) async {
    final next = replies.stream.first;
    workerPort.send(payload);
    await next;
  }

  print('blob param transport A/B — '
      '$_roundTripsPerSample round-trips/sample, $_samples samples\n');
  print('| Size | send([blob]) us/rt | Transferable us/rt | Δ | fromList us |');
  print('|---|---:|---:|---:|---:|');

  for (final size in _sizes) {
    final blob = _makeBlob(size);

    // ---- Warmup both paths ----
    for (var i = 0; i < _warmup; i++) {
      await roundTrip(_wrapDirect(blob));
      await roundTrip(_wrapTransferable(blob));
    }

    // ---- (a) direct SendPort copy ----
    final directMedians = <double>[];
    for (var s = 0; s < _samples; s++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < _roundTripsPerSample; i++) {
        await roundTrip(_wrapDirect(blob));
      }
      sw.stop();
      directMedians.add(sw.elapsedMicroseconds / _roundTripsPerSample);
    }
    directMedians.sort();

    // ---- (b) TransferableTypedData ----
    final transMedians = <double>[];
    for (var s = 0; s < _samples; s++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < _roundTripsPerSample; i++) {
        await roundTrip(_wrapTransferable(blob));
      }
      sw.stop();
      transMedians.add(sw.elapsedMicroseconds / _roundTripsPerSample);
    }
    transMedians.sort();

    // ---- isolated fromList construction cost ----
    final fromListMedians = <double>[];
    for (var s = 0; s < _samples; s++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < _roundTripsPerSample; i++) {
        // fromList requires a fresh source each time in the real path (the
        // caller's blob is single-use per bind); reuse here is fine because
        // fromList does not neuter its source list.
        TransferableTypedData.fromList([blob]);
      }
      sw.stop();
      fromListMedians.add(sw.elapsedMicroseconds / _roundTripsPerSample);
    }
    fromListMedians.sort();

    final d = directMedians[directMedians.length ~/ 2];
    final t = transMedians[transMedians.length ~/ 2];
    final fl = fromListMedians[fromListMedians.length ~/ 2];
    final deltaPct = (t - d) / d * 100;
    print('| ${_sizeLabel(size)} '
        '| ${d.toStringAsFixed(2)} '
        '| ${t.toStringAsFixed(2)} '
        '| ${deltaPct >= 0 ? '+' : ''}${deltaPct.toStringAsFixed(1)}% '
        '| ${fl.toStringAsFixed(2)} |');
  }

  workerPort.send('stop');
  resultPort.close();
  await replies.close();
}

// Mirror how a param blob is actually delivered: inside a small request-like
// list, the way `ExecuteRequest(sql, parameters, ...)` carries it.
Object _wrapDirect(Uint8List blob) => <Object?>['INSERT', blob];

Object _wrapTransferable(Uint8List blob) =>
    <Object?>['INSERT', TransferableTypedData.fromList([blob])];

Uint8List _makeBlob(int size) {
  final b = Uint8List(size);
  for (var i = 0; i < size; i++) {
    b[i] = (i * 31 + 7) & 0xFF;
  }
  return b;
}

void _worker(SendPort main) {
  final port = ReceivePort();
  main.send(port.sendPort);
  port.listen((msg) {
    if (msg is String) {
      port.close();
      return;
    }
    final list = msg as List<Object?>;
    final payload = list[1];
    Uint8List bytes;
    if (payload is TransferableTypedData) {
      bytes = payload.materialize().asUint8List();
    } else {
      bytes = payload as Uint8List;
    }
    // Touch every byte so the transfer + any lazy materialization is real
    // and the receive-side read cost is charged to both mechanisms equally,
    // matching allocateParams' full copy of the payload.
    var fold = 0;
    for (var i = 0; i < bytes.length; i++) {
      fold ^= bytes[i];
    }
    main.send(fold);
  });
}

String _sizeLabel(int bytes) {
  if (bytes >= 1024 * 1024) return '${bytes ~/ (1024 * 1024)}MB';
  return '${bytes ~/ 1024}KB';
}
