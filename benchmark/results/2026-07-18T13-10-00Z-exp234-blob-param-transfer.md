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
neuter its source list. The transferable hop beats the direct `SendPort.send`
route for raw bytes at 256 KB (−22.6%), but at 64 KB the wrap overhead makes
it **slower** (+22.7%) and at 4 MB `fromList`'s own copy catches up to the
saving (neutral). There was no structure to encode here, so exp 005's
codec-vs-VM verdict does not apply. The 64 KB regression is exactly why the
production threshold is 256 KB. (Mechanism attribution for *why* the direct
route costs more — same copy count, different destination — is in the
addendum below.)

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

For 256 KB–512 KB single-row blob INSERTs the main→writer hop cost is a
material fraction of the write, and the `TransferableTypedData` route is a
**~15–20% end-to-end** speedup, reproduced same-direction across every
order-flipped pass. Below 256 KB the wrap does not pay back (kept on the
direct path); at ≥ 1 MB the SQLite WAL write dominates and the effect washes
out to neutral. No change for non-blob or sub-threshold writes —
`wrapBlobParams` returns the input list unchanged (no allocation) when
nothing qualifies.

## Addendum: mechanism attribution (2026-07-20)

A post-acceptance deep-dive with
[`blob_param_mechanism_proof.dart`](../experiments/blob_param_mechanism_proof.dart)
(per-call costs; no resqlite imports) and
[`blob_param_gc_split.dart`](../experiments/blob_param_gc_split.dart)
(real INSERT path, one lane per process under `--verbose_gc`) corrected the
original "avoids the serializer deep copy" framing. Since Dart 2.15,
same-group sends use a single object-graph copy on the sender
(`runtime/vm/object_graph_copy.cc`); **both routes copy the payload exactly
once, on the main isolate**. The win is the copy's destination.

Per-call costs, median µs, two runs (synchronous wall of each single call;
worker-side columns reported back):

| Size | heapCopy | fromList | send(blob) | send(ttd) | materialize | setRange(direct) | setRange(ttd) |
|---|---:|---:|---:|---:|---:|---:|---:|
| 64 KB | 6.9–7.0 | 5.7–6.3 | 1.8–2.8 | 0.6–0.7 | 0.5–0.7 | 2.6 | 2.2 |
| 256 KB | 28.6–29.2 | 23.0–23.7 | 30.1–33.4 | 0.7–0.8 | 0.5–0.8 | 7.0 | 6.3 |
| 1 MB | 102–113 | 100–112 | 188–206 | 16–26 | 0.9–1.3 | 30.4 | 21.2 |
| 4 MB | 461–558 | 445–476 | 599–810 | 20–27 | 1.0–1.2 | 127.5 | 80.9 |

- `send(blob)` scales linearly → the copy runs inside the synchronous call,
  on the sender. At 256 KB it is ~15% over a plain copy (fast path: one
  new-space alloc + unchunked memmove); at ≥ 1 MB it is ~2× a plain memcpy
  (fast-path allocation fails → abort → `CopyTypedDataBaseWithSafepointChecks`
  redoes the copy in 100 KB safepoint-polled chunks).
- `send(ttd)` is near-constant at every size → ownership move, not a copy.
- `materialize()` is ~1 µs flat from 64 KB to 4 MB → a view, not a copy.
- `setRange` (the writer's real arena-consumption path) is equal-or-faster
  from the materialized view → no cost shifted to the writer.

Real-path GC attribution (300 × 256 KB INSERTs, isolated processes,
A/B-matched DELETE cadence): direct lane **29 app-isolate GCs / 8.6 ms
pause**; wrapped lane **20 GCs / 1.2–1.7 ms**. The asymmetry is per-GC cost,
not count — direct-lane scavenges must evacuate live 256 KB payloads from new
space; the wrapped payloads are malloc'd external memory the GC never traces.
Each collection also safepoints the whole isolate group, including the writer
mid-step. The isolated single-lane runs reproduce the end-to-end win
(−4% to −28% per insert across passes).

Residual: directly-attributed send-path + GC-pause deltas (~30 µs/insert at
256 KB) cover part of the observed 60–350 µs/insert range; the remainder is
second-order effects of the same heap churn (safepoint stalls inside the
writer's SQLite work, allocation slow paths), demonstrated collectively but
not budgeted line-by-line.
