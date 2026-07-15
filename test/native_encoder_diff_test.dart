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
