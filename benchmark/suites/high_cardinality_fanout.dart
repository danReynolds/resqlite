// ignore_for_file: avoid_print

/// A11b — High-Cardinality Stream Fan-out (v1).
///
/// 100 reactive streams watching distinct partitions of a 10K-item
/// table (items grouped into 100 owners × 100 items each). Each
/// stream runs `SELECT id, value FROM items WHERE owner_id = ?`
/// against a unique owner_id. Then a burst of 200 random-item writes
/// invalidates some fraction of the streams.
///
/// The existing `streaming/fan_out.dart` microbenchmark tests 10
/// streams. Real Flutter list views with reactive rows have ~50-200
/// simultaneous watchers. This workload measures whether a library's
/// stream engine scales to the upper end of that range without
/// falling over.
///
/// Peers: resqlite, sqlite_async. sqlite3.dart excluded (no streams).
///
/// ## Not registered in the default `run_all.dart` suite
///
/// Empirical measurements expose a non-linear cost in resqlite's
/// initial-emission drain: 100 fresh subscriptions take ~40 seconds
/// to all emit their first result, while sqlite_async drains in ~1.5s.
/// The root cause appears to be pool-fanout scheduling when many
/// `_createStream` calls race on a 4-worker reader pool — each
/// dispatch wakes every pending waiter, producing O(N²) microtask
/// churn. 200+ streams time out on a 2-minute budget.
///
/// Including A11b in the default suite would add 2-3 minutes to every
/// benchmark run until this pool issue is addressed. Instead the
/// workload is opt-in — run manually:
///
///     dart run benchmark/suites/high_cardinality_fanout.dart
///
/// When `--include-slow` lands (Phase 3 of Track A) this workload
/// will be wired up behind that flag. A v2 version bump can raise the
/// stream count once pool-fanout is improved.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../shared/peer.dart';
import '../shared/stats.dart';
import '../shared/workload.dart';

const WorkloadMeta highCardinalityFanoutMeta = WorkloadMeta(
  slug: 'high_cardinality_fanout',
  version: 1,
  title: 'High-Cardinality Stream Fan-out',
  description: '100 reactive streams each watching one of 100 owner '
      'partitions of a 10K-item table. 200 random-item writes target '
      'random items. Models Flutter list views with many simultaneous '
      'row watchers (detail screens, reactive timelines). Scaled to '
      '100 rather than the originally-planned 500 because pool fanout '
      'of fresh subscriptions scales non-linearly — 200+ streams time '
      'out on initial-emission drain. Full bench stays under ~90s at '
      'this scale.',
);

const int _itemCount = 10000;
const int _streamCount = 100;
const int _writeCount = 200;
const int _warmup = 1;
const int _iterations = 2;
const int _prngSeed = 0xCAFEF0;

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

/// Benchmark entry — uses production-scale constants (100 streams ×
/// 200 writes, 1 warmup + 2 measured iterations).
Future<String> runHighCardinalityFanoutBenchmark() =>
    _runFanoutBenchmark(
      streamCount: _streamCount,
      writeCount: _writeCount,
      warmup: _warmup,
      iterations: _iterations,
    );

/// Test entry — runs at a reduced scale so the DoD unit test can
/// complete in seconds rather than minutes. Exposed only for tests;
/// production callers use [runHighCardinalityFanoutBenchmark].
Future<String> runHighCardinalityFanoutBenchmarkSmallForTest() =>
    _runFanoutBenchmark(
      streamCount: 20,
      writeCount: 50,
      warmup: 0,
      iterations: 1,
    );

Future<String> _runFanoutBenchmark({
  required int streamCount,
  required int writeCount,
  required int warmup,
  required int iterations,
}) async {
  final md = StringBuffer()
    ..writeln('## ${highCardinalityFanoutMeta.sectionHeading}')
    ..writeln()
    ..writeln(highCardinalityFanoutMeta.description)
    ..writeln()
    ..writeln('### $streamCount streams × $writeCount writes');
  md.writeln();

  final readings = <_Reading>[];
  final tempDir = await Directory.systemTemp.createTemp('bench_fanout_');
  try {
    final peers = await PeerSet.open(
      tempDir.path,
      require: (p) => p.hasStreams,
    );
    try {
      for (final peer in peers.all) {
        print('  running on ${peer.name}...');
        final r = await _measure(
          peer,
          streamCount: streamCount,
          writeCount: writeCount,
          warmup: warmup,
          iterations: iterations,
        );
        readings.add(r);
      }
    } finally {
      await peers.closeAll();
    }
  } finally {
    await tempDir.delete(recursive: true);
  }

  _writeResults(md, readings, streamCount: streamCount, writeCount: writeCount);
  return md.toString();
}

// ---------------------------------------------------------------------------
// Measurement
// ---------------------------------------------------------------------------

final class _Reading {
  _Reading({
    required this.label,
    required this.timing,
    required this.medianInitialDrainMs,
    required this.medianWriteBurstMs,
    required this.medianEmissions,
  });

  final String label;

  /// End-to-end wall: initial drain + write burst + settle. This is
  /// what the `BenchmarkTiming` columns report in the markdown.
  final BenchmarkTiming timing;

  /// Isolated median: time to drain all 500 initial emissions (how
  /// long the library takes to spin up the subscriber fleet).
  final double medianInitialDrainMs;

  /// Isolated median: time from "first write dispatched" to "all
  /// emissions settled" (how long the library takes to process the
  /// write burst against 500 active subscribers).
  final double medianWriteBurstMs;

  /// Post-baseline emission count across all 500 streams.
  final int medianEmissions;
}

Future<_Reading> _measure(
  BenchmarkPeer peer, {
  required int streamCount,
  required int writeCount,
  required int warmup,
  required int iterations,
}) async {
  await _seed(peer, streamCount);

  final timing = BenchmarkTiming(peer.label);
  final initialDrainsMs = <double>[];
  final writeBurstsMs = <double>[];
  final emissionsByIter = <int>[];

  for (var iter = 0; iter < warmup + iterations; iter++) {
    final r = await _singleIteration(peer,
        streamCount: streamCount, writeCount: writeCount);
    if (iter >= warmup) {
      timing.record(
        wallMicroseconds: r.totalWallUs,
        mainMicroseconds: r.listenerUs,
      );
      initialDrainsMs.add(r.initialDrainUs / 1000.0);
      writeBurstsMs.add(r.writeBurstUs / 1000.0);
      emissionsByIter.add(r.postBaselineEmissions);
    }
  }

  return _Reading(
    label: peer.label,
    timing: timing,
    medianInitialDrainMs: _medianD(initialDrainsMs),
    medianWriteBurstMs: _medianD(writeBurstsMs),
    medianEmissions: _median(emissionsByIter),
  );
}

final class _IterResult {
  _IterResult({
    required this.totalWallUs,
    required this.initialDrainUs,
    required this.writeBurstUs,
    required this.listenerUs,
    required this.postBaselineEmissions,
  });
  final int totalWallUs;
  final int initialDrainUs;
  final int writeBurstUs;
  final int listenerUs;
  final int postBaselineEmissions;
}

Future<_IterResult> _singleIteration(
  BenchmarkPeer peer, {
  required int streamCount,
  required int writeCount,
}) async {
  final prng = math.Random(_prngSeed);

  final emitCounts = List<int>.filled(streamCount, 0);
  var listenerUs = 0;
  final subs = <StreamSubscription<List<Map<String, Object?>>>>[];

  final totalSw = Stopwatch()..start();
  final initialSw = Stopwatch()..start();

  for (var i = 0; i < streamCount; i++) {
    final idx = i;
    final ownerId = i + 1;
    final sub = peer.watch(
      'SELECT id, value FROM items WHERE owner_id = ? ORDER BY id',
      [ownerId],
    ).listen((_) {
      final sw = Stopwatch()..start();
      emitCounts[idx]++;
      sw.stop();
      listenerUs += sw.elapsedMicroseconds;
    });
    subs.add(sub);
  }

  try {
    await _waitUntil(
      predicate: () => emitCounts.every((c) => c >= 1),
      timeout: const Duration(seconds: 120),
      description: 'initial emissions from all $streamCount streams',
    );
    initialSw.stop();
    final initialDrainUs = initialSw.elapsedMicroseconds;

    final baseline = [...emitCounts];
    final baselineListenerUs = listenerUs;

    final writeSw = Stopwatch()..start();
    for (var w = 0; w < writeCount; w++) {
      final id = prng.nextInt(_itemCount) + 1;
      await peer.execute(
        'UPDATE items SET value = ? WHERE id = ?',
        [w, id],
      );
    }

    // Settle.
    var lastSum = emitCounts.reduce((a, b) => a + b);
    const quietWindow = Duration(milliseconds: 200);
    final quietDeadline =
        DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(quietDeadline)) {
      await Future<void>.delayed(quietWindow);
      final nowSum = emitCounts.reduce((a, b) => a + b);
      if (nowSum == lastSum) break;
      lastSum = nowSum;
    }
    writeSw.stop();
    totalSw.stop();

    var totalPost = 0;
    for (var i = 0; i < streamCount; i++) {
      totalPost += emitCounts[i] - baseline[i];
    }

    return _IterResult(
      totalWallUs: totalSw.elapsedMicroseconds,
      initialDrainUs: initialDrainUs,
      writeBurstUs: writeSw.elapsedMicroseconds,
      listenerUs: listenerUs - baselineListenerUs,
      postBaselineEmissions: totalPost,
    );
  } finally {
    for (final sub in subs) {
      await sub.cancel();
    }
  }
}

// ---------------------------------------------------------------------------
// Seed
// ---------------------------------------------------------------------------

Future<void> _seed(BenchmarkPeer peer, int streamCount) async {
  // Distribute items evenly across `streamCount` owners. For 10K items
  // and 100 owners that's 100 items per owner; for 20 owners (test
  // scale) it's 500 items per owner. Either way each stream's query
  // returns a bounded result set.
  final itemsPerOwner = _itemCount ~/ streamCount;
  await peer.execute(
    'CREATE TABLE items('
    'id INTEGER PRIMARY KEY, '
    'owner_id INTEGER NOT NULL, '
    'value INTEGER NOT NULL)',
  );
  await peer.execute('CREATE INDEX items_owner ON items(owner_id)');
  await peer.executeBatch(
    'INSERT INTO items(owner_id, value) VALUES (?, ?)',
    [
      for (var i = 0; i < _itemCount; i++)
        [
          (i ~/ itemsPerOwner) + 1,
          0,
        ],
    ],
  );
}

// ---------------------------------------------------------------------------
// Markdown output
// ---------------------------------------------------------------------------

void _writeResults(
  StringBuffer md,
  List<_Reading> readings, {
  required int streamCount,
  required int writeCount,
}) {
  md
    ..writeln('| Library | Wall med (ms) | Wall p90 (ms) | '
        'Main med (ms) | Main p90 (ms) | Init drain (ms) | '
        'Write burst (ms) | Emissions |')
    ..writeln('|---|---|---|---|---|---|---|---|');
  for (final r in readings) {
    md.writeln(
      '| ${r.label} '
      '| ${r.timing.wall.medianMs.toStringAsFixed(2)} '
      '| ${r.timing.wall.p90Ms.toStringAsFixed(2)} '
      '| ${r.timing.main.medianMs.toStringAsFixed(2)} '
      '| ${r.timing.main.p90Ms.toStringAsFixed(2)} '
      '| ${r.medianInitialDrainMs.toStringAsFixed(2)} '
      '| ${r.medianWriteBurstMs.toStringAsFixed(2)} '
      '| ${r.medianEmissions} |',
    );
  }
  md
    ..writeln()
    ..writeln('**Init drain**: median wall time from subscribing all '
        '$streamCount streams to the last one producing its initial '
        'emission. Exposes cold-start cost of the subscriber fleet.')
    ..writeln()
    ..writeln('**Write burst**: median wall time from first write to '
        'last emission settled after $writeCount writes. Dominated by '
        're-query cost × stream count × write count for libraries '
        'without per-row invalidation; hash suppression (resqlite exp '
        '031/033) elides emissions but the re-query itself still runs.')
    ..writeln()
    ..writeln('**Wall / Main** columns are end-to-end (init + writes + '
        'settle). `Main` is aggregate listener-callback time — the UI '
        'thread cost.')
    ..writeln();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

int _median(List<int> xs) {
  final sorted = [...xs]..sort();
  return sorted[sorted.length ~/ 2];
}

double _medianD(List<double> xs) {
  final sorted = [...xs]..sort();
  return sorted[sorted.length ~/ 2];
}

Future<void> _waitUntil({
  required bool Function() predicate,
  required Duration timeout,
  required String description,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(description, timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

// Standalone entry.
Future<void> main() async {
  final md = await runHighCardinalityFanoutBenchmark();
  print(md);
}
