# Experiment 193: Row.values list-view iterator

**Date:** 2026-06-22
**Status:** Rejected
**Direction:** `result-transfer-shape`
**Benchmark Run:** none - focused `row_map_facade` JIT/AOT probe only; no release-suite lane.

## Problem

Exp 158 and exp 176 tightened the existing `ResultSet` / `Row` shape instead
of replacing it. `row_map_facade.dart` now shows `Row` at parity or better than
`LinkedHashMap` on hot lookup, key iteration, entries, `forEach`, and
`Map.from`. One apparent gap remained on a fresh JIT run:

| Case | Row median | LinkedHashMap median | Delta |
|---|---:|---:|---:|
| values iteration | 8.607 ms | 4.779 ms | +3.828 ms |

`Row.values` returned a custom `IterableBase` backed by `_RowValueIterator`.
That iterator stepped through the whole `Row` object and read
`_schema.columnCount` on every bound check. A fixed-length list view over the
row's slice of the flat value array looked like a bounded way to remove that
indirection without changing the public `Map` contract.

## Hypothesis

Returning a fixed-length `_RowValues extends ListBase<Object?>` with direct
indexed access to `_values[_offset + index]` would make `for (final value in
row.values)` use a simpler list-style iterator. Accept if the focused
`values iteration` lane improved reproducibly while the existing hot lookup,
`forEach`, entries, and clone controls stayed neutral.

## Approach

Tried two local candidates and reverted both before publishing:

1. A direct custom iterator storing `_values`, `_offset`, and `_end` instead of
   a `Row` reference.
2. A fixed-length `_RowValues extends ListBase<Object?>` slice view with
   `operator []`, `length`, and unsupported mutation methods.

The focused harness was the existing `benchmark/experiments/row_map_facade.dart`.
Because JIT runs produced contradictory results after VM warmup, the decision
used AOT executables compiled from a clean `origin/main` baseline worktree and
the candidate branch:

```bash
dart compile exe benchmark/experiments/row_map_facade.dart -o /tmp/row_facade_exp193_baseline
dart compile exe benchmark/experiments/row_map_facade.dart -o /tmp/row_facade_exp193_candidate
```

## Results

### JIT probe

The first direct-iterator sample looked promising:

| Build | values iteration row median | LinkedHashMap median | Delta |
|---|---:|---:|---:|
| baseline, first clean sample | 8.607 ms | 4.779 ms | +3.828 ms |
| direct-iterator candidate, first sample | 3.410 ms | 4.788 ms | -1.378 ms |

That did not reproduce. After a fresh `dart pub get`, the same direct-iterator
candidate produced 5.693 / 8.616 / 8.563 / 8.728 ms over four JIT samples. A
fresh baseline pass also alternated between fast and slow values samples
(3.145 / 10.955 / 3.150 / 8.800 / 3.154 ms). The apparent gap was dominated by
JIT tiering and benchmark warmup behavior, not a stable implementation delta.

The fixed-list view looked stable under JIT (3.488 / 3.654 / 3.442 / 3.453 /
3.435 ms), so it received the AOT check.

### AOT check

Alternating compiled baseline and candidate binaries gave the opposite answer:

| Run | Baseline values | Candidate values | Delta |
|---|---:|---:|---:|
| 1 | 2.663 ms | 6.828 ms | +156.4% |
| 2 | 2.675 ms | 6.847 ms | +155.9% |
| 3 | 2.687 ms | 7.101 ms | +164.3% |

Controls stayed in the same range, so the regression is specific to the
`values` shape:

| Control | Baseline range | Candidate range | Verdict |
|---|---:|---:|---|
| hot lookup | 2.514-2.557 ms | 2.519-2.569 ms | neutral |
| containsKey | 5.164-5.258 ms | 5.204-5.227 ms | neutral |
| entries iteration | 4.293-4.513 ms | 4.333-4.366 ms | neutral |
| Map.from clone | 4.222-4.354 ms | 4.225-4.375 ms | neutral |

The original `_RowValueIterator` is already the better compiled shape. The
fixed `ListBase` facade likely adds indexed-list dispatch/range-check work that
the AOT compiler does not remove, while the existing iterator is optimized into
a tight walk over the backing row slice.

## Decision

**Rejected.** No runtime code kept. The only apparent win came from unstable
JIT behavior, and the compiled result regressed the target lane by roughly
2.6x. `Row.values` should stay on the existing `_RowValueIterator`.

## Future Notes

Do not retry a `ListBase`, `getRange`, or fixed-slice view for `Row.values`
based on JIT `row_map_facade` output alone. If this area is revisited, compile
the focused harness to AOT first and require the candidate to beat the original
iterator there. The broader exp 082 / 158 guidance still applies: optimize
inside the current `ResultSet` shape only when full consumer cost improves, not
just when a microbenchmark looks better under one runtime mode.

## Validation

- `dart pub get`
- `dart analyze --fatal-infos lib/src/row.dart`
- `dart test test/database_test.dart --plain-name 'row implements Map interface'`
- `dart run benchmark/experiments/row_map_facade.dart` on baseline and both candidates
- `dart compile exe benchmark/experiments/row_map_facade.dart` for baseline and candidate
- Alternating AOT baseline/candidate executions
