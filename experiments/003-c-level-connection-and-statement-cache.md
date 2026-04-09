# Experiment 003: C-Level Connection and Statement Cache

**Date:** 2026-04-06
**Status:** Accepted
**Commit:** [`4acfb57`](https://github.com/danReynolds/dune/commit/4acfb57)

## Problem

Each `Isolate.run()` call opened a fresh SQLite connection — `sqlite3_open_v2` + PRAGMA setup (WAL, busy_timeout, synchronous). This cost ~0.5-1ms per query. Additionally, prepared statements were created and finalized per query with no caching.

## Hypothesis

Moving the `sqlite3*` connection handle and a prepared statement LRU cache into a C struct that persists across Dart isolate lifetimes would eliminate the per-query connection overhead. Since native memory is process-global, any Dart isolate can call into the same C connection via its pointer address.

## What We Built

`resqlite_db` — a C struct containing:
- `sqlite3*` connection handle
- `resqlite_stmt_cache` — LRU cache of 32 prepared statements (keyed by SQL string)
- `pthread_mutex_t` for thread-safe access

`resqlite_open()` creates the struct. `resqlite_stmt_acquire()` looks up or prepares a statement. `resqlite_stmt_release()` returns it. Dart isolates pass the struct's pointer address as an integer.

## Results

At 5,000 rows:

| Implementation | Wall time |
|---|---|
| Per-isolate connection open | 4.92 ms |
| C-level persistent connection | **4.21 ms** |

**~0.7ms improvement.** The savings came from both the eliminated connection setup and the statement cache hits (skipping `sqlite3_prepare_v2` on repeated queries).

## Why Accepted

Clean architecture with measurable improvement. The C connection outliving Dart isolates is a foundational piece — it enables the connection pool (experiment 007) and the batch FFI approach (experiment 009). Statement caching particularly helped in the parameterized queries benchmark.
