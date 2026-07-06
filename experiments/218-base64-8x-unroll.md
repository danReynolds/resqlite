# Experiment 218: 8x base64 loop unroll for selectBytes BLOBs

**Date:** 2026-07-06
**Status:** Rejected
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused
  [`benchmark/experiments/select_bytes_blob_base64.dart`](../benchmark/experiments/select_bytes_blob_base64.dart);
  raw pass tables in
  [`benchmark/results/2026-07-06T13-17-08Z-exp218-base64-8x-unroll.md`](../benchmark/results/2026-07-06T13-17-08Z-exp218-base64-8x-unroll.md).
**Archive:** [`archive/exp-218`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-218)

## Problem

[Exp 216](216-base64-loop-unroll.md) proved that the native
[`json_write_base64`](../native/resqlite.c) payload loop is a real
`selectBytes()` BLOB hot path. Moving from one 3-byte group per loop trip to
four groups per trip kept output bytes identical and reproduced a 4KB BLOB win
across three passes.

That left one small follow-up question: did the four-triplet scalar unroll still
leave loop-control overhead, or had the bottleneck moved to table lookups,
stores, memory bandwidth, and the rest of the JSON result path?

[Exp 201](201-base64-quote-reservation.md) already rejected quote/framing
reservation around this helper. This run deliberately does not retry that
candidate; it tests only the payload-loop width after exp 216 changed the
baseline.

## Hypothesis

Widening the complete-triplet loop from four 3-byte groups per trip to eight
groups per trip should reduce loop-control work further on payload-heavy BLOB
cells while preserving the same base64 table, JSON quotes, encoded length, and
tail padding.

Prediction:

- The 4KB BLOB lane should reproduce candidate-faster across order-flipped
  passes if loop-control overhead remains material.
- The 128B lane may show a smaller same-direction win.
- Tiny 3B cells should stay neutral/noisy because they never enter either
  unrolled loop body.

Reject if the 4KB lane does not reproduce same-direction wins, or if the guard
lanes show a broader regression pattern.

## Approach

The archived prototype changes only [`native/resqlite.c`](../native/resqlite.c).
It keeps exp 216's local `RESQLITE_WRITE_B64_TRIPLET(idx)` macro and changes the
main complete-triplet loop from:

```c
for (; i <= len - 12; i += 12) {
    RESQLITE_WRITE_B64_TRIPLET(i);
    RESQLITE_WRITE_B64_TRIPLET(i + 3);
    RESQLITE_WRITE_B64_TRIPLET(i + 6);
    RESQLITE_WRITE_B64_TRIPLET(i + 9);
}
```

to eight triplets per iteration (`24 input bytes -> 32 output bytes`). The
existing scalar remainder loop still handles leftover complete triplets, and
the existing tail block still handles 1- or 2-byte padding.

The runtime prototype is archived at `archive/exp-218` and reverted from the
final branch. No runtime code is kept.

## Results

Focused harness:
`dart run benchmark/experiments/select_bytes_blob_base64.dart`. Values are
median microseconds per `selectBytes()` query.

| Lane | B1 | C1 | Delta 1 | C2 | B2 | Delta 2 | B3 | C3 | Delta 3 | C4 | B4 | Delta 4 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10k rows x 8 tiny blobs (3B) | 2345 | 2230 | -4.9% | 2221 | 2272 | -2.2% | 2245 | 2212 | -1.5% | 2347 | 2270 | +3.4% |
| 10k rows x 20 tiny blobs (3B) | 5380 | 5013 | -6.8% | 5025 | 5489 | -8.5% | 5212 | 5320 | +2.1% | 5464 | 5394 | +1.3% |
| 10k rows x 8 small blobs (16B) | 3102 | 2748 | -11.4% | 2814 | 2871 | -2.0% | 2926 | 2844 | -2.8% | 3099 | 3013 | +2.9% |
| 10k rows x 4 medium blobs (128B) | 4328 | 3722 | -14.0% | 3823 | 4058 | -5.8% | 4200 | 3956 | -5.8% | 3927 | 4067 | -3.4% |
| 1k rows x 2 large blobs (4KB) | 4622 | 4160 | -10.0% | 4223 | 4142 | +2.0% | 4821 | 4167 | -13.6% | 4560 | 4526 | +0.8% |
| 10k rows x 8 mixed (4 blob + 2 int + 2 text) | 2785 | 2620 | -5.9% | 2618 | 2568 | +1.9% | 2827 | 2613 | -7.6% | 2830 | 2814 | +0.6% |

The 128B medium-BLOB lane stayed candidate-faster in all four passes. That is a
real hint that wider unrolling can still remove some loop-control work on
mid-size cells.

The load-bearing 4KB lane did not reproduce. Two passes were clearly
candidate-faster (-10.0%, -13.6%), but the two order-flipped passes were
neutral/slower (+2.0%, +0.8%). The 8x candidate therefore does not add a stable
payload-throughput win over exp 216's 4x scalar baseline. Tiny and mixed guard
lanes also lost direction in the last pair.

Focused correctness:

```bash
dart test test/database_test.dart --name "selectBytes encodes blobs as base64"
```

The test passed against the candidate before the runtime change was reverted.

## Decision

Rejected. Do not widen `json_write_base64` from four triplets to eight.

Exp 216 remains the scalar portable baseline for BLOB `selectBytes()` payload
encoding. The 8x loop shape makes the C body larger but does not reproduce the
4KB throughput win required to justify carrying extra native hot-path code.
Future BLOB encoder work should target a larger mechanism: a different base64
algorithm, a copy/transport boundary, platform/compiler-specific evidence, or a
production profile that points at a new BLOB-specific cost.

## Test plan

- [x] `dart pub get`
- [x] `dart test test/database_test.dart --name "selectBytes encodes blobs as base64"`
- [x] Focused order-flipped A/B with
      `benchmark/experiments/select_bytes_blob_base64.dart` (four pairs; see
      Results)
