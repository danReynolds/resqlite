# Experiment 216: Base64 loop unroll for selectBytes BLOBs

**Date:** 2026-07-05
**Status:** Accepted
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused
  [`benchmark/experiments/select_bytes_blob_base64.dart`](../benchmark/experiments/select_bytes_blob_base64.dart);
  raw pass tables in
  [`benchmark/results/2026-07-05T10-07-55Z-exp216-base64-loop-unroll.md`](../benchmark/results/2026-07-05T10-07-55Z-exp216-base64-loop-unroll.md).

## Problem

`selectBytes()` serializes SQLite BLOB cells as base64 strings in
[`json_write_base64`](../native/resqlite.c). The helper already writes into the
connection's persistent `json_buf`; there is no intermediate allocation or Dart
copy inside the base64 path itself. After [exp 199](199-row-level-buf-ensure.md)
and [exp 203](203-cell-value-cache.md), the remaining BLOB-specific encoder
work is mostly the scalar base64 payload loop:

```c
for (; i + 2 < len; i += 3) {
    unsigned int v = ((unsigned int)data[i] << 16) |
                     ((unsigned int)data[i + 1] << 8) |
                      (unsigned int)data[i + 2];
    *out++ = b64_table[(v >> 18) & 0x3F];
    *out++ = b64_table[(v >> 12) & 0x3F];
    *out++ = b64_table[(v >> 6)  & 0x3F];
    *out++ = b64_table[ v        & 0x3F];
}
```

[Exp 201](201-base64-quote-reservation.md) already tried the smaller framing
cleanup around this loop and rejected it: reserving quote + payload + quote once
did not move the many-tiny-BLOB lanes that should have carried a per-cell
framing win. That experiment's future note was specific: further BLOB
`selectBytes()` work should target the base64 loop, transport/copy shape, or a
measured allocation boundary rather than the quote writes.

The base64 loop is the next bounded mechanism. It should matter more as the BLOB
payload gets larger, because each 3-byte group pays the same loop-control branch
and index arithmetic.

## Hypothesis

Unrolling `json_write_base64` so each loop trip encodes four 3-byte groups
should reduce loop-control overhead without changing the base64 alphabet,
padding, JSON framing, or output bytes.

Prediction:

- Medium and large BLOB lanes should reproduce candidate-faster across an
  order-flipped pair, with the strongest effect on 4KB cells.
- Tiny 3B BLOB lanes may stay neutral because each cell has only one triplet and
  never reaches the unrolled loop.
- Mixed rows should stay neutral or slightly faster; non-BLOB cell paths are
  unchanged.

Reject if medium/large BLOB lanes do not reproduce same-direction wins, or if
tiny/mixed guards show a reproduced regression large enough to erase the
payload-loop benefit.

## Approach

Change only [`native/resqlite.c`](../native/resqlite.c). Replace the scalar
one-triplet loop with:

- a macro-local `RESQLITE_WRITE_B64_TRIPLET(idx)` that emits the same four table
  lookups for one 3-byte group,
- a first loop that emits four triplets per iteration (`12 input bytes -> 16
  output bytes`),
- the original scalar loop for remaining complete triplets,
- the existing 1- or 2-byte tail handling with `=` padding.

The opening and closing JSON quotes stay where they are. `encoded_len` is
unchanged. The output is byte-identical for every length; the implementation
only changes loop shape.

## Results

Focused harness:
`dart run benchmark/experiments/select_bytes_blob_base64.dart`. Values are
median microseconds per `selectBytes()` query.

| Lane | Baseline P1 | Candidate P1 | Delta P1 | Candidate P2 | Baseline P2 | Delta P2 | Baseline P3 | Candidate P3 | Delta P3 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10k rows x 8 tiny blobs (3B) | 2345 | 2209 | -5.8% | 2223 | 2190 | +1.5% | 2216 | 2230 | +0.6% |
| 10k rows x 20 tiny blobs (3B) | 5239 | 4992 | -4.7% | 5177 | 5199 | -0.4% | 5341 | 5542 | +3.8% |
| 10k rows x 8 small blobs (16B) | 2873 | 2703 | -5.9% | 2798 | 3004 | -6.9% | 4211 | 2762 | -34.4%* |
| 10k rows x 4 medium blobs (128B) | 3751 | 3711 | -1.1% | 3765 | 4153 | -9.3% | 3973 | 3785 | -4.7% |
| 1k rows x 2 large blobs (4KB) | 4849 | 4191 | -13.6% | 4170 | 4786 | -12.9% | 4918 | 4332 | -11.9% |
| 10k rows x 8 mixed (4 blob + 2 int + 2 text) | 2619 | 2565 | -2.1% | 2557 | 2654 | -3.7% | 2806 | 2663 | -5.1% |

*Pair 3's small-BLOB baseline is a slow outlier and is not load-bearing.

The 4KB large-BLOB lane is the cleanest signal: candidate medians stay in a
tight 4170-4332 us/query band while baseline stays 4786-4918 us/query, giving a
reproduced 11.9-13.6% win. Medium BLOBs also stay candidate-faster across all
passes, though the baseline drifts enough that the effect band is wider. The
16B small-BLOB lane is candidate-faster in the primary order-flipped pair.

The 3B tiny-BLOB lanes are guardrails, not the main mechanism: each cell has
only one complete triplet, so most cells never use the four-triplet loop. Those
lanes are neutral/noisy rather than reproduced regressions. The mixed row stays
candidate-faster across all passes.

Focused correctness:

```bash
dart test test/database_test.dart --name "selectBytes encodes blobs as base64"
```

The test passed against the candidate.

## Decision

**Accepted.** Keep the loop unroll.

This is a narrow native encoder win: no public API change, no new allocation, no
format change, and no extra runtime state. It is specifically useful for BLOB
`selectBytes()` payloads at and above small/medium cell sizes, with the strongest
measured effect on the 4KB lane. It does not reopen exp 201's quote/framing
candidate; tiny one-triplet cells remain at the noise floor, which is exactly
what a payload-loop optimization predicts.

Future BLOB encoder work should use `select_bytes_blob_base64.dart` and treat
the 4KB lane as the throughput gate, with tiny 3B lanes as regression guards.
Another BLOB attempt should target a larger algorithmic or copy boundary, not
only per-cell framing.

## Test plan

- [x] `dart pub get`
- [x] `dart test test/database_test.dart --name "selectBytes encodes blobs as base64"`
- [x] Focused order-flipped A/B with
      `benchmark/experiments/select_bytes_blob_base64.dart` (three passes; see
      Results)
