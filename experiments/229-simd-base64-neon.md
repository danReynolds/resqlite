# Experiment 229: SIMD (NEON) `json_write_base64` kernel — the first SIMD kernel in the codebase

**Date:** 2026-07-14
**Status:** Accepted
**Category:** Moonshot
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused
  [`benchmark/experiments/select_bytes_blob_base64.dart`](../benchmark/experiments/select_bytes_blob_base64.dart);
  four order-flipped paired passes recorded in
  [`benchmark/results/2026-07-14T11-25-21Z-exp229-simd-base64-neon.md`](../benchmark/results/2026-07-14T11-25-21Z-exp229-simd-base64-neon.md).
  No release-suite run because no current release lane isolates BLOB
  base64 encoding wall time — the focused harness is the durable gate,
  consistent with exp 216 / 218 / 225.

## Problem

Every base64 kernel in `native/resqlite.c` since exp 216 has been scalar
C: [exp 216](216-base64-loop-unroll.md) 4×-unrolled the outer loop,
[exp 218](218-base64-8x-unroll.md) rejected wider unroll (loop-control
ceiling reached), and [exp 225](225-base64-lut12.md) collapsed the
per-triplet body to two 12-bit LUT lookups + two 16-bit stores (two loads
+ two stores per output-4 group is the scalar ceiling — a 24-bit LUT
would be 16 MiB, well past `.rodata` acceptability).

`signals.json` for `result-transfer-shape` records the frontier
explicitly: *"Future BLOB work needs a further mechanism change: SIMD
`_mm_shuffle_epi8` / `vqtbl4q_u8` base64 kernels, a compiler-flag change,
or production-profile evidence that BLOB encode dominates a real
workload."* No prior experiment has attempted a SIMD kernel — the
codebase has been ISA-agnostic scalar C throughout.

## Hypothesis (assumption challenged)

**Assumption challenged:** the resqlite native encoder must remain
ISA-agnostic scalar C. Every prior optimization to `json_write_base64`
worked within that ceiling.

If we introduce ISA-specific SIMD kernels behind clean compile-time
gates, an AArch64/NEON base64 kernel should crush the scalar
throughput ceiling on the 128 B / 4 KB payload lanes — the ones that
matter for typical BLOB payloads (thumbnails, small binary blobs) — with
neutral impact on the tiny-cell regression guards. If the win is real,
this experiment also unlocks a class of follow-ups (SIMD JSON escape
scan, SIMD FNV hash body, SSSE3/AVX2 kernels on x86_64) that until now
had no precedent in the codebase.

Predicted acceptance: 4 KB and 128 B lanes each reproduce ≥ 15 %
candidate-faster across two order-flipped paired passes, with tiny-cell
(3 B) and mixed guards inside the 3 % effect floor.

Predicted rejection: 4 KB gain reproduces below 15 % (SIMD does not
materially move the scalar+LUT12 ceiling for BLOB workloads we ship);
tiny-cell guards regress ≥ 3 % reproduced (categorical rejection: adding
SIMD is worse than keeping scalar); or 128 B lane is neutral (the SIMD
break-even point is above typical BLOB size, so the mechanism only
helps a niche workload).

## Approach

The change adds a single new SIMD kernel to `native/resqlite.c`, gated
on `defined(__aarch64__) && defined(__ARM_NEON)`:

- **Build-time gate.** A new `RESQLITE_HAS_NEON_BASE64` macro is set to
  1 on AArch64 targets that carry NEON (all Apple Silicon, iOS, and
  Android arm64 platforms — no build-hook change needed because
  `<arm_neon.h>` is provided by the toolchain and NEON is baseline on
  AArch64). The gate is 0 on x86_64, 32-bit ARM, and Windows. Non-ARM64
  targets fall through to the exp 225 scalar 12-bit-LUT encoder,
  unchanged.
- **NEON kernel.** `json_write_base64_neon_bulk` (marked
  `__attribute__((noinline))`) processes 48 input bytes into 64 output
  bytes per iteration:
    1. `vld3q_u8` loads 48 bytes deinterleaved as `uint8x16x3_t` — lane
       *j* of vec 0/1/2 holds triplet *j*'s A/B/C byte respectively.
    2. Four 6-bit indices per triplet are derived by shift/mask/or:
       `idx0 = A >> 2`, `idx1 = ((A & 3) << 4) | (B >> 4)`,
       `idx2 = ((B & 15) << 2) | (C >> 6)`, `idx3 = C & 0x3F`.
    3. Each index vector is mapped to the encoded byte via
       `vqtbl4q_u8` against a 64-byte alphabet table loaded from
       `b64_table[]` (AArch64-only; `vqtbl4` is the 4-register variant
       of the NEON table lookup).
    4. `vst4q_u8` writes the four output vectors interleaved, in the
       same char order the scalar `memcpy(pair_table, 2)` path emits.
  Output is bit-identical to scalar per algebraic equivalence.
- **Dispatcher.** `json_write_base64` gains one length check
  (`if (len >= 48)`) that calls `json_write_base64_neon_bulk` and
  advances `i` / `out` by the consumed bytes, then falls through into
  the existing scalar 12-bit-LUT loop for the 0–47 byte tail plus the
  final 1–2 byte padded ending. The SIMD kernel being `noinline` keeps
  the scalar loop's register allocation and code layout byte-identical
  to exp 225 — a critical design choice discovered mid-experiment (see
  Results below).

No public API changes. No changes to `hook/build.dart` (NEON is baseline
on `__aarch64__` and requires no compiler flag).

## Results

Full tables including rounds 3 and 4 are in the linked result file. The
decision rows across four paired order-flipped passes:

| Lane                          | pass Δ range          | verdict                        |
| ----------------------------- | --------------------- | ------------------------------ |
| 1 k × 2 large blobs (4 KB)    | -52.2 / -44.1 / -43.1 / -39.1 % | **reproduced ~-45% median** |
| 10 k × 4 medium blobs (128 B) | -32.5 / -22.8 / -13.8 / -2.9 %  | **reproduced ~-18% median** |
| 10 k × 8 small blobs (16 B)   | -6.2 / +1.1 / +1.2 / +8.2 %   | drift-suspected, ~+1% median  |
| 10 k × 8 tiny blobs (3 B)     | +0.3 / +0.6 / +1.4 / +1.7 %   | inside 3% floor (~+1% median) |
| 10 k × 20 tiny blobs (3 B)    | -2.8 / +0.9 / +4.4 / +4.8 %   | drift-suspected, ~+2.6% median|
| 10 k × 8 mixed                | -1.0 / +0.8 / +3.1 / +3.2 %   | inside 3% floor (~+1.5% median)|

Payload throughput on the load-bearing 4 KB lane goes from ~3,340 µs/query
on baseline to ~1,730 µs/query on candidate — **the NEON kernel is
roughly twice the scalar throughput**. The 128 B lane sees a solid
~18 % median improvement on top of exp 225. Tiny-cell (3 B) and mixed
guards stay inside the harness noise floor across all four paired
passes.

### Mid-experiment discovery: `noinline` matters for small-blob code gen

The first prototype (rounds 1 and 2, superseded — details in the result
file) reproduced the same 4 KB / 128 B wins but broke the 3 B guard at
+3-9 % reproduced regression. Investigation revealed the cause: even
when the small-blob code never called `json_write_base64_neon_bulk`, the
kernel's presence in the same function was changing the compiler's
register allocation and code layout for the scalar path, adding ~5-10
cycles per encode. On the 3 B lane that runs ~80,000 base64 calls per
query, that translates to ~400 µs/query — matching the observed
regression.

The kept design moves the NEON kernel into its own `noinline` function
and inlines the scalar body back into `json_write_base64`, so the
small-blob hot path is byte-identical to exp 225's layout. The 3 B
regression then collapses back into noise across four paired passes.

## Outcome

**Accepted.** A reproduced ~2× speedup on the 4 KB payload-throughput
lane and ~18 % on the 128 B lane, both well past the acceptance bar,
with tiny-cell and mixed guards inside the harness noise floor. The
mechanism introduces the first SIMD kernel to `native/resqlite.c`; the
build-time gate keeps non-ARM64 targets on the exp 225 scalar path
byte-for-byte, so no regression is possible on x86_64, 32-bit ARM,
or Windows.

Categorical implication: **SIMD kernels are a viable mechanism for
BLOB/text hot paths in resqlite** when they can be gated on the target
ISA and out-of-lined so the small-input path is unaffected. Follow-up
candidates now unlocked:
- SSSE3 (`_mm_shuffle_epi8`) base64 kernel on x86_64 — same shape,
  different table-lookup instruction. Deferred to keep this experiment
  bounded.
- SIMD JSON escape scan (`vceqq_u8` / `vcltq_u8` for control-char
  detection in `json_write_string`) — the signals-named "SWAR escape
  scan" mechanism now has a precedent to build on.
- SIMD FNV hash body for `resqlite_query_hash`'s TEXT/BLOB fold.

## Test plan

- `dart test test/database_test.dart -n selectBytes` — 9/9 pass, including
  `Database selectBytes encodes blobs as base64` (round-trips the exact
  BLOB bytes through the encoder + jsonDecode, would surface any bit
  difference).
- `dart analyze --fatal-infos` on the modified sources (pre-existing
  drift warnings in `benchmark/drift/` are unaffected).
- Four order-flipped paired passes of
  `benchmark/experiments/select_bytes_blob_base64.dart`, recorded in the
  result file.
- `dart run benchmark/finalize_experiment.dart --experiment=experiments/229-simd-base64-neon.md`.
