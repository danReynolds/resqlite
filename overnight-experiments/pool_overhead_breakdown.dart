// ignore_for_file: avoid_print
/// Detailed breakdown of exactly why the persistent pool is slower.
///
/// Compares the EXACT patterns used by:
/// - resqlite's one-off isolates (_runOnIsolate pattern)
/// - resqlite's reader pool (query() pattern)
///
/// Isolates the overhead sources:
/// 1. ReceivePort vs RawReceivePort
/// 2. replyPort.first vs Completer
/// 3. Round-trip scheduling (2 hops vs 1 hop)
/// 4. Request serialization cost (SQL string + params)
/// 5. Map serialization cost (result)
import 'dart:async';
import 'dart:isolate';

const _iterations = 500;
const _warmup = 50;

/// Simulated "work" — build a single-row result (6-column map).
Map<String, Object?> _doWork() {
  return {
    'id': 42,
    'name': 'Item 42',
    'description': 'Description for item 42 with padding text',
    'value': 63.0,
    'category': 'category_2',
    'created_at': '2026-04-07T12:00:00Z',
  };
}

Future<void> main() async {
  print('');
  print('=== Pool Overhead Breakdown ===');
  print('');
  print('Simulating 500 sequential single-row lookups.');
  print('Each test builds one 6-column map as "work".');
  print('');

  // Setup persistent worker.
  final workerReceive = ReceivePort();
  final readyCompleter = Completer<SendPort>();
  workerReceive.listen((msg) {
    if (msg is SendPort) readyCompleter.complete(msg);
  });
  await Isolate.spawn(_workerMain, workerReceive.sendPort);
  final workerPort = await readyCompleter.future;

  // =========================================================================
  // Pattern 1: resqlite's one-off isolate pattern (RawReceivePort + Completer)
  // =========================================================================
  print('1) resqlite one-off: Isolate.spawn + RawReceivePort + Completer');
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
      await Isolate.spawn((SendPort p) {
        final result = _doWork();
        Isolate.exit(p, result);
      }, port.sendPort);
      await completer.future;
      sw.stop();
      if (i >= _warmup) timings.add(sw.elapsedMicroseconds);
    }
    _printStats('One-off isolate', timings);
  }

  // =========================================================================
  // Pattern 2: resqlite pool's EXACT pattern (ReceivePort + .first)
  // =========================================================================
  print('');
  print('2) resqlite pool pattern: SendPort + ReceivePort + .first');
  {
    final timings = <int>[];
    for (var i = 0; i < _warmup + _iterations; i++) {
      final replyPort = ReceivePort();
      final sw = Stopwatch()..start();
      workerPort.send(_PoolStyleRequest(
        sql: 'SELECT * FROM items WHERE id = ?',
        params: [42],
        replyPort: replyPort.sendPort,
      ));
      final _ = await replyPort.first;
      sw.stop();
      if (i >= _warmup) timings.add(sw.elapsedMicroseconds);
    }
    _printStats('Pool pattern (ReceivePort + .first)', timings);
  }

  // =========================================================================
  // Pattern 3: Pool with RawReceivePort + Completer (better receive side)
  // =========================================================================
  print('');
  print('3) Pool with RawReceivePort + Completer');
  {
    final timings = <int>[];
    for (var i = 0; i < _warmup + _iterations; i++) {
      final replyPort = RawReceivePort();
      final completer = Completer<Object?>();
      replyPort.handler = (Object? msg) {
        replyPort.close();
        completer.complete(msg);
      };
      final sw = Stopwatch()..start();
      workerPort.send(_PoolStyleRequest(
        sql: 'SELECT * FROM items WHERE id = ?',
        params: [42],
        replyPort: replyPort.sendPort,
      ));
      await completer.future;
      sw.stop();
      if (i >= _warmup) timings.add(sw.elapsedMicroseconds);
    }
    _printStats('Pool (RawReceivePort + Completer)', timings);
  }

  // =========================================================================
  // Pattern 4: Pool returning List<List> instead of Map (like sqlite_async)
  // =========================================================================
  print('');
  print('4) Pool returning List<List> (sqlite_async style result)');
  {
    final timings = <int>[];
    for (var i = 0; i < _warmup + _iterations; i++) {
      final replyPort = RawReceivePort();
      final completer = Completer<Object?>();
      replyPort.handler = (Object? msg) {
        replyPort.close();
        completer.complete(msg);
      };
      final sw = Stopwatch()..start();
      workerPort.send(_ListStyleRequest(
        sql: 'SELECT * FROM items WHERE id = ?',
        params: [42],
        replyPort: replyPort.sendPort,
      ));
      await completer.future;
      sw.stop();
      if (i >= _warmup) timings.add(sw.elapsedMicroseconds);
    }
    _printStats('Pool (List<List> result)', timings);
  }

  // =========================================================================
  // Pattern 5: Pool with no request serialization (pre-bound closure)
  // =========================================================================
  print('');
  print('5) Pool with closure (no request serialization)');
  {
    final timings = <int>[];
    for (var i = 0; i < _warmup + _iterations; i++) {
      final replyPort = RawReceivePort();
      final completer = Completer<Object?>();
      replyPort.handler = (Object? msg) {
        replyPort.close();
        completer.complete(msg);
      };
      final sw = Stopwatch()..start();
      // Send a closure + reply port (sqlite_async's IsolateWorker style)
      workerPort.send(_ClosureRequest(
        task: _doWork,
        replyPort: replyPort.sendPort,
      ));
      await completer.future;
      sw.stop();
      if (i >= _warmup) timings.add(sw.elapsedMicroseconds);
    }
    _printStats('Pool (closure, no SQL serialization)', timings);
  }

  // =========================================================================
  // Pattern 6: Pool returning raw map (no wrapper class)
  // =========================================================================
  print('');
  print('6) Pool returning raw map (no wrapper)');
  {
    final timings = <int>[];
    for (var i = 0; i < _warmup + _iterations; i++) {
      final replyPort = RawReceivePort();
      final completer = Completer<Object?>();
      replyPort.handler = (Object? msg) {
        replyPort.close();
        completer.complete(msg);
      };
      final sw = Stopwatch()..start();
      workerPort.send(_RawMapRequest(replyPort.sendPort));
      await completer.future;
      sw.stop();
      if (i >= _warmup) timings.add(sw.elapsedMicroseconds);
    }
    _printStats('Pool (raw map, no wrapper, no SQL)', timings);
  }

  // Cleanup.
  workerPort.send(null);
  workerReceive.close();

  print('');
  print('=== Expected Ordering (fastest to slowest) ===');
  print('  6. Raw map (minimal overhead)');
  print('  5. Closure (no SQL serialization)');
  print('  4. List<List> result');
  print('  3. RawReceivePort pool');
  print('  2. ReceivePort pool (resqlite current)');
  print('  1. One-off isolate (resqlite current)');
  print('');
  print('If 3 is close to 1, the scheduling tax is the main issue.');
  print('If 2 >> 3, ReceivePort overhead matters.');
  print('If 4 << 3, map serialization is the key cost.');
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
      case _PoolStyleRequest(:final replyPort):
        final result = _doWork();
        replyPort.send(_QueryResult(result));
      case _ListStyleRequest(:final replyPort):
        final columns = ['id', 'name', 'description', 'value', 'category', 'created_at'];
        final rows = [[42, 'Item 42', 'Description for item 42 with padding text', 63.0, 'category_2', '2026-04-07T12:00:00Z']];
        replyPort.send((columns, rows));
      case _ClosureRequest(:final task, :final replyPort):
        replyPort.send(task());
      case _RawMapRequest(:final replyPort):
        replyPort.send(_doWork());
      case null:
        port.close();
    }
  });
}

// ---------------------------------------------------------------------------
// Message types
// ---------------------------------------------------------------------------

class _PoolStyleRequest {
  final String sql;
  final List<Object?> params;
  final SendPort replyPort;
  _PoolStyleRequest({
    required this.sql,
    required this.params,
    required this.replyPort,
  });
}

class _ListStyleRequest {
  final String sql;
  final List<Object?> params;
  final SendPort replyPort;
  _ListStyleRequest({
    required this.sql,
    required this.params,
    required this.replyPort,
  });
}

class _ClosureRequest {
  final Object? Function() task;
  final SendPort replyPort;
  _ClosureRequest({required this.task, required this.replyPort});
}

class _RawMapRequest {
  final SendPort replyPort;
  _RawMapRequest(this.replyPort);
}

class _QueryResult {
  final Map<String, Object?> row;
  _QueryResult(this.row);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

void _printStats(String label, List<int> timings) {
  timings.sort();
  final median = timings[timings.length ~/ 2];
  final p95 = timings[(timings.length * 0.95).floor()];
  final mean = (timings.reduce((a, b) => a + b) / timings.length).round();
  print('  $label: median $median us  |  mean $mean us  |  p95 $p95 us');
}
