// Benchmark: reader pool size comparison (2, 4, 8 workers)
// Tests both sequential and concurrent query patterns.

import 'dart:io';

import 'package:resqlite/resqlite.dart';

import '../shared/seeder.dart';

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('resqlite_poolsize_');

  for (final poolSize in [2, 4, 8]) {
    print('=== Pool size: $poolSize ===\n');

    final dbPath = '${dir.path}/bench_$poolSize.db';
    final db = await Database.open(dbPath);
    await seedResqlite(db, 10000);

    // Give the pool time to spawn all workers.
    await Future.delayed(Duration(milliseconds: 100));

    // --- Sequential point queries (1 at a time) ---
    {
      // Warmup.
      for (var i = 0; i < 50; i++) {
        await db.select('SELECT * FROM items WHERE id = ?', [i]);
      }

      final sw = Stopwatch()..start();
      const count = 1000;
      for (var i = 0; i < count; i++) {
        await db.select('SELECT * FROM items WHERE id = ?', [i % 10000]);
      }
      sw.stop();
      final qps = (count * 1000000 / sw.elapsedMicroseconds).round();
      print('  Sequential point query:  $qps qps');
    }

    // --- Concurrent queries (N at a time, 100 rows each) ---
    for (final concurrency in [2, 4, 8]) {
      // Warmup.
      for (var i = 0; i < 10; i++) {
        await db.select('SELECT * FROM items LIMIT 100');
      }

      final sw = Stopwatch()..start();
      const batches = 50;
      for (var batch = 0; batch < batches; batch++) {
        await Future.wait([
          for (var i = 0; i < concurrency; i++)
            db.select('SELECT * FROM items LIMIT 100'),
        ]);
      }
      sw.stop();
      final totalQueries = batches * concurrency;
      final wallMs = sw.elapsedMicroseconds / 1000;
      final perQueryMs = wallMs / totalQueries;
      print('  Concurrent $concurrency × 100 rows: ${perQueryMs.toStringAsFixed(2)} ms/query  (${wallMs.toStringAsFixed(0)} ms total for $totalQueries queries)');
    }

    // --- Sacrifice recovery (large result triggers respawn) ---
    {
      // Warmup.
      await db.select('SELECT * FROM items LIMIT 5000');
      await Future.delayed(Duration(milliseconds: 200)); // let respawn complete

      final times = <int>[];
      for (var i = 0; i < 10; i++) {
        final sw = Stopwatch()..start();
        await db.select('SELECT * FROM items LIMIT 5000');
        sw.stop();
        times.add(sw.elapsedMicroseconds);
        await Future.delayed(Duration(milliseconds: 100)); // respawn time
      }
      times.sort();
      print('  Sacrifice + respawn (5k rows): ${(times[times.length ~/ 2] / 1000).toStringAsFixed(2)} ms median');
    }

    print('');
    await db.close();
  }

  await dir.delete(recursive: true);
  exit(0);
}
