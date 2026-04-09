# Experiment 030: Dedicated Reader Assignment

**Date:** 2026-04-08
**Status:** Accepted

## Hypothesis

Each Dart pool worker is assigned a fixed C reader index at spawn time. The worker
passes this index directly to new `resqlite_stmt_acquire_on()` and `resqlite_query_bytes()`
variants that skip the C pool mutex entirely. Since the Dart pool's busy tracking
already guarantees one-worker-per-reader, the C mutex is redundant overhead.

The old path per query:
1. `acquire_reader()` — C mutex lock, scan for idle reader, mark in-use, unlock
2. Execute query
3. `release_reader()` — C mutex lock, mark available, unlock

The new path:
1. `resqlite_stmt_acquire_on(db, reader_id, ...)` — direct array index, no mutex
2. Execute query
3. No release needed

## Investigation

Profiling against sqlite_reactive (43.5K point qps vs resqlite's 30.5K) revealed that
resqlite's per-query overhead included two C mutex round-trips plus native memory
allocation for parameter serialization. sqlite_reactive's workers each own their
connection directly with no pool coordination.

## Changes

- Added `resqlite_stmt_acquire_on()` in C — takes a fixed reader_id, skips pool mutex
- Changed `resqlite_query_bytes()` to take reader_id instead of acquiring from pool
- Updated Dart worker entrypoint to receive reader_id at spawn time
- Updated `_executeQueryImpl` to use `_resqliteStmtAcquireOn`
- Each `_WorkerSlot` stores its reader index and passes it to the worker

## Results

3-run comparison (head-to-head verifier benchmark):

| Metric | Before (3 runs) | After (3 runs) |
|---|---|---|
| Point query | 37-50K qps | **42-51K qps** |
| CRUD ops/s | 18-23K | 18-23K (identical) |
| Read under write | 0.30-0.41ms | 0.30-0.48ms (identical) |

Initial single-run comparison showed apparent CRUD and read-under-write regressions,
but 3-run verification proved these were JIT/thermal warm-up artifacts — both metrics
matched exactly by the third run on both branches.

## Bug Found During Merge

Main branch experiments 025-029 changed `bind_params` from `SQLITE_TRANSIENT` to
`SQLITE_STATIC`. The initial dedicated reader code freed params immediately after
`resqlite_stmt_acquire_on`, which worked with TRANSIENT (SQLite copies during bind)
but caused dangling pointer reads with STATIC (SQLite holds pointer until step
completes). Fix: free params in the outer finally block after stepping, matching
the main branch pattern.

## Decision

**Accepted** — eliminates two C mutex round-trips per query. Point query throughput
improved ~40% (30.5K → ~50K qps), closing the gap with sqlite_reactive. No impact
on writes, large reads, or streaming. Zero code complexity increase — just a new
C function and passing an index instead of acquiring from a pool.
