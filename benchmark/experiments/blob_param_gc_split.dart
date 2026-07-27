// Per-lane GC attribution for exp 234 — runs ONE lane (baseline or candidate)
// of the real resqlite blob-INSERT path per process, so `--verbose_gc` output
// is attributable to that lane alone.
//
//   dart run benchmark/experiments/blob_param_gc_split.dart base
//   dart run benchmark/experiments/blob_param_gc_split.dart cand
//
// (VM flag via DART_VM_OPTIONS=--verbose_gc or `dart --verbose_gc run ...`.)
// Prints total wall for the insert loop; GC lines land on stderr.
import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/blob_transfer.dart';

const _size = 256 * 1024;
const _inserts = 300;

Future<void> main(List<String> args) async {
  final candidate = args.isNotEmpty && args.first == 'cand';
  BlobTransfer.paramThreshold = candidate ? 256 * 1024 : (1 << 40);

  final tmp = await Directory.systemTemp.createTemp('resqlite-exp234-gcs-');
  final db = await Database.open('${tmp.path}/g.db');
  await db.execute('CREATE TABLE b(id INTEGER PRIMARY KEY, payload BLOB)');
  final blob = Uint8List.fromList(
    List.generate(_size, (i) => (i * 31 + 7) & 0xFF),
  );

  for (var i = 0; i < 20; i++) {
    await db.execute('INSERT INTO b(payload) VALUES (?)', [blob]);
  }
  await db.execute('DELETE FROM b');

  // DELETE every 60 inserts matches blob_param_write_ab.dart's sample shape,
  // so per-insert wall is comparable and the table never grows unboundedly.
  final sw = Stopwatch()..start();
  for (var i = 0; i < _inserts; i++) {
    await db.execute('INSERT INTO b(payload) VALUES (?)', [blob]);
    if (i % 60 == 59) await db.execute('DELETE FROM b');
  }
  sw.stop();
  stdout.writeln(
    'lane=${candidate ? 'cand' : 'base'} '
    'inserts=$_inserts wall_ms=${(sw.elapsedMicroseconds / 1000).toStringAsFixed(1)} '
    'us_per_insert=${(sw.elapsedMicroseconds / _inserts).toStringAsFixed(1)}',
  );

  await db.close();
  await tmp.delete(recursive: true);
}
