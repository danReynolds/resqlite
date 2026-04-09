# Experiment 034: Per-Worker Schema Cache

**Date:** 2026-04-09
**Status:** Accepted

## Change

Added a `Map<String, RowSchema>` cache per worker isolate, keyed by SQL string.
On cache hit, skips N `sqlite3_column_name` FFI calls + N `_fastDecodeText`
string allocations (where N = column count, typically 3-15).

The cache persists for the worker's lifetime. Each worker isolate has its own
instance (top-level variable in read_worker.dart).

## Results

Part of cumulative +17% point query improvement. For repeated queries (the
common case with statement caching), eliminates all schema-related FFI calls
and string allocations after the first execution.

## Decision

**Accepted** — simple HashMap lookup. Eliminates real work (FFI calls + string
allocations) on the hot path. Cache grows bounded by distinct SQL strings
(typically <100 in any application).
