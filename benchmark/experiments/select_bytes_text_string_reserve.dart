// Focused A/B harness for selectBytes TEXT JSON string emission.
//
// The TEXT arm of write_json_to_buf calls json_write_string once per TEXT
// cell. Safe strings with no JSON escapes are the common case. The 96 B, 256 B,
// and 1 KiB lanes isolate the scan-then-copy cost that grows with a safe span;
// the long CJK lane checks the same shape with high UTF-8 bytes. Escaped lanes
// guard the fallback path, control-character lanes isolate `\u00XX` emission,
// and mixed/narrow lanes guard broader row-shape cost.
//
// Run on a quiet machine; two order-flipped passes recommended.
//   dart run benchmark/experiments/select_bytes_text_string_reserve.dart
import 'dart:io';

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

String _textValue(String mode, int row, int col, int bytes) {
  switch (mode) {
    case 'ascii':
      final seed = 'row_${row}_col_${col}_';
      return (seed * ((bytes ~/ seed.length) + 1)).substring(0, bytes);
    case 'escaped':
      final seed = 'r$row"c$col\\n\t/';
      return (seed * ((bytes ~/ seed.length) + 1)).substring(0, bytes);
    case 'control':
      final seed = 'r$row\x01c$col\x02\x03/';
      return (seed * ((bytes ~/ seed.length) + 1)).substring(0, bytes);
    case 'cjk':
      final seed = '日本語$row-$col';
      return (seed * ((bytes ~/ seed.length) + 1)).substring(0, bytes);
    default:
      throw ArgumentError.value(mode, 'mode');
  }
}

Future<void> _lane({
  required String label,
  required int rows,
  required int textCols,
  required int textBytes,
  required String mode,
  int intCols = 0,
  int realCols = 0,
  required int iters,
}) async {
  final dir = await Directory.systemTemp.createTemp('resq_text_json_');
  final db = await Database.open('${dir.path}/t.db');
  try {
    final textDefs = [for (var i = 0; i < textCols; i++) 't$i TEXT'];
    final intDefs = [for (var i = 0; i < intCols; i++) 'i$i INTEGER'];
    final realDefs = [for (var i = 0; i < realCols; i++) 'r$i REAL'];
    final defs = [
      'id INTEGER PRIMARY KEY',
      ...textDefs,
      ...intDefs,
      ...realDefs,
    ];
    await db.execute('CREATE TABLE t(${defs.join(', ')})');

    final textNames = [for (var i = 0; i < textCols; i++) 't$i'];
    final intNames = [for (var i = 0; i < intCols; i++) 'i$i'];
    final realNames = [for (var i = 0; i < realCols; i++) 'r$i'];
    final cols = ['id', ...textNames, ...intNames, ...realNames];
    final placeholders = List.filled(cols.length, '?').join(', ');
    final insertSql =
        'INSERT INTO t(${cols.join(', ')}) VALUES ($placeholders)';

    final batch = <List<Object?>>[];
    for (var r = 0; r < rows; r++) {
      final row = <Object?>[r];
      for (var c = 0; c < textCols; c++) {
        row.add(_textValue(mode, r, c, textBytes));
      }
      for (var c = 0; c < intCols; c++) {
        row.add(r * 31 + c);
      }
      for (var c = 0; c < realCols; c++) {
        row.add(r + c + 0.25);
      }
      batch.add(row);
    }
    await db.executeBatch(insertSql, batch);

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
  stdout.writeln('=== selectBytes TEXT JSON string emission ===');

  await _lane(
    label: '10k rows x 8 short ASCII text',
    rows: 10000,
    textCols: 8,
    textBytes: 16,
    mode: 'ascii',
    iters: 16,
  );
  await _lane(
    label: '10k rows x 20 short ASCII text',
    rows: 10000,
    textCols: 20,
    textBytes: 16,
    mode: 'ascii',
    iters: 8,
  );
  await _lane(
    label: '10k rows x 8 threshold ASCII text (64B)',
    rows: 10000,
    textCols: 8,
    textBytes: 64,
    mode: 'ascii',
    iters: 8,
  );
  await _lane(
    label: '10k rows x 8 medium ASCII text',
    rows: 10000,
    textCols: 8,
    textBytes: 96,
    mode: 'ascii',
    iters: 8,
  );
  await _lane(
    label: '10k rows x 8 long ASCII text (256B)',
    rows: 10000,
    textCols: 8,
    textBytes: 256,
    mode: 'ascii',
    iters: 4,
  );
  await _lane(
    label: '2k rows x 4 very long ASCII text (1KiB)',
    rows: 2000,
    textCols: 4,
    textBytes: 1024,
    mode: 'ascii',
    iters: 8,
  );
  await _lane(
    label: '2k rows x 4 very long CJK text (1K code units)',
    rows: 2000,
    textCols: 4,
    textBytes: 1024,
    mode: 'cjk',
    iters: 4,
  );
  await _lane(
    label: '10k rows x 8 escaped text',
    rows: 10000,
    textCols: 8,
    textBytes: 24,
    mode: 'escaped',
    iters: 10,
  );
  await _lane(
    label: '10k rows x 8 early-escape text (96B)',
    rows: 10000,
    textCols: 8,
    textBytes: 96,
    mode: 'escaped',
    iters: 6,
  );
  await _lane(
    label: '10k rows x 8 control text',
    rows: 10000,
    textCols: 8,
    textBytes: 24,
    mode: 'control',
    iters: 10,
  );
  await _lane(
    label: '10k rows x 8 mixed (4 text + 2 int + 2 real)',
    rows: 10000,
    textCols: 4,
    textBytes: 24,
    mode: 'ascii',
    intCols: 2,
    realCols: 2,
    iters: 12,
  );
  await _lane(
    label: '1k rows x 2 short ASCII text',
    rows: 1000,
    textCols: 2,
    textBytes: 16,
    mode: 'ascii',
    iters: 120,
  );
}
