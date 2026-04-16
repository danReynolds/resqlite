# Experiment 051: Lock-free reader pool with atomics

**Date:** 2026-04-15
**Status:** Rejected (not attempted — optimization target is dead code)

## Problem

The reader pool uses `sqlite3_mutex_enter/leave` around a linear scan of up to 16 reader slots in `acquire_reader` (resqlite.c:891). Under contention (8 concurrent reads), the mutex serializes pool acquisition. A lock-free approach using `atomic_compare_exchange_weak` on `in_use` flags could eliminate the mutex overhead (~20-25ns per lock/unlock pair on ARM64 vs ~3-5ns for a CAS).

## Why Not Attempted

Cross-referencing with experiment 030 (dedicated reader assignment) revealed that the mutex path is **dead code** in the current architecture. Each Dart reader worker isolate calls `resqlite_stmt_acquire_on(reader_id)` which bypasses `acquire_reader` entirely — no mutex, no pool scan. The generic `resqlite_stmt_acquire` (with mutex) is only used by `resqlite_db_status_total` (a diagnostic function) and as a fallback path that the Dart code never takes.

Experiment 030 already solved the contention problem at a higher level: by assigning dedicated readers to workers, it eliminated per-query pool coordination entirely. Making the unused pool path lock-free would be dead-code optimization.

## Decision

**Rejected — not attempted.** The optimization target doesn't exist in the live code path. The `pool_mutex` could be removed entirely in a cleanup pass, but that's a code quality change, not a performance experiment.

This was also a good lesson in **cross-referencing existing experiments before implementation**. A quick check of 030 saved hours of work that would have shown no benchmark signal.
