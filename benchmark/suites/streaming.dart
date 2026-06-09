// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
    final resqliteDb = await resqlite.Database.open(
      '${tempDir.path}/resqlite.db',
    );
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
    final seedParams = [
      for (var i = 0; i < 100; i++) ['item_$i', i],
    ];

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
            .watch('SELECT * FROM items ORDER BY id', throttle: Duration.zero)
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
            .watch('SELECT * FROM items ORDER BY id', throttle: Duration.zero)
            .first;
        sw.stop();
        asyncTiming.wallUs.add(sw.elapsedMicroseconds);
        asyncTiming.mainUs.add(sw.elapsedMicroseconds);
      }

      markdown.write(
        markdownTable('Initial Emission', [sqTiming, asyncTiming]),
      );
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

      markdown.write(
        markdownTable('Invalidation Latency', [sqTiming, asyncTiming]),
      );
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
                if (!unchangedReady[s].isCompleted)
                  unchangedReady[s].complete();
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
                'Unchanged stream $s emitted for an unchanged result!',
              );
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
                if (!unchangedReady[s].isCompleted)
                  unchangedReady[s].complete();
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

      markdown.write(
        markdownTable(
          'Unchanged Fanout Throughput (1 canary + 10 unchanged streams)',
          [sqTiming, asyncTiming],
        ),
      );
    }

    // -----------------------------------------------------------------
    // 2c. Long-text unchanged fanout — experiment 099/110 target
    //
    // The standard unchanged-fanout workload uses short TEXT cells, so
    // `resqlite_query_hash` never spends meaningful time in its byte-stream
    // fold loop. This focused workload keeps the result unchanged for
    // several long-text streams and uses one changed long-text barrier
    // stream to wait until the fanout wave has actually drained.
    // -----------------------------------------------------------------
    {
      const unchangedStreamCount = 8;
      const rowCount = 256;
      const textBytes = 4096;
      var counter = 100000;

      final tmp = await Directory.systemTemp.createTemp(
        'bench_long_text_stream_',
      );
      try {
        final db = await resqlite.Database.open('${tmp.path}/r.db');
        const createLongSql =
            'CREATE TABLE long_items('
            'id INTEGER PRIMARY KEY, '
            'body TEXT NOT NULL, '
            'marker INTEGER NOT NULL)';
        const insertLongSql =
            'INSERT INTO long_items(id, body, marker) VALUES (?, ?, ?)';

        await db.execute(createLongSql);
        await db.executeBatch(insertLongSql, [
          for (var i = 0; i < rowCount; i++)
            [i, _longTextPayload(textBytes, i), i],
        ]);

        final timing = BenchmarkTiming('resqlite');
        final unchangedSubs = <StreamSubscription>[];
        StreamSubscription? barrierSub;
        try {
          final unchangedEmissions = List<int>.filled(unchangedStreamCount, 0);
          final unchangedReady = <Completer<void>>[
            for (var i = 0; i < unchangedStreamCount; i++) Completer<void>(),
          ];

          for (var s = 0; s < unchangedStreamCount; s++) {
            final sub = db
                .stream(
                  'SELECT id, body, $s as sid FROM long_items '
                  'WHERE id < $rowCount ORDER BY id',
                )
                .listen((_) {
                  unchangedEmissions[s]++;
                  if (!unchangedReady[s].isCompleted)
                    unchangedReady[s].complete();
                });
            unchangedSubs.add(sub);
          }

          // Registered after the unchanged streams. It changes on each insert
          // and serves as a practical barrier for the preceding hash-only
          // re-query wave.
          final barrierStream = db.stream(
            'SELECT id, body FROM long_items ORDER BY id',
          );
          final barrierReady = Completer<void>();
          Completer<void>? waitBarrier;
          barrierSub = barrierStream.listen((_) {
            if (!barrierReady.isCompleted) {
              barrierReady.complete();
            } else if (waitBarrier != null && !waitBarrier.isCompleted) {
              waitBarrier.complete();
            }
          });

          await Future.wait(
            unchangedReady.map((c) => c.future),
          ).timeout(const Duration(seconds: 10));
          await barrierReady.future.timeout(const Duration(seconds: 10));

          for (var i = 0; i < defaultIterations; i++) {
            waitBarrier = Completer<void>();
            final before = List<int>.from(unchangedEmissions);

            final sw = Stopwatch()..start();
            await db.execute(insertLongSql, [
              counter,
              _longTextPayload(textBytes, counter),
              i,
            ]);
            counter++;
            await waitBarrier.future.timeout(const Duration(seconds: 10));
            sw.stop();
            timing.wallUs.add(sw.elapsedMicroseconds);
            timing.mainUs.add(sw.elapsedMicroseconds);

            for (var s = 0; s < unchangedStreamCount; s++) {
              if (unchangedEmissions[s] != before[s]) {
                throw StateError(
                  'Long-text unchanged stream $s emitted for an unchanged result.',
                );
              }
            }
          }
        } finally {
          await barrierSub?.cancel();
          for (final sub in unchangedSubs) {
            await sub.cancel();
          }
          await db.close();
        }

        markdown.write(
          markdownTable(
            'Long-Text Unchanged Fanout '
            '(8 unchanged streams, 256 rows x 4KB TEXT)',
            [timing],
          ),
        );
      } finally {
        await tmp.delete(recursive: true);
      }
    }

    // -----------------------------------------------------------------
    // 2d. Large-payload unchanged fanout — experiment 154 target
    //
    // Exp 110 promoted a 4KB TEXT stream hash workload. This one keeps the
    // same unchanged-fanout shape but pushes the byte-stream path harder:
    // each unchanged row carries both 32KB TEXT and 32KB BLOB payloads.
    // A tiny COUNT(*) stream is registered after the unchanged streams as
    // the barrier, so the timed path stays focused on hash-only unchanged
    // re-queries rather than changed-result payload decode.
    // -----------------------------------------------------------------
    {
      const unchangedStreamCount = 4;
      const rowCount = 64;
      const payloadBytes = 32768;
      var counter = 100000;

      final tmp = await Directory.systemTemp.createTemp(
        'bench_large_payload_stream_',
      );
      try {
        final db = await resqlite.Database.open('${tmp.path}/r.db');
        const createPayloadSql =
            'CREATE TABLE payload_items('
            'id INTEGER PRIMARY KEY, '
            'body TEXT NOT NULL, '
            'payload BLOB NOT NULL, '
            'marker INTEGER NOT NULL)';
        const insertPayloadSql =
            'INSERT INTO payload_items(id, body, payload, marker) '
            'VALUES (?, ?, ?, ?)';

        await db.execute(createPayloadSql);
        await db.executeBatch(insertPayloadSql, [
          for (var i = 0; i < rowCount; i++)
            [
              i,
              _longTextPayload(payloadBytes, i),
              _longBlobPayload(payloadBytes, i),
              i,
            ],
        ]);

        final timing = BenchmarkTiming('resqlite');
        final unchangedSubs = <StreamSubscription>[];
        StreamSubscription? barrierSub;
        try {
          final unchangedEmissions = List<int>.filled(unchangedStreamCount, 0);
          final unchangedReady = <Completer<void>>[
            for (var i = 0; i < unchangedStreamCount; i++) Completer<void>(),
          ];

          for (var s = 0; s < unchangedStreamCount; s++) {
            final sub = db
                .stream(
                  'SELECT id, body, payload, $s as sid FROM payload_items '
                  'WHERE id < $rowCount ORDER BY id',
                )
                .listen((_) {
                  unchangedEmissions[s]++;
                  if (!unchangedReady[s].isCompleted) {
                    unchangedReady[s].complete();
                  }
                });
            unchangedSubs.add(sub);
          }

          final barrierStream = db.stream(
            'SELECT COUNT(*) as cnt FROM payload_items',
          );
          final barrierReady = Completer<void>();
          Completer<void>? waitBarrier;
          barrierSub = barrierStream.listen((_) {
            if (!barrierReady.isCompleted) {
              barrierReady.complete();
            } else if (waitBarrier != null && !waitBarrier.isCompleted) {
              waitBarrier.complete();
            }
          });

          await Future.wait(
            unchangedReady.map((c) => c.future),
          ).timeout(const Duration(seconds: 10));
          await barrierReady.future.timeout(const Duration(seconds: 10));

          for (var i = 0; i < defaultIterations; i++) {
            waitBarrier = Completer<void>();
            final before = List<int>.from(unchangedEmissions);

            final sw = Stopwatch()..start();
            await db.execute(insertPayloadSql, [
              counter,
              _longTextPayload(payloadBytes, counter),
              _longBlobPayload(payloadBytes, counter),
              i,
            ]);
            counter++;
            await waitBarrier.future.timeout(const Duration(seconds: 10));
            sw.stop();
            timing.wallUs.add(sw.elapsedMicroseconds);
            timing.mainUs.add(sw.elapsedMicroseconds);

            for (var s = 0; s < unchangedStreamCount; s++) {
              if (unchangedEmissions[s] != before[s]) {
                throw StateError(
                  'Large-payload unchanged stream $s emitted for an unchanged result.',
                );
              }
            }
          }
        } finally {
          await barrierSub?.cancel();
          for (final sub in unchangedSubs) {
            await sub.cancel();
          }
          await db.close();
        }

        markdown.write(
          markdownTable(
            'Large-Payload Unchanged Fanout '
            '(4 unchanged streams, 64 rows x 32KB TEXT + 32KB BLOB)',
            [timing],
          ),
        );
      } finally {
        await tmp.delete(recursive: true);
      }
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
          subs.add(
            stream.listen((_) {
              emitCount++;
              if (emitCount == 1 && !initialC.isCompleted) initialC.complete();
              if (emitCount >= 2 && !reEmitC.isCompleted) reEmitC.complete();
            }),
          );
        }

        await Future.wait(
          initialCompleters.map((c) => c.future),
        ).timeout(const Duration(seconds: 5));

        final sw = Stopwatch()..start();
        await resqliteDb.execute(seedSql, ['fan_${counter++}', iter]);
        await Future.wait(
          reEmitCompleters.map((c) => c.future),
        ).timeout(const Duration(seconds: 5));
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
          subs.add(
            stream.listen((_) {
              emitCount++;
              if (emitCount == 1 && !initialC.isCompleted) initialC.complete();
              if (emitCount >= 2 && !reEmitC.isCompleted) reEmitC.complete();
            }),
          );
        }

        await Future.wait(
          initialCompleters.map((c) => c.future),
        ).timeout(const Duration(seconds: 5));

        final sw = Stopwatch()..start();
        await asyncDb.execute(seedSql, ['fan_${counter++}', iter]);
        await Future.wait(
          reEmitCompleters.map((c) => c.future),
        ).timeout(const Duration(seconds: 5));
        sw.stop();
        asyncTiming.wallUs.add(sw.elapsedMicroseconds);
        asyncTiming.mainUs.add(sw.elapsedMicroseconds);

        for (final s in subs) {
          await s.cancel();
        }
      }

      markdown.write(
        markdownTable('Fan-out (10 streams)', [sqTiming, asyncTiming]),
      );
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
              .watch(
                'SELECT COUNT(*) as cnt FROM items',
                throttle: Duration.zero,
              )
              .first;
        }
        sw.stop();
        asyncTiming.wallUs.add(sw.elapsedMicroseconds);
        asyncTiming.mainUs.add(sw.elapsedMicroseconds);
      }

      markdown.write(
        markdownTable('Stream Churn (100 cycles)', [sqTiming, asyncTiming]),
      );
      markdown.writeln('');
    }

    // -----------------------------------------------------------------
    // 5. No-Streams Write Throughput — experiment 077 target
    //
    // 200 sequential INSERTs while no stream has ever subscribed. The
    // stream engine's `_tableToKeys` is empty for the whole run, so
    // every handleDirtyTables call is pure overhead — allocating
    // `_pendingDirtyTables`, scheduling a microtask, running _flushDirty-
    // Tables to look up zero affected streams, returning.
    //
    // exp 077 adds `if (_tableToKeys.isEmpty) return;` after the write-
    // generation bump, eliminating the Set allocation + microtask when
    // nothing could possibly care. Win appears as reduced main-isolate
    // time on a tight write loop with no streams.
    // -----------------------------------------------------------------
    {
      final tmp = await Directory.systemTemp.createTemp('bench_nostream_');
      try {
        final db = await resqlite.Database.open('${tmp.path}/r.db');
        await db.execute(createSql);
        await db.execute(seedSql, ['seed', 0]);

        const writes = 200;
        // Warmup.
        for (var i = 0; i < 20; i++) {
          await db.execute(seedSql, ['warm_$i', i]);
        }

        final timing = BenchmarkTiming('resqlite');
        for (var iter = 0; iter < defaultIterations; iter++) {
          final sw = Stopwatch()..start();
          for (var i = 0; i < writes; i++) {
            await db.execute(seedSql, ['nostream_${iter}_$i', i]);
          }
          sw.stop();
          timing.wallUs.add(sw.elapsedMicroseconds);
          timing.mainUs.add(sw.elapsedMicroseconds);
        }

        await db.close();

        // sqlite_async comparison (no reactive engine to worry about).
        final async = sqlite_async.SqliteDatabase(path: '${tmp.path}/a.db');
        await async.initialize();
        await async.execute(createSql);
        await async.execute(seedSql, ['seed', 0]);
        for (var i = 0; i < 20; i++) {
          await async.execute(seedSql, ['warm_$i', i]);
        }
        final asyncTiming = BenchmarkTiming('sqlite_async');
        for (var iter = 0; iter < defaultIterations; iter++) {
          final sw = Stopwatch()..start();
          for (var i = 0; i < writes; i++) {
            await async.execute(seedSql, ['nostream_${iter}_$i', i]);
          }
          sw.stop();
          asyncTiming.wallUs.add(sw.elapsedMicroseconds);
          asyncTiming.mainUs.add(sw.elapsedMicroseconds);
        }
        await async.close();

        markdown.write(
          markdownTable(
            'No-Streams Write Throughput (200 inserts, no active streams)',
            [timing, asyncTiming],
          ),
        );
        markdown.writeln('');
      } finally {
        await tmp.delete(recursive: true);
      }
    }

    // -----------------------------------------------------------------
    // 6. Growing-Stream Invalidation — experiment 077 target
    //
    // Stream watches `SELECT id, name, value FROM items ORDER BY id`
    // (all rows, full-result emission). Each iteration INSERTs 100 new
    // rows in a batch. The stream re-queries after each batch.
    //
    // Baseline: `resqlite_query_hash` walks all current rows hashing
    // every cell byte, then comparison fails (hash changed), decode
    // pass runs. Work scales with current_row_count × col_count.
    //
    // exp 077: row-count short-circuit fires as soon as the stream
    // passes the previous row count (N + 1). Remaining rows are
    // counted but not hashed. For a +100-row insert on a 1000-row
    // stream, ~100 × 4 cells × ~250 ns = 100 μs saved per re-query.
    // -----------------------------------------------------------------
    {
      final tmp = await Directory.systemTemp.createTemp('bench_grow_');
      try {
        final db = await resqlite.Database.open('${tmp.path}/r.db');
        await db.execute(createSql);
        // Seed 500 rows so we start with a non-trivial baseline.
        await db.executeBatch(seedSql, [
          for (var i = 0; i < 500; i++) ['seed_$i', i],
        ]);

        final stream = db.stream(
          'SELECT id, name, value FROM items ORDER BY id',
        );
        Completer<void>? waitNext;
        final initial = Completer<void>();
        final sub = stream.listen((_) {
          if (!initial.isCompleted) {
            initial.complete();
          } else {
            final w = waitNext;
            if (w != null && !w.isCompleted) w.complete();
          }
        });
        await initial.future.timeout(const Duration(seconds: 5));

        const batch = 100;
        var counter = 100000;

        // Warmup.
        for (var w = 0; w < 3; w++) {
          final next = Completer<void>();
          waitNext = next;
          await db.executeBatch(seedSql, [
            for (var i = 0; i < batch; i++) ['warm_${counter++}', i],
          ]);
          await next.future.timeout(const Duration(seconds: 5));
        }

        final timing = BenchmarkTiming('resqlite');
        for (var iter = 0; iter < defaultIterations; iter++) {
          final next = Completer<void>();
          waitNext = next;
          final sw = Stopwatch()..start();
          await db.executeBatch(seedSql, [
            for (var i = 0; i < batch; i++) ['grow_${counter++}', i],
          ]);
          await next.future.timeout(const Duration(seconds: 5));
          sw.stop();
          timing.wallUs.add(sw.elapsedMicroseconds);
          timing.mainUs.add(sw.elapsedMicroseconds);
        }

        await sub.cancel();
        await db.close();

        markdown.write(
          markdownTable(
            'Growing-Stream Invalidation (batch-insert 100 into watched stream)',
            [timing],
          ),
        );
        markdown.writeln('');
      } finally {
        await tmp.delete(recursive: true);
      }
    }

    // -----------------------------------------------------------------
    // 7. Stream Subscription Rate — experiment 077 target
    //
    // 500 subscribe+cancel cycles in a tight loop. Each subscribe
    // triggers an initial query → read-tables retrieval via
    // `getReadTables`. Baseline: allocates + frees a 64-slot Utf8*
    // buffer per call (a ~512 B calloc/free). exp 077: reuses a
    // persistent buffer; zero-table short-circuits to `const <String>[]`.
    //
    // Win is small per cycle (~100-500 ns) but amplified by the cycle
    // count. 500 cycles × ~300 ns ≈ 150 μs saved — measurable on a
    // ~10 ms benchmark.
    // -----------------------------------------------------------------
    {
      final tmp = await Directory.systemTemp.createTemp('bench_subrate_');
      try {
        final db = await resqlite.Database.open('${tmp.path}/r.db');
        await db.execute(createSql);
        await db.execute(seedSql, ['seed', 0]);

        const cycles = 500;

        // Warmup.
        for (var i = 0; i < 10; i++) {
          await db.stream('SELECT COUNT(*) as cnt FROM items').first;
        }

        final timing = BenchmarkTiming('resqlite');
        for (var iter = 0; iter < defaultIterations; iter++) {
          final sw = Stopwatch()..start();
          for (var i = 0; i < cycles; i++) {
            await db.stream('SELECT COUNT(*) as cnt FROM items').first;
          }
          sw.stop();
          timing.wallUs.add(sw.elapsedMicroseconds);
          timing.mainUs.add(sw.elapsedMicroseconds);
        }

        await db.close();

        markdown.write(
          markdownTable(
            'Stream Subscription Rate (500 subscribe+cancel cycles)',
            [timing],
          ),
        );
        markdown.writeln('');
      } finally {
        await tmp.delete(recursive: true);
      }
    }

    await resqliteDb.close();
    await asyncDb.close();
  } finally {
    await tempDir.delete(recursive: true);
  }

  return markdown.toString();
}

String _longTextPayload(int targetBytes, int seed) {
  final prefix = 'seed_$seed:';
  const chunk = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final buffer = StringBuffer(prefix);
  while (buffer.length < targetBytes) {
    buffer.write(chunk);
  }
  return buffer.toString().substring(0, targetBytes);
}

Uint8List _longBlobPayload(int targetBytes, int seed) {
  final bytes = Uint8List(targetBytes);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = (seed * 31 + i) & 0xFF;
  }
  return bytes;
}
