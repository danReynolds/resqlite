# Experiment 094: Dirty/read table string reuse

**Date:** 2026-04-23
**Status:** Rejected

## Problem

Dirty-table and read-table capture reuse fixed native arrays, but each capture
cycle still frees and duplicates the table-name string for the next active slot.
Repeated single-table writes and repeated stream subscriptions often touch the
same table name over and over.

## Hypothesis

If the next capture cycle writes the same table name into the same slot, reusing
the existing `strdup` buffer should avoid a free/allocate pair and reduce hot
write and stream setup cost without changing table-set semantics.

## Approach

Changed `read_set_add` and `dirty_set_add` so a reused slot keeps its existing
string when it already matches the incoming table name. The experiment was run
in isolation and then reverted before the next candidate.

## Results

Artifacts:

- `benchmark/profile/results/exp094-dirty-read-reuse-dispatch.log`
- `benchmark/results/2026-04-23T19-08-51-exp094-dirty-read-string-reuse.md`
- `benchmark/results/2026-04-23T19-08-51-exp094-dirty-read-string-reuse.json`

Focused dispatch was effectively unchanged:

| Workload | Baseline | Experiment |
|---|---:|---:|
| Single insert execute p50 | 16 us | 16 us |
| Merge executeBatch p50 | 107 us | 104 us |

The full release comparison reported **0 wins, 14 regressions, 139 neutral**.
The flagged regressions were broad enough that the tiny targeted allocation
avoidance is not a safe optimization signal.

## Decision

Rejected.

This optimization is below the measurement floor and may perturb the hot native
branch/cache behavior more than it helps. The existing simple free/strdup path
is easier to reason about and benchmark-neutral enough to keep.
