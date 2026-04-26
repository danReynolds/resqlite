// ignore_for_file: avoid_print

/// A11c — Many-Streams Writer Throughput (v1).
///
/// Measures **writer throughput (writes/sec) while N streams are
/// subscribed**, splitting writes between two scenarios:
///
/// - **Disjoint**: writes target a column NOT in any stream's projection.
///   Optimal: writer cost is roughly the same as the no-streams baseline
///   because each stream should skip dispatch entirely.
/// - **Overlapping**: writes target a column IN every stream's projection.
///   Each write must reach all N streams' invalidation paths.
///
/// ## Why this exists
///
/// The existing `disjoint_columns.dart` suite measures the ratio of
/// disjoint-vs-overlapping stream emissions on the **stream side** —
/// it asks "did the library suppress emission?". On that metric, exp 075
/// (worker-side result-hash short-circuit, accepted) is observationally
/// indistinguishable from exp 052 (column-level dependency tracking,
/// rejected — sound but benchmark-invisible). The disjoint_columns suite
/// header explicitly notes:
///
/// > Measuring 052 specifically would require a many-streams writer
/// > throughput benchmark where the dispatch-elision win dominates. That
/// > benchmark doesn't exist yet.
///
/// This suite fills that gap. Exp 052's value is dispatch *elision* on
/// the writer side: a write that touches a column no stream projects
/// should skip the per-stream re-query dispatch entirely. Exp 075's hash
/// short-circuit still pays the dispatch cost (the re-query runs and
/// hashes; only the emission to the listener is suppressed). So a
/// writer-throughput-under-fanout benchmark should differentiate them
/// and unblock revisiting exp 052.
///
/// ## What it does NOT differentiate
///
/// - **Hash short-circuit (exp 075) vs no suppression at all** on the
///   stream-side. That story is told by `disjoint_columns.dart`.
/// - **Coalescing strategies** (exp 045, PR #17). Writes are issued
///   sequentially with awaits and microtask yields so per-stream
///   coalescing collapses to ~1 invalidation per write rather than
///   batching across the whole burst.
/// - **Cold-start cost of N subscriptions.** Streams are subscribed
///   and drained before timing starts; we measure steady-state writer
///   throughput, not subscriber spin-up.
///
/// ## Expected qualitative results
///
/// | Peer | Disjoint vs overlap | Why |
/// |---|---|---|
/// | resqlite (today) | similar | Both go through writer-side dispatch; exp 075 saves the emission but the per-stream re-query is still scheduled. Disjoint may be slightly cheaper because the post-hash compare suppresses listener delivery, but the writer-side fanout cost dominates. |
/// | resqlite (with exp 052 dispatch elision) | disjoint ≫ overlap | The dispatch itself would be skipped on column-disjoint writes — what this benchmark exists to make visible. |
/// | sqlite_async | similar | Table-level invalidation; disjoint and overlap both invalidate every stream uniformly. |
/// | drift | similar | `StreamQueryStore` is also table-level. |
///
/// **Primary metric**: median **writes/sec** during the timed write loop
/// per scenario (per the methodology, peers compare on absolute wall-time
/// medians; we expose the throughput derivation alongside).
///
/// **Secondary**: ratio `overlap/disjoint` writes/sec — interpretive only.
/// A library where the ratio is close to 1.0 is doing similar work
/// regardless of column overlap; a ratio ≪ 1.0 means it's actually
/// eliding work on disjoint writes.
///
/// **Baseline**: a "no streams" writer-only run is reported alongside as
/// a reference for "cost of having N subscribed streams per write".
///
/// ## Peers
///
/// - **resqlite** — the subject.
/// - **sqlite_async** — `throttle: Duration.zero` per the reactive-workload
///   convention so we measure its invalidation engine, not its 30 ms
///   default throttle.
/// - **drift** — uses `customSelect` with explicit `readsFrom` per the
///   `DriftPeer` adapter contract.
/// - **sqlite3.dart** — omitted (no streams API). Per the methodology's
///   asymmetric-capabilities rule, it does not appear in the table.
///
/// ## Cost gating
///
/// At N=50 streams × 500 writes per scenario × 3 peers × 3 iterations,
/// this suite takes longer than a few seconds — particularly on
/// sqlite_async / drift where the writer must round-trip per-write
/// invalidations through their stream stores. It is therefore registered
/// as `--include-slow`, matching the A9 / A11b precedent.
///
/// ## Implementation notes
///
/// Microtask yields between writes (`Future.delayed(Duration.zero)`) defeat
/// resqlite's per-microtask invalidation coalescing (exp 045) so each
/// write produces one invalidation per overlapping stream. Without this,
/// 500 sequential writes collapse to ~10 invalidations and the ratio
/// signal washes out. This matches the convention in
/// `disjoint_columns.dart`.
library;

import 'dart:async';
import 'dart:io';

import '../drift/many_streams_writer_db.dart';
import '../shared/peer.dart';
import '../shared/stats.dart';
import '../shared/workload.dart';

const WorkloadMeta manyStreamsWriterMeta = WorkloadMeta(
  slug: 'many_streams_writer',
  version: 1,
  title: 'Many-Streams Writer Throughput',
  description:
      'Writer throughput (writes/sec) under stream fan-out. '
      'A wide 20-column table is watched by N streams, each projecting a '
      'subset of columns over a partition of the row space. The writer '
      'issues 500 single-row updates first against a column NOT in any '
      'stream\'s projection (disjoint) and then against a column IN every '
      'stream\'s projection (overlapping). The disjoint-vs-overlapping '
      'spread reveals whether a library elides per-stream dispatch on '
      'column-disjoint writes — the writer-side counterpart to '
      'disjoint_columns.dart\'s stream-side ratio. A no-streams '
      'baseline run is reported as a writer-only reference.',
);

// Workload constants. Tuned so the suite runs in ~30-90s per peer.
const int _rowCount = 5000;
const int _streamCount = 50;
const int _writeCount = 500;
const int _iterations = 3;
const int _warmup = 1;

/// Production entry point — used by the release runner.
Future<String> runManyStreamsWriterThroughputBenchmark() => _run(
  streamCount: _streamCount,
  writeCount: _writeCount,
  iterations: _iterations,
  warmup: _warmup,
);

/// Test entry — reduced scale so unit tests can complete in seconds.
/// Exposed only for tests; production callers use
/// [runManyStreamsWriterThroughputBenchmark].
Future<String> runManyStreamsWriterThroughputBenchmarkSmallForTest() =>
    _run(streamCount: 5, writeCount: 30, iterations: 1, warmup: 0);

Future<String> _run({
  required int streamCount,
  required int writeCount,
  required int iterations,
  required int warmup,
}) async {
  final md = StringBuffer()
    ..writeln('## ${manyStreamsWriterMeta.sectionHeading}')
    ..writeln()
    ..writeln(manyStreamsWriterMeta.description)
    ..writeln()
    ..writeln('### $streamCount streams × $writeCount writes per scenario');
  md.writeln();

  // Wide table: id PK + 20 TEXT columns a..t.
  final colNames = [
    for (var i = 0; i < 20; i++) String.fromCharCode('a'.codeUnitAt(0) + i),
  ];
  // IF NOT EXISTS because drift auto-creates the table from its
  // @DriftDatabase schema at open; bare CREATE TABLE would throw "already
  // exists" on the drift peer. Schema must match
  // benchmark/drift/many_streams_writer_db.dart exactly.
  final createSql =
      'CREATE TABLE IF NOT EXISTS wide(id INTEGER PRIMARY KEY, ' +
      colNames.map((c) => '$c TEXT NOT NULL').join(', ') +
      ')';
  final insertSql =
      'INSERT INTO wide(id, ${colNames.join(', ')}) '
      'VALUES (?, ${List.filled(colNames.length, '?').join(', ')})';

  List<Object?> rowFor(int i) => [i, for (final _ in colNames) 'v$i'];

  final byPeer = <String, _PeerReadings>{};
  final tempDir = await Directory.systemTemp.createTemp('bench_a11c_');
  try {
    final peers = await PeerSet.open(
      tempDir.path,
      require: (p) => p.hasStreams,
      driftFactory: driftFactoryFor((exec) => ManyStreamsWriterDriftDb(exec)),
    );
    try {
      for (final peer in peers.all) {
        print('  running on ${peer.name}...');
        await peer.execute(createSql);
        await peer.executeBatch(insertSql, [
          for (var i = 0; i < _rowCount; i++) rowFor(i),
        ]);

        final readings = await _measurePeer(
          peer,
          streamCount: streamCount,
          writeCount: writeCount,
          warmup: warmup,
          iterations: iterations,
        );
        byPeer[peer.label] = readings;

        print(
          '${peer.label} '
          'baseline: ${readings.baseline.medianWritesPerSec.toStringAsFixed(0)} w/s, '
          'disjoint: ${readings.disjoint.medianWritesPerSec.toStringAsFixed(0)} w/s, '
          'overlap: ${readings.overlap.medianWritesPerSec.toStringAsFixed(0)} w/s',
        );
      }
    } finally {
      await peers.closeAll();
    }
  } finally {
    await tempDir.delete(recursive: true);
  }

  _writeBaselineSection(md, byPeer, writeCount: writeCount);
  _writeScenarioSection(
    md,
    'Disjoint column writes (SET c = ?, projection = id, a, b)',
    byPeer,
    pickDisjoint: true,
    writeCount: writeCount,
    streamCount: streamCount,
  );
  _writeScenarioSection(
    md,
    'Overlapping column writes (SET a = ?, projection = id, a, b)',
    byPeer,
    pickDisjoint: false,
    writeCount: writeCount,
    streamCount: streamCount,
  );
  _writeRatioSection(md, byPeer, streamCount: streamCount);

  md
    ..writeln(
      '**Writes/sec** is `writeCount / wall_time_seconds`. '
      'Higher is better. **Baseline** is the same write loop with no '
      'streams subscribed — the writer\'s ceiling on this hardware.',
    )
    ..writeln()
    ..writeln(
      '**Emissions** are post-baseline emissions summed across '
      'all $streamCount streams during the timed write loop. A library '
      'with hash-based result suppression (resqlite exp 075) reports '
      'low emission counts on the disjoint scenario even when its '
      'writer throughput is unchanged — that signal lives in '
      '`disjoint_columns.dart`, not here. This suite is about the '
      'writer-side cost of the dispatch itself.',
    )
    ..writeln()
    ..writeln(
      '**Overlap/disjoint ratio**: writes/sec under overlap '
      'divided by writes/sec under disjoint. A ratio close to 1.0 means '
      'the library performs similar writer-side work in both scenarios; '
      'a ratio ≪ 1.0 means it is actually eliding per-stream dispatch '
      'on disjoint writes. resqlite today is expected near 1.0; this '
      'benchmark exists to make a future column-tracking optimization '
      '(exp 052) visible by driving that ratio down.',
    )
    ..writeln();

  return md.toString();
}

// ---------------------------------------------------------------------------
// Measurement
// ---------------------------------------------------------------------------

class _ScenarioReading {
  _ScenarioReading({
    required this.timing,
    required this.medianWritesPerSec,
    required this.medianEmissions,
  });

  /// Per-iteration wall + main timing. Each iteration's wall covers the
  /// timed write loop only (initial drain + settle excluded).
  final BenchmarkTiming timing;

  /// Median throughput across measured iterations: `writeCount / wall_s`.
  final double medianWritesPerSec;

  /// Median post-baseline emission count across all streams.
  /// 0 for the baseline (no streams).
  final int medianEmissions;
}

class _PeerReadings {
  _PeerReadings({
    required this.label,
    required this.baseline,
    required this.disjoint,
    required this.overlap,
  });
  final String label;
  final _ScenarioReading baseline;
  final _ScenarioReading disjoint;
  final _ScenarioReading overlap;
}

Future<_PeerReadings> _measurePeer(
  BenchmarkPeer peer, {
  required int streamCount,
  required int writeCount,
  required int warmup,
  required int iterations,
}) async {
  // Baseline: same write loop, no streams. Writes use column `c` (the
  // disjoint column on the with-streams runs) so the SQL path is
  // identical between baseline and disjoint.
  final baseline = await _measureScenario(
    peer,
    streamCount: 0,
    writeCount: writeCount,
    warmup: warmup,
    iterations: iterations,
    updateSql: 'UPDATE wide SET c = ? WHERE id = ?',
    valueFor: (i) => 'b$i',
  );

  final disjoint = await _measureScenario(
    peer,
    streamCount: streamCount,
    writeCount: writeCount,
    warmup: warmup,
    iterations: iterations,
    updateSql: 'UPDATE wide SET c = ? WHERE id = ?',
    valueFor: (i) => 'd$i',
  );

  final overlap = await _measureScenario(
    peer,
    streamCount: streamCount,
    writeCount: writeCount,
    warmup: warmup,
    iterations: iterations,
    updateSql: 'UPDATE wide SET a = ? WHERE id = ?',
    valueFor: (i) => 'z$i',
  );

  return _PeerReadings(
    label: peer.label,
    baseline: baseline,
    disjoint: disjoint,
    overlap: overlap,
  );
}

Future<_ScenarioReading> _measureScenario(
  BenchmarkPeer peer, {
  required int streamCount,
  required int writeCount,
  required int warmup,
  required int iterations,
  required String updateSql,
  required String Function(int) valueFor,
}) async {
  final timing = BenchmarkTiming(peer.label);
  final wpsByIter = <double>[];
  final emissionsByIter = <int>[];

  for (var iter = 0; iter < warmup + iterations; iter++) {
    final r = await _singleIteration(
      peer,
      streamCount: streamCount,
      writeCount: writeCount,
      updateSql: updateSql,
      valueFor: valueFor,
    );
    if (iter >= warmup) {
      timing.record(
        wallMicroseconds: r.writeWallUs,
        mainMicroseconds: r.writeMainUs,
      );
      final wallSec = r.writeWallUs / 1e6;
      wpsByIter.add(wallSec == 0 ? 0 : writeCount / wallSec);
      emissionsByIter.add(r.postBaselineEmissions);
    }
  }

  return _ScenarioReading(
    timing: timing,
    medianWritesPerSec: _medianD(wpsByIter),
    medianEmissions: _median(emissionsByIter),
  );
}

class _IterResult {
  _IterResult({
    required this.writeWallUs,
    required this.writeMainUs,
    required this.postBaselineEmissions,
  });
  final int writeWallUs;
  final int writeMainUs;
  final int postBaselineEmissions;
}

Future<_IterResult> _singleIteration(
  BenchmarkPeer peer, {
  required int streamCount,
  required int writeCount,
  required String updateSql,
  required String Function(int) valueFor,
}) async {
  final emitCounts = List<int>.filled(streamCount, 0);
  final initialCompleters = <Completer<void>>[];
  final subs = <StreamSubscription<List<Map<String, Object?>>>>[];
  var listenerUs = 0;

  // Subscribe N streams, each watching a partition of the row space.
  // Each stream projects (id, a, b) — only `a` overlaps with the
  // overlapping-write scenario; column `c` is disjoint.
  for (var i = 0; i < streamCount; i++) {
    final idx = i;
    final initial = Completer<void>();
    initialCompleters.add(initial);
    // Partition: rows whose id is in [partStart, partEnd). With 5000
    // rows and 50 streams that's a 100-row slice per stream — small
    // enough that emissions are cheap to deliver but large enough that
    // a write to a row in the partition (1/50 of writes on average for
    // the random-id case; here we use sequential ids that span
    // partitions) actually changes the result. We size partitions so
    // every stream's window is non-empty regardless of write target.
    final partWidth = _rowCount ~/ streamCount;
    final partStart = idx * partWidth;
    final partEnd = partStart + partWidth;
    final sub = peer
        .watch(
          'SELECT id, a, b FROM wide WHERE id >= ? AND id < ? ORDER BY id',
          params: [partStart, partEnd],
          readsFrom: const {'wide'},
        )
        .listen((_) {
          final sw = Stopwatch()..start();
          if (!initial.isCompleted) {
            initial.complete();
          } else {
            emitCounts[idx]++;
          }
          sw.stop();
          listenerUs += sw.elapsedMicroseconds;
        });
    subs.add(sub);
  }

  try {
    // Drain initial emissions before timing the write loop. Generous
    // timeout because sqlite_async with 50 streams can take >10s to
    // drain initial emissions under its own scheduling.
    if (streamCount > 0) {
      await _waitUntil(
        predicate: () => initialCompleters.every((c) => c.isCompleted),
        timeout: const Duration(seconds: 60),
        description: 'initial emissions from all $streamCount streams',
      );
    }

    final baselineListenerUs = listenerUs;

    final wallSw = Stopwatch()..start();
    for (var w = 0; w < writeCount; w++) {
      // Spread writes across the row space. id = w % rowCount targets
      // a different partition each iteration in the with-streams runs,
      // so the partitioned streams all eventually see writes — making
      // overlap-vs-disjoint a meaningful distinction.
      await peer.execute(updateSql, [valueFor(w), w % _rowCount]);
      // Two event-queue yields. `Future.delayed(Duration.zero)`
      // schedules via `Timer.run`, which drains the microtask queue
      // first and then fires on the next event-loop turn — defeating
      // resqlite's per-microtask invalidation coalescing (exp 045).
      // Without this, 500 sequential writes collapse to ~10
      // invalidations per stream and the writer-side fanout cost is
      // hidden. Matches disjoint_columns.dart.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }
    wallSw.stop();
    // Drain any trailing in-flight emissions for the emission count, but
    // only after the wall clock is already stopped — including the drain
    // in the timed window bakes ~100 µs/write of fixed-cost padding into
    // the throughput denominator and hides per-write changes (the bug
    // that masked exp 107's true −67 % per-write reduction as a +51 %
    // w/s suite delta).
    if (streamCount > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    final wallUs = wallSw.elapsedMicroseconds;
    final listenerDelta = listenerUs - baselineListenerUs;

    var totalPost = 0;
    for (var i = 0; i < streamCount; i++) {
      totalPost += emitCounts[i];
    }

    return _IterResult(
      writeWallUs: wallUs,
      writeMainUs: listenerDelta,
      postBaselineEmissions: totalPost,
    );
  } finally {
    for (final sub in subs) {
      await sub.cancel();
    }
  }
}

// ---------------------------------------------------------------------------
// Markdown output
// ---------------------------------------------------------------------------

void _writeBaselineSection(
  StringBuffer md,
  Map<String, _PeerReadings> byPeer, {
  required int writeCount,
}) {
  md
    ..writeln('### No-streams baseline ($writeCount writes, no subscribers)')
    ..writeln()
    ..writeln(
      '| Library | Wall med (ms) | Wall p90 (ms) | '
      'Main med (ms) | Main p90 (ms) | Writes/sec |',
    )
    ..writeln('|---|---|---|---|---|---|');
  for (final entry in byPeer.entries) {
    final r = entry.value.baseline;
    md.writeln(
      '| ${entry.key} '
      '| ${r.timing.wall.medianMs.toStringAsFixed(2)} '
      '| ${r.timing.wall.p90Ms.toStringAsFixed(2)} '
      '| ${r.timing.main.medianMs.toStringAsFixed(2)} '
      '| ${r.timing.main.p90Ms.toStringAsFixed(2)} '
      '| ${r.medianWritesPerSec.toStringAsFixed(0)} |',
    );
  }
  md.writeln();
}

void _writeScenarioSection(
  StringBuffer md,
  String title,
  Map<String, _PeerReadings> byPeer, {
  required bool pickDisjoint,
  required int writeCount,
  required int streamCount,
}) {
  md
    ..writeln('### $title')
    ..writeln()
    ..writeln(
      '| Library | Wall med (ms) | Wall p90 (ms) | '
      'Main med (ms) | Main p90 (ms) | Writes/sec | Emissions |',
    )
    ..writeln('|---|---|---|---|---|---|---|');
  for (final entry in byPeer.entries) {
    final r = pickDisjoint ? entry.value.disjoint : entry.value.overlap;
    md.writeln(
      '| ${entry.key} '
      '| ${r.timing.wall.medianMs.toStringAsFixed(2)} '
      '| ${r.timing.wall.p90Ms.toStringAsFixed(2)} '
      '| ${r.timing.main.medianMs.toStringAsFixed(2)} '
      '| ${r.timing.main.p90Ms.toStringAsFixed(2)} '
      '| ${r.medianWritesPerSec.toStringAsFixed(0)} '
      '| ${r.medianEmissions} |',
    );
  }
  md.writeln();
}

void _writeRatioSection(
  StringBuffer md,
  Map<String, _PeerReadings> byPeer, {
  required int streamCount,
}) {
  md
    ..writeln('### Overlap-vs-disjoint writer-throughput ratio')
    ..writeln()
    ..writeln('| Library | Disjoint w/s | Overlap w/s | Overlap/disjoint |')
    ..writeln('|---|---|---|---|');
  for (final entry in byPeer.entries) {
    final dis = entry.value.disjoint.medianWritesPerSec;
    final ovr = entry.value.overlap.medianWritesPerSec;
    final ratio = dis == 0 ? 0.0 : ovr / dis;
    md.writeln(
      '| ${entry.key} '
      '| ${dis.toStringAsFixed(0)} '
      '| ${ovr.toStringAsFixed(0)} '
      '| ${ratio.toStringAsFixed(3)} |',
    );
  }
  md.writeln();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

int _median(List<int> xs) {
  if (xs.isEmpty) return 0;
  final sorted = [...xs]..sort();
  return sorted[sorted.length ~/ 2];
}

double _medianD(List<double> xs) {
  if (xs.isEmpty) return 0;
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

// Standalone entry — supports running this suite without the full
// release harness (matches the convention of other suites).
Future<void> main() async {
  final md = await runManyStreamsWriterThroughputBenchmark();
  print(md);
}
