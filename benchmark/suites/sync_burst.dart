// ignore_for_file: avoid_print

/// A7 — Sync Burst (v1).
///
/// Models offline-first apps pulling from a server and applying bulk
/// changes while the UI has active reactive streams.
///
/// Phases:
///   1. **Bulk insert**: 50,000 rows inserted via `executeBatch` in
///      500-row chunks. Measures throughput of the batch path and how
///      well the library handles a large commit burst.
///   2. **Incremental merges**: 10 rounds of 100-row
///      `INSERT OR REPLACE` each, simulating sync deltas. Measures
///      per-round latency after the main ingest.
///   3. **Active stream throughout**: one `SELECT COUNT(*) FROM items`
///      stream runs during both phases. The stream's emission count
///      and settle time give a clean signal on invalidation overhead.
///
/// Opt-in via `--include-slow` — this workload takes ~10-30s per
/// peer because 50K rows × 3 peers requires real I/O.
///
/// Peers: all three. sqlite3 is synchronous; we still include it for
/// the bulk-insert path (no streams needed for that phase). The
/// active-stream phase runs on the reactive-capable peers only.
library;

import 'dart:async';
import 'dart:io';

import '../drift/sync_burst_db.dart';
import '../shared/peer.dart';
import '../shared/stats.dart';
import '../shared/workload.dart';

const WorkloadMeta syncBurstMeta = WorkloadMeta(
  slug: 'sync_burst',
  version: 1,
  title: 'Sync Burst',
  description: '50K bulk insert via executeBatch in 500-row chunks, '
      'then 10 × 100-row INSERT OR REPLACE merges. A COUNT(*) stream '
      'stays active throughout on reactive peers. Models offline-first '
      'sync: a client pulling from a server, applying batched changes, '
      'while the local UI shows live counts. Opt-in via --include-slow.',
);

const int _bulkRowCount = 50000;
const int _bulkChunkSize = 500;
const int _mergeRounds = 10;
const int _mergeRowsPerRound = 100;
const int _iterations = 2;
const int _warmup = 0; // bulk-insert benchmarks are slow; skip warmup

Future<String> runSyncBurstBenchmark() async {
  final md = StringBuffer()
    ..writeln('## ${syncBurstMeta.sectionHeading}')
    ..writeln()
    ..writeln(syncBurstMeta.description)
    ..writeln();

  final bulkByPeer = <String, BenchmarkTiming>{};
  final mergeByPeer = <String, BenchmarkTiming>{};
  final streamEmissionsByPeer = <String, int>{};

  final tempDir =
      await Directory.systemTemp.createTemp('bench_sync_burst_');
  try {
    final peers = await PeerSet.open(
      tempDir.path,
      driftFactory: driftFactoryFor((exec) => SyncBurstDriftDb(exec)),
    );
    try {
      for (final peer in peers.all) {
        print('  running on ${peer.name}...');
        final (bulkTiming, mergeTiming, emissions) =
            await _measure(peer);
        bulkByPeer[peer.label] = bulkTiming;
        mergeByPeer[peer.label] = mergeTiming;
        if (peer.hasStreams) {
          streamEmissionsByPeer[peer.label] = emissions;
        }
      }
    } finally {
      await peers.closeAll();
    }
  } finally {
    await tempDir.delete(recursive: true);
  }

  _writeBulkSection(md, bulkByPeer);
  _writeMergeSection(md, mergeByPeer);
  _writeStreamSection(md, streamEmissionsByPeer);
  return md.toString();
}

Future<(BenchmarkTiming bulk, BenchmarkTiming merge, int emissions)>
    _measure(BenchmarkPeer peer) async {
  final bulk = BenchmarkTiming(peer.label);
  final merge = BenchmarkTiming(peer.label);
  var totalEmissions = 0;

  for (var iter = 0; iter < _warmup + _iterations; iter++) {
    // Fresh schema per iteration — bulk insert into an empty table
    // is the behavior we want to measure repeatedly.
    // DROP then CREATE IF NOT EXISTS so the drift peer (which auto-
    // creates the table at open) doesn't trip on "already exists", and
    // every iteration still starts from an empty table — the bulk-
    // insert path is what we're measuring. Schema must match
    // benchmark/drift/sync_burst_db.dart exactly.
    await peer.execute('DROP TABLE IF EXISTS items');
    await peer.execute('CREATE TABLE IF NOT EXISTS items('
        'id INTEGER PRIMARY KEY, '
        'external_id INTEGER UNIQUE, '
        'payload TEXT NOT NULL)');

    // Start the live-count stream before the writes begin.
    var emitCount = 0;
    StreamSubscription<List<Map<String, Object?>>>? sub;
    if (peer.hasStreams) {
      final stream = peer.watch(
        'SELECT COUNT(*) AS c FROM items',
        readsFrom: const {'items'},
      );
      sub = stream.listen((_) => emitCount++);
      // Drain initial emission.
      final initialDeadline =
          DateTime.now().add(const Duration(seconds: 10));
      while (emitCount < 1) {
        if (DateTime.now().isAfter(initialDeadline)) {
          fail('${peer.name}: initial emission never arrived');
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      emitCount = 0; // reset baseline after initial.
    }

    // Phase 1: bulk insert.
    final bulkSw = Stopwatch()..start();
    for (var offset = 0; offset < _bulkRowCount; offset += _bulkChunkSize) {
      final n = (offset + _bulkChunkSize <= _bulkRowCount)
          ? _bulkChunkSize
          : _bulkRowCount - offset;
      await peer.executeBatch(
        'INSERT INTO items(external_id, payload) VALUES (?, ?)',
        [
          for (var i = 0; i < n; i++) [offset + i, 'payload_${offset + i}'],
        ],
      );
    }
    bulkSw.stop();
    if (iter >= _warmup) {
      if (peer.isSynchronous) {
        bulk.recordWallOnly(bulkSw.elapsedMicroseconds);
      } else {
        bulk.record(
          wallMicroseconds: bulkSw.elapsedMicroseconds,
          // Bulk writes await the writer isolate; main-isolate cost is
          // the dispatch overhead per chunk (~tens of us at most).
          mainMicroseconds: 0,
        );
      }
    }

    // Phase 2: incremental merges.
    final mergeSw = Stopwatch()..start();
    for (var round = 0; round < _mergeRounds; round++) {
      await peer.executeBatch(
        'INSERT OR REPLACE INTO items(external_id, payload) VALUES (?, ?)',
        [
          for (var i = 0; i < _mergeRowsPerRound; i++)
            [
              _bulkRowCount + round * _mergeRowsPerRound + i,
              'merge_${round}_$i',
            ],
        ],
      );
    }
    mergeSw.stop();
    if (iter >= _warmup) {
      if (peer.isSynchronous) {
        merge.recordWallOnly(mergeSw.elapsedMicroseconds);
      } else {
        merge.record(
          wallMicroseconds: mergeSw.elapsedMicroseconds,
          mainMicroseconds: 0,
        );
      }
    }

    // Let any outstanding stream re-queries settle before tearing down.
    if (sub != null) {
      const quietWindow = Duration(milliseconds: 200);
      var lastCount = emitCount;
      final quietDeadline =
          DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(quietDeadline)) {
        await Future<void>.delayed(quietWindow);
        if (emitCount == lastCount) break;
        lastCount = emitCount;
      }
      if (iter >= _warmup) {
        totalEmissions += emitCount;
      }
      await sub.cancel();
    }
  }

  return (bulk, merge, totalEmissions ~/ _iterations);
}

void _writeBulkSection(
  StringBuffer md,
  Map<String, BenchmarkTiming> byPeer,
) {
  md
    ..writeln('### Bulk insert: $_bulkRowCount rows × $_bulkChunkSize-row chunks')
    ..writeln()
    ..writeln('| Library | Wall med (ms) | Wall p90 (ms) | '
        'Main med (ms) | Main p90 (ms) |')
    ..writeln('|---|---|---|---|---|');
  for (final timing in byPeer.values) {
    md.writeln(
      '| ${timing.label} '
      '| ${timing.wall.medianMs.toStringAsFixed(2)} '
      '| ${timing.wall.p90Ms.toStringAsFixed(2)} '
      '| ${timing.main.medianMs.toStringAsFixed(2)} '
      '| ${timing.main.p90Ms.toStringAsFixed(2)} |',
    );
  }
  md.writeln();
}

void _writeMergeSection(
  StringBuffer md,
  Map<String, BenchmarkTiming> byPeer,
) {
  md
    ..writeln('### Merge rounds: $_mergeRounds × $_mergeRowsPerRound rows')
    ..writeln()
    ..writeln('| Library | Wall med (ms) | Wall p90 (ms) | '
        'Main med (ms) | Main p90 (ms) |')
    ..writeln('|---|---|---|---|---|');
  for (final timing in byPeer.values) {
    md.writeln(
      '| ${timing.label} '
      '| ${timing.wall.medianMs.toStringAsFixed(2)} '
      '| ${timing.wall.p90Ms.toStringAsFixed(2)} '
      '| ${timing.main.medianMs.toStringAsFixed(2)} '
      '| ${timing.main.p90Ms.toStringAsFixed(2)} |',
    );
  }
  md.writeln();
}

void _writeStreamSection(
  StringBuffer md,
  Map<String, int> byPeer,
) {
  if (byPeer.isEmpty) return;
  md
    ..writeln('### Stream emissions during burst (COUNT(*))')
    ..writeln()
    ..writeln('| Library | Emissions |')
    ..writeln('|---|---|');
  for (final entry in byPeer.entries) {
    md.writeln('| ${entry.key} | ${entry.value} |');
  }
  md
    ..writeln()
    ..writeln('Every batch commit invalidates the COUNT(*) stream. '
        'Fewer emissions under the same write load signals better '
        'coalescing; more emissions may indicate per-commit re-emit '
        'without the suppression logic resqlite\'s engine applies '
        '(exp 031/033/075 + PR #17\'s per-stream re-query coalescing).')
    ..writeln();
}

Never fail(String msg) {
  throw StateError(msg);
}

Future<void> main() async {
  final md = await runSyncBurstBenchmark();
  print(md);
}
