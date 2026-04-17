# Experiment 078: Object-count-aware Isolate.exit threshold

**Date:** 2026-04-16
**Status:** Rejected (hypothesis undercut by Dart VM SMI representation; measured neutral)

## Problem

The reader pool currently decides between `SendPort.send` (copy) and
`Isolate.exit` (zero-copy + worker sacrifice) on a single signal: estimated
byte size of the result. Threshold is 256 KB. Above this, respawn cost
(~2–5 ms) is outweighed by memcpy cost of the payload; below it, copy is
cheaper than sacrifice.

External research (Dart VM docs, sdk#47508) notes that `SendPort.send`
runs `MessageValidator`, which walks the object graph of the payload
before copying. The implication: **object count**, not just byte count,
might predict transfer cost for row-based results where each cell is a
heap-allocated `Object?` reference.

Current byte threshold triggers at:
- ~32K `int` cells (8 bytes each)
- ~5K small-string cells (~50 bytes each)
- ~260 large-blob cells (~1 KB each)

The question: are there workloads with many small cells where the
validator walk dominates transfer time and sacrifice would be faster,
even though total bytes are under the 256 KB threshold?

## Hypothesis

Adding a cell-count fallback (`values.length > 8192`) to the sacrifice
decision will trigger `Isolate.exit` for wide-but-small-valued result
shapes (e.g. 2000–5000 rows of numeric-heavy data). If the validator walk
genuinely scales with node count, these workloads should see a speedup.

Threshold choice of 8192 cells = 1024 rows × 8 cols. Pushes sacrifice
into a band of result sizes (2k–5k rows at typical schema widths) that
the current byte threshold deliberately avoids.

## Approach

Added `sacrificeCellThreshold = 8192` constant and a helper
`_shouldSacrificeRaw(RawQueryResult)` that OR-combines the byte threshold
with the cell threshold. Applied the helper to all three row-based
dispatch paths in `lib/src/reader/read_worker.dart`:

- `SelectRequest`
- `SelectWithDepsRequest`
- `SelectIfChangedRequest` (changed branch)

`SelectBytesRequest` is left on pure byte threshold — the JSON payload is
a single `Uint8List`, not a walked graph.

Change is five lines of Dart. No C changes. No test-suite changes
required (behavior-equivalent from the caller's perspective; only the
transport path differs).

## Results

Three-repeat runs, compared against a three-repeat baseline taken
immediately before the change on the same machine.

- **Baseline:** `benchmark/results/2026-04-16T23-39-26-exp078-baseline.md`
- **Experiment:** `benchmark/results/2026-04-16T23-42-22-exp078-cell-threshold.md`
- **Summary:** 0 wins, 0 regressions, 63 neutral. "No changes beyond noise."

No benchmark moved beyond the noise-aware threshold in either direction.
Notably, the workloads the new threshold newly pushes into sacrifice —
`Scaling` at 2000–5000 rows and `Schema Shapes / Wide (20 cols)` at 1000
rows — showed no measurable change.

## Why The Hypothesis Failed

Two Dart VM behaviors explain the null result:

1. **SMIs are tagged pointers, not heap objects.** In AOT on 64-bit
   targets, small integers are stored directly in the List slot as a
   tagged pointer. The `MessageValidator` walk treats these as leaf
   values — there is no heap object to visit. So the "many boxed ints"
   case the hypothesis targeted doesn't actually produce extra
   validator nodes.

2. **Non-SMI values (double, String, Uint8List) contribute to both
   metrics.** A `List<Object?>` of 10K strings has 10K nodes AND ~N
   bytes per string. The byte threshold's `estimatedBytes +=` in the
   cell decode loop already accumulates string/blob byte lengths, so
   whenever a workload has enough heap nodes to matter, it also has
   enough bytes to trigger the existing threshold.

In other words: the Cluster A research note "object count matters, not
just bytes" is *theoretically* correct about `MessageValidator` but
*practically* redundant with the byte threshold for the workloads
resqlite actually produces, because the kinds of cells that walk as
heap nodes are exactly the kinds of cells whose content dominates the
byte estimate.

The int-heavy case where the two metrics most diverge (thousands of
SMI cells at low total bytes) is also the case where the VM does the
least validator work, so there's nothing to optimize.

## Decision

**Rejected.** The code change is correct and minimal, but the benchmark
suite — which includes narrow/wide/numeric/text schema shapes across
10 to 10,000 rows — shows no measurable impact. The reasoning in "Why
The Hypothesis Failed" explains why this result should be expected
rather than surprising.

The byte threshold remains a sufficient sacrifice signal for the
current result shapes. Future revisits would be justified only if:

- A new workload exposes a regime where cell count diverges from byte
  count *and* shows measurable validator-walk time (e.g., millions of
  small doubles — doubles do box on the heap unlike SMIs).
- Dart VM's isolate transfer semantics change in a way that decouples
  validator cost from data size.

## Archive

Code lives on branch `experiment-078-object-count-threshold` if a future
revisit wants to start from this implementation.

## Related

- Experiment 039 (byte-size sacrifice threshold) — the change this
  experiment proposed to extend
- Experiment 019 (hybrid reader pool) — the sacrifice mechanism itself
- Experiment 055 (columnar typed arrays) — a different response to the
  "many boxed values is expensive" intuition; also rejected on
  time-based benchmarks, also preserved for memory-profiling revisit
