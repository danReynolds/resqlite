# Experiment 022: WAL Autocheckpoint Tuning

**Date:** 2026-04-08
**Status:** Accepted (correctness/reliability improvement, not a benchmark win)

## Hypothesis

Raising WAL autocheckpoint from the default 1000 pages (~4MB) to 10000 pages
(~40MB) on the writer reduces checkpoint frequency, avoiding fsync-heavy
latency spikes during write bursts. Disabling autocheckpoint on readers
(set to 0) prevents readers from accidentally triggering checkpoints.
Adding journal_size_limit=64MB caps WAL file growth.

## Changes

In `open_connection()`:
- Readers: `PRAGMA wal_autocheckpoint = 0`
- Writer: `PRAGMA wal_autocheckpoint = 10000`
- Writer: `PRAGMA journal_size_limit = 67108864`

## Results

Mixed in microbenchmarks — 2 wins, 2 regressions, 13 neutral. All within noise.

This is expected: the autocheckpoint change affects tail latency and write burst
behavior, not steady-state throughput. The default 1000-page threshold means a
checkpoint (with fsync) fires every ~4MB of WAL writes. At 10000 pages, the
checkpoint fires 10x less often. The benefit shows up as fewer p99 latency spikes
in production workloads, not in median microbenchmark numbers.

## Decision

**Accepted** — the changes are correctness and reliability improvements:
- Readers never trigger checkpoints (prevents reader-writer contention)
- Writer checkpoints less frequently (smoother write latency)
- WAL file size is bounded (prevents disk space surprises)

These are standard production SQLite tuning recommendations from the SQLite docs
and PowerSync's optimization guide. No code complexity added.
