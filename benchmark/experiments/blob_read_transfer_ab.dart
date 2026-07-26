// Focused A/B for exp 236 — result-transfer-shape.
//
// Measures `select()` / `tx.select()` wall for blob-heavy results with the
// [EXP-236] TransferableTypedData blob-cell decode enabled (default) vs
// disabled. The threshold is a compile-time define (worker isolates hold
// their own copies of file-level globals, so a runtime toggle cannot reach
// the decode loop) — each lane is one process:
//
//   candidate: dart run benchmark/experiments/blob_read_transfer_ab.dart
//   baseline:  dart run -DRESQLITE_BLOB_CELL_TRANSFER_THRESHOLD=1099511627776 \
//                benchmark/experiments/blob_read_transfer_ab.dart
//
// Run passes order-flipped (base,cand then cand,base) per the exp 177 drift
// discipline; per-process lanes were validated by exp 234's gc_split.
//
// What the lanes exercise:
//   - blob-dominated select() results >= 256 KB: baseline SACRIFICES the
//     reader isolate on every query (Isolate.exit + ~2-5 ms respawn + stmt/
//     schema cache loss); candidate wraps the blob cells and keeps the
//     worker. This is the headline shape.
//   - sub-threshold and text-heavy lanes are controls: identical code path
//     in both lanes (direct cells / still-sacrificing), so they measure the
//     noise floor.
//   - tx.select goes through the writer (no sacrifice either lane); its win
//     is only graph-copy -> ownership-move, expected smaller.
import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/query_decoder.dart' show blobCellTransferThreshold;

const _selectsPerSample = 30;
const _samples = 9;
const _warmup = 10;

Future<void> main() async {
  final lane = blobCellTransferThreshold <= 1024 * 1024 ? 'cand' : 'base';
  final tmp = await Directory.systemTemp.createTemp('resqlite-exp236-');
  final db = await Database.open('${tmp.path}/exp236.db');
  await db.execute(
    'CREATE TABLE b(id INTEGER PRIMARY KEY, body TEXT, payload BLOB)',
  );

  Uint8List blobOf(int size, int seed) =>
      Uint8List.fromList(List.generate(size, (i) => (i * 31 + seed) & 0xFF));

  // Row sets per lane label; recreated fresh per shape.
  stdout.writeln('| Lane | Shape | median µs/select | min | max |');
  stdout.writeln('|---|---|---:|---:|---:|');

  Future<void> shape(
    String label,
    Future<void> Function() setup,
    Future<void> Function() query,
  ) async {
    await db.execute('DELETE FROM b');
    await setup();
    for (var i = 0; i < _warmup; i++) {
      await query();
    }
    final medians = <double>[];
    for (var s = 0; s < _samples; s++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < _selectsPerSample; i++) {
        await query();
      }
      sw.stop();
      medians.add(sw.elapsedMicroseconds / _selectsPerSample);
    }
    medians.sort();
    stdout.writeln(
      '| $lane | $label '
      '| ${medians[medians.length ~/ 2].toStringAsFixed(1)} '
      '| ${medians.first.toStringAsFixed(1)} '
      '| ${medians.last.toStringAsFixed(1)} |',
    );
  }

  const q = 'SELECT id, payload FROM b ORDER BY id';

  await shape('1×200KB blob (control: direct both lanes)', () async {
    await db.execute('INSERT INTO b(id, payload) VALUES (1, ?)', [
      blobOf(200 * 1024, 7),
    ]);
  }, () => db.select(q));

  await shape(
    '1×400KB text (control: sacrifices both lanes)',
    () async {
      await db.execute('INSERT INTO b(id, body) VALUES (1, ?)', [
        'x' * (400 * 1024),
      ]);
    },
    () => db.select('SELECT id, body FROM b ORDER BY id'),
  );

  await shape('20×512B blobs (control: small)', () async {
    for (var n = 0; n < 20; n++) {
      await db.execute('INSERT INTO b(id, payload) VALUES (?, ?)', [
        n + 1,
        blobOf(512, n),
      ]);
    }
  }, () => db.select(q));

  await shape('1×512KB blob', () async {
    await db.execute('INSERT INTO b(id, payload) VALUES (1, ?)', [
      blobOf(512 * 1024, 7),
    ]);
  }, () => db.select(q));

  await shape('1×1MB blob', () async {
    await db.execute('INSERT INTO b(id, payload) VALUES (1, ?)', [
      blobOf(1024 * 1024, 7),
    ]);
  }, () => db.select(q));

  await shape('4×300KB blobs', () async {
    for (var n = 0; n < 4; n++) {
      await db.execute('INSERT INTO b(id, payload) VALUES (?, ?)', [
        n + 1,
        blobOf(300 * 1024, n),
      ]);
    }
  }, () => db.select(q));

  await shape('tx.select 1×512KB blob', () async {
    await db.execute('INSERT INTO b(id, payload) VALUES (1, ?)', [
      blobOf(512 * 1024, 7),
    ]);
  }, () => db.transaction((tx) => tx.select(q)));

  await db.close();
  await tmp.delete(recursive: true);
}
