# Experiment 025: `PRAGMA optimize`

**Date:** 2026-04-08
**Status:** Rejected

## Hypothesis

SQLite recommends `PRAGMA optimize` to refresh planner statistics and opportunistically
run lightweight analysis. If planner quality is holding back app-shaped reads, running
`PRAGMA optimize=0x10002` after schema + seed setup should improve joins, parameterized
queries, or medium/large reads.

## Change

Added a benchmark-only helper that ran:

```sql
PRAGMA optimize=0x10002
```

after resqlite schema creation and seeding in the package-local read-heavy suites.

This was intentionally benchmark-scoped, not product code, because resqlite does not
currently have a clean schema-settled lifecycle hook.

## Results

Benchmark run:
- Baseline: `2026-04-08T17-14-06-exp025-baseline.md`
- Optimize: `2026-04-08T17-15-42-exp025-optimize.md`

Headline comparison versus the clean baseline:

| Benchmark | Baseline | Optimize | Delta |
|---|---:|---:|---:|
| Select Maps 100 rows | 0.36ms | 0.40ms | +11% |
| Select Maps 1000 rows | 0.40ms | 0.44ms | +10% |
| Select Maps 5000 rows | 2.27ms | 2.39ms | +5% |
| Parameterized queries | 15.41ms | 15.30ms | -1% |
| Interactive transaction | 0.06ms | 0.05ms | -17% |

Package benchmark summary versus baseline:
- 2 wins
- 1 regression
- 14 neutral

The one clear regression was the 100-row maps case. The few wins were either tiny
or in workloads that are noisy enough that a single run is not persuasive.

## Decision

**Rejected** as a performance optimization.

This does not mean `PRAGMA optimize` is wrong in production. It likely still belongs
in an application lifecycle with real long-lived datasets and skewed query plans.
But within resqlite's current benchmark suite, it did not produce a compelling or
reliable speedup, so it is not worth adding complexity just for benchmark wins.
