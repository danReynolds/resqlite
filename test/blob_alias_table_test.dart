// [EXP-243] + [EXP-253] Write-side blob aliasing (table protocol):
// blobTransfer.wrapParams wraps every large blob in a single request, while
// wrapParamsGroup leaves unique blobs on the coalesced envelope's one direct
// graph-copy hop and wraps only identities that repeat. A BlobUnwrapper
// materializes each wrapper exactly once (dedup by identity), so a shared
// wrapper spanning multiple writes is not double-materialized.
import 'dart:isolate';
import 'dart:typed_data';

import 'package:resqlite/src/blob_transfer.dart';
import 'package:test/test.dart';

Uint8List bigOf(int seed) =>
    Uint8List.fromList(List.generate(300 * 1024, (i) => (i + seed) & 0xFF));

void main() {
  group('wrapParams shared-wrapper (table protocol)', () {
    test('distinct large blobs get distinct wrappers', () {
      final a = bigOf(1), b = bigOf(2);
      final out = blobTransfer.wrapParams([a, b, 42]);
      expect(out[0], isA<TransferableTypedData>());
      expect(out[1], isA<TransferableTypedData>());
      expect(out[0], isNot(same(out[1])));
      expect(out[2], 42);
    });

    test('the SAME blob twice shares ONE wrapper', () {
      final blob = bigOf(1);
      final out = blobTransfer.wrapParams([blob, blob]);
      expect(out[0], isA<TransferableTypedData>());
      expect(out[1], same(out[0])); // one wrapper, referenced twice
    });

    test('no large blob → same list, no allocation', () {
      final params = <Object?>[1, 'x', Uint8List(1024)];
      expect(blobTransfer.wrapParams(params), same(params));
    });
  });

  group('wrapParamsGroup envelope sharing', () {
    test('no large blob keeps outer group and param lists unchanged', () {
      final a = <Object?>[1, Uint8List(1024)];
      final b = <Object?>['x'];
      final writes = [(sql: 'a', params: a), (sql: 'b', params: b)];
      final out = blobTransfer.wrapParamsGroup(writes);
      expect(out, same(writes));
      expect(out[0].params, same(a));
      expect(out[1].params, same(b));
    });

    test('distinct large blobs stay direct in a coalesced group', () {
      final a = bigOf(1), b = bigOf(2);
      final writes = [
        (sql: 'a', params: <Object?>[a]),
        (sql: 'b', params: <Object?>[b, 7]),
      ];
      final out = blobTransfer.wrapParamsGroup(writes);
      expect(out, same(writes));
      expect(out[0].params[0], same(a));
      expect(out[1].params[0], same(b));
    });

    test('equal-content distinct identities stay direct', () {
      final a = bigOf(1);
      final b = Uint8List.fromList(a);
      final writes = [
        (sql: 'a', params: <Object?>[a]),
        (sql: 'b', params: <Object?>[b]),
      ];
      final out = blobTransfer.wrapParamsGroup(writes);
      expect(out, same(writes));
      expect(out[0].params[0], same(a));
      expect(out[1].params[0], same(b));
    });

    test('threshold is inclusive and threshold minus one stays direct', () {
      final below = Uint8List(BlobTransfer.paramThreshold - 1);
      final at = Uint8List(BlobTransfer.paramThreshold);
      final writes = [
        (sql: 'a', params: <Object?>[below, at]),
        (sql: 'b', params: <Object?>[below, at]),
      ];
      final out = blobTransfer.wrapParamsGroup(writes);
      expect(out[0].params[0], same(below));
      expect(out[1].params[0], same(below));
      expect(out[0].params[1], isA<TransferableTypedData>());
      expect(out[1].params[1], same(out[0].params[1]));
    });

    test('blob reused across writes shares one wrapper across the group', () {
      final shared = bigOf(1);
      final out = blobTransfer.wrapParamsGroup([
        (sql: 'a', params: <Object?>[shared]),
        (sql: 'b', params: <Object?>[shared, 7]),
      ]);
      expect(out[0].params[0], isA<TransferableTypedData>());
      expect(out[1].params[0], same(out[0].params[0])); // shared wrapper
      expect(out[1].params[1], 7);
    });

    test(
      'mixed group wraps repeated identity but leaves unique blob direct',
      () {
        final shared = bigOf(1), unique = bigOf(2);
        final out = blobTransfer.wrapParamsGroup([
          (sql: 'a', params: <Object?>[shared, unique]),
          (sql: 'b', params: <Object?>[shared]),
        ]);
        expect(out[0].params[0], isA<TransferableTypedData>());
        expect(out[1].params[0], same(out[0].params[0]));
        expect(out[0].params[1], same(unique));
      },
    );

    test('repeat within one group member shares one wrapper', () {
      final shared = bigOf(3);
      final out = blobTransfer.wrapParamsGroup([
        (sql: 'a', params: <Object?>[shared, shared]),
        (sql: 'b', params: <Object?>[7]),
      ]);
      expect(out[0].params[0], isA<TransferableTypedData>());
      expect(out[0].params[1], same(out[0].params[0]));
      expect(out[1].params[0], 7);
    });
  });

  group('unwrap dedup', () {
    test('a shared wrapper referenced twice materializes once', () {
      final blob = bigOf(3);
      final wrapped = blobTransfer.wrapParams([
        blob,
        blob,
      ]); // [ttd, ttd] (same ttd)
      final out = blobTransfer.unwrapParams(wrapped);
      expect(out[0], isA<Uint8List>());
      expect(
        out[1],
        same(out[0]),
      ); // same materialized view, not re-materialized
      expect(out[0], equals(blob));
    });

    test(
      'one unwrapper across writes materializes an envelope wrapper once',
      () {
        final shared = bigOf(4);
        final group = blobTransfer.wrapParamsGroup([
          (sql: 'a', params: <Object?>[shared]),
          (sql: 'b', params: <Object?>[shared]),
        ]);
        // Simulate the writer's one-unwrapper-per-envelope unwrap.
        final unwrapper = blobTransfer.unwrapper();
        final u0 = unwrapper.unwrap(group[0].params);
        final u1 = unwrapper.unwrap(group[1].params); // must not re-materialize
        expect(u0[0], isA<Uint8List>());
        expect(u1[0], same(u0[0]));
        expect(u0[0], equals(shared));
      },
    );

    test('mixed group unwrap restores aliases and keeps unique bytes', () {
      final shared = bigOf(5);
      final unique = bigOf(6);
      final group = blobTransfer.wrapParamsGroup([
        (sql: 'a', params: <Object?>[shared, unique]),
        (sql: 'b', params: <Object?>[shared]),
      ]);
      final unwrapper = blobTransfer.unwrapper();
      final u0 = unwrapper.unwrap(group[0].params);
      final u1 = unwrapper.unwrap(group[1].params);
      expect(u0[0], isA<Uint8List>());
      expect(u1[0], same(u0[0]));
      expect(u0[0], equals(shared));
      expect(u0[1], same(unique));
      expect(u0[1], equals(unique));
    });
  });
}
