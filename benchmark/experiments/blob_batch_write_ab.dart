// End-to-end A/B for exp 237 — parameter-encoding-and-binding.
//
// Measures blob-heavy `executeBatch` wall with the [EXP-237]
// TransferableTypedData param-transfer path ENABLED vs DISABLED, in one
// process with interleaved, order-flipped sampling so machine drift indicts
// both lanes equally (the exp 159 / exp 177 drift discipline).
//
// This extends exp 234 from the single-row INSERT to the batch path. A
// `BatchRequest` carries every parameter set across ONE `SendPort.send`, so
// the baseline object-graph copy lands *all* of a batch's blobs on the shared
// GC heap in a single hop — a larger burst of live young-generation data than
// any single-row write produces. The candidate wraps each qualifying blob in
// its own `TransferableTypedData` (memcpy into malloc'd external memory +
// ownership move; the GC never traces the payload).
//
//   candidate (enabled): blobParamTransferThreshold = 256 KB
//   baseline (disabled): blobParamTransferThreshold = huge — every blob takes
//                        the direct object-graph copy (origin/main behavior)
//
// The batch runs as one transaction, so its per-row SQLite/WAL cost is
// amortized across the whole batch — which sharpens the question this run
// asks: with WAL cost spread thin, is the main->writer blob hop (transfer copy
// plus the GC/safepoint cost of its heap landing) now a material fraction of
// the batch, or does even an amortized SQLite step still dominate?
//
//   dart run benchmark/experiments/blob_batch_write_ab.dart
//
// Reports median us/row per size for each lane across two order-flipped passes.
import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/writer/blob_param_transfer.dart';

const _sizes = <int>[
  64 * 1024, // control (< threshold): candidate == baseline, both direct
  128 * 1024, // control (< threshold)
  256 * 1024, // wrapped
  512 * 1024, // wrapped
  1024 * 1024, // wrapped
];

const _rowsPerBatch = 30;
const _samples = 11;
const _warmup = 8;

const int _thresholdEnabled = 256 * 1024;
const int _thresholdDisabled = 1 << 40; // effectively off

Future<void> main() async {
  final tmp = await Directory.systemTemp.createTemp('resqlite-exp237-');
  final dbPath = '${tmp.path}/exp237.db';
  final db = await Database.open(dbPath);
  await db.execute('CREATE TABLE blob_doc(id INTEGER PRIMARY KEY, payload BLOB)');

  stdout.writeln(
    'blob batch write A/B — executeBatch of $_rowsPerBatch rows/sample, '
    '$_samples samples, two order-flipped passes\n',
  );
  stdout.writeln('| Size | Pass | Baseline us/row | Candidate us/row | Δ |');
  stdout.writeln('|---|---|---:|---:|---:|');

  for (final size in _sizes) {
    final blob = _makeBlob(size);
    final paramSets = [
      for (var i = 0; i < _rowsPerBatch; i++) <Object?>[blob],
    ];

    // Pass 1: baseline first, then candidate.
    final b1 = await _measure(db, paramSets, enabled: false);
    final c1 = await _measure(db, paramSets, enabled: true);
    _row(size, 'P1 base→cand', b1, c1);

    // Pass 2: candidate first, then baseline (order flipped).
    final c2 = await _measure(db, paramSets, enabled: true);
    final b2 = await _measure(db, paramSets, enabled: false);
    _row(size, 'P2 cand→base', b2, c2);
  }

  await db.close();
  await tmp.delete(recursive: true);
}

Future<double> _measure(
  Database db,
  List<List<Object?>> paramSets, {
  required bool enabled,
}) async {
  blobParamTransferThreshold = enabled ? _thresholdEnabled : _thresholdDisabled;
  const sql = 'INSERT INTO blob_doc(payload) VALUES (?)';

  // Warm: bind cache, statement cache, page cache, writer isolate.
  for (var i = 0; i < _warmup; i++) {
    await db.executeBatch(sql, paramSets);
    await db.execute('DELETE FROM blob_doc');
  }

  final medians = <double>[];
  for (var s = 0; s < _samples; s++) {
    final sw = Stopwatch()..start();
    await db.executeBatch(sql, paramSets);
    sw.stop();
    medians.add(sw.elapsedMicroseconds / _rowsPerBatch);
    await db.execute('DELETE FROM blob_doc');
  }
  medians.sort();
  return medians[medians.length ~/ 2];
}

void _row(int size, String pass, double baseline, double candidate) {
  final delta = (candidate - baseline) / baseline * 100;
  stdout.writeln(
    '| ${_sizeLabel(size)} '
    '| $pass '
    '| ${baseline.toStringAsFixed(1)} '
    '| ${candidate.toStringAsFixed(1)} '
    '| ${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}% |',
  );
}

Uint8List _makeBlob(int size) {
  final b = Uint8List(size);
  for (var i = 0; i < size; i++) {
    b[i] = (i * 31 + 7) & 0xFF;
  }
  return b;
}

String _sizeLabel(int bytes) {
  if (bytes >= 1024 * 1024) return '${bytes ~/ (1024 * 1024)}MB';
  return '${bytes ~/ 1024}KB';
}
