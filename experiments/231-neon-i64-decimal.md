# Experiment 231: Reject AArch64 NEON integer→decimal kernel

**Date:** 2026-07-15
**Status:** Rejected
**Category:** Moonshot
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused
  [`benchmark/experiments/select_bytes_int_heavy.dart`](../benchmark/experiments/select_bytes_int_heavy.dart);
  raw pair tables across three methodologies in
  [`benchmark/results/2026-07-15T13-06-57Z-exp231-neon-i64-decimal.md`](../benchmark/results/2026-07-15T13-06-57Z-exp231-neon-i64-decimal.md).
  No release-suite run because no release lane is integer-encode-heavy; the
  focused int harness is the durable gate established by exp 192.
**Archive:** [`archive/exp-231`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-231)

## Problem

`selectBytes()` serialises every `SQLITE_INTEGER` cell through
`resqlite_json_i64_to_str` inside `write_json_to_buf`.
[Exp 023](023-fast-itoa.md) replaced `snprintf` with a single-digit
loop; [exp 192](192-two-digit-itoa.md) halved the division count with a
two-digit `[00..99]` table and won −24% to −26% on the 10k×20 ~18-digit BIGINT
lane — proof that on integer-heavy payloads the itoa itself is a material
fraction of `selectBytes` wall.

For a large magnitude the two-digit loop is a **serial dependency chain**: each
iteration's `uval /= 100` feeds the next, so an 18-digit value walks ~9
dependent `umulh`+`memcpy` steps that cannot overlap. [Exp 229](229-simd-base64-neon.md)
had just landed the codebase's first AArch64/NEON kernel (base64) and named the
categorical implication that *out-of-lined ISA-specific kernels are viable*.
The tempting frontier: apply the same mechanism to the integer arm — break the
serial `/100` chain by splitting the magnitude into independent 8-digit groups
and formatting each in parallel with NEON.

## Hypothesis

**Assumption challenged:** the scalar two-digit-table loop is the floor for
integer JSON encoding, and exp 229's "out-of-line ISA kernel wins" generalises
from bulk byte payloads (base64) to scalar per-cell values (integers).

A NEON kernel that splits `uval` into a most-significant group plus up to two
zero-padded 8-digit groups, formats each 8-digit group with two vector
reciprocal splits (no per-digit serial dependency), and reassembles the digits,
was expected to beat the scalar chain on the deep-magnitude BIGINT lane.

Accept only if the 10k×20 BIGINT lane reproduces a candidate-faster win across
an order flip while the small-magnitude and mixed guard lanes stay neutral
(small magnitudes never enter the kernel). Reject if the target does not lean
faster.

## Approach

The archived prototype (`archive/exp-231`) added, gated on
`defined(__aarch64__) && defined(__ARM_NEON)`:

- `resqlite_json_u64_digits_neon` — an `__attribute__((noinline))` kernel (out
  of line, mirroring exp 229's small-path lesson) that splits the magnitude into
  `low8`, `mid8`, and a `high` group (0..1844) with two `/1e8` divides, then
  formats each 8-digit group via `neon_write_8_digits`.
- `neon_write_8_digits` — one scalar `/10000` split, then two NEON reciprocal
  passes: `(d*5243)>>19` for `/100` on 32-bit lanes and `(p*205)>>11` for `/10`
  on 16-bit lanes, with `vzip`/`vmovn`/`vst1` assembling 8 ASCII bytes. Both
  reciprocals are exact over their input ranges.
- `resqlite_json_i64_to_str` became a dispatcher: magnitudes ≥ 1e8 (≥ 9 digits)
  on AArch64 use the kernel; everything shorter, and every non-AArch64 target,
  stayed on the byte-identical scalar two-digit path (`..._scalar`). Small ints
  — the exp 220 lane — never entered the kernel.

Output is byte-for-byte identical to the scalar formatter. Correctness was
proven by a new differential test (`resqlite_test_i64_to_str` +
`native_encoder_diff_test.dart`): boundary magnitudes, an 8-digit-group sweep in
every group position, and 300k random full-i64 values, each asserted equal to
Dart's `int.toString()` for both the dispatch and forced-scalar paths.

## Results

The measurement environment was hostile: a shared dev machine with 15+ active
experiment worktrees, so the **identical-code** control lanes (`x20`/`x8` small
non-neg, same scalar bytes in both builds) drifted ±10–120% between paired runs.
No single pair is clean enough to quote a precise magnitude, so the load-bearing
evidence is the *sign of the target lane held across every methodology*.

| Methodology (BIGINT ~18-digit lane) | candidate vs baseline |
|---|---:|
| interleaved, baseline-first (×3) | +1.2% / +6.0% / +9.8% |
| order-flipped, candidate-first (×3) | +28% / +36% / +16% |
| 5-round min-of-N (min defeats additive noise) | +11.3% |
| earliest quiet solo pair | −0.6% (within noise) |

Across 11 passes the candidate is **never** convincingly faster on the target;
its best showing is ~flat in the one quiet pair, and it is measurably slower
everywhere the machine was loaded. Meanwhile the identical-code controls scatter
symmetrically around zero (−14% to +118%), confirming the drift is
environmental, not a code effect. A real ≥5% kernel win would have surfaced as a
consistent candidate-faster lean on the BIGINT lane in at least the quieter
passes; the opposite direction reproduced instead.

## Decision

**Rejected.** Keep the scalar two-digit-table itoa. Runtime prototype reverted
and preserved at `archive/exp-231`.

**Why it fails, and the transferable finding:** exp 229's base64 kernel wins
because one call amortises SIMD setup over an entire BLOB — tens to thousands of
bytes per invocation. The integer formatter is the opposite shape: one call
converts **exactly one** scalar value, so the out-of-line call boundary plus
vector setup is paid *per cell* with nothing to amortise it against, and it
loses to a fully-inlined scalar loop that the CPU already pipelines well. The
row-at-a-time result architecture never exposes a batch of integers to a single
kernel call. So exp 229's "out-of-line ISA kernels are viable" claim is bounded:
**viable for bulk per-cell payloads, not for scalar per-cell values.** Inlining
the kernel to remove the call boundary is the wrong fix — it would bloat the
per-cell hot loop in `write_json_to_buf` and regress the common small-int case,
exactly the code-generation regression exp 229 and exp 230 both hit when SIMD
state leaked into a hot scalar path.

Reopen only if a future architecture batches many integer cells into one encode
call (e.g. a columnar/bulk-step transfer that hands the kernel an array of
i64s), or a production profile shows integer-heavy `selectBytes` dominating wall
time enough to justify a different mechanism than per-cell dispatch. Do not
retry a per-cell integer SIMD kernel: the amortisation floor, not the digit
algorithm, is what sinks it.

## Validation

- `dart test test/native_encoder_diff_test.dart` — 7/7 pass (prototype: NEON
  path byte-identical to scalar and to Dart's oracle across boundaries, an
  8-digit-group sweep, and 300k random i64; publication: the shipped scalar
  formatter under the same differential harness).
- `dart analyze` on the changed sources.
- 11 focused A/B passes in three methodologies (interleaved both orders +
  min-of-N); AArch64 syntax/`-Wall` clean.
- `dart run benchmark/finalize_experiment.dart --experiment=experiments/231-neon-i64-decimal.md`.

The `resqlite_test_i64_to_str` export and the i64 differential test group are
**kept** on the publication branch: the integer JSON formatter previously had no
direct differential coverage (only 200 random ints via the selectBytes fuzz),
and boundary/full-range coverage of the scalar path is worth keeping regardless
of the kernel's rejection.
