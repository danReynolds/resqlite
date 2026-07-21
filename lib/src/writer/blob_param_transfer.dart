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
/// Matches the read-side `sacrificeByteThreshold` (256 KB) by design. Set on
/// the main isolate, where the wrapping decision is made. Internal (not part
/// of the public API surface); mutable so the A/B harness can force the
/// baseline lane by raising it above every tested payload.
int blobParamTransferThreshold = 256 * 1024;

/// Wrap large `Uint8List` blob params in `TransferableTypedData` so their
/// one isolate-hop copy lands in malloc'd external memory (then moves by
/// ownership transfer) instead of riding the graph copy onto the GC heap.
/// Returns [params] unchanged (no allocation) when no entry qualifies — the
/// overwhelmingly common case.
List<Object?> wrapBlobParams(List<Object?> params) {
  final threshold = blobParamTransferThreshold;
  List<Object?>? wrapped;
  for (var i = 0; i < params.length; i++) {
    final value = params[i];
    if (value is Uint8List && value.length >= threshold) {
      wrapped ??= List<Object?>.of(params);
      wrapped[i] = TransferableTypedData.fromList([value]);
    }
  }
  return wrapped ?? params;
}

/// Materialize any `TransferableTypedData` blob params back into `Uint8List`
/// on the writer isolate before binding. Returns [params] unchanged (no
/// allocation) when nothing was wrapped.
List<Object?> unwrapBlobParams(List<Object?> params) {
  List<Object?>? unwrapped;
  for (var i = 0; i < params.length; i++) {
    final value = params[i];
    if (value is TransferableTypedData) {
      unwrapped ??= List<Object?>.of(params);
      unwrapped[i] = value.materialize().asUint8List();
    }
  }
  return unwrapped ?? params;
}

/// [EXP-237] Batch (`executeBatch`) variant of [wrapBlobParams]: wrap every
/// qualifying blob across all parameter sets so a blob-heavy `executeBatch`
/// crosses to the writer through `TransferableTypedData` instead of the
/// object-graph copy — the exp 234 mechanism, applied per set.
///
/// Rebuilds only the sets that actually changed and only the outer list when at
/// least one did, so a batch with no large blob (the common case) returns the
/// input untouched with no allocation, exactly like [wrapBlobParams].
List<List<Object?>> wrapBlobParamSets(List<List<Object?>> paramSets) {
  List<List<Object?>>? wrapped;
  for (var i = 0; i < paramSets.length; i++) {
    final set = paramSets[i];
    final wrappedSet = wrapBlobParams(set);
    if (!identical(wrappedSet, set)) {
      wrapped ??= List<List<Object?>>.of(paramSets);
      wrapped[i] = wrappedSet;
    }
  }
  return wrapped ?? paramSets;
}

/// [EXP-237] Batch variant of [unwrapBlobParams]: materialize any wrapped blob
/// in any parameter set back into `Uint8List` on the writer before binding.
/// Returns [paramSets] unchanged (no allocation) when nothing was wrapped.
List<List<Object?>> unwrapBlobParamSets(List<List<Object?>> paramSets) {
  List<List<Object?>>? unwrapped;
  for (var i = 0; i < paramSets.length; i++) {
    final set = paramSets[i];
    final unwrappedSet = unwrapBlobParams(set);
    if (!identical(unwrappedSet, set)) {
      unwrapped ??= List<List<Object?>>.of(paramSets);
      unwrapped[i] = unwrappedSet;
    }
  }
  return unwrapped ?? paramSets;
}
