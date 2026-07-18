# Experiment 234: zero-copy blob parameter transfer via TransferableTypedData

- **Date:** 2026-07-18
- **Environment:** Apple M1 Pro, macOS 26.2, Dart 3.12.2 (`macos_arm64`)
- **Baseline:** `90924b6793ecff741639e4820a00fc5ecf4a4b9f` (`origin/main`)
- **Candidate:** this branch (`exp-234-blob-param-transfer`)
- **Harnesses:**
  - [`benchmark/experiments/blob_param_write_ab.dart`](../experiments/blob_param_write_ab.dart)
    — end-to-end single-row large-BLOB INSERT, feature toggled at runtime,
    interleaved order-flipped passes.
  - [`benchmark/experiments/blob_param_transport_ab.dart`](../experiments/blob_param_transport_ab.dart)
    — isolated main→writer transport A/B (`SendPort` copy vs
    `TransferableTypedData`), plus isolated `fromList` cost.
- **Decision:** Accepted (in review)

The A/B is toggled in one process (`blobParamTransferThreshold` = 256 KB for
the candidate, raised above every payload for the baseline) and sampled
interleaved + order-flipped, so machine drift indicts both lanes equally
(exp 159 / exp 177 discipline). Sub-threshold sizes (64 KB, 128 KB) are
**same-code-path controls**: the candidate leaves them on the direct path, so
their deltas measure only run-to-run noise.

## Transport microbenchmark (mechanism isolation)

Median µs per main→writer→reply round-trip; worker touches every byte.

| Size | `send([blob])` | `TransferableTypedData` | Δ | `fromList` µs |
|---|---:|---:|---:|---:|
| 4 KB | 15.21 | 13.53 | −11.0% | 0.35 |
| 64 KB | 56.59 | 69.45 | **+22.7%** | 3.08 |
| 256 KB | 316.54 | 245.07 | **−22.6%** | 9.21 |
| 1 MB | 1141.43 | 1001.77 | −12.2% | 37.59 |
| 4 MB | 3939.84 | 4143.63 | +5.2% | 144.07 |

Reads: `TransferableTypedData.fromList` does a plain memcpy into external
memory (cheap — 9 µs for 256 KB, vs the 316 µs round-trip) and does **not**
neuter its source list. The transferable hop beats the VM serializer's
per-object deep copy for raw bytes at 256 KB (−22.6%), but at 64 KB the wrap
overhead makes it **slower** (+22.7%) and at 4 MB `fromList`'s own copy
catches up to the saving (neutral). This is the inverse of exp 005: there was
no structure to encode here, so a straight byte transfer wins where a Dart
*codec* over structured maps lost. The 64 KB regression is exactly why the
production threshold is 256 KB.

## End-to-end single-row BLOB INSERT (representative clean pass)

Median µs/INSERT, 60 INSERTs/sample, 11 samples, two order-flipped passes.

| Size | Pass | Baseline µs | Candidate µs | Δ |
|---|---|---:|---:|---:|
| 64 KB (control) | P1 base→cand | 204.6 | 213.2 | +4.2% |
| 64 KB (control) | P2 cand→base | 193.6 | 200.0 | +3.3% |
| 128 KB (control) | P1 base→cand | 377.7 | 366.9 | −2.9% |
| 128 KB (control) | P2 cand→base | 324.1 | 337.4 | +4.1% |
| **256 KB** | P1 base→cand | 795.5 | 664.9 | **−16.4%** |
| **256 KB** | P2 cand→base | 907.7 | 701.5 | **−22.7%** |
| **512 KB** | P1 base→cand | 1519.4 | 1361.0 | **−10.4%** |
| **512 KB** | P2 cand→base | 1632.1 | 1439.1 | **−11.8%** |
| 1 MB | P1 base→cand | 3227.0 | 3254.0 | +0.8% |
| 1 MB | P2 cand→base | 3329.3 | 3197.7 | −4.0% |

## Reproduction across all recorded passes

Signed deltas per (size, order-flipped leg). The discriminator (exp 177) is
same-direction reproduction across the order flip, not raw magnitude.

- **256 KB (wrapped):** every leg candidate-faster across ~7 passes:
  (−45.9, −42.0), (−31.6, −17.8), (−11.8, −13.0), (−43.2, −1.4),
  (−12.4, −9.7), (−31.1, −20.6), (−26.0, −14.1), (−16.4, −22.7).
  12+/12 negative → real. Conservative read ~ −15% to −20%.
- **512 KB (wrapped):** (−13.1, −14.1), (−18.7, −24.3), (−11.8, −20.6),
  (−10.4, −11.8). 8/8 negative → real. ~ −12% to −18%.
- **1 MB (wrapped):** mixed sign across passes → **neutral**; the WAL write of
  a 1 MB blob plus `fromList`'s own growing copy dilute the transfer saving.
- **64 KB / 128 KB (control, direct path):** deltas flip sign across the order
  flip (e.g. 64 KB: +11/+4, −14/+8, −17/+2, +4/+3) — the drift signature,
  confirming ~±8–15% noise on this (contended) box and that the wins above
  clear the floor by reproducing same-direction.

## Interpretation

For 256 KB–512 KB single-row blob INSERTs the main→writer transfer copy is a
material fraction of the write, and replacing the VM serializer's deep copy
with a `TransferableTypedData` move is a **~15–20% end-to-end** speedup,
reproduced same-direction across every order-flipped pass. Below 256 KB the
wrap does not pay back (kept on the direct path); at ≥ 1 MB the SQLite WAL
write dominates and the effect washes out to neutral. No change for non-blob
or sub-threshold writes — `wrapBlobParams` returns the input list unchanged
(no allocation) when nothing qualifies.
