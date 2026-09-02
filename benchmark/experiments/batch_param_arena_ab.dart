// ignore_for_file: avoid_print
//
// A/B gate for caller-side batch parameter packing ([EXP-280]).
//
// Baseline sends `executeBatch`'s `List<List<Object?>>` to the writer isolate
// and packs it there. The candidate packs it on the issuing isolate and sends
// the arena's address. Wall time is only half the question: the packing walk
// the candidate moves is work the *main* isolate now does, and resqlite's
// contract is that reads and writes run "with zero main-isolate jank". So each
// lane reports both.
//
//   wall     median microseconds for the whole `executeBatch`.
//   block    the longest gap observed by an event-loop probe running for the
//            duration of that same call — how long the main isolate was
//            unavailable to anything else. This is the jank number.
//
// Lanes:
//   int-10k-x8      fixed-width numeric matrix. Packing is cheapest here, so
//                   this is where caller-side packing can win both metrics.
//   ascii-10k-x4    the Batch Insert shape: short ASCII text.
//   mixed-10k-x20   the release suite's Wide Batch Insert shape.
//   small-100-x8    a small batch. The candidate's arena must be owned memory,
//                   so it cannot use the isolate-local scratch buffer that
//                   `allocateReusableParamStructBuf` hands small packs today.
//                   This lane prices that loss.
//   tx-10k-x8       the same numeric matrix inside `db.transaction`, which
//                   takes the nested batch path.
//
//   dart run benchmark/experiments/batch_param_arena_ab.dart [--arm=<name>]
//
import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';

const _warmup = 3;
const _samples = 15;

void main(List<String> args) async {
  final arm = args
      .firstWhere((a) => a.startsWith('--arm='), orElse: () => '--arm=arm')
      .substring('--arm='.length);

  final lanes = <_Lane>[
    _Lane('int-10k-x8', rows: 10000, cols: 8, kind: _Kind.int64),
    _Lane('ascii-10k-x4', rows: 10000, cols: 4, kind: _Kind.ascii),
    _Lane('mixed-10k-x20', rows: 10000, cols: 20, kind: _Kind.mixed),
    _Lane('small-100-x8', rows: 100, cols: 8, kind: _Kind.mixed),
    _Lane('tx-10k-x8', rows: 10000, cols: 8, kind: _Kind.int64, inTx: true),
  ];

  print('exp280 batch parameter arena — arm=$arm, '
      '$_samples samples after $_warmup warmup\n');
  print('| Lane | wall med us | wall p90 us | block med us | block max us |');
  print('|---|---:|---:|---:|---:|');
  for (final lane in lanes) {
    final r = await _run(lane);
    print(
      '| ${lane.name} | ${r.wallMed.toStringAsFixed(1)} '
      '| ${r.wallP90.toStringAsFixed(1)} '
      '| ${r.blockMed.toStringAsFixed(1)} '
      '| ${r.blockMax.toStringAsFixed(1)} |',
    );
  }
}

Future<_Result> _run(_Lane lane) async {
  final dir = await Directory.systemTemp.createTemp('exp280_ab_');
  final db = await Database.open('${dir.path}/bench.db');
  try {
    final cols = [for (var i = 0; i < lane.cols; i++) 'c$i'];
    await db.execute(
      'CREATE TABLE t (${cols.map((c) => '$c ${lane.sqlType}').join(', ')})',
    );
    final sql = 'INSERT INTO t (${cols.join(', ')}) '
        'VALUES (${List.filled(lane.cols, '?').join(', ')})';
    final matrix = lane.build();

    Future<void> once() => lane.inTx
        ? db.transaction((tx) => tx.executeBatch(sql, matrix))
        : db.executeBatch(sql, matrix);

    for (var i = 0; i < _warmup; i++) {
      await once();
    }

    final wall = <double>[];
    final block = <double>[];
    for (var i = 0; i < _samples; i++) {
      final probe = _EventLoopProbe()..start();
      final sw = Stopwatch()..start();
      await once();
      sw.stop();
      block.add(probe.stop().toDouble());
      wall.add(sw.elapsedMicroseconds.toDouble());
      // Keep the table from growing without bound across samples, so every
      // sample inserts into a table of the same size.
      await db.execute('DELETE FROM t');
    }
    wall.sort();
    block.sort();
    return _Result(
      wallMed: wall[wall.length ~/ 2],
      wallP90: wall[(wall.length * 9) ~/ 10],
      blockMed: block[block.length ~/ 2],
      blockMax: block.last,
    );
  } finally {
    await db.close();
    await dir.delete(recursive: true);
  }
}

/// Reschedules itself on the event queue and records the largest gap between
/// consecutive runs. A gap is time the main isolate spent unavailable —
/// either running Dart or blocked in a leaf FFI call.
final class _EventLoopProbe {
  bool _running = false;
  int _lastUs = 0;
  int _maxGapUs = 0;
  final Stopwatch _sw = Stopwatch();

  void start() {
    _running = true;
    _sw.start();
    _lastUs = _sw.elapsedMicroseconds;
    _tick();
  }

  void _tick() {
    if (!_running) return;
    final now = _sw.elapsedMicroseconds;
    final gap = now - _lastUs;
    if (gap > _maxGapUs) _maxGapUs = gap;
    _lastUs = now;
    Timer.run(_tick);
  }

  int stop() {
    _running = false;
    _sw.stop();
    return _maxGapUs;
  }
}

final class _Result {
  const _Result({
    required this.wallMed,
    required this.wallP90,
    required this.blockMed,
    required this.blockMax,
  });

  final double wallMed;
  final double wallP90;
  final double blockMed;
  final double blockMax;
}

enum _Kind { mixed, ascii, int64 }

final class _Lane {
  _Lane(
    this.name, {
    required this.rows,
    required this.cols,
    required this.kind,
    this.inTx = false,
  });

  final String name;
  final int rows;
  final int cols;
  final _Kind kind;
  final bool inTx;

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
