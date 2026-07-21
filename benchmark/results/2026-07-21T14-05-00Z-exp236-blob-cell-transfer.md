# Experiment 236: reader blob-cell TransferableTypedData transfer

- **Date:** 2026-07-21
- **Environment:** Apple M1 Pro, macOS 26.2, Dart 3.12.2 (`macos_arm64`)
- **Baseline:** `-DRESQLITE_BLOB_CELL_TRANSFER_THRESHOLD=1099511627776` (wrap disabled; origin/main behavior)
- **Candidate:** this branch, default threshold 256 KB
- **Harness:** [`benchmark/experiments/blob_read_transfer_ab.dart`](../experiments/blob_read_transfer_ab.dart) — one process per lane (the threshold is a compile-time define because the decode loop runs on worker isolates), passes order-flipped per exp 177; per-process lanes validated by exp 234's gc_split.
- **Decision:** Accepted (in review)

Median µs/select, 30 selects/sample × 9 samples. P1 base→cand, P2 cand→base, P3 base→cand with controls reordered before any wrapped shape.

| Shape | P1 base | P1 cand | P2 base | P2 cand | P3 base | P3 cand | Δ (range) |
|---|---:|---:|---:|---:|---:|---:|---|
| 1×512KB blob | 399.2 | 79.6 | 320.7 | 63.6 | 386.6 | 66.9 | **−80% to −83%** |
| 1×1MB blob | 641.1 | 152.0 | 550.5 | 166.5 | 576.8 | 110.6 | **−70% to −81%** |
| 4×300KB blobs | 889.1 | 291.9 | 740.1 | 226.4 | 762.9 | 134.6 | **−67% to −82%** |
| tx.select 1×512KB | 703.3 | 90.6 | 523.7 | 82.9 | 614.5 | 84.5 | **−84% to −87%** |
| 200KB control (direct both) | 56.9 | 68.3 | 47.1 | 53.6 | 61.6 | 63.1 | +2% clean-order |
| 400KB text control (sacrifices both) | 395.3 | 394.4 | 357.9 | 321.7 | 410.2 | 364.3 | 0% to −11% |
| 20×512B control (small) | 34.4 | 28.3 | 27.4 | 23.7 | 46.8 | 39.0 | sub-resolution |

Control notes: the 200KB direct-path control read +14–20% candidate-slower in P1/P2 and collapsed to +2.4% in P3 once controls ran *before* any wrapped shape — in P1/P2 the baseline's blob lanes sacrificed their readers, so its later lanes ran on freshly-respawned workers while the candidate's were long-lived: cross-lane contamination, not a code-path effect. The text control (sacrifices in both lanes) stays within noise in every pass. The small-blob control trends candidate-faster in all passes but at 24–47µs it is below harness resolution (exp 221's narrow-lane rule).

Interpretation: the baseline sacrifices the reader isolate on **every** blob-dominated query ≥ 256 KB — `Isolate.exit`, ~2–5 ms respawn amortized across the pool, statement-cache and schema-cache loss. The candidate decodes large blob cells straight into `TransferableTypedData` (one native→external copy, GC-invisible), keeps the worker, and moves the buffer across the hop. Repeated blob reads become **3–6× faster**; `tx.select` (which could never sacrifice and paid the full graph copy) improves **~6–7×**.
