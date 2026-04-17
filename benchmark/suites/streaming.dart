// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;
import 'package:sqlite_async/sqlite_async.dart' as sqlite_async;

import '../shared/config.dart';
import '../shared/stats.dart';

/// Streaming benchmarks: initial emission, invalidation latency, fan-out, churn.
Future<String> runStreamingBenchmark() async {
  final markdown = StringBuffer();
  markdown.writeln('## Streaming');
  markdown.writeln('');
  markdown.writeln(
    'Reactive query performance. resqlite uses per-subscriber buffered '
    'controllers with authorizer-based dependency tracking. sqlite_async '
    'uses a 30ms default throttle (disabled here via throttle: Duration.zero).',
  );
  markdown.writeln('');

  final tempDir = await Directory.systemTemp.createTemp('bench_stream_');
  try {
    // -----------------------------------------------------------------
    // Setup
    // -----------------------------------------------------------------
    final resqliteDb = await resqlite.Database.open('${tempDir.path}/resqlite.db');
    final asyncDb = sqlite_async.SqliteDatabase(
      path: '${tempDir.path}/async.db',
    );
    await asyncDb.initialize();

    const createSql =
        'CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT NOT NULL, value INTEGER NOT NULL)';
    const seedSql = 'INSERT INTO items(name, value) VALUES (?, ?)';
    // 100 seed rows — matches main's pre-existing benchmarks so their
    // numbers remain historically comparable. The unchanged-fanout
    // benchmark below inserts an additional 900 rows *locally* so its
    // result size is big enough for the decode-skip win to clear noise.
    final seedParams = [for (var i = 0; i < 100; i++) ['item_$i', i]];

    await resqliteDb.execute(createSql);
    await resqliteDb.executeBatch(seedSql, seedParams);
    await asyncDb.execute(createSql);
    await asyncDb.executeBatch(seedSql, seedParams);

    // -----------------------------------------------------------------
    // 1. Initial emission latency
    // -----------------------------------------------------------------
    {
      // Warmup.
      for (var i = 0; i < defaultWarmup; i++) {
        await resqliteDb.stream('SELECT * FROM items ORDER BY id').first;
        await asyncDb
            .watch('SELECT * FROM items ORDER BY id',
                throttle: Duration.zero)
            .first;
      }

      final sqTiming = BenchmarkTiming('resqlite stream()');
      for (var i = 0; i < defaultIterations; i++) {
        final sw = Stopwatch()..start();
        await resqliteDb.stream('SELECT * FROM items ORDER BY id').first;
        sw.stop();
        sqTiming.wallUs.add(sw.elapsedMicroseconds);
        sqTiming.mainUs.add(sw.elapsedMicroseconds);
      }

      final asyncTiming = BenchmarkTiming('sqlite_async watch()');
      for (var i = 0; i < defaultIterations; i++) {
        final sw = Stopwatch()..start();
        await asyncDb
            .watch('SELECT * FROM items ORDER BY id',
                throttle: Duration.zero)
            .first;
        sw.stop();
        asyncTiming.wallUs.add(sw.elapsedMicroseconds);
        asyncTiming.mainUs.add(sw.elapsedMicroseconds);
      }

      markdown.write(markdownTable('Initial Emission', [sqTiming, asyncTiming]));
    }

    // -----------------------------------------------------------------
    // 2. Invalidation latency (write → re-emission)
    // -----------------------------------------------------------------
    {

      var counter = 1000;

      // resqlite
      final sqTiming = BenchmarkTiming('resqlite');
      {
        final stream = resqliteDb.stream('SELECT COUNT(*) as cnt FROM items');
        final initialC = Completer<void>();
        final sub = stream.listen((_) {
          if (!initialC.isCompleted) initialC.complete();
        });
        await initialC.future;

        for (var i = 0; i < defaultIterations; i++) {
          final reEmit = Completer<void>();
          sub.onData((_) {
            if (!reEmit.isCompleted) reEmit.complete();
          });
          final sw = Stopwatch()..start();
          await resqliteDb.execute(seedSql, ['inv_${counter++}', i]);
          await reEmit.future.timeout(const Duration(seconds: 2));
          sw.stop();
          sqTiming.wallUs.add(sw.elapsedMicroseconds);
          sqTiming.mainUs.add(sw.elapsedMicroseconds);
        }
        await sub.cancel();
      }

      // sqlite_async
      final asyncTiming = BenchmarkTiming('sqlite_async');
      {
        final stream = asyncDb.watch(
          'SELECT COUNT(*) as cnt FROM items',
          throttle: Duration.zero,
        );
        final initialC = Completer<void>();
        final sub = stream.listen((_) {
          if (!initialC.isCompleted) initialC.complete();
        });
        await initialC.future;

        for (var i = 0; i < defaultIterations; i++) {
          final reEmit = Completer<void>();
          sub.onData((_) {
            if (!reEmit.isCompleted) reEmit.complete();
          });
          final sw = Stopwatch()..start();
          await asyncDb.execute(seedSql, ['inv_${counter++}', i]);
          await reEmit.future.timeout(const Duration(seconds: 2));
          sw.stop();
          asyncTiming.wallUs.add(sw.elapsedMicroseconds);
          asyncTiming.mainUs.add(sw.elapsedMicroseconds);
        }
        await sub.cancel();
      }

      markdown.write(markdownTable('Invalidation Latency', [sqTiming, asyncTiming]));
    }

    // -----------------------------------------------------------------
    // 2b. Unchanged-fanout throughput — experiment 075 target
    //
    // fanoutCount distinct unchanged streams + 1 canary. Each unchanged
    // stream has a unique literal sid column so the stream registry
    // doesn't dedupe them — every INSERT dispatches N+1 independent
    // re-queries through the reader pool.
    //
    // Writes INSERT rows with new ids > 1000. The canary's COUNT(*)
    // changes and emits; the unchanged streams' WHERE id <= 1000
    // result-sets are identical across iterations and should NOT emit.
    //
    // With a 3-4 reader pool and 10 unchanged streams the pool backs
    // up: every write dispatches 11 re-queries over ~3 waves. Baseline
    // decodes ~1000 rows of each unchanged stream on every wave.
    // Experiment 075 hash-onlys them in C, skipping Dart decode
    // entirely when the hash matches.
    //
    // Total wall time is dominated by the re-query fanout (writes are
    // cheap, ~30 µs; fanout is where unchanged-stream work lives). A
    // working 075 drops end-to-end latency proportionally.
    // -----------------------------------------------------------------
    {
      const fanoutCount = 10;
      // Writes that are safely outside the WHERE id <= 1000 predicate.
      var counter = 100000;

      // Top up to 1000 rows for both databases so the unchanged-stream
      // result size is big enough for 075's hash-skip win to clear
      // noise. Earlier benchmarks in this suite run against the 100-row
      // seed (pre-existing baseline) — the extra rows land after they
      // finish, so their historical numbers are unchanged.
      final topupParams = [
        for (var i = 100; i < 1000; i++) ['item_$i', i],
      ];
      await resqliteDb.executeBatch(seedSql, topupParams);
      await asyncDb.executeBatch(seedSql, topupParams);

      // resqlite
      final sqTiming = BenchmarkTiming('resqlite');
      {
        final canaryStream = resqliteDb.stream(
          'SELECT COUNT(*) as cnt FROM items',
        );
        final canaryReady = Completer<void>();
        Completer<void>? waitCanary;
        final canarySub = canaryStream.listen((_) {
          if (!canaryReady.isCompleted) {
            canaryReady.complete();
          } else if (waitCanary != null && !waitCanary.isCompleted) {
            waitCanary.complete();
          }
        });

        final unchangedSubs = <StreamSubscription>[];
        final unchangedEmissions = List<int>.filled(fanoutCount, 0);
        final unchangedReady = <Completer<void>>[
          for (var i = 0; i < fanoutCount; i++) Completer<void>(),
        ];
        for (var s = 0; s < fanoutCount; s++) {
          final sub = resqliteDb
              .stream(
            'SELECT id, name, value, $s as sid FROM items '
            'WHERE id <= 1000 ORDER BY id',
          )
              .listen((_) {
            unchangedEmissions[s]++;
            if (!unchangedReady[s].isCompleted) unchangedReady[s].complete();
          });
          unchangedSubs.add(sub);
        }

        await canaryReady.future;
        await Future.wait(unchangedReady.map((c) => c.future));

        for (var i = 0; i < defaultIterations; i++) {
          waitCanary = Completer<void>();
          final before = List<int>.from(unchangedEmissions);

          final sw = Stopwatch()..start();
          await resqliteDb.execute(seedSql, ['unread_${counter++}', i]);
          await waitCanary.future.timeout(const Duration(seconds: 2));
          sw.stop();
          sqTiming.wallUs.add(sw.elapsedMicroseconds);
          sqTiming.mainUs.add(sw.elapsedMicroseconds);

          for (var s = 0; s < fanoutCount; s++) {
            if (unchangedEmissions[s] != before[s]) {
              throw StateError(
                  'Unchanged stream $s emitted for an unchanged result!');
            }
          }
        }
        await canarySub.cancel();
        for (final sub in unchangedSubs) {
          await sub.cancel();
        }
      }

      // sqlite_async: no worker-side hash, always emits duplicates.
      final asyncTiming = BenchmarkTiming('sqlite_async');
      {
        final canaryStream = asyncDb.watch(
          'SELECT COUNT(*) as cnt FROM items',
          throttle: Duration.zero,
        );
        final canaryReady = Completer<void>();
        Completer<void>? waitCanary;
        final canarySub = canaryStream.listen((_) {
          if (!canaryReady.isCompleted) {
            canaryReady.complete();
          } else if (waitCanary != null && !waitCanary.isCompleted) {
            waitCanary.complete();
          }
        });

        final unchangedSubs = <StreamSubscription>[];
        final unchangedReady = <Completer<void>>[
          for (var i = 0; i < fanoutCount; i++) Completer<void>(),
        ];
        for (var s = 0; s < fanoutCount; s++) {
          final sub = asyncDb
              .watch(
                'SELECT id, name, value, $s as sid FROM items '
                'WHERE id <= 1000 ORDER BY id',
                throttle: Duration.zero,
              )
              .listen((_) {
            if (!unchangedReady[s].isCompleted) unchangedReady[s].complete();
          });
          unchangedSubs.add(sub);
        }

        await canaryReady.future;
        await Future.wait(unchangedReady.map((c) => c.future));

        for (var i = 0; i < defaultIterations; i++) {
          waitCanary = Completer<void>();
          final sw = Stopwatch()..start();
          await asyncDb.execute(seedSql, ['unread_${counter++}', i]);
          await waitCanary.future.timeout(const Duration(seconds: 2));
          sw.stop();
          asyncTiming.wallUs.add(sw.elapsedMicroseconds);
          asyncTiming.mainUs.add(sw.elapsedMicroseconds);
        }
        await canarySub.cancel();
        for (final sub in unchangedSubs) {
          await sub.cancel();
        }
      }

      markdown.write(markdownTable(
        'Unchanged Fanout Throughput (1 canary + 10 unchanged streams)',
        [sqTiming, asyncTiming],
      ));
    }

    // -----------------------------------------------------------------
    // 3. Fan-out (10 streams, one write invalidates all)
    // -----------------------------------------------------------------
    {

      const streamCount = 10;
      var counter = 5000;

      // resqlite
      final sqTiming = BenchmarkTiming('resqlite');
      for (var iter = 0; iter < defaultIterations; iter++) {
        final subs = <StreamSubscription>[];
        final initialCompleters = <Completer<void>>[];
        final reEmitCompleters = <Completer<void>>[];

        for (var s = 0; s < streamCount; s++) {
          final initialC = Completer<void>();
          final reEmitC = Completer<void>();
          initialCompleters.add(initialC);
          reEmitCompleters.add(reEmitC);
          var emitCount = 0;

          final stream = resqliteDb.stream(
            "SELECT COUNT(*) as cnt, '$s' as sid FROM items",
          );
          subs.add(stream.listen((_) {
            emitCount++;
            if (emitCount == 1 && !initialC.isCompleted) initialC.complete();
            if (emitCount >= 2 && !reEmitC.isCompleted) reEmitC.complete();
          }));
        }

        await Future.wait(initialCompleters.map((c) => c.future))
            .timeout(const Duration(seconds: 5));

        final sw = Stopwatch()..start();
        await resqliteDb.execute(seedSql, ['fan_${counter++}', iter]);
        await Future.wait(reEmitCompleters.map((c) => c.future))
            .timeout(const Duration(seconds: 5));
        sw.stop();
        sqTiming.wallUs.add(sw.elapsedMicroseconds);
        sqTiming.mainUs.add(sw.elapsedMicroseconds);

        for (final s in subs) {
          await s.cancel();
        }
      }

      // sqlite_async
      final asyncTiming = BenchmarkTiming('sqlite_async');
      for (var iter = 0; iter < defaultIterations; iter++) {
        final subs = <StreamSubscription>[];
        final initialCompleters = <Completer<void>>[];
        final reEmitCompleters = <Completer<void>>[];

        for (var s = 0; s < streamCount; s++) {
          final initialC = Completer<void>();
          final reEmitC = Completer<void>();
          initialCompleters.add(initialC);
          reEmitCompleters.add(reEmitC);
          var emitCount = 0;

          final stream = asyncDb.watch(
            "SELECT COUNT(*) as cnt, '$s' as sid FROM items",
            throttle: Duration.zero,
          );
          subs.add(stream.listen((_) {
            emitCount++;
            if (emitCount == 1 && !initialC.isCompleted) initialC.complete();
            if (emitCount >= 2 && !reEmitC.isCompleted) reEmitC.complete();
          }));
        }

        await Future.wait(initialCompleters.map((c) => c.future))
            .timeout(const Duration(seconds: 5));

        final sw = Stopwatch()..start();
        await asyncDb.execute(seedSql, ['fan_${counter++}', iter]);
        await Future.wait(reEmitCompleters.map((c) => c.future))
            .timeout(const Duration(seconds: 5));
        sw.stop();
        asyncTiming.wallUs.add(sw.elapsedMicroseconds);
        asyncTiming.mainUs.add(sw.elapsedMicroseconds);

        for (final s in subs) {
          await s.cancel();
        }
      }

      markdown.write(markdownTable('Fan-out (10 streams)', [sqTiming, asyncTiming]));
    }

    // -----------------------------------------------------------------
    // 4. Stream churn (subscribe/unsubscribe cycles)
    // -----------------------------------------------------------------
    {

      const cycles = 100;

      // Warmup.
      for (var i = 0; i < defaultWarmup; i++) {
        final sub = resqliteDb
            .stream('SELECT COUNT(*) as cnt FROM items')
            .listen((_) {});
        await Future.delayed(const Duration(milliseconds: 10));
        await sub.cancel();
      }

      final sqTiming = BenchmarkTiming('resqlite');
      {
        final sw = Stopwatch()..start();
        for (var i = 0; i < cycles; i++) {
          await resqliteDb.stream('SELECT COUNT(*) as cnt FROM items').first;
        }
        sw.stop();
        sqTiming.wallUs.add(sw.elapsedMicroseconds);
        sqTiming.mainUs.add(sw.elapsedMicroseconds);
      }

      final asyncTiming = BenchmarkTiming('sqlite_async');
      {
        final sw = Stopwatch()..start();
        for (var i = 0; i < cycles; i++) {
          await asyncDb
              .watch('SELECT COUNT(*) as cnt FROM items',
                  throttle: Duration.zero)
              .first;
        }
        sw.stop();
        asyncTiming.wallUs.add(sw.elapsedMicroseconds);
        asyncTiming.mainUs.add(sw.elapsedMicroseconds);
      }

      markdown.write(markdownTable('Stream Churn (100 cycles)', [sqTiming, asyncTiming]));
      markdown.writeln('');
    }

    await resqliteDb.close();
    await asyncDb.close();
  } finally {
    await tempDir.delete(recursive: true);
  }

  return markdown.toString();
}

