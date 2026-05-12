// ignore_for_file: avoid_print
//
// Long-text cell-size scaling audit — exp 137.
//
// Exp 099 added an 8-byte FNV main loop and exp 110 wired in the
// matching long-text unchanged-fanout benchmark (8 unchanged streams
// x 256 rows x 4KB ASCII TEXT cells). The 4KB cell shape produced the
// -76% headline that justified accepting exp 099's revival.
//
// `signals.json#long-text-stream-hashing` carries the next gate as a
// `blockedOnMeasurement` entry plus a 2026-04-29 open candidate:
//
//   "broader long-payload workload (>= 32KB TEXT cells, mixed
//    BLOB/TEXT)"
//
// Without that workload we cannot tell whether the per-byte hashing
// cost continues to drive wall as cell sizes grow, or whether some
// other cost (SQLite text fetch, page cache, GC, isolate transfer)
// takes over. Either outcome closes the open candidate:
//
//   - linear scaling (per-byte wall stable across sizes) -> hashing
//     dominates; further hash-loop variants remain interesting and a
//     wider FNV unroll / SIMD probe is the natural next attempt.
//   - sub-linear scaling (per-byte wall drops at large sizes) -> some
//     non-hash floor dominates short-cell wall; long-text hashing is
//     not the next implementation target.
//   - super-linear scaling (per-byte wall climbs at large sizes) ->
//     allocation, GC, or isolate-transfer cost emerges; new direction.
//
// The harness mirrors exp 110's shape (8 unchanged streams x 256 rows,
// single barrier stream, INSERT per iteration) and just sweeps the
// per-cell byte size. Each size runs `iterationsPerSize` insert
// iterations, the wall is the per-iteration `Stopwatch` around the
// INSERT + barrier-emission wait, and the report is the median /
// p90 / p99 / per-byte wall at each size.
//
// Usage:
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/long_text_scaling_audit.dart --markdown

import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;
import 'package:resqlite/src/profile_mode.dart';

const int unchangedStreamCount = 8;
const int rowCount = 256;
const int iterationsPerSize = 30;
const int warmupIterations = 3;
const List<int> cellSizesBytes = [4096, 16384, 32768, 65536, 131072];

class _ScalingResult {
  _ScalingResult({
    required this.cellBytes,
    required this.medianUs,
    required this.p90Us,
    required this.p99Us,
    required this.minUs,
    required this.maxUs,
  });

  final int cellBytes;
  final int medianUs;
  final int p90Us;
  final int p99Us;
  final int minUs;
  final int maxUs;

  // Per-byte wall is a stand-in for "would 2x the bytes give 2x the
  // wall?". The fanout wave hashes:
  //   - every unchanged stream's full result (`rowCount` rows), times
  //     `unchangedStreamCount` streams,
  //   - plus the barrier stream's single fixed row (its body changes
  //     each iteration so the barrier emits, but the result-set size
  //     stays at exactly one row — the unchanged streams remain the
  //     dominant hashed-payload source).
  // SQLite TEXT cells stored on the same row as INTEGER columns return
  // the full payload pointer for hashing, so per-row hashed bytes are
  // approximately `cellBytes` (id/marker integer columns add a few
  // bytes of fold work each — kept in the formula as cellBytes only
  // because the integer-column contribution is negligible at >=4KB).
  double get totalHashedBytes =>
      cellBytes.toDouble() * (unchangedStreamCount * rowCount + 1);
  double get nsPerByte => (medianUs * 1000.0) / totalHashedBytes;
}

// Fixed primary key for the barrier row. Sits well outside every
// unchanged stream's `id < rowCount` predicate so the unchanged
// streams never observe a column change from the barrier UPDATE,
// while the barrier stream's `id = $barrierRowId` predicate keeps
// the result set at exactly one row across every iteration. This
// matters for `ns_per_byte`: an INSERT-driven barrier would grow
// the barrier's hashed payload by one row per iteration, drifting
// the per-iteration hashed-bytes denominator by ~1.3% over 30
// timed iterations and biasing later iterations heavier.
const int barrierRowId = 999999;

Future<_ScalingResult> runOneSize(int cellBytes) async {
  final tempDir = await Directory.systemTemp.createTemp(
    'long_text_scaling_${cellBytes}_',
  );
  try {
    final db = await resqlite.Database.open('${tempDir.path}/r.db');
    try {
      const createSql =
          'CREATE TABLE long_items('
          'id INTEGER PRIMARY KEY, '
          'body TEXT NOT NULL, '
          'marker INTEGER NOT NULL)';
      const insertSql =
          'INSERT INTO long_items(id, body, marker) VALUES (?, ?, ?)';
      const updateBarrierSql =
          'UPDATE long_items SET body = ? WHERE id = ?';

      await db.execute(createSql);
      await db.executeBatch(insertSql, [
        for (var i = 0; i < rowCount; i++)
          [i, _longTextPayload(cellBytes, i), i],
      ]);
      // Seed the fixed barrier row outside every unchanged stream's
      // predicate. Subsequent iterations UPDATE this row to trigger
      // the barrier emission without growing any result set.
      await db.execute(insertSql, [
        barrierRowId,
        _longTextPayload(cellBytes, barrierRowId),
        0,
      ]);

      final unchangedSubs = <StreamSubscription<List<Map<String, Object?>>>>[];
      StreamSubscription<List<Map<String, Object?>>>? barrierSub;

      try {
        final unchangedEmissions = List<int>.filled(unchangedStreamCount, 0);
        final unchangedReady = <Completer<void>>[
          for (var i = 0; i < unchangedStreamCount; i++) Completer<void>(),
        ];

        for (var s = 0; s < unchangedStreamCount; s++) {
          final idx = s;
          unchangedSubs.add(
            db
                .stream(
                  'SELECT id, body, $s as sid FROM long_items '
                  'WHERE id < $rowCount ORDER BY id',
                )
                .listen((_) {
                  unchangedEmissions[idx]++;
                  if (!unchangedReady[idx].isCompleted) {
                    unchangedReady[idx].complete();
                  }
                }),
          );
        }

        final barrierStream = db.stream(
          'SELECT id, body FROM long_items WHERE id = ?',
          [barrierRowId],
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
        ).timeout(const Duration(seconds: 30));
        await barrierReady.future.timeout(const Duration(seconds: 30));

        var counter = 100000;
        final wallUs = <int>[];

        // Warmups stabilize cache state and Dart JIT/AOT hot paths so the
        // first measured iteration is not an outlier. Discarded from the
        // result.
        for (var w = 0; w < warmupIterations; w++) {
          waitBarrier = Completer<void>();
          await db.execute(updateBarrierSql, [
            _longTextPayload(cellBytes, counter),
            barrierRowId,
          ]);
          counter++;
          await waitBarrier.future.timeout(const Duration(seconds: 30));
        }

        for (var i = 0; i < iterationsPerSize; i++) {
          waitBarrier = Completer<void>();
          final before = List<int>.from(unchangedEmissions);

          final sw = Stopwatch()..start();
          await db.execute(updateBarrierSql, [
            _longTextPayload(cellBytes, counter),
            barrierRowId,
          ]);
          counter++;
          await waitBarrier.future.timeout(const Duration(seconds: 30));
          sw.stop();
          wallUs.add(sw.elapsedMicroseconds);

          for (var s = 0; s < unchangedStreamCount; s++) {
            if (unchangedEmissions[s] != before[s]) {
              throw StateError(
                'Long-text unchanged stream $s emitted at cell size '
                '$cellBytes; the unchanged-fanout invariant has been '
                'broken (the hash-only fast path is supposed to suppress '
                'this stream).',
              );
            }
          }
        }

        final sorted = [...wallUs]..sort();
        return _ScalingResult(
          cellBytes: cellBytes,
          medianUs: sorted[sorted.length ~/ 2],
          p90Us:
              sorted[(sorted.length * 0.9).floor().clamp(0, sorted.length - 1)],
          p99Us: sorted[(sorted.length * 0.99).floor().clamp(0, sorted.length - 1)],
          minUs: sorted.first,
          maxUs: sorted.last,
        );
      } finally {
        await barrierSub?.cancel();
        for (final sub in unchangedSubs) {
          await sub.cancel();
        }
      }
    } finally {
      await db.close();
    }
  } finally {
    await tempDir.delete(recursive: true);
  }
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

Future<void> main(List<String> args) async {
  if (!kProfileMode) {
    stderr.writeln(
      'WARNING: kProfileMode=false; profile-only counters from other '
      'audits will stay zero. Wall measurements still work — the '
      'scaling decision in this audit is end-to-end wall, not '
      'counter-derived.',
    );
  }

  final writeMarkdown = args.contains('--markdown');

  final results = <_ScalingResult>[];
  for (final size in cellSizesBytes) {
    stderr.writeln(
      'Running cell size ${(size / 1024).toStringAsFixed(0)}KB '
      '($iterationsPerSize iterations)...',
    );
    results.add(await runOneSize(size));
  }

  final markdown = _renderMarkdown(results);
  print(markdown);

  if (writeMarkdown) {
    final outFile = File(
      'benchmark/profile/results/exp-137-long-text-scaling-aggregate.md',
    );
    await outFile.writeAsString(markdown);
    print('Wrote ${outFile.path}');
  }
}

String _renderMarkdown(List<_ScalingResult> results) {
  final buf = StringBuffer();
  buf.writeln('# Experiment 137 - Long-Text Cell-Size Scaling Audit');
  buf.writeln();
  buf.writeln(
    'Profile-mode harness: '
    '`benchmark/profile/long_text_scaling_audit.dart`',
  );
  buf.writeln();
  buf.writeln(
    'Workload shape: $unchangedStreamCount unchanged streams x $rowCount '
    'rows, one fixed-row barrier stream (id = $barrierRowId, outside '
    'every unchanged stream\'s `id < $rowCount` predicate), '
    '$iterationsPerSize timed UPDATE iterations against the barrier '
    'row per cell size after $warmupIterations warmups.',
  );
  buf.writeln();
  buf.writeln(
    'Wall convention: per-iteration `Stopwatch` brackets the UPDATE '
    'plus the wait for the barrier stream to re-emit. The unchanged '
    'streams must not emit (their hash-only fast path is supposed to '
    'suppress re-delivery); the harness asserts this on every '
    'iteration. Using UPDATE against a fixed barrier row keeps every '
    'result set at constant size across iterations, so per-iteration '
    'hashed-byte work is constant and the median is not biased toward '
    'later (heavier) iterations.',
  );
  buf.writeln();
  buf.writeln('Command:');
  buf.writeln();
  buf.writeln('```text');
  buf.writeln(
    'dart run -DRESQLITE_PROFILE=true '
    'benchmark/profile/long_text_scaling_audit.dart --markdown',
  );
  buf.writeln('```');
  buf.writeln();
  buf.writeln('## Wall by cell size');
  buf.writeln();
  buf.writeln(
    '| cell size | median_ms | p90_ms | p99_ms | min_ms | max_ms |',
  );
  buf.writeln(
    '|---|---:|---:|---:|---:|---:|',
  );
  for (final row in results) {
    buf.writeln(
      '| ${_formatCellSize(row.cellBytes)} | '
      '${(row.medianUs / 1000).toStringAsFixed(2)} | '
      '${(row.p90Us / 1000).toStringAsFixed(2)} | '
      '${(row.p99Us / 1000).toStringAsFixed(2)} | '
      '${(row.minUs / 1000).toStringAsFixed(2)} | '
      '${(row.maxUs / 1000).toStringAsFixed(2)} |',
    );
  }
  buf.writeln();
  buf.writeln('## Per-byte cost');
  buf.writeln();
  buf.writeln(
    'The fanout wave hashes every unchanged stream\'s full result '
    '($rowCount rows x $unchangedStreamCount unchanged streams) plus '
    'the barrier stream\'s single fixed row. '
    '`hashed_bytes_per_iter = cell_bytes x '
    '(${unchangedStreamCount * rowCount} + 1)`. `ns_per_byte` '
    'divides the median wall by the total hashed bytes to isolate '
    'the per-byte cost from the per-iteration overhead.',
  );
  buf.writeln();
  buf.writeln(
    '| cell size | hashed_bytes_per_iter | ns_per_byte (median) |',
  );
  buf.writeln('|---|---:|---:|');
  for (final row in results) {
    buf.writeln(
      '| ${_formatCellSize(row.cellBytes)} | '
      '${row.totalHashedBytes.toStringAsFixed(0)} | '
      '${row.nsPerByte.toStringAsFixed(3)} |',
    );
  }
  buf.writeln();
  buf.writeln('## Reading the table');
  buf.writeln();
  buf.writeln(
    '- `median_ms` is the per-iteration wall: one UPDATE against the '
    'fixed barrier row plus the fanout wave that re-hashes every '
    'unchanged stream\'s result.',
  );
  buf.writeln(
    '- `ns_per_byte` is the per-byte cost averaged across the full '
    'hashed payload. If hashing is the bottleneck, this number stays '
    'roughly flat across cell sizes.',
  );
  buf.writeln(
    '- Drift downward as cell sizes grow points to a per-iteration '
    'overhead floor (mutex acquisition, microtask scheduling, '
    'isolate dispatch) hiding the per-byte cost at small sizes.',
  );
  buf.writeln(
    '- Drift upward at large sizes points to a non-hash cost emerging '
    '— allocation, GC pressure, page cache misses, or SQLite text '
    'fetch stalling on disk.',
  );
  buf.writeln();
  buf.writeln('## Interpretation');
  buf.writeln();
  buf.writeln(
    'See `experiments/137-long-text-cell-scaling.md` for the decision '
    'and follow-up notes attached to these numbers.',
  );
  return buf.toString();
}

String _formatCellSize(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
}
