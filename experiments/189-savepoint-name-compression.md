# Experiment 189: Savepoint name compression

**Date:** 2026-06-20
**Status:** Rejected
**Direction:** `transaction-control-paths`
**Benchmark Run:** focused harness only (`benchmark/experiments/savepoint_name_compression.dart`); no release-suite run because the runtime candidate was reverted.

## Problem

Exp 101 cached top-level transaction control statements, but nested
transactions still construct depth-specific SQL strings on every boundary:

- `SAVEPOINT sN`
- `RELEASE sN`
- `ROLLBACK TO sN`

Exp 102 tried caching those depth-specific native strings and exp 111 later
re-tested that cached-string shape after adding the nested-transaction release
workload. The result stayed below the decision threshold: the 50x shallow
fanout row moved -9%, inside a +/-17% threshold, because the per-savepoint
writer-isolate round trip dominated per-string allocation.

The remaining lightweight naming candidate was simpler than exp 102's
depth-indexed caches: SQLite permits nested savepoints with the same name, and
`RELEASE` / `ROLLBACK TO` target the innermost matching frame. If every nested
level used the same savepoint name, the writer could reuse three cached SQL
strings (`SAVEPOINT s`, `RELEASE s`, `ROLLBACK TO s`) instead of interpolating
and allocating depth-specific strings.

## Hypothesis

Savepoint name compression should remove the remaining per-boundary string
formatting and `toNativeUtf8` / `calloc.free` work without adding native API
surface. If string construction is still visible, the focused nested-control
rows should improve, especially empty savepoint fanout and rollback-heavy
cases. If the realistic nested-write fanout does not improve across an
order-flipped pair, the string/naming subdirection should be closed.

Acceptance criterion: the representative nested-write fanout must improve
across an order-flipped focused A/B pair, with no rollback/deep-chain
regression. Empty savepoint fanout is an explanatory best-case signal, not the
acceptance gate.

## Approach

Built the candidate in `lib/src/writer/write_worker.dart`:

- replace depth-specific nested SQL (`SAVEPOINT s${state.txDepth}`,
  `RELEASE s$newDepth`, `ROLLBACK TO s$newDepth`) with cached same-name SQL
  pointers from `cachedSqlUtf8`;
- keep Dart `txDepth` unchanged as the runtime's nesting tracker;
- rely on SQLite's innermost-match semantics for same-name savepoints.

Added `benchmark/experiments/savepoint_name_compression.dart` so this candidate
can be measured without running the entire release suite. The harness reports
four rows:

- empty fanout x500: best-case savepoint control only;
- write fanout x100: representative nested write fanout, closest to exp 111's
  shipped release row;
- rollback fanout x100: exercises `ROLLBACK TO` + `RELEASE`;
- deep chain 100 x depth=5: repeated deep nesting with one inner write.

After measurement, the runtime change was reverted. The focused harness is
retained as the durable artifact.

## Results

Focused harness, 17 samples per row.

### Pass 1 - baseline first

| Case | Baseline ms | Candidate ms | Delta |
|---|---:|---:|---:|
| empty fanout x500 | 4.547 | 4.262 | -6.3% |
| write fanout x100 | 1.596 | 1.576 | -1.3% |
| rollback fanout x100 | 2.471 | 2.052 | -17.0% |
| deep chain 100 x depth=5 | 3.837 | 3.556 | -7.3% |

### Pass 2 - candidate first

| Case | Baseline ms | Candidate ms | Delta |
|---|---:|---:|---:|
| empty fanout x500 | 4.645 | 4.329 | -6.8% |
| write fanout x100 | 1.567 | 1.906 | +21.6% |
| rollback fanout x100 | 2.475 | 2.156 | -12.9% |
| deep chain 100 x depth=5 | 3.858 | 3.546 | -8.1% |

The empty fanout, rollback fanout, and deep-chain rows trend faster in both
passes, which confirms the candidate can remove a small amount of control-path
work. The representative write fanout does not reproduce: it is effectively
flat in pass 1 and materially slower in the order-flipped pass. That is the
same shape exp 111 warned about: once a nested transaction does real write
work, per-boundary naming/allocation savings are too small to separate from the
writer round-trip and scheduler floor.

## Decision

Rejected. Same-name savepoint SQL is clever and probably removes some real
string-control work, but it does not clear the representative nested-write gate.
The one row closest to the shipped release workload flips from neutral (-1.3%)
to slower (+21.6%) across the order-flipped pair.

The production path stays on explicit depth-specific savepoint names. The
candidate's small best-case wins do not justify relying on the subtler
same-name savepoint semantics, and they do not change the direction-level
belief from exp 111: nested transaction optimization needs to collapse
round-trips, not rename or cache per-savepoint SQL strings.

## Future Notes

- Do not retry savepoint string caching, naming compression, or a native helper
  that still sends one request per savepoint boundary without new evidence that
  the per-boundary string work is dominant.
- The retained `savepoint_name_compression.dart` harness is useful for quick
  transaction-control probes, but the representative gate remains the
  write-fanout row, not the empty-control best case.
- The only still-interesting transaction-control implementation shape is
  multi-savepoint round-trip batching, and it needs a design that preserves
  callback semantics and rollback legality.

## Validation

- `dart pub get`
- `dart analyze --fatal-infos lib/src/writer/write_worker.dart benchmark/experiments/savepoint_name_compression.dart`
- `dart test test/transaction_test.dart`
- `dart run benchmark/experiments/savepoint_name_compression.dart` on baseline and candidate in baseline-first order
- `dart run benchmark/experiments/savepoint_name_compression.dart` on candidate and baseline in candidate-first order
- `dart run benchmark/check_experiment_signals.dart`
- `dart run benchmark/finalize_experiment.dart --experiment=experiments/189-savepoint-name-compression.md`
- `dart run build_runner build --delete-conflicting-outputs`
- `dart analyze --fatal-infos`
