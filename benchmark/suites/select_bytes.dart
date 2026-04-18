// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;

import '../drift/micro_items_db.dart';
import '../shared/config.dart';
import '../shared/peer.dart';
import '../shared/seeder.dart';
import '../shared/stats.dart';

/// Bytes benchmark: query → JSON bytes (for HTTP response).
///
/// resqlite's `selectBytes()` is a native-side-encoded, zero-copy path
/// that returns `Uint8List` without materializing Dart maps. Other peers
/// don't have this API — a drift/sqlite3/sqlite_async user gets bytes
/// by calling `select()` + `utf8.encode(jsonEncode(...))` on the main
/// isolate. To be fair, we report both:
///
///   * one dedicated row for resqlite's native `selectBytes()` (the
///     feature being showcased)
///   * one row per peer for the idiomatic "select + encode" path,
///     including resqlite itself so readers can see the delta between
///     its two options
///
/// That gives 4 peers' select+encode costs side-by-side (fair comparison
/// of the path everyone has to run) plus resqlite's native fast path as
/// a separate data point.
Future<String> runSelectBytesBenchmark() async {
  final markdown = StringBuffer();
  markdown.writeln('## Select → JSON Bytes');
  markdown.writeln('');
  markdown.writeln(
    'Query result serialized to JSON-encoded `Uint8List` for HTTP response. '
    'resqlite\'s `selectBytes()` encodes natively on the worker isolate (zero-copy '
    'transfer to main); other peers and resqlite\'s own `select()` path go through '
    '`jsonEncode + utf8.encode` on the main isolate. Both numbers are reported '
    'per peer for the select+encode path; resqlite also reports its native '
    'selectBytes path as a separate row.',
  );
  markdown.writeln('');

  for (final rowCount in standardRowCounts) {
    final tempDir = await Directory.systemTemp.createTemp('bench_bytes_');
    try {
      final timings = await _benchmarkAtSize(tempDir.path, rowCount);
      printComparisonTable('=== Select Bytes: $rowCount rows ===', timings);
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
  final timings = <BenchmarkTiming>[];

  // --- Peer path: select() + utf8.encode(jsonEncode(...)) -------------
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
        final swMain = Stopwatch();
        final swWall = Stopwatch()..start();
        swMain.start();
        final future = peer.select(standardSelectSql);
        swMain.stop();
        final r = await future;
        swMain.start();
        utf8.encode(jsonEncode(r));
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

  // --- resqlite native selectBytes() ----------------------------------
  // Uses a dedicated db file to avoid any interference with the peer-set
  // cleanup above.
  final resqliteDb = await resqlite.Database.open('$dir/resqlite_bytes.db');
  try {
    await seedResqlite(resqliteDb, rowCount);
    final t = BenchmarkTiming('resqlite selectBytes()');
    for (var i = 0; i < defaultWarmup; i++) {
      await resqliteDb.selectBytes(standardSelectSql);
    }
    for (var i = 0; i < defaultIterations; i++) {
      final swMain = Stopwatch();
      final swWall = Stopwatch()..start();
      swMain.start();
      final future = resqliteDb.selectBytes(standardSelectSql);
      swMain.stop();
      final bytes = await future;
      swMain.start();
      bytes.length; // post-await resume
      swMain.stop();
      swWall.stop();
      t.record(
        wallMicroseconds: swWall.elapsedMicroseconds,
        mainMicroseconds: swMain.elapsedMicroseconds,
      );
    }
    timings.add(t);
  } finally {
    await resqliteDb.close();
  }

  return timings;
}

Future<void> main() async {
  await runSelectBytesBenchmark();
}
