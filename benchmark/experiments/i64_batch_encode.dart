// Focused A/B microbench for exp 240 — batched i64 -> decimal encoding.
//
// exp 231 rejected a per-value NEON i64 formatter for the SQLITE_INTEGER arm of
// write_json_to_buf: a scalar per-cell value has "nothing to amortise" over the
// SIMD setup. Its reopen door was explicit — reopen only if "a future
// architecture batches many integer cells into one encode call (a
// columnar/bulk transfer that hands the kernel an array of i64s)".
//
// This microbench builds exactly that: three native encoders that format a
// whole i64 array in one call (comma-separated, byte-identical output), and
// times pure conversion throughput with zero JSON-interleave or SQLite cost:
//
//   scalar  — the shipped two-digit-LUT formatter, once per value (baseline)
//   pipe2   — 2-way software-pipelined scalar (cross-value ILP, no SIMD)
//   neon    — inlined NEON vector digit kernel over the array (exp 231's reopen)
//
// If neither batch form beats `scalar` in this isolation, the integration into
// write_json_to_buf cannot help either — the JSON interleave only adds serial
// per-value output positioning on top — and exp 231's reopen door closes with
// a direct measurement rather than an inference.
//
// Lanes sweep digit width (the division-chain length is what a batch could
// overlap) and array length (amortisation surface):
//   - 20-digit ~1.8e19 BIGINTs  (worst-case chain; exp 231's target shape)
//   - ~10-digit mid ints        (typical i64 id / timestamp)
//   - 1..4-digit small ints     (row ids / counts; short chain)
//   - mixed magnitudes          (representative column)
//
// Run on a quiet machine; two order-flipped passes recommended.
//   dart run benchmark/experiments/i64_batch_encode.dart
@ffi.DefaultAsset('package:resqlite/src/native/resqlite_bindings.dart')
library;

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
// Force the native asset to build/link before we bind its test symbols.
// ignore: unused_import
import 'package:resqlite/resqlite.dart';

@ffi.Native<
  ffi.Int Function(ffi.Pointer<ffi.Int64>, ffi.Int, ffi.Pointer<ffi.Uint8>)
>(symbol: 'resqlite_test_i64_array_scalar', isLeaf: true)
external int i64ArrScalar(ffi.Pointer<ffi.Int64> vals, int n, ffi.Pointer<ffi.Uint8> out);

@ffi.Native<
  ffi.Int Function(ffi.Pointer<ffi.Int64>, ffi.Int, ffi.Pointer<ffi.Uint8>)
>(symbol: 'resqlite_test_i64_array_pipe2', isLeaf: true)
external int i64ArrPipe2(ffi.Pointer<ffi.Int64> vals, int n, ffi.Pointer<ffi.Uint8> out);

@ffi.Native<
  ffi.Int Function(ffi.Pointer<ffi.Int64>, ffi.Int, ffi.Pointer<ffi.Uint8>)
>(symbol: 'resqlite_test_i64_array_neon', isLeaf: true)
external int i64ArrNeon(ffi.Pointer<ffi.Int64> vals, int n, ffi.Pointer<ffi.Uint8> out);

typedef _Enc = int Function(ffi.Pointer<ffi.Int64>, int, ffi.Pointer<ffi.Uint8>);

int _median(List<int> xs) {
  xs.sort();
  return xs[xs.length ~/ 2];
}

/// Times one encoder over `iters` full-array passes, `rounds` samples; returns
/// median nanoseconds per array pass.
int _timeNsPerPass(
  _Enc enc,
  ffi.Pointer<ffi.Int64> vals,
  int n,
  ffi.Pointer<ffi.Uint8> out,
  int iters,
  int rounds,
) {
  // Warm up.
  for (var i = 0; i < 3; i++) {
    enc(vals, n, out);
  }
  final samples = <int>[];
  for (var r = 0; r < rounds; r++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < iters; i++) {
      enc(vals, n, out);
    }
    sw.stop();
    samples.add(sw.elapsedMicroseconds * 1000 ~/ iters);
  }
  return _median(samples);
}

String _decode(ffi.Pointer<ffi.Uint8> out, int len) =>
    utf8.decode(out.asTypedList(len));

void _lane({
  required String label,
  required List<int> vals,
  int iters = 4000,
  int rounds = 15,
}) {
  final n = vals.length;
  final valsPtr = malloc<ffi.Int64>(n);
  final list = valsPtr.asTypedList(n);
  for (var i = 0; i < n; i++) {
    list[i] = vals[i];
  }
  // Output upper bound: 20 digits + sign + comma per value.
  final out = malloc<ffi.Uint8>(n * 24 + 16);

  try {
    // Correctness: all three must agree byte-for-byte before we trust timings.
    final ns = i64ArrScalar(valsPtr, n, out);
    final sRef = _decode(out, ns);
    final np = i64ArrPipe2(valsPtr, n, out);
    final sPipe = _decode(out, np);
    final nn = i64ArrNeon(valsPtr, n, out);
    final sNeon = _decode(out, nn);
    if (sPipe != sRef) {
      throw StateError('pipe2 mismatch in "$label":\n  ref =$sRef\n  pipe=$sPipe');
    }
    if (sNeon != sRef) {
      throw StateError('neon mismatch in "$label":\n  ref =$sRef\n  neon=$sNeon');
    }

    final scalar = _timeNsPerPass(i64ArrScalar, valsPtr, n, out, iters, rounds);
    final pipe2 = _timeNsPerPass(i64ArrPipe2, valsPtr, n, out, iters, rounds);
    final neon = _timeNsPerPass(i64ArrNeon, valsPtr, n, out, iters, rounds);

    String pct(int cand) {
      final d = (cand - scalar) / scalar * 100;
      final sign = d >= 0 ? '+' : '';
      return '$sign${d.toStringAsFixed(1)}%';
    }

    print('${label.padRight(28)}'
        ' scalar=${scalar.toString().padLeft(7)}ns'
        '  pipe2=${pipe2.toString().padLeft(7)}ns (${pct(pipe2).padLeft(7)})'
        '  neon=${neon.toString().padLeft(7)}ns (${pct(neon).padLeft(7)})');
  } finally {
    malloc.free(valsPtr);
    malloc.free(out);
  }
}

void main() {
  // Deterministic values (Math.random is unavailable in workflow scripts, but
  // this is a plain benchmark; a fixed seed keeps runs comparable anyway).
  final rng = math.Random(0x240);
  List<int> gen(int n, int Function() next) => List.generate(n, (_) => next());

  const arrLen = 200; // one "wide row batch" worth of integer cells

  print('exp 240 — batched i64 array encode (ns per $arrLen-value array pass)');
  print('lower is better; pipe2/neon percentages are vs scalar baseline\n');

  // 20-digit BIGINTs near the i64 ceiling — longest division chain.
  _lane(
    label: 'big ~19-20 digit',
    vals: gen(arrLen, () {
      final hi = (rng.nextInt(1 << 32));
      final lo = (rng.nextInt(1 << 32));
      final v = (hi << 32) | lo; // spans full positive i64 range
      return rng.nextBool() ? -v : v;
    }),
  );

  // ~10-digit mid ints (unix seconds / typical ids).
  _lane(
    label: 'mid ~10 digit',
    vals: gen(arrLen, () => 1000000000 + rng.nextInt(2000000000)),
  );

  // Small 1..4 digit (row ids, counts) — short chain, most common shape.
  _lane(
    label: 'small 0..9999',
    vals: gen(arrLen, () => rng.nextInt(10000)),
  );

  // Mixed magnitudes — representative real column.
  _lane(
    label: 'mixed magnitudes',
    vals: gen(arrLen, () {
      switch (rng.nextInt(4)) {
        case 0:
          return rng.nextInt(100);
        case 1:
          return rng.nextInt(1000000);
        case 2:
          return 1000000000 + rng.nextInt(2000000000);
        default:
          final v = (rng.nextInt(1 << 32) << 20) | rng.nextInt(1 << 20);
          return rng.nextBool() ? -v : v;
      }
    }),
  );
}
