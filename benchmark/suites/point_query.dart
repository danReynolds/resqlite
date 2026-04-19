// ignore_for_file: avoid_print
import 'dart:io';

import '../drift/micro_items_db.dart';
import '../shared/peer.dart';
import '../shared/seeder.dart';
import '../shared/stats.dart';

/// Point query throughput: `SELECT * FROM items WHERE id = ?` in a hot loop.
///
/// Reports queries-per-second per library along with a 95% bootstrap CI
/// and two MDE values so small wins can be declared defensibly.
/// See experiments 059, 063, 066 — all rejected because their measured
/// improvements were in the 2-10% range and the prior harness couldn't
/// distinguish them from noise.
Future<String> runPointQueryBenchmark() async {
  final markdown = StringBuffer();
  markdown.writeln('## Point Query Throughput');
  markdown.writeln('');
  markdown.writeln(
    'Single-row lookup by primary key in a hot loop. Measures the per-query '
    'dispatch overhead. Each iteration runs $_queryCount sequential queries '
    'over $_iterations iterations per library. 95% CI and MDE values derive '
    'from per-iteration QPS samples via percentile bootstrap (deterministic, '
    'seed=$_bootstrapSeed).',
  );
  markdown.writeln('');

  final tempDir = await Directory.systemTemp.createTemp('bench_point_');
  final libResults = <String, _QpsResult>{};
  try {
    final peers = await PeerSet.open(
      tempDir.path,
      driftFactory: driftFactoryFor((exec) => MicroItemsDriftDb(exec)),
    );
    try {
      for (final peer in peers.all) {
        await seedPeer(peer, 1000);
        libResults[peer.name] = await _measure(peer);
      }
    } finally {
      await peers.closeAll();
    }
  } finally {
    await tempDir.delete(recursive: true);
  }

  final resqliteResult = libResults['resqlite']!;

  // ---- Legacy single-cell row (preserves hardware-summary and history
  // parser compatibility). ----
  markdown.writeln('| Metric | Value |');
  markdown.writeln('|---|---:|');
  markdown.writeln('| resqlite qps | ${resqliteResult.medianQps} |');
  markdown.writeln(
    '| resqlite per query | ${resqliteResult.perQueryMs.toStringAsFixed(3)} ms |',
  );
  markdown.writeln('');

  // ---- Multi-library CI+MDE subsection. ----
  markdown.writeln('### QPS + MDE');
  markdown.writeln('');
  markdown.writeln(
    '| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |',
  );
  markdown.writeln('|---|---:|---:|---:|---:|');
  for (final entry in libResults.entries) {
    final r = entry.value;
    markdown.writeln(
      '| ${entry.key} '
      '| ${r.medianQps} '
      '| ${r.ciLow.round()}..${r.ciHigh.round()} '
      '| ${r.mdeCiPct.toStringAsFixed(1)} '
      '| ${r.mdeMadPct.toStringAsFixed(1)} |',
    );
  }
  markdown.writeln('');

  // ---- Console readout. ----
  print('');
  print('=== Point Query ===');
  for (final entry in libResults.entries) {
    final r = entry.value;
    print(
      '${entry.key.padRight(14)} '
      '${r.medianQps.toString().padLeft(7)} qps '
      '(CI ${r.ciLow.round()}..${r.ciHigh.round()}, '
      'MDE_ci ${r.mdeCiPct.toStringAsFixed(1)}%)',
    );
  }
  print('');

  return markdown.toString();
}

// ---------------------------------------------------------------------------
// Measurement
// ---------------------------------------------------------------------------

const _queryCount = 500;
const _warmupIterations = 50;
const _iterations = 100;
const _bootstrapSeed = 0xC10FF1E;

class _QpsResult {
  _QpsResult({
    required this.medianQps,
    required this.perQueryMs,
    required this.ciLow,
    required this.ciHigh,
    required this.mdeCiPct,
    required this.mdeMadPct,
  });

  final int medianQps;
  final double perQueryMs;
  final double ciLow;
  final double ciHigh;
  final double mdeCiPct;
  final double mdeMadPct;
}

_QpsResult _summarize(List<int> iterationTimingsUs) {
  // Convert to per-iteration QPS samples, then feed through the bootstrap
  // and MDE helpers. Operating on QPS directly (rather than microseconds)
  // matches how the metric is reported and how the comparison threshold
  // is applied downstream in run_release.
  final qpsSamples = [
    for (final us in iterationTimingsUs)
      if (us > 0) _queryCount * 1000000 / us,
  ];
  if (qpsSamples.isEmpty) {
    return _QpsResult(
      medianQps: 0,
      perQueryMs: 0,
      ciLow: 0,
      ciHigh: 0,
      mdeCiPct: 0,
      mdeMadPct: 0,
    );
  }
  final stats = AggregateStats.from(qpsSamples);
  final ci = bootstrapMedianCI(qpsSamples, seed: _bootstrapSeed);
  return _QpsResult(
    medianQps: stats.median.round(),
    // ms/query = 1000 / (queries/second)
    perQueryMs: stats.median > 0 ? 1000.0 / stats.median : 0,
    ciLow: ci.low,
    ciHigh: ci.high,
    mdeCiPct: minimumDetectableEffectPct(qpsSamples, seed: _bootstrapSeed),
    mdeMadPct: madBasedDetectableEffectPct(qpsSamples),
  );
}

/// Unified per-peer hot-loop measurement. The previous hand-rolled
/// approach had three nearly-identical 15-line functions — one per
/// peer — which diverged over time (sqlite_async used `.get()` while
/// resqlite used `.select()`, so the measurement subtly differed).
/// Going through [BenchmarkPeer.select] uniformly is fairer: every
/// peer runs the exact same shape of call, returning the exact same
/// shape of result.
Future<_QpsResult> _measure(BenchmarkPeer peer) async {
  const sql = 'SELECT * FROM items WHERE id = ?';
  for (var i = 0; i < _warmupIterations * 10; i++) {
    await peer.select(sql, [i % 1000 + 1]);
  }
  final timings = <int>[];
  for (var iter = 0; iter < _iterations; iter++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < _queryCount; i++) {
      await peer.select(sql, [i % 1000 + 1]);
    }
    sw.stop();
    timings.add(sw.elapsedMicroseconds);
  }
  return _summarize(timings);
}

// Allow running standalone.
Future<void> main() async {
  final md = await runPointQueryBenchmark();
  print(md);
}
