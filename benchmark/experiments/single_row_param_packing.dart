// Focused microbenchmark for the single-row parameter encoder
// (`allocateParams`), isolating the bind-path encoding cost from any DB,
// FFI step, or result-transfer work. Used by exp 179 to measure the
// direct-ASCII-write change to `allocateParams` in isolation, since the
// bind is too small a fraction of any release-suite lane to register there.
//
//   dart run benchmark/experiments/single_row_param_packing.dart
//
// Reports median ns/op per parameter shape over N allocate+free cycles.
import 'dart:typed_data';

import 'package:resqlite/src/native/resqlite_bindings.dart';

const _iterations = 200000;
const _samples = 15;

void main() {
  final shapes = <String, List<Object?>>{
    // The Parameterized-Queries lane shape: one short ASCII text param.
    'ascii-1-short': ['cat_7'],
    // A typical ORM insert row: id + 4 short ASCII text columns.
    'ascii-5-mixed': [42, 'Ada Lovelace', 'ada@example.com', 'London', 'UK'],
    // Large ASCII text param (1 KB) — where direct-write should help most.
    'ascii-1-large': [_asciiOf(1024)],
    // Non-ASCII: exercises the direct UTF-8 path added after the ASCII fast
    // path, as a small-payload guardrail.
    'unicode-1': ['項目_東京_${'あ' * 64}'],
    // BLOB + int only: no string, identical on both paths (control).
    'blob-int': [7, Uint8List(256)],
  };

  print(
    'single-row param packing — $_iterations cycles/sample, '
    '$_samples samples\n',
  );
  print('| Shape | Median ns/op | Min | Max |');
  print('|---|---|---|---|');
  shapes.forEach((name, params) {
    final medians = <double>[];
    for (var s = 0; s < _samples; s++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < _iterations; i++) {
        final buf = allocateParams(params);
        freeParams(buf, params);
      }
      sw.stop();
      medians.add(sw.elapsedMicroseconds * 1000 / _iterations);
    }
    medians.sort();
    final med = medians[medians.length ~/ 2];
    print(
      '| $name | ${med.toStringAsFixed(1)} | '
      '${medians.first.toStringAsFixed(1)} | '
      '${medians.last.toStringAsFixed(1)} |',
    );
  });
}

String _asciiOf(int n) {
  final b = StringBuffer();
  for (var i = 0; i < n; i++) {
    b.writeCharCode(0x61 + (i % 26));
  }
  return b.toString();
}
