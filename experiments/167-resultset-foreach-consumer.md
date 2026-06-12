# Experiment 167: ResultSet.forEach Consumer Recheck

**Date:** 2026-06-12
**Status:** Rejected
**Direction:** `result-transfer-shape`
**Benchmark Run:** Focused SQLite-backed consumer benchmark, `benchmark/experiments/resultset_foreach_consumer.dart`

## Problem

Closed PR #125 / exp 141 found that overriding `ResultSet.forEach` could speed
up explicit `rows.forEach(...)` consumers on a synthetic `ResultSet`
microbenchmark. It was closed without merging because the result was not tied
to a current Tracelite or full-consumer-cost decision lane.

Exp 158 changed the surrounding row-consumption cost model by adding a
schema-name identity fast path and private `HashMap` fallback for
`RowSchema.indexOf`. That made the old exp 141 result stale enough to recheck,
but only if the recheck used real rows returned by `Database.select()`.

## Hypothesis

Override `ResultSet.forEach` to walk row offsets directly through the flat
value buffer. The change should help explicit `rows.forEach` consumers while
leaving `for-in`, indexed loops, result transport, `Row`, and public API shape
unchanged.

## Approach

Added `benchmark/experiments/resultset_foreach_consumer.dart`, which:

- seeds a real resqlite database with the standard 10,000-row, 6-column schema
- calls `Database.select()` before each measured sample so the consumer sees
  real `ResultSet` instances
- times `for-in lookup`, `forEach lookup`, `indexed lookup`, and
  `forEach length` consumers over the returned rows

The candidate runtime patch was the same narrow shape as exp 141: add a
`ResultSet.forEach` override that caches `_values`, `_schema`, and
`columnCount`, then calls the action with `Row._(...)` while walking offsets.
The runtime patch was removed after the result; only the benchmark and record
remain.

## Results

Focused aggregate:
[`benchmark/profile/results/exp-167-resultset-foreach-consumer.md`](../benchmark/profile/results/exp-167-resultset-foreach-consumer.md)

Headline JIT pairs:

| Case | Pair A baseline | Pair A candidate | Pair B baseline | Pair B candidate |
|---|---:|---:|---:|---:|
| forEach lookup | 30.525 ms | 28.383 ms (-7.0%) | 28.563 ms | 30.942 ms (+8.3%) |
| forEach length | 9.439 ms | 8.010 ms (-15.1%) | 8.652 ms | 9.490 ms (+9.7%) |
| for-in lookup control | 25.440 ms | 24.643 ms (-3.1%) | 27.531 ms | 28.311 ms (+2.8%) |
| indexed lookup control | 21.553 ms | 20.115 ms (-6.7%) | 20.778 ms | 21.143 ms (+1.8%) |

Pair A favored the candidate modestly, but controls moved in the same
direction. The longer confirmation pair reversed the target result:
`forEach lookup` became 8.3% slower and `forEach length` became 9.7% slower.

I tried an AOT-compiled comparison to reduce JIT effects, but the standalone
binary could not resolve resqlite's native asset (`resqlite_open`). The JIT
evidence is enough to reject the tiny runtime change; extending the measurement
system just to rescue this candidate would not be proportional.

## Decision

**Rejected.** The `ResultSet.forEach` override does not produce a stable current
win on a SQLite-backed full-consumer lane after exp 158's schema-index change.
No runtime code was kept.

No archive tag was created. The rejected implementation was a single
reconstructable method override, and the writeup captures the exact shape and
current measurements.

## Future Notes

Keep `benchmark/experiments/resultset_foreach_consumer.dart` for future
result-shape rechecks. Do not revive the exp 141 override unless a future Dart
runtime or real workload changes the result and shows a stable target win while
controls stay neutral.
