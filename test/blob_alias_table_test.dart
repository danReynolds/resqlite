// [EXP-243] Write-side blob aliasing (table protocol): wrapBlobParams /
// wrapBlobParamsGroup wrap each large blob, but a buffer referenced N times
// shares ONE TransferableTypedData (referenced at every position) instead of
// being duplicated into N external copies. unwrapBlobParams materializes each
// wrapper exactly once (dedup by identity), so a shared wrapper — including one
// spanning multiple writes of a coalesced group — is not double-materialized.
import 'dart:isolate';
import 'dart:typed_data';

import 'package:resqlite/src/blob_transfer.dart';
import 'package:test/test.dart';

Uint8List bigOf(int seed) =>
    Uint8List.fromList(List.generate(300 * 1024, (i) => (i + seed) & 0xFF));

void main() {
  group('wrapBlobParams shared-wrapper (table protocol)', () {
    test('distinct large blobs get distinct wrappers', () {
      final a = bigOf(1), b = bigOf(2);
      final out = wrapBlobParams([a, b, 42]);
      expect(out[0], isA<TransferableTypedData>());
      expect(out[1], isA<TransferableTypedData>());
      expect(out[0], isNot(same(out[1])));
      expect(out[2], 42);
    });

    test('the SAME blob twice shares ONE wrapper', () {
      final blob = bigOf(1);
      final out = wrapBlobParams([blob, blob]);
      expect(out[0], isA<TransferableTypedData>());
      expect(out[1], same(out[0])); // one wrapper, referenced twice
    });

    test('no large blob → same list, no allocation', () {
      final params = <Object?>[1, 'x', Uint8List(1024)];
      expect(wrapBlobParams(params), same(params));
    });
  });

  group('wrapBlobParamsGroup envelope sharing', () {
    test('blob reused across writes shares one wrapper across the group', () {
      final shared = bigOf(1);
      final out = wrapBlobParamsGroup([
        (sql: 'a', params: <Object?>[shared]),
        (sql: 'b', params: <Object?>[shared, 7]),
      ]);
      expect(out[0].params[0], isA<TransferableTypedData>());
      expect(out[1].params[0], same(out[0].params[0])); // shared wrapper
      expect(out[1].params[1], 7);
    });
  });

  group('unwrapBlobParams dedup', () {
    test('a shared wrapper referenced twice materializes once', () {
      final blob = bigOf(3);
      final wrapped = wrapBlobParams([blob, blob]); // [ttd, ttd] (same ttd)
      final out = unwrapBlobParams(wrapped);
      expect(out[0], isA<Uint8List>());
      expect(out[1], same(out[0])); // same materialized view, not re-materialized
      expect(out[0], equals(blob));
    });

    test('shared cache across writes materializes an envelope wrapper once', () {
      final shared = bigOf(4);
      final group = wrapBlobParamsGroup([
        (sql: 'a', params: <Object?>[shared]),
        (sql: 'b', params: <Object?>[shared]),
      ]);
      // Simulate the writer's shared-cache unwrap across the group's writes.
      final cache = <TransferableTypedData, Uint8List>{};
      final u0 = unwrapBlobParams(group[0].params, cache);
      final u1 = unwrapBlobParams(group[1].params, cache); // must not re-materialize
      expect(u0[0], isA<Uint8List>());
      expect(u1[0], same(u0[0]));
      expect(u0[0], equals(shared));
    });
  });
}
