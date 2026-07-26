// Confidence check for the selectBytes explanation: is sending a
// native-backed (external) Uint8List through SendPort cheaper than sending a
// heap Uint8List of the same size? If native-view send is faster/equal-and-
// efficient, that supports "selectBytes' external source already gets an
// efficient copy, so TTD is redundant."
//
//   native = malloc'd buffer viewed via asTypedList (like json_buf)
//   heap   = Uint8List.fromList (like a decoded blob param)
//   ttd    = TransferableTypedData wrapping the native view (the exp 242 cand)
import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const _sizes = [142 * 1024, 512 * 1024, 731 * 1024];
const _rt = 400;

Future<void> main() async {
  final rp = ReceivePort();
  final ready = Completer<SendPort>();
  final replies = StreamController<int>.broadcast();
  rp.listen((m) {
    if (m is SendPort) {
      ready.complete(m);
    } else {
      replies.add(m as int);
    }
  });
  await Isolate.spawn(_worker, rp.sendPort);
  final port = await ready.future;

  Future<void> roundTrip(Object payload) async {
    final next = replies.stream.first;
    port.send(payload);
    await next;
  }

  Future<double> bench(Object Function() make) async {
    for (var i = 0; i < 40; i++) {
      await roundTrip(make());
    }
    final med = <double>[];
    for (var s = 0; s < 9; s++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < _rt; i++) {
        await roundTrip(make());
      }
      sw.stop();
      med.add(sw.elapsedMicroseconds / _rt);
    }
    med.sort();
    return med[med.length ~/ 2];
  }

  // Pre-build ONE native view and ONE heap list per size, OUTSIDE the timed
  // loop, so we measure only the send round-trip (each send copies the same
  // pre-built payload). The ttd lane must rebuild (fromList is single-use once
  // sent) — so its number carries fromList cost, which is the honest cost of
  // the candidate anyway.
  print('| size | native-view send | heap send | ttd(native, incl fromList) |');
  print('|---|---:|---:|---:|');
  for (final size in _sizes) {
    final nativePtr = calloc<ffi.Uint8>(size);
    final nativeView = nativePtr.asTypedList(size);
    for (var i = 0; i < size; i += 64) {
      nativeView[i] = i & 0xFF;
    }
    final heap = Uint8List.fromList(nativeView);

    final nv = await bench(() => ['n', nativeView]); // reuse view, no rebuild
    final hp = await bench(() => ['h', heap]); // reuse heap list, no rebuild
    final td = await bench(
      () => [
        't',
        TransferableTypedData.fromList([nativeView]),
      ],
    );

    print(
      '| ${size ~/ 1024}KB | ${nv.toStringAsFixed(1)} '
      '| ${hp.toStringAsFixed(1)} | ${td.toStringAsFixed(1)} |',
    );
    calloc.free(nativePtr);
  }
  port.send(['stop']);
  rp.close();
  await replies.close();
}

void _worker(SendPort main) {
  final port = ReceivePort();
  main.send(port.sendPort);
  port.listen((m) {
    final list = m as List<Object?>;
    final kind = list[0] as String;
    if (kind == 'stop') {
      port.close();
      return;
    }
    Uint8List b;
    if (kind == 't') {
      b = (list[1] as TransferableTypedData).materialize().asUint8List();
    } else {
      b = list[1] as Uint8List;
    }
    var fold = 0;
    for (var i = 0; i < b.length; i += 512) {
      fold ^= b[i];
    }
    main.send(fold);
  });
}
