# Experiment 131: Wide-batch transaction shape

**Date:** 2026-05-08
**Status:** In Review
**Direction:** `parameter-encoding-and-binding`, `measurement-system`, `transaction-control-paths`
**Benchmark Run:** None (measurement-only)

## Problem

Exp 130 split the native `resqlite_run_batch*` wall and found that wide mixed
batches are dominated by `sqlite3_step` plus COMMIT. Reset and statement lookup
were tiny, and binding was material but ceiling-limited.

That left one ambiguity: the COMMIT bucket was measured inside the top-level
`resqlite_run_batch_profiled` wrapper. Before trying WAL or transaction-control
work, we needed to know whether that bucket was inherent transaction-finish
cost or an artifact of the top-level batch wrapper.

## Hypothesis

If COMMIT is wrapper-specific, then manually running:

```text
BEGIN IMMEDIATE
resqlite_run_batch_nested_profiled(...)
COMMIT
```

should produce a meaningfully different split from top-level
`resqlite_run_batch_profiled(...)`.

If COMMIT is inherent transaction-finish / WAL behavior, then both shapes should
land in the same steady-state band once the explicit BEGIN/COMMIT stopwatches
are added back around the nested batch.

Accept this as a measurement experiment if it can separate the row-loop batch
call from explicit transaction control without adding more library
instrumentation.

## Approach

Added `benchmark/profile/wide_batch_transaction_shape.dart`, which uses the
profiled native entrypoints introduced by exp 130:

- `top-level batch`: calls `executeBatchWriteProfiled`, which enters
  `resqlite_run_batch_profiled` and reports native BEGIN/COMMIT inside the
  batch profile;
- `manual tx + nested batch`: calls native `resqlite_tx_begin_immediate`,
  then `executeNestedBatchWriteProfiled`, then native `resqlite_tx_commit`,
  timing the explicit transaction-control calls from Dart and adding them back
  to the nested batch profile.

Both paths use the same 10,000-row x 20-parameter mixed rows from exp 129 /
exp 130:

- ASCII text;
- Unicode text;
- emoji text.

This intentionally bypasses writer-isolate and stream-invalidation overhead.
It is a native transaction-shape audit, not an end-to-end public API benchmark.

## Results

Command:

```text
dart run -DRESQLITE_PROFILE=true \
  benchmark/profile/wide_batch_transaction_shape.dart --markdown --repeats=5
```

The first pass is warmup-heavy. Passes 2-5 are the useful steady-state band.

| workload | scenario | steady native_total_us | commit / native | step / native | bind / native | reset / native |
|---|---|---:|---:|---:|---:|---:|
| mixed ASCII text | top-level batch | 9048-10187 | 24.93-28.83% | 45.72-49.09% | 14.12-14.77% | 2.33-2.71% |
| mixed ASCII text | manual tx + nested batch | 8941-10222 | 25.62-28.43% | 46.15-48.03% | 14.39-15.13% | 2.44-2.82% |
| mixed Unicode text | top-level batch | 9427-10439 | 29.78-32.83% | 41.96-44.88% | 14.05-14.40% | 2.11-2.38% |
| mixed Unicode text | manual tx + nested batch | 9547-10465 | 30.46-34.22% | 42.19-45.03% | 13.49-14.27% | 2.29-2.53% |
| mixed emoji text | top-level batch | 13917-15783 | 49.47-54.44% | 30.07-32.46% | 8.52-10.12% | 1.55-1.71% |
| mixed emoji text | manual tx + nested batch | 14243-14726 | 51.54-54.48% | 29.63-31.96% | 9.05-9.40% | 1.59-1.69% |

Raw committed output:

```text
benchmark/profile/results/exp-131-wide-batch-transaction-shape.md
```

## Decision

**Accept for review - measurement.**

The top-level batch wrapper is not the source of the large COMMIT bucket. Once
the explicit COMMIT stopwatch is added back around a nested profiled batch, the
manual transaction shape lands in the same steady-state band as the top-level
batch:

- ASCII: top-level 9.0-10.2 ms native total vs manual tx 8.9-10.2 ms;
- Unicode: top-level 9.4-10.4 ms vs manual tx 9.5-10.5 ms;
- emoji: top-level 13.9-15.8 ms vs manual tx 14.2-14.7 ms.

This retires the idea that `resqlite_run_batch` needs a structurally different
top-level transaction wrapper for the current wide-batch shape. The remaining
large buckets are the actual row stepping and the actual transaction finish.

The useful implication is narrower:

- batching multiple logical write batches inside one user transaction can
  amortize COMMIT, and the existing API already supports that;
- for a single large batch, moving it through the nested path does not remove
  commit cost;
- future implementation work should not target the C batch loop wrapper. It
  should either target WAL/commit behavior directly, with reader-concurrency
  guardrails, or stay on SQLite row-writing/step-side behavior.

## Future Notes

- Keep reset, statement lookup, and top-level wrapper reshaping off the active
  wide-batch candidate list for this workload.
- A WAL/commit experiment needs a guardrail for concurrent readers and stream
  workloads. Faster commits that block readers or increase checkpoint stalls
  would not be an acceptable package-level tradeoff.
- If a production app issues many smaller `executeBatch` calls back-to-back,
  measure grouping them in `Database.transaction` before adding new internal
  machinery. The API already exposes the likely commit-amortization path.
