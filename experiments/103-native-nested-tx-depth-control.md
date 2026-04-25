# Experiment 103: Native nested transaction depth control

**Date:** 2026-04-25
**Status:** Rejected
**Archive:** [`archive/exp-103`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-103)
**Benchmark Run:** None

## Problem

Experiment 101 accepted cached prepared statements for the top-level
transaction controls:

- `BEGIN IMMEDIATE`
- `COMMIT`
- `ROLLBACK`

It intentionally left nested transaction controls alone because their SQL is
depth-dependent:

- `SAVEPOINT sN`
- `RELEASE sN`
- `ROLLBACK TO sN`

Experiment 102 tried caching the Dart-side native strings for those savepoint
statements, but the standard benchmark suite had no nested-transaction workload,
so there was no attributable signal.

This follow-up adds a focused nested-transaction benchmark and tests whether
moving depth-based transaction control into C is worth the complexity.

## Hypothesis

The savepoint path pays fixed per-boundary costs in Dart:

- string interpolation for `sN`
- UTF-8 encoding
- native allocation/free for the SQL string
- generic `resqliteExec(...)` call path

A C helper can build the SQL into a stack buffer and execute it directly:

```c
resqlite_tx_depth_control(db, RESQLITE_TX_SAVEPOINT, depth);
resqlite_tx_depth_control(db, RESQLITE_TX_RELEASE, depth);
resqlite_tx_depth_control(db, RESQLITE_TX_ROLLBACK_TO, depth);
```

That should remove Dart allocation/encoding work while preserving the existing
SQLite semantics.

## Approach

Two passes were tested.

First pass:

- added three native functions:
  - `resqlite_tx_savepoint(db, depth)`
  - `resqlite_tx_release(db, depth)`
  - `resqlite_tx_rollback_to(db, depth)`
- each function used `snprintf(...)` into a stack buffer and then
  `sqlite3_exec(...)`
- replaced the nested branches in `_handleBegin`, `_handleCommit`, and
  `_handleRollback`

Second pass:

- collapsed the native surface to one generic helper:
  - `resqlite_tx_depth_control(db, op, depth)`
- added op constants instead of three Dart FFI bindings
- added a manual SQL builder to avoid `snprintf(...)` overhead
- broadened the focused benchmark to separate empty nesting overhead from
  nested writes

Focused benchmark:

```bash
dart run benchmark/experiments/nested_tx_control.dart \
  --repeats=15 \
  --cycles=5000
```

The benchmark measures four cases:

- empty nested transaction that commits
- empty nested transaction that rolls back
- nested transaction with one write that commits
- nested transaction with one write that rolls back

## Results

Validation:

- `dart analyze native/resqlite.c native/resqlite.h lib/src/native/resqlite_bindings.dart lib/src/writer/write_worker.dart benchmark/experiments/nested_tx_control.dart`
- `dart test test/transaction_test.dart`

Both passed in an external validation worktree with a fresh native build.

The second-pass `snprintf(...)` version had some encouraging intermediate
results:

| Case | Baseline | Candidate | Result |
|---|---:|---:|---:|
| empty commit | 28.196 ms | 21.930 ms | 22.2% faster |
| empty rollback | 36.974 ms | 31.082 ms | 15.9% faster |
| write commit | 42.291 ms | 34.488 ms | 18.5% faster |
| write rollback | 51.191 ms | 46.075 ms | 10.0% faster |

But larger-cycle and reversed-order runs weakened the signal:

| Case | Baseline | Candidate | Result |
|---|---:|---:|---:|
| empty commit | 62.713 ms | 59.227 ms | 5.6% faster |
| empty rollback | 85.830 ms | 80.592 ms | 6.1% faster |
| write commit | 97.826 ms | 97.838 ms | flat |
| write rollback | 137.154 ms | 124.730 ms | 9.1% faster |

The final manual-SQL-builder pass did not improve things:

| Case | Baseline | Candidate | Result |
|---|---:|---:|---:|
| empty commit | 67.752 ms | 65.081 ms | 3.9% faster |
| empty rollback | 89.822 ms | 91.261 ms | 1.6% slower |
| write commit | 108.312 ms | 109.071 ms | 0.7% slower |
| write rollback | 134.351 ms | 137.511 ms | 2.4% slower |

## Decision

Rejected.

The first measurable signal came from a new focused nested-transaction benchmark,
which was useful, but the optimization itself does not clear the bar.

The best-case result is a small savepoint-only improvement. Once the benchmark
includes realistic nested work, the effect drops into noise or regresses. The
manual SQL builder also made the native code more specialized without producing
a stable win.

The added complexity is not justified:

- extra internal native API surface
- duplicated transaction-control path
- more C code around a niche nested-transaction workload
- no expected impact on the standard release suite

The implementation is archived at `archive/exp-103` in case a future workload
shows deeply nested transactions as a real bottleneck. For now, exp 101 remains
the right boundary: cache the hot top-level transaction controls, leave
depth-dependent savepoints on the simpler existing path.
