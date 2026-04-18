// ignore_for_file: avoid_print
import 'dart:io';

import '../drift/micro_items_db.dart';
import '../shared/config.dart';
import '../shared/peer.dart';
import '../shared/seeder.dart';
import '../shared/stats.dart';

/// Core maps benchmark: select → iterate all fields.
Future<String> runSelectMapsBenchmark() async {
  final markdown = StringBuffer();
  markdown.writeln('## Select → Maps');
  markdown.writeln('');
  markdown.writeln('Query returns `List<Map<String, Object?>>`, caller iterates every field.');
  markdown.writeln('');

  for (final rowCount in standardRowCounts) {
    final tempDir = await Directory.systemTemp.createTemp('bench_maps_');
    try {
      final timings = await _benchmarkAtSize(tempDir.path, rowCount);
      printComparisonTable('=== Select Maps: $rowCount rows ===', timings);
      markdown.write(markdownTable('$rowCount rows', timings));
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  return markdown.toString();
}

Future<List<BenchmarkTiming>> _benchmarkAtSize(
  String dir,
  int rowCount,
) async {
  final peers = await PeerSet.open(
    dir,
    driftFactory: driftFactoryFor((exec) => MicroItemsDriftDb(exec)),
  );
  final timings = <BenchmarkTiming>[];
  try {
    for (final peer in peers.all) {
      await seedPeer(peer, rowCount);
    }

    // Same SQL + same consume-every-field loop on every peer. Each
    // peer decodes at its own natural pace; we measure wall (dispatch
    // + await + consume) and, for async peers, split main-isolate time
    // to capture post-return materialization cost separately.
    for (final peer in peers.all) {
      final t = BenchmarkTiming('${peer.label} select()');
      for (var i = 0; i < defaultWarmup; i++) {
        final r = await peer.select(standardSelectSql);
        _consumeRows(r);
      }
      for (var i = 0; i < defaultIterations; i++) {
        final swMain = Stopwatch();
        final swWall = Stopwatch()..start();
        swMain.start();
        final future = peer.select(standardSelectSql);
        swMain.stop();
        final r = await future;
        swMain.start();
        _consumeRows(r);
        swMain.stop();
        swWall.stop();
        if (peer.isSynchronous) {
          t.recordWallOnly(swWall.elapsedMicroseconds);
        } else {
          t.record(
            wallMicroseconds: swWall.elapsedMicroseconds,
            mainMicroseconds: swMain.elapsedMicroseconds,
          );
        }
      }
      timings.add(t);
    }
  } finally {
    await peers.closeAll();
  }

  return timings;
}

void _consumeRows(List<Map<String, Object?>> rows) {
  for (final row in rows) {
    for (final key in row.keys) {
      row[key];
    }
  }
}

// Allow running standalone.
Future<void> main() async {
  await runSelectMapsBenchmark();
}
