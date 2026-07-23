// EXP-243: isolate the TRANSFER trade for an aliased blob, removing SQLite-WAL
// noise. For one 300 KB buffer referenced N times in a message:
//   census : send the raw list -> graph copy copies the HEAP blob ONCE (slow
//            chunked heap-typed-data path) and aliases N times.
//   old    : send N TransferableTypedData -> N fast external memcpys.
// The peer's premise was "graph copy once is cheaper." But a large HEAP blob's
// graph copy hits the slow path, while external copies are fast — so at low N
// old can be faster in WALL even though it uses N buffers of external memory.
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

const _size = 300 * 1024;
const _rt = 300;

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

  Future<void> rt(Object p) async {
    final n = replies.stream.first;
    port.send(p);
    await n;
  }

  Future<double> bench(Object Function() make) async {
    for (var i = 0; i < 40; i++) {
      await rt(make());
    }
    final med = <double>[];
    for (var s = 0; s < 9; s++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < _rt; i++) {
        await rt(make());
      }
      sw.stop();
      med.add(sw.elapsedMicroseconds / _rt);
    }
    med.sort();
    return med[med.length ~/ 2];
  }

  final blob = Uint8List.fromList(List.generate(_size, (i) => i & 0xFF));

  print('300 KB buffer referenced N times — transfer round-trip µs');
  print('| N | census (1 graph copy) | old (N TTD) | table (1 TTD ×N) |');
  print('|---|---:|---:|---:|');
  for (final n in [1, 2, 4, 8, 32]) {
    final census = await bench(() => ['c', [for (var i = 0; i < n; i++) blob]]);
    final old = await bench(() => [
          'o',
          [for (var i = 0; i < n; i++) TransferableTypedData.fromList([blob])],
        ]);
    // Table protocol: ONE ttd, referenced N times (graph copier sends it once
    // by identity); receiver materializes the unique ttd once and substitutes.
    final table = await bench(() {
      final ttd = TransferableTypedData.fromList([blob]);
      return ['tab', [for (var i = 0; i < n; i++) ttd]];
    });
    print('| $n | ${census.toStringAsFixed(1)} | ${old.toStringAsFixed(1)} '
        '| ${table.toStringAsFixed(1)} |');
  }
  port.send(['stop']);
  rp.close();
  await replies.close();
}

Object? _sink;
void _worker(SendPort main) {
  final port = ReceivePort();
  main.send(port.sendPort);
  port.listen((m) {
    final list = m as List<Object?>;
    if (list[0] == 'stop') {
      port.close();
      return;
    }
    final items = list[1] as List;
    // Table-protocol receive: materialize each UNIQUE ttd exactly once (a
    // second materialize on the same object throws), substituting the result
    // for every reference. dedup by identity.
    final materialized = <TransferableTypedData, Uint8List>{};
    var fold = 0;
    for (final it in items) {
      final Uint8List b;
      if (it is TransferableTypedData) {
        b = materialized[it] ??= it.materialize().asUint8List();
      } else {
        b = it as Uint8List;
      }
      for (var i = 0; i < b.length; i += 512) {
        fold ^= b[i];
      }
    }
    _sink = fold;
    main.send(fold);
  });
}
