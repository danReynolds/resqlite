# Experiment 018: Multi-Row Step (Batch N Rows Per FFI Call)

**Date:** 2026-04-07
**Status:** Rejected

## Hypothesis

Stepping 64 rows per FFI call instead of 1 would reduce FFI crossing overhead from 5000 calls to ~78 calls at 5000 rows. At ~50ns saved per call (with isLeaf), that's ~245μs saved.

## What We Built

New C function `resqlite_step_rows` that:
1. Steps up to N rows per call (batch size = 64)
2. Copies text/blob data into a side buffer (since `sqlite3_column_text` pointers are invalidated by the next `sqlite3_step`)
3. Returns actual row count and a status code (SQLITE_ROW, SQLITE_DONE, or RESQLITE_BUFFER_FULL)

Updated Dart `_selectOnWorker` and `_selectWithDepsOnWorker` to call `_resqliteStepRows` in a loop, processing all rows in each batch before the next FFI call.

## Issues

1. **Alignment crash**: The packed string buffer produced unaligned pointers. `_fastDecodeText` does a word-at-a-time ASCII check by casting to `Int64*`, which requires 8-byte alignment. Fixed by adding an alignment guard (`ptr.address & 7 == 0`).

2. **String copy overhead**: The fundamental problem — every text value must be `memcpy`'d from SQLite's internal buffer into our side buffer, because `sqlite3_column_text` pointers are invalidated by the next `sqlite3_step`. With single-row stepping, Dart reads directly from SQLite's pointer (zero copy). Multi-row stepping adds a mandatory copy for every string.

## Results

| Benchmark | Before | After | Delta |
|---|---|---|---|
| Select Maps 100 rows | 0.34ms | 0.28ms | -18% (noise) |
| Select Maps 5000 rows | 2.40ms | 2.52ms | +5% |
| Schema Text-heavy | 0.62ms | 0.77ms | **+24% regression** |
| Schema Nullable | 0.40ms | 0.50ms | **+25% regression** |
| Parameterized 100×500 | 23.83ms | 19.49ms | -18% (noise — recovering from bad prior run) |

The text-heavy and nullable regressions are real — the memcpy overhead for string data exceeds the FFI crossing savings.

## Why It Failed

The current single-row approach reads text directly from SQLite's internal memory — a pointer that's valid until the next `sqlite3_step`. This is effectively zero-copy for text. Multi-row stepping breaks this by requiring a copy of every string into a side buffer so it survives past subsequent steps.

The FFI crossing overhead we were trying to eliminate (~250μs at 5000 rows) is smaller than the memcpy cost added for text-heavy schemas. The trade-off only works for numeric-only schemas with no strings, which is not a realistic workload.

## Decision

**Rejected.** Single-row stepping with direct SQLite pointer access is faster than multi-row stepping with string copies. The FFI crossing cost (~50ns per call with isLeaf) is already low enough that batching doesn't justify the copy overhead.
