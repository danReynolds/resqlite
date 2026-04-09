# Experiment 026: `sqlite3_db_status()` Probe

**Date:** 2026-04-08
**Status:** Rejected (no follow-on optimization justified)

## Hypothesis

Before attempting a process-global page cache or more aggressive memory tuning, we
should check whether sqlite is actually under page-cache or lookaside pressure in
resqlite's hot paths.

If cache miss rates are high, cache spill happens, or lookaside misses show up in
meaningful volume, then a deeper page-cache experiment might be justified.

## Change

Added an experiment-only aggregate probe:

- native helper: `resqlite_db_status_total(...)`
- Dart binding: `getDbStatusTotal(...)`
- benchmark script: `benchmark/experiments/db_status_probe.dart`

The probe sums `sqlite3_db_status()` across the writer and idle readers, then runs
four representative workloads:

1. point lookups
2. parameterized page reads
3. large result reads
4. write burst

## Results

Probe output:

| Workload | Cache hit rate | Cache spill | Lookaside misses |
|---|---:|---:|---:|
| Point lookups | 100.0% (2002 / 1) | 0 | 0 / 0 |
| Parameterized page reads | 99.9% (7991 / 9) | 0 | 0 / 0 |
| Large result reads | 100.0% (80 / 0) | 0 | 0 / 0 |
| Write burst | 100.0% (6002 / 0) | 0 | 0 / 0 |

Additional observations:
- aggregate cache usage sat around `3.08-3.35 MiB`
- lookaside highwater reached `175`, but there were zero size/full misses
- no cache spill occurred in any workload

## Decision

**Rejected** as a tuning direction for now.

The probe says the current configuration is already warm and healthy:
- near-perfect cache hit rates after warmup
- zero spill
- zero lookaside miss pressure

That means a process-global page-cache experiment would be solving a problem we do
not currently have. The measurement tooling was still useful, but the optimization
it was meant to justify is not warranted by the data.
