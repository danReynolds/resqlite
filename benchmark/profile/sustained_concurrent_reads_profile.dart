// ignore_for_file: avoid_print
//
// Sustained concurrent-reads parking stress — exp 139.
//
// Holds `concurrency` reads in-flight continuously for `--duration-ms`
// milliseconds at each sweep level. The short-burst exp 115 harness
// fires N reads, awaits them all, then resets the counters — it cannot
// distinguish "FIFO holds for one burst" from "FIFO holds when the
// waiter queue is continuously refilled across many wake/admit cycles
// while late lanes overlap early lanes' completions."
//
// signals.json#stream-rerun-dispatch.openCandidates lists
// "long-running concurrent-reads workload that sustains parked
// dispatchers past pool size" (addedAfter: 115, addedDate:
// 2026-04-30). exp 114's archive future-notes ask the same thing:
// dispatch-internal optimization can only be re-evaluated against a
// workload that surfaces non-zero wake retries.
//
// Lane pattern. Each of `concurrency` lanes runs a loop:
//   while (sw.elapsedMilliseconds < durationMs) await _query(...);
// At any instant ~concurrency queries are in flight. As one lane's
// query completes, the same lane awaits the next one — keeping the
// pool's waiter queue continuously refilled instead of going through
// a barrier between bursts. Half the lanes run a fast point query
// (~10 µs per call) and half run a 1k-row range scan (~150 µs per
// call) so worker slot release order does not match lane launch
// order, which is the ordering condition FIFO has to handle
// correctly.
//
// What this measures:
//   parked_total       per-sweep total ReaderPool._dispatch parks
//   wake_retry_total   wake-amplification — FIFO must keep this 0
//   max_parked         peak concurrent parked dispatchers
//   completed_queries  throughput proxy
//
// Reading the table:
//   - At concurrency == pool size: zero parking expected; lanes never
//     contend.
//   - Above pool size: parked_total grows with duration × overflow;
//     max_parked is roughly concurrency - pool size if all lanes are
//     in flight when scanning fails. wake_retry must stay 0.
//   - If wake_retry > 0 under sustained pressure, FIFO has a leak the
//     short-burst harness cannot see, and exp 114's archived FIFO
//     redesign or a slot-handoff variant becomes worth re-evaluating
//     on this workload.
//
// Usage:
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/sustained_concurrent_reads_profile.dart
//
//   --duration-ms=N   sustained pressure per concurrency level
//                     (default 1000)
//   --concurrencies=4,8,16,32   sweep override
//   --markdown        write
//                     benchmark/profile/results/exp-139-sustained-park-aggregate.md

import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/profile_counters.dart';
import 'package:resqlite/src/profile_mode.dart';

const List<int> _defaultConcurrencies = [4, 8, 16, 32];
const int _passes = 5;
const int _warmupPasses = 2;
const int _defaultDurationMs = 1000;
const int _rowCount = 1000;

class _Result {
  _Result({
    required this.concurrency,
    required this.parked,
    required this.retries,
    required this.maxParked,
    required this.completed,
    required this.wallUs,
  });

  final int concurrency;
  final int parked;
  final int retries;
  final int maxParked;
  final int completed;
  final int wallUs;
}

Future<void> main(List<String> args) async {
  if (!kProfileMode) {
    stderr.writeln(
      'WARNING: kProfileMode is false — counters will report zero.\n'
      'Run with: dart run -DRESQLITE_PROFILE=true '
      'benchmark/profile/sustained_concurrent_reads_profile.dart',
    );
  }

  final writeMarkdown = args.contains('--markdown');
  final durationMs = _intArg(args, '--duration-ms', _defaultDurationMs);
  final concurrencies = _intListArg(args, '--concurrencies', _defaultConcurrencies);

  final tempDir = await Directory.systemTemp.createTemp('exp139_');
  final db = await Database.open('${tempDir.path}/test.db');
  try {
    await db.execute('CREATE TABLE items(id INTEGER PRIMARY KEY, v INTEGER)');
    await db.executeBatch(
      'INSERT INTO items(v) VALUES (?)',
      List.generate(_rowCount, (i) => [i]),
    );

    // Warmup at the highest concurrency level to settle JIT and prime
    // the reader workers, matching the exp 115 harness convention.
    for (var i = 0; i < _warmupPasses; i++) {
      await _runSustained(db, concurrencies.last, durationMs);
    }

    final results = <_Result>[];
    for (final n in concurrencies) {
      final parked = <int>[];
      final retries = <int>[];
      final maxParked = <int>[];
      final completed = <int>[];
      final wallUs = <int>[];
      for (var p = 0; p < _passes; p++) {
        final r = await _runSustained(db, n, durationMs);
        parked.add(r.parked);
        retries.add(r.retries);
        maxParked.add(r.maxParked);
        completed.add(r.completed);
        wallUs.add(r.wallUs);
      }
      results.add(
        _Result(
          concurrency: n,
          parked: _medianInt(parked),
          retries: _medianInt(retries),
          maxParked: _medianInt(maxParked),
          completed: _medianInt(completed),
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
      'Passes per concurrency level: $_passes (after $_warmupPasses warmup), '
      'sustained $durationMs ms each',
    );
    print('');
    _printTable(results);

    if (writeMarkdown) {
      final outFile = File(
        'benchmark/profile/results/exp-139-sustained-park-aggregate.md',
      );
      await outFile.writeAsString(
        _renderMarkdown(results, readerCount, durationMs),
      );
      print('');
      print('Wrote ${outFile.path}');
    }
  } finally {
    await db.close();
    await tempDir.delete(recursive: true);
  }
}

/// Sustain `concurrency` in-flight reads for `durationMs` milliseconds.
///
/// Each lane runs `while (deadline not reached) await query();`. As a
/// query completes, the same lane awaits the next one — keeping the
/// pool's waiter queue continuously refilled instead of going through
/// the burst/barrier pattern of `Future.wait`.
Future<_Result> _runSustained(
  Database db,
  int concurrency,
  int durationMs,
) async {
  ProfileCounters.reset();
  final sw = Stopwatch()..start();
  final deadlineMs = durationMs;
  var completed = 0;

  Future<void> runLane(int laneId) async {
    // Lanes split evenly between a fast point query and a 1k-row range
    // scan so the order in which workers finish does not match the
    // order in which lanes parked. If FIFO is correct it doesn't care
    // about that match; if it isn't this surfaces the bug.
    final useRange = laneId.isEven;
    while (sw.elapsedMilliseconds < deadlineMs) {
      if (useRange) {
        await db.select(
          'SELECT v FROM items WHERE v >= ? AND v < ?',
          [0, _rowCount],
        );
      } else {
        await db.select(
          'SELECT id FROM items WHERE id = ?',
          [laneId % _rowCount],
        );
      }
      completed++;
    }
  }

  await Future.wait(List.generate(concurrency, runLane));
  sw.stop();

  return _Result(
    concurrency: concurrency,
    parked: ProfileCounters.dispatcherParkedTotal,
    retries: ProfileCounters.dispatcherWakeRetryTotal,
    maxParked: ProfileCounters.dispatcherMaxParkedConcurrent,
    completed: completed,
    wallUs: sw.elapsedMicroseconds,
  );
}

int _readerPoolSize() => (Platform.numberOfProcessors - 1).clamp(2, 4);

int _medianInt(List<int> values) {
  if (values.isEmpty) return 0;
  final sorted = List<int>.from(values)..sort();
  return sorted[sorted.length ~/ 2];
}

int _intArg(List<String> args, String flag, int defaultValue) {
  for (final arg in args) {
    if (arg.startsWith('$flag=')) {
      return int.parse(arg.substring(flag.length + 1));
    }
  }
  return defaultValue;
}

List<int> _intListArg(List<String> args, String flag, List<int> defaultValue) {
  for (final arg in args) {
    if (arg.startsWith('$flag=')) {
      return arg
          .substring(flag.length + 1)
          .split(',')
          .map((s) => int.parse(s.trim()))
          .toList();
    }
  }
  return defaultValue;
}

void _printTable(List<_Result> rows) {
  print(
    '| concurrency | parked_total | wake_retry_total | max_parked | '
    'completed | wall_ms |',
  );
  print('|---:|---:|---:|---:|---:|---:|');
  for (final r in rows) {
    final wallMs = (r.wallUs / 1000).toStringAsFixed(2);
    print(
      '| ${r.concurrency} | ${r.parked} | ${r.retries} | ${r.maxParked} | '
      '${r.completed} | $wallMs |',
    );
  }
}

String _renderMarkdown(
  List<_Result> rows,
  int readerCount,
  int durationMs,
) {
  final sb = StringBuffer();
  sb.writeln('# Experiment 139 — Sustained concurrent-reads parking');
  sb.writeln();
  sb.writeln(
    'Profile-mode harness: '
    '`benchmark/profile/sustained_concurrent_reads_profile.dart`',
  );
  sb.writeln();
  sb.writeln(
    'Reader pool size: $readerCount '
    '(`(Platform.numberOfProcessors - 1).clamp(2, 4)`)',
  );
  sb.writeln(
    'Passes per concurrency level: $_passes '
    '(after $_warmupPasses warmup), sustained $durationMs ms each',
  );
  sb.writeln();
  sb.writeln(
    'Workload: each of `concurrency` lanes runs '
    '`while (deadline not reached) await select();`. Even-indexed lanes '
    'fire a 1k-row range scan; odd-indexed lanes fire a single-row '
    'point query. As one query completes the same lane awaits the '
    'next, so the pool waiter queue is continuously refilled instead '
    'of barriering through `Future.wait` between bursts.',
  );
  sb.writeln();
  sb.writeln(
    '| concurrency | parked_total | wake_retry_total | '
    'max_parked | completed | wall_ms |',
  );
  sb.writeln('|---:|---:|---:|---:|---:|---:|');
  for (final r in rows) {
    final wallMs = (r.wallUs / 1000).toStringAsFixed(2);
    sb.writeln(
      '| ${r.concurrency} | ${r.parked} | ${r.retries} | '
      '${r.maxParked} | ${r.completed} | $wallMs |',
    );
  }
  sb.writeln();
  sb.writeln('## Reading the table');
  sb.writeln();
  sb.writeln(
    '- `parked_total` accumulates over the whole sustained pass, '
    'so absolute values are durationMs-dependent. Compare ratios '
    'and growth shape across concurrency rather than raw counts.',
  );
  sb.writeln(
    '- `wake_retry_total` is the load-bearing column. Exp 118 (FIFO '
    'one-shot waiters) drove this to zero on short bursts; the open '
    'question for exp 139 was whether the invariant survives '
    'continuously-refilled waiter queues and out-of-order slot '
    'release. Any non-zero value here would surface a leak the '
    'short-burst exp 115 harness cannot see.',
  );
  sb.writeln(
    '- `max_parked` is the peak observed parking depth. With the lane '
    'pattern, in-flight count is bounded by `concurrency`; at '
    'concurrency above the pool size the steady-state queue depth is '
    'roughly `concurrency - readerCount`.',
  );
  sb.writeln(
    '- `completed` is total queries finished during the pass; it is '
    'a throughput proxy that scales with concurrency up to the pool '
    'size, then plateaus (SQLite serializes work across the worker '
    'pool).',
  );
  sb.writeln();
  sb.writeln('## What this enables');
  sb.writeln();
  sb.writeln(
    'Closes the `long-running concurrent-reads workload that sustains '
    'parked dispatchers past pool size` open candidate in '
    '`signals.json#stream-rerun-dispatch`. If a future reader-pool '
    'dispatch idea (slot handoff, work-stealing, exp 114-style '
    'reawakening) needs to show measurable headroom, run it against '
    'this harness and compare `parked_total`, `wake_retry_total`, and '
    'wall_ms — the short-burst exp 115 harness will not surface '
    'sustained-pressure regressions.',
  );
  return sb.toString();
}
