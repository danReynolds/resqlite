// EXP-245 / Experiment A of the peer's estimand split: the INTRINSIC transfer
// estimand — `SendPort.send` vs `Isolate.exit` for handing off a prepared
// production `ResultSet`, with spawn, SQLite stepping, decode, and result
// CONSTRUCTION all moved OUTSIDE the timed interval.
//
// Protocol (peer-designed):
//   - A worker isolate builds the real production ResultSet graph (flat
//     row-major values list + RowSchema + wrapper — the exact object graph that
//     crosses the boundary in production, per row.dart) and holds it live.
//   - Worker sends a tiny Ready(goPort) to main.
//   - Main records t0 (VM-timeline µs) and sends Go.
//   - Worker immediately does `resultPort.send(result)` OR
//     `Isolate.exit(resultPort, result)`.
//   - Main's result-port handler records t1 as its FIRST statement.
//   handoffWall = t1 - t0. t0 and t1 are both on main -> one monotonic clock.
//
// One fresh PROCESS per observation (no receiver-heap accumulation, no mode
// carryover, neither mode inheriting the other's GC state). An orchestrator runs
// matched send/exit children in randomized ABBA blocks. Process startup is
// irrelevant — it is outside the timed interval.
//
//   orchestrate: dart run benchmark/experiments/prepared_result_handoff.dart
//   child (internal): ... --child <shape> <send|exit>
import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:isolate';

import 'package:resqlite/src/row.dart' show ResultSet, RowSchema;

// Shapes: name -> prepared ResultSet. Structure matches production (distinct
// per-cell string objects, as SQLite decode produces — not canonical/shared).
ResultSet _build(String shape) {
  switch (shape) {
    case 'empty':
      return ResultSet(<Object?>[], RowSchema(const ['a']), 0);
    case 'num10kx20':
      return _numeric(10000, 20);
    case 'mixed10kx8':
      return _mixed(10000);
    case 'str400k':
      return _bigString(400 * 1024);
    case 'str1m':
      return _bigString(1024 * 1024);
    // structural-slot sweep at 4 columns (slots = rows * 4)
    case 'num2k':
      return _numeric(500, 4);
    case 'num8k':
      return _numeric(2000, 4);
    case 'num20k':
      return _numeric(5000, 4);
    case 'num48k':
      return _numeric(12000, 4);
    default:
      throw ArgumentError('unknown shape $shape');
  }
}

ResultSet _numeric(int rows, int cols) {
  final names = [for (var c = 0; c < cols; c++) 'c$c'];
  final values = List<Object?>.filled(rows * cols, null);
  var k = 0;
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      values[k++] = r * 31 + c;
    }
  }
  return ResultSet(values, RowSchema(names), rows);
}

ResultSet _mixed(int rows) {
  // 8 cols: 4 ints, 4 strings (distinct per-cell objects).
  final names = const ['a', 'b', 'c', 'd', 's', 't', 'u', 'v'];
  final values = List<Object?>.filled(rows * 8, null);
  var k = 0;
  for (var r = 0; r < rows; r++) {
    values[k++] = r;
    values[k++] = r * 3;
    values[k++] = r ~/ 2;
    values[k++] = -r;
    values[k++] = 'row_$r name field with some descriptive text';
    values[k++] = 'category_${r % 20}_${r & 7}';
    values[k++] = 'status_${r % 5}';
    values[k++] = 'tag_$r';
  }
  return ResultSet(values, RowSchema(names), rows);
}

ResultSet _bigString(int bytes) {
  final sb = StringBuffer();
  for (var i = 0; i < bytes; i++) {
    sb.writeCharCode(65 + (i % 26));
  }
  return ResultSet(<Object?>[sb.toString()], RowSchema(const ['s']), 1);
}

// ---- child: exactly one timed observation, then exit ----

void _worker(List<Object?> args) {
  final shape = args[0] as String;
  final mode = args[1] as String;
  final readyPort = args[2] as SendPort;
  final resultPort = args[3] as SendPort;

  final result = _build(shape); // construction — BEFORE the barrier

  final goPort = RawReceivePort();
  goPort.handler = (_) {
    goPort.close();
    if (mode == 'exit') {
      Isolate.exit(resultPort, result);
    } else {
      resultPort.send(result);
    }
  };
  readyPort.send(goPort.sendPort);
}

Future<int> _observe(String shape, String mode) async {
  final readyPort = RawReceivePort();
  final resultPort = RawReceivePort();
  final done = Completer<int>();
  var t0 = 0;

  readyPort.handler = (Object? msg) {
    final goPort = msg as SendPort;
    t0 = Timeline.now; // record t0, then release Go
    goPort.send(1);
  };
  resultPort.handler = (Object? msg) {
    final t1 = Timeline.now; // FIRST statement — arbitrary caller work excluded
    if (!done.isCompleted) done.complete(t1 - t0);
  };

  final iso = await Isolate.spawn(
    _worker,
    [shape, mode, readyPort.sendPort, resultPort.sendPort],
  );
  final wall = await done.future;
  readyPort.close();
  resultPort.close();
  if (mode == 'send') iso.kill(priority: Isolate.immediate);
  return wall;
}

// ---- orchestrator ----

const _shapes = [
  'empty',
  'num10kx20',
  'mixed10kx8',
  'str400k',
  'str1m',
  'num2k',
  'num8k',
  'num20k',
  'num48k',
];
const _blocks = 8; // ABBA blocks per shape -> 2*_blocks samples per mode

double _median(List<double> xs) {
  final s = [...xs]..sort();
  return s[s.length ~/ 2];
}

Future<void> _orchestrate() async {
  final exe = Platform.resolvedExecutable;
  final script = Platform.script.toFilePath();
  stdout.writeln('Experiment A — prepared-result handoff (Go-sent -> received, µs)');
  stdout.writeln('shape | send med | exit med | exit-send | send-empty | exit-empty');
  stdout.writeln('---|---:|---:|---:|---:|---:');

  final sendMed = <String, double>{};
  final exitMed = <String, double>{};

  for (final shape in _shapes) {
    final send = <double>[];
    final exit = <double>[];
    for (var b = 0; b < _blocks; b++) {
      // ABBA: alternate the order each block to cancel drift.
      final order = b.isEven
          ? ['send', 'exit', 'exit', 'send']
          : ['exit', 'send', 'send', 'exit'];
      for (final mode in order) {
        final r = await Process.run(exe, [
          'run',
          script,
          '--child',
          shape,
          mode,
        ]);
        final line = (r.stdout as String)
            .split('\n')
            .firstWhere((l) => l.startsWith('RESULT '), orElse: () => '');
        if (line.isEmpty) {
          stderr.writeln('child failed ($shape/$mode): ${r.stderr}');
          continue;
        }
        final us = double.parse(line.substring('RESULT '.length).trim());
        (mode == 'send' ? send : exit).add(us);
      }
    }
    sendMed[shape] = _median(send);
    exitMed[shape] = _median(exit);
  }

  final emptySend = sendMed['empty']!;
  final emptyExit = exitMed['empty']!;
  for (final shape in _shapes) {
    final s = sendMed[shape]!;
    final e = exitMed[shape]!;
    stdout.writeln('$shape | ${s.toStringAsFixed(1)} | ${e.toStringAsFixed(1)} '
        '| ${(e - s).toStringAsFixed(1)} '
        '| ${(s - emptySend).toStringAsFixed(1)} '
        '| ${(e - emptyExit).toStringAsFixed(1)}');
  }
}

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args[0] == '--child') {
    final wall = await _observe(args[1], args[2]);
    stdout.writeln('RESULT $wall');
    return;
  }
  await _orchestrate();
}
