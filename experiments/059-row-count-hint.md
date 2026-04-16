# Experiment 059: Row count hint in schema cache

**Date:** 2026-04-16
**Status:** Rejected (below noise floor)

## Problem

`decodeQuery` pre-allocates `List<Object?>.filled(colCount * 256, null, growable: true)` for the result values. This is a compromise: too small, and multi-row queries do unnecessary list doublings; too large, and point queries waste allocation for a 512-slot list with one row's worth of data.

For queries that run repeatedly with stable row counts (typical for streams and repeated point queries), we could remember the last row count and pre-size appropriately.

## Approach

Extend the per-worker schema cache to store row count alongside schema:

```dart
final class _CachedSchema {
  _CachedSchema(this.schema, [this.rowCountHint = 256]);
  final RowSchema schema;
  int rowCountHint;
}
```

On cache hit, use `cached.rowCountHint` for pre-allocation. After query completion, update the hint to `rowCount + (rowCount >> 2)` (25% overallocation) so small growth doesn't trigger a resize.

## Results

**2 wins, 0 regressions, 61 neutral** (3 repeats vs baseline).

- Batched Write Inside Transaction (100 rows) / resqlite: **-11%** (one of two wins — likely an internal tx.select benefits)
- All other metrics: within noise

The core select() path was unchanged:
- select 10k rows: 4.70ms → 4.88ms (within noise)
- select 1k rows: 0.38ms (unchanged)
- point query: 113k → 114k qps (within noise)

## Why It Didn't Show

Two reasons:
1. **The benchmark runs multiple iterations per measurement.** After iteration 1, the hint is correct, so iterations 2+ use the optimal allocation. Since the median is taken across iterations, the one-time "wrong size" penalty is averaged away.
2. **List growth is already cheap.** Dart's list implementation uses geometric doubling with `realloc`-like semantics. A point query with `colCount * 256` pre-size does zero growths. Even for 10k rows, only ~3-4 growths are needed from the 256 baseline.

## Decision

**Rejected.** The optimization is correct and zero-risk, but the measurable improvement is below the benchmark noise floor. The single 11% win on batched write tx is real but isolated; it doesn't move the headline numbers.

Keeping the simpler 1-line allocation over a 2-field cache entry + update logic is the right tradeoff when the measurable benefit is marginal.
