// Focused A/B harness for exp 194 / exp 232 — exact integral and quarter-step
// REAL fast paths for selectBytes JSON encoding.
//
// The SQLITE_FLOAT arm currently pays snprintf("%.17g") for every REAL cell.
// This workload separates exactly integral and quarter-step REAL values, which
// can avoid general formatting without changing spelling, from fractional REAL
// controls that must stay on snprintf.
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
  int quarterRealCols = 0,
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
    final quarterDefs = [for (var i = 0; i < quarterRealCols; i++) 'rq$i REAL'];
    final textDefs = [for (var i = 0; i < textCols; i++) 't$i TEXT'];
    final defs = [
      'id INTEGER PRIMARY KEY',
      ...integralDefs,
      ...quarterDefs,
      ...fractionalDefs,
      ...textDefs,
    ];
    await db.execute('CREATE TABLE t(${defs.join(', ')})');

    final integralNames = [for (var i = 0; i < integralRealCols; i++) 'ri$i'];
    final fractionalNames = [
      for (var i = 0; i < fractionalRealCols; i++) 'rf$i',
    ];
    final quarterNames = [for (var i = 0; i < quarterRealCols; i++) 'rq$i'];
    final textNames = [for (var i = 0; i < textCols; i++) 't$i'];
    final cols = [
      'id',
      ...integralNames,
      ...quarterNames,
      ...fractionalNames,
      ...textNames,
    ];
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
      for (var c = 0; c < quarterRealCols; c++) {
        final whole = rng.nextInt(1 << 30) - (1 << 29);
        row.add(whole + const [0.25, 0.5, 0.75][(r + c) % 3]);
      }
      for (var c = 0; c < fractionalRealCols; c++) {
        final whole = rng.nextInt(1 << 30) - (1 << 29);
        row.add(whole + ((r + c).isEven ? 0.125 : 0.375));
      }
      for (var c = 0; c < textCols; c++) {
        row.add('text_${r}_$c');
      }
      batch.add(row);
    }
    await db.executeBatch(sql, batch);

    // Untimed setup contract: target cells must remain non-integral SQLite
    // REAL quarter steps, while fallback controls must remain REAL eighths.
    // This keeps storage affinity or fixture drift from silently changing the
    // native formatter path measured by either lane.
    final invariantTerms = <String>[
      for (final name in integralNames)
        "typeof($name) = 'real' AND CAST($name AS INTEGER) = $name",
      for (final name in quarterNames)
        "typeof($name) = 'real' AND "
            'CAST($name * 4 AS INTEGER) = $name * 4 AND '
            'CAST($name * 4 AS INTEGER) % 4 != 0',
      for (final name in fractionalNames)
        "typeof($name) = 'real' AND "
            'CAST($name * 8 AS INTEGER) = $name * 8 AND '
            'CAST($name * 4 AS INTEGER) != $name * 4',
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
    '=== selectBytes exact REAL JSON encoding (exp 194 / exp 232) ===',
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
    label: '10k rows x 8 quarter-step reals',
    rows: 10000,
    integralRealCols: 0,
    quarterRealCols: 8,
    iters: 20,
  );
  await _lane(
    label: '10k rows x 20 quarter-step reals',
    rows: 10000,
    integralRealCols: 0,
    quarterRealCols: 20,
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
    label: '10k rows x 8 mixed (4 quarter + 2 frac-real + 2 text)',
    rows: 10000,
    integralRealCols: 0,
    quarterRealCols: 4,
    fractionalRealCols: 2,
    textCols: 2,
    iters: 16,
  );
  await _lane(
    label: '1k rows x 2 quarter-step reals',
    rows: 1000,
    integralRealCols: 0,
    quarterRealCols: 2,
    iters: 200,
  );
}
