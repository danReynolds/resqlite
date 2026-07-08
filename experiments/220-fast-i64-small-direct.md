# Experiment 220: reject `fast_i64_to_str` 0..9999 direct-write fast path

**Date:** 2026-07-08
**Status:** Rejected
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused
  [`benchmark/experiments/select_bytes_int_heavy.dart`](../benchmark/experiments/select_bytes_int_heavy.dart);
  raw pair tables in
  [`benchmark/results/2026-07-08T11-15-15Z-exp220-fast-i64-small-direct.md`](../benchmark/results/2026-07-08T11-15-15Z-exp220-fast-i64-small-direct.md).
**Archive:** [`archive/exp-220`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-220)

## Problem

`selectBytes()` serialises every `SQLITE_INTEGER` cell through
[`fast_i64_to_str`](../native/resqlite.c) inside `write_json_to_buf`. After
[exp 192](192-two-digit-itoa.md) replaced the exp-023 single-digit loop with a
two-digit `[00..99]` lookup, the tightest small-int path looks roughly like:

```c
if (val == 0) { buf[0] = '0'; return 1; }
char tmp[20];
int pos = 20, negative = 0;
unsigned long long uval = ...; // sign-normalise (LLONG_MIN safe)
while (uval >= 100) { ...pos -= 2; memcpy(tmp+pos, ..., 2); }
if (uval >= 10)   { pos -= 2; memcpy(tmp+pos, ..., 2); }
else              { tmp[--pos] = '0' + uval; }
int digits = 20 - pos;
if (negative) buf[len++] = '-';
memcpy(buf + len, tmp + pos, digits);
```

For the typical row-id / small-key / small-count shape (`0..9999`) the code
still writes the digits into a stack scratch `tmp[20]`, computes `pos`, then
`memcpy`s from `tmp+pos` back to `buf`. Every cell pays one write to `tmp`,
one `memcpy` from `tmp` to `buf`, and the sign-normalisation branch even
though it is never taken.

Row IDs, foreign-key indices, denormalised counts, and status enums are among
the most common INTEGER column shapes in real schemas, and many of them
naturally live in `0..9999` (small tables, small counts, low-cardinality
enums, small timestamp derivatives). A direct-write fast path that skips the
`tmp[]` scratch, sign branch, and the trailing `memcpy` should be the next
bounded step after [exp 192](192-two-digit-itoa.md) and
[exp 194](194-real-integer-fastpath.md) inside the same `write_json_to_buf`
per-cell chain.

## Hypothesis

A `0..9999` direct-write branch at the top of `fast_i64_to_str` should reduce
per-cell integer JSON encoding wall time on workloads where every cell hits
that range. Larger magnitudes and negatives fall through unchanged; output
bytes stay byte-identical across the whole `int64` range.

Predictions:

- New `10k rows x 20 small non-neg ints (0..9999)` and
  `10k rows x 8 small non-neg ints (0..9999)` lanes should reproduce
  candidate-faster across an order-flipped pair.
- The `~18 digit big ints` lane should stay neutral: every cell falls
  through the fast-path gate unchanged.
- The exp-192 baseline `small ints` lanes (uniform `[-2^29, 2^29)`) will
  either stay neutral (if the extra compare-and-branch is below the effect
  floor) or reproduce a small regression (if the added per-cell instruction
  count is measurable).

Reject if the primary target lanes fail to reproduce, or if the exp-192
baseline lanes reproduce a regression above the sub-1% guards that recent
encoder wins (exp 190 / 192 / 194 / 195 / 216) have shipped with.

## Approach

Change only [`native/resqlite.c`](../native/resqlite.c). Insert the fast path
between the existing `val == 0` shortcut and the exp-192 general path:

```c
if ((unsigned long long)val < 10000ULL) {
    unsigned uv = (unsigned)val;
    if (uv < 10)   { buf[0] = '0' + uv; return 1; }
    if (uv < 100)  { memcpy(buf, kTwoDigits + uv*2, 2); return 2; }
    if (uv < 1000) { /* one digit + one pair */ return 3; }
    /* 1000..9999: two pairs */ return 4;
}
// exp-192 general path unchanged.
```

Casting a signed `long long` to `unsigned long long` treats negatives as very
large unsigned values, well above `10000ULL`, so no explicit sign check is
needed inside the fast path; negatives, `LLONG_MIN`, and `|val| >= 10000` all
fall through to the existing implementation.

Extend
[`benchmark/experiments/select_bytes_int_heavy.dart`](../benchmark/experiments/select_bytes_int_heavy.dart)
with two new lanes at the top of the run that isolate the fast path
(`10k x 20` and `10k x 8`, every cell drawn from `rng.nextInt(10000)`). The
existing exp-192 lanes below them keep the mixed-magnitude uniform
`[-2^29, 2^29)` distribution so any per-cell overhead added to the general
path is visible.

The runtime prototype is archived at `archive/exp-220` and reverted from the
final branch. No runtime code is kept.

## Results

Focused harness:
`dart run benchmark/experiments/select_bytes_int_heavy.dart`. Values are
median microseconds per `selectBytes()` query.

| Lane | B1 | C1 | Delta 1 | C2 | B2 | Delta 2 |
|---|---:|---:|---:|---:|---:|---:|
| 10k rows x 20 small non-neg ints (0..9999) | 4897 | 4331 | -11.6% | 4336 | 4842 | -10.4% |
| 10k rows x 8 small non-neg ints (0..9999) | 2183 | 1945 | -10.9% | 1976 | 2189 | -9.7% |
| 10k rows x 8 small ints | 2572 | 2645 | +2.8% | 2657 | 2589 | +2.6% |
| 10k rows x 20 small ints | 5790 | 5985 | +3.4% | 5953 | 5783 | +2.9% |
| 10k rows x 20 big ints (~18 digits) | 7228 | 7284 | +0.8% | 7350 | 7301 | +0.7% |
| 10k rows x 8 mixed (4 int + 2 text + 2 real) | 8664 | 8654 | -0.1% | 8637 | 8684 | -0.5% |
| 1k rows x 2 ints | 98 | 98 | 0.0% | 107 | 99 | +8.1% |

The fast path reproduces its target win on both new lanes with the same sign
across the order-flipped pair: `10k x 20 small non-neg` moves -11.6% and
-10.4%, `10k x 8 small non-neg` moves -10.9% and -9.7%. Every cell in those
lanes hits the direct-write branch, so the win magnitude is the pure per-cell
saving from the eliminated `tmp[]` write, `memcpy` from `tmp` to `buf`, and
sign-normalisation branch.

The exp-192 baseline `small ints` lanes reproduce a small regression in the
same direction across the flip. Their distribution is uniform in
`[-2^29, 2^29)`, so essentially every cell (>99.999%) falls through the
fast-path gate. Branch prediction is not the driver — the predictor cleanly
learns `always fall through` — so the ~3% reproduced cost is instruction-
count overhead from the added compare-and-branch per cell, not a mispredict.

The `~18-digit big ints` regression guard stays neutral (+0.8% / +0.7%,
below the 3% effect floor), and the 4-int-plus-text-plus-real mixed row is
neutral (-0.1% / -0.5%). The `1k x 2 ints` sub-100us lane took a slow
outlier in pair 2 but is not load-bearing at that resolution.

Focused correctness:

```bash
dart test test/database_test.dart -n "selectBytes"
```

All nine selectBytes tests passed against the candidate — including the
`selectBytes encodes int64 extremes` test that already covers 0, 1, 9, 10,
99, 100, 999, -999, 1000, 9999, 10000, 12345, -12345, deep magnitudes, and
`LLONG_MIN` / `LLONG_MAX`, i.e. every boundary of the new fast path — before
the runtime change was reverted.

## Decision

Rejected.

The primary target reproduces cleanly, but the reproduced ~3% regression on
the load-bearing `small ints` lane sits well above the sub-1% guards that
exp 190 / 192 / 194 / 195 / 216 shipped with. The mixed-magnitude
distribution represents a real workload shape (signed row IDs, foreign
keys, epoch-derived timestamps), and without a production profile showing
`0..9999` INTEGER columns dominate a shipped app's `selectBytes` wall, adding
a per-cell compare-and-branch that slows the general path by ~3% for a
~10% win on a narrow range is not a clear trade.

Would reopen if any of the following changes:

- A production profile or downstream user report shows a shipped app spends
  meaningful `selectBytes` wall time in `fast_i64_to_str` on columns that
  live entirely in `0..9999`.
- A follow-up finds a mechanism that adds no per-cell overhead on cells that
  fall through — for example, a compile-time-specialised encoder chosen per
  column-type hint on `resqlite_cached_stmt`, or PGO on a workload known to
  be small-non-neg-heavy.
- Two order-flipped passes on both `10k x 20 small non-neg (0..9999)` and
  `10k x 20 small ints` clear the acceptance gate together — the second
  gate is what this run failed.

The runtime prototype is preserved at `archive/exp-220`. The extended
`select_bytes_int_heavy.dart` harness is the durable contribution: its two
new small-non-neg lanes plus the existing exp-192 baseline lanes are now the
acceptance gate for any future small-int JSON encoder work in the
`result-transfer-shape` direction.

## Test plan

- [x] `dart pub get` in the exp-220 worktree
- [x] `dart test test/database_test.dart -n "selectBytes"` (nine tests
      including int64 extremes and REAL integer-valued numbers)
- [x] `dart analyze benchmark/experiments/select_bytes_int_heavy.dart` clean
- [x] Focused order-flipped A/B with
      `benchmark/experiments/select_bytes_int_heavy.dart` (two pairs; see
      Results)
