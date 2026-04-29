# Experiment 111: Nested transaction benchmark

**Date:** 2026-04-29T06:11:38
**Status:** In Review
**Direction:** `transaction-control-paths`, `measurement-system`

## Problem

Experiments 102 and 103 both pointed at the same gap: the standard release
suite covered top-level transaction control, but not nested `transaction()`
calls. That made savepoint-path ideas hard to evaluate. A change could touch
`SAVEPOINT`, `RELEASE`, or `ROLLBACK TO` and still produce only unrelated
suite drift.

The project already had focused one-off evidence from exp 103, but that script
was not part of the default release artifact. Future scheduled runners still
needed a durable benchmark row before revisiting nested transaction control.

## Hypothesis

Add a small resqlite-only nested transaction subsection to the write suite:

- depth 3 nested `transaction()` calls, so the path covers multiple savepoint
  names rather than only `s1`
- 50 cycles per sample, so the metric rises above the ultra-fast `0.02 ms`
  absolute floor
- empty commit, write commit, and write rollback cases, so both `RELEASE` and
  `ROLLBACK TO` stay visible

This is a measurement improvement, not an implementation optimization. The
acceptance bar is that the workload is valid, cheap enough for the default
suite, and emits stable-enough numbers to evaluate future savepoint changes.

SQLite's own transaction docs remain aligned with resqlite's API shape:
`BEGIN...COMMIT` transactions do not nest, and nested transactions use
savepoints. The savepoint docs define `RELEASE` as removing savepoints rather
than writing inner changes to disk, while `ROLLBACK TO` rewinds to the matching
savepoint and keeps that savepoint active.

Sources checked:

- SQLite transactions: https://www.sqlite.org/lang_transaction.html
- SQLite savepoints: https://www.sqlite.org/lang_savepoint.html

## Approach

Updated `benchmark/suites/writes.dart` with a new subsection:

```text
Nested Transactions (depth 3 × 50 cycles)
```

The benchmark opens a resqlite database and records three timings:

1. `resqlite empty commit` — repeats depth-3 nested transactions with no leaf
   work.
2. `resqlite write commit` — writes one row at the leaf and commits the
   nested savepoints.
3. `resqlite write rollback` — writes one row at the leaf, throws a sentinel,
   and catches it in the outer transaction body so each nested transaction
   rolls back without aborting the full sample.

This stays out of `BenchmarkPeer` for the same reason the existing interactive
transaction sections do: the peer abstraction does not expose a uniform nested
transaction handle, and forcing that into the peer layer would be a separate
API-shape project.

## Results

Artifacts:

- `benchmark/results/2026-04-29T06-11-38-exp111-nested-tx-benchmark.md`
- `benchmark/results/2026-04-29T06-11-38-exp111-nested-tx-benchmark.json`

Command:

```text
dart run benchmark/run_release.dart exp111-nested-tx-benchmark --repeat=3 \
  --compare-to=benchmark/results/2026-04-27T15-46-01-exp110-fnv-8byte-long-text.md
```

Representative release rows from the final repeat:

| Benchmark | Median | p90 |
|---|---:|---:|
| `resqlite empty commit` | 1.418 ms | 1.565 ms |
| `resqlite write commit` | 1.705 ms | 1.835 ms |
| `resqlite write rollback` | 2.062 ms | 2.240 ms |

Repeat-level medians across the 3-run artifact:

| Benchmark | 3-run median | 95% CI | MDE_ci | Stability |
|---|---:|---:|---:|---|
| `resqlite empty commit` | 1.60 ms | 1.42..1.88 ms | 28.6% | noisy |
| `resqlite write commit` | 1.87 ms | 1.71..2.20 ms | 26.5% | noisy |
| `resqlite write rollback` | 2.32 ms | 2.06..2.33 ms | 11.5% | stable |

The empty/write commit rows are intentionally above the absolute floor, but a
3-run release artifact still classifies them as noisy. That is acceptable for a
new measurement row: future implementation experiments should use repeat-aware
thresholds and should not over-read small savepoint-only deltas.

The full timing comparison reported 42 wins, 0 regressions, and 113 neutral
against the exp 110 artifact. Those wins are run-environment drift, not caused
by the benchmark addition. The new nested rows have no previous baseline row,
so they correctly do not participate in the A/B comparison yet.

Validation:

```text
dart run build_runner build --delete-conflicting-outputs
dart analyze
dart test test/transaction_test.dart
dart test test/benchmark_parse_results_test.dart
dart run benchmark/suites/writes.dart
dart run benchmark/check_generated_data.dart
dart run benchmark/check_experiment_signals.dart
```

## Decision

Keep in review as an accepted measurement improvement.

The default release suite now exercises the depth-dependent savepoint path that
exp 102 and exp 103 could only reason about with focused scripts. This does not
make savepoint optimization automatically attractive: the first two rows are
still noisy at 3 repeats, and exp 103 already showed that native depth-control
helpers were not worth their complexity. But future attempts now have a
committed release metric to compare against.

## Future Notes

Use this benchmark before revisiting cached savepoint strings, native
savepoint helpers, or any transaction depth-control refactor. A future change
should move the nested rows without regressing the existing interactive
transaction, `tx.executeBatch`, and transaction-read sections.

Do not treat this as evidence that nested transactions are common in real
applications. Production traces or user workloads should still drive whether
this path deserves more implementation complexity.
