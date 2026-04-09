// ignore_for_file: avoid_print
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;

import '../shared/config.dart';
import '../shared/seeder.dart';
import '../shared/stats.dart';

/// Point query throughput: SELECT WHERE id = ? in a hot loop.
/// Reports queries per second — the latency floor for the pool dispatch path.
Future<String> runPointQueryBenchmark() async {
  final markdown = StringBuffer();
  markdown.writeln('## Point Query Throughput');
  markdown.writeln('');
  markdown.writeln(
    'Single-row lookup by primary key in a hot loop. Measures the per-query '
    'dispatch overhead of the reader pool.',
  );
  markdown.writeln('');

  final tempDir = await Directory.systemTemp.createTemp('bench_point_');
  try {
    final db = await resqlite.Database.open('${tempDir.path}/resqlite.db');
    await seedResqlite(db, 1000);

    const queryCount = 500;

    // Warmup.
    for (var i = 0; i < defaultWarmup * 10; i++) {
      await db.select('SELECT * FROM items WHERE id = ?', [i % 1000 + 1]);
    }

    // Measure.
    final timings = <int>[];
    for (var iter = 0; iter < defaultIterations; iter++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < queryCount; i++) {
        await db.select('SELECT * FROM items WHERE id = ?', [i % 1000 + 1]);
      }
      sw.stop();
      timings.add(sw.elapsedMicroseconds);
    }

    timings.sort();
    final medianUs = timings[timings.length ~/ 2];
    final qps = (queryCount * 1000000 / medianUs).round();
    final perQueryUs = medianUs / queryCount;

    markdown.writeln('| Metric | Value |');
    markdown.writeln('|---|---:|');
    markdown.writeln('| resqlite qps | $qps |');
    markdown.writeln(
      '| resqlite per query | ${(perQueryUs / 1000).toStringAsFixed(3)} ms |',
    );
    markdown.writeln('');

    print('');
    print('=== Point Query ===');
    print('$qps qps (${perQueryUs.toStringAsFixed(1)} µs/query)');
    print('');

    await db.close();
  } finally {
    await tempDir.delete(recursive: true);
  }

  return markdown.toString();
}
