/// [EXP-234] How a BLOB write parameter travels from the main isolate to the
/// writer isolate.
///
/// Isolates share no mutable memory, so a `Uint8List` param has to be handed
/// off. [wrapBlobParams], called where write requests are built on the main
/// isolate, picks one of two routes per blob:
///
/// - **direct** — blobs under [blobParamTransferThreshold] stay in the param
///   list as-is and ride the `SendPort.send` object-graph copy like every
///   other param value.
/// - **wrapped** — larger blobs are replaced by a `TransferableTypedData`:
///   a VM container whose constructor copies the bytes into malloc'd memory
///   outside the GC heap, and which a send then hands to the receiver by
///   ownership transfer instead of another copy. [unwrapBlobParams] on the
///   writer turns it back into a `Uint8List` view via `materialize()` before
///   binding.
///
/// Both routes copy the payload exactly once, on the main isolate — the win is
/// not a removed copy, it is where the copy lands. For
/// `db.execute('INSERT INTO doc(body) VALUES (?)', [blob])`:
///
///   direct:  blob --graph copy--> GC-heap TypedData --> writer
///            --> allocateParams arena --> SQLite page
///   wrapped: blob --memcpy--> malloc'd buffer --ownership move--> writer
///            materialize() view --> allocateParams arena --> SQLite page
///
/// Why the destination matters (Dart SDK `runtime/vm/object_graph_copy.cc`):
/// the direct route's graph copy allocates its destination on the shared GC
/// heap, so every in-flight blob is live young-generation data that the GC's
/// copying young-generation collector (the "scavenger") must drag through
/// each collection — and each collection safepoints the whole isolate group,
/// including the writer mid-step, which the serialized request/reply protocol
/// converts directly into write latency. A blob too large for the copier's
/// fast-path new-space allocation also aborts onto the slow path
/// (`CopyTypedDataBaseWithSafepointChecks`), which restarts the copy and
/// memmoves in `kChunkSize` (100 KB) chunks with a safepoint poll between
/// chunks — the send-side transfer of a multi-MB blob then costs roughly
/// double a single plain memcpy of the same bytes. The wrapped route's buffer
/// (`TransferableTypedData_factory`, Dart SDK `runtime/lib/isolate.cc`) is
/// invisible to the GC, its send is a constant-time ownership move, and
/// `materialize()` is a zero-copy view over the same buffer (single-use).
///
/// `TransferableTypedData.fromList` copies rather than takes — it does *not*
/// neuter the caller's list — so the public contract (the caller keeps its
/// blob) is preserved.
///
/// Evidence and measurements: experiments/234-blob-param-transfer.md and
/// benchmark/experiments/blob_param_mechanism_proof.dart.
library;

import 'dart:collection';
import 'dart:isolate';
import 'dart:typed_data';

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
/// 256 KB by design — the size at which a single blob's malloc+finalizer wrap
/// cost is repaid by the graph copy it avoids. (This is the write-side *wrap*
/// threshold; it is distinct from the read-side *sacrifice* decision, which
/// exp 246 moved onto mutable slot count rather than bytes.) Set on the main
/// isolate, where the wrapping decision is made. Internal (not part of the
/// public API surface); mutable so the A/B harness can force the baseline lane
/// by raising it above every tested payload.
int blobParamTransferThreshold = 256 * 1024;

/// Wrap large `Uint8List` blob params in `TransferableTypedData` so their
/// one isolate-hop copy lands in malloc'd external memory (then moves by
/// ownership transfer) instead of riding the graph copy onto the GC heap.
///
/// [EXP-243] Identity-aware: a buffer referenced more than once shares **one**
/// wrapper, referenced at all its positions (the "table protocol"). The graph
/// copier then sends that wrapper once (identity preserved), the writer
/// materializes it once, and it is never duplicated into N external copies.
///
/// Returns [params] unchanged (no allocation) when no entry qualifies — the
/// overwhelmingly common case.
List<Object?> wrapBlobParams(List<Object?> params) {
  final threshold = blobParamTransferThreshold;
  if (!_hasLargeBlob(params, threshold)) return params;
  return _wrapShared(params, _newWrapCache(), threshold);
}

/// [EXP-243] Envelope-level variant for a coalesced write group
/// (`MultiExecuteRequest`). Shares one wrapper per unique backing buffer across
/// **all** the group's writes, so a buffer reused across writes crosses as a
/// single `TransferableTypedData` referenced by every occurrence. Returns
/// [writes] unchanged (no allocation) when nothing qualifies.
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

/// True if [params] holds any `Uint8List` at or above [threshold]. Fast
/// pre-scan that keeps the common no-large-blob path allocation-free.
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

/// Wrap each large blob, sharing one wrapper per unique backing buffer via
/// [cache] (`putIfAbsent` on an identity map). Distinct buffers each get their
/// own wrapper; an aliased buffer reuses its wrapper at every position.
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
/// views before binding. [cache] dedups by wrapper identity so a wrapper shared
/// across positions (or, for a coalesced group, across writes) is materialized
/// **exactly once** — a second `materialize()` on the same wrapper would throw.
/// A caller processing one param list may omit [cache] (a local one is made);
/// a caller spanning multiple lists (`_handleMultiExecute`) must pass one shared
/// cache. Returns [params] unchanged (no allocation) when nothing was wrapped.
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
