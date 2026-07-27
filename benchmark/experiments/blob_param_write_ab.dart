// End-to-end A/B for exp 234 — parameter-encoding-and-binding.
//
// Measures single-row large-BLOB INSERT wall with the [EXP-234]
// TransferableTypedData param-transfer path ENABLED vs DISABLED, in one
// process with interleaved, order-flipped sampling so machine drift indicts
// both lanes equally (the exp 159 / exp 177 drift discipline).
//
//   candidate (enabled): blobParamTransferThreshold = 256 KB — large blobs
//                        cross to the writer via TransferableTypedData
//                        (memcpy into malloc'd external memory + ownership
//                        move; the GC never sees the payload).
//   baseline (disabled): blobParamTransferThreshold = huge — every blob takes
//                        the direct SendPort object-graph copy (origin/main
//                        behavior): one sender-side copy landing on the
//                        shared GC heap, chunked with safepoint polls on the
//                        slow path for large payloads.
//
// The end-to-end wall includes the SQLite step (WAL write of the blob), so a
// win only appears if the main->writer hop — transfer copy plus the GC/
// safepoint cost of its heap landing — is a material fraction of the whole
// INSERT at that payload size. That is exactly the open question: does the
// blob param hop dominate, or does SQLite stepping? (Mechanism attribution:
// blob_param_mechanism_proof.dart / blob_param_gc_split.dart.)
//
//   dart run benchmark/experiments/blob_param_write_ab.dart
//
// Reports median us/INSERT per size for each lane across two order-flipped
// passes.
import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/blob_transfer.dart';

const _sizes = <int>[
  64 * 1024, // control (< threshold): candidate == baseline, both direct
  128 * 1024, // control (< threshold)
  256 * 1024, // wrapped
  512 * 1024, // wrapped
  1024 * 1024, // wrapped
];

const _writesPerSample = 60;
const _samples = 11;
const _warmup = 20;

const int _thresholdEnabled = 256 * 1024;
const int _thresholdDisabled = 1 << 40; // effectively off

Future<void> main() async {
  final tmp = await Directory.systemTemp.createTemp('resqlite-exp234-');
  final dbPath = '${tmp.path}/exp234.db';
  final db = await Database.open(dbPath);
  await db.execute(
    'CREATE TABLE blob_doc(id INTEGER PRIMARY KEY, payload BLOB)',
  );

  stdout.writeln(
    'blob param write A/B — $_writesPerSample INSERTs/sample, '
    '$_samples samples, two order-flipped passes\n',
  );
  stdout.writeln('| Size | Pass | Baseline us | Candidate us | Δ |');
  stdout.writeln('|---|---|---:|---:|---:|');

  for (final size in _sizes) {
    final blob = _makeBlob(size);

    // Pass 1: baseline first, then candidate.
    final b1 = await _measure(db, blob, enabled: false);
    final c1 = await _measure(db, blob, enabled: true);
    _row(size, 'P1 base→cand', b1, c1);

    // Pass 2: candidate first, then baseline (order flipped).
    final c2 = await _measure(db, blob, enabled: true);
    final b2 = await _measure(db, blob, enabled: false);
    _row(size, 'P2 cand→base', b2, c2);
  }

  await db.close();
  await tmp.delete(recursive: true);
}

Future<double> _measure(
  Database db,
  Uint8List blob, {
  required bool enabled,
}) async {
  blobParamTransferThreshold = enabled ? _thresholdEnabled : _thresholdDisabled;

  // Warm: bind cache, statement cache, page cache, writer isolate.
  for (var i = 0; i < _warmup; i++) {
    await db.execute('INSERT INTO blob_doc(payload) VALUES (?)', [blob]);
  }
  await db.execute('DELETE FROM blob_doc');

  final medians = <double>[];
  for (var s = 0; s < _samples; s++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < _writesPerSample; i++) {
      await db.execute('INSERT INTO blob_doc(payload) VALUES (?)', [blob]);
    }
    sw.stop();
    medians.add(sw.elapsedMicroseconds / _writesPerSample);
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
