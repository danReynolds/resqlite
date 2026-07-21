# Experiment 237: batch blob parameter transfer via TransferableTypedData

- **Date:** 2026-07-21
- **Environment:** Apple M1 Pro, macOS 26.2, Dart 3.12.2 (`macos_arm64`)
- **Baseline:** `0af824f` (`origin/main`)
- **Candidate:** this branch (`exp-237-batch-blob-transfer`), prototype since
  reverted — runtime code archived at `archive/exp-237`
- **Harness:**
  [`benchmark/experiments/blob_batch_write_ab.dart`](../experiments/blob_batch_write_ab.dart)
  — end-to-end blob-heavy `executeBatch` (30 rows/batch, one blob param each),
  feature toggled at runtime (`blobParamTransferThreshold` = 256 KB candidate,
  raised above every payload for baseline), interleaved + order-flipped passes.
- **Decision:** Rejected — reproduced regression, no size shows a win.

Δ is candidate − baseline; **positive = candidate slower**. Sub-threshold
64/128 KB sizes are same-code-path controls (candidate leaves them on the
direct path), so their deltas measure only run-to-run noise.

## Run 1 (full)

| Size | Pass | Baseline µs/row | Candidate µs/row | Δ |
|---|---|---:|---:|---:|
| 64 KB | P1 base→cand | 148.9 | 145.6 | −2.2% |
| 64 KB | P2 cand→base | 143.8 | 84.2 | −41.4% |
| 128 KB | P1 base→cand | 277.6 | 307.5 | +10.8% |
| 128 KB | P2 cand→base | 289.4 | 269.5 | −6.9% |
| 256 KB | P1 base→cand | 565.4 | 658.3 | +16.4% |
| 256 KB | P2 cand→base | 555.0 | 655.5 | +18.1% |
| 512 KB | P1 base→cand | 1224.4 | 1298.8 | +6.1% |
| 512 KB | P2 cand→base | 1267.4 | 1376.2 | +8.6% |
| 1 MB | P1 base→cand | 2450.2 | 2518.6 | +2.8% |
| 1 MB | P2 cand→base | 2422.8 | 2537.1 | +4.7% |

## Run 2 (full)

| Size | Pass | Baseline µs/row | Candidate µs/row | Δ |
|---|---|---:|---:|---:|
| 64 KB | P1 base→cand | 95.5 | 202.8 | +112.4% |
| 64 KB | P2 cand→base | 180.1 | 127.5 | −29.2% |
| 128 KB | P1 base→cand | 327.0 | 327.3 | +0.1% |
| 128 KB | P2 cand→base | 327.8 | 314.4 | −4.1% |
| 256 KB | P1 base→cand | 612.0 | 658.7 | +7.6% |
| 256 KB | P2 cand→base | 605.5 | 658.2 | +8.7% |
| 512 KB | P1 base→cand | 1202.6 | 1398.7 | +16.3% |
| 512 KB | P2 cand→base | 1215.6 | 1315.1 | +8.2% |
| 1 MB | P1 base→cand | 2435.1 | 2567.6 | +5.4% |
| 1 MB | P2 cand→base | 2468.3 | 2542.5 | +3.0% |

## Runs 3–4 (wrapped sizes)

| Size | Run/Pass | Baseline µs/row | Candidate µs/row | Δ |
|---|---|---:|---:|---:|
| 256 KB | R3 P1 | 626.6 | 677.4 | +8.1% |
| 256 KB | R3 P2 | 659.3 | 710.7 | +7.8% |
| 512 KB | R3 P1 | 1301.5 | 1895.9 | +45.7% |
| 512 KB | R3 P2 | 1283.7 | 1337.5 | +4.2% |
| 1 MB | R3 P1 | 2568.6 | 2637.4 | +2.7% |
| 1 MB | R3 P2 | 2611.4 | 2776.4 | +6.3% |
| 256 KB | R4 P1 | 606.1 | 687.4 | +13.4% |
| 256 KB | R4 P2 | 642.5 | 708.3 | +10.2% |
| 512 KB | R4 P1 | 1239.1 | 1279.2 | +3.2% |
| 512 KB | R4 P2 | 1467.6 | 1340.6 | −8.7% |
| 1 MB | R4 P1 | 3003.7 | 3257.5 | +8.4% |
| 1 MB | R4 P2 | 2685.8 | 3549.6 | +32.2% |

## Summary

- **256 KB: 8/8 legs candidate-slower**, +7.6% to +18.1% (median ≈ +9.5%),
  reproduced same-direction across every order flip — the load-bearing
  rejection signal, at the exact size where single-row INSERT (exp 234) won
  −16% to −23%.
- 512 KB: 7/8 legs slower, noisier.
- 1 MB: uniformly slightly slower, WAL-dominated.
- No payload size shows a win. The exp 234 mechanism inverts because
  `executeBatch` collapses N writes into one writer round-trip, removing the
  per-round-trip scavenge-vs-writer-mid-step churn the wrap reclaims — leaving
  only the 30× `fromList`/`materialize` wrap tax.
