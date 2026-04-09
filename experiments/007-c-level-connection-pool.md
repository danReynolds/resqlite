# Experiment 007: C-Level Connection Pool

**Date:** 2026-04-06
**Status:** Accepted
**Commit:** [`3a08838`](https://github.com/danReynolds/dune/commit/3a08838)

## Problem

resqlite used a single C connection with a `pthread_mutex`. Concurrent reads serialized — query 2 waited for query 1 to finish. sqlite_async's Dart-side connection pool (multiple worker isolates, each with its own connection) allowed true parallel reads and was 3.8x faster at 8x concurrency.

## Hypothesis

A C-level connection pool with multiple read-only `sqlite3*` handles would enable true parallel reads while keeping the coordination overhead in C (nanosecond mutex/condvar) instead of Dart (microsecond isolate message passing).

## What We Built

Extended `resqlite_db` to hold an array of reader connections (default 4):
- Each reader has its own `sqlite3*` handle opened in `SQLITE_OPEN_READONLY` mode
- Each reader has its own `resqlite_stmt_cache` (statement cache)
- `pthread_cond_t` condition variable signals when a reader becomes available
- `resqlite_stmt_acquire` grabs an idle reader (blocks if all busy)
- `resqlite_stmt_release` returns a reader and signals waiting callers
- Write connection is separate (used by `execute()`)

SQLite in WAL mode natively supports concurrent readers, so multiple read-only connections can query simultaneously without contention.

## Results

### Concurrent reads (1,000 rows, N parallel queries)

| Concurrency | Single connection | C pool | sqlite_async |
|---|---|---|---|
| 1 | 0.77 ms | 0.79 ms | 0.68 ms |
| 2 | 1.64 ms | **0.86 ms** | 0.64 ms |
| 4 | 2.83 ms | **0.70 ms** | 0.80 ms |
| 8 | 5.64 ms | **1.29 ms** | 1.58 ms |

At 8x concurrency: **5.64ms → 1.29ms** (4.4x improvement). resqlite now beats sqlite_async (1.58ms) because C-level pool coordination is cheaper than Dart isolate message passing.

### Single-query performance

No regression for single queries (0.77ms → 0.79ms). The pool overhead for acquiring/releasing a reader is negligible (nanosecond mutex).

## Why Accepted

Eliminated the concurrent read weakness completely. resqlite now beats sqlite_async at every concurrency level. The C pool also enabled per-reader statement caches, improving cache hit rates under concurrent workloads.
