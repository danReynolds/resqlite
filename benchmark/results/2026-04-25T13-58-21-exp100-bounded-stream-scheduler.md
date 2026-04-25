# resqlite Benchmark Results

Generated: 2026-04-25T13:58:21.653115

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp100-bounded-stream-scheduler`
- Repeats: `3`
- Runtime: `dart-vm / Dart 3.11.0`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `codex/exp-107-bounded-stream-scheduler @ ded64ebe1d7c (dirty)`
- Comparison baseline: `2026-04-23T19-38-11-exp097-one-pass-initial-stream-hash.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.012 | 0.015 | 0.001 | 0.001 |
| sqlite3 select() | 0.016 | 0.016 | 0.016 | 0.016 |
| sqlite_async select() | 0.033 | 0.065 | 0.001 | 0.002 |
| drift select() | 0.041 | 0.082 | 0.001 | 0.003 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.050 | 0.052 | 0.009 | 0.009 |
| sqlite3 select() | 0.123 | 0.156 | 0.123 | 0.156 |
| sqlite_async select() | 0.131 | 0.212 | 0.010 | 0.013 |
| drift select() | 0.210 | 0.249 | 0.011 | 0.013 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.403 | 0.523 | 0.089 | 0.093 |
| sqlite3 select() | 1.105 | 1.284 | 1.105 | 1.284 |
| sqlite_async select() | 1.055 | 1.290 | 0.097 | 0.106 |
| drift select() | 1.779 | 2.091 | 0.099 | 0.104 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 5.024 | 15.561 | 0.893 | 1.424 |
| sqlite3 select() | 15.919 | 25.180 | 15.919 | 25.180 |
| sqlite_async select() | 14.273 | 24.442 | 0.976 | 1.849 |
| drift select() | 24.685 | 36.043 | 0.979 | 1.088 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.033 | 0.035 | 0.016 | 0.017 |
| sqlite3 + jsonEncode | 0.032 | 0.060 | 0.032 | 0.060 |
| sqlite_async + jsonEncode | 0.051 | 0.052 | 0.017 | 0.017 |
| drift + jsonEncode | 0.064 | 0.082 | 0.017 | 0.019 |
| resqlite selectBytes() | 0.011 | 0.013 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.214 | 0.237 | 0.168 | 0.182 |
| sqlite3 + jsonEncode | 0.261 | 0.281 | 0.261 | 0.281 |
| sqlite_async + jsonEncode | 0.268 | 0.317 | 0.153 | 0.181 |
| drift + jsonEncode | 0.343 | 0.445 | 0.160 | 0.187 |
| resqlite selectBytes() | 0.046 | 0.074 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.831 | 2.001 | 1.505 | 1.589 |
| sqlite3 + jsonEncode | 2.729 | 3.364 | 2.729 | 3.364 |
| sqlite_async + jsonEncode | 3.080 | 6.969 | 1.699 | 4.008 |
| drift + jsonEncode | 3.299 | 7.280 | 1.594 | 2.510 |
| resqlite selectBytes() | 0.368 | 0.415 | 0.000 | 0.001 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 21.225 | 28.725 | 15.232 | 19.427 |
| sqlite3 + jsonEncode | 32.346 | 43.878 | 32.346 | 43.878 |
| sqlite_async + jsonEncode | 35.149 | 45.370 | 17.274 | 20.979 |
| drift + jsonEncode | 43.677 | 63.126 | 16.359 | 22.662 |
| resqlite selectBytes() | 3.885 | 7.943 | 0.003 | 0.019 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.103 | 0.108 | 0.035 | 0.038 |
| sqlite3 | 0.323 | 0.356 | 0.323 | 0.356 |
| sqlite_async | 0.380 | 0.479 | 0.044 | 0.053 |
| drift | 0.605 | 0.726 | 0.043 | 0.057 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.951 | 1.070 | 0.271 | 0.310 |
| sqlite3 | 3.477 | 4.436 | 3.477 | 4.436 |
| sqlite_async | 3.219 | 3.754 | 0.358 | 0.449 |
| drift | 5.124 | 7.227 | 0.349 | 0.377 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.562 | 0.611 | 0.103 | 0.112 |
| sqlite3 | 1.500 | 2.236 | 1.500 | 2.236 |
| sqlite_async | 1.433 | 1.867 | 0.122 | 0.137 |
| drift | 2.173 | 2.548 | 0.127 | 0.143 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.311 | 0.422 | 0.102 | 0.130 |
| sqlite3 | 1.056 | 4.342 | 1.056 | 4.342 |
| sqlite_async | 1.021 | 2.982 | 0.126 | 0.719 |
| drift | 1.918 | 3.751 | 0.134 | 0.311 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.316 | 0.754 | 0.102 | 0.216 |
| sqlite3 | 1.025 | 1.464 | 1.025 | 1.464 |
| sqlite_async | 1.003 | 1.395 | 0.122 | 0.209 |
| drift | 1.693 | 3.728 | 0.124 | 0.233 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.014 | 0.029 | 0.001 | 0.001 |
| sqlite3 | 0.015 | 0.016 | 0.015 | 0.016 |
| sqlite_async | 0.035 | 0.055 | 0.001 | 0.003 |
| drift | 0.039 | 0.052 | 0.001 | 0.002 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.031 | 0.042 | 0.004 | 0.005 |
| sqlite3 | 0.061 | 0.066 | 0.061 | 0.066 |
| sqlite_async | 0.073 | 0.085 | 0.005 | 0.006 |
| drift | 0.113 | 0.140 | 0.005 | 0.006 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.047 | 0.051 | 0.009 | 0.009 |
| sqlite3 | 0.119 | 0.127 | 0.119 | 0.127 |
| sqlite_async | 0.125 | 0.155 | 0.009 | 0.012 |
| drift | 0.183 | 0.228 | 0.009 | 0.011 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.199 | 0.210 | 0.044 | 0.045 |
| sqlite3 | 0.547 | 0.631 | 0.547 | 0.631 |
| sqlite_async | 0.520 | 0.653 | 0.046 | 0.054 |
| drift | 0.789 | 0.919 | 0.045 | 0.049 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.387 | 0.427 | 0.087 | 0.093 |
| sqlite3 | 1.098 | 1.229 | 1.098 | 1.229 |
| sqlite_async | 1.046 | 1.372 | 0.093 | 0.117 |
| drift | 1.655 | 2.120 | 0.093 | 0.101 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.830 | 0.869 | 0.176 | 0.189 |
| sqlite3 | 2.226 | 2.591 | 2.226 | 2.591 |
| sqlite_async | 2.257 | 3.403 | 0.202 | 0.223 |
| drift | 3.676 | 4.985 | 0.207 | 0.234 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.387 | 6.937 | 0.449 | 0.668 |
| sqlite3 | 6.324 | 10.163 | 6.324 | 10.163 |
| sqlite_async | 8.092 | 12.587 | 0.541 | 0.787 |
| drift | 9.703 | 11.316 | 0.502 | 0.552 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 6.847 | 27.573 | 0.993 | 2.739 |
| sqlite3 | 15.076 | 18.693 | 15.076 | 18.693 |
| sqlite_async | 14.571 | 18.358 | 0.974 | 1.875 |
| drift | 25.915 | 33.013 | 0.983 | 1.303 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 11.808 | 22.451 | 1.727 | 2.588 |
| sqlite3 | 36.162 | 46.418 | 36.162 | 46.418 |
| sqlite_async | 42.682 | 54.012 | 1.965 | 3.767 |
| drift | 59.472 | 88.808 | 2.067 | 8.591 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.033 | 0.039 | 0.033 | 0.039 |
| sqlite3 + jsonEncode | 0.031 | 0.033 | 0.031 | 0.033 |
| sqlite_async + jsonEncode | 0.052 | 0.055 | 0.052 | 0.055 |
| drift + jsonEncode | 0.058 | 0.090 | 0.058 | 0.090 |
| resqlite selectBytes() | 0.012 | 0.013 | 0.012 | 0.013 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.109 | 0.138 | 0.109 | 0.138 |
| sqlite3 + jsonEncode | 0.136 | 0.146 | 0.136 | 0.146 |
| sqlite_async + jsonEncode | 0.147 | 0.151 | 0.147 | 0.151 |
| drift + jsonEncode | 0.202 | 0.239 | 0.202 | 0.239 |
| resqlite selectBytes() | 0.029 | 0.042 | 0.029 | 0.042 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.203 | 0.264 | 0.203 | 0.264 |
| sqlite3 + jsonEncode | 0.264 | 0.324 | 0.264 | 0.324 |
| sqlite_async + jsonEncode | 0.268 | 0.351 | 0.268 | 0.351 |
| drift + jsonEncode | 0.330 | 0.405 | 0.330 | 0.405 |
| resqlite selectBytes() | 0.050 | 0.071 | 0.050 | 0.071 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.937 | 1.150 | 0.937 | 1.150 |
| sqlite3 + jsonEncode | 1.308 | 1.451 | 1.308 | 1.451 |
| sqlite_async + jsonEncode | 1.428 | 2.651 | 1.428 | 2.651 |
| drift + jsonEncode | 1.758 | 4.075 | 1.758 | 4.075 |
| resqlite selectBytes() | 0.187 | 0.237 | 0.187 | 0.237 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.964 | 5.581 | 1.964 | 5.581 |
| sqlite3 + jsonEncode | 2.622 | 5.428 | 2.622 | 5.428 |
| sqlite_async + jsonEncode | 2.616 | 5.042 | 2.616 | 5.042 |
| drift + jsonEncode | 3.320 | 5.921 | 3.320 | 5.921 |
| resqlite selectBytes() | 0.371 | 0.383 | 0.371 | 0.383 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 4.144 | 9.911 | 4.144 | 9.911 |
| sqlite3 + jsonEncode | 5.436 | 11.159 | 5.436 | 11.159 |
| sqlite_async + jsonEncode | 5.664 | 11.088 | 5.664 | 11.088 |
| drift + jsonEncode | 7.179 | 14.254 | 7.179 | 14.254 |
| resqlite selectBytes() | 0.878 | 1.903 | 0.878 | 1.903 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 10.984 | 18.663 | 10.984 | 18.663 |
| sqlite3 + jsonEncode | 16.193 | 24.845 | 16.193 | 24.845 |
| sqlite_async + jsonEncode | 15.532 | 23.095 | 15.532 | 23.095 |
| drift + jsonEncode | 19.647 | 26.607 | 19.647 | 26.607 |
| resqlite selectBytes() | 2.220 | 4.514 | 2.220 | 4.514 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 22.351 | 28.210 | 22.351 | 28.210 |
| sqlite3 + jsonEncode | 35.802 | 51.810 | 35.802 | 51.810 |
| sqlite_async + jsonEncode | 30.407 | 41.634 | 30.407 | 41.634 |
| drift + jsonEncode | 49.065 | 69.384 | 49.065 | 69.384 |
| resqlite selectBytes() | 4.140 | 8.550 | 4.140 | 8.550 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 47.846 | 69.510 | 47.846 | 69.510 |
| sqlite3 + jsonEncode | 71.424 | 89.740 | 71.424 | 89.740 |
| sqlite_async + jsonEncode | 84.302 | 130.171 | 84.302 | 130.171 |
| drift + jsonEncode | 100.696 | 179.740 | 100.696 | 179.740 |
| resqlite selectBytes() | 10.893 | 22.017 | 10.893 | 22.017 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.31 | 0.39 | 0.31 |
| sqlite_async | 0.97 | 1.21 | 0.97 |
| drift | 1.48 | 1.73 | 1.48 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.34 | 0.40 | 0.17 |
| sqlite_async | 1.38 | 1.75 | 0.69 |
| drift | 2.92 | 3.43 | 1.46 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.37 | 0.68 | 0.09 |
| sqlite_async | 2.22 | 2.90 | 0.55 |
| drift | 5.45 | 6.14 | 1.36 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.71 | 1.25 | 0.09 |
| sqlite_async | 5.17 | 6.04 | 0.65 |
| drift | 11.33 | 12.27 | 1.42 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 115116 |
| resqlite per query | 0.009 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 115116 | 98104..118627 | 8.9 | 12.7 |
| sqlite3 | 186075 | 182282..187882 | 1.5 | 4.9 |
| sqlite_async | 38107 | 31054..39718 | 11.4 | 31.9 |
| drift | 37541 | 32990..41293 | 11.1 | 34.0 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 15.055 | 17.045 | 15.055 | 17.045 |
| sqlite_async | 37.985 | 49.767 | 37.985 | 49.767 |
| drift | 55.467 | 63.128 | 55.467 | 63.128 |
| sqlite3 (no cache) | 26.528 | 31.651 | 26.528 | 31.651 |
| sqlite3 (cached stmt) | 24.774 | 26.776 | 24.774 | 26.776 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.851 | 2.628 | 1.851 | 2.628 |
| sqlite3 execute() | 0.965 | 1.708 | 0.965 | 1.708 |
| sqlite_async execute() | 4.021 | 6.833 | 4.021 | 6.833 |
| drift execute() | 3.247 | 4.053 | 3.247 | 4.053 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.058 | 0.060 | 0.058 | 0.060 |
| sqlite3 executeBatch() | 0.050 | 0.054 | 0.050 | 0.054 |
| sqlite_async executeBatch() | 0.101 | 0.141 | 0.101 | 0.141 |
| drift executeBatch() | 0.117 | 0.141 | 0.117 | 0.141 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.445 | 0.512 | 0.445 | 0.512 |
| sqlite3 executeBatch() | 0.437 | 0.486 | 0.437 | 0.486 |
| sqlite_async executeBatch() | 0.550 | 0.783 | 0.550 | 0.783 |
| drift executeBatch() | 0.745 | 0.914 | 0.745 | 0.914 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.725 | 5.434 | 4.725 | 5.434 |
| sqlite3 executeBatch() | 4.915 | 6.228 | 4.915 | 6.228 |
| sqlite_async executeBatch() | 5.211 | 5.474 | 5.211 | 5.474 |
| drift executeBatch() | 7.193 | 8.579 | 7.193 | 8.579 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.056 | 0.082 | 0.056 | 0.082 |
| sqlite_async writeTransaction() | 0.102 | 0.190 | 0.102 | 0.190 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.073 | 0.099 | 0.073 | 0.099 |
| resqlite tx.execute() loop | 0.776 | 0.928 | 0.776 | 0.928 |
| sqlite_async tx.execute() loop | 1.376 | 3.188 | 1.376 | 3.188 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.471 | 0.683 | 0.471 | 0.683 |
| resqlite tx.execute() loop | 6.380 | 7.502 | 6.380 | 7.502 |
| sqlite_async tx.execute() loop | 11.925 | 12.796 | 11.925 | 12.796 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.112 | 0.134 | 0.112 | 0.134 |
| sqlite_async tx.getAll() | 0.213 | 0.286 | 0.213 | 0.286 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.206 | 0.249 | 0.206 | 0.249 |
| sqlite_async tx.getAll() | 0.411 | 0.572 | 0.411 | 0.572 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.027 | 0.035 | 0.027 | 0.035 |
| sqlite_async watch() | 0.117 | 0.130 | 0.117 | 0.130 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.057 | 0.074 | 0.057 | 0.074 |
| sqlite_async | 0.084 | 0.119 | 0.084 | 0.119 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.218 | 0.348 | 0.218 | 0.348 |
| sqlite_async | 1.393 | 6.368 | 1.393 | 6.368 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.239 | 0.300 | 0.239 | 0.300 |
| sqlite_async | 0.312 | 0.416 | 0.312 | 0.416 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.656 | 1.656 | 1.656 | 1.656 |
| sqlite_async | 10.334 | 10.334 | 10.334 | 10.334 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.108 | 4.821 | 4.108 | 4.821 |
| sqlite_async | 6.806 | 7.774 | 6.806 | 7.774 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.614 | 0.763 | 0.614 | 0.763 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 7.137 | 8.041 | 7.137 | 8.041 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. On resqlite's main branch this ratio is driven toward 0 by experiment 075 (C-side result-hash short-circuit), not by writer-side column-tracking (exp 052 is not implemented). The two mechanisms are indistinguishable on this read-side benchmark.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 87.7 | 0.000 |
| sqlite_async | 3429 | 965.9 | 0.982 |
| drift | 5000 | 1168.9 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 78.2 | 0.000 |
| sqlite_async | 3491 | 954.7 | 0.982 |
| drift | 5000 | 1170.7 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 215.35 | 216.08 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 433.59 | 435.63 | 0.00 | 0.00 | 1109 | 3 |
| drift stream() | 572.46 | 583.29 | 0.01 | 0.04 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.028 | 0.052 | 0.000 | 0.000 |
| sqlite3 | 0.022 | 0.054 | 0.022 | 0.054 |
| sqlite_async | 0.069 | 0.168 | 0.000 | 0.000 |
| drift | 0.055 | 0.131 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.021 | 0.037 | 0.000 | 0.000 |
| sqlite3 | 0.015 | 0.025 | 0.015 | 0.025 |
| sqlite_async | 0.053 | 0.114 | 0.000 | 0.000 |
| drift | 0.043 | 0.099 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.029 | 0.043 | 0.000 | 0.000 |
| sqlite3 | 0.033 | 0.040 | 0.033 | 0.040 |
| sqlite_async | 0.077 | 0.244 | 0.000 | 0.001 |
| drift | 0.061 | 0.089 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.010 | 0.022 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.007 | 0.005 | 0.007 |
| sqlite_async | 0.029 | 0.084 | 0.000 | 0.000 |
| drift | 0.023 | 0.044 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.040 | 0.045 | 0.001 | 0.001 |
| sqlite3 | 0.065 | 0.077 | 0.065 | 0.077 |
| sqlite_async | 0.080 | 0.087 | 0.001 | 0.001 |
| drift | 0.092 | 0.109 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 105.889 | 106.478 | 0.000 | 0.000 | 0 |
| sqlite_async | 214.707 | 216.093 | 0.000 | 0.000 | 40 |
| drift | 220.563 | 222.409 | 0.000 | 0.018 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 479.42 | 479.42 | 0.00 | 0.00 | 24.49 | 454.92 | 2 |
| sqlite_async | 496.61 | 496.61 | 0.00 | 0.00 | 24.63 | 471.97 | 1176 |
| drift | 1876.37 | 1876.37 | 0.23 | 0.23 | 13.98 | 1862.83 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 4.91 | 25.36 | 1.34..12.17 | ±5.41 |
| sqlite3 select() | 3.05 | 7.59 | 0.00..6.47 | ±3.23 |
| sqlite_async select() | 1.00 | 1.00 | 0.97..1.00 | ±0.02 |
| drift select() | 8.56 | 28.72 | 0.00..12.61 | ±6.30 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 8.00 | 0.00..5.75 | ±2.88 |
| resqlite + jsonEncode | 0.00 | 37.19 | 0.00..8.77 | ±4.38 |
| sqlite3 + jsonEncode | 0.00 | 18.23 | 0.00..5.97 | ±2.98 |
| sqlite_async + jsonEncode | 0.00 | 3.52 | 0.00..3.02 | ±1.51 |
| drift + jsonEncode | 0.00 | 82.98 | 0.00..17.67 | ±8.84 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.00 | 4.92 | 0.00..0.00 | ±0.00 |
| sqlite3 executeBatch() | 0.00 | 0.50 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 0.02 | 0.00..0.00 | ±0.00 |
| drift batch() | 0.03 | 4.50 | 0.00..3.00 | ±1.50 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.08 | 0.00..0.06 | ±0.03 |
| sqlite_async watch() | 0.00 | 0.52 | 0.00..0.02 | ±0.01 |

## SQLite Diagnostics

resqlite-only internal SQLite counters captured via `Database.diagnostics()` after representative workloads. Values reflect the writer plus idle readers in this connection pool; they are not process-global SQLite totals.

### Warm read working set (20000 rows + 2000 point lookups)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | Readers busy |
|---|---|---|---|---|---|---|
| resqlite | 3207.0 | 3189.5 | 5.3 | 12.2 | 2048.0 | 0 |

### Statement cache footprint (48 distinct SELECT texts)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | Readers busy |
|---|---|---|---|---|---|---|
| resqlite | 3300.0 | 3189.5 | 5.3 | 105.2 | 2048.0 | 0 |

### WAL after write burst (1000 inserted rows)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | Readers busy |
|---|---|---|---|---|---|---|
| resqlite | 257.5 | 240.0 | 5.3 | 12.2 | 161.0 | 0 |

## Repeat Stability

These rows summarize resqlite wall medians across repeated full-suite runs.
Use this section to judge whether small deltas are real or just noise.

| Benchmark | Median (ms) | 95% CI (ms) | MDE_ci | Range | MAD | Stability |
|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.03 | 0.03..0.03 | 10.3% | 10.3% | 3.4% | moderate |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 20.0% | 20.0% | 10.0% | noisy |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.03 | 0.03..0.03 | 21.4% | 21.4% | 7.1% | moderate |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02..0.02 | 14.3% | 14.3% | 4.8% | moderate |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.31 | 0.30..0.31 | 3.2% | 3.2% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.31 | 0.30..0.31 | 3.2% | 3.2% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.34 | 0.32..0.45 | 38.2% | 38.2% | 5.9% | moderate |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.17 | 0.16..0.22 | 35.3% | 35.3% | 5.9% | moderate |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.37 | 0.37..0.38 | 2.7% | 2.7% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.09 | 0.09..0.09 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.73 | 0.71..0.75 | 5.5% | 5.5% | 2.7% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.09 | 0.09..0.09 | 0.0% | 0.0% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.04 | 10.0% | 10.0% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 300.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 105.69 | 104.48..105.89 | 1.3% | 1.3% | 0.2% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 427.31 | 233.27..479.42 | 57.6% | 57.6% | 12.2% | noisy |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 215.35 | 213.74..216.21 | 1.1% | 1.1% | 0.4% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 15.05 | 14.90..15.47 | 3.8% | 3.8% | 1.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 15.05 | 14.90..15.47 | 3.8% | 3.8% | 1.0% | stable |
| Point Query Throughput / resqlite qps | 115116.00 | 113327.00..122807.00 | 8.2% | 8.2% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.02 | 50.0% | 50.0% | 7.1% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.04 | 36.4% | 36.4% | 12.1% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.04 | 36.4% | 36.4% | 12.1% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 100.0% | 100.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 50.0% | 50.0% | 8.3% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.02 | 50.0% | 50.0% | 8.3% | noisy |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05..0.05 | 8.3% | 8.3% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.20 | 0.19..0.21 | 8.4% | 8.4% | 3.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.20 | 0.19..0.21 | 8.4% | 8.4% | 3.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.05 | 0.05..0.06 | 18.0% | 18.0% | 8.0% | noisy |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.05 | 0.05..0.06 | 18.0% | 18.0% | 8.0% | noisy |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.39 | 0.38..0.41 | 6.7% | 6.7% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.96 | 1.91..2.04 | 6.6% | 6.6% | 2.6% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.96 | 1.91..2.04 | 6.6% | 6.6% | 2.6% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09..0.09 | 5.7% | 5.7% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.37 | 0.37..0.38 | 2.7% | 2.7% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.37 | 0.37..0.38 | 2.7% | 2.7% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 5.93 | 5.19..6.85 | 27.9% | 27.9% | 12.4% | noisy |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 22.80 | 22.35..24.43 | 9.1% | 9.1% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 22.80 | 22.35..24.43 | 9.1% | 9.1% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.90 | 0.87..0.99 | 13.2% | 13.2% | 3.1% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 3.88 | 3.85..4.14 | 7.4% | 7.4% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 3.88 | 3.85..4.14 | 7.4% | 7.4% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.83 | 0.82..0.89 | 7.5% | 7.5% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 4.36 | 4.14..4.62 | 10.9% | 10.9% | 4.9% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 4.36 | 4.14..4.62 | 10.9% | 10.9% | 4.9% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.18 | 0.18..0.18 | 2.3% | 2.3% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.88 | 0.83..0.97 | 15.5% | 15.5% | 5.2% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.88 | 0.83..0.97 | 15.5% | 15.5% | 5.2% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 12.37 | 11.81..18.20 | 51.7% | 51.7% | 4.5% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 47.85 | 44.85..48.79 | 8.2% | 8.2% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 47.85 | 44.85..48.79 | 8.2% | 8.2% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.78 | 1.73..1.80 | 4.4% | 4.4% | 1.3% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 8.39 | 8.37..10.89 | 30.1% | 30.1% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 8.39 | 8.37..10.89 | 30.1% | 30.1% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03..0.03 | 19.4% | 19.4% | 9.7% | noisy |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.10..0.11 | 10.1% | 10.1% | 4.6% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.11 | 0.10..0.11 | 10.1% | 10.1% | 4.6% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.01 | 25.0% | 25.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.03..0.03 | 10.3% | 10.3% | 3.4% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.03..0.03 | 10.3% | 10.3% | 3.4% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.20 | 0.20..0.21 | 3.5% | 3.5% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.94 | 0.94..1.05 | 11.9% | 11.9% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.94 | 0.94..1.05 | 11.9% | 11.9% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04..0.04 | 2.3% | 2.3% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.19 | 0.18..0.20 | 6.4% | 6.4% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.19 | 0.18..0.20 | 6.4% | 6.4% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.39 | 2.29..2.39 | 4.1% | 4.1% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 10.92 | 10.58..10.98 | 3.7% | 3.7% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 10.92 | 10.58..10.98 | 3.7% | 3.7% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.45 | 0.43..0.45 | 4.2% | 4.2% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 2.22 | 2.00..2.85 | 38.3% | 38.3% | 9.8% | noisy |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 2.22 | 2.00..2.85 | 38.3% | 38.3% | 9.8% | noisy |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.10 | 0.10..0.17 | 69.9% | 69.9% | 1.9% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.04 | 0.04..0.04 | 0.0% | 0.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.31 | 0.30..0.32 | 4.1% | 4.1% | 0.6% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.10 | 0.10..0.10 | 4.0% | 4.0% | 1.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.31 | 0.29..0.32 | 8.0% | 8.0% | 1.9% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.10 | 0.09..0.10 | 7.8% | 7.8% | 0.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.56 | 0.56..0.57 | 2.0% | 2.0% | 0.2% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.10 | 0.10..0.10 | 0.0% | 0.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.95 | 0.93..0.95 | 1.9% | 1.9% | 0.2% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.27 | 0.27..0.28 | 3.3% | 3.3% | 1.5% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.06 | 106.1% | 106.1% | 18.2% | noisy |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.01..0.04 | 150.0% | 150.0% | 6.3% | moderate |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 109.1% | 109.1% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.21 | 0.20..0.23 | 15.4% | 15.4% | 7.5% | moderate |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.17 | 0.16..0.18 | 11.3% | 11.3% | 4.8% | moderate |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.05..0.05 | 10.4% | 10.4% | 4.2% | moderate |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.87 | 1.83..1.92 | 4.6% | 4.6% | 2.1% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.53 | 1.50..1.55 | 2.9% | 2.9% | 1.4% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.37 | 0.37..0.38 | 4.0% | 4.0% | 1.6% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 22.08 | 21.23..24.96 | 16.9% | 16.9% | 3.9% | moderate |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 15.41 | 15.23..15.83 | 3.9% | 3.9% | 1.1% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.91 | 3.88..3.99 | 2.6% | 2.6% | 0.6% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.01 | 50.0% | 50.0% | 25.0% | noisy |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.09 | 535.7% | 535.7% | 14.3% | noisy |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 1050.0% | 1050.0% | 50.0% | noisy |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.05..0.16 | 214.0% | 214.0% | 2.0% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 11.1% | 11.1% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.40 | 0.40..0.47 | 15.9% | 15.9% | 0.2% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.08..0.09 | 11.2% | 11.2% | 0.0% | stable |
| Select → Maps / 10000 rows / resqlite select() | 5.02 | 4.67..5.08 | 8.4% | 8.4% | 1.2% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.86 | 0.70..0.89 | 22.2% | 22.2% | 3.5% | moderate |
| Streaming / Fan-out (10 streams) / resqlite | 0.32 | 0.24..0.41 | 53.9% | 53.9% | 25.1% | noisy |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.32 | 0.24..0.41 | 53.9% | 53.9% | 25.1% | noisy |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.61 | 0.52..0.86 | 54.7% | 54.7% | 14.8% | noisy |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.61 | 0.52..0.86 | 54.7% | 54.7% | 14.8% | noisy |
| Streaming / Initial Emission / resqlite stream() | 0.04 | 0.03..0.06 | 92.3% | 92.3% | 30.8% | noisy |
| Streaming / Initial Emission / resqlite stream() [main] | 0.04 | 0.03..0.06 | 92.3% | 92.3% | 30.8% | noisy |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.04..0.06 | 24.5% | 24.5% | 8.2% | noisy |
| Streaming / Invalidation Latency / resqlite [main] | 0.05 | 0.04..0.06 | 24.5% | 24.5% | 8.2% | noisy |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 4.11 | 4.11..4.30 | 4.6% | 4.6% | 0.0% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 4.11 | 4.11..4.30 | 4.6% | 4.6% | 0.0% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.02 | 1.66..2.70 | 51.6% | 51.6% | 18.0% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.02 | 1.66..2.70 | 51.6% | 51.6% | 18.0% | noisy |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 7.14 | 6.32..7.59 | 17.9% | 17.9% | 6.4% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 7.14 | 6.32..7.59 | 17.9% | 17.9% | 6.4% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.22 | 0.22..1.39 | 522.8% | 522.8% | 2.7% | stable |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.22 | 0.22..1.39 | 522.8% | 522.8% | 2.7% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.06..0.06 | 5.0% | 5.0% | 1.7% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.06 | 0.06..0.06 | 5.0% | 5.0% | 1.7% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.46 | 0.45..0.52 | 15.4% | 15.4% | 2.4% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.46 | 0.45..0.52 | 15.4% | 15.4% | 2.4% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.72 | 4.69..5.94 | 26.5% | 26.5% | 0.8% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.72 | 4.69..5.94 | 26.5% | 26.5% | 0.8% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.68 | 0.62..0.78 | 23.3% | 23.3% | 9.7% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.68 | 0.62..0.78 | 23.3% | 23.3% | 9.7% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07..0.08 | 4.0% | 4.0% | 1.3% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07..0.08 | 4.0% | 4.0% | 1.3% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 7.08 | 6.38..7.18 | 11.3% | 11.3% | 1.3% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 7.08 | 6.38..7.18 | 11.3% | 11.3% | 1.3% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.51 | 0.47..0.58 | 20.5% | 20.5% | 8.0% | noisy |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.51 | 0.47..0.58 | 20.5% | 20.5% | 8.0% | noisy |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.06 | 0.06..0.07 | 22.0% | 22.0% | 5.1% | moderate |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.06 | 0.06..0.07 | 22.0% | 22.0% | 5.1% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 2.27 | 1.85..2.38 | 23.4% | 23.4% | 5.1% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 2.27 | 1.85..2.38 | 23.4% | 23.4% | 5.1% | moderate |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.20 | 0.19..0.21 | 7.0% | 7.0% | 2.5% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.20 | 0.19..0.21 | 7.0% | 7.0% | 2.5% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.12 | 0.11..0.12 | 4.3% | 4.3% | 1.7% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.12 | 0.11..0.12 | 4.3% | 4.3% | 1.7% | stable |


## Comparison vs Previous Run

Previous: `2026-04-23T19-38-11-exp097-one-pass-initial-stream-hash.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.02 | 0.03 | +0.01 | ±10% / ±0.02 ms | 10.3% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | +0.00 | ±30% / ±0.02 ms | 20.0% | noisy | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.03 | +0.01 | ±21% / ±0.02 ms | 21.4% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.02 | +0.01 | ±14% / ±0.02 ms | 14.3% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.29 | 0.31 | +0.02 | ±10% / ±0.03 ms | 3.2% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.29 | 0.31 | +0.02 | ±10% / ±0.03 ms | 3.2% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.31 | 0.34 | +0.03 | ±38% / ±0.13 ms | 38.2% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.16 | 0.17 | +0.01 | ±35% / ±0.06 ms | 35.3% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.81 | 0.37 | -0.44 | ±10% / ±0.08 ms | 2.7% | stable | 🟢 Win (-54%) |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.20 | 0.09 | -0.11 | ±10% / ±0.02 ms | 0.0% | stable | 🟢 Win (-55%) |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.65 | 0.73 | +0.08 | ±10% / ±0.07 ms | 5.5% | stable | 🔴 Regression (+12%) |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.08 | 0.09 | +0.01 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 10.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±300% / ±0.02 ms | 300.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 108.94 | 105.69 | -3.25 | ±10% / ±10.89 ms | 1.3% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 240.69 | 427.31 | +186.62 | ±58% / ±246.15 ms | 57.6% | noisy | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 225.54 | 215.35 | -10.19 | ±10% / ±22.55 ms | 1.1% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.19 | 15.05 | +0.87 | ±10% / ±1.51 ms | 3.8% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.19 | 15.05 | +0.87 | ±10% / ±1.51 ms | 3.8% | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 129410.00 | 115116.00 | -14294.00 | ±10% / ±12941.00 ms | 8.2% | stable | 🔴 Regression (-11%) |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01 | +0.00 | ±50% / ±0.02 ms | 50.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.01 | ±36% / ±0.02 ms | 36.4% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.03 | +0.01 | ±36% / ±0.02 ms | 36.4% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±100% / ±0.02 ms | 100.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±50% / ±0.02 ms | 50.0% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±50% / ±0.02 ms | 50.0% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.05 | +0.00 | ±10% / ±0.02 ms | 8.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.20 | +0.01 | ±10% / ±0.02 ms | 8.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.20 | +0.01 | ±10% / ±0.02 ms | 8.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.05 | +0.01 | ±24% / ±0.02 ms | 18.0% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.05 | +0.01 | ±24% / ±0.02 ms | 18.0% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.37 | 0.39 | +0.02 | ±10% / ±0.04 ms | 6.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.71 | 1.96 | +0.25 | ±10% / ±0.20 ms | 6.6% | stable | 🔴 Regression (+15%) |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.71 | 1.96 | +0.25 | ±10% / ±0.20 ms | 6.6% | stable | 🔴 Regression (+15%) |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 5.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.37 | +0.03 | ±10% / ±0.04 ms | 2.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.37 | +0.03 | ±10% / ±0.04 ms | 2.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.19 | 5.93 | +1.74 | ±37% / ±2.21 ms | 27.9% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 21.96 | 22.80 | +0.83 | ±10% / ±2.28 ms | 9.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 21.96 | 22.80 | +0.83 | ±10% / ±2.28 ms | 9.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.83 | 0.90 | +0.07 | ±13% / ±0.12 ms | 13.2% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.68 | 3.88 | +0.20 | ±10% / ±0.39 ms | 7.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.68 | 3.88 | +0.20 | ±10% / ±0.39 ms | 7.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.75 | 0.83 | +0.08 | ±10% / ±0.08 ms | 7.5% | stable | 🔴 Regression (+11%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.62 | 4.36 | +0.74 | ±15% / ±0.64 ms | 10.9% | moderate | 🔴 Regression (+20%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.62 | 4.36 | +0.74 | ±15% / ±0.64 ms | 10.9% | moderate | 🔴 Regression (+20%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.17 | 0.18 | +0.01 | ±10% / ±0.02 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.86 | 0.88 | +0.02 | ±16% / ±0.14 ms | 15.5% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.86 | 0.88 | +0.02 | ±16% / ±0.14 ms | 15.5% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.44 | 12.37 | +1.93 | ±52% / ±6.39 ms | 51.7% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 44.76 | 47.85 | +3.09 | ±10% / ±4.78 ms | 8.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 44.76 | 47.85 | +3.09 | ±10% / ±4.78 ms | 8.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.65 | 1.78 | +0.13 | ±10% / ±0.18 ms | 4.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.08 | 8.39 | +0.32 | ±30% / ±2.53 ms | 30.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.08 | 8.39 | +0.32 | ±30% / ±2.53 ms | 30.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03 | +0.01 | ±29% / ±0.02 ms | 19.4% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.11 | +0.01 | ±14% / ±0.02 ms | 10.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.10 | 0.11 | +0.01 | ±14% / ±0.02 ms | 10.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±25% / ±0.02 ms | 25.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 10.3% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 10.3% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.18 | 0.20 | +0.02 | ±10% / ±0.02 ms | 3.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.88 | 0.94 | +0.06 | ±12% / ±0.11 ms | 11.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.88 | 0.94 | +0.06 | ±12% / ±0.11 ms | 11.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.19 | +0.01 | ±10% / ±0.02 ms | 6.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.19 | +0.01 | ±10% / ±0.02 ms | 6.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.21 | 2.39 | +0.17 | ±10% / ±0.24 ms | 4.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 9.74 | 10.92 | +1.18 | ±10% / ±1.09 ms | 3.7% | stable | 🔴 Regression (+12%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 9.74 | 10.92 | +1.18 | ±10% / ±1.09 ms | 3.7% | stable | 🔴 Regression (+12%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.44 | 0.45 | +0.01 | ±10% / ±0.04 ms | 4.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.99 | 2.22 | +0.23 | ±38% / ±0.85 ms | 38.3% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.99 | 2.22 | +0.23 | ±38% / ±0.85 ms | 38.3% | noisy | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.10 | 0.10 | +0.00 | ±70% / ±0.07 ms | 69.9% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.29 | 0.31 | +0.03 | ±10% / ±0.03 ms | 4.1% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 4.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.28 | 0.31 | +0.03 | ±10% / ±0.03 ms | 8.0% | stable | 🔴 Regression (+11%) |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.10 | 0.10 | +0.01 | ±10% / ±0.02 ms | 7.8% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.51 | 0.56 | +0.05 | ±10% / ±0.06 ms | 2.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.92 | 0.95 | +0.03 | ±10% / ±0.09 ms | 1.9% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.28 | 0.27 | -0.01 | ±10% / ±0.03 ms | 3.3% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.01 | ±106% / ±0.04 ms | 106.1% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.01 | 0.02 | +0.00 | ±150% / ±0.02 ms | 150.0% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | +0.00 | ±109% / ±0.02 ms | 109.1% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.19 | 0.21 | +0.02 | ±22% / ±0.05 ms | 15.4% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.15 | 0.17 | +0.02 | ±14% / ±0.02 ms | 11.3% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.05 | +0.00 | ±13% / ±0.02 ms | 10.4% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.76 | 1.87 | +0.11 | ±10% / ±0.19 ms | 4.6% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.45 | 1.53 | +0.08 | ±10% / ±0.15 ms | 2.9% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.37 | 0.37 | +0.01 | ±10% / ±0.04 ms | 4.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 21.89 | 22.08 | +0.20 | ±17% / ±3.74 ms | 16.9% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 15.07 | 15.41 | +0.34 | ±10% / ±1.54 ms | 3.9% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.88 | 3.91 | +0.03 | ±10% / ±0.39 ms | 2.6% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±75% / ±0.02 ms | 50.0% | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | +0.00 | ±536% / ±0.07 ms | 535.7% | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±1050% / ±0.02 ms | 1050.0% | noisy | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.05 | +0.00 | ±214% / ±0.11 ms | 214.0% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±11% / ±0.02 ms | 11.1% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.38 | 0.40 | +0.03 | ±16% / ±0.06 ms | 15.9% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.09 | +0.00 | ±11% / ±0.02 ms | 11.2% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 4.68 | 5.02 | +0.34 | ±10% / ±0.50 ms | 8.4% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.88 | 0.86 | -0.02 | ±22% / ±0.20 ms | 22.2% | moderate | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.20 | 0.32 | +0.12 | ±75% / ±0.24 ms | 53.9% | noisy | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.20 | 0.32 | +0.12 | ±75% / ±0.24 ms | 53.9% | noisy | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.53 | 0.61 | +0.08 | ±55% / ±0.34 ms | 54.7% | noisy | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.53 | 0.61 | +0.08 | ±55% / ±0.34 ms | 54.7% | noisy | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.04 | +0.01 | ±92% / ±0.04 ms | 92.3% | noisy | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.04 | +0.01 | ±92% / ±0.04 ms | 92.3% | noisy | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.05 | +0.00 | ±24% / ±0.02 ms | 24.5% | noisy | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.05 | +0.00 | ±24% / ±0.02 ms | 24.5% | noisy | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.33 | 4.11 | +0.78 | ±10% / ±0.41 ms | 4.6% | stable | 🔴 Regression (+24%) |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.33 | 4.11 | +0.78 | ±10% / ±0.41 ms | 4.6% | stable | 🔴 Regression (+24%) |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.50 | 2.02 | +0.52 | ±54% / ±1.09 ms | 51.6% | noisy | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.50 | 2.02 | +0.52 | ±54% / ±1.09 ms | 51.6% | noisy | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.08 | 7.14 | +1.05 | ±19% / ±1.37 ms | 17.9% | moderate | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.08 | 7.14 | +1.05 | ±19% / ±1.37 ms | 17.9% | moderate | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.19 | 0.22 | +0.04 | ±523% / ±1.17 ms | 522.8% | stable | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.19 | 0.22 | +0.04 | ±523% / ±1.17 ms | 522.8% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 5.0% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 5.0% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.46 | 0.46 | +0.00 | ±15% / ±0.07 ms | 15.4% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.46 | 0.46 | +0.00 | ±15% / ±0.07 ms | 15.4% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.67 | 4.72 | +0.06 | ±26% / ±1.25 ms | 26.5% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.67 | 4.72 | +0.06 | ±26% / ±1.25 ms | 26.5% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.61 | 0.68 | +0.07 | ±29% / ±0.20 ms | 23.3% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.61 | 0.68 | +0.07 | ±29% / ±0.20 ms | 23.3% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.07 | +0.01 | ±10% / ±0.02 ms | 4.0% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.07 | +0.01 | ±10% / ±0.02 ms | 4.0% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 5.30 | 7.08 | +1.78 | ±11% / ±0.80 ms | 11.3% | stable | 🔴 Regression (+34%) |
| Write Performance / Batched Write Inside Transaction (100... | 5.30 | 7.08 | +1.78 | ±11% / ±0.80 ms | 11.3% | stable | 🔴 Regression (+34%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.43 | 0.51 | +0.09 | ±24% / ±0.12 ms | 20.5% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.43 | 0.51 | +0.09 | ±24% / ±0.12 ms | 20.5% | noisy | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.09 | 0.06 | -0.03 | ±22% / ±0.02 ms | 22.0% | moderate | 🟢 Win (-31%) |
| Write Performance / Interactive Transaction (insert + sel... | 0.09 | 0.06 | -0.03 | ±22% / ±0.02 ms | 22.0% | moderate | 🟢 Win (-31%) |
| Write Performance / Single Inserts (100 sequential) / res... | 1.84 | 2.27 | +0.43 | ±23% / ±0.53 ms | 23.4% | moderate | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.84 | 2.27 | +0.43 | ±23% / ±0.53 ms | 23.4% | moderate | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.20 | +0.02 | ±10% / ±0.02 ms | 7.0% | stable | 🔴 Regression (+12%) |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.20 | +0.02 | ±10% / ±0.02 ms | 7.0% | stable | 🔴 Regression (+12%) |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.12 | +0.01 | ±10% / ±0.02 ms | 4.3% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.12 | +0.01 | ±10% / ±0.02 ms | 4.3% | stable | ⚪ Within noise |

**Summary:** 4 wins, 16 regressions, 133 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.02 | 0.03 | +0.01 MB | ±1.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 2.97 | 0.00 | -2.97 MB | ±8.84 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 3.69 | 0.00 | -3.69 MB | ±4.38 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 0.00 | +0.00 MB | ±2.88 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 0.03 | 0.00 | -0.03 MB | ±2.98 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±1.51 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 14.34 | 8.56 | -5.78 MB | ±6.30 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / resqlite select() | 4.52 | 4.91 | +0.39 MB | ±5.41 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite3 select() | 3.39 | 3.05 | -0.34 MB | ±3.23 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 1.00 | 1.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.06 | 0.06 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 0 wins, 0 regressions, 15 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 3877 | 3429 | -448 | ±100 | 🟢 Fewer re-emits (-448) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 20 | 10 | -10 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 3992 | 3491 | -501 | ±100 | 🔴 Invalidation elided (-501) — writes not firing |

**Granularity summary:** 1 fewer-re-emit, 1 more-re-emit, 4 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


