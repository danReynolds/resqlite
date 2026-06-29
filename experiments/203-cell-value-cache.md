# Experiment 203: Per-cell `sqlite3_column_value` reuse in `write_json_to_buf`

**Date:** 2026-06-28
**Status:** Accepted
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused A/B only
(`benchmark/experiments/select_bytes_int_heavy.dart`,
`benchmark/experiments/select_bytes_real_int_fastpath.dart`,
`benchmark/experiments/select_bytes_wide_cols.dart`,
`benchmark/experiments/large_bytes_transfer.dart`), order-flipped pair on a
quiet box. No release-suite run; the focused harnesses are the gate (no
release lane is integer-heavy or TEXT-heavy enough for per-cell FFI savings
to register, per exp 192 / exp 198 / exp 199's gating analysis).

## Problem

After [exp 195](195-stmt-cache-name-tokens.md) cached column-name tokens,
[exp 198](198-direct-buf-int-float-json.md) collapsed the per-cell
integer/float formatter to a direct write, and
[exp 199](199-row-level-buf-ensure.md) hoisted the per-cell `buf_ensure`,
the remaining per-cell cost inside `write_json_to_buf` is the SQLite API
itself. Every column access goes through `sqlite3_column_*`, which is
defined in the amalgamation as:

```c
SQLITE_API int sqlite3_column_type(sqlite3_stmt *pStmt, int i){
    int iType = sqlite3_value_type( columnMem(pStmt,i) );
    columnMallocFailure(pStmt);
    return iType;
}
```

`columnMem` enters the connection's `db->mutex`, checks `i < nResColumn`,
returns `&pVm->pResultRow[i]`; `columnMallocFailure` leaves the mutex and
runs `sqlite3ApiExit`. On a NOMUTEX connection (which is the only mode
resqlite ever opens — `lib/src/native/...` passes `SQLITE_OPEN_NOMUTEX`
unconditionally) the mutex enter/leave resolve to no-op function calls,
but the lookup itself, the result-row range check, and the `sqlite3ApiExit`
all still fire per column access.

The current encoder fires this whole sequence twice per fixed cell (one
`sqlite3_column_type` + one `sqlite3_column_int64` / `_double`) and three
times per TEXT / BLOB cell (`column_type` + `column_text` / `column_blob`
+ `column_bytes`). On a 10k × 20 INTEGER `selectBytes` that is 400k
`columnMem` invocations per query.

## Hypothesis

Calling `sqlite3_column_value(stmt, i)` once per cell returns the same
`Mem*` that every `sqlite3_column_*` routine looks up internally, exposed
as an `sqlite3_value*`. The `sqlite3_value_*` family operates on that
pointer directly — no `columnMem`, no `sqlite3ApiExit`. So hoisting
`sqlite3_column_value` to the top of the per-cell switch and dispatching
through `sqlite3_value_type` / `sqlite3_value_int64` / `sqlite3_value_double`
/ `sqlite3_value_text` / `sqlite3_value_bytes` / `sqlite3_value_blob`
should collapse 2 or 3 `columnMem` lookups per cell into 1, with
bit-identical JSON output (`sqlite3_column_*` is literally implemented
as `sqlite3_value_* ∘ columnMem`).

The signal should reproduce on every selectBytes shape — the saving is
per cell, the magnitude proportional to per-cell wall — and stay flat
on the fractional-REAL guard because `snprintf("%.17g")` dwarfs any
FFI saving.

## Approach

In [`native/resqlite.c`](../native/resqlite.c) `write_json_to_buf`, inside
the per-column loop:

```c
sqlite3_value* val = sqlite3_column_value(stmt, i);
int type = sqlite3_value_type(val);
switch (type) {
    case SQLITE_INTEGER:
        b->len += fast_i64_to_str(
            sqlite3_value_int64(val),
            (char*)(b->data + b->len));
        break;
    case SQLITE_FLOAT:
        b->len += fast_double_to_json_num(
            sqlite3_value_double(val),
            (char*)(b->data + b->len), (size_t)cell_max);
        break;
    case SQLITE_TEXT: {
        const char* text = (const char*)sqlite3_value_text(val);
        int text_len = sqlite3_value_bytes(val);
        ...
    }
    case SQLITE_BLOB: {
        int blob_len = sqlite3_value_bytes(val);
        const unsigned char* blob =
            (const unsigned char*)sqlite3_value_blob(val);
        ...
    }
    ...
}
```

The "value_text before value_bytes" ordering is preserved — calling
`value_bytes` first on a TEXT cell triggers an implicit conversion that
invalidates the text pointer, same as the `column_*` API. The row-level
`buf_ensure` from exp 199 is untouched; the TEXT / BLOB re-ensure path
is unchanged.

Safety: the SQLite docs warn that "the object returned by
`sqlite3_column_value()` is an unprotected sqlite3_value object … the
behavior is not threadsafe" if you call `sqlite3_value_*` on it from a
non-`sqlite3_bind_value` / `sqlite3_result_value` context. The warning
specifically targets multithreaded callers that might race against
another thread holding the connection mutex. resqlite opens every
connection with `SQLITE_OPEN_NOMUTEX` and gives each connection to a
single isolate worker — there is no thread that could be racing the
underlying Mem cell. The `unprotected` vs `protected` distinction
collapses to "same thing" in single-threaded mode.

The same pattern is mechanically applicable to `resqlite_step_row` and
`resqlite_step_row_hash` (used by the rows / stream path), but those are
out of scope for this experiment — the load-bearing focused harness for
those paths is different (`select_maps`, `row_map_facade`,
`single_stream_long_payload_hash`) and they should be measured on their
own.

## Results

Two order-flipped passes per focused harness, median across 8–11
samples per lane. Same-machine quiet box (Apple Silicon, Dart 3.x AOT).
Pass 1 ordering is baseline-then-candidate; Pass 2 is
candidate-then-baseline.

### `select_bytes_int_heavy.dart` (exp 192 / 198 / 199's harness, µs/query)

| Lane | P1 base | P1 cand | Δ P1 | P2 cand | P2 base | Δ P2 |
|---|---:|---:|---:|---:|---:|---:|
| 10k × 8 small ints | 2719 | 2694 | **−0.9 %** | 2696 | 2753 | **−2.1 %** |
| 10k × 20 small ints | 6385 | 6230 | **−2.4 %** | 6227 | 6345 | **−1.9 %** |
| 10k × 20 big ints (~18 digits) | 7492 | 7239 | **−3.4 %** | 7404 | 7441 | −0.5 % |
| 10k × 8 mixed (4 int + 2 text + 2 real) | 9068 | 8917 | **−1.7 %** | 8881 | 9022 | **−1.6 %** |
| 1k × 2 ints | 107 | 102 | **−4.7 %** | 102 | 105 | **−2.9 %** |

All five lanes move candidate-faster in the same direction across the
flip (per [exp 177](177-ab-drift-discriminator.md)'s classifier this
reproduces).

### `select_bytes_real_int_fastpath.dart` (exp 194's harness, µs/query)

| Lane | P1 base | P1 cand | Δ P1 | P2 cand | P2 base | Δ P2 |
|---|---:|---:|---:|---:|---:|---:|
| 10k × 8 integral reals | 3040 | 2947 | **−3.1 %** | 2886 | 2990 | **−3.5 %** |
| 10k × 20 integral reals | 6907 | 6486 | **−6.1 %** | 6410 | 6826 | **−6.1 %** |
| 10k × 20 fractional reals | 69518 | 68843 | −1.0 % | 68884 | 69135 | −0.4 % |
| 10k × 8 mixed (4 int-real + 2 frac-real + 2 text) | 9534 | 9426 | −1.1 % | 9443 | 9553 | −1.2 % |
| 1k × 2 integral reals | 113 | 108 | **−4.4 %** | 110 | 113 | **−2.7 %** |

The fractional-REAL guard (−1.0 % / −0.4 %, the lane where
`snprintf("%.17g")` dominates per-cell wall) stays inside the noise
band — exactly the prediction of an experiment that only removes
per-cell FFI lookup, not per-cell formatter cost. The integral-REAL
lanes carry the largest deltas because they hit the `column_value` +
`value_type` + `value_double` sequence per cell with no expensive
formatter underneath.

### `select_bytes_wide_cols.dart` (exp 190's harness, ms/query)

| Lane | P1 base | P1 cand | Δ P1 | P2 cand | P2 base | Δ P2 |
|---|---:|---:|---:|---:|---:|---:|
| 10k × 8 int | 2.147 | 2.120 | −1.3 % | 2.079 | 2.110 | −1.5 % |
| 10k × 20 int | 5.104 | 4.926 | **−3.5 %** | 4.937 | 5.260 | **−6.1 %** |
| 10k × 8 mixed | 2.454 | 2.332 | **−5.0 %** | 2.301 | 2.381 | **−3.4 %** |
| 10k × 20 mixed | 5.791 | 5.606 | **−3.2 %** | 5.637 | 5.790 | **−2.6 %** |
| 10k × 2 int | 0.638 | 0.628 | −1.6 % | 0.626 | 0.648 | **−3.4 %** |
| 100 rows × 5 mixed | 0.034 | 0.031 | **−8.8 %** | 0.031 | 0.036 | **−13.9 %** |
| 1 row × 5 mixed | 0.018 | 0.016 | — | 0.017 | 0.015 | — |

The 1-row regression guard moves at the sub-µs floor (the harness
reports milliseconds) and is not load-bearing in either direction —
same shape exp 195 / 199 flagged on this lane.

### `large_bytes_transfer.dart` (exp 174's harness, µs/query)

| Lane | P1 base | P1 cand | Δ P1 | P2 cand | P2 base | Δ P2 |
|---|---:|---:|---:|---:|---:|---:|
| large-bytes (~651 KB TEXT) | 252 | 247 | **−2.0 %** | 248 | 256 | **−3.1 %** |
| small-bytes (~65 KB TEXT) | 80 | 77 | **−3.8 %** | 78 | 81 | **−3.7 %** |

Both TEXT lanes show same-direction wins — the TEXT path is where this
change saves the most per cell (`column_text` + `column_bytes` collapses
two `columnMem` lookups into the one `column_value` already cached).

## Decision

**In Review (candidate-accepted at the local level).** Every focused
harness reproduces the same-direction win across the order flip:
integer-heavy lanes move −1 % to −6 %, integral-REAL lanes move
−3 % to −6 %, wide-cols lanes move −1 % to −5 %, large/small TEXT
lanes move −2 % to −4 %. The fractional-REAL guard stays inside ±1 %
across both passes — the cleanest evidence that the saving is
columnMem amortization rather than noise, since fractional REAL is
dominated by `snprintf` and would dilute any genuine per-cell FFI win.

The magnitude sits in the same band as the recent per-cell encoder
wins (exp 192's −8 % to −26 % on the deepest-digit lane is the
ceiling; exp 198's −7 % to −9 % on the same lanes is comparable;
exp 199's −1.6 % to −4 % is the closest neighbour). Each of those
took a different per-cell cost off the table; this one takes the
SQLite-API lookup overhead off.

Bit-identical JSON output: `sqlite3_column_*` is literally
`sqlite3_value_* ∘ columnMem` in the SQLite amalgamation, so any
output difference would imply a Mem cell mutation between the
hoisted `column_value` and the subsequent `value_*` calls. The full
`test/database_test.dart` suite (including the `selectBytes`
embedded-NUL / int extremes / real-integer / base64 BLOB cases)
passes against the candidate.

## Why kept

The change is mechanical and minimal — five `sqlite3_column_X` calls
replaced with one `sqlite3_column_value` and the matching
`sqlite3_value_X` calls, ~10 net additional lines of C in
`write_json_to_buf`. No new state, no new allocation, no public API
change. The safety footnote (NOMUTEX + single-isolate-per-connection
makes "unprotected" and "protected" `sqlite3_value*` indistinguishable)
is a property of the connection lifecycle, not the change.

The saving is structurally what the diff predicts: zero added work
on the per-cell loop, two `columnMem` lookups removed per TEXT/BLOB
cell, one per fixed cell, and one `sqlite3ApiExit` per saved
lookup. Compiler-level: every `sqlite3_value_*` callable is a small
flag-bits check on `pVal->flags` and a direct field read, no
control-flow indirection.

## What this leaves on the table

The remaining per-cell cost is dominated by:

- `sqlite3_column_value` itself — still one `columnMem` per cell. The
  only way below this is a per-statement type cache that decides
  ahead of time which cells need a value lookup at all (the candidate
  [exp 200](200-stable-type-selectbytes-moonshot.md) tried and was
  rejected on storage-class semantics) or a SQLite-internal API
  resqlite does not expose.
- The TEXT / BLOB `json_write_string` (SWAR escape scan) and
  `json_write_base64` loops, which were re-checked by
  [exp 201](201-base64-quote-reservation.md) and
  [exp 202](202-text-json-string-reserve.md) — both rejected for being
  below the noise floor at typical cell sizes.
- `snprintf("%.17g")` on the fractional REAL path — exp 041 already
  rejected a vendored Grisu/Ryu replacement on code-size grounds; a
  smaller hand-rolled fast path remains the only realistic angle.
- The same change is mechanically applicable to `resqlite_step_row`
  and `resqlite_step_row_hash` (the rows / stream-hash paths). Those
  measure on different harnesses (`row_map_facade`, `select_maps`,
  `single_stream_long_payload_hash`) where the per-cell FFI saving is
  a smaller fraction of total wall (each cell pays Dart-side decode
  and isolate transfer afterwards), so they should be picked up by a
  separate experiment that runs against the right gate, not folded
  here.

## Operational notes

- No public API change.
- ~10 net additional lines of C in `native/resqlite.c`; the existing
  switch arms are reshaped to call `sqlite3_value_*` against a hoisted
  `sqlite3_value*`.
- Safe against any future re-introduction of FULLMUTEX connections in
  a single place: callers that need the protected-object guarantee
  would have to copy the `sqlite3_value*` via `sqlite3_value_dup`
  before crossing a thread boundary. resqlite has never done so and
  has no plans to.
- Existing `selectBytes` regression tests (int extremes, integral and
  fractional REAL, base64 BLOB, embedded-NUL TEXT) pass unchanged.
- Builds clean against current sqlite3mc; uses only the public SQLite
  C API.
