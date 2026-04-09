# Experiment 028: Static Bind for Text and Blob Params

**Date:** 2026-04-08
**Status:** Accepted
**Commit:** [`8822bd2`](https://github.com/danReynolds/dune/commit/8822bd2)

## Hypothesis

The current bind path allocates native memory for text/blob params in Dart, then
asks SQLite to copy those same bytes again via `SQLITE_TRANSIENT`. If we keep the
param buffers alive until the statement is reset/released, SQLite can bind against
them as `SQLITE_STATIC` and avoid the second copy.

This should mostly help:
- small and medium parameterized reads
- repeated query shapes
- larger batch writes with many bound values

## Change

Two coordinated changes:

1. In native `bind_params(...)`, switched text/blob binds from `SQLITE_TRANSIENT`
   to `SQLITE_STATIC`.
2. In `read_worker.dart`, delayed `freeParams(...)` until after the statement is
   released so the bound memory stays valid for the lifetime of the query.

## Results

Benchmark runs:
- Baseline: `2026-04-08T17-14-06-exp025-baseline.md`
- Static bind: `2026-04-08T17-19-23-exp028-static-bind.md`

Baseline vs static-bind highlights:

| Benchmark | Baseline | Static bind | Delta |
|---|---:|---:|---:|
| Select Maps 100 rows | 0.36ms | 0.30ms | -17% |
| Select Maps 1000 rows | 0.40ms | 0.40ms | 0% |
| Select Maps 5000 rows | 2.27ms | 2.09ms | -8% |
| Select Bytes 5000 rows | 3.16ms | 3.01ms | -5% |
| Parameterized queries | 15.41ms | 14.81ms | -4% |
| Batch insert 10000 | 4.74ms | 4.57ms | -4% |
| Single inserts | 1.85ms | 1.86ms | neutral |
| Interactive transaction | 0.06ms | 0.05ms | small win / likely noise |

The auto-generated comparison in the run file shows only two formal wins because
its threshold is ±10%, but the broader pattern is consistently favorable on the
read and parameter-heavy workloads this experiment was targeting.

## Decision

**Accepted**.

This is the most convincing of the parameter-path experiments:
- small read win is real
- parameterized queries improved
- large batch write cost also trended slightly down
- no obvious reliability issue surfaced in the benchmark run

The code change landed with additional regression coverage for repeated cached
text/blob parameter binds in `database_test.dart`. The broader full-suite benchmark
run is noisier than this targeted experiment, so this should still be understood as
"targeted workload win, broad-suite neutral-to-noisy" rather than a universal speedup.
