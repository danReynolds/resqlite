# exp 230 — AArch64 NEON JSON safe-prefix scan + copy

**Date:** 2026-07-15
**Harness:** `benchmark/experiments/select_bytes_text_string_reserve.dart`
**Hardware:** Apple Silicon (macOS ARM64)
**Baseline:** `932015a` (runtime equal to `origin/main` at `f75cae6`)
**Candidate:** `archive/exp-230` at `bbd767a`

The candidate fused JSON escape classification and payload copying for TEXT
values of at least 256 bytes. AArch64 NEON classified 16 bytes at a time with
`vcltq_u8` / `vceqq_u8` / `vmaxvq_u8` and stored safe vectors with
`vst1q_u8`. The first unsafe vector transferred to the canonical scalar byte
loop; SIMD was not restarted after an escape. All shorter values and all
non-AArch64 targets retained the scalar encoder.

## Decision gate

- Accept only if the 256-byte and 1 KiB safe ASCII lanes reproduce at least
  15% candidate-faster across the order flip, with CJK in the same direction.
- Keep short, mixed, control, and escaped lanes within the 3% effect floor.
- Reject a win confined to the 1 KiB micro-lane or a target that misses the
  gate in either ordering.

## Final raw medians (microseconds/query)

Each lane runs six rounds and reports the median. The first pair ran candidate
then baseline; the second flipped the order.

### Pair 1 — candidate then baseline

| Lane | Candidate | Baseline | Delta |
| --- | ---: | ---: | ---: |
| 10k x 8 short ASCII (16 B) | 2625 | 2486 | +5.6% |
| 10k x 20 short ASCII (16 B) | 7013 | 5561 | +26.1% |
| 10k x 8 safe ASCII (64 B) | 3295 | 3300 | -0.2% |
| 10k x 8 safe ASCII (96 B) | 3754 | 3680 | +2.0% |
| 10k x 8 safe ASCII (256 B) | 5477 | 6653 | **-17.7%** |
| 2k x 4 safe ASCII (1 KiB) | 1526 | 2298 | **-33.6%** |
| 2k x 4 CJK (1K code units) | 2673 | 3573 | **-25.2%** |
| 10k x 8 escaped (24 B) | 6859 | 6672 | +2.8% |
| 10k x 8 early escape (96 B) | 19053 | 19111 | -0.3% |
| 10k x 8 late escape (96 B) | 4088 | 4141 | -1.3% |
| 10k x 8 early escape (256 B) | 48293 | 47030 | +2.7% |
| 10k x 8 late escape (256 B) | 6165 | 7340 | -16.0% |
| 10k x 8 control (24 B) | 5702 | 5720 | -0.3% |
| 10k x 8 mixed | 4891 | 5209 | -6.1% |
| 1k x 2 short ASCII (16 B) | 97 | 97 | 0.0% |

The 20-column short result is a run-local outlier: no prototype code is
entered below 256 bytes, and the order-flipped pair collapses it to +1.4%.

### Pair 2 — baseline then candidate

| Lane | Baseline | Candidate | Delta |
| --- | ---: | ---: | ---: |
| 10k x 8 short ASCII (16 B) | 2470 | 2533 | +2.6% |
| 10k x 20 short ASCII (16 B) | 5592 | 5670 | +1.4% |
| 10k x 8 safe ASCII (64 B) | 3160 | 3300 | +4.4% |
| 10k x 8 safe ASCII (96 B) | 3656 | 3714 | +1.6% |
| 10k x 8 safe ASCII (256 B) | 6850 | 5986 | **-12.6%** |
| 2k x 4 safe ASCII (1 KiB) | 2255 | 1487 | **-34.1%** |
| 2k x 4 CJK (1K code units) | 3457 | 2575 | **-25.5%** |
| 10k x 8 escaped (24 B) | 6673 | 6683 | +0.1% |
| 10k x 8 early escape (96 B) | 19107 | 19316 | +1.1% |
| 10k x 8 late escape (96 B) | 4138 | 4004 | -3.2% |
| 10k x 8 early escape (256 B) | 47083 | 46637 | -0.9% |
| 10k x 8 late escape (256 B) | 6879 | 6481 | -5.8% |
| 10k x 8 control (24 B) | 5736 | 5814 | +1.4% |
| 10k x 8 mixed | 5109 | 4953 | -3.1% |
| 1k x 2 short ASCII (16 B) | 96 | 106 | +10.4% |

The 1 microsecond narrow-lane movement is below this harness's useful
resolution. The 64-byte result also never enters the candidate and disagrees
with the first pair, so it is treated as drift rather than runtime fallout.

## Verdict

The mechanism is real above the boundary: 1 KiB safe ASCII improves
33.6-34.1% and the CJK lane improves 25.2-25.5%. The 256-byte decision row,
however, improves 17.7% and then only 12.6%. It does not reproduce the
predeclared 15% floor.

Escaped guards were made safe only after moving the cutoff to 256 bytes and
continuing with the scalar byte loop from the first unsafe vector. An earlier
speculative-copy-and-rollback variant regressed late-escape 96-byte text by
15-26%. The final variant removes that categorical regression, but the
remaining 256-byte signal is too borderline for an ISA-specific encoder and
new native dispatch surface.

**Rejected.** The exact prototype is preserved at `archive/exp-230`; runtime
code is reverted. The long safe/escaped lanes and exact `dart:convert` boundary
oracle remain as reusable measurement infrastructure.

## Correctness and code-generation checks

- `dart test test/native_encoder_diff_test.dart` — 5/5 tests pass on the
  prototype, including randomized mixed-type JSON round-trips and exact long
  string output across vector boundaries, quote/backslash/control positions,
  and multibyte UTF-8.
- AArch64 disassembly confirms the vector loop contains 16-byte load/store,
  byte comparisons, and `umaxv`; the canonical scalar encoder is unchanged on
  the publication branch.
- The prototype used only documented A64 Advanced SIMD intrinsics from the
  [Arm ACLE reference](https://arm-software.github.io/acle/neon_intrinsics/advsimd.html).
