// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';

Future<void> main(List<String> args) async {
  final label = args.isEmpty ? 'default' : args.first;
  final tempDir = await Directory.systemTemp.createTemp(
    'resqlite_stream_scheduler_',
  );
  try {
    print('=== stream scheduler experiment: $label ===');
    print('rounds=$_rounds');
    print('repeats=$_repeats');
    print('');
    print('| Workload | p50 | p95 | p99 | updates/sec |');
    print('|---|---:|---:|---:|---:|');

    for (final workload in _Workload.values) {
      final result = _summarize([
        for (var i = 0; i < _repeats; i++)
          await _runOnce(
            '${tempDir.path}/$label-${workload.name}-$i.db',
            workload,
          ),
      ]);
      print(
        '| ${workload.name} '
        '| ${result.p50Ms.toStringAsFixed(3)} ms '
        '| ${result.p95Ms.toStringAsFixed(3)} ms '
        '| ${result.p99Ms.toStringAsFixed(3)} ms '
        '| ${result.updatesPerSecond.toStringAsFixed(0)} |',
      );
    }
  } finally {
    await tempDir.delete(recursive: true);
  }
}

const _rounds = int.fromEnvironment(
  'RESQLITE_STREAM_SCHEDULER_ROUNDS',
  defaultValue: 1000,
);

const _repeats = int.fromEnvironment(
  'RESQLITE_STREAM_SCHEDULER_REPEATS',
  defaultValue: 1,
);

enum _Workload {
  singleStream,
  eightStreamFanout,
  thirtyTwoStreamFanout,
  sixtyFourStreamFanout,
  probeReadDuringSixtyFourFanout,
}

Future<_RunResult> _runOnce(String path, _Workload workload) async {
  final db = await Database.open(path);
  try {
    await db.execute(
      'CREATE TABLE items(id INTEGER PRIMARY KEY, value INTEGER NOT NULL)',
    );
    await db.execute('INSERT INTO items(id, value) VALUES (1, 0)');

    return await switch (workload) {
      _Workload.singleStream => _fanout(db, 1),
      _Workload.eightStreamFanout => _fanout(db, 8),
      _Workload.thirtyTwoStreamFanout => _fanout(db, 32),
      _Workload.sixtyFourStreamFanout => _fanout(db, 64),
      _Workload.probeReadDuringSixtyFourFanout => _probeReadDuringFanout(db),
    };
  } finally {
    await db.close();
  }
}

Future<_RunResult> _fanout(Database db, int streamCount) async {
  final streams = [
    for (var i = 0; i < streamCount; i++)
      StreamIterator(
        db.stream('SELECT value + $i AS value FROM items WHERE id = 1'),
      ),
  ];

  try {
    await Future.wait([for (final stream in streams) stream.moveNext()]);

    final samples = <int>[];
    final total = Stopwatch()..start();
    for (var i = 0; i < _rounds; i++) {
      final sw = Stopwatch()..start();
      await db.execute('UPDATE items SET value = value + 1 WHERE id = 1');
      await Future.wait([for (final stream in streams) stream.moveNext()]);
      sw.stop();
      samples.add(sw.elapsedMicroseconds);
    }
    total.stop();

    return _RunResult(
      p50Ms: _percentileMs(samples, 0.50),
      p95Ms: _percentileMs(samples, 0.95),
      p99Ms: _percentileMs(samples, 0.99),
      updatesPerSecond: _rounds / (total.elapsedMicroseconds / 1e6),
    );
  } finally {
    await Future.wait([for (final stream in streams) stream.cancel()]);
  }
}

Future<_RunResult> _probeReadDuringFanout(Database db) async {
  await db.execute(
    'CREATE TABLE probe(id INTEGER PRIMARY KEY, value INTEGER NOT NULL)',
  );
  await db.executeBatch('INSERT INTO probe(id, value) VALUES (?, ?)', [
    for (var i = 1; i <= 1000; i++) [i, i],
  ]);

  final streams = [
    for (var i = 0; i < 64; i++)
      StreamIterator(
        db.stream('SELECT value + $i AS value FROM items WHERE id = 1'),
      ),
  ];

  try {
    await Future.wait([for (final stream in streams) stream.moveNext()]);

    final samples = <int>[];
    final total = Stopwatch()..start();
    for (var i = 0; i < _rounds; i++) {
      await db.execute('UPDATE items SET value = value + 1 WHERE id = 1');

      final sw = Stopwatch()..start();
      await db.select('SELECT * FROM probe LIMIT 1000');
      sw.stop();
      samples.add(sw.elapsedMicroseconds);

      await Future.wait([for (final stream in streams) stream.moveNext()]);
    }
    total.stop();

    return _RunResult(
      p50Ms: _percentileMs(samples, 0.50),
      p95Ms: _percentileMs(samples, 0.95),
      p99Ms: _percentileMs(samples, 0.99),
      updatesPerSecond: _rounds / (total.elapsedMicroseconds / 1e6),
    );
  } finally {
    await Future.wait([for (final stream in streams) stream.cancel()]);
  }
}

double _percentileMs(List<int> valuesUs, double percentile) {
  final sorted = [...valuesUs]..sort();
  final index = ((sorted.length - 1) * percentile).round();
  return sorted[index] / 1000;
}

_RunResult _summarize(List<_RunResult> results) {
  return _RunResult(
    p50Ms: _median(results.map((r) => r.p50Ms).toList()),
    p95Ms: _median(results.map((r) => r.p95Ms).toList()),
    p99Ms: _median(results.map((r) => r.p99Ms).toList()),
    updatesPerSecond: _median(results.map((r) => r.updatesPerSecond).toList()),
  );
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

final class _RunResult {
  const _RunResult({
    required this.p50Ms,
    required this.p95Ms,
    required this.p99Ms,
    required this.updatesPerSecond,
  });

  final double p50Ms;
  final double p95Ms;
  final double p99Ms;
  final double updatesPerSecond;
}
