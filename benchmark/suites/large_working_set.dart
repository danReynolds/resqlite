// ignore_for_file: avoid_print

/// A9 — Large Working Set (v1).
///
/// Measures behavior on a database whose size exceeds typical mmap /
/// page-cache capacity. Seeds a ~1 GB database once (cached across
/// runs), then measures random-point and range-scan latency under
/// both cold-cache and warm-cache conditions.
///
/// Why this workload exists: every other benchmark in the suite uses
/// ≤10K rows that fit entirely in SQLite's 256 MB mmap window. On a
/// mature production app with years of data, you routinely hit the
/// mmap boundary — at which point mmap stops helping, OS page-cache
/// eviction matters, and query-plan choices (index-driven vs. table
/// scan) have consequences they don't have on small data.
///
/// Peers: all three. Reads only, no streams.
///
/// Opt-in via `--include-slow`. Seed takes ~1-3 minutes the first
/// time; subsequent runs cache the seeded DB file in
/// `benchmark/results/_cache/` and start immediately.
///
/// Cold vs warm distinction:
///   - **Warm**: 10 rounds of the same queries back-to-back. The
///     OS page cache and SQLite's pcache fill in during round 1;
///     rounds 2+ hit cache.
///   - **Cold**: between each round, call `PRAGMA shrink_memory` on
///     the DB to drop pcache. OS page cache is not fully evicted by
///     that PRAGMA (OS owns it), so "cold" here means
///     "SQLite's pcache is cold; OS may still help." A truer cold
///     test requires reopening the connection, which this workload
///     does not do.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../drift/large_working_set_db.dart';
import '../shared/peer.dart';
import '../shared/stats.dart';
import '../shared/workload.dart';

const WorkloadMeta largeWorkingSetMeta = WorkloadMeta(
  slug: 'large_working_set',
  version: 1,
  title: 'Large Working Set',
  description: 'Random-point and range-scan latency on a ~1 GB '
      'database. Measures behavior at scale, where mmap and page '
      'cache matter. Cold-cache and warm-cache variants reported '
      'separately. Seed is cached across runs. Opt-in via '
      '--include-slow.',
);

/// Target size ~1 GB. 200-byte payload × 5M rows ≈ 1 GB + indexes.
const int _seedRowCount = 5000000;
const int _payloadLength = 200;
const int _pointQueriesPerRound = 1000;
const int _rangeScansPerRound = 10;
const int _rangeScanLimit = 500;
const int _warmRounds = 5;
const int _coldRounds = 3;
const int _prngSeed = 0xB16B00B5;

/// Production entry — uses the full 1 GB seed scale.
Future<String> runLargeWorkingSetBenchmark() => _runLargeWorkingSetBenchmark(
      seedRowCount: _seedRowCount,
      cacheFilename: 'large_working_set_v1.db',
      pointQueriesPerRound: _pointQueriesPerRound,
      rangeScansPerRound: _rangeScansPerRound,
      warmRounds: _warmRounds,
      coldRounds: _coldRounds,
    );

/// Test entry — uses a reduced scale so the DoD unit test can run
/// in seconds rather than paying the 1 GB seed cost. Exposed only
/// for tests; production callers use [runLargeWorkingSetBenchmark].
Future<String> runLargeWorkingSetBenchmarkSmallForTest() =>
    _runLargeWorkingSetBenchmark(
      seedRowCount: 20000,
      cacheFilename: 'large_working_set_test.db',
      pointQueriesPerRound: 20,
      rangeScansPerRound: 2,
      warmRounds: 1,
      coldRounds: 1,
    );

Future<String> _runLargeWorkingSetBenchmark({
  required int seedRowCount,
  required String cacheFilename,
  required int pointQueriesPerRound,
  required int rangeScansPerRound,
  required int warmRounds,
  required int coldRounds,
}) async {
  final md = StringBuffer()
    ..writeln('## ${largeWorkingSetMeta.sectionHeading}')
    ..writeln()
    ..writeln(largeWorkingSetMeta.description)
    ..writeln();

  // Cache the seeded DB file across runs so repeated invocations
  // don't pay the seed cost. `benchmark/results/_cache/` is already
  // under the benchmark dir hierarchy so CI artifact collection can
  // opt into caching it.
  final cacheDir = Directory('benchmark/results/_cache');
  if (!cacheDir.existsSync()) await cacheDir.create(recursive: true);
  final seedFile = File('${cacheDir.path}/$cacheFilename');

  if (!seedFile.existsSync()) {
    print('  seeding ${(seedRowCount / 1000).toStringAsFixed(0)}K '
        'rows (one-time cost)...');
    await _seedCacheFile(seedFile.path, seedRowCount);
  } else {
    print('  using cached seed at ${seedFile.path} '
        '(${(seedFile.lengthSync() / (1 << 20)).toStringAsFixed(0)} MB)');
  }

  final warmByPeer = <String, _Reading>{};
  final coldByPeer = <String, _Reading>{};

  for (final mode in [_Mode.warm, _Mode.cold]) {
    // Each peer gets its own copy of the seeded DB. We copy rather
    // than open in-place so peers don't stomp each other's WAL / SHM
    // state.
    final tempDir =
        await Directory.systemTemp.createTemp('bench_large_${mode.name}_');
    try {
      final peers = await PeerSet.open(
        tempDir.path,
        driftFactory:
            driftFactoryFor((exec) => LargeWorkingSetDriftDb(exec)),
      );
      try {
        for (final peer in peers.all) {
          // Copy the seed data into the peer's working db.
          final peerDbPath = '${tempDir.path}/${peer.name}.db';
          await peer.close();
          await _copyFile(seedFile, File(peerDbPath));
          // Drift tracks schema via `PRAGMA user_version`. The cached
          // seed was produced by the resqlite peer with raw SQL, so
          // user_version is 0 and drift would try to run its
          // onCreate migrator (which does CREATE TABLE items again,
          // conflicting with the already-seeded table). Stamp the
          // file to schemaVersion=1 so drift treats it as already
          // migrated. No-op for non-drift peers. Schema on disk must
          // match benchmark/drift/large_working_set_db.dart exactly.
          _stampDriftUserVersion(peerDbPath, 1);
          await peer.open(peerDbPath);

          print('  running ${mode.name} on ${peer.name}...');
          final reading = await _measureRounds(
            peer,
            mode,
            seedRowCount: seedRowCount,
            pointQueriesPerRound: pointQueriesPerRound,
            rangeScansPerRound: rangeScansPerRound,
            rounds: mode == _Mode.warm ? warmRounds : coldRounds,
          );
          if (mode == _Mode.warm) {
            warmByPeer[peer.label] = reading;
          } else {
            coldByPeer[peer.label] = reading;
          }
        }
      } finally {
        await peers.closeAll();
      }
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  _writeSection(
    md,
    'Warm cache ($warmRounds rounds)',
    warmByPeer,
    pointQueriesPerRound: pointQueriesPerRound,
    rangeScansPerRound: rangeScansPerRound,
    seedRowCount: seedRowCount,
  );
  _writeSection(
    md,
    'Cold cache ($coldRounds rounds with shrink_memory)',
    coldByPeer,
    pointQueriesPerRound: pointQueriesPerRound,
    rangeScansPerRound: rangeScansPerRound,
    seedRowCount: seedRowCount,
  );
  return md.toString();
}

enum _Mode { warm, cold }

final class _Reading {
  _Reading({required this.label, required this.point, required this.range});
  final String label;
  final BenchmarkTiming point;
  final BenchmarkTiming range;
}

Future<_Reading> _measureRounds(
  BenchmarkPeer peer,
  _Mode mode, {
  required int seedRowCount,
  required int pointQueriesPerRound,
  required int rangeScansPerRound,
  required int rounds,
}) async {
  final point = BenchmarkTiming('${peer.label} point');
  final range = BenchmarkTiming('${peer.label} range');

  for (var r = 0; r < rounds; r++) {
    if (mode == _Mode.cold) {
      await peer.execute('PRAGMA shrink_memory');
    }
    // Random point queries.
    final prng = math.Random(_prngSeed ^ r);
    for (var i = 0; i < pointQueriesPerRound; i++) {
      final id = prng.nextInt(seedRowCount) + 1;
      final sw = Stopwatch()..start();
      final rows =
          await peer.select('SELECT payload FROM items WHERE id = ?', [id]);
      for (final row in rows) {
        for (final v in row.values) {
          if (identical(v, v)) continue;
        }
      }
      sw.stop();
      if (peer.isSynchronous) {
        point.recordWallOnly(sw.elapsedMicroseconds);
      } else {
        point.record(
          wallMicroseconds: sw.elapsedMicroseconds,
          mainMicroseconds: 0,
        );
      }
    }
    // Range scans.
    for (var i = 0; i < rangeScansPerRound; i++) {
      final start = prng.nextInt(seedRowCount - _rangeScanLimit) + 1;
      final sw = Stopwatch()..start();
      final rows = await peer.select(
        'SELECT payload FROM items WHERE id >= ? AND id < ? LIMIT ?',
        [start, start + _rangeScanLimit, _rangeScanLimit],
      );
      for (final row in rows) {
        for (final v in row.values) {
          if (identical(v, v)) continue;
        }
      }
      sw.stop();
      if (peer.isSynchronous) {
        range.recordWallOnly(sw.elapsedMicroseconds);
      } else {
        range.record(
          wallMicroseconds: sw.elapsedMicroseconds,
          mainMicroseconds: 0,
        );
      }
    }
  }
  return _Reading(label: peer.label, point: point, range: range);
}

// ---------------------------------------------------------------------------
// Seed (one-time, cached)
// ---------------------------------------------------------------------------

Future<void> _seedCacheFile(String path, int seedRowCount) async {
  // Use the resqlite peer for the seed — we only need the data at
  // rest; any peer that can produce a valid SQLite file would do.
  final peer = ResqlitePeer();
  await peer.open(path);
  try {
    await peer.execute('CREATE TABLE items('
        'id INTEGER PRIMARY KEY, '
        'payload TEXT NOT NULL)');
    // Chunked batch insert so we don't allocate one massive paramSets
    // array (5M rows would blow up heap).
    const chunkSize = 5000;
    final payload = List.filled(_payloadLength, 'x').join();
    final progressEvery = seedRowCount ~/ 10; // 10% increments
    for (var offset = 0; offset < seedRowCount; offset += chunkSize) {
      final n = (offset + chunkSize <= seedRowCount)
          ? chunkSize
          : seedRowCount - offset;
      await peer.executeBatch(
        'INSERT INTO items(payload) VALUES (?)',
        [for (var i = 0; i < n; i++) [payload]],
      );
      if (progressEvery > 0 && offset > 0 && offset % progressEvery == 0) {
        print('    seeded '
            '${(offset / seedRowCount * 100).toStringAsFixed(0)}%');
      }
    }
    print('    seeded 100%');
  } finally {
    await peer.close();
  }
}

Future<void> _copyFile(File src, File dest) async {
  await src.openRead().pipe(dest.openWrite());
}

/// Stamp a SQLite file's `PRAGMA user_version` synchronously. Used to
/// signal drift's migrator that the seeded table is at the current
/// schema version, so drift skips its `onCreate` step. A raw
/// `sqlite3.dart` open is cheap and avoids polluting the peer abstraction
/// with a setup-only hook.
void _stampDriftUserVersion(String path, int version) {
  final raw = sqlite3.sqlite3.open(path);
  try {
    raw.execute('PRAGMA user_version = $version');
  } finally {
    raw.close();
  }
}

void _writeSection(
  StringBuffer md,
  String title,
  Map<String, _Reading> byPeer, {
  required int pointQueriesPerRound,
  required int rangeScansPerRound,
  required int seedRowCount,
}) {
  md
    ..writeln('### $title')
    ..writeln()
    ..writeln('Random-point ($pointQueriesPerRound/round) and range-scan '
        '($rangeScansPerRound/round, LIMIT $_rangeScanLimit) against a '
        '${(seedRowCount / 1000).toStringAsFixed(0)}K-row table.')
    ..writeln()
    ..writeln('| Library | Point p50 (ms) | Point p90 (ms) | '
        'Range p50 (ms) | Range p90 (ms) |')
    ..writeln('|---|---|---|---|---|');
  for (final reading in byPeer.values) {
    md.writeln(
      '| ${reading.label} '
      '| ${reading.point.wall.medianMs.toStringAsFixed(3)} '
      '| ${reading.point.wall.p90Ms.toStringAsFixed(3)} '
      '| ${reading.range.wall.medianMs.toStringAsFixed(3)} '
      '| ${reading.range.wall.p90Ms.toStringAsFixed(3)} |',
    );
  }
  md.writeln();
}

Future<void> main() async {
  final md = await runLargeWorkingSetBenchmark();
  print(md);
}
