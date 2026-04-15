# Experiment 039: Byte-size sacrifice threshold

**Date:** 2026-04-10
**Status:** Accepted

## Hypothesis

The cell-count threshold (`rows * cols > 6000`) is a poor proxy for SendPort
copy cost. A 200-row query with large text blobs can transfer more data than a
2000-row query with tiny ints, yet only the latter would trigger sacrifice.
Estimating actual byte size and using a byte threshold should give a more
accurate sacrifice signal with zero additional overhead.

## What We Built

Added a `byteEstimate` accumulator to the existing cell loop in
`_executeQueryImpl`. Each cell contributes its actual data size:

- `int` / `double`: +8 bytes
- `text`: +byte length
- `blob`: +byte length
- `null`: +0

This piggybacks on the per-cell type switch that already runs for every value —
no second pass, no new FFI calls. The estimate is stored on `RawQueryResult` and
used for the sacrifice decision.

Unified both the row and selectBytes thresholds into a single
`sacrificeByteThreshold = 256 KB`. Below this, SendPort memcpy is
sub-millisecond. Above it, Isolate.exit zero-copy transfer outweighs the
~2-5ms respawn cost.

Replaced:
- `const int sacrificeThreshold = 6000` (cell count)
- `const int bytesSacrificeThreshold = 102400` (100 KB, bytes only)

With:
- `const int sacrificeByteThreshold = 256 * 1024` (256 KB, both paths)

## Results

Benchmark comparison against previous baseline (3-repeat medians):

- **13 wins, 0 regressions, 9 neutral**
- No measurable overhead from the `byteEstimate +=` additions in the inner loop

The wins are from accumulated changes (control port fix, raw-data sacrifice
path) rather than the threshold change itself, but the threshold change
introduced zero regression.

## Why 256 KB

At 256 KB, a `memcpy` takes ~0.05ms. Isolate.exit respawn costs ~2-5ms. So
sacrifice only pays off when the zero-copy savings exceed the respawn overhead —
roughly above 1-2 MB of data. 256 KB is conservative enough to avoid unnecessary
sacrifice while still catching genuinely large results.

With the test schema (~107 bytes/row × 6 cols), 256 KB ≈ 2450 rows.
