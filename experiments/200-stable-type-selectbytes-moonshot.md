# Experiment 200: Stable-Type selectBytes Moonshot

**Date:** 2026-06-26T08:58:26-04:00
**Status:** Rejected
**Category:** Moonshot
**Direction:** `result-transfer-shape`
**Benchmark Run:** focused `benchmark/experiments/select_bytes_int_heavy.dart` and `benchmark/experiments/select_bytes_wide_cols.dart`; no release-suite run because the runtime prototype was rejected and reverted.
**Archive:** [`archive/exp-200`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-200)

## Problem

Exp 190, 192, 194, 195, 198, and 199 removed most of the visible per-cell JSON
encoder overhead from `write_json_to_buf`: column-name tokens are cached, integer
and integer-valued REAL formatters write directly into the output buffer, and
the fixed-size row path pre-reserves capacity once per row.

One boundary remains in the inner loop: every cell still calls
`sqlite3_column_type(stmt, i)` before choosing the NULL / INTEGER / FLOAT / TEXT
/ BLOB writer. On fixed-shape result sets this looks redundant. The statement
and table declarations often imply stable per-column storage classes, and the
first row reveals the actual SQLite storage class the encoder will see.

## Hypothesis

Assumption challenged: `selectBytes()` must inspect each row's SQLite storage
class cell by cell, even when a result set appears type-stable.

Prototype: record each column's storage class from row 0, then serialize later
rows using that cached class instead of calling `sqlite3_column_type()` again.
This intentionally allows more risk than an exploit experiment. The point is to
measure the ceiling for removing the type probe and to learn whether any hidden
default can be safe.

The kill condition is correctness, not just wall time: if ordinary SQLite
dynamic typing can make later rows carry a different storage class, the hidden
default is invalid no matter how much a fixed-type benchmark improves.

## Approach

The archived prototype changed only `write_json_to_buf`:

- allocate one per-query `int[col_count]` type vector,
- fill it from `sqlite3_column_type()` while serializing row 0,
- for row 1 and later, skip `sqlite3_column_type()` and dispatch on the cached
  first-row type,
- keep the existing row-level reservation and fixed-cell direct-write path from
  exp 199.

No production-safe fallback was added. A fallback that rechecks the type before
using the cached class would pay the exact probe this experiment is trying to
remove. A production version would need a stronger proof surface: strict tables,
declared-type inspection with query-shape constraints, an explicit opt-in, or
some other semantic contract that SQLite's dynamic storage classes cannot
silently violate.

The runtime patch was archived and reverted from the branch. No unsafe code is
kept.

## Results

### Fixed-shape integer harness

Focused harness: `dart run benchmark/experiments/select_bytes_int_heavy.dart`.
Medians are one baseline pass followed by one candidate pass.

| Lane | Baseline | Candidate | Delta |
|---|---:|---:|---:|
| 10k rows x 8 small ints | 3056 us | 2820 us | -7.7% |
| 10k rows x 20 small ints | 7626 us | 8415 us | +10.3% |
| 10k rows x 20 big ints (~18 digits) | 8431 us | 8756 us | +3.9% |
| 10k rows x 8 mixed (4 int + 2 text + 2 real) | 9985 us | 10385 us | +4.0% |
| 1k rows x 2 ints | 136 us | 145 us | +6.6% |

This harness does not support accepting the idea. The narrow 8-column integer
lane improves, but every other lane regresses in the same pass. The per-query
type-vector allocation and altered branch shape appear to erase or exceed the
saved type call on the integer-heavy shapes that should have been the cleanest
win.

### Wide-column harness

Focused harness: `dart run benchmark/experiments/select_bytes_wide_cols.dart`.
This produced a visible candidate-faster signal, but the confirmation baseline
also drifted much slower than the first baseline, so magnitude is not
load-bearing.

| Shape | Baseline P1 | Candidate P1 | Delta P1 | Candidate P2 | Baseline P2 | Delta P2 |
|---|---:|---:|---:|---:|---:|---:|
| 10k rows x 8 int cols | 2.539 ms | 2.181 ms | -14.1% | 2.105 ms | 3.547 ms | -40.7% |
| 10k rows x 20 int cols | 6.486 ms | 5.485 ms | -15.4% | 5.174 ms | 7.058 ms | -26.7% |
| 10k rows x 8 mixed cols | 2.779 ms | 2.635 ms | -5.2% | 2.327 ms | 4.022 ms | -42.1% |
| 10k rows x 20 mixed cols | 8.906 ms | 6.251 ms | -29.8% | 5.982 ms | 8.091 ms | -26.1% |
| 10k rows x 2 int cols | 0.801 ms | 0.685 ms | -14.5% | 0.658 ms | 0.870 ms | -24.4% |

There is probably a real ceiling in the wide fixed-shape case: skipping one
SQLite type probe per cell is not free. But the mixed benchmark signal is not
enough to overcome the semantic failure below, and the integer-specific harness
does not reproduce a clean win.

### Dynamic type hazard

A targeted local probe created a single untyped SQLite column, inserted an
INTEGER in row 1 and TEXT in row 2, and compared `selectBytes()` with
`select()`:

```text
selectBytes prototype: [{"v":1},{"v":0}]
select baseline:       [{"v":1},{"v":"abc"}]
```

The prototype cached row 0 as `SQLITE_INTEGER`, then serialized row 1 with
`sqlite3_column_int64()`. SQLite converted the text value `"abc"` to integer
`0`, producing wrong JSON.

This is not an edge condition outside SQLite's model. SQLite storage classes are
per value, not per column, unless a stronger schema contract is present and
proven usable by the encoder.

Validation:

```bash
dart pub get
dart run benchmark/experiments/select_bytes_int_heavy.dart
dart run benchmark/experiments/select_bytes_wide_cols.dart
```

The dynamic-type probe was local-only and removed before publication.

## Decision

Rejected as a hidden default.

The performance ceiling is plausible on fixed-shape wide rows, but the
assumption is not safe for ordinary SQLite result sets. Caching the first row's
storage class can silently corrupt `selectBytes()` output as soon as later rows
carry a different storage class. The only safe hidden implementation would need
to reintroduce per-cell verification or a proof layer whose complexity is not
justified by the current mixed performance evidence.

## Future Notes

- Do not skip `sqlite3_column_type()` in the general `selectBytes()` path based
  only on the first row.
- Reopen this frontier only with a real proof surface: SQLite STRICT tables,
  declared-type plus query-shape constraints, a generated/static statement
  mode, or an explicit user-visible contract.
- If a proof surface exists, reuse `select_bytes_wide_cols.dart` as the fast
  ceiling check, but require a dynamic-storage-class correctness guard before
  any production code can be accepted.
