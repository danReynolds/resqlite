# Experiment 140: SQLite-backed result consumer cost audit

**Date:** 2026-06-04
**Status:** In Review
**Direction:** `result-transfer-shape`, `measurement-system`
**Benchmark Run:** None

## Problem

The `result-transfer-shape` direction had one unresolved measurement blocker:
a full-consumption benchmark that exercises real `Map` / `Row` access patterns
end-to-end. Exp 082 already showed the current `ResultSet` / `Row` message graph
beating materialized maps and binary-row facades in a synthetic isolate-transfer
harness, but that did not include SQLite decode, statement execution, or
actual `db.select()` results.

Without a SQLite-backed consumer benchmark, future result-shape experiments
would be forced to infer too much from synthetic payloads. The missing decision
was whether normal row consumption is a large enough part of end-to-end
`select()` cost to justify another internal result-shape change while keeping
the public API lean.

## Hypothesis

The current lazy `Row` facade should remain close to optimal for normal access
patterns. If that is true, then consuming real SQLite-backed results by `id`
lookup or `row.forEach` should stay a small fraction of total `select()` cost,
especially at larger row counts where decode and isolate transfer dominate.

The exception should be explicit materialization with `Map.from(row)`: that
allocates a new map per row by choice, so any large cost there points to caller
behavior or a possible specialized API, not an internal replacement for the
default lazy result shape.

## Approach

Added `benchmark/experiments/result_consumer_cost.dart`, a focused harness that:

- seeds numeric-heavy and mixed-schema SQLite tables at 100, 1,000, and 10,000
  rows;
- runs repeated `db.select()` calls against the real resqlite reader path;
- measures `select()` wall and main-isolate consumption wall separately;
- compares four consumer modes: `length only`, `id key per row`,
  `forEach all cells`, and `Map copy`.

The aggregate result is committed at
`benchmark/profile/results/exp-140-result-consumer-cost.md`.

The AOT/product executable path was checked, but the standalone compiled
executable could not resolve resqlite's native asset map on this local toolchain
(`resqlite_open` was not available to the compiled process). The committed
measurement uses the supported `dart run` path and records the runtime as
JIT/profile-debug.

## Results

The 10,000-row cases are the decision-relevant rows because fixed overhead and
timer granularity dominate smaller tables.

| dataset | consumer | select p50 | consume p50 | total p50 | consume % |
|---|---|---:|---:|---:|---:|
| numeric | length only | 3.716 ms | 0.000 ms | 3.716 ms | 0.0% |
| numeric | id key per row | 3.522 ms | 0.167 ms | 3.732 ms | 4.5% |
| numeric | forEach all cells | 3.254 ms | 0.448 ms | 3.794 ms | 11.8% |
| numeric | Map copy | 3.298 ms | 4.946 ms | 9.074 ms | 54.5% |
| mixed | length only | 3.998 ms | 0.000 ms | 3.998 ms | 0.0% |
| mixed | id key per row | 4.034 ms | 0.163 ms | 4.197 ms | 3.9% |
| mixed | forEach all cells | 4.242 ms | 0.386 ms | 4.615 ms | 8.4% |
| mixed | Map copy | 3.563 ms | 3.388 ms | 7.092 ms | 47.8% |

Normal lazy access stays small at 10,000 rows: `id` lookup is 3.9-4.5% of
total wall, and full-cell `forEach` is 8.4-11.8%. Those numbers do not reopen
the broad result-shape direction; most wall still sits in SQLite decode,
worker-side result construction, and isolate delivery.

`Map.from(row)` is materially different. It makes consumption 47.8-54.5% of
total wall by allocating and populating 10,000 maps. That is useful evidence,
but it is not an internal `ResultSet` replacement signal: the default contract
already avoids those per-row maps unless the caller explicitly asks for them.

## Decision

**In Review — measurement.** The full-consumption benchmark gap is closed.
The current lazy `ResultSet` / `Row` shape remains the right default for the
lean `select()` API under the measured access modes.

Future result-transfer work should not retry broad internal row-shape
replacements unless this harness, or a comparable real workload, shows
consumer cost outside explicit `Map` materialization. If real apps often
materialize every row into maps, the follow-up should be framed as caller
guidance or a specialized materialized-map API decision, not as a hidden
replacement for lazy rows.

## Future Notes

- Re-run this harness under product-mode native assets once standalone AOT
  native-asset resolution is available in the local toolchain.
- Keep tracking Dart SDK #50068 for deeply immutable typed data. It remains
  open as of 2026-06-04, so exp 089's upstream blocker has not changed.
- Use `benchmark/experiments/result_consumer_cost.dart` as the acceptance gate
  for any future result-shape proposal that claims main-isolate row consumption
  headroom.
