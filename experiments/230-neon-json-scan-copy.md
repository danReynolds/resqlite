# Experiment 230: Reject AArch64 NEON JSON safe-prefix scan + copy

**Date:** 2026-07-15
**Status:** Rejected
**Category:** Moonshot
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused
  [`benchmark/experiments/select_bytes_text_string_reserve.dart`](../benchmark/experiments/select_bytes_text_string_reserve.dart);
  two final order-flipped paired passes plus prototype-development rounds are
  recorded in
  [`benchmark/results/2026-07-15T10-41-42Z-exp230-neon-json-scan-copy.md`](../benchmark/results/2026-07-15T10-41-42Z-exp230-neon-json-scan-copy.md).
  No release-suite run because no release lane isolates long safe TEXT JSON
  encoding wall time; the focused harness is the durable gate established by
  exp 202 / 219.
**Archive:** [`archive/exp-230`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-230)

## Problem

`json_write_string` scans safe TEXT with the portable 8-byte SWAR loop from
[exp 043](043-swar-escape-lookup-table.md), then copies the complete safe span
through `buf_write`. [Exp 202](202-text-json-string-reserve.md)
showed that reservation alone does not matter; [exp 219](219-json-control-escape.md)
won by removing `snprintf` only for control escapes. [Exp 229](229-simd-base64-neon.md)
then introduced the codebase's first AArch64/NEON kernel and named SIMD JSON
escape scan as the next TEXT-side mechanism.

Safe long strings still pay two traversals: classify, then copy. The plausible
moonshot was to fuse them, storing each vector only after proving it contains
no control byte, quote, or backslash.

## Hypothesis

**Assumption challenged:** safe JSON TEXT needs a portable scan followed by a
separate copy. AArch64 NEON can classify and copy 16 bytes per iteration,
turning two scalar/SWAR traversals into one vector traversal without changing
the public API or output bytes.

Accept only if 256-byte and 1 KiB safe ASCII both reproduce at least 15%
candidate-faster across an order flip, with the CJK lane in the same direction.
Short, mixed, control, and unsafe-at-start/end lanes must remain inside the 3%
effect floor. Reject a win confined to 1 KiB or a 256-byte result that misses
the gate in either ordering.

## Approach

The archived final prototype used an AArch64-only long-TEXT path:

- A compile-time `defined(__aarch64__) && defined(__ARM_NEON)` gate retained
  the scalar encoder on every other target.
- The 16-byte loop used `vcltq_u8` for bytes below space, `vceqq_u8` for quote
  and backslash, `vmaxvq_u8` to reduce the escape mask, and `vst1q_u8` to copy
  a proven-safe vector. These are documented A64 Advanced SIMD intrinsics in
  the [Arm ACLE reference](https://arm-software.github.io/acle/neon_intrinsics/advsimd.html).
- Dispatch happened at the TEXT call site only for `len >= 256`; column-name
  encoding and shorter values retained the canonical scalar function.
- On the first unsafe vector, an out-of-line scalar tail resumed at that vector
  and remained scalar. The prototype did not restart SIMD after escapes, so it
  did not revive the wider post-escape scan shape from closed exp 221 / PR 236.
- A new exact-output oracle compares `selectBytes` bytes against
  `dart:convert` around 16/32/48/64/80/96/128/256/1024-byte boundaries, with
  escapes at vector edges and multibyte UTF-8.

The focused harness now includes safe 64 B, 96 B, 256 B, 1 KiB, and CJK lanes,
plus early- and late-escape guards at 96 B and 256 B.

## Results

Decision rows from the two final order-flipped pairs:

| Lane | Pair 1 | Pair 2 | Read |
| --- | ---: | ---: | --- |
| safe ASCII 256 B | **-17.7%** | **-12.6%** | second pass misses 15% gate |
| safe ASCII 1 KiB | **-33.6%** | **-34.1%** | large-span mechanism reproduced |
| CJK 1K code units | **-25.2%** | **-25.5%** | high UTF-8 bytes remain safe |
| early escape 256 B | +2.7% | -0.9% | neutral/mixed |
| late escape 256 B | -16.0% | -5.8% | no rollback penalty |
| early escape 96 B | -0.3% | +1.1% | scalar cutoff, neutral |
| late escape 96 B | -1.3% | -3.2% | scalar cutoff, neutral-to-faster |
| escaped text 24 B | +2.8% | +0.1% | inside effect floor |
| control text 24 B | -0.3% | +1.4% | inside effect floor |

The full raw tables document short-lane drift as well. One candidate-first
pass put the unchanged 20-column short lane at +26.1%; the order flip collapsed
it to +1.4%. A one-microsecond narrow-lane movement similarly reports as 10.4%.
Neither is treated as code-path evidence because values below 256 bytes never
enter the prototype.

### Prototype development findings

The bounded iterations were informative even though the final result failed:

1. Putting NEON state into the scalar function changed its register allocation
   and regressed short escaped text, repeating exp 229's code-generation lesson.
2. A clean out-of-line SIMD attempt that rolled back on an unsafe vector kept
   scalar assembly byte-identical, but late-escape 96-byte text regressed
   15-26% because it paid almost a full speculative pass and then the full
   scalar pass.
3. Continuing scalar from the first unsafe vector removed that double pass.
   Moving dispatch to the TEXT caller with a 256-byte cutoff made unsafe guards
   neutral, while splitting the escaped tail out of the all-safe kernel reduced
   the safe fast path's register frame.
4. Even after those refinements, the load-bearing 256-byte win did not reproduce
   above the preset floor.

## Decision

**Rejected.** Keep the portable SWAR scan + copy encoder.

The 1 KiB result proves fused vector classification-and-copy is a real
mechanism, but it is not enough to ship a new ISA-specific TEXT encoder when
the 256-byte break-even row is 17.7% in one ordering and 12.6% in the other.
The exact runtime prototype is preserved at `archive/exp-230` and removed from
the publication branch.

The harness and boundary oracle remain. Reopen only if a production/AOT profile
shows escape-free TEXT at 1 KiB or larger materially dominates result transfer,
or a different mechanism removes the per-cell dispatch/setup floor at 256
bytes. Do not retry another threshold or speculative rollback variant.

## Validation

- `dart test test/native_encoder_diff_test.dart` — 5/5 pass on the prototype
  and after runtime revert.
- two final order-flipped focused A/B pairs, with development pairs used to
  isolate scalar code-generation and unsafe-tail costs.
- AArch64 disassembly inspected for vector classification/store instructions
  and scalar-path isolation.
- `dart run benchmark/finalize_experiment.dart --experiment=experiments/230-neon-json-scan-copy.md`.
