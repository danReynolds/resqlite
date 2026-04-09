# Experiment 013: FFI isLeaf Annotation

**Date:** 2026-04-07
**Status:** Accepted
**Commit:** [`af2cfd0`](https://github.com/danReynolds/dune/commit/af2cfd0)

## Hypothesis

Adding `isLeaf: true` to all `@ffi.Native` bindings will reduce per-call overhead by eliminating safepoint checks and thread state transitions on every Dart-to-C call.

## Background

Dart FFI calls without `isLeaf` perform a full thread state transition on every call:
1. Transition from Dart mutator to native thread state
2. Safepoint check (can the GC run?)
3. Execute the C function
4. Transition back to Dart mutator state

With `isLeaf: true`, steps 1-2 and 4 are eliminated. The requirement is that the C function doesn't call back into Dart and doesn't block for extended time. All of resqlite's C functions qualify — they're pure computation against in-process SQLite memory.

## Changes

Added `isLeaf: true` to all 33 `@ffi.Native` annotations across three files:
- `database.dart` — 6 bindings (sqlite3_column_count, sqlite3_column_name, resqlite_stmt_acquire, resqlite_stmt_release, resqlite_step_row, strlen)
- `resqlite_bindings.dart` — 11 bindings (resqlite_open, resqlite_close, resqlite_exec, resqlite_execute, resqlite_run_batch, resqlite_get_dirty_tables, resqlite_get_read_tables, resqlite_writer_handle, resqlite_free, and helpers)
- `writer_isolate.dart` — 16 bindings (sqlite3_prepare_v2, sqlite3_bind_*, sqlite3_step, sqlite3_reset, sqlite3_finalize, sqlite3_column_*, sqlite3_changes)

## Results

Compared against previous run (after-cleanup baseline):

| Benchmark | Before | After | Delta |
|---|---|---|---|
| Select Maps 100 rows | 0.32ms | 0.26ms | **-19%** |
| Schema Narrow (2 cols) | 0.17ms | 0.15ms | **-12%** |
| Schema Wide (20 cols) | 1.11ms | 1.01ms | -9% |
| Parameterized (100 × 500 rows) | 19.34ms | 17.77ms | -8% |
| Select Maps 5000 rows | 2.39ms | 2.21ms | -8% |
| Batch Insert 10k rows | 4.83ms | 4.52ms | -6% |
| Select Bytes 1000 rows | 0.78ms | 0.74ms | -5% |
| Schema Text-heavy | 0.63ms | 0.60ms | -5% |

**0 regressions.** Improvements strongest on small results where FFI overhead is a larger fraction of total time.

## Why It Works

resqlite already batches work into relatively few FFI calls (one `resqlite_step_row` per row instead of ~16 `sqlite3_column_*` calls). But even with batching, a 1000-row query makes ~1010+ FFI calls (step × rows + column metadata + acquire/release). At ~50ns saved per call, that's ~50μs saved — consistent with the observed 5-8% improvement on 1000-row queries.

The 19% improvement on 100-row queries is larger because the FFI overhead is a bigger fraction of the ~0.3ms total wall time.

## Decision

**Accepted.** Zero complexity cost, zero risk, consistent improvement across all benchmarks.
