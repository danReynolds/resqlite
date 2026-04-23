// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;

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
  final planSummary = summarizeAdaptivePointQueryPlan();
  markdown.writeln(
    'Single-row lookup by primary key in a hot loop. Measures the per-query '
    'dispatch overhead. Each sample runs the same adaptive number of '
    '$_queryCount-query batches, chosen after warmup so that '
    '$kPointQuerySampleCount samples target about '
    '${_pointQueryMeasurementTime.inMilliseconds} ms of total measurement per '
    'library after warmup. 95% CI and MDE values derive from per-sample QPS '
    'via percentile bootstrap (deterministic, seed=$_bootstrapSeed).',
  );
  markdown.writeln('');
  markdown.writeln(
    'Adaptive schedule: `$planSummary` (batch count chosen per library after warmup).',
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
const _warmupEstimateSamples = 3;
const _bootstrapSeed = 0xC10FF1E;
const kPointQuerySampleCount = 15;
const Duration _pointQueryWarmupTime = Duration(milliseconds: 500);
const Duration _pointQueryMeasurementTime = Duration(milliseconds: 1000);

final class AdaptiveMeasurementPlan {
  const AdaptiveMeasurementPlan({
    required this.batchesPerSample,
    required this.sampleCount,
  });

  final int batchesPerSample;
  final int sampleCount;
}

AdaptiveMeasurementPlan planAdaptivePointQueryMeasurement({
  required double estimatedBatchUs,
  int sampleCount = kPointQuerySampleCount,
  Duration measurementTime = _pointQueryMeasurementTime,
}) {
  final perSampleTargetUs = measurementTime.inMicroseconds / sampleCount;
  final rawBatchesPerSample = estimatedBatchUs <= 0
      ? 1.0
      : perSampleTargetUs / estimatedBatchUs;
  final batchesPerSample = math.max(1, rawBatchesPerSample.round());
  return AdaptiveMeasurementPlan(
    batchesPerSample: batchesPerSample,
    sampleCount: sampleCount,
  );
}

String summarizeAdaptivePointQueryPlan({
  int sampleCount = kPointQuerySampleCount,
  Duration measurementTime = _pointQueryMeasurementTime,
}) =>
    '$sampleCount samples, target ${measurementTime.inMilliseconds} ms total';

final class _MeasurementSample {
  const _MeasurementSample({required this.queryCount, required this.elapsedUs});

  final int queryCount;
  final int elapsedUs;
}

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

_QpsResult _summarize(List<_MeasurementSample> samples) {
  // Convert to per-iteration QPS samples, then feed through the bootstrap
  // and MDE helpers. Operating on QPS directly (rather than microseconds)
  // matches how the metric is reported and how the comparison threshold
  // is applied downstream in run_release.
  final qpsSamples = [
    for (final sample in samples)
      if (sample.elapsedUs > 0)
        sample.queryCount * 1000000 / sample.elapsedUs,
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
  var nextId = 1;

  Future<int> runBatches(int batchCount) async {
    final sw = Stopwatch()..start();
    for (var batch = 0; batch < batchCount; batch++) {
      for (var i = 0; i < _queryCount; i++) {
        await peer.select(sql, [nextId]);
        nextId++;
        if (nextId > 1000) nextId = 1;
      }
    }
    sw.stop();
    return sw.elapsedMicroseconds;
  }

  final warmup = Stopwatch()..start();
  var warmupBatches = 1;
  while (warmup.elapsed < _pointQueryWarmupTime) {
    await runBatches(warmupBatches);
    warmupBatches *= 2;
  }

  final estimateSamples = <double>[];
  for (var i = 0; i < _warmupEstimateSamples; i++) {
    final elapsedUs = await runBatches(1);
    estimateSamples.add(elapsedUs.toDouble());
  }
  final estimatedBatchUs = AggregateStats.from(estimateSamples).median;
  final plan = planAdaptivePointQueryMeasurement(
    estimatedBatchUs: estimatedBatchUs,
  );

  final samples = <_MeasurementSample>[];
  for (var sample = 0; sample < plan.sampleCount; sample++) {
    final elapsedUs = await runBatches(plan.batchesPerSample);
    samples.add(
      _MeasurementSample(
        queryCount: plan.batchesPerSample * _queryCount,
        elapsedUs: elapsedUs,
      ),
    );
  }
  return _summarize(samples);
}

// Allow running standalone.
Future<void> main() async {
  final md = await runPointQueryBenchmark();
  print(md);
}
