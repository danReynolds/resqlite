# Experiment 096: Direct batch parameter encoding

**Date:** 2026-04-23
**Status:** Rejected

## Problem

`executeBatch` flattens `List<List<Object?>>` into a temporary Dart
`List<Object?>` before encoding native parameter structs. For large batches,
that extra list is avoidable.

## Hypothesis

Writing native parameter structs directly from the nested parameter sets should
reduce large batch write overhead by avoiding the intermediate flattened list.

## Approach

Added nested-param allocation/free helpers and routed both top-level
`executeBatchWrite` and nested transaction batch writes through them. The C
batch API was unchanged. The experiment was run in isolation and then reverted.

## Results

Artifacts:

- `benchmark/profile/results/exp096-direct-batch-param-encoding-dispatch.log`
- `benchmark/results/2026-04-23T19-28-04-exp096-direct-batch-param-encoding.md`
- `benchmark/results/2026-04-23T19-28-04-exp096-direct-batch-param-encoding.json`

Focused dispatch did not move:

| Workload | Baseline | Experiment |
|---|---:|---:|
| Merge executeBatch p50 | 107 us | 106 us |

The full release comparison reported **0 wins, 1 regression, 152 neutral**.
Large batch medians trended in the right direction in the structured artifact,
but the harness did not classify the improvement as a reliable win and the code
added a substantial second parameter-encoding path.

## Decision

Rejected.

Avoiding the flattened list is a plausible cleanup only if batch payload
construction becomes a proven bottleneck. With the current suite, the added
allocator complexity is not justified.
