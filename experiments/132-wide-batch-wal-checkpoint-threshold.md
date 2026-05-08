# Experiment 132: Wide-batch WAL checkpoint threshold

**Date:** 2026-05-08
**Status:** In Review
**Direction:** `parameter-encoding-and-binding`, `measurement-system`, `transaction-control-paths`
**Benchmark Run:** None (focused profile and guardrail harness)

## Problem

Exp 130 found that the native wide-batch path is dominated by SQLite stepping
plus COMMIT. Exp 131 then showed the COMMIT bucket is inherent
transaction-finish/WAL behavior, not an artifact of the top-level
`resqlite_run_batch` wrapper.

The remaining ambiguity was whether COMMIT was pure SQLite transaction finish
or whether resqlite's writer WAL hook was doing extra checkpoint work inline.
The hook previously ran a PASSIVE checkpoint whenever the WAL reached 500
pages.

## Hypothesis

If the 500-page hook is firing inside COMMIT for medium-large wide batches,
then raising the internal checkpoint threshold could reduce write-visible tail
latency while keeping WAL growth modest.

Accept a small threshold bump only if:

- the checkpoint wall is directly measured inside COMMIT;
- concurrent-reader and stream guardrails stay healthy;
- larger threshold values do not look safer than the smaller bump.

Reject broad checkpoint deferral if it only moves cost into larger periodic
stalls or unbounded WAL growth.

## Approach

Added `benchmark/profile/wide_batch_wal_checkpoint.dart`.

The harness extends the native batch profile with WAL-hook counters:

- `wal_hook_count`
- `wal_pages_max`
- `checkpoint_count`
- `checkpoint_busy_count`
- `checkpoint_pages`
- `checkpoint_us`

It also adds an experiment-only internal threshold setter so the same binary can
compare checkpoint policies:

- 500 pages: old baseline;
- 1000 pages: candidate;
- 2000 / 5000 pages: larger deferral checks;
- disabled hook checkpoint: ceiling / negative-control shape.

Guardrails cover:

- single 10,000-row x 20-parameter wide batches across ASCII, Unicode, and
  emoji text;
- public `Database.executeBatch` under concurrent reader queries;
- public stream emissions across repeated batch writes;
- sustained 60 x 2,000-row emoji batches on one connection to expose periodic
  checkpoint tail latency.

The production change is intentionally narrow: raise
`RESQLITE_WRITER_PASSIVE_CHECKPOINT_PAGES` from 500 to 1000.

## Results

Command:

```text
dart run -DRESQLITE_PROFILE=true \
  benchmark/profile/wide_batch_wal_checkpoint.dart --markdown \
  --repeats=5 --rows=10000
```

Raw output:

```text
benchmark/profile/results/exp-132-wide-batch-wal-checkpoint.md
```

Single-batch medians:

| workload | baseline 500 wall | candidate 1000 wall | native_us | commit_us | checkpoint_us |
|---|---:|---:|---:|---:|---:|
| mixed ASCII text | 13.23 ms | 12.47 ms | 9896 -> 9422 | 2559 -> 2481 | 0 -> 0 |
| mixed Unicode text | 14.70 ms | 14.53 ms | 10061 -> 10037 | 3013 -> 3152 | 0 -> 0 |
| mixed emoji text | 20.74 ms | 17.26 ms | 14146 -> 11112 | 7075 -> 3670 | 2686 -> 0 |

ASCII and Unicode stayed below the old 500-page threshold in this shape
(`wal_pages_max` 373 and 457), so the threshold change does not explain their
small run-to-run movement. Emoji crossed it (`wal_pages_max` 529), and the
baseline paid an inline PASSIVE checkpoint inside COMMIT.

Public concurrent-reader guardrail:

| policy | write_wall_ms | read_median_us | read_p90_us | read_max_us | wal_bytes |
|---|---:|---:|---:|---:|---:|
| baseline 500 | 66.63 | 23 | 55 | 6602 | 2228952 |
| candidate 1000 | 52.38 | 17 | 36 | 3123 | 3576192 |

Stream guardrail:

| policy | expected_emissions | observed_emissions | final_count |
|---|---:|---:|---:|
| baseline 500 | 6 | 6 | 2500 |
| candidate 1000 | 6 | 6 | 2500 |

Sustained 60 x 2,000-row emoji sweep:

| policy | total_wall_ms | batch_p90_us | batch_max_us | checkpointed_batches | wal_bytes |
|---|---:|---:|---:|---:|---:|
| baseline 500 | 340.98 | 6419 | 8448 | 12 | 2410232 |
| candidate 1000 | 328.20 | 4764 | 12006 | 6 | 4486712 |
| 2000 pages | 332.95 | 4010 | 20359 | 3 | 8643792 |
| 5000 pages | 322.14 | 4266 | 19701 | 1 | 20637112 |
| disabled | 307.33 | 4016 | 4691 | 0 | 28325032 |

The higher thresholds and disabled hook improve some medians, but they do so by
deferring more checkpoint work. The 2000/5000-page policies create much larger
checkpoint spikes, and disabling checkpointing grows the WAL to 28 MB before the
manual PASSIVE checkpoint.

## Decision

**Accept for local branch.**

Raise the default passive writer checkpoint threshold from 500 to 1000 pages.

This is the smallest policy change that removes the inline checkpoint from the
measured 10k x20 emoji batch while keeping WAL growth modest. It also improves
the public concurrent-reader guardrail and preserves stream emission behavior.

Do not raise the threshold to 2000/5000 pages and do not disable the hook. Those
policies are useful ceilings, but they create larger periodic stalls and larger
WAL files. The safe conclusion is a small threshold retune, not broad checkpoint
deferral.

## Future Notes

- Keep exp 132's sustained sweep in any future checkpoint-policy evaluation.
- Treat checkpoint policy as a storage/concurrency tradeoff, not a local C-loop
  micro-optimization.
- The remaining wide-batch native headroom is more likely in SQLite row stepping
  than in reset, statement lookup, top-level wrapper shape, or broad checkpoint
  deferral.
