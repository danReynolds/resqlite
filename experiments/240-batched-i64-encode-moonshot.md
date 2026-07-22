# Experiment 240: Batched i64 → decimal encode moonshot

**Date:** 2026-07-22
**Status:** Rejected
**Category:** Moonshot
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused
  ([`benchmark/experiments/i64_batch_encode.dart`](../benchmark/experiments/i64_batch_encode.dart)
  isolated conversion +
  [`benchmark/experiments/select_bytes_int_heavy.dart`](../benchmark/experiments/select_bytes_int_heavy.dart)
  end-to-end; raw tables in
  [`benchmark/results/2026-07-22T11-23-30Z-exp240-batched-i64-encode.md`](../benchmark/results/2026-07-22T11-23-30Z-exp240-batched-i64-encode.md)).

## Problem

`write_json_to_buf`'s `SQLITE_INTEGER` arm formats one integer cell per call
through `resqlite_json_i64_to_str` (exp 192's two-digit-LUT scalar). Exp 231
tried to speed that formatter with a per-value AArch64 NEON kernel and rejected
it: a scalar per-cell value "converts ONE scalar value per call with nothing to
amortise", so the vector setup never pays back. Exp 231 left one door explicit:

> Reopen only if a future architecture batches many integer cells into one
> encode call (e.g. a columnar/bulk-step transfer that hands the kernel an
> array of i64s).

No experiment had built that batched form. This run does, and asks the paired
question: does handing an encoder an *array* of adjacent integer cells — so
per-value latency can amortise across them — beat per-cell formatting, either
with SIMD or with plain cross-value instruction-level parallelism?

## Hypothesis

Assumption challenged: integer JSON encoding must format one cell at a time, in
row-major order, because that is the shape of the `{"col":val,...}` output.

If adjacent integer cells were formatted as a *batch*, their independent
decimal-division chains could overlap in the CPU's out-of-order window instead
of running fully serialised, and any SIMD setup could amortise across the group
— exactly the amortisation exp 231's per-value kernel lacked.

Accept if a batched candidate reproduces a ≥5 % end-to-end win on integer-heavy
`selectBytes` lanes across the order flip, with no material regression on
short-integer or mixed lanes. Reject if the isolated conversion win does not
survive integration, or if realistic (short-magnitude) columns regress.

Risk budget (moonshot-sized, bounded): three test-only native array encoders, a
new focused microbench, and — only if the microbench showed headroom — a
contained lookahead in the one `SQLITE_INTEGER` arm. No public API change.

## Approach

Two stages, following the "measurement carries the experiment it unlocks" rule.

**Stage 1 — isolated conversion microbench.** Three test-only native encoders
format a whole i64 array to a comma-separated decimal string in one call,
byte-identically:

- `scalar` — the shipped per-value two-digit-LUT formatter (baseline).
- `pipe2` — a 2-way software-pipelined scalar: peel a two-digit pair off two
  independent values per loop trip so their magic-number divides overlap. No
  SIMD.
- `neon` — exp 231's vector 8-digit kernel, inlined and run over the array so
  adjacent values pipeline (the faithful form of exp 231's reopen).

`i64_batch_encode.dart` times pure conversion (no JSON tokens, no SQLite) across
digit-width lanes.

**Stage 2 — end-to-end integration** of the winning microbench candidate
(`pipe2`) into `write_json_to_buf`: when column *i* and *i+1* are both
`SQLITE_INTEGER`, format them with a pipelined pair formatter and emit
`value, token[i+1], value`, advancing past the consumed column. Output is
byte-identical to two single formats; the next token's 16-byte over-copy
(exp 227) lands in that cell's `cell_max` reservation exactly as the per-cell
path's does, so the row-start capacity reservation still covers it. Measured
with the existing `select_bytes_int_heavy.dart` against `origin/main`.

## Results

**Stage 1 — isolated conversion (median ns per 200-value pass, vs `scalar`):**

| Lane | scalar | pipe2 | neon |
|---|---:|---:|---:|
| big ~19–20 digit | 2258 | **−6.6%** | **−16.8%** |
| mid ~10 digit | 947 | **−9.7%** | +57.6% |
| small 0..9999 | 960 | +5.3% | +48.9% |
| mixed magnitudes | 1159 | −1.4% | +0.9% |

`pipe2` reproduces a −6 to −13 % conversion win on mid/big magnitudes across
passes, flat on short/mixed. `neon` wins only on the longest chain and is +45
to +60 % on realistic short values — the fixed vector setup cannot amortise
below ~9 digits. That reproduces exp 231's per-value finding *with an array in
hand*, closing its SIMD reopen door harder rather than opening it, so `pipe2`
(portable, no SIMD) was the only candidate worth integrating.

**Stage 2 — end-to-end `selectBytes` (median-of-4 interleaved passes, µs/query):**

| Lane | Baseline | Candidate | Delta |
|---|---:|---:|---:|
| 10k × 20 small non-neg (0..9999) | 4918 | 5309 | **+7.9%** |
| 10k × 8 small non-neg | 2371 | 2421 | +2.1% |
| 10k × 8 small ints | 2624 | 2792 | +6.4% |
| 10k × 20 small ints | 5824 | 6112 | +4.9% |
| 10k × 20 big ints (~18 digit) | 7156 | 8023 | **+12.1%** |
| 10k × 8 mixed | 8971 | 9055 | +0.9% |
| 1k × 2 ints | 98 | 108 | +10.7% |

The candidate is **uniformly slower end-to-end**, consistent across all four
passes, and worst (+12.1 %) on the big-ints lane — the exact shape where the
isolated `pipe2` conversion won the most. The isolated win inverts completely.

## Decision

**Rejected.** The pipelined-scalar conversion win is real in isolation but the
integer conversion is not `write_json_to_buf`'s bottleneck: per-cell SQLite
value access, token writes, and buffer bookkeeping dominate, and the
pair-lookahead machinery (extra branch, dual scratch buffers, duplicated inner
token emit) costs more than the overlapped divide chains save. The two integers
of a pair are also fetched serially via `sqlite3_value_int64`, so the "two
independent chains" premise that produced the microbench win never holds on the
real path — the same lesson exp 226 recorded (an isolated packer win of −28 %
that did not clear the 5 % end-to-end gate) and exp 231 recorded for per-value
SIMD.

This closes both forms of exp 231's reopen door with direct array-batch
measurement: NEON handed an array still loses on realistic columns, and even a
zero-SIMD pipelined-scalar batch regresses once wired into the row-major
encoder. Integer `selectBytes` encoding stays on the shipped per-cell
two-digit-LUT formatter.

Would reopen only if a future result representation encodes integer columns
*columnar* — i.e. the encoder receives a contiguous array of already-fetched
i64 values, with the JSON framing decoupled from the per-value fetch — so the
cross-value pipelining premise actually holds on the hot path. That is a
transfer-shape change, not a formatter tweak.

No `archive/` tag: the reverted integration is a trivial lookahead in one
`switch` arm, fully described above, and the kept test encoders preserve the
conversion primitives for any future re-evaluation.

## Validation

- `dart analyze --fatal-infos` clean on native, lib, the harness, and the test.
- `dart test test/native_encoder_diff_test.dart` — the new
  `exp 240 batched i64 array encoders differential` group asserts
  `scalar == pipe2 == neon == Dart.toString()` across every ordered pair of
  boundary magnitudes plus 4000 random arrays (0–32 values, full i64 range,
  odd/even lengths), alongside the existing base64 / i64 / selectBytes fuzz.
- `benchmark/experiments/i64_batch_encode.dart` (isolated, 3+ passes) and
  `select_bytes_int_heavy.dart` (end-to-end, 4 interleaved passes vs
  `origin/main`).
