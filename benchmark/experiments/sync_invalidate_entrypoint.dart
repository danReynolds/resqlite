// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';

const int _defaultRuns = 3;
const int _defaultIterations = 3000;
const int _defaultWarmup = 500;
const int _rowCount = 1000;

Future<void> main(List<String> args) async {
  var runs = _defaultRuns;
  var iterations = _defaultIterations;
  var warmup = _defaultWarmup;

  for (final arg in args) {
    if (arg.startsWith('--runs=')) {
      runs = int.parse(arg.substring('--runs='.length));
    } else if (arg.startsWith('--iterations=')) {
      iterations = int.parse(arg.substring('--iterations='.length));
    } else if (arg.startsWith('--warmup=')) {
      warmup = int.parse(arg.substring('--warmup='.length));
    } else if (arg == '--help' || arg == '-h') {
      _printUsage();
      return;
    } else {
      throw ArgumentError('Unknown argument: $arg');
    }
  }

  print('Stream invalidate entrypoint benchmark');
  print('  runs=$runs iterations=$iterations warmup=$warmup rows=$_rowCount');
  print('');

  final noStream = <_Stats>[];
  final oneStream = <_Stats>[];

  for (var run = 0; run < runs; run++) {
    final noStreamStats = await _measureCase(
      iterations: iterations,
      warmup: warmup,
      streamCount: 0,
    );
    noStream.add(noStreamStats);
    print('run ${run + 1} no_streams: ${noStreamStats.format()}');

    final oneStreamStats = await _measureCase(
      iterations: iterations,
      warmup: warmup,
      streamCount: 1,
    );
    oneStream.add(oneStreamStats);
    print('run ${run + 1} one_stream: ${oneStreamStats.format()}');
  }

  print('');
  print('| case | run p50s (us) | median p50 | median p90 | median p99 |');
  print('|---|---:|---:|---:|---:|');
  _printAggregate('no_streams', noStream);
  _printAggregate('one_stream', oneStream);
}

Future<_Stats> _measureCase({
  required int iterations,
  required int warmup,
  required int streamCount,
}) async {
  final tempDir = await Directory.systemTemp.createTemp('resqlite_sync_inv_');
  final db = await Database.open('${tempDir.path}/bench.db');
  final samples = <int>[];
  final subs = <StreamSubscription<List<Map<String, Object?>>>>[];

  try {
    await db.execute(
      'CREATE TABLE items(id INTEGER PRIMARY KEY, value TEXT NOT NULL)',
    );
    await db.executeBatch('INSERT INTO items(id, value) VALUES (?, ?)', [
      for (var i = 0; i < _rowCount; i++) [i, 'v$i'],
    ]);

    final initial = <Completer<void>>[];
    for (var i = 0; i < streamCount; i++) {
      final ready = Completer<void>();
      initial.add(ready);
      final sub = db
          .stream('SELECT id, value FROM items WHERE id = ?', [i])
          .listen((_) {
            if (!ready.isCompleted) ready.complete();
          });
      subs.add(sub);
    }
    if (initial.isNotEmpty) {
      await Future.wait(initial.map((c) => c.future));
    }

    final total = warmup + iterations;
    for (var i = 0; i < total; i++) {
      final sw = Stopwatch()..start();
      await db.execute('UPDATE items SET value = ? WHERE id = ?', [
        'v${i & 1023}',
        i % _rowCount,
      ]);
      sw.stop();

      // Give stream re-query scheduling a chance to make progress so
      // one_stream measures steady-state invalidate entry cost rather
      // than unbounded queue buildup.
      if (streamCount > 0) {
        await Future<void>.delayed(Duration.zero);
      }

      if (i >= warmup) {
        samples.add(sw.elapsedMicroseconds);
      }
    }

    return _Stats.from(samples);
  } finally {
    for (final sub in subs) {
      await sub.cancel();
    }
    await db.close();
    await tempDir.delete(recursive: true);
  }
}

void _printAggregate(String name, List<_Stats> runs) {
  final p50s = runs.map((s) => s.p50).toList();
  final p90s = runs.map((s) => s.p90).toList();
  final p99s = runs.map((s) => s.p99).toList();
  print(
    '| $name | ${p50s.join(', ')} | ${_median(p50s)} | '
    '${_median(p90s)} | ${_median(p99s)} |',
  );
}

final class _Stats {
  _Stats(this.p50, this.p90, this.p99, this.max);

  factory _Stats.from(List<int> samples) {
    if (samples.isEmpty) return _Stats(0, 0, 0, 0);
    final sorted = [...samples]..sort();
    int percentile(double p) {
      final index = ((sorted.length - 1) * p).round();
      return sorted[index];
    }

    return _Stats(
      percentile(0.50),
      percentile(0.90),
      percentile(0.99),
      sorted.last,
    );
  }

  final int p50;
  final int p90;
  final int p99;
  final int max;

  String format() => 'p50=$p50 us p90=$p90 us p99=$p99 us max=$max us';
}

int _median(List<int> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

void _printUsage() {
  print(
    'Usage: dart run benchmark/experiments/sync_invalidate_entrypoint.dart '
    '[--runs=N] [--iterations=N] [--warmup=N]',
  );
}
