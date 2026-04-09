# Experiment 014: Writer Connection Tuning

**Date:** 2026-04-07
**Status:** Partially accepted
**Commit:** [`4c368a6`](https://github.com/danReynolds/dune/commit/4c368a6)

## Hypothesis

Three write-path optimizations could reduce per-write overhead:
1. `PRAGMA locking_mode=EXCLUSIVE` on the writer — skip shm file operations
2. `BEGIN IMMEDIATE` instead of `BEGIN` — avoid lock-upgrade path
3. Remove `sqlite3_clear_bindings` — redundant when all params are rebound

## Results

### locking_mode=EXCLUSIVE — REJECTED

Setting `PRAGMA locking_mode=EXCLUSIVE` on the writer causes `SQLITE_BUSY` (error 5) on all reader connections. Despite research suggesting WAL mode allows concurrent readers with an exclusive writer, the reality is that EXCLUSIVE locking mode holds the file lock permanently, blocking all other connections.

**This is incompatible with our reader pool architecture.** Reverted immediately.

### BEGIN IMMEDIATE — ACCEPTED

Changed `BEGIN` to `BEGIN IMMEDIATE` in both `resqlite_run_batch` (C) and the writer isolate's pre-allocated transaction strings (Dart). Acquires the write lock upfront instead of deferring to the first write statement. Since our writer is the only connection that writes, the lock is always available.

Theoretically avoids the lock-upgrade path inside SQLite's pager, but benchmark impact was within noise.

### Remove sqlite3_clear_bindings — ACCEPTED

Removed all 4 `sqlite3_clear_bindings` calls:
- `get_or_prepare_writer` (cache hit path)
- `get_or_prepare_reader` (cache hit path)
- `resqlite_run_batch` (cache hit on initial prepare)
- `resqlite_run_batch` (per-iteration in the batch loop)

`sqlite3_clear_bindings` sets all parameters to NULL. Since `bind_params` immediately rebinds every slot, the clear is pure waste — looping through all parameters to null them before overwriting.

## Benchmark

Comparison vs isLeaf baseline: 0 wins, 3 regressions (all within noise — 10μs on batch 100, run-to-run I/O variance on batch 10k, and an unrelated read fluctuation). No measurable improvement or degradation.

The changes are theoretically correct (less work per query) but too small to measure against I/O noise in write benchmarks.

## Decision

- `locking_mode=EXCLUSIVE`: **Rejected** — incompatible with concurrent readers
- `BEGIN IMMEDIATE`: **Accepted** — correct, no downside
- Remove `clear_bindings`: **Accepted** — strictly less work, no downside
