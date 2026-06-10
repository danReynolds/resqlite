# Experiment 160 — Tier-1 incremental stream maintenance: profile aggregate

Date: 2026-06-10

Harnesses:

- `benchmark/profile/ivm_engage_check.dart` (new): A11c-overlap-shaped
  engagement check printing the exp 160 profile counters.
- `benchmark/profile/writer_sqlite_wall_audit.dart` (exp 147 harness),
  single pass per side, baseline (main) → candidate (exp-160), machine
  otherwise idle.
- `benchmark/run_tracelite_experiment.dart --direction=stream-rerun-dispatch`,
  two passes (standard order + order-flipped).

## Engagement (profile counters, candidate)

50 streams x 500 writes, A11c-overlap shape (every write touches a
projected column):

```
ivm_skipped=24,500  ivm_applied=500  ivm_bail=0  invalidate_count=500
```

24,500 of 25,000 per-stream invalidation decisions were proven misses
(no reader dispatch, no SQLite); the remaining 500 were local patches.
Zero re-queries reached the reader pool during the burst.

## Writer wall split audit (single pass per side)

Baseline (main @ b32177a):

| workload | wall_ms | writer_sqlite_us | invalidate_us | residual_us | emissions |
|---|---:|---:|---:|---:|---:|
| A11c baseline (0 streams x 500 writes) | 96.50 | 28,080 | 0 | 68,417 | 0 |
| A11c disjoint (50 x 500) | 100.57 | 22,995 | 21,909 | 55,669 | 0 |
| A11c overlap (50 x 500) | 186.46 | 21,418 | 29,974 | 135,071 | 44 |
| keyed PK subscriptions (50 x 200) | 46.87 | 11,208 | 7,317 | 28,340 | 3 |

Candidate (exp-160):

| workload | wall_ms | writer_sqlite_us | invalidate_us | residual_us | emissions |
|---|---:|---:|---:|---:|---:|
| A11c baseline (0 streams x 500 writes) | 75.38 | 22,380 | 0 | 52,998 | 0 |
| A11c disjoint (50 x 500) | 104.16 | 17,684 | 24,120 | 62,360 | 0 |
| A11c overlap (50 x 500) | 132.02 | 16,717 | 67,340 | 47,966 | 500 |
| keyed PK subscriptions (50 x 200) | 25.50 | 6,321 | 8,896 | 10,287 | 3 |

A11c overlap −29% wall while delivering 500 emissions vs 44 (the
baseline's re-query latency coalesces/suppresses most per-write
changes); keyed-PK −46%. `invalidate_us` grows on overlap because
patch+emit now run inline in the invalidation pass; the residual bucket
(round-trip + completion scheduling) collapses 135k → 48k µs.

## Tracelite decision summary

Pass 1 (baseline phase first, candidate second; CVs tight on both
sides):

| scenario | delta | 95% CI | p |
|---|---:|---|---|
| many-streams-writer-throughput | −18.5% | −122..−96.3 ms | 3.4e-6 |
| keyed-pk-subscriptions | −14.1% | −60.0..−27.4 ms | 1.6e-10 |
| high-cardinality-fanout | +2.11% | +2.59..+12.8 ms | 0.009 |

Keyed-PK within-run CV drops 0.13–0.15 → 0.02–0.05 under the candidate.

Pass 2 (order flipped): see experiment writeup.

Raw per-run JSONs and tracelite artifacts are local-only under
`build/tracelite-experiments/`.
