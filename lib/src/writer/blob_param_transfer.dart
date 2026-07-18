/// [EXP-234] Zero-copy transfer of large BLOB write parameters across the
/// main -> writer isolate hop.
///
/// A `Uint8List` blob param placed in a `List<Object?>` and sent through
/// `SendPort.send` is deep-copied by the VM's C++ serializer. Wrapping a large
/// blob in `TransferableTypedData` moves the bytes to the receiver without that
/// serializer copy (`materialize()` hands back a view over the transferred
/// external buffer). `TransferableTypedData.fromList` copies the source into an
/// external buffer but does *not* neuter the caller's list, so the public API
/// contract (the caller keeps ownership of the blob it passed) is preserved.
///
/// Small blobs are left on the direct path: below the threshold the wrap/
/// materialize bookkeeping is not worth it and the focused transport A/B shows
/// the mechanism only reliably wins for large payloads.
library;

import 'dart:isolate';
import 'dart:typed_data';

/// Minimum blob size (bytes) to route through `TransferableTypedData`.
///
/// Below this, blobs stay on the direct `SendPort` copy: the focused A/B
/// (`benchmark/experiments/blob_param_write_ab.dart`) shows the transferable
/// hop only reproduces an end-to-end win once the blob is a material fraction
/// of the write (~256 KB–512 KB); smaller blobs do not pay back the wrap.
/// Matches the read-side `sacrificeByteThreshold` (256 KB) by design.
///
/// Set on the main isolate, where the wrapping decision is made. Internal
/// (not part of the public API surface); mutable so the A/B harness can force
/// the baseline lane by raising it above every tested payload.
int blobParamTransferThreshold = 256 * 1024;

/// Wrap large `Uint8List` blob params in `TransferableTypedData` for a
/// zero-serializer-copy isolate hop. Returns [params] unchanged (no
/// allocation) when no entry qualifies — the overwhelmingly common case.
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
