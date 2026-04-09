// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:resqlite/resqlite.dart';

/// Streaming benchmarks for resqlite.
/// Outputs JSON results to stdout for the runner to collect.
Future<void> main() async {
  final tempDir = await Directory.systemTemp.createTemp('bench_stream_resqlite_');
  final results = <String, dynamic>{};

  try {
    final db = await Database.open('${tempDir.path}/test.db');
    await db.execute(
      'CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT NOT NULL, value INTEGER NOT NULL)',
    );
    await db.executeBatch(
      'INSERT INTO items(name, value) VALUES (?, ?)',
      [for (var i = 0; i < 100; i++) ['item_$i', i]],
    );

    // --- 1. Initial emission latency ---
    {
      const iterations = 20;
      final timings = <int>[];

      for (var i = 0; i < iterations; i++) {
        final sw = Stopwatch()..start();
        final stream = db.stream('SELECT * FROM items ORDER BY id');
        await stream.first;
        sw.stop();
        timings.add(sw.elapsedMicroseconds);
      }

      timings.sort();
      results['initial_emission_us'] = timings[timings.length ~/ 2];
    }

    // --- 2. Invalidation latency (write → re-emission) ---
    {
      const iterations = 20;
      final timings = <int>[];
      var counter = 1000;

      final stream = db.stream('SELECT COUNT(*) as cnt FROM items');
      final initialCompleter = Completer<void>();
      var gotInitial = false;

      final sub = stream.listen((_) {
        if (!gotInitial) {
          gotInitial = true;
          initialCompleter.complete();
        }
      });

      await initialCompleter.future;

      for (var i = 0; i < iterations; i++) {
        final reEmit = Completer<void>();

        sub.onData((_) {
          if (!reEmit.isCompleted) {
            reEmit.complete();
          }
        });

        final sw = Stopwatch()..start();
        await db.execute('INSERT INTO items(name, value) VALUES (?, ?)', ['bench_${counter++}', i]);
        await reEmit.future.timeout(const Duration(seconds: 2));
        sw.stop();
        timings.add(sw.elapsedMicroseconds);
      }

      await sub.cancel();
      timings.sort();
      results['invalidation_latency_us'] = timings[timings.length ~/ 2];
    }

    // --- 3. Multi-stream fan-out (10 streams, one write) ---
    {
      const streamCount = 10;
      const iterations = 10;
      final timings = <int>[];
      var counter = 5000;

      for (var iter = 0; iter < iterations; iter++) {
        // Set up N streams with unique SQL (no deduplication).
        final initialCompleters = <Completer<void>>[];
        final reEmitCompleters = <Completer<void>>[];
        final subs = <StreamSubscription<List<Map<String, Object?>>>>[];

        for (var i = 0; i < streamCount; i++) {
          final initialC = Completer<void>();
          final reEmitC = Completer<void>();
          initialCompleters.add(initialC);
          reEmitCompleters.add(reEmitC);
          var emitCount = 0;

          final stream = db.stream(
            "SELECT COUNT(*) as cnt, '$i' as sid FROM items",
          );
          subs.add(stream.listen((_) {
            emitCount++;
            if (emitCount == 1 && !initialC.isCompleted) {
              initialC.complete();
            } else if (emitCount >= 2 && !reEmitC.isCompleted) {
              reEmitC.complete();
            }
          }));
        }

        // Wait for all initial emissions.
        await Future.wait(initialCompleters.map((c) => c.future))
            .timeout(const Duration(seconds: 5));

        // Time: write → all re-emissions arrive.
        final sw = Stopwatch()..start();
        await db.execute(
          'INSERT INTO items(name, value) VALUES (?, ?)',
          ['fanout_${counter++}', iter],
        );
        await Future.wait(reEmitCompleters.map((c) => c.future))
            .timeout(const Duration(seconds: 5));
        sw.stop();
        timings.add(sw.elapsedMicroseconds);

        // Clean up subscriptions.
        for (final s in subs) {
          await s.cancel();
        }
      }

      timings.sort();
      results['fanout_10_streams_us'] = timings[timings.length ~/ 2];
    }

    await db.close();
  } finally {
    await tempDir.delete(recursive: true);
  }

  print(jsonEncode(results));
  exit(0);
}
