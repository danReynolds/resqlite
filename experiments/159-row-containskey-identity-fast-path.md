# Experiment 159: Row.containsKey identity fast path

**Date:** 2026-06-10
**Status:** Rejected
**Direction:** `result-transfer-shape`
**Benchmark Run:** Focused `row_map_facade` paired A/B
**Archive:** Not created; the candidate is a one-line private method swap (see
snippet below) and there is no surrounding scaffolding worth preserving. The
row.dart change was reverted before merge consistent with rejection.

## Problem

Experiment 158 added the schema-name identity fast path to `RowSchema.indexOf`
and observed a clean win on full row consumption — `row_map_facade` hot lookup
dropped 10.750 → 5.136 ms (-52%) and `select_maps` 10K main-isolate consumption
dropped 1.998 → 0.967 ms (-52%).

That experiment intentionally left `Row.containsKey` on the original direct
`_indexByName.containsKey(key)` path. The `containsKey` row median in exp 158
moved from 17.720 → 17.701 ms, recorded as neutral.

The bounded question for this run was therefore: does extending exp 158's
identity fast path to `Row.containsKey` produce a measurable win on the
same workload, or is the existing direct `HashMap.containsKey` already at
the noise floor of the available benchmark?

## Hypothesis

`Row.containsKey` currently bypasses `RowSchema.indexOf` and goes straight to
`_indexByName.containsKey(key)`. Routing it through `indexOf` would let
canonical-string lookups (the common case in user code that mirrors row.keys)
short-circuit inside the up-to-32-column identity scan that exp 158 already
established, without changing any public API and without affecting
`Row.operator[]`, which already uses `indexOf`.

Predicted ceiling: roughly the same shape as exp 158's hot-lookup delta, since
both paths now share the same `indexOf` call.

Accept only if `row_map_facade` containsKey medians drop materially relative to
baseline noise. Reject if the candidate collapses to the noise floor — a wide
identity scan plus HashMap fallback for non-identical keys is a real fallthrough
cost, and matching `HashMap.containsKey` on canonical strings alone is not a
merge-worthy outcome.

## Approach

`Row.containsKey` now calls `_schema.indexOf(key) >= 0` instead of
`_schema._indexByName.containsKey(key)`:

```dart
@override
bool containsKey(Object? key) =>
    key is String && _schema.indexOf(key) >= 0;
```

`indexOf` was unchanged. For schemas with `≤ 32` columns it still runs the
identity scan first, falling back to the private `HashMap<String, int>` for
non-identical or unknown keys. Schemas wider than 32 columns skip the identity
loop entirely and go straight to the HashMap, identical to exp 158's behavior.

No other code, public API, or transfer surface was touched.

A pre-run sanity check confirmed canonical-string identity holds in the
benchmark setup: `identical("updated_at", schema.names[5])` returned `true` and
`indexOf("updated_at")` returned `5`. So the identity fast path *does* fire on
the row_map_facade workload — the experiment is measuring the speedup of
identity-scan vs HashMap on canonical strings, not the cost of an unmatched
fast path.

## Results

Three paired runs of `dart run benchmark/experiments/row_map_facade.dart`,
stashing the change for baseline and unstashing for candidate. `containsKey`
row medians (8-column schema, 500,000 inner iterations per measurement):

| Run | Baseline row (ms) | Candidate row (ms) |
|---|---:|---:|
| 1 | 15.329 | 12.377 |
| 2 | 15.231 | 14.707 |
| 3 | 13.930 | 15.101 |

Run-median summary:

| Metric | Value |
|---|---:|
| Baseline median | 15.231 ms |
| Candidate median | 14.707 ms |
| Delta | -3.4% |
| Baseline run-to-run range | 13.930 – 15.329 ms (1.4 ms span) |
| Candidate run-to-run range | 12.377 – 15.101 ms (2.7 ms span) |

The candidate range fully overlaps the baseline range, and the run-3 candidate
median (15.101 ms) is *above* the run-3 baseline median (13.930 ms). The
nominal -3.4% drop in the median is smaller than the per-run variance on
either side.

`Row.operator[]` paths (`hot lookup`, `iterate keys + lookup`) were already
ahead under exp 158, and `Map.from clone`, `forEach`, `entries iteration`, and
`values iteration` do not exercise `containsKey`. None of those moved
materially across the paired runs.

`select_maps` and `point_query` were not re-run as guardrails because internal
resqlite code does not call `Row.containsKey` (`grep -rn 'containsKey' lib/`
returns only the row.dart definition itself and the docstring), and exp 158
already covered the shared `indexOf` path.

## Decision

Reject.

The identity fast path is consistent with exp 158 and the change is
behavior-preserving, but the measured win on the available benchmark is below
the per-run noise floor. The most likely explanation is that
`HashMap<String, int>.containsKey` is already very fast on canonical-string
keys — Dart caches `String.hashCode` on canonical strings, so the bucket lookup
collapses to a single hash + identity-compare. The candidate path replaces that
with a short identity-scan loop that performs almost the same comparison count.

There is also a small downside outside the canonical case: any
`row.containsKey(nonCanonicalKey)` call now pays an up-to-32 element identity
scan before falling through to the HashMap. For typical user code that passes
literal column names this is invisible, but a workload that calls `containsKey`
with many runtime-built strings (e.g. JSON-derived keys) would lose a few
nanoseconds per call.

Without a workload where containsKey-time dominates and the keys are usually
canonical-and-present, the change has no measurable upside on current
benchmarks and a small theoretical downside on the non-canonical path.

## Future Notes

- Do not retry this exact swap unless a new workload makes containsKey on
  canonical-string column names a material fraction of wall time. The
  obvious candidate would be a streaming consumer that filters rows by
  optional-column presence on every emitted row.
- The result is *not* evidence that `RowSchema.indexOf`'s identity fast path
  is unnecessary; exp 158 stands. It only shows that the cost reduction
  inside the existing `containsKey` shape is below the current measurement
  floor.
- If a future result-shape experiment touches `containsKey`, it should
  measure on a benchmark that strips the loop-and-switch overhead currently
  dominating the `row_map_facade` `containsKey` case, or pair the change
  with a workload that calls containsKey on rows transferred from worker
  isolates rather than constructed inline.

## Validation

- `dart pub get`
- `dart analyze lib/src/row.dart`
- `dart test test/database_test.dart` (49/49 pass — includes
  `row.containsKey('id')` / `row.containsKey('name')` /
  `row.containsKey('nonexistent')` assertions)
- Focused identity check confirming
  `identical('updated_at', schema.names[5]) == true` on the benchmark schema
- Focused `row_map_facade` A/B (3 baseline + 3 candidate runs, table above)
