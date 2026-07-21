# Experiment 234: Zero-copy blob parameter transfer via TransferableTypedData

**Date:** 2026-07-18
**Status:** Accepted
**Direction:** `parameter-encoding-and-binding`
**Benchmark Run:** none — focused
  [`benchmark/experiments/blob_param_write_ab.dart`](../benchmark/experiments/blob_param_write_ab.dart)
  (end-to-end INSERT),
  [`benchmark/experiments/blob_param_transport_ab.dart`](../benchmark/experiments/blob_param_transport_ab.dart)
  (isolated transport), and
  [`benchmark/experiments/blob_param_mechanism_proof.dart`](../benchmark/experiments/blob_param_mechanism_proof.dart)
  (per-claim mechanism attribution, with
  [`blob_param_gc_split.dart`](../benchmark/experiments/blob_param_gc_split.dart)
  for per-lane GC attribution on the real path); raw pass tables in
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

1. **main → writer isolate**, when `SendPort.send(ExecuteRequest)` copies the
   request graph — including the blob bytes — via the VM's object-graph copy
   (Dart SDK `runtime/vm/object_graph_copy.cc`), landing the payload on the
   shared GC heap;
2. **writer → native param arena**, in `allocateParams` (`view.setRange`);
3. **arena → SQLite b-tree page**, inside `sqlite3_step`.

Copies (2) and (3) are unavoidable (the arena must outlive the bind, and SQLite
owns its pages). Copy (1) is the tempting target: `TransferableTypedData`
carries typed-data bytes across a `SendPort` by ownership transfer of a
malloc'd buffer instead of a graph copy onto the heap.

[Exp 005](005-dart-binary-codec-transferable-typed-data.md) rejected a Dart
binary **codec** for structured map **results** — but that lost because
encoding row structure in Dart is slower than the VM serializer, not because
`TransferableTypedData` is slow. A raw `Uint8List` **parameter** has no
structure to encode, so it is a distinct question that exp 005 never answered.

## Hypothesis

For a large blob write param, wrapping the `Uint8List` in
`TransferableTypedData` before `SendPort.send` (and materializing it on the
writer before `allocateParams`) replaces the graph copy on the main→writer hop
with a plain memcpy into external memory plus a constant-time ownership move.
The win should appear where that hop's cost is a material fraction of the
whole INSERT, and wash out where the SQLite WAL write dominates.

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
(both built on the main isolate before send) and into the coalescing pump's
`MultiExecuteRequest` construction (added by the review pass — without it, a
concurrent burst of standalone blob writes, the exact shape the exp 180 pump
exists for, silently fell back to the graph-copy hop); unwrapping into
`_handleExecute`, `_handleTxQuery`, and `_handleMultiExecute` on the writer.
`fromList` copies its source into external memory but does **not** neuter the
caller's list, so the public contract (the caller keeps its blob) holds. The
threshold is internal (not exported) and matches the read-side
`sacrificeByteThreshold` (256 KB) by design.

Two review-pass hardenings on the error paths: exceptions embed the
*unwrapped* params (a spent `TransferableTypedData` cannot cross a `SendPort`,
so an exception carrying `msg.params` was unsendable and killed the writer
isolate — permanent hang), and the writer entrypoint's reply-send falls back
to a stripped exception copy if a payload ever proves unsendable. `_request`
also builds the request before enqueueing its completer, since request
constructors can now throw (native allocation in `fromList`) and a throw after
enqueue would desync FIFO reply matching.

Deliberately conservative: the batch (`BatchRequest`) path stays on the direct
copy for now — the single large blob (an image / document / serialized
payload) is the primary, cleanest shape and the one this run measures.

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
documents, serialized protobuf/JSON blobs, small media — the
`TransferableTypedData` route is a **~15–20% end-to-end** speedup. Below
256 KB the wrap does not pay back (kept on the direct path); at ≥ 1 MB the
SQLite WAL write dominates and the effect washes out. Non-blob and
sub-threshold writes are structurally unaffected (fast-path returns the list
unchanged).

## Mechanism (post-acceptance attribution)

A follow-up deep-dive (VM source reading plus
[`blob_param_mechanism_proof.dart`](../benchmark/experiments/blob_param_mechanism_proof.dart)
and [`blob_param_gc_split.dart`](../benchmark/experiments/blob_param_gc_split.dart))
corrected the mechanism story this experiment originally shipped with. The
PR-era framing — "removes the VM serializer's deep copy" — is wrong in two
ways: since Dart 2.15 same-group sends use an object-graph copy, not the
serializer, and that copy happens **once, on the sender** — there is no
receive-side rebuild. Both routes copy the payload exactly once, on the main
isolate. What actually produces the win, each part measured separately:

- **The copy's destination.** The direct route lands every in-flight blob on
  the shared GC heap, where the scavenger must evacuate it as live
  young-generation data — and every collection safepoints the whole isolate
  group, including the writer mid-step, which the serialized request/reply
  protocol converts directly into write latency. On the real INSERT path
  (isolated single-lane processes under `--verbose_gc`, 300 × 256 KB inserts)
  the direct lane cost 29 GCs / 8.6 ms of pause vs the wrapped lane's
  20 GCs / 1.2 ms — the asymmetry is per-GC cost, not count, because the
  wrapped route's payload lives in malloc'd memory the GC never traces.
- **Copy machinery at large sizes.** `SendPort.send`'s synchronous wall
  scales linearly with blob size (proving the sender-side copy), and blobs
  too large for the copier's fast-path new-space allocation abort onto
  `CopyTypedDataBaseWithSafepointChecks`, which restarts the copy in
  `kChunkSize` (100 KB) safepoint-polled chunks — measured at roughly double
  a plain memcpy at ≥ 1 MB. This is real but matters least where the win is
  biggest: at 256 KB the fast path usually succeeds and `send(blob)` is only
  ~15% over a plain copy.
- **The wrapped route's costs are flat where they must be.** `fromList` is
  one linear memcpy (≈ a plain heap copy), `send` of the wrapper is
  constant-time at every size, `materialize()` is ~1 µs flat from 64 KB to
  4 MB (a view, not a copy), and the writer's arena `setRange` from the
  materialized view is equal-or-faster than from a heap `Uint8List` — no
  cost was shifted to the writer.

Honest residual: summing the directly-attributed send-path and GC-pause
deltas covers part of the end-to-end win; the remainder is second-order
effects of the same heap churn (safepoint stalls landing inside the writer's
SQLite work, allocation slow paths), demonstrated collectively — isolated
single-lane runs reproduce the full win — but not budgeted line-by-line.

This also sharpens the exp 005 contrast: exp 005's codec lost because
encoding *structure* in Dart is slower than the VM's native walk; a raw blob
has no structure, so the only remaining costs are destination and machinery —
both of which the wrap avoids.

## Decision

**Accepted (in review).** A contained, threshold-gated ~15–20% win on
moderate-large single-row blob INSERTs, in an active direction whose open
question this consumes. The mechanism (one copy either way — the wrapped
route lands it in malloc'd memory the GC never traces and moves it in
constant time; `fromList` is cheap and non-neutering) and the boundaries
(64 KB regresses, 1 MB+ is disk-dominated) are both directly measured.

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
- [x] mechanism attribution: per-call cost table (`blob_param_mechanism_proof.dart`,
  two passes) + per-lane GC attribution on the real path
  (`blob_param_gc_split.dart` under `--verbose_gc`, isolated processes)
- [x] `dart run benchmark/finalize_experiment.dart --experiment=experiments/234-blob-param-transfer.md`
