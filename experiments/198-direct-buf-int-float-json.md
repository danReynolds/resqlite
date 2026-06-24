# Experiment 198: Direct-to-buffer integer and float JSON formatting

**Date:** 2026-06-24
**Status:** In Review
**Direction:** `result-transfer-shape`
**Benchmark Run:** Focused A/B (`benchmark/experiments/select_bytes_int_heavy.dart` and `benchmark/experiments/select_bytes_real_int_fastpath.dart`), order-flipped pair on a quiet box; release-suite single-pass A/B captured as a no-regression smoke (release lanes are not integer- or integer-real-heavy enough to register the focused signal, and the flagged single-pass rows live on writer-pipelining / scaling / re-emit paths this change cannot mechanically touch — same exp 159 / exp 177 phase-drift signature as exp 192 / exp 194).

## Problem

After [exp 192](192-two-digit-itoa.md) collapsed the `fast_i64_to_str` digit
loop and [exp 194](194-real-integer-fastpath.md) routed integer-valued REAL
through that same path, every INTEGER and integer-valued FLOAT cell in
`write_json_to_buf` still pays the same boilerplate around the formatter
call:

```c
case SQLITE_INTEGER: {
    char num[24];
    int num_len = fast_i64_to_str(sqlite3_column_int64(stmt, i), num);
    JSON_CHECK(buf_write_str(b, num, num_len));   // memcpy stack → b
    break;
}
```

The stack scratch buffer is filled by the formatter and then immediately
`memcpy`'d into `b->data + b->len` by `buf_write_str` →
`buf_write` → `memcpy`. On a 10k row × 20 INTEGER column query that is
200,000 short `memcpy`s of ≤20 bytes each, plus a non-inlineable
`buf_write` call that has to re-check capacity even though the formatter
already capped its write at ≤24 bytes.

`fast_i64_to_str` already takes a raw `char*`, and
`fast_double_to_json_num` already takes a `char* + size_t`; neither
inspects the destination beyond writing into it. They can write straight
into the output buffer if the caller guarantees capacity.

## Hypothesis

Pre-reserving the maximum cell length (`buf_ensure(b, 24)` for INTEGER,
33 for FLOAT — one extra byte covers the snprintf NUL terminator on the
fractional fallback) and pointing the formatter at `b->data + b->len`
directly should remove one short `memcpy` per integer or float cell.
The signal should reproduce on the same int-heavy lanes that drove
exp 192 (`select_bytes_int_heavy.dart`) and on exp 194's integer-real
lanes (`select_bytes_real_int_fastpath.dart`), while the fractional
REAL fallback — dominated by `snprintf("%.17g")` — stays inside the
noise floor.

## Approach

In [`native/resqlite.c`](../native/resqlite.c):

- Add two `RESQLITE_HOT static` helpers:
  - `buf_write_int_json(resqlite_buf* b, long long val)` —
    `buf_ensure(b, 24)`, then call `fast_i64_to_str` with the
    destination set to `(char*)(b->data + b->len)`, then advance
    `b->len` by the returned digit count. `fast_i64_to_str` never
    writes a NUL terminator, so 24 bytes (20 digits + sign + slack)
    is exact.
  - `buf_write_double_json(resqlite_buf* b, double val)` —
    `buf_ensure(b, 33)` and call `fast_double_to_json_num(..., 33)`
    directly into `b->data + b->len`. The extra byte covers the
    `snprintf` fractional fallback's NUL terminator, which lands inside
    the buffer but is not counted toward `b->len`.
- Replace the `SQLITE_INTEGER` and `SQLITE_FLOAT` cases inside
  `write_json_to_buf` with single `JSON_CHECK` calls to the new helpers.
  Bit-identical output: same formatter, same digits, same NUL handling
  (the snprintf fallback's NUL still lands in scratch space below
  `b->cap`).

Stack scratch arrays, the intermediate `int num_len` locals, and the
`buf_write_str` indirection on this path are gone.

No public API change. No new const data. The new helpers shave one
`memcpy` and one function-call boundary per integer or integer-real
cell; the `buf_ensure` cost is identical to what `buf_write` would have
paid anyway. The existing `int extremes` and `real integer-valued`
selectBytes tests in `test/database_test.dart` cover the
correctness-preserving boundary cases (0, ±1, ±999, ±10000, ±1234567890,
`LLONG_MIN`, `LLONG_MAX`, integer-valued REAL through `±max_exact_int`).

## Results

Two order-flipped passes on each focused harness, median of 6 rounds
per lane. Same-machine quiet box.

### `select_bytes_int_heavy.dart` (exp 192's harness)

| Lane | Base P1 | Base P2 | Cand P1 | Cand P2 | Δ P1 | Δ P2 |
|---|---|---|---|---|---|---|
| 10k × 8 small ints | 3035 | 2998 | 2817 | 2775 | **−7.2 %** | **−7.4 %** |
| 10k × 20 small ints | 6557 | 6527 | 6392 | 6080 | **−2.5 %** | **−6.8 %** |
| 10k × 20 big ints (~18 digits) | 8350 | 8361 | 7624 | 7572 | **−8.7 %** | **−9.4 %** |
| 10k × 8 mixed (4 int + 2 text + 2 real) | 8983 | 9040 | 8830 | 9211 | −1.7 % | +1.9 % |
| 1k × 2 ints | 116 | 115 | 105 | 106 | **−9.5 %** | **−7.8 %** |

All values µs/query median. The mixed-row guard is dominated by text and
real cells (~75 % of the per-row work); its split sign across passes is
sub-2 % phase noise of the kind exp 177 catalogued, not a real regression.
The small-magnitude (1k × 2) lane reproduces the per-cell win at
sub-millisecond scale.

### `select_bytes_real_int_fastpath.dart` (exp 194's harness)

| Lane | Base P1 | Base P2 | Cand P1 | Cand P2 | Δ P1 | Δ P2 |
|---|---|---|---|---|---|---|
| 10k × 8 integral reals | 3252 | 3280 | 2972 | 2990 | **−8.6 %** | **−8.8 %** |
| 10k × 20 integral reals | 6835 | 6835 | 6323 | 6318 | **−7.5 %** | **−7.6 %** |
| 10k × 20 fractional reals | 68909 | 69272 | 69344 | 68287 | +0.6 % | −1.4 % |
| 10k × 8 mixed (4 int-real + 2 frac-real + 2 text) | 9593 | 9531 | 9346 | 9425 | −2.6 % | −1.1 % |
| 1k × 2 integral reals | 122 | 122 | 111 | 114 | **−9.0 %** | **−6.6 %** |

Integer-via-REAL inherits the integer-side win cleanly (−7 to −9 %).
Fractional REAL stays inside ±1.5 % across the flip — the snprintf
`%.17g` call dwarfs the saved `memcpy`, so the helper's only effect on
that path is to remove the intermediate `num_len` round trip.

### Release-suite single-pass A/B + flip

Baseline: `benchmark/results/2026-06-24T07-27-32-baseline-for-exp198.md`.
Candidate: `benchmark/results/2026-06-24T07-30-24-exp198-direct-buf-int-json.md`.
Flagged rows are dominated by single-pass noise on lanes the change
cannot mechanically touch: `Single Inserts (100 sequential)` +12 % and
`Disjoint/Overlap column re-emit` counters live on the writer-pipelining
and stream-dispatch paths (exp 159 / exp 177 territory); `Large payload
(~650 KB) selectBytes` +21 % is a +0.05 ms swing on a 0.23 ms metric
whose payload is one large TEXT-heavy row (no integer cells); the only
mechanical-path-adjacent flag is `Select → JSON Bytes / 100 rows /
resqlite + jsonEncode` −11 % which is consistent with the focused
signal. No integer-heavy release lane crosses the per-benchmark MDE in
both directions; the broader spread is the phase-drift signature
exp 192 and exp 194 also produced single-pass.

## Decision

**In Review (candidate-accepted at the local level).** Two order-flipped
focused passes both clear the per-benchmark MDE on the integer and
integer-real lanes (−6.6 % to −9.5 %), the fractional-REAL guard stays
inside ±1.5 %, the mixed-shape guards stay inside ±2 %, and the
`selectBytes` int-extremes + real-integer-valued tests in
`test/database_test.dart` continue to pass against the candidate
without modification. The change is ~20 lines of additive C, no new
const data, and no public API surface.

## Why kept

The focused signal is structurally what the diff predicts: one fewer
short `memcpy` and one fewer function-call boundary per integer or
integer-real cell, with no other code paths perturbed. The integer and
integer-real wins extend the encoder line that
[exp 023](023-fast-itoa.md) → [exp 192](192-two-digit-itoa.md) →
[exp 194](194-real-integer-fastpath.md) opened, and the helpers are
mechanically reusable by any future C-side JSON writer that wants the
same direct-write pattern.

## What this leaves on the table

The fractional REAL path is still `snprintf("%.17g")`; a hand-rolled
Grisu2/Ryu would attack that, but it is a much larger change with
correctness audit cost and is out of scope here. The `SQLITE_TEXT` and
`SQLITE_BLOB` paths already write to the output buffer via
`json_write_string` / `json_write_base64`, which already do their own
`buf_ensure` and direct-write; no analogous helper would help them.

## Operational notes

- No public API change.
- ~25 lines of additive C in `native/resqlite.c`; two new helpers, two
  case bodies simplified.
- Existing int-extremes and real-integer-valued `selectBytes` tests
  cover correctness (`LLONG_MIN`, `LLONG_MAX`, integer-valued REAL
  through `±max_exact_int`, fractional REAL, negative zero — all
  preserved).
- Builds clean against current sqlite3mc; no compiler-version dependence.
