# Experiment 234: Zero-copy blob parameter transfer via TransferableTypedData

**Date:** 2026-07-18
**Status:** Accepted
**Direction:** `parameter-encoding-and-binding`
**Benchmark Run:** none — focused
  [`benchmark/experiments/blob_param_write_ab.dart`](../benchmark/experiments/blob_param_write_ab.dart)
  (end-to-end INSERT) and
  [`benchmark/experiments/blob_param_transport_ab.dart`](../benchmark/experiments/blob_param_transport_ab.dart)
  (isolated transport); raw pass tables in
  [`benchmark/results/2026-07-18T13-10-00Z-exp234-blob-param-transfer.md`](../benchmark/results/2026-07-18T13-10-00Z-exp234-blob-param-transfer.md).
  No release-suite run because no current release lane isolates large-blob
  parameter transfer; the focused harnesses are the durable gate.

## Problem

The `parameter-encoding-and-binding` direction still carried an open question:
*"Are there remaining blob-heavy parameter shapes where encoding, not SQLite
stepping, dominates?"* The single-row and batch **text** bind paths were
tightened by exp 125/149/186/187, and the numeric batch scan by exp 113/226,
but the **blob** arm was never measured in isolation.

A `Uint8List` blob param on the write path is copied three times before it
lands in a database page:

1. **main → writer isolate**, when `SendPort.send(ExecuteRequest)` deep-copies
   the request graph — including the blob bytes — through the VM's C++ object
   serializer;
2. **writer → native param arena**, in `allocateParams` (`view.setRange`);
3. **arena → SQLite b-tree page**, inside `sqlite3_step`.

Copies (2) and (3) are unavoidable (the arena must outlive the bind, and SQLite
owns its pages). Copy (1) is the tempting target: `TransferableTypedData` moves
typed-data bytes across a `SendPort` without the serializer's deep copy.

[Exp 005](005-dart-binary-codec-transferable-typed-data.md) rejected a Dart
binary **codec** for structured map **results** — but that lost because
encoding row structure in Dart is slower than the VM serializer, not because
`TransferableTypedData` is slow. A raw `Uint8List` **parameter** has no
structure to encode, so it is a distinct question that exp 005 never answered.

## Hypothesis

For a large blob write param, wrapping the `Uint8List` in
`TransferableTypedData` before `SendPort.send` (and materializing it on the
writer before `allocateParams`) removes the serializer's deep copy on the
main→writer hop. The win should appear where that copy is a material fraction
of the whole INSERT, and wash out where the SQLite WAL write dominates.

Acceptance: two order-flipped end-to-end passes must reproduce same-direction
candidate-faster on a large-blob single-row INSERT, above the noise floor
established by same-code-path controls below the wrap threshold.

## Approach

New internal helper
[`lib/src/writer/blob_param_transfer.dart`](../lib/src/writer/blob_param_transfer.dart):

- `wrapBlobParams(params)` — on the main isolate, replace any `Uint8List` with
  `length >= blobParamTransferThreshold` (256 KB) by
  `TransferableTypedData.fromList([blob])`. Returns the **input list unchanged,
  with no allocation**, when nothing qualifies — the common case, so non-blob
  and small-blob writes are untouched.
- `unwrapBlobParams(params)` — on the writer isolate, materialize any
  `TransferableTypedData` back to `Uint8List` before binding. Also a no-op when
  nothing was wrapped.

Wrapping is wired into the `ExecuteRequest` and `QueryRequest` constructors
(both built on the main isolate before send); unwrapping into `_handleExecute`
and `_handleTxQuery` on the writer. `fromList` copies its source into external
memory but does **not** neuter the caller's list, so the public contract (the
caller keeps its blob) holds. The threshold is internal (not exported) and
matches the read-side `sacrificeByteThreshold` (256 KB) by design.

Deliberately conservative: the batch (`BatchRequest`) and coalesced-write
(`MultiExecuteRequest`) paths stay on the direct copy for now — the single
large blob (an image / document / serialized payload) is the primary, cleanest
shape and the one this run measures.

## Results

Single-row BLOB INSERT, median µs/INSERT, two order-flipped passes
(representative clean pass; full reproduction table in the results file):

| Size | Δ P1 (base→cand) | Δ P2 (cand→base) | Read |
|---|---:|---:|---|
| 64 KB (control) | +4.2% | +3.3% | direct path — noise |
| 128 KB (control) | −2.9% | +4.1% | direct path — noise |
| **256 KB** | **−16.4%** | **−22.7%** | wrapped — reproduced win |
| **512 KB** | **−10.4%** | **−11.8%** | wrapped — reproduced win |
| 1 MB | +0.8% | −4.0% | WAL-write dominated — neutral |

Across ~7 recorded passes, **every** 256 KB and 512 KB leg is candidate-faster
(12+/12 and 8/8 negative); the sub-threshold controls flip sign across the
order flip (the exp 177 drift signature), confirming the wins clear the
~±8–15% noise floor by reproducing same-direction. The transport
microbenchmark isolates the cause: the transferable hop is −22.6% at 256 KB but
**+22.7% (slower) at 64 KB** (wrap overhead) and neutral at 4 MB (`fromList`'s
own copy catches up) — exactly the shape that justifies a 256 KB threshold.

Interpretation: for **256 KB–512 KB single-row blob INSERTs** — thumbnails,
documents, serialized protobuf/JSON blobs, small media — replacing the VM
serializer's deep copy with a `TransferableTypedData` move is a **~15–20%
end-to-end** speedup. Below 256 KB the wrap does not pay back (kept on the
direct path); at ≥ 1 MB the SQLite WAL write dominates and the effect washes
out. Non-blob and sub-threshold writes are structurally unaffected (fast-path
returns the list unchanged).

## Outcome

**Accepted (in review).** A contained, threshold-gated ~15–20% win on
moderate-large single-row blob INSERTs, in an active direction whose open
question this consumes. The mechanism (raw-byte transfer beats the VM
serializer; `fromList` is cheap and non-neutering) and the boundaries (64 KB
regresses, 1 MB+ is disk-dominated) are both directly measured.

Would reopen the batch/coalesced-write blob paths if a blob-heavy
`executeBatch` workload shows the same transfer fraction; would revisit the
256 KB threshold if a production profile shows a different blob-size
distribution.

## Test plan

- [x] `dart analyze` on `lib/` (clean)
- [x] `dart test test/database_test.dart -j 1` (55/55, incl. new
  large-blob-survives-TransferableTypedData round-trip test on execute + tx.select)
- [x] focused end-to-end A/B, interleaved + order-flipped, ~7 passes
- [x] transport microbenchmark isolating the main→writer copy
- [x] `dart run benchmark/finalize_experiment.dart --experiment=experiments/234-blob-param-transfer.md`
