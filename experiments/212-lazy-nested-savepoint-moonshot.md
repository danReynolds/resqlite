# Experiment 212: Lazy nested-savepoint materialization moonshot

**Date:** 2026-07-03
**Status:** Rejected
**Category:** Moonshot
**Direction:** `transaction-control-paths`
**Benchmark Run:** focused
[`benchmark/experiments/savepoint_name_compression.dart`](../benchmark/experiments/savepoint_name_compression.dart),
order-flipped baseline/candidate pair
**Archive:** [`archive/exp-212`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-212)

## Problem

The nested-transaction direction has already closed the small local
savepoint optimizations:

- [exp 102](102-savepoint-string-cache.md) cached depth-specific savepoint
  strings, but the release suite had no nested workload yet.
- [exp 111](111-nested-tx-benchmark-savepoint-cache.md) added the nested
  workload and re-ran that cache; the 50x shallow fanout row moved only
  -9%, inside the +/-17% decision threshold.
- [exp 189](189-savepoint-name-compression.md) tried same-name savepoints.
  Empty/rollback/deep best-case rows improved, but the representative
  nested-write fanout failed to reproduce and flipped slower in the
  order-flipped pass.

The recurring lesson is that per-savepoint string and allocation work is not
the active ceiling once the nested body performs a real write. The only
remaining plausible frontier is round-trip shaped: a nested write body pays one
writer-isolate message for `SAVEPOINT`, one for the write, and one for
`RELEASE`. If that request count is the actual floor, a prototype that removes
one message should improve the one-write nested fanout.

## Hypothesis

Assumption challenged: nested `Transaction.transaction()` must materialize its
SQLite savepoint eagerly, before the body runs, even when the body might be
empty or might perform exactly one write.

Prototype:

- make nested transactions lazy by default;
- empty nested bodies materialize no SQLite savepoint and skip both
  `SAVEPOINT` and `RELEASE`;
- the first nested `execute()` sends one internal writer request that issues
  `SAVEPOINT sN` and the write together;
- once materialized, normal `RELEASE` / `ROLLBACK TO` cleanup preserves the
  existing nested-transaction semantics;
- force materialization before `executeBatch()` or before starting a child
  nested transaction, keeping the prototype bounded and conservative.

Expected result:

- empty fanout should improve sharply because it removes two writer requests
  per inner block;
- write fanout should improve if one fewer writer request is the load-bearing
  cost;
- rollback and deep-chain rows should stay neutral or improve modestly;
- reject if write fanout does not reproduce candidate-faster, because empty
  nested bodies are not common or important enough to carry runtime complexity.

The risk budget is intentionally moonshot-shaped. The prototype changes
transaction-control scheduling and adds internal request/state complexity, but
does not add public API. If accepted, it would still need a careful audit of
rare savepoint-failure edges before merge.

## Approach

The archived prototype is at
[`archive/exp-212`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-212).

Implementation sketch:

- added an internal `BeginExecuteRequest` in
  [`lib/src/writer/write_worker.dart`](../lib/src/writer/write_worker.dart)
  whose handler runs `_beginNestedSavepoint(state)` and then `executeWrite()`
  before replying with the normal `ExecuteResponse`;
- added writer-side helpers for explicit begin/commit/rollback requests and
  for the fused first nested write;
- taught `Transaction` to track a lazily-materialized nested savepoint;
- nested `execute()` uses the fused request on the first write;
- nested `executeBatch()` and nested-child transactions force ordinary
  materialization first;
- empty nested bodies skip both begin and commit/rollback.

The runtime change was tested, archived, and then reverted from the final
branch. The PR keeps only this writeup, result artifact, index row, and signal
metadata.

## Results

Raw run notes are recorded in
[`benchmark/results/2026-07-03T10-09-23Z-exp212-lazy-nested-savepoint.md`](../benchmark/results/2026-07-03T10-09-23Z-exp212-lazy-nested-savepoint.md).

Focused harness: `dart run benchmark/experiments/savepoint_name_compression.dart`.
Negative delta means candidate faster.

| Case | Pair 1 baseline | Pair 1 candidate | Delta | Pair 2 candidate | Pair 2 baseline | Delta |
|---|---:|---:|---:|---:|---:|---:|
| empty fanout x500 | 4.760 ms | 1.052 ms | -77.9% | 1.230 ms | 4.823 ms | -74.5% |
| write fanout x100 | 1.603 ms | 2.802 ms | +74.8% | 2.174 ms | 1.612 ms | +34.9% |
| rollback fanout x100 | 2.383 ms | 2.738 ms | +14.9% | 2.462 ms | 2.445 ms | +0.7% |
| deep chain 100 x depth=5 | 3.702 ms | 3.934 ms | +6.3% | 4.004 ms | 3.736 ms | +7.2% |

The empty-control case behaves exactly as predicted: skipping SAVEPOINT/RELEASE
for empty nested blocks is roughly 4x faster. That is not the acceptance gate.

The representative write fanout fails hard. It regresses in both pass
orderings: +74.8% in the baseline-first pair and +34.9% in the candidate-first
pair. Rollback fanout is neutral-to-slower and the deep chain is slower in both
passes. The fused first-write request removed one message, but it did not lower
the workload wall time; the added state and request shape likely disrupted the
already-cheap transaction path more than the removed empty begin helped.

## Decision

Rejected.

Lazy nested-savepoint materialization is a real win only for empty nested
transaction bodies. The workload that matters for this direction is the
one-write nested fanout, and it reproduced candidate-slower across the
order-flipped pair. Keeping runtime complexity for an empty-body win would
optimize a rare shape while slowing the representative nested write path.

The implementation is preserved at `archive/exp-212`; no runtime code is kept.

## Future Notes

- Do not retry lazy savepoint materialization or "SAVEPOINT + first execute"
  fusion without new evidence that empty nested bodies are a common production
  hot path. The current focused harness says the write-shaped case regresses.
- If transaction-control work reopens, it needs a stronger semantic shape than
  lazy begin: either a full savepoint-scope command batch that fuses begin,
  body, and release/rollback into one request, or a profile showing deeply
  nested transaction control is hot enough to justify design work.
- Because the public API is near-frozen, any public surface for explicit nested
  batching would need a massive, broad win. This experiment does not provide
  that evidence.

## Validation

- `dart pub get`
- `dart analyze --fatal-infos lib/src/writer/write_worker.dart lib/src/writer/writer.dart lib/src/transaction.dart benchmark/experiments/savepoint_name_compression.dart` (prototype)
- `dart test test/transaction_test.dart` (prototype)
- `dart run benchmark/experiments/savepoint_name_compression.dart` baseline-first pair
- `dart run benchmark/experiments/savepoint_name_compression.dart` candidate-first pair

