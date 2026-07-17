# Exp 228 — canonical stream hash after result growth

Focused A/B on an Apple M1 Pro with Dart 3.12.2. The baseline is commit
`74e005c` (the exp 228 harness and regressions on runtime base `10fbeb4`); the
candidate is `62b9e8a`. Each invocation creates a fresh database per round,
seeds 5,000 rows with a 64-byte TEXT cell, appends 100 rows, then calls the
public reader-worker `selectIfChanged` path for the growth and immediate
unchanged checks. Each pass uses two warmups and nine measured rounds.

## Correctness signal

| Pass | Collection order | Baseline redundant decodes | Candidate redundant decodes |
|---|---|---:|---:|
| 1 | baseline → candidate | 9 / 9 | 0 / 9 |
| 2 | baseline → candidate | 9 / 9 | 0 / 9 |
| 3 | candidate → baseline | 9 / 9 | 0 / 9 |

The baseline's first growth call returns a prefix-only hash. The immediate
identical rerun computes the complete hash, mismatches that cached prefix, and
decodes all 5,100 rows. The candidate's growth call returns the complete hash,
so the immediate rerun returns the unchanged sentinel without decoding.

## Pass 1 — baseline then candidate

| Lane | Baseline p50 | Baseline p90 | Candidate p50 | Candidate p90 | p50 delta |
|---|---:|---:|---:|---:|---:|
| growth | 0.986 ms | 1.295 ms | 1.127 ms | 1.386 ms | +14.3% |
| immediate unchanged | 0.877 ms | 1.412 ms | 0.389 ms | 0.514 ms | -55.6% |
| combined cycle | 1.863 ms | 2.506 ms | 1.505 ms | 1.900 ms | -19.2% |

## Pass 2 — baseline then candidate

| Lane | Baseline p50 | Baseline p90 | Candidate p50 | Candidate p90 | p50 delta |
|---|---:|---:|---:|---:|---:|
| growth | 0.948 ms | 1.163 ms | 0.995 ms | 1.094 ms | +5.0% |
| immediate unchanged | 0.860 ms | 1.190 ms | 0.366 ms | 0.401 ms | -57.4% |
| combined cycle | 1.812 ms | 2.121 ms | 1.370 ms | 1.460 ms | -24.4% |

## Pass 3 — candidate then baseline

| Lane | Baseline p50 | Baseline p90 | Candidate p50 | Candidate p90 | p50 delta |
|---|---:|---:|---:|---:|---:|
| growth | 1.211 ms | 1.844 ms | 0.982 ms | 1.096 ms | -18.9% |
| immediate unchanged | 0.982 ms | 2.626 ms | 0.356 ms | 0.383 ms | -63.7% |
| combined cycle | 2.146 ms | 4.470 ms | 1.365 ms | 1.476 ms | -36.4% |

The growth-only leg moves with collection order and remains near the harness's
millisecond noise floor. The load-bearing signals reproduce: the baseline
always decodes once too often, the candidate never does, and the combined
sequence is 19–36% faster across all three passes.

## Regression tests

- Baseline `query_decoder_test`: failed because the immediate same-result call
  returned `RawQueryResult` instead of `null`.
- Baseline public stream test: failed with an identical third emission after a
  no-op update.
- Candidate `dart test test/query_decoder_test.dart test/stream_test.dart`:
  31/31 pass.
