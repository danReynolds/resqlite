# Experiment 183 — json_buf retention audit + high-threshold reclaim: aggregate

Date: 2026-06-17

Harnesses:

- `benchmark/experiments/json_buf_retention.dart` — three workload
  shapes (small-only, one-shot-large, recurring-large), reports
  `Diagnostics.readerJsonBufHighWaterBytes` + RSS at five checkpoints
  per shape. Run once per side (baseline = origin/main, candidate =
  exp-183 with the diagnostic + shrink).
- `benchmark/experiments/large_bytes_transfer.dart` — exp 174's
  perf-neutrality A/B at small (~64 KB) and large (~651 KB) result
  sizes. Single pass per side, machine otherwise idle.

## Retention audit

### small-only (200 × ~4 KB `selectBytes`, no large reads)

| checkpoint | baseline | candidate |
|---|---:|---:|
| open | 64.0 KB | 64.0 KB |
| after 10 warmup | 64.0 KB | 64.0 KB |
| after 200 small | 64.0 KB | 64.0 KB |

Identical. The shrink doesn't fire on warm small buffers (`cap` never
crosses the 1 MB trigger).

### one-shot-large (8 concurrent × ~8 MB `selectBytes`, then 200 small)

| checkpoint | baseline | candidate |
|---|---:|---:|
| after seed + 1 small probe + 1 large probe | 8.05 MB | 8.05 MB |
| after 10 small warmup | 8.05 MB | **64.0 KB** |
| after concurrent burst of 8 large | 32.00 MB | 32.00 MB |
| after 200 small (post-burst settle) | **32.00 MB** | **64.0 KB** |

Baseline pins **32 MB** across the four readers for the rest of the
connection's life. Candidate reclaims **−32 MB** of pinned native heap
after the subsequent small reads. The single-probe row also shows the
shrink reclaiming an 8 MB one-off probe once the warmup runs through.

### recurring-large (1 large per 50 small, 300 interleaved)

| checkpoint | baseline | candidate |
|---|---:|---:|
| after seed | 64.0 KB | 64.0 KB |
| after 300 interleaved | **16.03 MB** | **64.0 KB** |

The recurring shape pins 16 MB on baseline; the candidate settles at
the 64 KB initial cap because each large read is immediately followed
by small reads that trip the reclaim. Each periodic large pays a
normal `buf_ensure` grow (~1 realloc per large), negligible against
the SQLite step + JSON-write that dominates a large-bytes query.

## Performance neutrality (`large_bytes_transfer.dart`)

| lane | baseline | candidate | Δ |
|---|---:|---:|---:|
| large-bytes (~651 KB, 150 iters) | 292 µs/query | 294 µs/query | +0.7 % |
| small-bytes (~64 KB, 2000 iters) | 98 µs/query | 100 µs/query | +2.0 % |

Both within run-to-run noise. The candidate adds one FFI call per
`selectBytes` reply; for warm buffers below the 1 MB trigger this is a
constant-time return.

## Reading the table

- `json_buf_total` is `sum(reader.json_buf.cap)` across the
  4-reader pool, summed in C and exposed through the new
  `Diagnostics.readerJsonBufHighWaterBytes` field.
- The reclaim fires from the reader worker AFTER `SendPort.send` on a
  `selectBytes` reply (the bytes are snapshotted by then, so realloc is
  safe). Gated by `json_buf.cap > 1 MB` AND `last_used_len < 256 KB`
  to keep back-to-back large reads on a warm buffer.
- A realloc failure inside the shrink leaves the existing larger
  buffer intact — the optimization is best-effort memory reclaim, not
  a correctness path.
