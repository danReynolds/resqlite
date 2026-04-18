// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;

import '../drift/micro_items_db.dart';
import '../shared/config.dart';
import '../shared/peer.dart';
import '../shared/seeder.dart';
import '../shared/stats.dart';

const _rowCounts = [10, 50, 100, 500, 1000, 2000, 5000, 10000, 20000];

/// Scaling benchmark: how performance changes with result size.
///
/// Two sub-benchmarks per row count:
///   * **Maps** — `select()` + full-field-iteration. Standard read path.
///   * **Bytes** — select-then-encode JSON path on all peers, plus a
///     separate resqlite-native `selectBytes()` row showcasing the
///     zero-copy fast path.
///
/// Identifies where isolate overhead amortizes and where the byte path
/// diverges from the map path per library.
Future<String> runScalingBenchmark() async {
  final markdown = StringBuffer();
  markdown.writeln('## Scaling (10 → 20,000 rows)');
  markdown.writeln('');
  markdown.writeln('Shows how each library scales with result size. Identifies the crossover '
      'point where resqlite\'s isolate overhead becomes negligible.');
  markdown.writeln('');

  markdown.writeln('### Maps (select → iterate all fields)');
  markdown.writeln('');

  print('');
  print('=== Scaling: Maps ===');

  for (final rowCount in _rowCounts) {
    final tempDir = await Directory.systemTemp.createTemp('bench_scale_');
    try {
      final timings = await _benchmarkMaps(tempDir.path, rowCount);
      print('-- $rowCount rows --');
      for (final t in timings) {
        print('${t.label.padRight(24)} ${fmtMs(t.wall.medianMs)} ms');
      }
      markdown.write(markdownTable('$rowCount rows', timings));
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  markdown.writeln('');
  markdown.writeln('### Bytes (selectBytes → JSON)');
  markdown.writeln('');

  print('');
  print('=== Scaling: Bytes ===');

  for (final rowCount in _rowCounts) {
    final tempDir = await Directory.systemTemp.createTemp('bench_scale_b_');
    try {
      final timings = await _benchmarkBytes(tempDir.path, rowCount);
      print('-- $rowCount rows --');
      for (final t in timings) {
        print('${t.label.padRight(28)} ${fmtMs(t.wall.medianMs)} ms');
      }
      markdown.write(markdownTable('$rowCount rows', timings));
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  markdown.writeln('');
  return markdown.toString();
}

Future<List<BenchmarkTiming>> _benchmarkMaps(String dir, int rowCount) async {
  final peers = await PeerSet.open(
    dir,
    driftFactory: driftFactoryFor((exec) => MicroItemsDriftDb(exec)),
  );
  final timings = <BenchmarkTiming>[];
  try {
    for (final peer in peers.all) {
      await seedPeer(peer, rowCount);
    }

    for (final peer in peers.all) {
      final t = BenchmarkTiming(peer.label);
      for (var i = 0; i < defaultWarmup; i++) {
        _consume(await peer.select(standardSelectSql));
      }
      for (var i = 0; i < defaultIterations; i++) {
        final swMain = Stopwatch();
        final swWall = Stopwatch()..start();
        swMain.start();
        final future = peer.select(standardSelectSql);
        swMain.stop();
        final r = await future;
        swMain.start();
        _consume(r);
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

Future<List<BenchmarkTiming>> _benchmarkBytes(String dir, int rowCount) async {
  final timings = <BenchmarkTiming>[];

  // Peer path: select() + utf8.encode(jsonEncode(...)).
  final peers = await PeerSet.open(
    dir,
    driftFactory: driftFactoryFor((exec) => MicroItemsDriftDb(exec)),
  );
  try {
    for (final peer in peers.all) {
      await seedPeer(peer, rowCount);
    }
    for (final peer in peers.all) {
      final t = BenchmarkTiming('${peer.label} + jsonEncode');
      for (var i = 0; i < defaultWarmup; i++) {
        final r = await peer.select(standardSelectSql);
        utf8.encode(jsonEncode(r));
      }
      for (var i = 0; i < defaultIterations; i++) {
        final sw = Stopwatch()..start();
        final r = await peer.select(standardSelectSql);
        utf8.encode(jsonEncode(r));
        sw.stop();
        t.recordWallOnly(sw.elapsedMicroseconds);
      }
      timings.add(t);
    }
  } finally {
    await peers.closeAll();
  }

  // resqlite native selectBytes() fast path.
  final resqliteDb = await resqlite.Database.open('$dir/resqlite_bytes.db');
  try {
    await seedResqlite(resqliteDb, rowCount);
    final t = BenchmarkTiming('resqlite selectBytes()');
    for (var i = 0; i < defaultWarmup; i++) {
      await resqliteDb.selectBytes(standardSelectSql);
    }
    for (var i = 0; i < defaultIterations; i++) {
      final sw = Stopwatch()..start();
      await resqliteDb.selectBytes(standardSelectSql);
      sw.stop();
      t.recordWallOnly(sw.elapsedMicroseconds);
    }
    timings.add(t);
  } finally {
    await resqliteDb.close();
  }

  return timings;
}

void _consume(List<Map<String, Object?>> rows) {
  for (final row in rows) {
    for (final key in row.keys) {
      row[key];
    }
  }
}

Future<void> main() async {
  await runScalingBenchmark();
}
