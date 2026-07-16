// Focused A/B harness for exp 194 — integer-valued REAL fast path for
// selectBytes JSON encoding.
//
// The SQLITE_FLOAT arm currently pays snprintf("%.17g") for every REAL cell.
// This workload separates exactly integral REAL values, which can reuse the
// int64 JSON encoder without changing spelling, from fractional REAL values
// that must stay on snprintf.
//
// Run on a quiet machine; two order-flipped passes recommended.
//   dart run benchmark/experiments/select_bytes_real_int_fastpath.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:resqlite/resqlite.dart';

Future<int> _medianUs(Database db, String sql, int iters, int rounds) async {
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
  required int integralRealCols,
  int fractionalRealCols = 0,
  int textCols = 0,
  required int iters,
}) async {
  final dir = await Directory.systemTemp.createTemp('resq_real_json_');
  final db = await Database.open('${dir.path}/t.db');
  try {
    final integralDefs = [
      for (var i = 0; i < integralRealCols; i++) 'ri$i REAL',
    ];
    final fractionalDefs = [
      for (var i = 0; i < fractionalRealCols; i++) 'rf$i REAL',
    ];
    final textDefs = [for (var i = 0; i < textCols; i++) 't$i TEXT'];
    final defs = [
      'id INTEGER PRIMARY KEY',
      ...integralDefs,
      ...fractionalDefs,
      ...textDefs,
    ];
    await db.execute('CREATE TABLE t(${defs.join(', ')})');

    final integralNames = [for (var i = 0; i < integralRealCols; i++) 'ri$i'];
    final fractionalNames = [
      for (var i = 0; i < fractionalRealCols; i++) 'rf$i',
    ];
    final textNames = [for (var i = 0; i < textCols; i++) 't$i'];
    final cols = ['id', ...integralNames, ...fractionalNames, ...textNames];
    final placeholders = List.filled(cols.length, '?').join(', ');
    final sql = 'INSERT INTO t(${cols.join(', ')}) VALUES ($placeholders)';

    final rng = math.Random(194);
    final batch = <List<Object?>>[];
    for (var r = 0; r < rows; r++) {
      final row = <Object?>[r];
      for (var c = 0; c < integralRealCols; c++) {
        final value = rng.nextInt(1 << 30) - (1 << 29);
        row.add(value.toDouble());
      }
      for (var c = 0; c < fractionalRealCols; c++) {
        row.add(rng.nextDouble() * 1000000.0 + c + 0.125);
      }
      for (var c = 0; c < textCols; c++) {
        row.add('text_${r}_$c');
      }
      batch.add(row);
    }
    await db.executeBatch(sql, batch);

    // Untimed setup contract: storage affinity or fixture drift must not
    // silently change which native formatter path either lane exercises.
    final invariantTerms = <String>[
      for (final name in integralNames)
        "typeof($name) = 'real' AND "
            'ABS($name) <= 9007199254740992.0 AND '
            'CAST($name AS INTEGER) = $name',
      for (final name in fractionalNames)
        "typeof($name) = 'real' AND CAST($name AS INTEGER) != $name",
    ];
    if (invariantTerms.isNotEmpty) {
      final violations = await db.select(
        'SELECT COUNT(*) AS n FROM t WHERE NOT '
        '(${invariantTerms.join(' AND ')})',
      );
      if (violations.single['n'] != 0) {
        throw StateError(
          'REAL benchmark fixture violated its formatter-path invariant: '
          '${violations.single['n']} rows',
        );
      }
    }

    final selectSql = 'SELECT ${cols.join(', ')} FROM t ORDER BY id';
    final probe = (await db.selectBytes(selectSql)).bytes;
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
  stdout.writeln(
    '=== selectBytes integer-valued REAL JSON encoding (exp 194) ===',
  );

  await _lane(
    label: '10k rows x 8 integral reals',
    rows: 10000,
    integralRealCols: 8,
    iters: 20,
  );
  await _lane(
    label: '10k rows x 20 integral reals',
    rows: 10000,
    integralRealCols: 20,
    iters: 12,
  );
  await _lane(
    label: '10k rows x 20 fractional reals',
    rows: 10000,
    integralRealCols: 0,
    fractionalRealCols: 20,
    iters: 8,
  );
  await _lane(
    label: '10k rows x 8 mixed (4 int-real + 2 frac-real + 2 text)',
    rows: 10000,
    integralRealCols: 4,
    fractionalRealCols: 2,
    textCols: 2,
    iters: 16,
  );
  await _lane(
    label: '1k rows x 2 integral reals',
    rows: 1000,
    integralRealCols: 2,
    iters: 200,
  );
}
