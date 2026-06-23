# Experiment 196: selectBytes encoder inter-row framing batch

**Date:** 2026-06-23
**Status:** Rejected
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused A/B
  (`benchmark/experiments/select_bytes_wide_cols.dart`), two order-flipped
  passes on a quiet box; no release-suite run because the change is a per-row
  framing micro-opt that no release lane isolates.

## Problem

The `selectBytes()` JSON encoder (`write_json_to_buf` in `native/resqlite.c`)
has had its per-cell work tightened repeatedly: exp 190/195 cache the column
`"name":` tokens, exp 192 the integer itoa, exp 194 the integral-REAL fast
path. What's left untouched is the **structural framing** — the literal `{`,
`}`, and `,` bytes that delimit rows. Per row the loop issues three separate
single-char `buf_write_char` calls at the row boundary (`}` to close the
previous row, `,` to separate, `{` to open the next), each with its own
capacity check.

## Hypothesis

On a wide-many-row result, those structural writes happen ~3 per row — tens of
thousands of capacity-checked single-byte writes on a 10k-row result. Batching
the inter-row `}` + `,` + `{` into a single `buf_write(b, "},{", 3)` (and
emitting the final row's `}` once after the loop) should cut the structural
`buf_write` count by roughly two-thirds without changing a single output byte.
If structural framing is a material share of encoder wall time, the wide
shapes in `select_bytes_wide_cols.dart` should improve a few percent, with the
narrowest shape (10k × 2, where framing is the largest relative share) moving
most.

Acceptance criterion: the wide 10k-row shapes improve by more than the
run-to-run noise floor (~3%), reproduced with the same sign across both
order-flipped passes.

## Approach

In `write_json_to_buf`, replaced the per-row `if (row>0) buf_write_char(',')`
+ `buf_write_char('{')` opening and the per-row `buf_write_char('}')` close
with:

- row 0: `buf_write_char('{')`;
- row > 0: `buf_write(b, "},{", 3)` — closes the prior row, separates, and
  opens this one in one write;
- after the loop: `buf_write_char('}')` to close the final row (skipped when
  there were zero rows).

Output is byte-identical (verified by the existing `selectBytes` correctness
suite, including the empty-result `[]` case and the
`selectBytes matches jsonEncode of select` equality test, all green on the
candidate build).

## Results

Focused `select_bytes_wide_cols.dart`, median ms/call, two order-flipped passes
(candidate-first, then baseline-first):

| Shape | Δ pass 1 | Δ pass 2 |
|---|---:|---:|
| 10k rows × 8 int | −1.1% | −0.3% |
| 10k rows × 20 int | −3.9% | −0.4% |
| 10k rows × 8 mixed | −0.4% | **+1.8%** |
| 10k rows × 20 mixed | −2.3% | −0.3% |
| 10k rows × 2 int (control) | −4.5% | −2.2% |
| 1 row / 100 rows (guards) | sub-µs noise | sub-µs noise |

The two **baseline** runs alone differ by ~2.5% on the 10k × 8 int lane (2.550
vs 2.614 ms), which sets the noise floor for this harness on this machine. Every
candidate delta sits inside that floor: the headline-looking −3.9% on 10k × 20
int collapses to −0.4% on the flipped pass, the mixed shape changes **sign**
across the flip (+1.8%), and the control (10k × 2) moves as much as or more than
the targets — the signature of run-to-run drift, not a real effect.

## Decision

Rejected — below the noise floor. The framing batch removes real `buf_write`
calls, but structural delimiters are a tiny share of encoder wall: the cost is
dominated by the per-cell value formatters (`fast_i64_to_str`,
`fast_double_to_json_num`) and `json_write_string`'s SWAR escape scan, which run
once per *cell*, not per *row*. No runtime code kept.

Would reopen only if a profiler attributes a meaningful share of `selectBytes`
wall specifically to `buf_write` call overhead (e.g. on an extremely narrow,
many-row shape the focused harness doesn't cover), or if `buf_write_char` itself
is shown to be a non-inlined hot call. Until then, treat the encoder's
structural framing as settled and spend effort on the value formatters or the
transfer path instead.
