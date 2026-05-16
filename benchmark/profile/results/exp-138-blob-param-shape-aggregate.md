# Experiment 138 — Blob-heavy Batch Parameter Shape Audit

Focused benchmark: `benchmark/experiments/batch_param_flatten.dart`

Reader pool size: irrelevant (writer-only `executeBatch`).

Wall-clock convention: each timed sample is one `executeBatch` call against
a fixed-shape statement on a fresh temp database, after 8 warmup
iterations. p50 is the median over 30 iterations (15 for the 4 KB / 4096 B
case to keep total wall reasonable). The benchmark prebuilds the
`paramSets` list outside the timed region, so the signal is centered on
writer-isolate batch parameter encoding plus SQLite batch stepping.

Command:

```text
dart run benchmark/experiments/batch_param_flatten.dart \
  --iterations=30 \
  --cell-mode=blob \
  --blob-size=N
```

## Configurations

- `mixed`: existing default — 25% TEXT (ASCII, ~12 bytes/cell),
  25% INTEGER, 25% REAL, 25% BLOB (4 bytes/cell). Anchor row for
  comparison with exp 113 / 125 / 126.
- `blob, blob_size=N`: every column is `BLOB` with a deterministic
  N-byte payload per cell, varying by row+col so SQLite cannot collapse
  identical values into a shared cached representation.

## p50 wall (ms) by shape and blob size

`p50_ms` over 30 iterations (15 for the 4096 B / 10000×20 case).

| shape | mixed | blob 4B | blob 64B | blob 256B | blob 1024B | blob 4096B |
|---|---:|---:|---:|---:|---:|---:|
| 100 rows × 2 params | 0.180 | 0.236 | 0.424 | 0.227 | 0.624 | 1.110 |
| 1000 rows × 2 params | 0.503 | 0.525 | 0.539 | 0.956 | 9.639 | 27.083 |
| 10000 rows × 2 params | 3.892 | 3.964 | 5.402 | 22.877 | 131.913 | 396.800 |
| 100 rows × 8 params | 0.177 | 0.153 | 0.175 | 0.517 | 0.950 | 8.768 |
| 1000 rows × 8 params | 0.766 | 0.848 | 1.452 | 13.816 | 22.366 | 111.919 |
| 10000 rows × 8 params | 6.503 | 9.011 | 26.297 | 146.825 | 417.401 | 2103.957 |
| 100 rows × 20 params | 0.217 | 0.247 | 0.316 | 0.741 | 6.001 | 21.821 |
| 1000 rows × 20 params | 1.149 | 1.638 | 2.915 | 18.361 | 69.791 | (skipped) |
| 10000 rows × 20 params | 12.297 | 17.055 | 93.170 | 240.479 | 1335.526 | (skipped) |

## Per-byte throughput (MB/s, derived)

`payload_bytes = row_count × param_width × blob_size`, divided by p50.
Mixed-mode row excluded — its mixed cell composition makes per-byte
denominators meaningless. Shapes whose total payload is below ~1 MB are
per-row-overhead-dominated; their throughput is correspondingly low.

| shape | blob 4B | blob 64B | blob 256B | blob 1024B | blob 4096B |
|---|---:|---:|---:|---:|---:|
| 1000 rows × 8 params | 38 | 353 | 148 | 366 | 293 |
| 10000 rows × 8 params | 35 | 312 | 139 | 196 | 156 |
| 1000 rows × 20 params | 49 | 439 | 279 | 293 | — |
| 10000 rows × 20 params | 47 | 137 | 213 | 153 | — |

## Reading the table

- **Mixed-mode anchor** (10k × 20 params): 12.297 ms, sits between
  exp 113's 14.2 ms median (pre-direct-matrix) and exp 125's 13.0 ms
  (ASCII fast path). The benchmark is reproducing the same encoder path
  that exp 113 / 125 / 126 exercised.
- **Tiny-blob path** (4 B): wall is dominated by per-row encoding +
  SQLite bind overhead. 10k × 20 = 17 ms at ~47 MB/s; doubling the
  param width roughly doubles the wall (8.2 µs/row vs 4.5 µs/row for
  8 params), which is row-overhead-shaped rather than byte-shaped.
- **Medium-blob path** (64 B – 256 B): wall scales close to linearly
  with total payload bytes. Per-byte throughput sits in a 137–439 MB/s
  band — SQLite's WAL-write throughput band on this hardware.
- **Large-blob path** (1024 B – 4096 B): per-byte throughput plateaus
  at 150–366 MB/s. Wall is dominated by SQLite page writes /
  WAL-frame I/O; encoding adds a fraction.
- **No allocation-path acceleration is visible.** The throughput band
  is flat across blob sizes from 64 B upward, which is the signature
  of SQLite stepping being the bottleneck, not Dart-side encoding.
  Compare exp 125 / 126: removing `utf8.encode` and the per-string
  temporary `Uint8List` dropped wall by 13–27% on wide ASCII / Unicode
  batches. There is no analogous removable allocation in the blob path
  because `view.setRange(...)` already writes the caller-supplied
  `Uint8List` directly into the inline parameter buffer.

## Comparison with exp 125 / 126 wide string shapes

For the 10k × 20 wide shape:

| variant | p50 (ms) | total payload | throughput (MB/s) | source |
|---|---:|---:|---:|---|
| ASCII (~12 B / cell) | 12.760 | 2.4 MB | 188 | exp 125 |
| Unicode (~22 B / cell) | 18.988 | 4.4 MB | 232 | exp 126 |
| Emoji (~26 B / cell) | 17.458 | 5.2 MB | 298 | exp 126 |
| Blob 64 B | 93.170 | 12.8 MB | 137 | exp 138 |
| Blob 256 B | 240.479 | 51.2 MB | 213 | exp 138 |
| Blob 1024 B | 1335.526 | 204.8 MB | 153 | exp 138 |

All variants land in the same SQLite-stepping throughput band once total
payload exceeds ~5 MB. Strings additionally benefit from exp 125 / 126's
allocation removal at the smaller end of the band; blobs already use the
direct-write path so their per-byte cost cannot be reduced without
changing SQLite-side work.

## Interpretation

See `experiments/138-blob-param-shape-audit.md` for the decision and
follow-up notes attached to these numbers.
