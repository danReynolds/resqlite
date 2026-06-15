// Focused A/B harness for exp 174 — selectBytes native-view transfer.
//
// Compares per-query wall for selectBytes at two sizes:
//   - large (>256KB): the path that formerly took the sacrifice
//     (Isolate.exit + reader respawn) branch; exp 174 sends the native
//     json_buf view directly instead, eliminating the respawn.
//   - small (<256KB): formerly fromList + SendPort (two copies); exp 174
//     sends the view (one copy). Expected neutral (copy is a small fraction
//     of per-query JSON-gen + round-trip).
//
// Run on a quiet machine; structural (respawn) deltas survive moderate load.
//   dart run benchmark/experiments/large_bytes_transfer.dart
import 'dart:io';

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
      final b = await db.selectBytes(sql);
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
  required int bodyLen,
  required int iters,
}) async {
  final dir = await Directory.systemTemp.createTemp('resq_bytes_xfer_');
  final db = await Database.open('${dir.path}/t.db');
  try {
    await db.execute('CREATE TABLE t(id INTEGER PRIMARY KEY, body TEXT)');
    final body = 'x' * bodyLen;
    await db.executeBatch(
      'INSERT INTO t(id, body) VALUES (?, ?)',
      [for (var i = 0; i < rows; i++) [i, '$body-$i']],
    );
    const sql = 'SELECT id, body FROM t ORDER BY id';
    final probe = await db.selectBytes(sql);
    // warm up
    for (var i = 0; i < (iters ~/ 4) + 1; i++) {
      await db.selectBytes(sql);
    }
    final medUs = await _medianUs(db, sql, iters, 6);
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
  stdout.writeln('=== selectBytes native-view transfer (exp 174) ===');
  await _lane(label: 'large-bytes (>256KB)', rows: 2000, bodyLen: 300, iters: 150);
  await _lane(label: 'small-bytes (<256KB)', rows: 1000, bodyLen: 40, iters: 2000);
}
