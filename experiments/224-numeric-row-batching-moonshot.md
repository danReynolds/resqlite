# Experiment 224: Dynamic numeric-row batching moonshot

**Date:** 2026-07-12
**Status:** Rejected
**Category:** Moonshot
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused
  [`benchmark/experiments/select_rows_step_row_ffi.dart`](../benchmark/experiments/select_rows_step_row_ffi.dart);
  raw order-flipped tables in
  [`benchmark/results/2026-07-12T10-19-03Z-exp224-numeric-row-batching.md`](../benchmark/results/2026-07-12T10-19-03Z-exp224-numeric-row-batching.md).
**Archive:** [`archive/exp-224`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-224)

## Problem

The rows path still crosses FFI once per SQLite result row through
`resqlite_step_row`. [Exp 018](018-multi-row-step.md) and
[exp 074](074-bulk-step-many.md) tried stepping 64-128 rows at a time, but both
had to copy every TEXT/BLOB payload into a side arena because SQLite-owned
pointers become invalid at the next `sqlite3_step()`. That extra copy made
text-heavy reads 24-38% slower and erased the crossing reduction.

Exp 074 left one architectural follow-up open: a pure-numeric bulk path. Numeric
and NULL values fit directly in the existing 16-byte `resqlite_cell`, so they
do not carry the pointer-lifetime problem that killed the earlier designs.
Since then, exp 205 added a focused rows-path harness with 10k x 8 and 10k x 20
INTEGER lanes, making that follow-up directly measurable.

## Hypothesis

Assumption challenged: every `select()` row must return to Dart before SQLite
can step again.

The prototype dynamically batches contiguous INTEGER, FLOAT, and NULL rows in
C. If a row contains TEXT or BLOB, it includes that row as the final row of the
batch and returns immediately. Dart decodes the borrowed pointer before the
next native call. That should collapse a 10,000-row numeric scan from roughly
10,001 leaf FFI calls to about 157 without adding the payload copy that invalidated
exp 018/074.

Accept if both INTEGER lanes reproduce at least 5% candidate-faster across the
order flip and the TEXT/mixed fallback guards have no reproduced regression
above 3%. Reject if the numeric lanes stay at the noise floor or the dynamic
fallback makes pointer-heavy rows materially slower.

The risk budget is moonshot-sized but bounded: two new native step entry points,
a row-major cell decoder, and a larger persistent per-worker cell buffer. There
is no public API change, no type assumption, and no payload arena. The buffer is
capped at 64 rows and approximately 64 KiB per worker even for wide schemas.

## Approach

The archived prototype changes the C/Dart row decoder in three places:

- `resqlite_step_rows` fills up to 64 rows in a row-major `resqlite_cell`
  buffer. INTEGER/FLOAT values are copied into the cell union and NULL needs no
  payload. Seeing TEXT/BLOB sets a stop flag after the current row.
- `resqlite_step_rows_hash` applies the same batching rule while preserving the
  initial stream-registration hash. The unchanged stream re-query path remains
  the existing hash-only C pass.
- `decodeQuery` and `decodeQueryWithInitialHash` decode the returned batch
  before making another FFI call. The persistent buffer chooses
  `min(64, 64 KiB / row_width)` rows so a very wide query cannot multiply its
  worker memory by 64.

This is dynamic, not declared-type speculation. SQLite storage class belongs to
each value, so a column declared INTEGER can still contain TEXT in a non-STRICT
table. The prototype inspects every actual cell and stops at the first
pointer-backed row, preserving the dynamic-type correctness boundary that
[exp 200](200-stable-type-selectbytes-moonshot.md) showed cannot be inferred
from row 0.

SQLite documents that result TEXT/BLOB pointers remain valid only until a type
conversion, `sqlite3_step`, reset, or finalize. Returning immediately after the
pointer row preserves that contract without copying
([SQLite result-value lifetime](https://www.sqlite.org/c3ref/column_blob.html)).
Dart's leaf FFI path deliberately reduces crossing overhead, which is why the
remaining ceiling needed measurement rather than assumption
([Dart leaf calls](https://api.dart.dev/dart-ffi/NativeFunctionPointer/asFunction.html)).

Correctness probes inserted 70 INTEGER values, then TEXT, 70 REAL values, then
BLOB and NULL into one dynamically typed column. Both reader and transaction
`select()` paths, plus the initial stream decode/hash path, returned every value
in order across the 64-row and pointer boundaries. The full focused database
and stream test set passed before benchmarking.

## Results

Focused harness: `dart run benchmark/experiments/select_rows_step_row_ffi.dart`.
Medians are milliseconds per 10,000-row `select()` call.

| Lane | Pair 1 delta | Pair 2 delta | Interpretation |
|---|---:|---:|---|
| **10k x 8 INTEGER** | **+1.9%** | **+0.5%** | candidate-slower both |
| **10k x 20 INTEGER** | **+4.6%** | **-0.5%** | sign reversal / flat |
| 10k x 20 short TEXT | +6.5% | +5.3% | reproduced regression |
| 10k x 6 mixed | -2.3% | -3.6% | small fallback movement |

The numeric acceptance gate did not fire. The narrow INTEGER lane is slightly
slower in both orderings, and the wide INTEGER lane flips around zero. Reducing
about 10,000 leaf calls to roughly 157 therefore does not remove enough wall
time to offset the combined batch-shaped decoder. The benchmark does not
separate the costs of its larger buffer, row-major indexing, stop flag, and
shared Dart batch loop; it shows that their integrated cost exceeds the saved
crossings.

The pointer-heavy guard is worse: 20 short TEXT columns regress by 5-7% in both
orderings. No bytes are copied, so this is the clean evidence exp 018/074 could
not provide. The dynamic stop flag and batch-shaped decoder add enough overhead
to produce one-row behavior on the batch API, so even the safe version of the
idea harms an important schema shape.

## Decision

**Rejected.**

The one-row `resqlite_step_row` design remains the right default. Leaf FFI
crossings are already cheap, the one-row cell buffer has excellent locality,
and TEXT/BLOB rows can decode directly from SQLite-owned memory. Dynamic
numeric-run batching removes crossings but does not remove SQLite stepping or
Dart object construction; the combined batch path is neutral-to-slower on the
numeric target and materially slower on the pointer-heavy guard.

The prototype is preserved at `archive/exp-224` and reverted from the final
branch. Reopen only if a Dart runtime change makes leaf crossings materially
more expensive, or if a production/AOT profile shows the crossing itself—not
SQLite stepping, cell dispatch, or Dart allocation—as a top rows-path cost.
Do not retry a different batch size or a declared-type shortcut under the
current runtime: exp 018/074 already ruled out copied payload arenas, exp 200
rules out hidden type stability, and exp 224 closes the dynamic no-copy form.

## Validation

- `dart analyze --fatal-infos lib/src/query_decoder.dart test/database_test.dart test/stream_test.dart`
- `dart test test/database_test.dart test/stream_test.dart -j 1` (83 tests)
- Two order-flipped focused A/B passes of
  `benchmark/experiments/select_rows_step_row_ffi.dart`
- `git diff --check`
