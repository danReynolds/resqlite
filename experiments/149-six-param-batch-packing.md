# Experiment 149: Six-parameter batch packing

**Date:** 2026-06-08
**Status:** In Review
**Direction:** `parameter-encoding-and-binding`
**Benchmark Run:** Tracelite profile, `exp149-six-param-batch-packing`

## Problem

Experiments 125 and 126 justified direct payload packing for large wide batches,
while experiment 146 rejected broadening the ASCII fast path to small/narrow
batch writes. That left a middle shape uncovered: app-like merge batches that
are not 20-parameter ORM rows, but still bind enough repeated text parameters
for temporary UTF-8 list allocation to matter.

The Tracelite profile workload from exp 143 exposed exactly that shape. Its
`merge_rounds` phase repeatedly executes 100-row `INSERT OR REPLACE` batches
against a six-parameter row:

- `id`
- `name`
- `description`
- `value`
- `category`
- `created_at`

On current main, that path still used the generic batch encoder because the
ASCII fast path required at least eight parameters and 8,192 total bound
parameters.

## Hypothesis

Lowering the guarded ASCII batch-packing threshold from `8 / 8192` to `6 / 600`
should improve the profile merge-round path without reviving exp 146's rejected
small/narrow broadening. The new guard admits repeated six-parameter batches
where Tracelite shows material writer work, while keeping one-, two-, and
three-parameter batch writes on the generic path.

Reject if the profile merge-round improvement does not reproduce, if focused
batch correctness fails, or if the implementation requires new API surface or
complex shape-specialization code.

## Approach

Created two resqlite worktrees from `origin/main` at
`841e3623f0c05cb978624ebdcd84b9dfe2c36eaf`:

- Baseline: `/Users/dan/.codex/worktrees/resqlite-exp149-baseline`
- Candidate: `/Users/dan/.codex/worktrees/resqlite-exp149-six-param-batch-packing`

Candidate patch:

```diff
-const int _asciiBatchMinParamCount = 8;
-const int _asciiBatchMinTotalParamCount = 8192;
+const int _asciiBatchMinParamCount = 6;
+const int _asciiBatchMinTotalParamCount = 600;
```

A focused database test adds a six-column `executeBatch` case with 100 rows per
batch. The first batch exercises the ASCII fast path, and the second includes a
non-ASCII string plus blobs so the UTF-8 fallback stays covered at the new
threshold.

The integrated Tracelite A/B strict batch scenario was deliberately not used as
the proof for this change: `narrow-batch-insert` is a two-parameter lane, and
`sync-burst` is a three-parameter lane below this guard. Exp 146 already showed
that broad small/narrow admission is not justified. This run instead uses the
Tracelite profile workload that actually exposed the six-parameter merge cost.

## Results

Paired profile command:

```text
/Users/dan/Coding/flutter_arm64/bin/cache/dart-sdk/bin/dart run \
  benchmark/profile/run_tracelite_profile.dart \
  --tracelite-root=/Users/dan/Coding/tracelite \
  --dart=/Users/dan/Coding/flutter_arm64/bin/cache/dart-sdk/bin/dart \
  --label=exp149-six-param-batch-packing-candidate \
  --out-dir=build/tracelite-profile/exp149-six-param-batch-packing-candidate \
  --allow-unpinned-tracelite \
  --no-graph-data
```

Tracelite revision:

```text
8fbfac7675348fa2a765e3b0c36f3a5a22c67fc0
```

Profile artifacts:

- Baseline:
  `build/tracelite-profile/exp149-six-param-batch-packing-baseline/workload-summary.json`
- Candidate:
  `build/tracelite-profile/exp149-six-param-batch-packing-candidate/workload-summary.json`
- Candidate insights:
  `build/tracelite-profile/exp149-six-param-batch-packing-candidate/insights.md`

Workload C, `merge_rounds`:

| Metric | Baseline | Candidate | Delta |
|---|---:|---:|---:|
| `executeBatch` p50 | 88 us | 75 us | -14.8% |
| `executeBatch` work p50 | 75 us | 62 us | -17.3% |
| `executeBatch` p90 | 96 us | 84 us | -12.5% |
| `writer_sqlite_us` | 87,895 us | 75,947 us | -13.6% |

Other profile lanes did not move in a way that changes the decision:

- Noop dispatch floors were identical at 9 us reader / 13 us writer.
- Single inserts do not use the batch path.
- Point queries do not use the batch path.

## Decision

**Accept for review.**

This is the narrow version of the batch-threshold change that exp 146 was
missing. It does not reopen the rejected small/narrow path; it admits the
specific six-parameter repeated merge shape that Tracelite showed was spending
real writer-side time in SQLite-facing batch execution.

The implementation cost is low: two threshold constants and one focused
correctness test. The existing generic encoder remains the fallback for
non-ASCII text and for narrow batch shapes.

## Future Notes

Do not lower this below six parameters without a new workload and a Tracelite
decision artifact that clears the primary gate. Exp 146 remains the guardrail:
small/narrow writes should stay generic unless a real workload proves otherwise.

The current Tracelite suite still lacks a strict policy scenario for the
six-parameter merge-round profile shape. If this path becomes a recurring
product workload, add that as a Tracelite suite scenario instead of reusing
`narrow-batch-insert` as a proxy.

## Validation

- `dart pub get`
- `dart analyze lib/src/native/resqlite_bindings.dart test/database_test.dart`
- `dart test test/database_test.dart`
- `dart test test/transaction_test.dart`
- Tracelite profile baseline:
  `benchmark/profile/run_tracelite_profile.dart --label=exp149-six-param-batch-packing-baseline`
- Tracelite profile candidate:
  `benchmark/profile/run_tracelite_profile.dart --label=exp149-six-param-batch-packing-candidate`
