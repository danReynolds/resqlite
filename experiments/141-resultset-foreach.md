# Experiment 141: ResultSet forEach Fast Path

**Date:** 2026-06-05
**Status:** In Review
**Direction:** `result-transfer-shape`

## Problem

`ResultSet` uses `ListMixin<Row>` so the shipped result shape stays compact:
one flat values list, one shared schema, and lazy row views. Exp 032 optimized
the `Row` map facade itself, but `ResultSet.forEach` still inherited the
generic list-mixin traversal path.

That leaves a narrow main-isolate consumer cost: callers who write
`rows.forEach((row) { ... })` pay generic list iteration machinery even though
`ResultSet` can construct each lazy `Row` directly from the flat values list.

## Hypothesis

Override `ResultSet.forEach` to walk row offsets directly. This should improve
explicit `rows.forEach` consumers without changing the public API, result
transport shape, `operator []`, or normal indexed loops.

The broader idea of overriding `ResultSet.iterator` is plausible, but should
only be accepted if it improves `for-in` without moving unrelated controls.

## Approach

Implemented a direct `ResultSet.forEach` override in `lib/src/row.dart`:

- cache `_values`, `_schema`, and `columnCount` locally
- walk offsets in `columnCount` strides
- call the supplied action with `Row._(values, schema, offset)`

Added `benchmark/experiments/resultset_iteration.dart`, a focused AOT
microbenchmark that constructs a 10,000-row x 8-column `ResultSet` and compares
`for-in`, `rows.forEach`, and indexed loops across length-only and lookup-heavy
consumers.

## Results

Focused aggregate:
[`benchmark/profile/results/exp-141-resultset-foreach.md`](../benchmark/profile/results/exp-141-resultset-foreach.md)

Decision rows from two paired AOT runs:

| Case | Pair A baseline | Pair A candidate | Pair B baseline | Pair B candidate |
|---|---:|---:|---:|---:|
| forEach length | 18.590 ms | 14.677 ms (-21.0%) | 15.354 ms | 14.593 ms (-5.0%) |
| forEach lookup | 108.888 ms | 92.158 ms (-15.4%) | 99.837 ms | 80.093 ms (-19.8%) |
| indexed length control | 24.427 ms | 24.209 ms (-0.9%) | 22.187 ms | 22.491 ms (+1.4%) |
| indexed lookup control | 88.082 ms | 82.873 ms (-5.9%) | 72.613 ms | 76.715 ms (+5.6%) |

The accepted direct `forEach` override consistently improved lookup-heavy
`rows.forEach` consumption by 15-20%. Length-only `forEach` improved in both
pairs, though the smaller second-pair delta is below the local noise floor.
Indexed-loop controls stayed in the same band, which matches the scope of the
change.

The broader `ResultSet.iterator` override was tested and rejected. It improved
some `for-in` medians, but moved controls noisily enough that the extra surface
was not worth accepting.

## Decision

**Accepted for review.** Keep the direct `ResultSet.forEach` override and leave
`iterator` inherited from `ListMixin`.

This is a small internal main-isolate consumption win. It does not change
result transport, map materialization cost, or the public select contract.
Future result-shape experiments should still rely on full consumer-cost
evidence before changing API or storage shape.

## Future Notes

Do not broaden this into a custom `ResultSet.iterator` without cleaner evidence
than this run produced. If future full-consumption benchmarks show `for-in`
itself as material, re-test iterator changes with stable indexed controls and a
real SQLite-backed workload.
