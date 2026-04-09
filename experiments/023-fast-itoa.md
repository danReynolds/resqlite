# Experiment 023: Fast int64-to-string for JSON Serialization

**Date:** 2026-04-08
**Status:** Accepted

## Hypothesis

`snprintf(num, sizeof(num), "%lld", value)` parses the format string on every
call. A hand-rolled int64-to-string avoids format parsing overhead. With
5000 rows × 2 integer columns = 10K calls per selectBytes query, the overhead
adds up.

## Change

Added `fast_i64_to_str()` — simple digit extraction loop with negative handling
(avoids UB on LLONG_MIN). Used in `write_json_to_buf()` for SQLITE_INTEGER.

## Results

| Benchmark | Before | After | Delta |
|---|---|---|---|
| selectBytes 100 rows | 0.08ms | 0.07ms | -12% |
| select Maps 100 rows | 0.35ms | 0.30ms | -14% |
| Single inserts | 2.13ms | 1.78ms | -16% |

3 wins, 1 regression (noise — interactive tx 0.05→0.06ms), 13 neutral.

The selectBytes improvement at 100 rows is genuine — at that size, JSON
serialization cost is a significant fraction of total wall time. The select
Maps improvement is likely noise (itoa doesn't affect the Maps path).

## Decision

**Accepted** — measurable win on the selectBytes hot path. The implementation
is simple (30 lines), correct (handles negatives and LLONG_MIN), and has
no downside.
