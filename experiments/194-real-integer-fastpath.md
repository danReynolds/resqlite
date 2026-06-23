# Experiment 194: Integer-valued REAL selectBytes fast path

**Date:** 2026-06-23
**Status:** In Review
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused A/B
  (`benchmark/experiments/select_bytes_real_int_fastpath.dart`),
  order-flipped pair on a quiet box; no release-suite run because the
  changed path is specifically REAL-cell JSON formatting and the focused
  harness isolates integral REAL, fractional REAL, mixed, and small-payload
  shapes directly.

## Problem

After [exp 190](190-selectbytes-col-name-preencode.md) amortized column-name
tokens and [exp 192](192-two-digit-itoa.md) tightened the `SQLITE_INTEGER`
arm, `write_json_to_buf` still formatted every `SQLITE_FLOAT` cell with
`snprintf("%.17g")`.

That is the right fallback for fractional doubles, huge magnitudes,
NaN/Inf, and negative zero, but it is also paid for REAL columns whose
stored value is exactly integral. Those values are common in schemas that use
REAL affinity for scoring, timestamps, or metrics while still carrying many
whole-number cells. For those cells, the JSON spelling from `%.17g` is the
same decimal integer spelling the existing `fast_i64_to_str` path already
emits for `SQLITE_INTEGER`.

## Hypothesis

If a REAL value is finite, exactly integral, and inside the exact integer
range of a double (`abs(value) <= 2^53`), `selectBytes()` can route it through
`fast_i64_to_str` without changing JSON semantics. The win should reproduce
on real-heavy rowsets where integral REAL cells dominate, while fractional
REAL lanes should stay flat because they still use `snprintf`.

Acceptance criterion: two order-flipped focused passes must improve the
integral-REAL primary lanes by more than 10%, with the fractional-REAL guard
neutral and the small/mixed lanes moving in the predicted direction.

## Approach

In [`native/resqlite.c`](../native/resqlite.c):

- add `fast_double_to_json_num`;
- keep `snprintf("%.17g")` for negative zero, non-finite values, fractional
  values, and values outside the exact `double` integer range;
- route positive zero directly to `"0"`;
- for finite integral values in `[-2^53, 2^53]`, cast to `long long` and reuse
  `fast_i64_to_str`;
- replace only the `SQLITE_FLOAT` call site in `write_json_to_buf`.

The helper is intentionally conservative. It does not try to replace general
floating-point formatting or revive exp 041's broad Ryu/Grisu direction; it
only removes `snprintf` where the existing integer encoder is exactly the same
JSON spelling.

Added focused harness
[`benchmark/experiments/select_bytes_real_int_fastpath.dart`](../benchmark/experiments/select_bytes_real_int_fastpath.dart)
with:

- 10k x 8 integral REAL cells;
- 10k x 20 integral REAL cells;
- 10k x 20 fractional REAL cells as the fallback guard;
- 10k x 8 mixed rowset (4 integral REAL + 2 fractional REAL + 2 TEXT);
- 1k x 2 integral REAL cells as the small-payload guard.

Added `test/database_test.dart` coverage for integral REAL values, fractional
values, and a huge fallback value through `db.selectBytes()`.

## Results

Focused `select_bytes_real_int_fastpath.dart`, two order-flipped passes
(medians in us/query, six rounds per lane):

| Lane | Pass 1 baseline | Pass 1 candidate | Delta | Pass 2 baseline | Pass 2 candidate | Delta |
|---|---:|---:|---:|---:|---:|---:|
| 10k rows x 8 integral reals | 15311 | 3190 | -79.2% | 15367 | 3221 | -79.0% |
| 10k rows x 20 integral reals | 37328 | 6896 | -81.5% | 37491 | 6960 | -81.4% |
| 10k rows x 20 fractional reals | 68508 | 68831 | +0.5% | 68777 | 69095 | +0.5% |
| 10k rows x 8 mixed (4 int-real + 2 frac-real + 2 text) | 15597 | 9566 | -38.7% | 15740 | 10281 | -34.7% |
| 1k rows x 2 integral reals | 438 | 123 | -71.9% | 436 | 123 | -71.8% |

Pass 1 ran baseline first, then candidate. Pass 2 ran candidate first, then
baseline. The primary integral-REAL lanes reproduce at roughly -79% to -82%
in both orderings. The fractional-REAL guard is effectively unchanged, which
confirms the helper is not perturbing the general `snprintf` fallback path.
The mixed lane moves in proportion to its four integral-REAL columns, and the
small lane still moves because `snprintf` dominated the tiny payload.

## Decision

**Accepted / In Review.** The candidate is a small, behavior-preserving
special case with a large reproduced win on the target path and a flat
fractional fallback guard. It does not expand public API, does not change
general floating-point formatting, and keeps negative zero on the old
`snprintf` path.

The release suite is not the right denominator for this change: the public
lanes are not REAL-integer-heavy enough to isolate a per-cell formatter win.
The durable gate for this path is the focused
`select_bytes_real_int_fastpath.dart` harness.

## Future Notes

- Future `SQLITE_FLOAT` work should start with
  `select_bytes_real_int_fastpath.dart`, not the release suite alone.
- Do not broaden this helper beyond exact integral doubles without a separate
  correctness and size argument. Exp 041 already rejected a broad
  third-party float formatter because the code-size and compatibility burden
  outweighed the measured win.
- If a real production profile shows fractional REAL cells dominating
  `selectBytes()` wall time, the next candidate should be a much smaller
  fractional fast path than Ryu/Grisu, with the fractional guard in this
  harness as the acceptance gate.

## Validation

- `dart pub get`
- `dart format benchmark/experiments/select_bytes_real_int_fastpath.dart test/database_test.dart`
- `dart analyze --fatal-infos benchmark/experiments/select_bytes_real_int_fastpath.dart test/database_test.dart`
- `dart test test/database_test.dart --plain-name 'selectBytes encodes real integer-valued numbers'`
- `dart test test/database_test.dart --plain-name 'selectBytes'`
- `dart run benchmark/experiments/select_bytes_real_int_fastpath.dart` on baseline and candidate in baseline-first order
- `dart run benchmark/experiments/select_bytes_real_int_fastpath.dart` on candidate and baseline in candidate-first order
