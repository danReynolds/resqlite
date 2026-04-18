// ignore_for_file: avoid_print
import 'dart:io';

import '../drift/micro_items_db.dart';
import '../shared/config.dart';
import '../shared/peer.dart';
import '../shared/seeder.dart';
import '../shared/stats.dart';

const _rowCount = 1000;
const _concurrencyLevels = [1, 2, 4, 8];

/// Concurrent reads benchmark: parallel Future.wait with varying concurrency.
///
/// sqlite3 is excluded by capability (synchronous, no meaningful concurrency
/// semantic). Remaining peers — resqlite, sqlite_async, drift — all expose
/// async `select()` that participates in `Future.wait`.
///
/// Output format: one subsection per concurrency level, standard
/// `| Library | Wall med | Wall p90 |` table shape. The dashboard's
/// scenario view groups these into a line chart across concurrency
/// levels.
Future<String> runConcurrentReadsBenchmark() async {
  final markdown = StringBuffer();
  markdown.writeln('## Concurrent Reads (1000 rows per query)');
  markdown.writeln('');
  markdown.writeln('Multiple parallel `select()` calls via `Future.wait`. '
      'sqlite3 is excluded (synchronous, no concurrency). Each concurrency '
      'level runs `N` parallel queries; we report both total wall time and '
      'effective per-query latency (total / N).');
  markdown.writeln('');

  final tempDir = await Directory.systemTemp.createTemp('bench_concurrent_');
  try {
    final peers = await PeerSet.open(
      tempDir.path,
      require: (p) => !p.isSynchronous,
      driftFactory: driftFactoryFor((exec) => MicroItemsDriftDb(exec)),
    );
    try {
      for (final peer in peers.all) {
        await seedPeer(peer, _rowCount);
      }

      print('');
      print('=== Concurrent Reads ===');

      for (final n in _concurrencyLevels) {
        markdown.writeln('### ${n}× concurrency');
        markdown.writeln('');
        markdown.writeln(
          '| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |',
        );
        markdown.writeln('|---|---|---|---|');

        for (final peer in peers.all) {
          // Warmup.
          for (var i = 0; i < defaultWarmup; i++) {
            await Future.wait([
              for (var j = 0; j < n; j++) peer.select(standardSelectSql),
            ]);
          }
          final timing = BenchmarkTiming(peer.label);
          for (var i = 0; i < defaultIterations; i++) {
            final sw = Stopwatch()..start();
            await Future.wait([
              for (var j = 0; j < n; j++) peer.select(standardSelectSql),
            ]);
            sw.stop();
            timing.recordWallOnly(sw.elapsedMicroseconds);
          }
          final perQuery = timing.wall.medianMs / n;
          markdown.writeln(
            '| ${peer.label} '
            '| ${timing.wall.medianMs.toStringAsFixed(2)} '
            '| ${timing.wall.p90Ms.toStringAsFixed(2)} '
            '| ${perQuery.toStringAsFixed(2)} |',
          );
          print(
            '${peer.label.padRight(14)} ${n}× '
            '${fmtMs(timing.wall.medianMs)} ms wall, '
            '${fmtMs(perQuery)} ms/query',
          );
        }
        markdown.writeln('');
      }
    } finally {
      await peers.closeAll();
    }
  } finally {
    await tempDir.delete(recursive: true);
  }

  return markdown.toString();
}

Future<void> main() async {
  await runConcurrentReadsBenchmark();
}
