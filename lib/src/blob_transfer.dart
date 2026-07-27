/// How BLOBs cross isolate boundaries.
///
/// A `Uint8List` is the one result/param value that `SendPort.send` must copy
/// byte for byte (strings and numbers are shared by reference), so large blobs
/// in either direction are wrapped in `TransferableTypedData`: the same single
/// copy, but into malloc'd external memory the GC never traces, followed by an
/// ownership move across the hop instead of a graph copy.
///
/// The whole system:
///
/// - **main → writer (params):** [wrapBlobParams] / [wrapBlobParamsGroup] wrap
///   blobs ≥ [blobParamTransferThreshold]; the writer restores them with
///   [unwrapBlobParams] before binding.
/// - **worker → main (result cells):** the decode loop (query_decoder.dart)
///   wraps cells ≥ [blobCellTransferThreshold]; main restores them with
///   [materializeTransferableBlobCells] at each receive boundary.
///
/// Mechanism, measurements, and the bytes-vs-slots threshold split:
/// doc/arch/cross-isolate-data-transfer.md. Experiments: 234 (params),
/// 236 (cells), 243 (aliased params).
library;

import 'dart:collection';
import 'dart:isolate';
import 'dart:typed_data';

export 'row.dart' show materializeTransferableBlobCells;

/// Minimum blob size (bytes) to route through `TransferableTypedData`.
///
/// The win is a hump, so this is a floor with deliberately no ceiling:
///
/// - Below the floor the wrap loses: a small blob fits the graph copier's
///   fast path (one new-space allocation plus a single unchunked memmove),
///   while the wrap still pays malloc + finalizer + materialize bookkeeping.
/// - Around the floor, transport and GC cost are a material slice of the
///   whole insert — this is where the win peaks.
/// - Well above it the relative win washes out: SQLite's WAL write dominates
///   the insert, and very large payloads allocate straight to old space,
///   skipping the new-space churn that drives the win. But it never reverses,
///   and the wrap still trims main-isolate blocking — so oversized blobs keep
///   the wrap rather than getting an upper cutoff.
///
/// 256 KB by design — the size at which a blob's malloc+finalizer wrap cost is
/// repaid by the graph copy it avoids. Mutable so a benchmark can force the
/// unwrapped lane.
int blobParamTransferThreshold = 256 * 1024;

/// Minimum blob-cell size for the worker→main direction: result cells at or
/// above this decode straight into `TransferableTypedData` instead of a heap
/// `Uint8List` (see query_decoder.dart's decode loops).
///
/// A const define, not a variable like [blobParamTransferThreshold]: the
/// decode loop runs on worker isolates, which never see a main-isolate
/// assignment, so only a compile-time value reaches every isolate.
const int blobCellTransferThreshold = int.fromEnvironment(
  'RESQLITE_BLOB_CELL_TRANSFER_THRESHOLD',
  defaultValue: 256 * 1024,
);

/// Wrap large `Uint8List` blob params in `TransferableTypedData` so their
/// one isolate-hop copy lands in malloc'd external memory (then moves by
/// ownership transfer) instead of riding the graph copy onto the GC heap.
///
/// A buffer referenced more than once shares one wrapper, so aliasing survives
/// the hop instead of duplicating into N external copies. Returns [params]
/// unchanged when no entry qualifies.
List<Object?> wrapBlobParams(List<Object?> params) {
  final threshold = blobParamTransferThreshold;
  if (!_hasLargeBlob(params, threshold)) return params;
  return _wrapShared(params, _newWrapCache(), threshold);
}

/// As [wrapBlobParams], but sharing wrappers across a whole coalesced group so
/// a buffer reused between writes still crosses once.
List<({String sql, List<Object?> params})> wrapBlobParamsGroup(
  List<({String sql, List<Object?> params})> writes,
) {
  final threshold = blobParamTransferThreshold;
  var anyLarge = false;
  for (final w in writes) {
    if (_hasLargeBlob(w.params, threshold)) {
      anyLarge = true;
      break;
    }
  }
  if (!anyLarge) return writes;
  final cache = _newWrapCache(); // shared across the whole envelope
  return [
    for (final w in writes)
      (sql: w.sql, params: _wrapShared(w.params, cache, threshold)),
  ];
}

/// Pre-scan that keeps the common no-large-blob path allocation-free.
bool _hasLargeBlob(List<Object?> params, int threshold) {
  for (final value in params) {
    if (value is Uint8List && value.length >= threshold) return true;
  }
  return false;
}

Map<Uint8List, TransferableTypedData> _newWrapCache() =>
    HashMap<Uint8List, TransferableTypedData>(
      equals: identical,
      hashCode: identityHashCode,
    );

/// Wraps each large blob, reusing [cache]'s wrapper for a repeated buffer.
List<Object?> _wrapShared(
  List<Object?> params,
  Map<Uint8List, TransferableTypedData> cache,
  int threshold,
) {
  List<Object?>? out;
  for (var i = 0; i < params.length; i++) {
    final value = params[i];
    if (value is Uint8List && value.length >= threshold) {
      out ??= List<Object?>.of(params);
      out[i] = cache[value] ??= TransferableTypedData.fromList([value]);
    }
  }
  return out ?? params;
}

/// Materialize any `TransferableTypedData` blob params back into `Uint8List`
/// views before binding.
///
/// A second `materialize()` on the same wrapper throws, so a caller spanning
/// several param lists — a coalesced group — must pass one shared [cache].
List<Object?> unwrapBlobParams(
  List<Object?> params, [
  Map<TransferableTypedData, Uint8List>? cache,
]) {
  List<Object?>? out;
  for (var i = 0; i < params.length; i++) {
    final value = params[i];
    if (value is TransferableTypedData) {
      out ??= List<Object?>.of(params);
      cache ??= HashMap<TransferableTypedData, Uint8List>(
        equals: identical,
        hashCode: identityHashCode,
      );
      out[i] = cache[value] ??= value.materialize().asUint8List();
    }
  }
  return out ?? params;
}
