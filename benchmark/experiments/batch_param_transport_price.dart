// ignore_for_file: avoid_print
//
// Prices the write path's *parameter transport* on its own, so a candidate
// that proposes to move parameter packing off the writer isolate can be
// costed before it is built ([EXP-280]).
//
// `db.executeBatch(sql, paramSets)` sends `List<List<Object?>>` to the writer
// isolate as a `BatchRequest`. The VM copies that object graph on the main
// isolate and rebuilds it on the writer, which then walks it a second time in
// `allocateBatchParams` to produce the native arena SQLite binds from. Exp 234
// named that main->writer hop "copy (1)" and removed it for a single large
// blob; nothing has ever measured what it costs for a whole parameter matrix.
//
// Lanes, per shape:
//
//   graph-floor   an int out to a persistent echo isolate and an int back.
//                 The round trip with no payload — the subtrahend.
//   graph-rt      the same round trip carrying the `List<List<Object?>>`
//                 matrix out and an int back. `graph-rt - graph-floor` is
//                 what the parameter graph copy costs, both halves of it.
//   send          `SendPort.send(matrix)` alone, not awaiting the reply. The
//                 serialize half, which runs on *this* isolate — the main
//                 isolate in production. This is the number a caller-side
//                 packer has to beat, not `copy`.
//   pack          `allocateBatchParams` + `freeParamBuffer` over the same
//                 matrix, on this isolate. What the writer pays today after
//                 the copy lands, and what a caller-side packer would pay
//                 instead of `send`.
//   e2e           the public `db.executeBatch` for the same shape. The
//                 denominator: transport is only worth attacking if it is a
//                 material fraction of this.
//
// Every lane awaits each iteration before starting the next, because a batch
// write does. Strings and numbers are *shared*, not copied, between isolates
// in one group (see `sacrificeSlotThreshold` in read_worker.dart), so
// `graph-rt` prices structure — the inner lists and their slots — which is
// exactly what a matrix of scalar parameters is.
//
//   dart run benchmark/experiments/batch_param_transport_price.dart
//
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/native/resqlite_bindings.dart';

const _warmup = 3;
const _samples = 11;

void main(List<String> args) async {
  final shapes = <_Shape>[
    // The release suite's Wide Batch Insert lane.
    _Shape('10k x 20 mixed', rows: 10000, kind: _Kind.mixed, cols: 20),
    // The Batch Insert (10000 rows) lane's shape.
    _Shape('10k x 4 ascii', rows: 10000, kind: _Kind.ascii, cols: 4),
    // Numeric only: the cheapest possible per-cell pack, so the copy's share
    // is at its largest here if the copy is what dominates.
    _Shape('10k x 8 int', rows: 10000, kind: _Kind.int64, cols: 8),
    // A small batch, where any fixed per-request cost dominates.
    _Shape('100 x 8 mixed', rows: 100, kind: _Kind.mixed, cols: 8),
  ];

  final echo = await _EchoWorker.spawn();
  print('batch parameter transport price — $_samples samples '
      'after $_warmup warmup\n');
  print('| Shape | graph-floor us | graph-rt us | copy us | send us '
      '| pack us | e2e us | copy/e2e | pack/send |');
  print('|---|---:|---:|---:|---:|---:|---:|---:|---:|');

  for (final shape in shapes) {
    final matrix = shape.build();
    final floor = await _median(() => echo.roundTrip(0));
    final rt = await _median(() => echo.roundTrip(matrix));
    final send = await _median(
      () => echo.sendOnly(matrix),
      reported: () => echo.lastSendUs,
    );
    final pack = await _median(() async {
      final buf = allocateBatchParams(matrix);
      freeParamBuffer(buf);
    });
    final e2e = await _measureEndToEnd(shape, matrix);

    final copy = rt - floor;
    print(
      '| ${shape.label} | ${floor.toStringAsFixed(1)} '
      '| ${rt.toStringAsFixed(1)} | ${copy.toStringAsFixed(1)} '
      '| ${send.toStringAsFixed(1)} '
      '| ${pack.toStringAsFixed(1)} | ${e2e.toStringAsFixed(1)} '
      '| ${(100 * copy / e2e).toStringAsFixed(1)}% '
      '| ${(pack / send).toStringAsFixed(2)}x |',
    );
  }

  echo.close();
}

Future<double> _measureEndToEnd(_Shape shape, List<List<Object?>> matrix) async {
  final dir = await Directory.systemTemp.createTemp('exp280_e2e_');
  final db = await Database.open('${dir.path}/bench.db');
  try {
    final cols = [for (var i = 0; i < shape.cols; i++) 'c$i'];
    await db.execute(
      'CREATE TABLE t (${cols.map((c) => '$c ${shape.sqlType}').join(', ')})',
    );
    final sql = 'INSERT INTO t (${cols.join(', ')}) '
        'VALUES (${List.filled(shape.cols, '?').join(', ')})';
    return await _median(() => db.executeBatch(sql, matrix));
  } finally {
    await db.close();
    await dir.delete(recursive: true);
  }
}

/// Median of [_samples] runs of [op]. When [reported] is given, the sample is
/// what it returns rather than the elapsed time of the whole call — for lanes
/// that must do teardown work inside `op` that is not part of the measurement.
Future<double> _median(
  Future<void> Function() op, {
  int Function()? reported,
}) async {
  for (var i = 0; i < _warmup; i++) {
    await op();
  }
  final us = <double>[];
  for (var i = 0; i < _samples; i++) {
    final sw = Stopwatch()..start();
    await op();
    sw.stop();
    us.add((reported?.call() ?? sw.elapsedMicroseconds).toDouble());
  }
  us.sort();
  return us[us.length ~/ 2];
}

enum _Kind { mixed, ascii, int64 }

final class _Shape {
  _Shape(this.label, {required this.rows, required this.kind, required this.cols});

  final String label;
  final int rows;
  final _Kind kind;
  final int cols;

  String get sqlType => kind == _Kind.int64 ? 'INTEGER' : 'TEXT';

  List<List<Object?>> build() => [
        for (var r = 0; r < rows; r++)
          [
            for (var c = 0; c < cols; c++)
              switch (kind) {
                _Kind.int64 => r * cols + c,
                _Kind.ascii => 'row${r}_col$c',
                _Kind.mixed =>
                  c.isEven ? r * cols + c : 'value_${r}_$c-payload',
              },
          ],
      ];
}

/// A persistent isolate that replies to whatever it is sent with an int, so a
/// round trip prices the outbound payload and nothing else.
final class _EchoWorker {
  _EchoWorker._(this._toWorker, this._fromWorker, this._isolate);

  final SendPort _toWorker;
  final ReceivePort _fromWorker;
  final Isolate _isolate;
  late final StreamIterator<Object?> _replies =
      StreamIterator<Object?>(_fromWorker);

  static Future<_EchoWorker> spawn() async {
    final handshake = ReceivePort();
    final isolate = await Isolate.spawn(_entry, handshake.sendPort);
    final it = StreamIterator<Object?>(handshake);
    await it.moveNext();
    final toWorker = it.current! as SendPort;
    final fromWorker = ReceivePort();
    toWorker.send(fromWorker.sendPort);
    await it.cancel();
    return _EchoWorker._(toWorker, fromWorker, isolate);
  }

  /// Microseconds spent inside the most recent [sendOnly].
  int lastSendUs = 0;

  Future<void> roundTrip(Object? payload) async {
    _toWorker.send(payload);
    await _replies.moveNext();
  }

  /// Times `SendPort.send` alone — the serialize half, paid by this isolate —
  /// then drains the reply outside the measurement so the worker stays in
  /// lockstep with the caller.
  Future<void> sendOnly(Object? payload) async {
    final sw = Stopwatch()..start();
    _toWorker.send(payload);
    sw.stop();
    lastSendUs = sw.elapsedMicroseconds;
    await _replies.moveNext();
  }

  void close() {
    _replies.cancel();
    _fromWorker.close();
    _isolate.kill(priority: Isolate.immediate);
  }

  static void _entry(SendPort handshake) {
    final inbox = ReceivePort();
    handshake.send(inbox.sendPort);
    SendPort? reply;
    inbox.listen((message) {
      if (reply == null) {
        reply = message as SendPort;
        return;
      }
      // Touch the graph so the copy cannot be elided, then reply with a
      // scalar: the reply direction must not carry the payload back.
      var n = 0;
      if (message is List) n = message.length;
      reply!.send(n);
    });
  }
}
