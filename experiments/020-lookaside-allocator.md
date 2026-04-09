# Experiment 020: SQLITE_DEFAULT_LOOKASIDE=1200,128

**Date:** 2026-04-08
**Status:** Accepted (no measurable impact, but zero-cost improvement)

## Hypothesis

Bumping the lookaside allocator from the default 100 small slots to 128 gives
SQLite's dual-pool architecture (since 3.31.0) more headroom for transient
allocations during query execution. The SQLite docs claim 10-15% overall speedup
from the lookaside allocator. Increasing slots costs ~4.5KB extra per connection.

## Change

Added compile flag: `SQLITE_DEFAULT_LOOKASIDE=1200,128`

## Results

All benchmarks neutral. No wins, no regressions. The lookaside allocator was
already active at default settings — bumping from 100 to 128 small slots didn't
produce a measurable difference in our workload.

## Decision

**Accepted** — zero runtime cost, zero code complexity, and the SQLite docs
recommend tuning this. The improvement may be more visible in workloads with
complex expressions or many transient allocations per query (JOINs, subqueries,
CTEs) which our benchmarks don't heavily exercise.
