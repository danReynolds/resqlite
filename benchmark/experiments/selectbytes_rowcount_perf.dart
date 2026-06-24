// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;

import '../shared/seeder.dart';

/// Focused A/B harness for the selectBytes row-count metadata change.
///
/// Times end-to-end `selectBytes()` wall (native serialize + FFI + SendPort
/// transfer) at several row counts. Run on the baseline commit and again
/// after the change; the row-count out-param adds one pointer to a leaf FFI
/// call plus one record field on the SendPort hop, so the medians must not
/// move beyond noise.
const _warmup = 30;
const _iterations = 300;
const _rowCounts = [100, 1000, 10000];

double _median(List<double> xs) {
  xs.sort();
  final n = xs.length;
  return n.isOdd ? xs[n ~/ 2] : (xs[n ~/ 2 - 1] + xs[n ~/ 2]) / 2;
}

double _percentile(List<double> sorted, double p) =>
    sorted[(sorted.length * p).floor().clamp(0, sorted.length - 1)];

Future<void> main() async {
  print('=== selectBytes row-count perf (end-to-end wall) ===');
  for (final rowCount in _rowCounts) {
    final tempDir = await Directory.systemTemp.createTemp('bench_rc_');
    try {
      final db = await resqlite.Database.open('${tempDir.path}/test.db');
      await seedResqlite(db, rowCount);
      const sql = standardSelectSql;

      for (var i = 0; i < _warmup; i++) {
        await db.selectBytes(sql);
      }

      final samples = <double>[];
      for (var i = 0; i < _iterations; i++) {
        final sw = Stopwatch()..start();
        await db.selectBytes(sql);
        sw.stop();
        samples.add(sw.elapsedMicroseconds / 1000.0);
      }
      final med = _median(samples);
      final p90 = _percentile(samples, 0.90);
      print(
        '${rowCount.toString().padLeft(6)} rows: '
        'median ${med.toStringAsFixed(4)} ms  '
        'p90 ${p90.toStringAsFixed(4)} ms',
      );
      await db.close();
    } finally {
      await tempDir.delete(recursive: true);
    }
  }
}
