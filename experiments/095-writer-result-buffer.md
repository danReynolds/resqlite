# Experiment 095: Persistent writer result buffer

**Date:** 2026-04-23
**Status:** Rejected

## Problem

`executeWrite` allocates a 16-byte native result buffer for every write so C can
return `affectedRows` and `lastInsertId`. The writer isolate is single-threaded,
so this buffer could be allocated once and reused.

## Hypothesis

Moving the result buffer to per-worker persistent storage should remove a small
calloc/free pair from every single-statement write and improve small write
latency.

## Approach

Replaced the per-call result-buffer allocation in `executeWrite` with a
top-level writer-isolate buffer. The experiment was run in isolation and then
reverted before the next candidate.

## Results

Artifacts:

- `benchmark/profile/results/exp095-writer-result-buffer-dispatch.log`
- `benchmark/results/2026-04-23T19-19-25-exp095-writer-result-buffer.md`
- `benchmark/results/2026-04-23T19-19-25-exp095-writer-result-buffer.json`

Focused dispatch moved only marginally:

| Workload | Baseline | Experiment |
|---|---:|---:|
| Noop execute p50 | 9 us | 10 us |
| Single insert execute p50 | 16 us | 15 us |
| Merge executeBatch p50 | 107 us | 106 us |

The full release comparison reported **0 wins, 14 regressions, 139 neutral**.
The write-path medians were mostly within ordinary run variance.

## Decision

Rejected.

The allocation is theoretically removable, but the practical signal is not
strong enough to justify the extra lifetime management and top-level native
state.
