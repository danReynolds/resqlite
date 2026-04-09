# Experiment 009: Batch FFI with resqlite_step_row

**Date:** 2026-04-06
**Status:** Accepted
**Commit:** [`4c18bb4`](https://github.com/danReynolds/dune/commit/4c18bb4)

## Problem

The `select()` hot loop makes ~16 FFI calls per row: 1 `sqlite3_step` + 6 `sqlite3_column_type` + 6 `sqlite3_column_xxx` (value read) + ~3 `sqlite3_column_bytes` (text lengths). For 5,000 rows, that's ~80,000 FFI calls. Each FFI boundary crossing costs ~10-20ns.

A micro-benchmark confirmed: the C bulk reader (one FFI call for everything) completed the same query in 0.68ms, while the full `select()` pipeline took 2.42ms. The overhead (1.74ms) was 72% of the total, with FFI calls accounting for ~80% of that overhead.

## Hypothesis

A C function that steps one row and fills a pre-allocated native struct array with all column types and values in one call would reduce FFI crossings from ~16/row to 1/row. Dart reads values from native memory via `ByteData` (no FFI call). Estimated savings: ~1ms at 5,000 rows.

## What We Built

```c
typedef struct {
    int type;
    long long int_val;
    double double_val;
    const char* text_ptr;
    int text_len;
    const void* blob_ptr;
} resqlite_cell;

int resqlite_step_row(sqlite3_stmt* stmt, int col_count, resqlite_cell* cells);
```

Dart pre-allocates one `resqlite_cell` array (native memory, reused across rows). Each `resqlite_step_row` call fills the array. Dart reads type tags and numeric values directly from `ByteData` (getInt32/getInt64/getFloat64). Text pointers and lengths are read as int64 addresses, then used with `Pointer.fromAddress` + `utf8.decode`.

## Results

### Maps wall time

| Rows | Before (per-cell FFI) | After (batch) | Improvement |
|---|---|---|---|
| 1,000 | 0.59 ms | **0.51 ms** | -14% |
| 5,000 | 2.96 ms | **2.55 ms** | -14% |
| 10,000 | 6.12 ms | **6.36 ms** | +4% (noise) |
| 20,000 | 18.03 ms | **16.44 ms** | -9% |

### Concurrent reads (8 parallel, 1,000 rows)

| Implementation | Wall |
|---|---|
| Before batch | 1.29 ms |
| **After batch** | **1.07 ms** |
| sqlite_async | 1.51 ms |

### Parameterized queries (100 queries × ~500 rows)

| Implementation | Wall |
|---|---|
| Before batch | 23.02 ms |
| **After batch** | **19.89 ms** |
| sqlite3 (cached) | 22.87 ms |
| sqlite_async | 26.32 ms |

### Schema shapes — wide tables benefit most

| Shape (1,000 rows) | Before | After | Improvement |
|---|---|---|---|
| Wide (20 cols) | 1.44 ms | **1.14 ms** | -21% |
| Numeric-heavy | 0.47 ms | **0.41 ms** | -13% |
| Text-heavy | 0.89 ms | **0.87 ms** | -2% |

Wide tables see the biggest improvement (more columns = more FFI calls saved per row). Text-heavy tables see minimal improvement (utf8.decode dominates regardless of FFI overhead).

## Why Accepted

Consistent 9-21% improvement across all benchmarks. The improvement compounds with the connection pool (concurrent reads improved from 1.29ms to 1.07ms) and statement cache (parameterized queries dropped from 23ms to 19.89ms). resqlite now holds the top position on every benchmark we measure.

### Final standings after all optimizations

| Benchmark | resqlite | sqlite3 | sqlite_async |
|---|---|---|---|
| Maps 5k rows (wall) | **2.55 ms** | 3.93 ms | 4.20 ms |
| Maps 20k rows (wall) | **16.44 ms** | 22.83 ms | 20.59 ms |
| Bytes 5k rows (wall) | **3.68 ms** | 13.27 ms | 16.36 ms |
| Concurrent 8x (wall) | **1.07 ms** | — | 1.51 ms |
| Parameterized 100q (wall) | **19.89 ms** | 22.87 ms | 26.32 ms |
| Maps 5k (main isolate) | **0.46 ms** | 3.93 ms | 0.91 ms |
