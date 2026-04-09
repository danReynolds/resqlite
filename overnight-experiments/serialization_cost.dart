// ignore_for_file: avoid_print
/// Measures the SendPort serialization cost for different result formats:
/// 1. List<Map<String, Object?>> — what resqlite's pool sends
/// 2. List<List<Object?>> + column names — what sqlite_async sends (ResultSet)
/// 3. Wrapping in a class vs sending raw lists
///
/// Also compares Isolate.exit cost for the same data shapes.
///
/// This isolates the serialization overhead from scheduling overhead.
import 'dart:async';
import 'dart:isolate';

const _iterations = 500;
const _warmup = 50;

Future<void> main() async {
  print('');
  print('=== Serialization Cost: Maps vs Lists across Isolate Boundary ===');
  print('');
  print('Iterations: $_iterations (after $_warmup warmup)');
  print('');

  // Setup persistent worker.
  final workerReceive = ReceivePort();
  final readyCompleter = Completer<SendPort>();
  workerReceive.listen((msg) {
    if (msg is SendPort) readyCompleter.complete(msg);
  });
  await Isolate.spawn(_workerMain, workerReceive.sendPort);
  final workerPort = await readyCompleter.future;

  // --- 1 row scenarios ---
  for (final rowCount in [1, 10, 50]) {
    print('--- $rowCount rows, 6 columns ---');
    print('');

    // A) SendPort: List<Map<String, Object?>>
    {
      final timings = <int>[];
      for (var i = 0; i < _warmup + _iterations; i++) {
        final reply = ReceivePort();
        final sw = Stopwatch()..start();
        workerPort.send(_RequestMaps(reply.sendPort, rowCount));
        await reply.first;
        sw.stop();
        if (i >= _warmup) timings.add(sw.elapsedMicroseconds);
      }
      timings.sort();
      print('  SendPort List<Map>:     median ${timings[timings.length ~/ 2]} us  '
          'p95 ${timings[(timings.length * 0.95).floor()]} us');
    }

    // B) SendPort: List<List<Object?>> + column names (sqlite_async style)
    {
      final timings = <int>[];
      for (var i = 0; i < _warmup + _iterations; i++) {
        final reply = ReceivePort();
        final sw = Stopwatch()..start();
        workerPort.send(_RequestLists(reply.sendPort, rowCount));
        await reply.first;
        sw.stop();
        if (i >= _warmup) timings.add(sw.elapsedMicroseconds);
      }
      timings.sort();
      print('  SendPort List<List>:    median ${timings[timings.length ~/ 2]} us  '
          'p95 ${timings[(timings.length * 0.95).floor()]} us');
    }

    // C) Isolate.exit: List<Map<String, Object?>>
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
        await Isolate.spawn(
          (args) {
            final (SendPort p, int n) = args;
            Isolate.exit(p, _buildMaps(n));
          },
          (port.sendPort, rowCount),
        );
        await completer.future;
        sw.stop();
        if (i >= _warmup) timings.add(sw.elapsedMicroseconds);
      }
      timings.sort();
      print('  Isolate.exit List<Map>: median ${timings[timings.length ~/ 2]} us  '
          'p95 ${timings[(timings.length * 0.95).floor()]} us');
    }

    // D) Isolate.exit: List<List<Object?>> + column names
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
        await Isolate.spawn(
          (args) {
            final (SendPort p, int n) = args;
            Isolate.exit(p, _buildLists(n));
          },
          (port.sendPort, rowCount),
        );
        await completer.future;
        sw.stop();
        if (i >= _warmup) timings.add(sw.elapsedMicroseconds);
      }
      timings.sort();
      print('  Isolate.exit List<List>: median ${timings[timings.length ~/ 2]} us  '
          'p95 ${timings[(timings.length * 0.95).floor()]} us');
    }

    // E) SendPort: wrapper class with List<Map> (like resqlite's _QueryResult)
    {
      final timings = <int>[];
      for (var i = 0; i < _warmup + _iterations; i++) {
        final reply = ReceivePort();
        final sw = Stopwatch()..start();
        workerPort.send(_RequestWrappedMaps(reply.sendPort, rowCount));
        await reply.first;
        sw.stop();
        if (i >= _warmup) timings.add(sw.elapsedMicroseconds);
      }
      timings.sort();
      print('  SendPort Wrapped<Map>:  median ${timings[timings.length ~/ 2]} us  '
          'p95 ${timings[(timings.length * 0.95).floor()]} us');
    }

    print('');
  }

  // Cleanup.
  workerPort.send(null);
  workerReceive.close();

  print('=== Analysis ===');
  print('');
  print('Compare:');
  print('  SendPort List<Map> vs SendPort List<List>');
  print('  -> Shows cost of serializing string keys per row');
  print('');
  print('  SendPort List<Map> vs Isolate.exit List<Map>');
  print('  -> Shows total overhead: spawn vs serialize+send');
  print('');
  print('  Isolate.exit is always: spawn_cost + validation_walk');
  print('  SendPort is: request_serialize + scheduling + result_serialize + scheduling');
  print('');
}

// ---------------------------------------------------------------------------
// Worker
// ---------------------------------------------------------------------------

void _workerMain(SendPort mainPort) {
  final port = ReceivePort();
  mainPort.send(port.sendPort);

  port.listen((msg) {
    switch (msg) {
      case _RequestMaps(:final replyPort, :final rowCount):
        replyPort.send(_buildMaps(rowCount));
      case _RequestLists(:final replyPort, :final rowCount):
        replyPort.send(_buildLists(rowCount));
      case _RequestWrappedMaps(:final replyPort, :final rowCount):
        replyPort.send(_WrappedResult(_buildMaps(rowCount)));
      case null:
        port.close();
    }
  });
}

// ---------------------------------------------------------------------------
// Data builders
// ---------------------------------------------------------------------------

List<Map<String, Object?>> _buildMaps(int n) {
  return [
    for (var i = 0; i < n; i++)
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

(List<String>, List<List<Object?>>) _buildLists(int n) {
  final columns = ['id', 'name', 'description', 'value', 'category', 'created_at'];
  final rows = [
    for (var i = 0; i < n; i++)
      [
        i,
        'Item $i',
        'Description for item $i with padding text',
        i * 1.5,
        'category_${i % 10}',
        '2026-04-07T12:00:00Z',
      ],
  ];
  return (columns, rows);
}

// ---------------------------------------------------------------------------
// Message types
// ---------------------------------------------------------------------------

class _RequestMaps {
  final SendPort replyPort;
  final int rowCount;
  _RequestMaps(this.replyPort, this.rowCount);
}

class _RequestLists {
  final SendPort replyPort;
  final int rowCount;
  _RequestLists(this.replyPort, this.rowCount);
}

class _RequestWrappedMaps {
  final SendPort replyPort;
  final int rowCount;
  _RequestWrappedMaps(this.replyPort, this.rowCount);
}

class _WrappedResult {
  final List<Map<String, Object?>> rows;
  _WrappedResult(this.rows);
}
