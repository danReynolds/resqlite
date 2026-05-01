// ignore_for_file: avoid_print
//
// Dispatcher-park profile harness — exp 115.
//
// Drives the reader pool with bursts of concurrent reads at increasing
// concurrency levels, snapshots `ProfileCounters` around each burst,
// and prints a per-concurrency table of:
//
//   parked_total       : total `_dispatch` await events
//   wake_retry_total   : woke from await but found no slot, re-parked
//                        (wake-amplification signal — should approach
//                        zero with FIFO/slot-handoff dispatch schemes)
//   max_parked         : peak concurrent parked dispatchers
//   wall_ms            : end-to-end burst wall time
//
// This is measurement-only. The counters are gated behind
// `kProfileMode` and tree-shake out of release builds; the harness
// must be run with `-DRESQLITE_PROFILE=true` for the numbers to be
// non-zero.
//
// Usage:
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/dispatcher_park_profile.dart
//
// Optional --markdown writes a committable markdown table to
// `benchmark/profile/results/exp-115-dispatcher-park-aggregate.md`.

import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/profile_counters.dart';
import 'package:resqlite/src/profile_mode.dart';

const List<int> _concurrencyLevels = [1, 2, 4, 8, 16, 32];
const int _bursts = 5;
const int _warmupBursts = 2;

class _Result {
  _Result({
    required this.concurrency,
    required this.parked,
    required this.retries,
    required this.maxParked,
    required this.wallUs,
  });

  final int concurrency;
  final int parked;
  final int retries;
  final int maxParked;
  final int wallUs;
}

Future<void> main(List<String> args) async {
  if (!kProfileMode) {
    stderr.writeln(
      'WARNING: kProfileMode is false — counters will report zero.\n'
      'Run with: dart run -DRESQLITE_PROFILE=true '
      'benchmark/profile/dispatcher_park_profile.dart',
    );
  }

  final writeMarkdown = args.contains('--markdown');

  final tempDir = await Directory.systemTemp.createTemp('exp115_');
  final db = await Database.open('${tempDir.path}/test.db');
  try {
    await db.execute('CREATE TABLE items(id INTEGER PRIMARY KEY, v INTEGER)');
    await db.executeBatch(
      'INSERT INTO items(v) VALUES (?)',
      List.generate(1000, (i) => [i]),
    );

    // Warmup — let JIT settle and prime the reader workers.
    for (var i = 0; i < _warmupBursts; i++) {
      await _runBurst(db, _concurrencyLevels.last);
    }

    final results = <_Result>[];
    for (final n in _concurrencyLevels) {
      // Median across bursts for stability.
      final parked = <int>[];
      final retries = <int>[];
      final maxParked = <int>[];
      final wallUs = <int>[];
      for (var b = 0; b < _bursts; b++) {
        final r = await _runBurst(db, n);
        parked.add(r.parked);
        retries.add(r.retries);
        maxParked.add(r.maxParked);
        wallUs.add(r.wallUs);
      }
      results.add(
        _Result(
          concurrency: n,
          parked: _medianInt(parked),
          retries: _medianInt(retries),
          maxParked: _medianInt(maxParked),
          wallUs: _medianInt(wallUs),
        ),
      );
    }

    final readerCount = _readerPoolSize();
    print('');
    print(
      'Reader pool size (Platform.numberOfProcessors-1, clamped 2..4): '
      '$readerCount',
    );
    print(
      'Bursts per concurrency level: $_bursts (after $_warmupBursts warmup)',
    );
    print('');
    _printTable(results);

    if (writeMarkdown) {
      final outFile = File(
        'benchmark/profile/results/exp-115-dispatcher-park-aggregate.md',
      );
      await outFile.writeAsString(_renderMarkdown(results, readerCount));
      print('');
      print('Wrote ${outFile.path}');
    }
  } finally {
    await db.close();
    await tempDir.delete(recursive: true);
  }
}

Future<_Result> _runBurst(Database db, int concurrency) async {
  ProfileCounters.reset();
  final sw = Stopwatch()..start();
  final futures = <Future<void>>[];
  for (var i = 0; i < concurrency; i++) {
    futures.add(_query(db));
  }
  await Future.wait(futures);
  sw.stop();
  return _Result(
    concurrency: concurrency,
    parked: ProfileCounters.dispatcherParkedTotal,
    retries: ProfileCounters.dispatcherWakeRetryTotal,
    maxParked: ProfileCounters.dispatcherMaxParkedConcurrent,
    wallUs: sw.elapsedMicroseconds,
  );
}

Future<void> _query(Database db) async {
  // A medium-cost read so workers stay busy long enough to force
  // backpressure when concurrency exceeds the pool size.
  await db.select('SELECT v FROM items WHERE v >= ? AND v < ?', [0, 1000]);
}

int _readerPoolSize() => (Platform.numberOfProcessors - 1).clamp(2, 4);

int _medianInt(List<int> values) {
  if (values.isEmpty) return 0;
  final sorted = List<int>.from(values)..sort();
  return sorted[sorted.length ~/ 2];
}

void _printTable(List<_Result> rows) {
  print(
    '| concurrency | parked_total | wake_retry_total | max_parked | wall_ms |',
  );
  print('|---:|---:|---:|---:|---:|');
  for (final r in rows) {
    final wallMs = (r.wallUs / 1000).toStringAsFixed(2);
    print(
      '| ${r.concurrency} | ${r.parked} | ${r.retries} | ${r.maxParked} | $wallMs |',
    );
  }
}

String _renderMarkdown(List<_Result> rows, int readerCount) {
  final sb = StringBuffer();
  sb.writeln('# Experiment 115 — Dispatcher Park Counters');
  sb.writeln();
  sb.writeln(
    'Profile-mode harness: '
    '`benchmark/profile/dispatcher_park_profile.dart`',
  );
  sb.writeln();
  sb.writeln(
    'Reader pool size: $readerCount '
    '(`(Platform.numberOfProcessors - 1).clamp(2, 4)`)',
  );
  sb.writeln(
    'Bursts per concurrency level: $_bursts '
    '(after $_warmupBursts warmup)',
  );
  sb.writeln();
  sb.writeln(
    'Workload: `SELECT v FROM items WHERE v >= ? AND v < ?` '
    'fanned out at the listed concurrency. Each burst awaits all '
    'queries; counters are reset between bursts and the median for each '
    'reported column is taken across bursts.',
  );
  sb.writeln();
  sb.writeln(
    '| concurrency | parked_total | wake_retry_total | '
    'max_parked | wall_ms |',
  );
  sb.writeln('|---:|---:|---:|---:|---:|');
  for (final r in rows) {
    final wallMs = (r.wallUs / 1000).toStringAsFixed(2);
    sb.writeln(
      '| ${r.concurrency} | ${r.parked} | ${r.retries} | '
      '${r.maxParked} | $wallMs |',
    );
  }
  sb.writeln();
  sb.writeln('## Reading the table');
  sb.writeln();
  sb.writeln(
    '- `parked_total` increments each time `_dispatch` awaits '
    '`_workerAvailable` after finding no worker currently available '
    'for dispatch.',
  );
  sb.writeln(
    '- `wake_retry_total` increments when the dispatcher resumes '
    'from `await` but finds no slot on the next scan and re-parks. '
    'With shared-completer wakeup, a single worker-free event wakes '
    'every parked dispatcher; exactly one wins the slot and the rest '
    're-park. FIFO or slot-handoff dispatch should keep this counter '
    'near zero.',
  );
  sb.writeln(
    '- `max_parked` is the peak observed concurrency of parked '
    'dispatchers across the burst. A peak above the pool size is the '
    'precondition for any reader-pool-internal dispatch optimization '
    '(exp 114-style FIFO swap, slot handoff) to be measurable.',
  );
  sb.writeln();
  sb.writeln('## What this enables');
  sb.writeln();
  sb.writeln(
    'Future dispatch-area experiments (exp 114 archive, exp 083 '
    'pre-dispatch queue, slot-handoff variants) can now be evaluated '
    'against direct evidence that the parked-dispatcher path was '
    'exercised, instead of inferring it from a wall-time delta on a '
    'workload that may not even reach `_workerAvailable`.',
  );
  return sb.toString();
}
