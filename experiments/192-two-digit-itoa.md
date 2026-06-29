# Experiment 192: Two-digit table itoa for selectBytes integer columns

**Date:** 2026-06-21
**Status:** Accepted
**Direction:** `result-transfer-shape`
**Benchmark Run:** Focused A/B (`benchmark/experiments/select_bytes_int_heavy.dart`),
order-flipped pair on a quiet box; release-suite single-pass A/B + flip
included as a no-regression guard (release lanes are not integer-heavy
enough to register the focused signal; release flags are dominated by
phase drift per [exp 159](159-writer-pipelining.md) /
[exp 177](177-ab-drift-discriminator.md)).

## Problem

[Exp 023](023-fast-itoa.md) replaced `snprintf("%lld")` inside
`write_json_to_buf` (the `selectBytes()` JSON encoder) with a hand-rolled
single-digit-per-iteration loop, measuring −12 % on selectBytes 100 rows.
[Exp 190](190-selectbytes-col-name-preencode.md) is in flight pre-encoding
the column-name half of the same per-row loop. The remaining cell-emit
work for integer columns is the single-digit loop itself — one `% 10` and
`/ 10` per output digit, executed once per integer cell per row.

A 10k × 20 INTEGER selectBytes query performs 200,000 integer
conversions; an int64 magnitude up to ~9.2e18 takes up to 19 iterations
per call. Halving the division count by emitting two digits per
iteration (a well-known itoa technique using a `[00..99]` lookup table)
is a bounded next step on a path exp 023 already established as
measurable.

## Hypothesis

Replacing the single-digit `fast_i64_to_str` body with a two-digit table
lookup — one `% 100` / `/ 100` and one 2-byte `memcpy` per pair of output
digits — reduces per-integer encoding cost enough to show a measurable
signal on integer-heavy `selectBytes` at row × column counts where the
JSON int-to-string path is a significant fraction of total wall time.
Bigger digit counts amplify the win; the worst case for the old loop
(~18-digit magnitudes) sees the biggest absolute improvement.

## Approach

In [`native/resqlite.c`](../native/resqlite.c):

- Add a 200-byte `kTwoDigits` table containing `"0001020304...9899"`.
- Rewrite `fast_i64_to_str` to write into a 20-byte stack `tmp` buffer
  from the tail inward, consuming two decimal digits per iteration via
  `kTwoDigits + d * 2`. The trailing 1 or 2 digits are handled by a
  single tail branch.
- Negative handling, the LLONG_MIN sentinel
  (`(unsigned long long)(-(val + 1)) + 1`), and the `val == 0` short
  circuit are preserved bit-for-bit from exp 023.
- The function still returns the number of bytes written into `buf`
  and is still consumed by exactly one call site
  (`write_json_to_buf`'s `SQLITE_INTEGER` arm).

Add the focused A/B harness
[`benchmark/experiments/select_bytes_int_heavy.dart`](../benchmark/experiments/select_bytes_int_heavy.dart)
with three int-heavy primary lanes (10k × 8 small ints, 10k × 20 small
ints, 10k × 20 big ints ~18 digits) and two regression guards (10k × 8
mixed of int/text/real, 1k × 2 small ints).

Add an int-extremes correctness test to `test/database_test.dart`
covering 0, ±1, ±9, ±10, ±99, ±100, ±999, ±10000, ±1234567890, LLONG_MIN
and LLONG_MAX through `db.selectBytes()` end-to-end.

## Results

Focused `select_bytes_int_heavy.dart`, two order-flipped passes (medians
in µs/query, 6 rounds each, ≥10 iterations per round; quiet box):

| Lane | Pass 1 baseline | Pass 1 candidate | Δ | Pass 2 baseline | Pass 2 candidate | Δ |
|---|---:|---:|---:|---:|---:|---:|
| 10k rows × 8 small ints  | 3407 | 3034 | −10.9 % | 3380 | 2987 | −11.6 % |
| 10k rows × 20 small ints | 7808 | 6993 |  −10.4 % | 7705 | 7063 |  −8.3 % |
| 10k rows × 20 big ints (~18 digits) | 12029 | 8908 | −25.9 % | 11700 | 8906 | −23.9 % |
| 10k rows × 8 mixed (4 int + 2 text + 2 real) | 9455 | 9369 |  −0.9 % | 9435 | 9462 | +0.3 % |
| 1k rows × 2 ints | 130 | 126 |  −3.1 % | 130 | 119 |  −8.5 % |

Pass 1 = baseline first; Pass 2 = candidate first. Every int-heavy
primary lane moves same-direction across the order flip, with the
biggest win on the deepest-digit shape — exactly the shape the algorithm
predicts (fewer divisions for longer digit chains). The 10k × 8 mixed
regression guard sits inside ±1 % across both passes (integer cells are
not dominant in that lane). The 1k × 2 ints lane is small absolute (~10
µs) and order-noisy.

Release-suite single-pass A/B (`run_release.dart --repeat=1`) and an
order-flipped second pass: indistinguishable at the selectBytes lanes
because none of them is integer-heavy enough to register. The same 10k
rows → JSON Bytes lane reads 3.545 / 5.213 / 3.598 / 3.739 ms across the
four side-passes — *which side is first* explains more variance than
*which side is candidate*. The remaining release flags (Long-Text /
Long-Payload Unchanged Fanout, Nested Transactions, column-granularity
re-emit counters) reverse sign across the order flip and live on
hash/savepoint/dependency paths the change cannot mechanically touch —
the [exp 159](159-writer-pipelining.md) /
[exp 177](177-ab-drift-discriminator.md) drift signature. No release
lane regresses reproducibly.

Memory: zero RSS delta (the change adds a 200-byte `const` table to
`.rodata`).

## Decision

**Accepted / In Review.** The two-digit table cuts integer JSON encoding
cost on the `selectBytes()` hot path by ~8 % to ~26 % across two
order-flipped focused passes, with the biggest win on the highest-digit
shape. The mixed-cell regression guard stays flat. The change is
contained — one 200-byte `const` table and a rewritten function body
behind the same signature, with `LLONG_MIN` handling preserved
bit-for-bit and end-to-end int-extremes correctness covered by a new
test.

The release suite is not the right denominator for this change — none of
its lanes is integer-heavy enough to register the per-cell saving — so
the focused harness is the durable evidence, and `select_bytes_int_heavy.dart`
is the gate for future int-JSON encoder work.

## Future Notes

The change closes the bounded `fast_i64_to_str` headroom that exp 023
left on the table. Further itoa wins (4- or 8-digit tables, branchless
log10 length prediction) are diminishing returns on integer-heavy
selectBytes — `select_bytes_int_heavy.dart` is the right denominator if
a future runner wants to confirm or close that follow-up. The bigger
remaining slice of `write_json_to_buf` is the `SQLITE_FLOAT` arm's
`snprintf("%.17g")` call; [exp 041](041-ryu-double-to-string.md) already
rejected a vendored Grisu/Ryu replacement on size grounds, so any future
float-encode candidate needs either a much smaller fast path or a real
production profile showing FLOAT cells dominate selectBytes wall time.
