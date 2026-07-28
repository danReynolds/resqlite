/// How BLOBs cross isolate boundaries.
///
/// A `Uint8List` is the one result/param value that `SendPort.send` must copy
/// byte for byte (strings and numbers are shared by reference), so large blobs
/// in either direction are wrapped in `TransferableTypedData`: the same single
/// copy, but into malloc'd external memory the GC never traces, followed by an
/// ownership move across the hop instead of a graph copy.
///
/// The whole system, through [blobTransfer]:
///
/// - **main → writer (params):** [BlobTransfer.wrapParams] wraps blobs ≥
///   [BlobTransfer.paramThreshold]. [BlobTransfer.wrapParamsGroup] wraps only
///   repeated blob identities in a coalesced envelope; unique buffers already
///   cross in one graph-copy hop. The writer restores wrappers with
///   [BlobTransfer.unwrapParams], or one [BlobUnwrapper] spanning a coalesced
///   envelope.
/// - **worker → main (result cells):** the decode loop (query_decoder.dart)
///   wraps cells ≥ [BlobTransfer.cellThreshold]; main restores them with
///   [BlobTransfer.materializeCells] at each receive boundary.
///
/// Mechanism, measurements, and the bytes-vs-slots threshold split:
/// doc/arch/cross-isolate-data-transfer.md. Experiments: 234 (params),
/// 236 (cells), 243 (aliased params).
library;

import 'dart:collection';
import 'dart:isolate';
import 'dart:typed_data';

import 'row.dart' show materializeTransferableBlobCells;

/// The blob transfer system. See the library doc for the map.
const BlobTransfer blobTransfer = BlobTransfer._();

final class BlobTransfer {
  const BlobTransfer._();

  /// Minimum blob size (bytes) for a *param* to route through
  /// `TransferableTypedData` on its way to the writer.
  ///
  /// The win is a hump, so this is a floor with deliberately no ceiling:
  /// below it the wrap bookkeeping outweighs the graph copy it avoids; well
  /// above it the win washes toward neutral but never reverses. 256 KB is the
  /// measured crossover. Mutable so a benchmark can force the unwrapped lane.
  static int paramThreshold = 256 * 1024;

  /// Minimum blob size (bytes) for a result *cell* to decode straight into
  /// `TransferableTypedData` on the worker (query_decoder.dart's loops).
  ///
  /// A const define, not a variable like [paramThreshold]: the decode loop
  /// runs on worker isolates, which never see a main-isolate assignment, so
  /// only a compile-time value reaches every isolate.
  static const int cellThreshold = int.fromEnvironment(
    'RESQLITE_BLOB_CELL_TRANSFER_THRESHOLD',
    defaultValue: 256 * 1024,
  );

  /// Wraps large blob params so their one isolate-hop copy lands in external
  /// memory (then moves by ownership transfer) instead of riding the graph
  /// copy onto the GC heap.
  ///
  /// A buffer referenced more than once shares one wrapper, so aliasing
  /// survives the hop instead of duplicating into N external copies. Returns
  /// [params] unchanged when no entry qualifies.
  List<Object?> wrapParams(List<Object?> params) {
    final threshold = paramThreshold;
    if (!_hasLargeBlob(params, threshold)) return params;
    return _wrapShared(params, _newWrapCache(), threshold);
  }

  /// Routes a coalesced group according to the cost topology of its one
  /// isolate hop.
  ///
  /// Unique large buffers stay on the direct graph-copy path: unlike separate
  /// [wrapParams] sends, a group pays one copy before any of its writes run, so
  /// there is no per-send heap churn interleaved with writer SQLite work.
  /// Repeated identities still use one shared wrapper, preserving the
  /// alias-table win and avoiding the graph copier's large-buffer slow path.
  /// Returns [writes] unchanged when no large buffer repeats.
  List<({String sql, List<Object?> params})> wrapParamsGroup(
    List<({String sql, List<Object?> params})> writes,
  ) {
    final threshold = paramThreshold;
    final repeated = _repeatedLargeBlobs(writes, threshold);
    if (repeated == null) return writes;
    final cache = _newWrapCache(); // shared across the whole envelope
    return [
      for (final w in writes)
        (
          sql: w.sql,
          params: _wrapShared(w.params, cache, threshold, eligible: repeated),
        ),
    ];
  }

  /// One unwrapper per received envelope; see [BlobUnwrapper].
  BlobUnwrapper unwrapper() => BlobUnwrapper._();

  /// Restores wrapped params in a single-list envelope. A coalesced group
  /// must use one [unwrapper] across all its lists instead — a wrapper shared
  /// across the group is single-use (see [BlobUnwrapper]).
  List<Object?> unwrapParams(List<Object?> params) =>
      BlobUnwrapper._().unwrap(params);

  /// Restores wrapped result cells to `Uint8List` views at a main-isolate
  /// receive boundary. No-op unless the decode marked the result as carrying
  /// wrapped cells.
  void materializeCells(List<Map<String, Object?>> rows) =>
      materializeTransferableBlobCells(rows);
}

/// Restores wrapped params on the receiving isolate — one instance per
/// message envelope.
///
/// The per-wrapper dedup here is *correctness*, not caching: an aliased blob
/// arrives as ONE wrapper referenced at every position (possibly spanning a
/// coalesced group's writes), and `materialize()` is single-use — a second
/// call on the same wrapper throws. So each wrapper is materialized exactly
/// once and every other occurrence receives that same view — which also
/// restores the sender's aliasing: positions that shared a buffer going in
/// share one `Uint8List` coming out. Hence the lifetime rule: one unwrapper
/// spans the whole envelope, and never outlives it. See the write-envelope
/// rule in doc/arch/cross-isolate-data-transfer.md §5.
final class BlobUnwrapper {
  BlobUnwrapper._();

  /// Wrapper → its one materialized view (see class doc: dedup for
  /// correctness). Lazy so an envelope with nothing wrapped allocates nothing.
  Map<TransferableTypedData, Uint8List>? _views;

  /// Returns [params] with any wrapped blob restored to a `Uint8List` view,
  /// or [params] itself when nothing was wrapped.
  List<Object?> unwrap(List<Object?> params) {
    List<Object?>? out;
    for (var i = 0; i < params.length; i++) {
      final value = params[i];
      if (value is TransferableTypedData) {
        out ??= List<Object?>.of(params);
        final views = _views ??= HashMap<TransferableTypedData, Uint8List>(
          equals: identical,
          hashCode: identityHashCode,
        );
        out[i] = views[value] ??= value.materialize().asUint8List();
      }
    }
    return out ?? params;
  }
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

/// Returns the identities that occur more than once among qualifying blobs,
/// or null when the group can stay entirely on its one direct graph-copy hop.
Set<Uint8List>? _repeatedLargeBlobs(
  List<({String sql, List<Object?> params})> writes,
  int threshold,
) {
  HashSet<Uint8List>? seen;
  HashSet<Uint8List>? repeated;
  for (final write in writes) {
    for (final value in write.params) {
      if (value is! Uint8List || value.length < threshold) continue;
      final identities = seen ??= _newBlobIdentitySet();
      if (!identities.add(value)) {
        (repeated ??= _newBlobIdentitySet()).add(value);
      }
    }
  }
  return repeated;
}

HashSet<Uint8List> _newBlobIdentitySet() =>
    HashSet<Uint8List>(equals: identical, hashCode: identityHashCode);

/// Wraps each large blob, reusing [cache]'s wrapper for a repeated buffer.
List<Object?> _wrapShared(
  List<Object?> params,
  Map<Uint8List, TransferableTypedData> cache,
  int threshold, {
  Set<Uint8List>? eligible,
}) {
  List<Object?>? out;
  for (var i = 0; i < params.length; i++) {
    final value = params[i];
    if (value is Uint8List &&
        value.length >= threshold &&
        (eligible == null || eligible.contains(value))) {
      out ??= List<Object?>.of(params);
      out[i] = cache[value] ??= TransferableTypedData.fromList([value]);
    }
  }
  return out ?? params;
}
