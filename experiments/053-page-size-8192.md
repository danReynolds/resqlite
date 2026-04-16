# Experiment 053: Page size 8192

**Date:** 2026-04-15
**Status:** Rejected (performance wins real, but breaks existing databases)

## Problem

SQLite defaults to 4096-byte pages. Modern SSDs and NVMe drives have 4KB-16KB erase blocks. Larger pages mean fewer B-tree nodes for the same data volume, shallower trees, and fewer page reads for range scans. With `mmap_size=256MB`, larger pages also reduce the number of page cache entries SQLite must manage.

## Hypothesis

Doubling page size from 4096 to 8192 should improve read performance for large result sets by reducing B-tree depth and page count. Write performance may also improve due to fewer pages per transaction.

## Approach

Added `PRAGMA page_size = 8192` before `PRAGMA journal_mode = WAL` in `open_connection` (resqlite.c). Page size must be set before the first write to the database — it only takes effect on new databases; existing databases retain their original page size unless `VACUUM` is run.

## Results

**14 wins, 0 regressions** (3 repeats × 2 runs vs baseline).

| Benchmark | Baseline | 8K pages | Delta |
|---|---|---|---|
| Select maps 10000 rows | 5.57ms | 4.58-4.67ms | **-16 to -18%** |
| Batched write tx 100 rows | 0.82ms | 0.63ms | **-23%** |
| Batched write tx 1000 rows | 8.27ms | 6.12ms | **-26%** |
| Batched write tx (executeBatch) | 0.54ms | 0.45ms | **-17%** |
| Transaction read 500 rows | 0.13ms | 0.10ms | **-23%** |
| Transaction read 1000 rows | 0.23ms | 0.19ms | **-17%** |
| selectBytes (all sizes) | — | — | unchanged |

The large-read improvement (-16 to -18% at 10k rows) is real and consistent. Transaction reads and writes also improved significantly. selectBytes was unaffected (the C JSON serializer's cost dominates page read cost).

## Decision

**Rejected as a default change** despite real performance wins, because:

1. **Breaks existing databases.** `PRAGMA page_size` only takes effect on new databases. Existing users would need to run `VACUUM` (which rewrites the entire database and can be very slow for large DBs) or see no benefit.
2. **Should be user-configurable.** Page size is a deployment decision, not a library default. Some users may have reasons to prefer 4096 (smaller databases, memory-constrained devices). A better approach would be a `pageSize` parameter on `Database.open` that defaults to 4096 for compatibility.
3. **Increases minimum I/O granularity.** Each page write is 8KB instead of 4KB. For workloads with many small updates to different pages, this increases write amplification.

Recommendation: expose as a `Database.open` configuration option rather than changing the default. Document the tradeoffs.
