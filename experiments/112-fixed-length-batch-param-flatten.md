# Experiment 112: Fixed-length batch parameter flattening

**Date:** 2026-04-28T10:47:00
**Status:** Rejected
**Direction:** `parameter-encoding-and-binding`, `measurement-system`

## Problem

Experiment 096 rejected direct nested batch parameter encoding because it added
a second encoder path and did not move the benchmark suite. Experiment 109 then
made the shared `allocateParams` path faster by packing text and blob bytes
inline, leaving one simpler adjacent question: does the existing Dart-side
batch flatten step still cost enough to optimize?

`executeBatchWrite` and `executeNestedBatchWrite` flatten
`List<List<Object?>>` into a temporary `List<Object?>` before calling
`allocateParams`. The live implementation used a growable list plus `addAll`,
which can resize while building large batches.

## Hypothesis

Pre-sizing the flattened list and filling it by index should remove growable
list resizing without reviving experiment 096's larger duplicate-encoder
complexity. The result would be most visible on large text-param batch writes,
especially the 10,000-row batch insert shape that benefited from experiment
109.

Accept if the focused benchmark shows a repeatable large-batch improvement
outside run noise, with no small-batch regression. Reject if medians overlap or
the effect stays below the release-suite decision threshold.

## Approach

Added a focused exploratory benchmark:

```text
dart run benchmark/experiments/batch_param_flatten.dart --iterations=50
```

The benchmark prebuilds `paramSets` outside the timed region, then measures one
`executeBatch` call for 100, 1,000, and 10,000 rows. Between samples it deletes
the previously inserted rows outside the timed region, so the timed portion is
centered on writer-isolate batch preparation and SQLite batch execution.

The candidate production change was deliberately small:

```dart
final flattened = List<Object?>.filled(
  paramSets.length * paramCount,
  null,
  growable: false,
);
var offset = 0;
for (final set in paramSets) {
  for (var i = 0; i < paramCount; i++) {
    flattened[offset + i] = set[i];
  }
  offset += paramCount;
}
```

Both top-level and nested transaction batch writes continued to use the shared
`allocateParams` encoder from experiment 109.

## Results

Focused benchmark p50 wall time:

| Run | Variant | 100 rows | 1,000 rows | 10,000 rows |
|---|---|---:|---:|---:|
| 1 | Baseline | 0.169 ms | 0.426 ms | 4.042 ms |
| 2 | Candidate | 0.210 ms | 0.372 ms | 3.479 ms |
| 3 | Candidate | 0.182 ms | 0.379 ms | 3.578 ms |
| 4 | Baseline | 0.220 ms | 0.402 ms | 3.727 ms |
| 5 | Candidate | 0.154 ms | 0.413 ms | 3.779 ms |

The first candidate run looked promising at 10,000 rows, but the confirmation
passes overlapped with the baseline. The 1,000-row and 10,000-row candidate
medians stayed directionally plausible, but the effect was small enough that
run ordering and tail noise could explain it. The 100-row shape was mixed and
not a target.

The production change was reverted after measurement. No release-suite run was
performed because the focused benchmark did not establish a reliable target
signal.

## Decision

**Rejected.**

Fixed-length flattening is much cheaper than experiment 096's duplicate
encoder, but it still does not produce an acceptance-level signal. Dart's
growable-list plus `addAll` path appears good enough relative to SQLite batch
execution and the shared inline parameter encoder.

The focused benchmark remains useful as a quick probe for future batch
parameter work, but the production code should stay with the simpler current
flattening path.

## Future Notes

Do not revisit batch parameter flattening by itself. Reopen only if a profiler
shows the writer isolate spending material time building the temporary flat
list, or if a new batch workload has much wider parameter rows than the current
two-param INSERT benchmarks. Any future attempt should preserve one shared
parameter encoder unless measurement shows the larger direct nested encoding
shape from experiment 096 has become worthwhile.
