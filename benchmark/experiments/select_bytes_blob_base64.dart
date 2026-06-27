// Focused A/B harness for selectBytes BLOB base64 JSON encoding.
//
// The BLOB arm of write_json_to_buf calls json_write_base64 once per BLOB
// cell. Lanes with many tiny BLOBs make per-cell JSON framing and buffer
// capacity checks visible; medium and large BLOB lanes guard that base64
// throughput itself does not regress.
//
// Run on a quiet machine; two order-flipped passes recommended.
//   dart run benchmark/experiments/select_bytes_blob_base64.dart
import 'dart:io';
import 'dart:typed_data';

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
  required int blobCols,
  required int blobBytes,
  int intCols = 0,
  int textCols = 0,
  required int iters,
}) async {
  final dir = await Directory.systemTemp.createTemp('resq_blob_json_');
  final db = await Database.open('${dir.path}/t.db');
  try {
    final blobDefs = [for (var i = 0; i < blobCols; i++) 'b$i BLOB'];
    final intDefs = [for (var i = 0; i < intCols; i++) 'i$i INTEGER'];
    final textDefs = [for (var i = 0; i < textCols; i++) 't$i TEXT'];
    final defs = [
      'id INTEGER PRIMARY KEY',
      ...blobDefs,
      ...intDefs,
      ...textDefs,
    ];
    await db.execute('CREATE TABLE t(${defs.join(', ')})');

    final blobNames = [for (var i = 0; i < blobCols; i++) 'b$i'];
    final intNames = [for (var i = 0; i < intCols; i++) 'i$i'];
    final textNames = [for (var i = 0; i < textCols; i++) 't$i'];
    final cols = ['id', ...blobNames, ...intNames, ...textNames];
    final placeholders = List.filled(cols.length, '?').join(', ');
    final insertSql =
        'INSERT INTO t(${cols.join(', ')}) VALUES ($placeholders)';

    final blobs = [
      for (var c = 0; c < blobCols; c++)
        Uint8List.fromList([
          for (var i = 0; i < blobBytes; i++) (i * 31 + c * 17) & 0xff,
        ]),
    ];

    final batch = <List<Object?>>[];
    for (var r = 0; r < rows; r++) {
      final row = <Object?>[r];
      for (var c = 0; c < blobCols; c++) {
        row.add(blobs[c]);
      }
      for (var c = 0; c < intCols; c++) {
        row.add(r * 37 + c);
      }
      for (var c = 0; c < textCols; c++) {
        row.add('text_${r}_$c');
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
  stdout.writeln('=== selectBytes BLOB base64 JSON encoding ===');

  await _lane(
    label: '10k rows x 8 tiny blobs (3B)',
    rows: 10000,
    blobCols: 8,
    blobBytes: 3,
    iters: 20,
  );
  await _lane(
    label: '10k rows x 20 tiny blobs (3B)',
    rows: 10000,
    blobCols: 20,
    blobBytes: 3,
    iters: 10,
  );
  await _lane(
    label: '10k rows x 8 small blobs (16B)',
    rows: 10000,
    blobCols: 8,
    blobBytes: 16,
    iters: 12,
  );
  await _lane(
    label: '10k rows x 4 medium blobs (128B)',
    rows: 10000,
    blobCols: 4,
    blobBytes: 128,
    iters: 8,
  );
  await _lane(
    label: '1k rows x 2 large blobs (4KB)',
    rows: 1000,
    blobCols: 2,
    blobBytes: 4096,
    iters: 8,
  );
  await _lane(
    label: '10k rows x 8 mixed (4 blob + 2 int + 2 text)',
    rows: 10000,
    blobCols: 4,
    blobBytes: 16,
    intCols: 2,
    textCols: 2,
    iters: 12,
  );
}
