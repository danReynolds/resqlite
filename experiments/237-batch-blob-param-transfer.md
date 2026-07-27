# Experiment 237: batch blob parameter transfer via TransferableTypedData

**Date:** 2026-07-21
**Status:** Rejected
**Direction:** `parameter-encoding-and-binding`
**Benchmark Run:** none — focused
  [`benchmark/experiments/blob_batch_write_ab.dart`](../benchmark/experiments/blob_batch_write_ab.dart)
  (end-to-end blob-heavy `executeBatch`, feature toggled at runtime,
  interleaved order-flipped passes); raw pass tables in
  [`benchmark/results/2026-07-21T15-40-00Z-exp237-batch-blob-transfer.md`](../benchmark/results/2026-07-21T15-40-00Z-exp237-batch-blob-transfer.md).
  No release-suite run because no current release lane isolates large-blob
  parameter transfer; the focused harness is the durable gate.
**Archive:** [`archive/exp-237`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-237)

## Problem

[Exp 234](234-blob-param-transfer.md) accepted a ~15–20% end-to-end win on
256 KB–512 KB **single-row** blob INSERTs by wrapping large `Uint8List` params
in `TransferableTypedData` before the main→writer `SendPort` hop, so the
payload's one copy lands in malloc'd external memory the GC never traces
instead of on the shared young-generation heap. It deliberately left the batch
(`BatchRequest`/`executeBatch`) path on the direct object-graph copy and named
the reopen condition explicitly:

> Would reopen the batch/coalesced-write blob paths if a blob-heavy
> `executeBatch` workload shows the same transfer fraction.

That is the `parameter-encoding-and-binding` direction's standing open question
(`openQuestions[1]`): *does the exp 234 blob-transfer win extend to batch
(`BatchRequest`) writes carrying per-set blobs?* This experiment answers it.

## Hypothesis

A `BatchRequest` carries every parameter set across **one** `SendPort.send`, so
the baseline object-graph copy lands *all* of a batch's blobs on the GC heap in
a single hop — a larger burst of live young-generation data than any single
write produces. If exp 234's mechanism is really "large blobs on the GC heap
are expensive," wrapping each qualifying blob per set should reproduce the
single-row win, and possibly amplify it, on a blob-heavy `executeBatch`.

Acceptance: two order-flipped end-to-end passes must reproduce same-direction
candidate-faster on 256 KB–512 KB blobs, above the sub-threshold control noise
floor — the same bar exp 234 cleared.

## Approach

Extend the exp 234 helper family in
[`lib/src/blob_transfer.dart`](../lib/src/blob_transfer.dart)
with `wrapBlobParamSets` / `unwrapBlobParamSets`, which apply the existing
per-list `wrapBlobParams` / `unwrapBlobParams` across a `List<List<Object?>>`,
rebuilding only the sets that changed and only the outer list when at least one
did (so a no-large-blob batch returns the input untouched, no allocation).
Wrapping is wired into the `BatchRequest` constructor (built on the main
isolate before send); unwrapping into `_handleBatch` on the writer, before
either `executeBatchWrite` or `executeNestedBatchWrite`, since
`allocateBatchParams` requires concrete `Uint8List` blobs. The threshold and
256 KB floor are shared with exp 234; sub-threshold and non-blob batches are
structurally unaffected.

The prototype is byte-correct: a new round-trip test inserts a batch mixing
wrapped (≥ 256 KB) and direct (< 256 KB) blobs, standalone and nested inside a
transaction, and reads every payload back byte-identical.

## Results

Blob-heavy `executeBatch` (30 rows/batch, one blob param each), median µs/row,
two order-flipped passes per run, four runs. Δ is candidate − baseline
(**positive = candidate slower**). Sub-threshold 64/128 KB are same-code-path
controls — the candidate leaves them on the direct path, so their deltas are
pure noise.

| Size | R1 P1 | R1 P2 | R2 P1 | R2 P2 | R3 P1 | R3 P2 | R4 P1 | R4 P2 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 64 KB (ctl) | −2.2% | −41.4% | +112.4% | −29.2% | — | — | — | — |
| 128 KB (ctl) | +10.8% | −6.9% | +0.1% | −4.1% | — | — | — | — |
| **256 KB** | **+16.4%** | **+18.1%** | **+7.6%** | **+8.7%** | **+8.1%** | **+7.8%** | **+13.4%** | **+10.2%** |
| 512 KB | +6.1% | +8.6% | +16.3% | +8.2% | +45.7% | +4.2% | +3.2% | −8.7% |
| 1 MB | +2.8% | +4.7% | +5.4% | +3.0% | +2.7% | +6.3% | +8.4% | +32.2% |

The 256 KB lane — the exact size where single-row INSERT won −16% to −23% in
exp 234 — is candidate-**slower on all 8/8 legs**, +7.6% to +18.1%, reproduced
same-direction across every order flip (median ≈ +9.5%). 512 KB leans slower
(7/8 positive, noisier); 1 MB is uniformly slightly slower but WAL-dominated.
Meanwhile the sub-threshold controls swing ±100%+ in both directions, which
*calibrates* the noise floor: the wrapped lanes reproduce a consistent
regression that the controls' noise does not manufacture.

Interpretation: **the exp 234 mechanism inverts for batches.** Exp 234's win
came from the interaction between per-write-round-trip heap churn and the writer
being safepointed *mid-step*: across N independent single-row INSERTs, each
send parks a fresh blob on the heap, and scavenges triggered while the writer is
mid-`sqlite3_step` on the previous blob stall it — a cost that compounds over
many round-trips and that moving blobs off-heap removes. `executeBatch` already
collapses those N writes into **one** writer round-trip inside one transaction,
so there is no interleaving of scavenge-versus-writer-step to reclaim — the very
thing exp 234 optimized is absent. What remains is the candidate paying 30×
`fromList` (malloc + finalizer + external-memory accounting, which itself
pressures the GC) plus 30× `materialize()`, against a baseline whose single
graph-copy of all 30 blobs is a one-time transient the writer never races. The
wrap tax is real; the offsetting benefit is gone.

## Decision

**Rejected.** Wrapping batch blob params in `TransferableTypedData` is a
reproduced +8% to +18% regression at 256 KB (8/8 legs slower), leaning slower at
512 KB and 1 MB, with no size showing a win. Runtime code is reverted;
`BatchRequest` stays on the direct object-graph copy exactly as exp 234 left it.

This is a *premise-refuted* outcome, and a valuable one: it bounds exp 234's
claim. The blob-transfer win is not "GC-heap blobs are expensive" in the
abstract — it is specific to **many independent write round-trips** whose heap
churn stalls the writer mid-step. Batching removes the round-trips, so it
removes the win and leaves only the per-blob wrap cost. The
`parameter-encoding-and-binding` open question is answered *no* for the batch
path.

Would reopen only if: (a) a Dart runtime change makes `TransferableTypedData`
wrapping cheap enough that the tax disappears (then even a small batch benefit
could surface), or (b) a production workload shows a *single* `executeBatch`
carrying one or few very large blobs (where per-blob wrap cost is amortized over
fewer sets and the batch's own WAL cost is large) rather than the many-mid-size
shape tested here. The `blob_batch_write_ab.dart` harness is the durable gate
for any such revisit; the prototype is preserved at `archive/exp-237` for
cherry-pick.

## Test plan

- [x] `dart analyze` on the changed `lib/` files and the harness (clean)
- [x] `dart test test/database_test.dart -j 1` (58/58, incl. new mixed-set
  batch large-blob round-trip on `executeBatch` + nested `tx.executeBatch`)
  — passed with the prototype in place, before the runtime revert
- [x] focused end-to-end batch A/B, interleaved + order-flipped, four runs
- [x] `dart run benchmark/finalize_experiment.dart --experiment=experiments/237-batch-blob-param-transfer.md`
