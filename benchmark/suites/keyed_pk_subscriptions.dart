// ignore_for_file: avoid_print

/// A11 — Keyed PK Subscriptions (v1).
///
/// 50 reactive streams each watch exactly one primary key via
/// `SELECT * FROM items WHERE id = ?`. A loop of 200 writes targets
/// random PKs across a 10,000-row table. Most writes miss the 50
/// watched PKs entirely, so the optimal library fires only on hits.
///
/// A library with table-level invalidation over-fires: 200 writes ×
/// 50 streams = 10,000 re-queries even though most writes miss. A
/// library with hash-based unchanged suppression (as resqlite has via
/// exp 031 / 033 today) skips most emissions but still pays the
/// re-query cost. A library with keyed-PK invalidation (Track D's
/// planned `watchRow()` API) skips the re-query entirely when the
/// write's PK is not watched.
///
/// This benchmark motivates Track D's `watchRow(table, pk)` API — the
/// Flutter-idiomatic precision observer that matches how detail-screen
/// widgets actually consume reactive data. At v1 we sized to 50/200
/// so the full bench completes under ~60s on M1 Pro; a v2 version bump
/// can raise counts if a bigger-scale story becomes necessary.
///
/// Peers: resqlite, sqlite_async. sqlite3.dart is excluded (no streams).
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../drift/keyed_pk_db.dart';
import '../shared/peer.dart';
import '../shared/stats.dart';
import '../shared/workload.dart';

const WorkloadMeta keyedPkMeta = WorkloadMeta(
  slug: 'keyed_pk_subscriptions',
  version: 1,
  title: 'Keyed PK Subscriptions',
  description: '50 reactive streams each watch one PK. 200 random-PK '
      'writes across a 10K-row table. The committed PRNG seed produces '
      '3 hits on watched PKs, so both miss-path and hit-path are '
      'exercised each run. With keyed invalidation, a library fires '
      'only on those hits. With table-level invalidation, every write '
      'triggers a re-query on all 50 streams (10K re-queries, most '
      'suppressed by hash but still costly).',
);

const int _tableRowCount = 10000;
// Scale picked so each iteration completes in a few seconds on
// resqlite and ~10 seconds on sqlite_async — the full bench
// (warmup + measured runs × both peers) stays under ~60s.
// The narrative (re-query cost scales with stream count × write count)
// is visible at this scale; bumping to 100 × 1000 made the bench
// multi-minute without adding signal.
const int _streamCount = 50;
const int _writeCount = 200;
const int _iterations = 3;
const int _warmup = 1;

/// Fixed seed so the random PK sequence is stable across iterations
/// and peers — fair comparison requires identical writes.
///
/// This specific seed, combined with the 50-streams × 200-writes
/// configuration, produces a small number of deliberate hits (~3 in
/// the committed v1 settings) so both miss-path (most writes) and
/// hit-path (a few writes whose PK is watched) are exercised by the
/// same run. Verified via a tiny Dart script — see the commit that
/// picked this seed.
const int _prngSeed = 0xBEEF;

Future<String> runKeyedPkSubscriptionsBenchmark() async {
  final markdown = StringBuffer()
    ..writeln('## ${keyedPkMeta.sectionHeading}')
    ..writeln()
    ..writeln(keyedPkMeta.description)
    ..writeln()
    ..writeln('### $_streamCount streams × $_writeCount random-PK writes');
  markdown.writeln();

  final readings = <_Reading>[];

  final tempDir =
      await Directory.systemTemp.createTemp('bench_keyed_pk_');
  try {
    final peers = await PeerSet.open(
      tempDir.path,
      require: (p) => p.hasStreams,
      driftFactory: driftFactoryFor((exec) => KeyedPkDriftDb(exec)),
    );
    try {
      for (final peer in peers.all) {
        print('  running on ${peer.name}...');
        final r = await _measure(peer);
        readings.add(r);
      }
    } finally {
      await peers.closeAll();
    }
  } finally {
    await tempDir.delete(recursive: true);
  }

  _writeResultTable(markdown, readings);
  return markdown.toString();
}

// ---------------------------------------------------------------------------
// Measurement
// ---------------------------------------------------------------------------

final class _Reading {
  _Reading({
    required this.label,
    required this.timing,
    required this.medianTotalEmissions,
    required this.medianObservedHits,
  });

  final String label;
  final BenchmarkTiming timing;

  /// Median of per-iteration `sum(post-baseline emissions across all 50
  /// streams)`. Optimal = number of writes that hit a watched PK (3
  /// with the committed seed + v1 counts; see [_prngSeed]). Larger =
  /// over-fire. Smaller = hash suppression elided emissions for hits
  /// whose row value did not materially change.
  final int medianTotalEmissions;

  /// Median of per-iteration count of writes whose PK matched one of the
  /// watched IDs. This is the "denominator" — emissions should not
  /// exceed this number for the workload to be correct (emissions can
  /// be fewer when hash suppression elides a change that was a no-op at
  /// the row-value level).
  final int medianObservedHits;
}

Future<_Reading> _measure(BenchmarkPeer peer) async {
  await _seed(peer);

  final watchedIds = _pickWatchedIds();
  final timing = BenchmarkTiming('${peer.label} stream()');
  final totalEmissionsByIter = <int>[];
  final observedHitsByIter = <int>[];

  for (var i = 0; i < _warmup + _iterations; i++) {
    final r = await _singleIteration(peer, watchedIds);
    if (i >= _warmup) {
      // Main-isolate time for this workload is the time spent inside
      // the stream listener callback — that's where emission delivery
      // work lands on the UI thread. Wall time covers dispatch +
      // await + drain. Setting main == wall would overstate the UI
      // thread cost for async peers (most of wall is awaiting).
      timing.record(
        wallMicroseconds: r.wallMicroseconds,
        mainMicroseconds: r.listenerMicroseconds,
      );
      totalEmissionsByIter.add(r.totalEmissions);
      observedHitsByIter.add(r.observedHits);
    }
  }

  return _Reading(
    label: '${peer.label} stream()',
    timing: timing,
    medianTotalEmissions: _median(totalEmissionsByIter),
    medianObservedHits: _median(observedHitsByIter),
  );
}

final class _IterationResult {
  _IterationResult({
    required this.wallMicroseconds,
    required this.listenerMicroseconds,
    required this.totalEmissions,
    required this.observedHits,
  });
  final int wallMicroseconds;
  /// Aggregate time spent inside the emission listener callback across
  /// all streams in this iteration. Represents main-isolate CPU work;
  /// differs from wall which includes dispatch + await + drain.
  final int listenerMicroseconds;
  final int totalEmissions;
  final int observedHits;
}

Future<_IterationResult> _singleIteration(
  BenchmarkPeer peer,
  List<int> watchedIds,
) async {
  // Reset the random sequence deterministically per iteration so every
  // peer sees the same write pattern in the same order.
  final prng = math.Random(_prngSeed);

  // Subscribe to all watched PKs. Each listener times itself so the
  // total time spent on the main isolate delivering emissions is
  // measurable separately from wall time.
  final emitCounts = List<int>.filled(_streamCount, 0);
  var listenerMicroseconds = 0;
  final subs = <StreamSubscription<List<Map<String, Object?>>>>[];
  for (var i = 0; i < _streamCount; i++) {
    final idx = i; // Capture for closure.
    final sub = peer.watch(
      'SELECT id, body, updated_at FROM items WHERE id = ?',
      params: [watchedIds[i]],
      readsFrom: const {'items'},
    ).listen((_) {
      final sw = Stopwatch()..start();
      emitCounts[idx]++;
      sw.stop();
      listenerMicroseconds += sw.elapsedMicroseconds;
    });
    subs.add(sub);
  }

  try {
    // Drain initial emissions — wait until every stream has emitted at
    // least once. Generous timeout because sqlite_async with 50 streams
    // can take >10s to drain initial emissions under its own scheduling.
    await _waitUntil(
      predicate: () => emitCounts.every((c) => c >= 1),
      timeout: const Duration(seconds: 60),
      description: 'initial emissions from all $_streamCount streams',
    );

    // Baseline snapshot. Post-baseline emissions are the "real" count.
    final baseline = [...emitCounts];
    final baselineListenerUs = listenerMicroseconds;

    final watchedSet = watchedIds.toSet();
    var observedHits = 0;
    final sw = Stopwatch()..start();

    // Randomized writes over all 10K PKs. Target id and payload are
    // deterministic given the seed so peers see identical traffic.
    for (var w = 0; w < _writeCount; w++) {
      final pk = prng.nextInt(_tableRowCount) + 1;
      if (watchedSet.contains(pk)) observedHits++;
      await peer.execute(
        'UPDATE items SET body = ?, updated_at = ? WHERE id = ?',
        ['body_$w', w, pk],
      );
    }

    // Settle: wait until no more emissions arrive for a quiet window.
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

    sw.stop();

    var totalPostBaseline = 0;
    for (var i = 0; i < _streamCount; i++) {
      totalPostBaseline += emitCounts[i] - baseline[i];
    }

    return _IterationResult(
      wallMicroseconds: sw.elapsedMicroseconds,
      listenerMicroseconds: listenerMicroseconds - baselineListenerUs,
      totalEmissions: totalPostBaseline,
      observedHits: observedHits,
    );
  } finally {
    for (final sub in subs) {
      await sub.cancel();
    }
  }
}

/// Pick the $_streamCount watched PKs evenly across the 10K-row table
/// so the hit distribution is uniform. Fixed, deterministic choice —
/// same IDs across peers, same IDs across runs.
List<int> _pickWatchedIds() {
  final step = _tableRowCount ~/ _streamCount;
  return [for (var i = 0; i < _streamCount; i++) (i * step) + 1];
}

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------

Future<void> _seed(BenchmarkPeer peer) async {
  // IF NOT EXISTS because drift auto-creates the table from its
  // @DriftDatabase schema at open; re-issuing bare CREATE TABLE would
  // throw "table already exists" on that peer. The schema here must
  // match benchmark/drift/keyed_pk_db.dart exactly.
  await peer.execute(
    'CREATE TABLE IF NOT EXISTS items('
    'id INTEGER PRIMARY KEY, '
    'body TEXT NOT NULL, '
    'updated_at INTEGER NOT NULL'
    ')',
  );
  final rows = <List<Object?>>[
    for (var i = 1; i <= _tableRowCount; i++)
      ['seed_body_$i', 0],
  ];
  await peer.executeBatch(
    'INSERT INTO items(body, updated_at) VALUES (?, ?)',
    rows,
  );
}

// ---------------------------------------------------------------------------
// Markdown output
// ---------------------------------------------------------------------------

void _writeResultTable(StringBuffer md, List<_Reading> readings) {
  md
    ..writeln('| Library | Wall med (ms) | Wall p90 (ms) | '
        'Main med (ms) | Main p90 (ms) | '
        'Total emits | Observed hits |')
    ..writeln('|---|---|---|---|---|---|---|');
  for (final r in readings) {
    md.writeln(
      '| ${r.label} '
      '| ${r.timing.wall.medianMs.toStringAsFixed(2)} '
      '| ${r.timing.wall.p90Ms.toStringAsFixed(2)} '
      '| ${r.timing.main.medianMs.toStringAsFixed(2)} '
      '| ${r.timing.main.p90Ms.toStringAsFixed(2)} '
      '| ${r.medianTotalEmissions} '
      '| ${r.medianObservedHits} |',
    );
  }
  md.writeln();
  md
    ..writeln('**Total emits**: post-baseline emissions summed across all '
        '$_streamCount streams. **Observed hits**: how many of the '
        '$_writeCount random writes actually targeted a watched PK. '
        'Perfect behavior: emissions == hits. Emissions < hits means '
        'hash suppression elided some writes whose row value did not '
        'change. Emissions > hits means over-fire.')
    ..writeln()
    ..writeln('Wall time is dominated by re-query work. A library with '
        'keyed-PK invalidation (Track D\'s planned `watchRow()`) can '
        'avoid re-querying for writes whose PK is unwatched, reducing '
        'wall time substantially even when emission counts already '
        'look clean due to hash suppression.')
    ..writeln();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

int _median(List<int> xs) {
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
  final md = await runKeyedPkSubscriptionsBenchmark();
  print(md);
}
