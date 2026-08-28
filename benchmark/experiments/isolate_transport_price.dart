// ignore_for_file: avoid_print
//
// Prices resqlite's cross-isolate transport on its own, so a candidate that
// proposes to remove or replace part of it can be costed before it is built
// ([EXP-279]).
//
// Exp 265 measured the `select()` isolate round trip at 6.3 us of an 8.4 us
// canonical point read (claim 265.1) and every candidate since has tried to
// collect it: run the query on the caller (exps 265, 269), answer from a cache
// so no query runs at all (exp 270), reorder who gets the worker first (exp
// 275), strip the async frames in front of it (exp 278). All were rejected. In
// none of them was the 6.3 us ever broken down — it is the *difference* between
// two arms, and everything the worker path does that the inline path does not
// is inside it, not just the messages.
//
// This harness times the messages alone. There is no SQLite and no resqlite
// code in any lane: one persistent worker isolate echoes what it is sent, and
// each lane changes only the shape of what crosses the boundary. Every lane
// awaits each round trip before starting the next, because a read does.
//
//   iso-echo        an int out and an int back. The round trip at its floor.
//   iso-request     a `SelectRequest`-shaped object out — String sql, List
//                   parameters, three ints — int back. The request adder.
//   iso-result      a marker out, a point read's reply back: one row of six
//                   cells, six column names and the `(result, sacrificed,
//                   error)` envelope, pre-built on the worker so the lane times
//                   the transfer and not the decode. The reply adder.
//   iso-full        request object out and result shape back in one trip: a
//                   point read's whole transport, measured rather than summed.
//   iso-bytes       the `selectBytes` shape — 256 KB as a view over malloc'd
//                   memory, which is what the reader sends over its `json_buf`
//                   (exp 174).
//   iso-bytes-heap  the same 256 KB as an ordinary heap `Uint8List`. The pair
//                   isolates *backing* from size: they carry identical bytes.
//
// Read `iso-full` against exp 265's 6.3 us for how much of the hop is transport
// and how much is the per-request work around it, and the `iso-bytes` pair
// before any change that would materialize a payload on the Dart heap before
// sending it.
//
// Usage:
//   dart run benchmark/experiments/isolate_transport_price.dart \
//     [--samples=11] [--lanes=iso-echo,iso-full] [--iterations=2000]
//
// Build it AOT for figures comparable with shipped code; the JIT numbers differ
// by more than the effects being measured.
import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const _iterations = 2000;
const _warmup = 500;

/// Payload size for the two bytes lanes, near the middle of what `selectBytes`
/// carries in the release suite's large-payload lane (exp 175).
const _payloadBytes = 256 * 1024;

/// Shaped like `SelectRequest`: what the pool actually hands a worker.
final class _Request {
  _Request(this.sql, this.parameters);
  final String sql;
  final List<Object?> parameters;
  final int? traceCorrelationId = null;
  int rowHint = 0;
  int initialRowHint = 0;
}

const _resultMarker = 'result';
const _bytesMarker = 'bytes';
const _bytesHeapMarker = 'bytes-heap';

/// A point read's reply, in the envelope `_WorkerSlot` receives.
final _result = (
  <List<Object?>>[
    <Object?>[1, 'Widget', 19.99, 'A short description', 1, 1735689600000],
  ],
  <String>['id', 'name', 'price', 'description', 'in_stock', 'created_at'],
  false,
  null,
);

/// Stands in for the view over a reader's `json_buf` that `selectBytes` sends.
final _payload = malloc<ffi.Uint8>(_payloadBytes).asTypedList(_payloadBytes);

/// The same bytes as an ordinary heap list, so the two bytes lanes differ only
/// in how the payload is backed.
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
      reply.send(_result);
      return;
    }
    if (msg is _Request) {
      // rowHint == -1 is the `iso-full` lane: object out, result shape back.
      reply.send(msg.rowHint == -1 ? _result : msg.rowHint);
      return;
    }
    reply.send(msg);
  };
  reply.send(commands.sendPort);
}

/// A persistent worker isolate that echoes what it is sent, so a lane measures
/// the transport and nothing else.
Future<(SendPort, RawReceivePort)> _spawnEcho() async {
  final ready = Completer<SendPort>.sync();
  final replies = RawReceivePort();
  replies.handler = (Object? msg) {
    if (msg is SendPort) ready.complete(msg);
  };
  await Isolate.spawn(_echoEntry, replies.sendPort);
  return (await ready.future, replies);
}

Future<int> _run(
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

double _median(List<double> xs) {
  final sorted = List<double>.from(xs)..sort();
  return sorted[sorted.length ~/ 2];
}

const _shapes = <String, String>{
  'iso-echo': 'echo',
  'iso-request': 'request',
  'iso-result': 'result',
  'iso-full': 'full',
  'iso-bytes': 'bytes',
  'iso-bytes-heap': 'bytes-heap',
};

Future<void> main(List<String> args) async {
  var samples = 11;
  var iterations = _iterations;
  var warmup = _warmup;
  var lanes = _shapes.keys.toList();
  for (final arg in args) {
    if (arg.startsWith('--samples=')) {
      samples = int.parse(arg.substring('--samples='.length));
    } else if (arg.startsWith('--iterations=')) {
      iterations = int.parse(arg.substring('--iterations='.length));
      warmup = iterations ~/ 4;
    } else if (arg.startsWith('--lanes=')) {
      lanes = arg.substring('--lanes='.length).split(',');
    } else {
      throw ArgumentError('unknown argument: $arg');
    }
  }

  final (commands, replies) = await _spawnEcho();

  print('=== isolate transport price ===');
  print('iterations=$iterations samples=$samples');
  for (final lane in lanes) {
    final shape = _shapes[lane];
    if (shape == null) throw ArgumentError('unknown lane: $lane');
    await _run(commands, replies, warmup, shape);
    final perCall = <double>[];
    for (var s = 0; s < samples; s++) {
      final stopwatch = Stopwatch()..start();
      await _run(commands, replies, iterations, shape);
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

  commands.send(null);
  replies.close();
}
