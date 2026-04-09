# Experiment 027: Transaction Query Writer Cache

**Date:** 2026-04-08
**Status:** Rejected

## Hypothesis

`tx.select()` inside interactive transactions still prepares statements on the
writer connection each time. Reusing the writer-side statement cache for those
transaction reads should reduce interactive transaction overhead and improve the
mixed read/write path.

## Change

Added a first-pass writer-connection cache path for transaction reads:

- native helpers to acquire/release cached writer statements
- FFI bindings for that acquire/release path
- `write_worker.dart` `_handleQuery(...)` switched from ad hoc prepare/reset to
  the writer statement cache

This was intentionally a narrow experiment: reuse the cached statement, but do not
yet rebuild the transaction read path around the faster batched reader machinery.

## Results

Benchmark run:
- `2026-04-08T17-18-09-exp027-tx-writer-cache.md`

Relevant outcomes:

| Benchmark | Result |
|---|---|
| Interactive transaction | `0.05ms` (no meaningful change) |
| Parameterized queries | `14.49ms` (small win, likely noise) |
| Single inserts | `3.15ms` (large regression vs neighboring runs) |

Package benchmark summary versus the prior run:
- 3 wins
- 1 regression
- 13 neutral

The key target metric, interactive transaction cost, did not move in a meaningful
way. The large single-insert regression was likely noise or unrelated runtime
variation, but it makes the run less persuasive rather than more.

## Decision

**Rejected** in this form.

This tells us that transaction-read prepare overhead is not the dominant bottleneck
in the current interactive transaction benchmark. A fuller rewrite that reuses the
same cached + batched row path as the dedicated readers may still be interesting,
but this smaller writer-cache-only version is not enough to justify merging.
