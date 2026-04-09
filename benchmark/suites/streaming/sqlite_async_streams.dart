// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:sqlite_async/sqlite_async.dart';

/// Streaming benchmarks for sqlite_async.
/// Outputs JSON results to stdout for the runner to collect.
Future<void> main() async {
  final tempDir = await Directory.systemTemp.createTemp('bench_stream_async_');
  final results = <String, dynamic>{};

  try {
    final db = SqliteDatabase(path: '${tempDir.path}/test.db');
    await db.initialize();
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
        final stream = db.watch('SELECT * FROM items ORDER BY id');
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

      final stream = db.watch('SELECT COUNT(*) as cnt FROM items');
      final completer = Completer<void>();
      var emissions = 0;

      final sub = stream.listen((_) {
        emissions++;
        if (emissions == 1) completer.complete();
      });

      await completer.future;

      for (var i = 0; i < iterations; i++) {
        final reEmit = Completer<void>();

        sub.onData((_) {
          emissions++;
          if (!reEmit.isCompleted) {
            reEmit.complete();
          }
        });

        final sw = Stopwatch()..start();
        await db.execute(
          'INSERT INTO items(name, value) VALUES (?, ?)',
          ['bench_${counter++}', i],
        );
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

      final streams = <Stream<sqlite.ResultSet>>[];
      final subs = <StreamSubscription<sqlite.ResultSet>>[];
      final initialCompleters = <Completer<void>>[];

      for (var s = 0; s < streamCount; s++) {
        final stream = db.watch(
          'SELECT COUNT(*) as cnt FROM items WHERE value > ?',
          parameters: [s * 10],
        );
        streams.add(stream);
        final c = Completer<void>();
        initialCompleters.add(c);
        subs.add(stream.listen((_) {
          if (!c.isCompleted) c.complete();
        }));
      }

      await Future.wait(initialCompleters.map((c) => c.future))
          .timeout(const Duration(seconds: 5));

      for (var i = 0; i < iterations; i++) {
        final allUpdated = <Completer<void>>[];
        for (var s = 0; s < streamCount; s++) {
          final c = Completer<void>();
          allUpdated.add(c);
          subs[s].onData((_) {
            if (!c.isCompleted) c.complete();
          });
        }

        final sw = Stopwatch()..start();
        await db.execute(
          'INSERT INTO items(name, value) VALUES (?, ?)',
          ['fanout_${counter++}', 50],
        );
        await Future.wait(allUpdated.map((c) => c.future))
            .timeout(const Duration(seconds: 5));
        sw.stop();
        timings.add(sw.elapsedMicroseconds);
      }

      for (final sub in subs) {
        await sub.cancel();
      }

      timings.sort();
      results['fanout_${streamCount}_streams_us'] = timings[timings.length ~/ 2];
    }

    await db.close();
  } finally {
    await tempDir.delete(recursive: true);
  }

  print(jsonEncode(results));
  exit(0);
}
