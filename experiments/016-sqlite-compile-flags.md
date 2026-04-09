# Experiment 016: SQLite Compile Flags Cleanup

**Date:** 2026-04-07
**Status:** Accepted (correctness improvements, performance within noise)
**Commit:** [`b9c6b6d`](https://github.com/danReynolds/dune/commit/b9c6b6d)

## Changes

### New compile-time flags (hook/build.dart)
- `SQLITE_DEFAULT_WAL_SYNCHRONOUS=1` — readers automatically get `synchronous=NORMAL` in WAL mode. Removed the explicit PRAGMA call from `open_connection`.
- `SQLITE_OMIT_AUTOINIT` — removes the `sqlite3_initialize()` check from every API entry point. Added explicit `sqlite3_initialize()` call in `resqlite_open`.
- `SQLITE_OMIT_UTF16` — removes dead UTF-16 code paths. We only use UTF-8 via FFI.
- `SQLITE_LIKE_DOESNT_MATCH_BLOBS` — enables the LIKE optimization fast path.

### sqlite3_prepare_v3 with SQLITE_PREPARE_PERSISTENT
All statement preparations in the C layer now use `sqlite3_prepare_v3` with `SQLITE_PREPARE_PERSISTENT`. This tells SQLite to allocate the statement's internal memory from the system allocator instead of the connection's lookaside buffer. Since our statements live in an LRU cache for the connection's lifetime, this frees lookaside slots for transient allocations during query execution.

## Results

Benchmark comparison: 1 win (transaction -17%), 2 regressions (both noise — parameterized queries affected by system load, all libraries slower; batch 100 rows is 10μs).

These optimizations target per-API-call overhead that's below the measurement resolution of our benchmark suite. They're correct by construction — less work per call, no behavioral change.

## Decision

**Accepted** — correct improvements with no downside. The per-call savings stack with `isLeaf: true` (experiment 013) but are individually too small to measure.
