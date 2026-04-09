// Benchmark: reader pool performance across result sizes.
// Exercises both the SendPort path (small results) and the Isolate.exit
// sacrifice path (large results), showing the pool's adaptive behavior.

import 'dart:io';

import 'package:resqlite/resqlite.dart';

import '../shared/config.dart';
import '../shared/seeder.dart';
import '../shared/stats.dart';

Future<void> main() async {
  print('=== Reader Pool Across Result Sizes ===\n');

  final dir = await Directory.systemTemp.createTemp('resqlite_pool_');
  final dbPath = '${dir.path}/bench.db';
  final db = await Database.open(dbPath);
  await seedResqlite(db, 10000);

  for (final rowCount in [1, 10, 50, 100, 500, 1000, 5000]) {
    final sql = 'SELECT * FROM items LIMIT $rowCount';

    // Warmup.
    for (var i = 0; i < defaultWarmup; i++) {
      await db.select(sql);
    }

    final timing = BenchmarkTiming('pool ($rowCount rows)');
    for (var i = 0; i < defaultIterations; i++) {
      final sw = Stopwatch()..start();
      final result = await db.select(sql);
      sw.stop();
      for (final row in result) { row.values; }
      timing.wallUs.add(sw.elapsedMicroseconds);
      timing.mainUs.add(sw.elapsedMicroseconds);
    }

    // Estimate which pool path was taken (6 cols in seeded data).
    final cells = rowCount * 6;
    final path = cells > 6000 ? 'SACRIFICE' : 'SENDPORT';
    printComparisonTable('=== $rowCount rows ($path) ===', [timing]);
    print('');
  }

  // Point query throughput test.
  print('=== Point Query Throughput ===\n');
  {
    for (var i = 0; i < 50; i++) {
      await db.select('SELECT * FROM items WHERE id = ?', [i]);
    }

    final sw = Stopwatch()..start();
    const count = 500;
    for (var i = 0; i < count; i++) {
      await db.select('SELECT * FROM items WHERE id = ?', [i % 10000]);
    }
    sw.stop();
    final us = sw.elapsedMicroseconds;
    final qps = (count * 1000000 / us).round();
    print('Pool: ${(us / count / 1000).toStringAsFixed(2)} ms/query ($qps qps)');
  }

  // selectBytes throughput test.
  print('\n=== selectBytes Throughput ===\n');
  for (final rowCount in [100, 1000, 5000]) {
    final sql = 'SELECT * FROM items LIMIT $rowCount';

    for (var i = 0; i < defaultWarmup; i++) {
      await db.selectBytes(sql);
    }

    final timing = BenchmarkTiming('selectBytes ($rowCount rows)');
    for (var i = 0; i < defaultIterations; i++) {
      final sw = Stopwatch()..start();
      await db.selectBytes(sql);
      sw.stop();
      timing.wallUs.add(sw.elapsedMicroseconds);
      timing.mainUs.add(sw.elapsedMicroseconds);
    }

    printComparisonTable('$rowCount rows', [timing]);
    print('');
  }

  await db.close();
  await dir.delete(recursive: true);
  exit(0);
}
