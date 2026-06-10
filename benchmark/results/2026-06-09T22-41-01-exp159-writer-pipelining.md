# resqlite Benchmark Results

Generated: 2026-06-09T22:41:01.745822

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp159-writer-pipelining`
- Repeats: `5`
- Runtime: `dart-runtime / Dart 3.12.1`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `exp-159-writer-pipelining @ 841e3623f0c0 (dirty)`
- Comparison baseline: `2026-06-08T07-34-23-exp144-sqlite3mc-2-3-5.md`
- Comparison mode: `automatic`
- Comparison baseline compatibility: `incompatible (automatic comparison skipped)`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.021 | 0.025 | 0.002 | 0.002 |
| sqlite3 select() | 0.028 | 0.030 | 0.028 | 0.030 |
| sqlite_async select() | 0.053 | 0.057 | 0.003 | 0.003 |
| drift select() | 0.060 | 0.065 | 0.002 | 0.002 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.074 | 0.078 | 0.015 | 0.016 |
| sqlite3 select() | 0.204 | 0.209 | 0.204 | 0.209 |
| sqlite_async select() | 0.198 | 0.225 | 0.017 | 0.018 |
| drift select() | 0.285 | 0.288 | 0.016 | 0.019 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.575 | 0.587 | 0.148 | 0.155 |
| sqlite3 select() | 1.874 | 1.923 | 1.874 | 1.923 |
| sqlite_async select() | 1.576 | 1.900 | 0.160 | 0.166 |
| drift select() | 2.521 | 2.664 | 0.158 | 0.164 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 7.577 | 24.850 | 1.521 | 1.988 |
| sqlite3 select() | 23.314 | 26.411 | 23.314 | 26.411 |
| sqlite_async select() | 19.667 | 24.951 | 1.649 | 2.641 |
| drift select() | 37.614 | 53.013 | 2.188 | 3.731 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.039 | 0.049 | 0.019 | 0.024 |
| sqlite3 + jsonEncode | 0.047 | 0.049 | 0.047 | 0.049 |
| sqlite_async + jsonEncode | 0.074 | 0.094 | 0.021 | 0.023 |
| drift + jsonEncode | 0.092 | 0.107 | 0.021 | 0.025 |
| resqlite selectBytes() | 0.024 | 0.025 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.247 | 0.279 | 0.184 | 0.208 |
| sqlite3 + jsonEncode | 0.374 | 0.486 | 0.374 | 0.486 |
| sqlite_async + jsonEncode | 0.375 | 0.417 | 0.185 | 0.195 |
| drift + jsonEncode | 0.474 | 0.555 | 0.186 | 0.198 |
| resqlite selectBytes() | 0.086 | 0.110 | 0.000 | 0.001 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 2.369 | 8.157 | 1.841 | 3.848 |
| sqlite3 + jsonEncode | 3.688 | 9.373 | 3.688 | 9.373 |
| sqlite_async + jsonEncode | 3.380 | 10.625 | 1.841 | 4.664 |
| drift + jsonEncode | 4.458 | 11.493 | 1.863 | 3.429 |
| resqlite selectBytes() | 0.695 | 0.764 | 0.000 | 0.002 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 29.313 | 48.967 | 20.690 | 23.676 |
| sqlite3 + jsonEncode | 44.697 | 59.243 | 44.697 | 59.243 |
| sqlite_async + jsonEncode | 47.669 | 58.048 | 20.898 | 23.377 |
| drift + jsonEncode | 68.950 | 73.746 | 21.902 | 32.317 |
| resqlite selectBytes() | 7.605 | 12.499 | 0.007 | 0.314 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.149 | 0.173 | 0.057 | 0.062 |
| sqlite3 | 0.604 | 0.660 | 0.604 | 0.660 |
| sqlite_async | 0.596 | 0.665 | 0.078 | 0.086 |
| drift | 0.894 | 1.141 | 0.073 | 0.080 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.341 | 1.486 | 0.456 | 0.488 |
| sqlite3 | 5.763 | 6.623 | 5.763 | 6.623 |
| sqlite_async | 4.865 | 5.367 | 0.641 | 0.669 |
| drift | 8.124 | 11.192 | 0.646 | 0.698 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.048 | 1.123 | 0.170 | 0.176 |
| sqlite3 | 2.412 | 2.590 | 2.412 | 2.590 |
| sqlite_async | 2.041 | 2.355 | 0.223 | 0.242 |
| drift | 3.221 | 3.764 | 0.228 | 0.239 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.432 | 0.472 | 0.166 | 0.181 |
| sqlite3 | 1.845 | 1.982 | 1.845 | 1.982 |
| sqlite_async | 1.542 | 1.775 | 0.229 | 0.238 |
| drift | 2.689 | 2.816 | 0.235 | 0.250 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.439 | 0.497 | 0.165 | 0.176 |
| sqlite3 | 1.684 | 1.765 | 1.684 | 1.765 |
| sqlite_async | 1.492 | 1.711 | 0.214 | 0.233 |
| drift | 2.472 | 2.629 | 0.212 | 0.233 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.023 | 0.037 | 0.002 | 0.002 |
| sqlite3 | 0.029 | 0.032 | 0.029 | 0.032 |
| sqlite_async | 0.055 | 0.065 | 0.002 | 0.003 |
| drift | 0.079 | 0.120 | 0.002 | 0.005 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.047 | 0.050 | 0.008 | 0.008 |
| sqlite3 | 0.108 | 0.115 | 0.108 | 0.115 |
| sqlite_async | 0.126 | 0.145 | 0.009 | 0.010 |
| drift | 0.165 | 0.197 | 0.009 | 0.010 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.077 | 0.079 | 0.016 | 0.016 |
| sqlite3 | 0.203 | 0.208 | 0.203 | 0.208 |
| sqlite_async | 0.199 | 0.204 | 0.017 | 0.018 |
| drift | 0.329 | 0.412 | 0.018 | 0.023 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.306 | 0.310 | 0.077 | 0.078 |
| sqlite3 | 0.988 | 1.092 | 0.988 | 1.092 |
| sqlite_async | 0.844 | 1.212 | 0.087 | 0.127 |
| drift | 1.418 | 1.621 | 0.086 | 0.113 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.592 | 0.599 | 0.153 | 0.156 |
| sqlite3 | 1.939 | 2.098 | 1.939 | 2.098 |
| sqlite_async | 1.562 | 1.835 | 0.158 | 0.176 |
| drift | 2.567 | 3.052 | 0.160 | 0.169 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.268 | 1.307 | 0.303 | 0.320 |
| sqlite3 | 3.891 | 4.925 | 3.891 | 4.925 |
| sqlite_async | 3.381 | 3.897 | 0.333 | 0.352 |
| drift | 5.481 | 6.460 | 0.330 | 0.354 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.629 | 10.070 | 0.777 | 1.118 |
| sqlite3 | 9.830 | 12.535 | 9.830 | 12.535 |
| sqlite_async | 8.752 | 9.650 | 0.810 | 0.921 |
| drift | 14.021 | 14.873 | 0.814 | 0.857 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 10.488 | 17.942 | 1.533 | 1.927 |
| sqlite3 | 23.310 | 27.406 | 23.310 | 27.406 |
| sqlite_async | 17.186 | 18.678 | 1.560 | 1.612 |
| drift | 31.226 | 40.672 | 1.806 | 4.033 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 20.069 | 28.381 | 3.323 | 3.622 |
| sqlite3 | 58.935 | 62.896 | 58.935 | 62.896 |
| sqlite_async | 58.266 | 72.453 | 4.215 | 5.162 |
| drift | 79.737 | 103.048 | 4.707 | 8.865 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.042 | 0.050 | 0.042 | 0.050 |
| sqlite3 + jsonEncode | 0.047 | 0.050 | 0.047 | 0.050 |
| sqlite_async + jsonEncode | 0.074 | 0.101 | 0.074 | 0.101 |
| drift + jsonEncode | 0.077 | 0.084 | 0.077 | 0.084 |
| resqlite selectBytes() | 0.021 | 0.023 | 0.021 | 0.023 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.130 | 0.133 | 0.130 | 0.133 |
| sqlite3 + jsonEncode | 0.190 | 0.196 | 0.190 | 0.196 |
| sqlite_async + jsonEncode | 0.199 | 0.215 | 0.199 | 0.215 |
| drift + jsonEncode | 0.246 | 0.307 | 0.246 | 0.307 |
| resqlite selectBytes() | 0.052 | 0.065 | 0.052 | 0.065 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.250 | 0.259 | 0.250 | 0.259 |
| sqlite3 + jsonEncode | 0.372 | 0.436 | 0.372 | 0.436 |
| sqlite_async + jsonEncode | 0.362 | 0.368 | 0.362 | 0.368 |
| drift + jsonEncode | 0.463 | 0.526 | 0.463 | 0.526 |
| resqlite selectBytes() | 0.085 | 0.092 | 0.085 | 0.092 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.137 | 1.183 | 1.137 | 1.183 |
| sqlite3 + jsonEncode | 1.777 | 1.850 | 1.777 | 1.850 |
| sqlite_async + jsonEncode | 1.625 | 1.733 | 1.625 | 1.733 |
| drift + jsonEncode | 2.147 | 2.298 | 2.147 | 2.298 |
| resqlite selectBytes() | 0.364 | 0.372 | 0.364 | 0.372 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 2.225 | 2.391 | 2.225 | 2.391 |
| sqlite3 + jsonEncode | 3.639 | 4.243 | 3.639 | 4.243 |
| sqlite_async + jsonEncode | 3.350 | 4.000 | 3.350 | 4.000 |
| drift + jsonEncode | 4.291 | 12.989 | 4.291 | 12.989 |
| resqlite selectBytes() | 0.706 | 0.779 | 0.706 | 0.779 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 5.674 | 12.894 | 5.674 | 12.894 |
| sqlite3 + jsonEncode | 8.320 | 15.367 | 8.320 | 15.367 |
| sqlite_async + jsonEncode | 7.919 | 15.976 | 7.919 | 15.976 |
| drift + jsonEncode | 10.235 | 21.314 | 10.235 | 21.314 |
| resqlite selectBytes() | 1.542 | 2.367 | 1.542 | 2.367 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 19.213 | 23.146 | 19.213 | 23.146 |
| sqlite3 + jsonEncode | 21.224 | 30.114 | 21.224 | 30.114 |
| sqlite_async + jsonEncode | 23.055 | 31.161 | 23.055 | 31.161 |
| drift + jsonEncode | 26.374 | 36.700 | 26.374 | 36.700 |
| resqlite selectBytes() | 4.611 | 9.155 | 4.611 | 9.155 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 37.194 | 42.027 | 37.194 | 42.027 |
| sqlite3 + jsonEncode | 49.154 | 55.191 | 49.154 | 55.191 |
| sqlite_async + jsonEncode | 53.145 | 57.159 | 53.145 | 57.159 |
| drift + jsonEncode | 59.373 | 67.428 | 59.373 | 67.428 |
| resqlite selectBytes() | 7.781 | 11.724 | 7.781 | 11.724 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 63.415 | 68.665 | 63.415 | 68.665 |
| sqlite3 + jsonEncode | 93.069 | 103.809 | 93.069 | 103.809 |
| sqlite_async + jsonEncode | 96.680 | 109.292 | 96.680 | 109.292 |
| drift + jsonEncode | 129.414 | 141.282 | 129.414 | 141.282 |
| resqlite selectBytes() | 17.424 | 18.532 | 17.424 | 18.532 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.43 | 0.47 | 0.43 |
| sqlite_async | 1.39 | 1.50 | 1.39 |
| drift | 2.40 | 2.62 | 2.40 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.46 | 0.47 | 0.23 |
| sqlite_async | 2.07 | 2.54 | 1.03 |
| drift | 4.31 | 4.90 | 2.15 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.49 | 1.09 | 0.12 |
| sqlite_async | 3.38 | 4.16 | 0.85 |
| drift | 8.33 | 8.87 | 2.08 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.95 | 1.69 | 0.12 |
| sqlite_async | 6.89 | 8.73 | 0.86 |
| drift | 17.06 | 17.89 | 2.13 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 70587 |
| resqlite per query | 0.014 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 70587 | 69374..70961 | 1.1 | 2.8 |
| sqlite3 | 96899 | 95503..97507 | 1.0 | 2.4 |
| sqlite_async | 28427 | 28137..28485 | 0.6 | 1.6 |
| drift | 25312 | 24614..25801 | 2.3 | 5.8 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 19.522 | 20.301 | 19.522 | 20.301 |
| sqlite_async | 55.091 | 56.842 | 55.091 | 56.842 |
| drift | 87.359 | 90.241 | 87.359 | 90.241 |
| sqlite3 (no cache) | 44.552 | 45.730 | 44.552 | 45.730 |
| sqlite3 (cached stmt) | 44.407 | 45.157 | 44.407 | 45.157 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 2.412 | 3.019 | 2.412 | 3.019 |
| sqlite3 execute() | 1.401 | 2.092 | 1.401 | 2.092 |
| sqlite_async execute() | 5.530 | 6.387 | 5.530 | 6.387 |
| drift execute() | 4.641 | 5.583 | 4.641 | 5.583 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.073 | 0.075 | 0.073 | 0.075 |
| sqlite3 executeBatch() | 0.087 | 0.092 | 0.087 | 0.092 |
| sqlite_async executeBatch() | 0.156 | 0.167 | 0.156 | 0.167 |
| drift executeBatch() | 0.191 | 0.216 | 0.191 | 0.216 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.529 | 0.597 | 0.529 | 0.597 |
| sqlite3 executeBatch() | 0.778 | 0.818 | 0.778 | 0.818 |
| sqlite_async executeBatch() | 0.795 | 0.815 | 0.795 | 0.815 |
| drift executeBatch() | 1.086 | 1.097 | 1.086 | 1.097 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 5.350 | 5.978 | 5.350 | 5.978 |
| sqlite3 executeBatch() | 7.748 | 8.226 | 7.748 | 8.226 |
| sqlite_async executeBatch() | 7.843 | 9.304 | 7.843 | 9.304 |
| drift executeBatch() | 10.558 | 15.210 | 10.558 | 15.210 |

### Wide Batch Insert (10000 rows x 20 params)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 18.064 | 38.405 | 18.064 | 38.405 |
| sqlite3 executeBatch() | 37.815 | 40.672 | 37.815 | 40.672 |
| sqlite_async executeBatch() | 42.155 | 56.487 | 42.155 | 56.487 |
| drift executeBatch() | 50.122 | 55.048 | 50.122 | 55.048 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.117 | 0.222 | 0.117 | 0.222 |
| sqlite_async writeTransaction() | 0.172 | 0.259 | 0.172 | 0.259 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.104 | 0.135 | 0.104 | 0.135 |
| resqlite tx.execute() loop | 1.374 | 1.587 | 1.374 | 1.587 |
| sqlite_async tx.execute() loop | 2.313 | 2.674 | 2.313 | 2.674 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.612 | 0.724 | 0.612 | 0.724 |
| resqlite tx.execute() loop | 11.145 | 13.057 | 11.145 | 13.057 |
| sqlite_async tx.execute() loop | 23.274 | 25.236 | 23.274 | 25.236 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.172 | 0.223 | 0.172 | 0.223 |
| sqlite_async tx.getAll() | 0.344 | 0.376 | 0.344 | 0.376 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.266 | 0.331 | 0.266 | 0.331 |
| sqlite_async tx.getAll() | 0.610 | 0.692 | 0.610 | 0.692 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 1.428 | 1.776 | 1.428 | 1.776 |
| resqlite nested transaction() depth=5 | 0.151 | 0.188 | 0.151 | 0.188 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.052 | 0.063 | 0.052 | 0.063 |
| sqlite_async watch() | 0.200 | 0.234 | 0.200 | 0.234 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.101 | 0.196 | 0.101 | 0.196 |
| sqlite_async | 0.130 | 0.362 | 0.130 | 0.362 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.267 | 0.340 | 0.267 | 0.340 |
| sqlite_async | 0.712 | 1.606 | 0.712 | 1.606 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.133 | 3.937 | 3.133 | 3.937 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.281 | 0.344 | 0.281 | 0.344 |
| sqlite_async | 0.392 | 0.659 | 0.392 | 0.659 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.726 | 2.726 | 2.726 | 2.726 |
| sqlite_async | 13.511 | 13.511 | 13.511 | 13.511 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 5.587 | 6.640 | 5.587 | 6.640 |
| sqlite_async | 11.196 | 13.044 | 11.196 | 13.044 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.824 | 1.113 | 0.824 | 1.113 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.398 | 15.656 | 14.398 | 15.656 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. For resqlite, this emission metric can reflect writer-side column-level invalidation, experiment 075's native result-hash short-circuit, or both. Use A11c (Many-Streams Writer Throughput) when the question is specifically writer-side dispatch elision.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 76.6 | 0.000 |
| sqlite_async | 4108 | 1728.0 | 0.949 |
| drift | 5000 | 1563.5 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 79.4 | 0.000 |
| sqlite_async | 4331 | 1790.5 | 0.949 |
| drift | 5000 | 1527.2 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 218.84 | 219.26 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 442.43 | 442.95 | 0.00 | 0.00 | 1187 | 3 |
| drift stream() | 603.67 | 624.77 | 0.01 | 0.01 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.030 | 0.039 | 0.000 | 0.000 |
| sqlite3 | 0.025 | 0.031 | 0.025 | 0.031 |
| sqlite_async | 0.063 | 0.083 | 0.000 | 0.000 |
| drift | 0.060 | 0.080 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.025 | 0.030 | 0.000 | 0.000 |
| sqlite3 | 0.017 | 0.021 | 0.017 | 0.021 |
| sqlite_async | 0.052 | 0.071 | 0.000 | 0.000 |
| drift | 0.051 | 0.063 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.041 | 0.065 | 0.000 | 0.000 |
| sqlite3 | 0.051 | 0.054 | 0.051 | 0.054 |
| sqlite_async | 0.089 | 0.105 | 0.001 | 0.001 |
| drift | 0.087 | 0.096 | 0.001 | 0.001 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.015 | 0.038 | 0.000 | 0.000 |
| sqlite3 | 0.010 | 0.011 | 0.010 | 0.011 |
| sqlite_async | 0.038 | 0.047 | 0.000 | 0.000 |
| drift | 0.037 | 0.044 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.066 | 0.075 | 0.001 | 0.001 |
| sqlite3 | 0.113 | 0.119 | 0.113 | 0.119 |
| sqlite_async | 0.129 | 0.135 | 0.002 | 0.002 |
| drift | 0.148 | 0.155 | 0.002 | 0.002 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 107.161 | 108.547 | 0.000 | 0.000 | 0 |
| sqlite_async | 215.203 | 215.314 | 0.000 | 0.000 | 43 |
| drift | 226.529 | 227.329 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 436.35 | 436.35 | 0.00 | 0.00 | 13.54 | 422.81 | 2 |
| sqlite_async | 481.96 | 481.96 | 0.00 | 0.00 | 12.41 | 469.55 | 1194 |
| drift | 2493.03 | 2493.03 | 0.02 | 0.02 | 13.71 | 2479.32 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 4.30 | 21.62 | 0.75..12.99 | ±6.12 |
| sqlite3 select() | 3.60 | 10.52 | 0.00..10.17 | ±5.08 |
| sqlite_async select() | 1.00 | 1.12 | 0.99..1.00 | ±0.01 |
| drift select() | 4.68 | 41.78 | 0.95..20.96 | ±10.01 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.66 | 6.36 | 0.64..1.68 | ±0.52 |
| resqlite + jsonEncode | 6.55 | 85.16 | 0.00..25.68 | ±12.84 |
| sqlite3 + jsonEncode | 0.00 | 38.88 | 0.00..0.00 | ±0.00 |
| sqlite_async + jsonEncode | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| drift + jsonEncode | 0.00 | 61.61 | 0.00..11.25 | ±5.62 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 2.00 | 31.49 | 0.61..7.55 | ±3.47 |
| sqlite3 executeBatch() | 0.00 | 0.48 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| drift batch() | 0.03 | 4.54 | 0.00..2.01 | ±1.00 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.07 | 0.12 | 0.00..0.09 | ±0.04 |
| sqlite_async watch() | 0.00 | 0.52 | 0.00..0.52 | ±0.26 |

## SQLite Diagnostics

resqlite-only internal SQLite counters captured via `Database.diagnostics()` after representative workloads. Values reflect the writer plus idle readers in this connection pool; they are not process-global SQLite totals.

### Warm read working set (20000 rows + 2000 point lookups)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | Readers busy |
|---|---|---|---|---|---|---|
| resqlite | 3210.4 | 3189.5 | 5.3 | 15.6 | 2048.0 | 0 |

### Statement cache footprint (48 distinct SELECT texts)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | Readers busy |
|---|---|---|---|---|---|---|
| resqlite | 3299.6 | 3189.5 | 5.3 | 104.8 | 2048.0 | 0 |

### WAL after write burst (1000 inserted rows)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | Readers busy |
|---|---|---|---|---|---|---|
| resqlite | 260.9 | 240.0 | 5.3 | 15.6 | 161.0 | 0 |

## Repeat Stability

These rows summarize resqlite wall medians across repeated full-suite runs.
Use this section to judge whether small deltas are real or just noise.

| Benchmark | Median (ms) | 95% CI (ms) | MDE_ci | Range | MAD | Stability |
|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.04 | 0.04..0.04 | 2.3% | 4.7% | 0.0% | stable |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.02 | 0.01..0.02 | 6.3% | 12.5% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.03 | 0.03..0.04 | 9.1% | 18.2% | 6.1% | moderate |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.03 | 0.03..0.03 | 7.4% | 14.8% | 3.7% | moderate |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.43 | 0.43..0.44 | 1.2% | 2.3% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.43 | 0.43..0.44 | 1.2% | 2.3% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.47 | 0.45..0.48 | 3.2% | 6.4% | 2.1% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.24 | 0.22..0.24 | 4.2% | 8.3% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.51 | 0.49..0.55 | 5.9% | 11.8% | 3.9% | moderate |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.13 | 0.12..0.14 | 7.7% | 15.4% | 7.7% | moderate |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 1.03 | 0.95..1.09 | 6.8% | 13.6% | 4.9% | moderate |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.13 | 0.12..0.14 | 7.7% | 15.4% | 7.7% | moderate |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.07 | 0.06..0.07 | 9.8% | 19.7% | 6.1% | moderate |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.01 | 200.0% | 400.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 106.76 | 105.38..107.16 | 0.8% | 1.7% | 0.4% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 234.29 | 232.77..436.35 | 43.4% | 86.9% | 0.4% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 218.84 | 217.55..219.59 | 0.5% | 0.9% | 0.3% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 20.05 | 19.52..20.39 | 2.2% | 4.3% | 1.7% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 20.05 | 19.52..20.39 | 2.2% | 4.3% | 1.7% | stable |
| Point Query Throughput / resqlite qps | 63833.00 | 53466.00..70587.00 | 13.4% | 26.8% | 5.0% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.02 | 0.02..0.03 | 13.0% | 26.1% | 4.3% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.04 | 0.04..0.05 | 15.5% | 31.0% | 4.8% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.04 | 0.04..0.05 | 15.5% | 31.0% | 4.8% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 25.0% | 50.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.02 | 0.02..0.03 | 8.7% | 17.4% | 8.7% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.02 | 0.02..0.03 | 8.7% | 17.4% | 8.7% | noisy |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.07 | 0.07..0.08 | 2.7% | 5.4% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.25 | 0.24..0.25 | 2.6% | 5.2% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.25 | 0.24..0.25 | 2.6% | 5.2% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.02 | 3.3% | 6.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.09 | 0.08..0.09 | 4.1% | 8.2% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.09 | 0.08..0.09 | 4.1% | 8.2% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.58 | 0.57..0.60 | 2.8% | 5.7% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 2.24 | 2.22..2.37 | 3.2% | 6.4% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 2.24 | 2.22..2.37 | 3.2% | 6.4% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.15 | 0.15..0.15 | 2.3% | 4.6% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.71 | 0.69..0.71 | 1.3% | 2.7% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.71 | 0.69..0.71 | 1.3% | 2.7% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 9.07 | 7.71..11.19 | 19.2% | 38.4% | 15.0% | noisy |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 28.27 | 27.47..37.19 | 17.2% | 34.4% | 2.8% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 28.27 | 27.47..37.19 | 17.2% | 34.4% | 2.8% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 1.76 | 1.53..1.80 | 7.7% | 15.4% | 2.4% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 6.93 | 6.86..7.78 | 6.6% | 13.2% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 6.93 | 6.86..7.78 | 6.6% | 13.2% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 1.29 | 1.25..1.33 | 2.9% | 5.8% | 2.8% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 5.85 | 5.58..10.19 | 39.4% | 78.8% | 4.7% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 5.85 | 5.58..10.19 | 39.4% | 78.8% | 4.7% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.31 | 0.30..0.32 | 3.6% | 7.2% | 1.3% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 1.62 | 1.54..1.64 | 3.0% | 6.0% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 1.62 | 1.54..1.64 | 3.0% | 6.0% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 20.37 | 20.07..23.54 | 8.5% | 17.0% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 64.56 | 62.63..65.53 | 2.2% | 4.5% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 64.56 | 62.63..65.53 | 2.2% | 4.5% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 3.42 | 3.32..3.50 | 2.5% | 5.0% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 15.56 | 13.65..17.42 | 12.1% | 24.3% | 9.0% | noisy |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 15.56 | 13.65..17.42 | 12.1% | 24.3% | 9.0% | noisy |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.05 | 0.04..0.05 | 6.1% | 12.2% | 4.1% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.13 | 0.13..0.14 | 2.7% | 5.4% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.13 | 0.13..0.14 | 2.7% | 5.4% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.05 | 0.05..0.05 | 3.8% | 7.7% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.05 | 0.05..0.05 | 3.8% | 7.7% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.30 | 0.29..0.31 | 2.2% | 4.3% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 1.14 | 1.13..1.23 | 4.3% | 8.6% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 1.14 | 1.13..1.23 | 4.3% | 8.6% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.08 | 0.07..0.08 | 2.0% | 3.9% | 1.3% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.36 | 0.35..0.37 | 2.8% | 5.6% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.36 | 0.35..0.37 | 2.8% | 5.6% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 3.63 | 3.48..3.96 | 6.6% | 13.1% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 19.21 | 13.07..21.12 | 20.9% | 41.9% | 3.6% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 19.21 | 13.07..21.12 | 20.9% | 41.9% | 3.6% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.76 | 0.75..0.79 | 2.4% | 4.9% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 3.95 | 3.85..4.61 | 9.6% | 19.1% | 2.4% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 3.95 | 3.85..4.61 | 9.6% | 19.1% | 2.4% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.16 | 0.15..0.21 | 20.3% | 40.6% | 5.6% | moderate |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.06 | 0.06..0.12 | 52.5% | 104.9% | 1.6% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.44 | 0.42..0.45 | 3.0% | 5.9% | 2.1% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.17 | 0.16..0.17 | 3.3% | 6.7% | 1.2% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.43 | 0.42..0.45 | 3.1% | 6.3% | 1.9% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.17 | 0.16..0.17 | 3.0% | 6.1% | 0.6% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 1.02 | 0.95..1.08 | 6.3% | 12.7% | 2.3% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.17 | 0.16..0.17 | 3.3% | 6.6% | 2.4% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 1.31 | 1.29..1.37 | 3.3% | 6.7% | 2.1% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.45 | 0.44..0.47 | 3.5% | 6.9% | 2.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.04 | 0.04..0.09 | 70.5% | 141.0% | 2.6% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02..0.05 | 78.9% | 157.9% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.02 | 0.02..0.04 | 31.3% | 62.5% | 8.3% | noisy |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.25 | 0.24..0.31 | 13.4% | 26.7% | 0.8% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.18 | 0.18..0.23 | 13.0% | 26.1% | 0.5% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.09 | 0.09..0.10 | 6.1% | 12.2% | 4.4% | moderate |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 2.37 | 2.32..2.46 | 3.1% | 6.2% | 2.2% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.84 | 1.81..1.93 | 3.4% | 6.8% | 1.7% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.70 | 0.69..0.74 | 3.0% | 6.0% | 1.4% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 30.70 | 29.31..37.24 | 12.9% | 25.8% | 4.5% | moderate |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 20.90 | 19.72..21.17 | 3.5% | 6.9% | 1.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 7.47 | 7.23..11.28 | 27.1% | 54.3% | 2.9% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.07 | 383.3% | 766.7% | 22.2% | noisy |
| Select → Maps / 10 rows / resqlite select() | 0.02 | 0.02..0.13 | 245.7% | 491.3% | 8.7% | noisy |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.03 | 650.0% | 1300.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.07 | 0.07..0.21 | 93.2% | 186.5% | 1.4% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.02 | 13.3% | 26.7% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.58 | 0.57..0.64 | 6.3% | 12.6% | 1.9% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.15 | 0.14..0.15 | 2.0% | 4.1% | 0.0% | stable |
| Select → Maps / 10000 rows / resqlite select() | 10.44 | 7.47..11.96 | 21.5% | 43.0% | 14.6% | noisy |
| Select → Maps / 10000 rows / resqlite select() [main] | 1.77 | 1.49..1.90 | 11.4% | 22.9% | 7.2% | moderate |
| Streaming / Fan-out (10 streams) / resqlite | 0.29 | 0.28..0.66 | 67.4% | 134.8% | 3.5% | moderate |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.29 | 0.28..0.66 | 67.4% | 134.8% | 3.5% | moderate |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.73 | 0.70..0.82 | 8.3% | 16.6% | 3.6% | moderate |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.73 | 0.70..0.82 | 8.3% | 16.6% | 3.6% | moderate |
| Streaming / Initial Emission / resqlite stream() | 0.05 | 0.04..0.13 | 76.9% | 153.8% | 7.7% | moderate |
| Streaming / Initial Emission / resqlite stream() [main] | 0.05 | 0.04..0.13 | 76.9% | 153.8% | 7.7% | moderate |
| Streaming / Invalidation Latency / resqlite | 0.10 | 0.08..0.14 | 28.2% | 56.4% | 16.8% | noisy |
| Streaming / Invalidation Latency / resqlite [main] | 0.10 | 0.08..0.14 | 28.2% | 56.4% | 16.8% | noisy |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 3.13 | 2.88..3.80 | 14.8% | 29.5% | 7.1% | moderate |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 3.13 | 2.88..3.80 | 14.8% | 29.5% | 7.1% | moderate |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 5.30 | 5.09..5.59 | 4.7% | 9.4% | 0.7% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 5.30 | 5.09..5.59 | 4.7% | 9.4% | 0.7% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 3.59 | 2.73..5.08 | 32.7% | 65.4% | 16.8% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 3.59 | 2.73..5.08 | 32.7% | 65.4% | 16.8% | noisy |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 14.40 | 13.00..15.13 | 7.4% | 14.7% | 5.0% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 14.40 | 13.00..15.13 | 7.4% | 14.7% | 5.0% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.29 | 0.27..0.35 | 14.4% | 28.7% | 3.8% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.29 | 0.27..0.35 | 14.4% | 28.7% | 3.8% | moderate |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.08 | 0.07..0.08 | 4.5% | 9.0% | 1.3% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.08 | 0.07..0.08 | 4.5% | 9.0% | 1.3% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.55 | 0.53..0.56 | 3.2% | 6.4% | 2.6% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.55 | 0.53..0.56 | 3.2% | 6.4% | 2.6% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 5.59 | 5.35..5.68 | 3.0% | 5.9% | 1.6% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 5.59 | 5.35..5.68 | 3.0% | 5.9% | 1.6% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 1.22 | 1.09..1.52 | 17.5% | 35.0% | 10.7% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 1.22 | 1.09..1.52 | 17.5% | 35.0% | 10.7% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.10 | 0.09..0.13 | 16.8% | 33.7% | 2.9% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.10 | 0.09..0.13 | 16.8% | 33.7% | 2.9% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 11.51 | 11.14..13.97 | 12.3% | 24.6% | 2.2% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 11.51 | 11.14..13.97 | 12.3% | 24.6% | 2.2% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.60 | 0.58..0.62 | 3.2% | 6.3% | 1.5% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.60 | 0.58..0.62 | 3.2% | 6.3% | 1.5% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.10 | 0.08..0.12 | 17.6% | 35.3% | 14.7% | noisy |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.10 | 0.08..0.12 | 17.6% | 35.3% | 14.7% | noisy |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.15 | 0.14..0.22 | 26.8% | 53.6% | 9.9% | noisy |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.15 | 0.14..0.22 | 26.8% | 53.6% | 9.9% | noisy |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 1.76 | 1.43..2.26 | 23.7% | 47.4% | 18.9% | noisy |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 1.76 | 1.43..2.26 | 23.7% | 47.4% | 18.9% | noisy |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 2.69 | 2.41..2.92 | 9.4% | 18.9% | 5.9% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 2.69 | 2.41..2.92 | 9.4% | 18.9% | 5.9% | moderate |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.27 | 0.26..0.27 | 1.9% | 3.8% | 0.4% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.27 | 0.26..0.27 | 1.9% | 3.8% | 0.4% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.16 | 0.14..0.17 | 8.6% | 17.3% | 3.1% | moderate |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.16 | 0.14..0.17 | 8.6% | 17.3% | 3.1% | moderate |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 18.46 | 18.06..18.68 | 1.7% | 3.3% | 0.4% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 18.46 | 18.06..18.68 | 1.7% | 3.3% | 0.4% | stable |


## Comparison

Automatic comparison skipped because `2026-06-08T07-34-23-exp144-sqlite3mc-2-3-5.md` was not captured in a compatible environment:
- runtime differs: current `dart-runtime` vs baseline `dart-vm`
- dartVersion differs: current `3.12.1` vs baseline `3.11.5`

Use `--compare-to=benchmark/results/2026-06-08T07-34-23-exp144-sqlite3mc-2-3-5.md` to run an explicit reference comparison anyway.
