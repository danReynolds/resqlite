# Experiment 214: Write result direct-read prototype

**Date:** 2026-07-04T10:09:20Z
**Status:** Rejected
**Direction:** `stream-rerun-dispatch`, `measurement-system`
**Benchmark Run:** focused
  [`benchmark/experiments/write_result_direct_read.dart`](../benchmark/experiments/write_result_direct_read.dart);
  see
  [`benchmark/results/2026-07-04T10-09-20Z-exp214-write-result-direct-read.md`](../benchmark/results/2026-07-04T10-09-20Z-exp214-write-result-direct-read.md).
**Archive:** [`archive/exp-214`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-214)

## Problem

`executeWrite()` receives a 16-byte `resqlite_write_result` struct from native
code on every `Database.execute()` / `Transaction.execute()` call. Baseline
code decodes that struct by wrapping the native pointer in a typed list and
then creating a `ByteData` view:

```dart
final view = ByteData.sublistView(
  resultBuf.asTypedList(_writeResultSize),
);
return WriteResult(
  view.getInt32(_writeResultOffAffected, Endian.little),
  view.getInt64(_writeResultOffLastId, Endian.little),
);
```

Exp 095 already rejected the larger persistent writer-result-buffer idea:
removing the native `calloc` / `free` pair did not produce reliable write-path
wins, and the extra lifetime state was not worth carrying. Exp 211 later
accepted persistent `queryBytes()` slots only because `select_bytes_repeated_calls.dart`
gave that reader-side scratch cost a microsecond-precision harness.

This experiment tests a narrower writer-side question that exp 095 did not
isolate: can we remove the per-write Dart view allocation while keeping the
native result buffer lifetime exactly as it is?

## Hypothesis

Reading `affectedRows` and `lastInsertId` directly from the native pointer
should avoid a small Dart allocation/decode step per write. If that cost is
material, a microsecond writer harness should show same-direction improvement
on the no-op writer floor and simple point-update lanes.

Reject if the deltas do not reproduce across order-flipped passes. The expected
effect is small, so a single candidate-faster lane is not enough.

## Approach

The archived prototype changed only the `executeWrite()` result decode:

```dart
return WriteResult(
  (resultBuf + _writeResultOffAffected).cast<ffi.Int>().value,
  (resultBuf + _writeResultOffLastId).cast<ffi.Int64>().value,
);
```

The native `resultBuf` allocation and free stayed unchanged, so the prototype
does not add persistent native state and does not revisit exp 095's lifetime
trade-off.

The final branch reverts the runtime change and keeps a focused benchmark:
`write_result_direct_read.dart`. It repeatedly runs three public writer shapes
and reports median microseconds per `Database.execute()` call:

- `noop update`: writer round-trip floor with no changed rows.
- `point update`: one changed row, no bind parameter.
- `param update`: one changed row with one integer bind parameter.

## Results

Raw numbers are recorded in
[`benchmark/results/2026-07-04T10-09-20Z-exp214-write-result-direct-read.md`](../benchmark/results/2026-07-04T10-09-20Z-exp214-write-result-direct-read.md).
Negative deltas mean the direct-read candidate was faster.

| Pair | Shape | Baseline us/call | Candidate us/call | Delta |
|---|---|---:|---:|---:|
| baseline -> candidate | noop update | 6.758 | 6.842 | +1.2% |
| baseline -> candidate | point update | 14.825 | 14.286 | -3.6% |
| baseline -> candidate | param update | 14.578 | 14.347 | -1.6% |
| candidate -> baseline | noop update | 6.885 | 9.800 | +42.3% |
| candidate -> baseline | point update | 14.531 | 16.405 | +12.9% |
| candidate -> baseline | param update | 14.667 | 15.728 | +7.2% |
| baseline -> candidate confirmation | noop update | 6.879 | 6.635 | -3.5% |
| baseline -> candidate confirmation | point update | 14.577 | 14.539 | -0.3% |
| baseline -> candidate confirmation | param update | 14.435 | 14.639 | +1.4% |

The result does not reproduce. Pair 1 had a small candidate-faster signal on
the two write-shaped lanes but made the no-op floor slower. Pair 2 moved every
lane candidate-slower, including the no-op and parameterized shapes where the
mechanism is identical, which reads as broad run drift or a real regression
rather than a targeted scalar-decode win. Pair 3 returned to mixed/neutral
deltas.

## Decision

**Rejected.** Do not keep the direct pointer-read runtime change.

The prototype removes a small Dart view allocation, but the public writer path
does not show a stable same-direction win. This now closes the narrow
"decode the existing writer result struct differently" idea. It does not
reopen exp 095's persistent native result buffer: that idea adds lifetime state
and was already rejected under focused and release evidence.

The retained benchmark is the useful part. Future writer-result micro-changes
can use `write_result_direct_read.dart` as a quick floor check, but they still
need same-direction order-flipped deltas before touching runtime code.

## Test plan

- [x] `dart pub get`
- [x] `dart analyze --fatal-infos lib/src/native/resqlite_bindings.dart benchmark/experiments/write_result_direct_read.dart`
- [x] `dart test test/database_test.dart --name 'execute INSERT returns affected rows and last insert ID|execute UPDATE returns affected rows|execute DELETE returns affected rows|execute DDL returns zero affected rows'`
- [x] `dart test test/transaction_test.dart --name 'db.execute without parameters returns accurate affectedRows and lastInsertId'`
- [x] Focused order-flipped A/B with
      `benchmark/experiments/write_result_direct_read.dart`
