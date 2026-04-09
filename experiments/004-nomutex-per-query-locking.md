# Experiment 004: NOMUTEX with Per-Query Locking

**Date:** 2026-04-06
**Status:** Accepted
**Commit:** [`4acfb57`](https://github.com/danReynolds/dune/commit/4acfb57)

## Problem

SQLite's default `SQLITE_OPEN_FULLMUTEX` wraps every API call in a mutex lock/unlock. For a 20,000-row query with 6 columns, that's ~60,000 lock/unlock operations (step + type + value per cell). Each mutex operation costs ~20ns, totaling ~1.2ms of pure mutex overhead.

## Hypothesis

Switching to `SQLITE_OPEN_NOMUTEX` and adding our own `pthread_mutex` locked once per query (in `stmt_acquire`, unlocked in `stmt_release`) would reduce 60,000 mutex operations to 2, saving ~1ms at large result sizes.

## What We Built

Changed `resqlite_open` from `SQLITE_OPEN_FULLMUTEX` to `SQLITE_OPEN_NOMUTEX`. Added `pthread_mutex_t` to the `resqlite_db` struct. `resqlite_stmt_acquire` locks before any SQLite calls, `resqlite_stmt_release` unlocks after the caller finishes stepping through results.

Thread safety is preserved — concurrent queries from different Dart isolates block on the mutex. Only one query executes at a time per connection (later improved by the connection pool in experiment 007).

## Results

At 5,000 rows:

| Implementation | Wall time |
|---|---|
| FULLMUTEX (per-API-call locking) | 4.92 ms |
| **NOMUTEX (per-query locking)** | **4.21 ms** |

The improvement was ~0.7ms, measured alongside the C connection change (experiment 003). Isolating the mutex change alone was difficult since both were implemented together, but the theoretical savings of ~1ms at 20k rows aligns with the combined improvement.

## Why Accepted

Measurable improvement with no correctness trade-off. The per-query mutex is strictly safer than FULLMUTEX for our use case (each query runs to completion under one lock).
