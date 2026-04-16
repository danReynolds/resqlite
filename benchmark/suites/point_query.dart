// ignore_for_file: avoid_print
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:sqlite_async/sqlite_async.dart' as sqlite_async;

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
    // ---- Seed identical datasets per library. ----
    final resqliteDb = await resqlite.Database.open('${tempDir.path}/resqlite.db');
    await seedResqlite(resqliteDb, 1000);

    final sqlite3Db = sqlite3.sqlite3.open('${tempDir.path}/sqlite3.db');
    sqlite3Db.execute('PRAGMA journal_mode = WAL');
    seedSqlite3(sqlite3Db, 1000);

    final asyncDb = sqlite_async.SqliteDatabase(path: '${tempDir.path}/async.db');
    await asyncDb.initialize();
    await seedSqliteAsync(asyncDb, 1000);

    // ---- Measure each library. ----
    libResults['resqlite'] = await _measureResqlite(resqliteDb);
    libResults['sqlite3'] = _measureSqlite3(sqlite3Db);
    libResults['sqlite_async'] = await _measureSqliteAsync(asyncDb);

    await resqliteDb.close();
    sqlite3Db.close();
    await asyncDb.close();
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
  // is applied downstream in run_all.
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
    mdeCiPct: minimumDetectableEffectPct(qpsSamples),
    mdeMadPct: madBasedDetectableEffectPct(qpsSamples),
  );
}

Future<_QpsResult> _measureResqlite(resqlite.Database db) async {
  const sql = 'SELECT * FROM items WHERE id = ?';
  for (var i = 0; i < _warmupIterations * 10; i++) {
    await db.select(sql, [i % 1000 + 1]);
  }
  final timings = <int>[];
  for (var iter = 0; iter < _iterations; iter++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < _queryCount; i++) {
      await db.select(sql, [i % 1000 + 1]);
    }
    sw.stop();
    timings.add(sw.elapsedMicroseconds);
  }
  return _summarize(timings);
}

_QpsResult _measureSqlite3(sqlite3.Database db) {
  const sql = 'SELECT * FROM items WHERE id = ?';
  final stmt = db.prepare(sql);
  for (var i = 0; i < _warmupIterations * 10; i++) {
    final rs = stmt.select([i % 1000 + 1]);
    for (final _ in rs) {}
  }
  final timings = <int>[];
  for (var iter = 0; iter < _iterations; iter++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < _queryCount; i++) {
      final rs = stmt.select([i % 1000 + 1]);
      for (final _ in rs) {}
    }
    sw.stop();
    timings.add(sw.elapsedMicroseconds);
  }
  stmt.close();
  return _summarize(timings);
}

Future<_QpsResult> _measureSqliteAsync(sqlite_async.SqliteDatabase db) async {
  const sql = 'SELECT * FROM items WHERE id = ?';
  for (var i = 0; i < _warmupIterations * 10; i++) {
    await db.get(sql, [i % 1000 + 1]);
  }
  final timings = <int>[];
  for (var iter = 0; iter < _iterations; iter++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < _queryCount; i++) {
      await db.get(sql, [i % 1000 + 1]);
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
