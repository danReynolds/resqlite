// ignore_for_file: avoid_print
/// Targeted microbenchmark: SendPort latency breakdown vs Isolate.spawn.
///
/// Tests the hypothesis that ReceivePort listener scheduling (microtask/event
/// loop) introduces latency that Isolate.spawn doesn't have.
///
/// Measures:
/// A) SendPort one-way latency (send -> receive, no payload)
/// B) SendPort one-way latency (send -> receive, with small map payload)
/// C) SendPort round-trip (request -> worker does trivial work -> response)
/// D) SendPort round-trip (request -> worker builds 1 map -> response)
/// E) Isolate.spawn + Isolate.exit (no work)
/// F) Isolate.spawn + Isolate.exit (build 1 map and exit with it)
/// G) Full pipeline comparison: simulated query via SendPort vs spawn
///
/// Key insight to test: Does each message hop through the Dart event loop
/// add ~10-20us that accumulates in the SendPort round-trip path?
import 'dart:async';
import 'dart:isolate';

const _iterations = 500;
const _warmup = 50;

Future<void> main() async {
  print('');
  print('=== SendPort vs Isolate.spawn Latency Breakdown ===');
  print('');
  print('Iterations: $_iterations (after $_warmup warmup)');
  print('');

  // --- Setup persistent worker ---
  final workerReceive = ReceivePort();
  final readyCompleter = Completer<SendPort>();

  workerReceive.listen((msg) {
    if (msg is SendPort) {
      readyCompleter.complete(msg);
    }
  });

  await Isolate.spawn(_workerMain, workerReceive.sendPort);
  final workerPort = await readyCompleter.future;

  // =========================================================================
  // A) SendPort one-way latency (no payload)
  // =========================================================================
  print('A) SendPort one-way latency (no payload)...');
  {
    final timings = <int>[];
    for (var i = 0; i < _warmup + _iterations; i++) {
      final reply = ReceivePort();
      final sw = Stopwatch()..start();
      // Send a "ping" — worker immediately sends back a "pong"
      workerPort.send(_Ping(reply.sendPort));
      await reply.first;
      sw.stop();
      if (i >= _warmup) timings.add(sw.elapsedMicroseconds);
    }
    _printStats('A: SendPort round-trip (no payload)', timings);
  }

  // =========================================================================
  // B) SendPort round-trip with small map payload
  // =========================================================================
  print('');
  print('B) SendPort round-trip (worker returns 1 small map)...');
  {
    final timings = <int>[];
    for (var i = 0; i < _warmup + _iterations; i++) {
      final reply = ReceivePort();
      final sw = Stopwatch()..start();
      workerPort.send(_BuildOneMap(reply.sendPort));
      await reply.first;
      sw.stop();
      if (i >= _warmup) timings.add(sw.elapsedMicroseconds);
    }
    _printStats('B: SendPort round-trip (1 map)', timings);
  }

  // =========================================================================
  // C) SendPort round-trip with 10 maps
  // =========================================================================
  print('');
  print('C) SendPort round-trip (worker returns 10 maps)...');
  {
    final timings = <int>[];
    for (var i = 0; i < _warmup + _iterations; i++) {
      final reply = ReceivePort();
      final sw = Stopwatch()..start();
      workerPort.send(_BuildTenMaps(reply.sendPort));
      await reply.first;
      sw.stop();
      if (i >= _warmup) timings.add(sw.elapsedMicroseconds);
    }
    _printStats('C: SendPort round-trip (10 maps)', timings);
  }

  // =========================================================================
  // D) SendPort with instrumented worker — measures request-side, work, reply
  // =========================================================================
  print('');
  print('D) SendPort instrumented breakdown (build 1 map)...');
  {
    final requestSideTimes = <int>[];
    final workTimes = <int>[];
    final replySideTimes = <int>[];
    final totalTimes = <int>[];

    for (var i = 0; i < _warmup + _iterations; i++) {
      final reply = ReceivePort();
      final sendTime = _microsNow();
      workerPort.send(_InstrumentedRequest(reply.sendPort, sendTime));
      final result = await reply.first as _InstrumentedResponse;
      final receiveTime = _microsNow();

      if (i >= _warmup) {
        requestSideTimes.add(result.receiveTime - sendTime);
        workTimes.add(result.workDone - result.receiveTime);
        replySideTimes.add(receiveTime - result.workDone);
        totalTimes.add(receiveTime - sendTime);
      }
    }

    requestSideTimes.sort();
    workTimes.sort();
    replySideTimes.sort();
    totalTimes.sort();

    print('  Request delivery (main -> worker):');
    print('    median: ${requestSideTimes[requestSideTimes.length ~/ 2]} us');
    print('    p95:    ${requestSideTimes[(requestSideTimes.length * 0.95).floor()]} us');
    print('  Worker computation (build 1 map):');
    print('    median: ${workTimes[workTimes.length ~/ 2]} us');
    print('    p95:    ${workTimes[(workTimes.length * 0.95).floor()]} us');
    print('  Reply delivery (worker -> main):');
    print('    median: ${replySideTimes[replySideTimes.length ~/ 2]} us');
    print('    p95:    ${replySideTimes[(replySideTimes.length * 0.95).floor()]} us');
    print('  Total:');
    print('    median: ${totalTimes[totalTimes.length ~/ 2]} us');
    print('    p95:    ${totalTimes[(totalTimes.length * 0.95).floor()]} us');
  }

  // =========================================================================
  // E) Isolate.spawn + Isolate.exit (no work)
  // =========================================================================
  print('');
  print('E) Isolate.spawn + Isolate.exit (no work)...');
  {
    final timings = <int>[];
    for (var i = 0; i < _warmup + _iterations; i++) {
      final port = RawReceivePort();
      final completer = Completer<void>();
      port.handler = (_) {
        port.close();
        completer.complete();
      };
      final sw = Stopwatch()..start();
      await Isolate.spawn((SendPort p) => Isolate.exit(p, null), port.sendPort);
      await completer.future;
      sw.stop();
      if (i >= _warmup) timings.add(sw.elapsedMicroseconds);
    }
    _printStats('E: Isolate.spawn + exit (no work)', timings);
  }

  // =========================================================================
  // F) Isolate.spawn + Isolate.exit (build 1 map)
  // =========================================================================
  print('');
  print('F) Isolate.spawn + Isolate.exit (build 1 map)...');
  {
    final timings = <int>[];
    for (var i = 0; i < _warmup + _iterations; i++) {
      final port = RawReceivePort();
      final completer = Completer<Object?>();
      port.handler = (Object? msg) {
        port.close();
        completer.complete(msg);
      };
      final sw = Stopwatch()..start();
      await Isolate.spawn(_buildOneMapAndExit, port.sendPort);
      await completer.future;
      sw.stop();
      if (i >= _warmup) timings.add(sw.elapsedMicroseconds);
    }
    _printStats('F: Isolate.spawn + exit (1 map)', timings);
  }

  // =========================================================================
  // G) Isolate.spawn + Isolate.exit (build 10 maps)
  // =========================================================================
  print('');
  print('G) Isolate.spawn + Isolate.exit (build 10 maps)...');
  {
    final timings = <int>[];
    for (var i = 0; i < _warmup + _iterations; i++) {
      final port = RawReceivePort();
      final completer = Completer<Object?>();
      port.handler = (Object? msg) {
        port.close();
        completer.complete(msg);
      };
      final sw = Stopwatch()..start();
      await Isolate.spawn(_buildTenMapsAndExit, port.sendPort);
      await completer.future;
      sw.stop();
      if (i >= _warmup) timings.add(sw.elapsedMicroseconds);
    }
    _printStats('G: Isolate.spawn + exit (10 maps)', timings);
  }

  // =========================================================================
  // H) RawReceivePort vs ReceivePort for SendPort round-trip
  // =========================================================================
  print('');
  print('H) RawReceivePort round-trip (no payload) — tests event loop bypass...');
  {
    final timings = <int>[];
    for (var i = 0; i < _warmup + _iterations; i++) {
      final reply = RawReceivePort();
      final completer = Completer<void>();
      reply.handler = (_) {
        reply.close();
        completer.complete();
      };
      final sw = Stopwatch()..start();
      workerPort.send(_Ping(reply.sendPort));
      await completer.future;
      sw.stop();
      if (i >= _warmup) timings.add(sw.elapsedMicroseconds);
    }
    _printStats('H: RawReceivePort round-trip (no payload)', timings);
  }

  // =========================================================================
  // I) Consecutive SendPort messages — tests event loop queuing effect
  // =========================================================================
  print('');
  print('I) Back-to-back SendPort (5 rapid pings, measure each)...');
  {
    // This tests whether messages queue up in the event loop
    final allTimings = List.generate(5, (_) => <int>[]);

    for (var iter = 0; iter < _warmup + _iterations; iter++) {
      final replies = List.generate(5, (_) => ReceivePort());
      final sws = List.generate(5, (_) => Stopwatch());

      for (var j = 0; j < 5; j++) {
        sws[j].start();
        workerPort.send(_Ping(replies[j].sendPort));
      }

      for (var j = 0; j < 5; j++) {
        await replies[j].first;
        sws[j].stop();
        if (iter >= _warmup) {
          allTimings[j].add(sws[j].elapsedMicroseconds);
        }
      }
    }

    for (var j = 0; j < 5; j++) {
      allTimings[j].sort();
      final median = allTimings[j][allTimings[j].length ~/ 2];
      print('  Ping $j: median ${median} us');
    }
  }

  // Cleanup.
  workerPort.send(_Shutdown());
  workerReceive.close();

  print('');
  print('=== Summary ===');
  print('');
  print('The key comparison is:');
  print('  SendPort round-trip (1 map) vs Isolate.spawn+exit (1 map)');
  print('  SendPort round-trip (10 maps) vs Isolate.spawn+exit (10 maps)');
  print('');
  print('If SendPort is faster for no-payload but slower with maps,');
  print('it means the serialization cost dominates (not scheduling).');
  print('');
  print('If both hops (request + reply) each add ~5-10us scheduling,');
  print('the 2x hop overhead explains the gap.');
  print('');
}

// ---------------------------------------------------------------------------
// Worker isolate
// ---------------------------------------------------------------------------

void _workerMain(SendPort mainPort) {
  final port = ReceivePort();
  mainPort.send(port.sendPort);

  port.listen((msg) {
    switch (msg) {
      case _Ping(:final replyPort):
        replyPort.send(null);
      case _BuildOneMap(:final replyPort):
        replyPort.send(_buildOneMap());
      case _BuildTenMaps(:final replyPort):
        replyPort.send(_buildTenMaps());
      case _InstrumentedRequest(:final replyPort, :final sendTimestamp):
        final receiveTime = _microsNow();
        final map = _buildOneMap();
        final workDone = _microsNow();
        replyPort.send(_InstrumentedResponse(
          map: map,
          receiveTime: receiveTime,
          workDone: workDone,
        ));
      case _Shutdown():
        port.close();
    }
  });
}

// ---------------------------------------------------------------------------
// One-off isolate entrypoints
// ---------------------------------------------------------------------------

void _buildOneMapAndExit(SendPort port) {
  Isolate.exit(port, _buildOneMap());
}

void _buildTenMapsAndExit(SendPort port) {
  Isolate.exit(port, _buildTenMaps());
}

// ---------------------------------------------------------------------------
// Work simulation (building maps — same as what a query would produce)
// ---------------------------------------------------------------------------

Map<String, Object?> _buildOneMap() {
  return {
    'id': 42,
    'name': 'Item 42',
    'description': 'Description for item 42 with padding text',
    'value': 63.0,
    'category': 'category_2',
    'created_at': '2026-04-07T12:00:00Z',
  };
}

List<Map<String, Object?>> _buildTenMaps() {
  return [
    for (var i = 0; i < 10; i++)
      {
        'id': i,
        'name': 'Item $i',
        'description': 'Description for item $i with padding text',
        'value': i * 1.5,
        'category': 'category_${i % 10}',
        'created_at': '2026-04-07T12:00:00Z',
      },
  ];
}

// ---------------------------------------------------------------------------
// Message types
// ---------------------------------------------------------------------------

class _Ping {
  final SendPort replyPort;
  _Ping(this.replyPort);
}

class _BuildOneMap {
  final SendPort replyPort;
  _BuildOneMap(this.replyPort);
}

class _BuildTenMaps {
  final SendPort replyPort;
  _BuildTenMaps(this.replyPort);
}

class _InstrumentedRequest {
  final SendPort replyPort;
  final int sendTimestamp;
  _InstrumentedRequest(this.replyPort, this.sendTimestamp);
}

class _InstrumentedResponse {
  final Map<String, Object?> map;
  final int receiveTime;
  final int workDone;
  _InstrumentedResponse({
    required this.map,
    required this.receiveTime,
    required this.workDone,
  });
}

class _Shutdown {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

int _microsNow() => DateTime.now().microsecondsSinceEpoch;

void _printStats(String label, List<int> timings) {
  timings.sort();
  final median = timings[timings.length ~/ 2];
  final p95 = timings[(timings.length * 0.95).floor()];
  final p99 = timings[(timings.length * 0.99).floor()];
  final min = timings.first;
  final max = timings.last;
  final mean = (timings.reduce((a, b) => a + b) / timings.length).round();
  print('  $label');
  print('    median: $median us  |  mean: $mean us  |  min: $min us  |  max: $max us');
  print('    p95: $p95 us  |  p99: $p99 us');
}
