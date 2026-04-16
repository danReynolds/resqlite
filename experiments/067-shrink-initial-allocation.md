# Experiment 067: Shrink initial values list allocation

**Date:** 2026-04-16
**Status:** Rejected (regressed — Dart VM has fast path for List.filled)

## Problem

`decodeQuery` pre-allocates `List<Object?>.filled(colCount * 256, null, growable: true)` for every query. For point queries (colCount ≈ 5, rowCount = 1), this is 1280 null slots for a single-row result — ~10KB of mostly-unused heap.

Experiment 063 (SelectOne) showed that sized-right allocation (colCount slots only) was one of the sources of its 28-48% win. This experiment tried to capture that piece transparently inside `decodeQuery` by changing `colCount * 256` to `colCount * 4`.

## Hypothesis

Point queries allocate ~1280 fewer slots. Multi-row queries pay a few extra geometric doublings (Dart's list grows by `oldCap * 2 + small`), but the per-growth cost is amortized O(1). Net win for small results, net zero for large results.

## Results

**0 wins, 4 regressions, 59 neutral.**

| Benchmark | Before | After | Delta |
|---|---|---|---|
| Stream Churn (100 cycles) | 2.14ms | 3.08ms | **+44%** |
| Batched Write Inside Transaction (100 rows) | 0.65ms | 0.91ms | **+40%** |
| Batched Write Inside Transaction [main] | 0.65ms | 0.91ms | **+40%** |
| (3 others within noise, all trending up) | | | |

Every workload that involves many small queries regressed. The shrink hurt, not helped.

## Why It Failed

Dart's VM appears to have a fast path for `List<Object?>.filled(n, null)` when `n` is large and the fill value is `null`. Likely the implementation:
- Bump-allocates a contiguous region
- Relies on that region being zero-filled by the OS (null is represented as zero in Dart pointers)
- Skips the explicit "write null to every slot" loop

For small `n`, this fast path may not trigger, so the allocation is more expensive relative to its size. The amortized per-element cost is higher for small lists than for large pre-allocated ones.

Additionally, when the result is multi-row and the initial allocation is small, the growth sequence `colCount * 4 → 8 → 16 → 32 → ...` requires multiple reallocs. Each `values.length *= 2` does a copy of the current content. These copies cost more than the "wasted" upfront allocation of a larger initial list.

## Decision

**Rejected.** The `colCount * 256` initial size is well-tuned for the current Dart VM. It produces zero regressions across the benchmark suite; any shrinking hits the list-growth pathology.

This is a counterintuitive result — "allocate less" usually saves work, but here the Dart VM's implementation details make "allocate more upfront with a fast path" the winning strategy.

**Lesson:** VM implementation details matter more than theoretical allocation cost. Always measure Dart-level memory optimizations; the VM is often smarter about `filled(n, null)` than user code.

## Related Experiments

- 063 — captured this allocation saving as part of a specialized `selectOne` API that bypasses `List<Map>` entirely
- 066 — attempted to capture 063's wins transparently; this experiment 067 was the last remaining piece and it didn't work
