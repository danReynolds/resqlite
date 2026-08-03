// Differential / fuzz coverage for the resqlite_json value encoders.
//
// The encoders in native/resqlite_json.c all share one invariant: their JSON
// output must be byte-identical to a known-good reference. Two of them are
// hard to cover with fixed cases:
//
//   1. base64 — on AArch64 the shipped path is the NEON kernel; on every other
//      target it is the scalar 12-bit-LUT encoder. Only whichever arch CI runs
//      on exercises its path, and a lane-order or off-by-one bug in the SIMD
//      kernel would not trip a fixed round-trip case unless the payload happens
//      to hit the bad alignment. Here we fuzz across every length 0..200 plus
//      large payloads and assert, in one run:
//         dispatch(NEON-or-scalar) == forced-scalar == dart:convert base64.
//      On ARM that directly pits the SIMD kernel against the scalar reference
//      and the oracle; the x86 CI lane (see .github/workflows/ci.yml) runs the
//      same test with the scalar path as the dispatcher.
//
//   2. string escape + number formatting — fuzzed end-to-end through
//      selectBytes() and checked by decoding back to the inserted values. We do
//      NOT byte-compare against jsonEncode(select): resqlite's number spelling
//      differs from Dart's by design (integer-valued REALs render as integers,
//      exp 194; fractional REALs use %.17g), but both decode to equal values.
@ffi.DefaultAsset('package:resqlite/src/native/resqlite_bindings.dart')
library;

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

// Test-support entry defined in native/resqlite_json.c. Encodes `len` input
// bytes as base64 into `out`; `forceScalar != 0` selects the always-scalar
// reference path, otherwise the shipped dispatcher (NEON where available).
// Returns bytes written (including the surrounding quotes), or -1 on OOM.
@ffi.Native<
  ffi.Int Function(
    ffi.Pointer<ffi.Uint8>,
    ffi.Int,
    ffi.Pointer<ffi.Uint8>,
    ffi.Int,
  )
>(symbol: 'resqlite_test_base64_encode', isLeaf: true)
external int resqliteTestBase64Encode(
  ffi.Pointer<ffi.Uint8> data,
  int len,
  ffi.Pointer<ffi.Uint8> out,
  int forceScalar,
);

// Test-support entry defined in native/resqlite_json.c (added by exp 231).
// Writes `val` as JSON decimal digits into `out` (no NUL) via the shipped
// integer formatter. Returns bytes written.
@ffi.Native<ffi.Int Function(ffi.Int64, ffi.Pointer<ffi.Uint8>)>(
  symbol: 'resqlite_test_i64_to_str',
  isLeaf: true,
)
external int resqliteTestI64ToStr(int val, ffi.Pointer<ffi.Uint8> out);

// Test-support entries defined in native/resqlite_json.c (exp 240). Each
// formats an array of `n` i64 values as a comma-separated decimal string into
// `out` (no NUL) and returns bytes written. `scalar` is the shipped per-value
// two-digit-LUT formatter; `pipe2` and `neon` are the batched candidates that
// exp 240 evaluated. All three must produce byte-identical output.
@ffi.Native<
  ffi.Int Function(ffi.Pointer<ffi.Int64>, ffi.Int, ffi.Pointer<ffi.Uint8>)
>(symbol: 'resqlite_test_i64_array_scalar', isLeaf: true)
external int resqliteTestI64ArrayScalar(
    ffi.Pointer<ffi.Int64> vals, int n, ffi.Pointer<ffi.Uint8> out);

@ffi.Native<
  ffi.Int Function(ffi.Pointer<ffi.Int64>, ffi.Int, ffi.Pointer<ffi.Uint8>)
>(symbol: 'resqlite_test_i64_array_pipe2', isLeaf: true)
external int resqliteTestI64ArrayPipe2(
    ffi.Pointer<ffi.Int64> vals, int n, ffi.Pointer<ffi.Uint8> out);

@ffi.Native<
  ffi.Int Function(ffi.Pointer<ffi.Int64>, ffi.Int, ffi.Pointer<ffi.Uint8>)
>(symbol: 'resqlite_test_i64_array_neon', isLeaf: true)
external int resqliteTestI64ArrayNeon(
    ffi.Pointer<ffi.Int64> vals, int n, ffi.Pointer<ffi.Uint8> out);

// Test-support entry defined in native/resqlite.c (exp 259). Returns 1 when
// every byte of `p[0..len)` is below 0x80. The row decoder turns a `1` into a
// Latin-1 `String.fromCharCodes` widen instead of `utf8.decode`, so a wrong
// answer is silent mojibake rather than a crash.
@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Uint8>, ffi.Int)>(
  symbol: 'resqlite_test_text_is_ascii',
  isLeaf: true,
)
external int resqliteTestTextIsAscii(ffi.Pointer<ffi.Uint8> p, int len);

/// Runs `bytes` through the native TEXT ASCII classifier.
bool _nativeIsAscii(List<int> bytes) {
  final p = malloc<ffi.Uint8>(bytes.isEmpty ? 1 : bytes.length);
  try {
    for (var i = 0; i < bytes.length; i++) {
      p[i] = bytes[i];
    }
    return resqliteTestTextIsAscii(p, bytes.length) != 0;
  } finally {
    malloc.free(p);
  }
}

/// Formats `vals` via one of the three exp 240 native array encoders and
/// returns the emitted comma-separated string.
String _nativeI64Array(
  List<int> vals,
  int Function(ffi.Pointer<ffi.Int64>, int, ffi.Pointer<ffi.Uint8>) enc,
) {
  final n = vals.length;
  final valsPtr = malloc<ffi.Int64>(n == 0 ? 1 : n);
  final out = malloc<ffi.Uint8>(n * 24 + 16);
  try {
    for (var i = 0; i < n; i++) {
      valsPtr[i] = vals[i];
    }
    final len = enc(valsPtr, n, out);
    return utf8.decode(out.asTypedList(len));
  } finally {
    malloc.free(valsPtr);
    malloc.free(out);
  }
}

/// Formats `val` via the shipped native integer formatter.
String _nativeI64(int val) {
  // RESQLITE_JSON_INT_MAX (24) is the reserved width; a little headroom.
  final outPtr = malloc<ffi.Uint8>(32);
  try {
    final n = resqliteTestI64ToStr(val, outPtr);
    expect(n, greaterThanOrEqualTo(1), reason: 'encode returned nothing');
    return utf8.decode(outPtr.asTypedList(n));
  } finally {
    malloc.free(outPtr);
  }
}

/// Encodes `input` via the native path selected by [forceScalar] and returns
/// the emitted JSON string (quotes included).
String _nativeBase64(Uint8List input, {required bool forceScalar}) {
  final inPtr = malloc<ffi.Uint8>(input.isEmpty ? 1 : input.length);
  // Output upper bound: 4 chars per 3 bytes rounded up, plus two quotes.
  final outCap = ((input.length + 2) ~/ 3) * 4 + 2;
  final outPtr = malloc<ffi.Uint8>(outCap == 0 ? 2 : outCap);
  try {
    if (input.isNotEmpty) {
      inPtr.asTypedList(input.length).setAll(0, input);
    }
    final n = resqliteTestBase64Encode(
      inPtr,
      input.length,
      outPtr,
      forceScalar ? 1 : 0,
    );
    expect(n, greaterThanOrEqualTo(0), reason: 'encode returned OOM');
    return utf8.decode(outPtr.asTypedList(n));
  } finally {
    malloc.free(inPtr);
    malloc.free(outPtr);
  }
}

void main() {
  group('native base64 encoder differential', () {
    test('dispatch == scalar == dart:convert across lengths 0..200', () {
      final rng = Random(0xB64F42);
      for (var len = 0; len <= 200; len++) {
        final bytes = Uint8List.fromList(
          List.generate(len, (_) => rng.nextInt(256)),
        );
        final oracle = '"${base64.encode(bytes)}"';
        expect(
          _nativeBase64(bytes, forceScalar: false),
          oracle,
          reason: 'dispatch path diverged from dart:convert at len=$len',
        );
        expect(
          _nativeBase64(bytes, forceScalar: true),
          oracle,
          reason: 'scalar path diverged from dart:convert at len=$len',
        );
      }
    });

    test('dispatch == scalar == dart:convert for large payloads', () {
      final rng = Random(0x5EEDED);
      // Sizes straddle the 48-byte SIMD block boundary and its multiples.
      for (final len in [47, 48, 49, 95, 96, 97, 4096, 4097, 65537, 1 << 20]) {
        final bytes = Uint8List.fromList(
          List.generate(len, (_) => rng.nextInt(256)),
        );
        final oracle = '"${base64.encode(bytes)}"';
        expect(
          _nativeBase64(bytes, forceScalar: false),
          oracle,
          reason: 'dispatch diverged at len=$len',
        );
        expect(
          _nativeBase64(bytes, forceScalar: true),
          oracle,
          reason: 'scalar diverged at len=$len',
        );
      }
    });

    test('all-byte-value blocks encode correctly', () {
      // Blocks covering every byte value, offset so both the SIMD block and the
      // scalar tail see the full range of inputs.
      for (var offset = 0; offset < 3; offset++) {
        final bytes = Uint8List.fromList(
          List.generate(256 + offset, (i) => i & 0xff),
        );
        final oracle = '"${base64.encode(bytes)}"';
        expect(_nativeBase64(bytes, forceScalar: false), oracle);
        expect(_nativeBase64(bytes, forceScalar: true), oracle);
      }
    });
  });

  group('native i64 formatter differential', () {
    // The integer JSON formatter (resqlite_json_i64_to_str) previously had no
    // direct differential coverage — the selectBytes fuzz below only exercised
    // 200 random ints. Exp 231 added this while prototyping (and rejecting) a
    // NEON integer kernel; the coverage is worth keeping against the scalar
    // two-digit-table path regardless of that outcome.
    void check(int val) {
      expect(
        _nativeI64(val),
        val.toString(),
        reason: 'native i64 formatter diverged from Dart at val=$val',
      );
    }

    test('boundary magnitudes and digit-group edges', () {
      const edges = <int>[
        0, 1, -1, 9, 10, 99, 100, 999, 1000,
        99999999, 100000000, // 8 -> 9 digits
        99999999999999, 100000000000000, // 14 -> 15 digits
        9999999999999999, 10000000000000000, // 16 -> 17 digits
        1234567890, 1000000000, 2000000010, // internal-zero shapes
        1000000000000000000, // 19 digits, trailing zeros
        1020304050607080900, // interleaved zeros across all digit groups
        9223372036854775807, // LLONG_MAX
        -9223372036854775808, // LLONG_MIN (sign-normalize edge)
        4294967295, 4294967296, // u32 boundary
      ];
      for (final v in edges) {
        check(v);
      }
    });

    test('dense random fuzz across the full i64 range', () {
      final rng = Random(0x1D07A);
      for (var i = 0; i < 300000; i++) {
        final hi = rng.nextInt(1 << 32);
        final lo = rng.nextInt(1 << 32);
        check((hi << 32) | lo); // may be negative — Dart int is 64-bit signed
        check(rng.nextInt(100000000)); // dense sub-9-digit coverage too
      }
    });
  });

  group('exp 259 TEXT ASCII classifier differential', () {
    void check(List<int> bytes, {String? reason}) {
      expect(
        _nativeIsAscii(bytes),
        bytes.every((b) => b < 0x80),
        reason: reason ?? 'classifier diverged on $bytes',
      );
    }

    test('high byte at every position of every length up to 40', () {
      // The scan consumes 8 bytes per SWAR word and finishes the remainder one
      // byte at a time, so both the word body and the tail must see a high bit
      // wherever it sits.
      for (var len = 0; len <= 40; len++) {
        check(List<int>.filled(len, 0x41));
        for (var pos = 0; pos < len; pos++) {
          final bytes = List<int>.filled(len, 0x41);
          bytes[pos] = 0x80;
          check(bytes, reason: 'len=$len, high byte at $pos');
          bytes[pos] = 0xFF;
          check(bytes, reason: 'len=$len, 0xFF at $pos');
        }
      }
    });

    test('0x7F stays ASCII and 0x80 does not, at word boundaries', () {
      for (final len in const [7, 8, 9, 15, 16, 17, 23, 24, 25]) {
        check(List<int>.filled(len, 0x7F), reason: 'all 0x7F len=$len');
        final last = List<int>.filled(len, 0x41)..[len - 1] = 0x80;
        check(last, reason: 'trailing 0x80 len=$len');
      }
    });

    test('real UTF-8 payloads', () {
      for (final s in <String>[
        '',
        'ascii_only_1234',
        'a' * 300,
        'café',
        '項目_東京',
        'emoji 🎉🚀',
        'mostly ascii with one é at the very end',
      ]) {
        check(utf8.encode(s), reason: 'string "$s"');
      }
    });

    test('dense random fuzz', () {
      final rng = Random(0x259A);
      for (var i = 0; i < 20000; i++) {
        final len = rng.nextInt(64);
        final bytes = List<int>.generate(
          len,
          // Mostly ASCII so the sparse-high-byte case dominates, which is the
          // shape a single accented character inside a long value produces.
          (_) => rng.nextInt(100) == 0 ? 0x80 + rng.nextInt(0x80) : rng.nextInt(0x80),
        );
        check(bytes);
      }
    });
  });

  group('exp 240 batched i64 array encoders differential', () {
    // The batched candidates (pipe2 software-pipelining, neon vector kernel)
    // must be byte-identical to the shipped per-value scalar formatter and to
    // Dart's oracle. The pipe2 path pairs adjacent values, so parity has to
    // hold across the odd/even boundary and the intra-pair digit-length mix;
    // the neon path formats each value through the vector 8-digit kernel.
    void checkArray(List<int> vals) {
      final oracle = vals.join(',');
      expect(_nativeI64Array(vals, resqliteTestI64ArrayScalar), oracle,
          reason: 'scalar array encoder diverged: $vals');
      expect(_nativeI64Array(vals, resqliteTestI64ArrayPipe2), oracle,
          reason: 'pipe2 array encoder diverged: $vals');
      expect(_nativeI64Array(vals, resqliteTestI64ArrayNeon), oracle,
          reason: 'neon array encoder diverged: $vals');
    }

    test('boundary shapes, mixed lengths, odd/even counts', () {
      const edges = <int>[
        0, 1, -1, 9, 10, 99, 100, 999, 1000,
        99999999, 100000000, 9999999999999999, 10000000000000000,
        1020304050607080900, 9223372036854775807, -9223372036854775808,
        4294967295, 4294967296,
      ];
      // Every ordered pair (covers the pair path's intra-pair length mix), plus
      // odd-length arrays that force the scalar tail after a pipelined pair.
      for (var a = 0; a < edges.length; a++) {
        for (var b = 0; b < edges.length; b++) {
          checkArray([edges[a], edges[b]]);
        }
      }
      checkArray(edges); // 18 values — odd tail after pairs
      checkArray([1]); // single value, no pair
      checkArray([1, 2, 3]); // one pair + tail
    });

    test('dense random arrays across the full i64 range', () {
      final rng = Random(0x240F42);
      for (var iter = 0; iter < 4000; iter++) {
        final n = rng.nextInt(33); // include 0-length and odd lengths
        final vals = List.generate(n, (_) {
          switch (rng.nextInt(3)) {
            case 0:
              return rng.nextInt(10000); // short
            case 1:
              return rng.nextInt(1 << 31); // mid
            default:
              final hi = rng.nextInt(1 << 32);
              final lo = rng.nextInt(1 << 32);
              return (hi << 32) | lo; // full range, may be negative
          }
        });
        checkArray(vals);
      }
    });
  });

  group('selectBytes string/number encoder fuzz', () {
    late Directory dir;
    late Database db;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('resq_enc_fuzz_');
      db = await Database.open('${dir.path}/t.db');
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    // Round-trip correctness: selectBytes output must be valid JSON that
    // decodes back to the inserted values. Exercises the string escaper (raw
    // control bytes, named escapes, `\uXXXX`, multibyte UTF-8) and the number
    // formatters. Numbers compare by value, not spelling.
    test('random mixed-type rows decode back to the inserted values', () async {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, i INTEGER, d REAL, '
        's TEXT, b BLOB)',
      );

      final rng = Random(0xF0FA11);
      String randomString() {
        final n = rng.nextInt(24);
        final sb = StringBuffer();
        for (var i = 0; i < n; i++) {
          final pick = rng.nextInt(10);
          if (pick < 5) {
            sb.writeCharCode(0x20 + rng.nextInt(0x5f)); // printable ASCII
          } else if (pick < 7) {
            const specials = ['"', '\\', '\n', '\r', '\t', '\b', '\f', ''];
            sb.write(specials[rng.nextInt(specials.length)]);
          } else if (pick < 9) {
            sb.write(['é', 'ü', '中', '文', '😀', 'Ω'][rng.nextInt(6)]);
          } else {
            sb.writeCharCode(rng.nextInt(0x20)); // raw control byte
          }
        }
        return sb.toString();
      }

      final rows = <List<Object?>>[];
      for (var r = 0; r < 200; r++) {
        final blobLen = rng.nextInt(80);
        rows.add([
          r,
          rng.nextBool()
              ? (rng.nextInt(1 << 32) - (1 << 31))
              : (rng.nextBool() ? -9223372036854775808 : 9223372036854775807),
          rng.nextBool()
              ? rng.nextDouble() * 1e6 - 5e5
              : (rng.nextInt(1000) - 500).toDouble(),
          randomString(),
          Uint8List.fromList(List.generate(blobLen, (_) => rng.nextInt(256))),
        ]);
      }
      await db.executeBatch(
        'INSERT INTO t(id, i, d, s, b) VALUES (?, ?, ?, ?, ?)',
        rows,
      );

      const sql = 'SELECT id, i, d, s, b FROM t ORDER BY id';
      final bytesResult = await db.selectBytes(sql);
      // A malformed escape would make this decode throw.
      final decoded = jsonDecode(utf8.decode(bytesResult.bytes)) as List;

      expect(decoded, hasLength(rows.length));
      for (var r = 0; r < rows.length; r++) {
        final got = decoded[r] as Map<String, dynamic>;
        final want = rows[r];
        expect(got['id'], want[0], reason: 'id mismatch row $r');
        expect(got['i'], want[1], reason: 'int mismatch row $r');
        expect(
          (got['d'] as num).toDouble(),
          want[2] as double,
          reason: 'double mismatch row $r',
        );
        expect(got['s'], want[3], reason: 'string mismatch row $r');
        expect(
          got['b'],
          base64.encode(want[4] as Uint8List),
          reason: 'blob mismatch row $r',
        );
      }
    });

    test('long string boundary output matches dart:convert exactly', () async {
      await db.execute('CREATE TABLE strings(id INTEGER PRIMARY KEY, s TEXT)');

      const safeAlphabet =
          'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_';
      String safeAscii(int length) => List.generate(
        length,
        (i) => safeAlphabet[i % safeAlphabet.length],
      ).join();

      final values = <String>[];
      const lengths = [
        0,
        1,
        15,
        16,
        17,
        31,
        32,
        33,
        47,
        48,
        49,
        63,
        64,
        65,
        79,
        80,
        81,
        95,
        96,
        97,
        127,
        128,
        129,
        255,
        256,
        257,
        1024,
      ];

      for (final length in lengths) {
        final safe = safeAscii(length);
        values.add(safe);
        if (length > 0) {
          for (final position in {
            0,
            if (length > 15) 15,
            if (length > 16) 16,
            length - 1,
          }) {
            for (final special in const ['"', '\\', '\u0001']) {
              values.add(
                '${safe.substring(0, position)}$special'
                '${safe.substring(position + 1)}',
              );
            }
          }
        }
      }

      values.addAll(['日本語' * 64, 'éü中文Ω' * 64, '${'日本語' * 24}"${'中文' * 40}']);

      await db.executeBatch('INSERT INTO strings(id, s) VALUES (?, ?)', [
        for (var i = 0; i < values.length; i++) [i, values[i]],
      ]);

      final actual = utf8.decode(
        (await db.selectBytes('SELECT s FROM strings ORDER BY id')).bytes,
      );
      final expected = jsonEncode([
        for (final value in values) {'s': value},
      ]);
      expect(actual, expected);
    });
  });
}
