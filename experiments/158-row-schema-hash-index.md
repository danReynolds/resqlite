# Experiment 158: Row schema hash index

**Date:** 2026-06-09
**Status:** Accepted
**Direction:** `result-transfer-shape`
**Benchmark Run:** Focused `row_map_facade`, `select_maps`, `point_query`

## Problem

The shipped `ResultSet` shape keeps transfer lean by sharing one flat values
list and one `RowSchema` across lazily-created `Row` views. That is still the
right public API shape, but full row consumption pays one column-name lookup for
every accessed cell:

```dart
for (final row in rows) {
  for (final key in row.keys) {
    row[key];
  }
}
```

`RowSchema` built its column index with a default map literal. For this fixed
lookup table we do not need insertion-order semantics; the query column order is
already preserved in `RowSchema.names`. The index only needs fast name-to-offset
lookup for `Row.operator[]` and `containsKey`.

## Hypothesis

Use a schema-name identity fast path plus a `HashMap<String, int>` fallback for
`RowSchema.indexOf`, but only on schemas where a short identity scan stays
cheap.

This should reduce main-isolate full-consumption cost without changing the
public `List<Row>` / `Map<String, Object?>` surface. Accept for review if
`select_maps` improves on resqlite's 1K/10K full-consumption paths and hot
single-row point queries stay neutral, since point queries construct a schema
per select and would expose any construction-cost regression.

## Approach

`RowSchema.indexOf` now first checks whether the lookup key is one of the
schema's own column-name objects by identity when the schema has at most 32
columns. That catches the common full-consumption pattern:

```dart
for (final key in row.keys) {
  row[key];
}
```

When the caller supplies an equal but non-identical string, or when the schema
is wider than 32 columns, the method falls back to a private `HashMap<String,
int>` index. Query column order remains stored in `RowSchema.names`; the
private lookup map does not need insertion order. No public API changes and no
result transport changes are introduced.

A local width sweep showed the identity scan winning through 32 columns and
losing by 48 columns on this machine. The repo's standard schema is 6 columns,
the row facade benchmark is 8 columns, and the release-facing wide schema is 20
columns, so the guard preserves the measured win while avoiding the obvious
downside for unusually wide selects.

An earlier sub-candidate tried a custom `ResultSet` iterator. It did not hold up
under paired `select_maps` runs, so that code was removed before this PR.

## Results

Focused paired runs compared `origin/main` at `c14bbbd` against the candidate
branch in fresh worktrees with generated Drift files.

`row_map_facade` isolates `Row` map operations. The winning candidate was the
combined `<= 32` column identity fast path plus `HashMap` fallback:

| Case | Baseline row median | Candidate row median | Delta |
|---|---:|---:|---:|
| hot lookup | 10.750 ms | 5.136 ms | -52.2% |
| iterate keys + lookup | 20.602 ms | 10.650 ms | -48.3% |
| containsKey | 17.720 ms | 17.701 ms | neutral |

`select_maps` consumes every field in every returned row. The clean paired pass
after the combined candidate was:

| Rows | Baseline | Candidate | Delta |
|---|---:|---:|---:|
| 1,000 wall | 0.869 ms | 0.606 ms | -30.3% |
| 1,000 main | 0.169 ms | 0.081 ms | -52.1% |
| 10,000 wall | 14.671 ms | 10.087 ms | -31.2% |
| 10,000 main | 1.998 ms | 0.967 ms | -51.6% |

The first 10K baseline/candidate pair was noisy, so the decision does not rely
on it. The final paired run above lines up with the isolated row facade
measurement and shows the main-isolate consumer cost moving in the targeted
direction.

Point-query guardrail:

| Metric | Baseline | Candidate | Delta |
|---|---:|---:|---:|
| resqlite qps | 44,587 | 42,006 | -5.8%, CI overlap |
| resqlite per query | 0.022 ms | 0.024 ms | neutral/noisy |

The point-query run constructs schemas but does not consume rows, so it is a
guardrail for construction overhead. The candidate CI overlapped the baseline
CI; there is no clear small-select regression signal.

## Decision

**Accept for review.**

This is a small internal data-structure change that preserves the lean public
API and removes lookup overhead from full row consumption. It directly uses the
existing `select_maps` workload that measures end-to-end `Map`/`Row` access
rather than only transfer setup, and the isolated row facade benchmark confirms
the intended lookup path moved.

## Future Notes

Do not reopen larger result-shape changes from this result alone. The win is
specific to the private schema index used by the current `Row` facade. The
identity scan is intentionally capped at 32 columns; revisit that threshold only
with a width sweep and a full-consumption benchmark for wider schemas. New
result-transfer experiments should still prove full consumer cost, not just
worker transfer or decode setup.

## Validation

- `dart pub get`
- `dart run build_runner build --delete-conflicting-outputs`
- Focused facade A/B: `dart run benchmark/experiments/row_map_facade.dart`
- Focused A/B: `dart run benchmark/suites/select_maps.dart`
- Point-query guardrail A/B: `dart run benchmark/suites/point_query.dart`
