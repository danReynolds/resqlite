// ignore_for_file: avoid_print
//
// Many-streams writer-throughput profile harness — A11c reconnaissance.
//
// Runs the A11c shape (1 wide table, N streams subscribed, sequential
// single-row UPDATEs with microtask yields between writes) on resqlite
// only and emits per-write timing breakdowns:
//
//   t_writer_us         : await peer.execute(...) — writer round-trip
//                         only, before stream-engine.invalidate is called.
//                         This is the writer-isolate dispatch + SQL +
//                         WAL commit cost. Independent of N.
//   t_invalidate_us     : synchronous body of StreamEngine.onDependencyChanges
//                         on the main isolate — _tableIndex lookup +
//                         dirty-set fanout + _flushQueue scheduling.
//                         Scales with N.
//   t_yield_us          : two `Future.delayed(Duration.zero)` yields
//                         after the write — drains the microtask queue
//                         and gives the reader pool / listener
//                         microtasks a turn. The "fanout drain" surrogate.
//   t_total_us          : full per-write wall, await-to-await.
//
// The 50-stream baseline run skips invalidate by registering zero
// streams. Disjoint and overlap both register N streams and differ
// only in the column written.
//
// Output: `benchmark/profile/results/a11c_writer_profile_<scenario>_<ts>.json`
// per scenario (raw, gitignored). Aggregate .md is committed.
//
// Usage:
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/many_streams_writer_profile.dart [--out=PREFIX]
//
// This harness is resqlite-only by design — A11c's peer comparison is
// in benchmark/suites/many_streams_writer_throughput.dart; here we only
// want to characterize where resqlite's own ~17 µs/write of fanout cost
// lives so the next experiment is informed.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/profile_counters.dart';
import 'package:resqlite/src/profile_mode.dart';

// Workload constants — match suite when reasonable, but cut iterations
// because we want per-write samples, not throughput medians. The
// stream-count sweep variant (--scaling) overrides _streamCount and
// runs disjoint+overlap at multiple N values to reveal whether fanout
// cost is per-stream linear or flat overhead.
const int _rowCount = 5000;
const int _streamCount = 50;
const int _writeCount = 500;
const int _iterations = 3;
const int _warmup = 1;
const List<int> _scalingNs = [0, 5, 10, 25, 50];

class _Sample {
  _Sample({
    required this.scenario,
    required this.iter,
    required this.writeIndex,
    required this.writerUs,
    required this.yieldUs,
    required this.totalUs,
    required this.invalidateUs,
    required this.intersectionUs,
    required this.intersectionEntries,
  });

  final String scenario;
  final int iter;
  final int writeIndex;
  final int writerUs;
  final int yieldUs;
  final int totalUs;

  /// Microseconds spent inside the synchronous body of
  /// `StreamEngine.onDependencyChanges` for this write. Subset of `writerUs`
  /// (which also includes the writer-isolate round-trip and reply
  /// microtask). Zero in the baseline scenario (no streams).
  final int invalidateUs;

  /// Microseconds spent specifically in per-entry column-set intersection
  /// probes for this write. Subset of `invalidateUs`. Sum across
  /// `intersectionEntries` per-watcher probes; per-watcher cost is
  /// `intersectionUs / intersectionEntries`.
  final int intersectionUs;
  final int intersectionEntries;

  Map<String, Object?> toJson() => {
    'scenario': scenario,
    'iter': iter,
    'i': writeIndex,
    'writer_us': writerUs,
    'yield_us': yieldUs,
    'total_us': totalUs,
    'invalidate_us': invalidateUs,
    'intersection_us': intersectionUs,
    'intersection_entries': intersectionEntries,
  };
}

Future<void> main(List<String> args) async {
  String? outPrefix;
  var scaling = false;
  for (final a in args) {
    if (a.startsWith('--out=')) {
      outPrefix = a.substring('--out='.length);
    } else if (a == '--scaling') {
      scaling = true;
    } else if (a == '--help' || a == '-h') {
      _printUsage();
      return;
    }
  }

  print('A11c many-streams writer-throughput profile (resqlite only)');
  print('============================================================');
  print(
    '  rowCount=$_rowCount streamCount=$_streamCount '
    'writeCount=$_writeCount iters=$_iterations warmup=$_warmup',
  );
  print(
    '  kProfileMode=$kProfileMode '
    '(Timeline markers ${kProfileMode ? 'active' : 'tree-shaken'})',
  );
  print('');

  final tempDir = await Directory.systemTemp.createTemp('a11c_profile_');
  final db = await Database.open('${tempDir.path}/test.db');

  final colNames = [
    for (var i = 0; i < 20; i++) String.fromCharCode('a'.codeUnitAt(0) + i),
  ];
  final createSql =
      'CREATE TABLE wide(id INTEGER PRIMARY KEY, ' +
      colNames.map((c) => '$c TEXT NOT NULL').join(', ') +
      ')';
  final insertSql =
      'INSERT INTO wide(id, ${colNames.join(', ')}) '
      'VALUES (?, ${List.filled(colNames.length, '?').join(', ')})';

  try {
    await db.execute(createSql);
    await db.executeBatch(insertSql, [
      for (var i = 0; i < _rowCount; i++) [i, for (final _ in colNames) 'v$i'],
    ]);

    final allSamples = <_Sample>[];

    if (scaling) {
      // Stream-count scaling sweep — disjoint only. Reveals per-stream
      // linear vs flat overhead. We use disjoint because hash
      // short-circuit suppresses listener delivery so the per-write
      // cost cleanly reflects re-query dispatch.
      for (final n in _scalingNs) {
        print('=== Scaling N=$n streams (disjoint, UPDATE wide SET c = ?) ===');
        allSamples.addAll(
          await _runScenario(
            db,
            scenario: 'scale_n$n',
            streamCount: n,
            updateSql: 'UPDATE wide SET c = ? WHERE id = ?',
            valueFor: (writeIndex, iteration) => 'd$iteration-$writeIndex',
          ),
        );
      }
    } else {
      // BASELINE — 0 streams subscribed, write column c.
      print('=== Baseline (0 streams, UPDATE wide SET c = ?) ===');
      allSamples.addAll(
        await _runScenario(
          db,
          scenario: 'baseline',
          streamCount: 0,
          updateSql: 'UPDATE wide SET c = ? WHERE id = ?',
          valueFor: (writeIndex, iteration) => 'b$iteration-$writeIndex',
        ),
      );

      // DISJOINT — N streams projecting (id, a, b), write column c.
      print('=== Disjoint ($_streamCount streams, UPDATE wide SET c = ?) ===');
      allSamples.addAll(
        await _runScenario(
          db,
          scenario: 'disjoint',
          streamCount: _streamCount,
          updateSql: 'UPDATE wide SET c = ? WHERE id = ?',
          valueFor: (writeIndex, iteration) => 'd$iteration-$writeIndex',
        ),
      );

      // OVERLAP — N streams projecting (id, a, b), write column a.
      print('=== Overlap ($_streamCount streams, UPDATE wide SET a = ?) ===');
      allSamples.addAll(
        await _runScenario(
          db,
          scenario: 'overlap',
          streamCount: _streamCount,
          updateSql: 'UPDATE wide SET a = ? WHERE id = ?',
          valueFor: (writeIndex, iteration) => 'z$iteration-$writeIndex',
        ),
      );
    }

    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final prefix = outPrefix ?? 'benchmark/profile/results/a11c_writer_profile';
    final outDir = Directory(File(prefix).parent.path);
    if (!outDir.existsSync()) outDir.createSync(recursive: true);

    final rawPath = '${prefix}_$ts.json';
    await File(rawPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'generated_at': DateTime.now().toIso8601String(),
        'profile_mode_enabled': kProfileMode,
        'config': {
          'rowCount': _rowCount,
          'streamCount': _streamCount,
          'writeCount': _writeCount,
          'iterations': _iterations,
          'warmup': _warmup,
        },
        'samples': allSamples.map((s) => s.toJson()).toList(),
      }),
    );
    print('');
    print('Raw samples: $rawPath');

    final agg = _aggregate(allSamples);
    print('');
    print(agg);
  } finally {
    await db.close();
    await tempDir.delete(recursive: true);
  }
}

Future<List<_Sample>> _runScenario(
  Database db, {
  required String scenario,
  required int streamCount,
  required String updateSql,
  required String Function(int writeIndex, int iteration) valueFor,
}) async {
  final samples = <_Sample>[];

  for (var iter = 0; iter < _warmup + _iterations; iter++) {
    final isWarmup = iter < _warmup;

    final initialCompleters = <Completer<void>>[];
    final subs = <StreamSubscription<List<Map<String, Object?>>>>[];
    final emitCounts = List<int>.filled(streamCount, 0);

    for (var i = 0; i < streamCount; i++) {
      final idx = i;
      final initial = Completer<void>();
      initialCompleters.add(initial);
      final partWidth = _rowCount ~/ streamCount;
      final partStart = idx * partWidth;
      final partEnd = partStart + partWidth;
      final sub = db
          .stream(
            'SELECT id, a, b FROM wide WHERE id >= ? AND id < ? ORDER BY id',
            [partStart, partEnd],
          )
          .listen((_) {
            if (!initial.isCompleted) {
              initial.complete();
            } else {
              emitCounts[idx]++;
            }
          });
      subs.add(sub);
    }

    try {
      // Drain initial emissions before timing.
      if (streamCount > 0) {
        await _waitUntil(
          predicate: () => initialCompleters.every((c) => c.isCompleted),
          timeout: const Duration(seconds: 60),
        );
      }

      // Per-write breakdown.
      //
      // db.execute() awaits the writer-isolate round-trip. Once the
      // writer returns, Database.execute() synchronously calls
      // _streamEngine.onDependencyChanges(...) which runs the dirty-set
      // fanout (cheap: hash-set unions over _tableIndex), enqueues all
      // dirty entries, and *kicks off* _flushQueue() — but the per-stream
      // selectIfChanged dispatches actually run on awaits inside
      // _flushQueue, which means they land during the yields below.
      //
      //   t_writer = await db.execute(...) — writer round-trip + the
      //              synchronous prefix of invalidate. Cheap fanout
      //              bookkeeping but NOT the per-stream re-query work.
      //   t_yield  = 2× Future.delayed(Duration.zero). The microtask
      //              queue drains here; reader-pool selectIfChanged
      //              dispatches and listener microtasks fire. This is
      //              where the bulk of the per-stream fanout cost lives.
      //   t_total  = both, await-to-await wall per write.
      //
      // The "fanout cost N streams add" is recovered as
      // `scenario.t_total - baseline.t_total`, decomposed by which of
      // (writer, yield) absorbed the extra work.
      final writerSw = Stopwatch();
      final yieldSw = Stopwatch();
      final totalSw = Stopwatch();

      for (var w = 0; w < _writeCount; w++) {
        totalSw
          ..reset()
          ..start();

        // Snapshot ProfileCounters before the write. The synchronous
        // body of StreamEngine.onDependencyChanges runs *inside* db.execute()
        // before the future resolves, so the counter delta is captured
        // entirely between these two snapshots.
        final invalUsBefore = ProfileCounters.invalidateUs;
        final isectUsBefore = ProfileCounters.intersectionUs;
        final isectEntriesBefore = ProfileCounters.intersectionEntries;

        writerSw
          ..reset()
          ..start();
        await db.execute(updateSql, [valueFor(w, iter), w % _rowCount]);
        writerSw.stop();

        final invalUs = ProfileCounters.invalidateUs - invalUsBefore;
        final isectUs = ProfileCounters.intersectionUs - isectUsBefore;
        final isectEntries =
            ProfileCounters.intersectionEntries - isectEntriesBefore;

        yieldSw
          ..reset()
          ..start();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        yieldSw.stop();

        totalSw.stop();

        if (!isWarmup) {
          samples.add(
            _Sample(
              scenario: scenario,
              iter: iter - _warmup,
              writeIndex: w,
              writerUs: writerSw.elapsedMicroseconds,
              yieldUs: yieldSw.elapsedMicroseconds,
              totalUs: totalSw.elapsedMicroseconds,
              invalidateUs: invalUs,
              intersectionUs: isectUs,
              intersectionEntries: isectEntries,
            ),
          );
        }
      }

      if (streamCount > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      var totalEmissions = 0;
      for (final c in emitCounts) {
        totalEmissions += c;
      }
      print(
        '  iter ${iter - _warmup}${isWarmup ? ' (warmup)' : ''}: '
        'emissions=$totalEmissions ${streamCount == 0 ? '(no streams)' : ''}',
      );
    } finally {
      for (final s in subs) {
        await s.cancel();
      }
    }
  }

  return samples;
}

String _aggregate(List<_Sample> samples) {
  final byScenario = <String, List<_Sample>>{};
  for (final s in samples) {
    byScenario.putIfAbsent(s.scenario, () => []).add(s);
  }

  final buf = StringBuffer();
  buf.writeln('## Per-write timing breakdown (resqlite only, A11c shape)');
  buf.writeln();
  buf.writeln(
    'Each row is the **median** of $_writeCount per-iteration writes '
    '× $_iterations iterations after $_warmup warmup. `total_us` is the '
    'await-to-await wall per write (execute + 2 microtask yields). '
    '`writer_us` is the `await db.execute(...)` portion only — '
    'includes writer-isolate dispatch + SQL + WAL commit + the '
    'synchronous `streamEngine.onDependencyChanges` body. `yield_us` is the '
    '2× `Future.delayed(Duration.zero)` cost where reader-pool '
    'dispatches and listener microtasks settle.',
  );
  buf.writeln();
  buf.writeln(
    '| scenario | n | writer_us p50/p90/p99 | yield_us p50/p90/p99 '
    '| total_us p50/p90/p99 | invalidate_us p50 | isect_us p50 / per-watch | writes/sec |',
  );
  buf.writeln('|---|---:|---|---|---|---:|---:|---:|');
  // Default ordering for the standard 3-scenario run; scaling mode
  // sorts numerically below.
  final standard = ['baseline', 'disjoint', 'overlap'];
  final scenarios = byScenario.keys.toList();
  scenarios.sort((a, b) {
    final ai = standard.indexOf(a);
    final bi = standard.indexOf(b);
    if (ai >= 0 && bi >= 0) return ai.compareTo(bi);
    if (ai >= 0) return -1;
    if (bi >= 0) return 1;
    // Both scaling — extract trailing N.
    int parseN(String s) => int.tryParse(s.replaceFirst('scale_n', '')) ?? 0;
    return parseN(a).compareTo(parseN(b));
  });
  for (final scenario in scenarios) {
    final list = byScenario[scenario];
    if (list == null || list.isEmpty) continue;
    final w = _stats(list.map((s) => s.writerUs).toList());
    final y = _stats(list.map((s) => s.yieldUs).toList());
    final t = _stats(list.map((s) => s.totalUs).toList());
    final inv = _stats(list.map((s) => s.invalidateUs).toList());
    final isect = _stats(list.map((s) => s.intersectionUs).toList());
    // Per-watcher mean isolated from total intersection time / total
    // intersection-entries probed. Avoids /0 when no streams or no
    // dirtyColumns metadata.
    final isectTotal = list.fold<int>(0, (a, b) => a + b.intersectionUs);
    final entriesTotal = list.fold<int>(0, (a, b) => a + b.intersectionEntries);
    final perWatch = entriesTotal == 0
        ? '—'
        : (isectTotal / entriesTotal).toStringAsFixed(2);
    final wps = t.p50 == 0 ? 0 : (1e6 / t.p50);
    buf.writeln(
      '| $scenario | ${list.length} | ${w.p50}/${w.p90}/${w.p99} '
      '| ${y.p50}/${y.p90}/${y.p99} | ${t.p50}/${t.p90}/${t.p99} '
      '| ${inv.p50} | ${isect.p50} / $perWatch | '
      '${wps.toStringAsFixed(0)} |',
    );
  }
  buf.writeln();

  // Deltas.
  final base = byScenario['baseline'];
  final dis = byScenario['disjoint'];
  final ovr = byScenario['overlap'];
  if (base != null && dis != null && ovr != null) {
    final bw = _stats(base.map((s) => s.writerUs).toList()).p50;
    final dw = _stats(dis.map((s) => s.writerUs).toList()).p50;
    final ow = _stats(ovr.map((s) => s.writerUs).toList()).p50;
    final by = _stats(base.map((s) => s.yieldUs).toList()).p50;
    final dy = _stats(dis.map((s) => s.yieldUs).toList()).p50;
    final oy = _stats(ovr.map((s) => s.yieldUs).toList()).p50;
    final bt = _stats(base.map((s) => s.totalUs).toList()).p50;
    final dt = _stats(dis.map((s) => s.totalUs).toList()).p50;
    final ot = _stats(ovr.map((s) => s.totalUs).toList()).p50;
    buf.writeln('## Fanout deltas vs baseline (medians)');
    buf.writeln();
    buf.writeln(
      '| scenario | Δwriter_us | Δyield_us | Δtotal_us '
      '| writes/sec |',
    );
    buf.writeln('|---|---:|---:|---:|---:|');
    buf.writeln(
      '| baseline | 0 | 0 | 0 | ${bt == 0 ? 0 : (1e6 / bt).round()} '
      '|',
    );
    buf.writeln(
      '| disjoint | ${dw - bw} | ${dy - by} | ${dt - bt} '
      '| ${dt == 0 ? 0 : (1e6 / dt).round()} |',
    );
    buf.writeln(
      '| overlap  | ${ow - bw} | ${oy - by} | ${ot - bt} '
      '| ${ot == 0 ? 0 : (1e6 / ot).round()} |',
    );
    buf.writeln();
    buf.writeln('## Disjoint-vs-overlap delta');
    buf.writeln();
    buf.writeln(
      '`overlap.total - disjoint.total = ${ot - dt} μs/write`. '
      'This is the absolute time exp 075\'s worker-side hash '
      'short-circuit saves on disjoint writes — the per-stream '
      're-query still runs on disjoint, but the hash compares equal '
      'so emission to the listener is suppressed.',
    );
    buf.writeln();
  }
  buf.writeln('## Notes');
  buf.writeln();
  buf.writeln(
    '- writer_us **includes** the synchronous body of '
    '`StreamEngine.onDependencyChanges(...)` that runs inside '
    '`Database.execute()` before the future resolves. The harness '
    'does not split them externally without touching production code; '
    'the writer fanout cost is recovered as the '
    '`scenario.writer - baseline.writer` delta above.',
  );
  buf.writeln(
    '- yield_us is where the reader-pool '
    '`selectIfChanged` dispatches and listener microtasks land. '
    'When this number scales with N, the cost is per-stream dispatch; '
    'when it stays flat, it is fixed per-write overhead.',
  );
  buf.writeln(
    '- Numbers below ~5 μs are at the edge of Stopwatch '
    'resolution on this hardware — interpret with caution.',
  );
  buf.writeln();
  return buf.toString();
}

class _Stats {
  _Stats(this.p50, this.p90, this.p99, this.max);
  final int p50;
  final int p90;
  final int p99;
  final int max;
}

_Stats _stats(List<int> xs) {
  if (xs.isEmpty) return _Stats(0, 0, 0, 0);
  final sorted = [...xs]..sort();
  int pct(double p) {
    final idx = ((sorted.length - 1) * p).round();
    return sorted[idx];
  }

  return _Stats(pct(0.5), pct(0.9), pct(0.99), sorted.last);
}

Future<void> _waitUntil({
  required bool Function() predicate,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('predicate did not settle', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void _printUsage() {
  print(
    'Usage: dart run -DRESQLITE_PROFILE=true '
    'benchmark/profile/many_streams_writer_profile.dart '
    '[--out=PREFIX] [--scaling]',
  );
  print('');
  print('  --out=PREFIX  Path prefix for raw JSON output. Defaults to');
  print('                benchmark/profile/results/a11c_writer_profile');
  print('  --scaling     Run a stream-count sweep (N=$_scalingNs) instead');
  print('                of the standard baseline+disjoint+overlap trio.');
  print('                Reveals whether fanout cost is per-stream linear');
  print('                or flat per-write.');
}
