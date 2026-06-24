// Focused A/B harness for exp 192 — two-digit table itoa for selectBytes
// integer columns.
//
// The selectBytes JSON encoder calls fast_i64_to_str once per integer cell.
// Exp 023 introduced a single-digit loop (one `% 10` / `/ 10` per output digit)
// that replaced snprintf. Exp 192 replaces it with a two-digit table lookup
// (one `% 100` / `/ 100` and one 2-byte memcpy per pair of digits), halving
// the division count.
//
// Lanes target integer-heavy selectBytes payloads where this path dominates:
//   - 10k rows x 8 INTEGER columns  (small-but-many ints, like row ids)
//   - 10k rows x 20 INTEGER columns (wider rows, deeper i64 magnitudes)
//   - 10k rows x 20 BIGINT columns  (~18-digit magnitudes — worst case for
//                                    the digit loop)
// A 10k rows x 8 mixed (int+text+real) lane and a 1k rows x 2 INTEGER
// lane act as regression guards: integer encoding is one component, not the
// whole row, and small payloads should stay within sub-millisecond noise.
//
// Run on a quiet machine; two order-flipped passes recommended.
//   dart run benchmark/experiments/select_bytes_int_heavy.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:resqlite/resqlite.dart';

Future<int> _medianUs(
  Database db,
  String sql,
  int iters,
  int rounds,
) async {
  final samples = <int>[];
  for (var r = 0; r < rounds; r++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < iters; i++) {
      final b = (await db.selectBytes(sql)).bytes;
      if (b.isEmpty) throw StateError('empty result');
    }
    sw.stop();
    samples.add(sw.elapsedMicroseconds ~/ iters);
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}

Future<void> _lane({
  required String label,
  required int rows,
  required int intCols,
  bool bigMagnitude = false,
  int textCols = 0,
  int realCols = 0,
  required int iters,
}) async {
  final dir = await Directory.systemTemp.createTemp('resq_int_json_');
  final db = await Database.open('${dir.path}/t.db');
  try {
    final intDefs = [for (var i = 0; i < intCols; i++) 'i$i INTEGER'];
    final textDefs = [for (var i = 0; i < textCols; i++) 't$i TEXT'];
    final realDefs = [for (var i = 0; i < realCols; i++) 'r$i REAL'];
    final defs = ['id INTEGER PRIMARY KEY', ...intDefs, ...textDefs, ...realDefs];
    await db.execute('CREATE TABLE t(${defs.join(', ')})');

    final intNames = [for (var i = 0; i < intCols; i++) 'i$i'];
    final textNames = [for (var i = 0; i < textCols; i++) 't$i'];
    final realNames = [for (var i = 0; i < realCols; i++) 'r$i'];
    final cols = ['id', ...intNames, ...textNames, ...realNames];
    final placeholders = List.filled(cols.length, '?').join(', ');
    final sql =
        'INSERT INTO t(${cols.join(', ')}) VALUES ($placeholders)';

    final rng = math.Random(7);
    final batch = <List<Object?>>[];
    for (var r = 0; r < rows; r++) {
      final row = <Object?>[r];
      for (var c = 0; c < intCols; c++) {
        if (bigMagnitude) {
          // 17-19 digit magnitudes — exercise the long path of the digit loop.
          final mag = (rng.nextInt(0x7fffffff) << 31) | rng.nextInt(0x7fffffff);
          row.add(rng.nextBool() ? -mag : mag);
        } else {
          // Small-to-medium magnitudes (1-9 digits) — typical row ids.
          row.add(rng.nextInt(1 << 30) - (1 << 29));
        }
      }
      for (var c = 0; c < textCols; c++) {
        row.add('text_${r}_$c');
      }
      for (var c = 0; c < realCols; c++) {
        row.add(rng.nextDouble() * 1000);
      }
      batch.add(row);
    }
    await db.executeBatch(sql, batch);

    final selectSql = 'SELECT ${cols.join(', ')} FROM t ORDER BY id';
    final probe = (await db.selectBytes(selectSql)).bytes;
    // warm up
    for (var i = 0; i < (iters ~/ 4) + 1; i++) {
      await db.selectBytes(selectSql);
    }
    final medUs = await _medianUs(db, selectSql, iters, 6);
    stdout.writeln(
      '$label: ${probe.length}B x$iters -> median ${medUs}us/query '
      '(${(medUs * iters / 1000).toStringAsFixed(1)}ms total)',
    );
  } finally {
    await db.close();
    await dir.delete(recursive: true);
  }
}

Future<void> main() async {
  stdout.writeln('=== selectBytes integer JSON encoding (exp 192) ===');

  // Primary target: many integers per row, deep digit counts.
  await _lane(
    label: '10k rows x 8 small ints',
    rows: 10000,
    intCols: 8,
    iters: 20,
  );
  await _lane(
    label: '10k rows x 20 small ints',
    rows: 10000,
    intCols: 20,
    iters: 12,
  );
  await _lane(
    label: '10k rows x 20 big ints (~18 digits)',
    rows: 10000,
    intCols: 20,
    bigMagnitude: true,
    iters: 10,
  );

  // Regression guards.
  await _lane(
    label: '10k rows x 8 mixed (4 int + 2 text + 2 real)',
    rows: 10000,
    intCols: 4,
    textCols: 2,
    realCols: 2,
    iters: 20,
  );
  await _lane(
    label: '1k rows x 2 ints',
    rows: 1000,
    intCols: 2,
    iters: 200,
  );
}
