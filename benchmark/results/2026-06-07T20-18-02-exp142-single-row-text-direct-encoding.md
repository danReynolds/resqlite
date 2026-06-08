# resqlite Benchmark Results

Generated: 2026-06-07T20:18:02.155203

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp142-single-row-text-direct-encoding`
- Repeats: `1`
- Runtime: `dart-vm / Dart 3.11.5`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `exp-142-single-row-text-direct-encoding @ 8c91b32fe6ef (dirty)`
- Comparison baseline: `2026-05-02T07-25-17-exp120-flush-admit-bound.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.087 | 0.594 | 0.022 | 0.079 |
| sqlite3 select() | 0.395 | 1.947 | 0.395 | 1.947 |
| sqlite_async select() | 0.273 | 1.238 | 0.025 | 0.054 |
| drift select() | 0.368 | 1.260 | 0.020 | 0.066 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.083 | 0.193 | 0.010 | 0.017 |
| sqlite3 select() | 0.255 | 0.543 | 0.255 | 0.543 |
| sqlite_async select() | 0.439 | 1.052 | 0.021 | 0.041 |
| drift select() | 0.491 | 0.860 | 0.023 | 0.032 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.464 | 0.665 | 0.078 | 0.085 |
| sqlite3 select() | 1.305 | 1.895 | 1.305 | 1.895 |
| sqlite_async select() | 1.642 | 2.586 | 0.110 | 0.140 |
| drift select() | 2.397 | 4.227 | 0.113 | 0.149 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 6.910 | 16.426 | 0.741 | 2.036 |
| sqlite3 select() | 22.740 | 30.931 | 22.740 | 30.931 |
| sqlite_async select() | 16.891 | 25.729 | 0.900 | 2.849 |
| drift select() | 30.444 | 45.750 | 0.931 | 4.774 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.097 | 0.180 | 0.073 | 0.096 |
| sqlite3 + jsonEncode | 0.052 | 0.057 | 0.052 | 0.057 |
| sqlite_async + jsonEncode | 0.191 | 0.344 | 0.040 | 0.067 |
| drift + jsonEncode | 0.130 | 0.260 | 0.030 | 0.072 |
| resqlite selectBytes() | 0.022 | 0.030 | 0.000 | 0.002 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.252 | 0.395 | 0.187 | 0.269 |
| sqlite3 + jsonEncode | 0.303 | 0.485 | 0.303 | 0.485 |
| sqlite_async + jsonEncode | 0.938 | 3.593 | 0.231 | 1.283 |
| drift + jsonEncode | 0.577 | 1.397 | 0.193 | 0.286 |
| resqlite selectBytes() | 0.056 | 0.100 | 0.000 | 0.002 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 2.452 | 6.726 | 1.911 | 3.743 |
| sqlite3 + jsonEncode | 3.089 | 7.421 | 3.089 | 7.421 |
| sqlite_async + jsonEncode | 3.670 | 7.448 | 1.854 | 5.016 |
| drift + jsonEncode | 4.501 | 20.883 | 1.723 | 7.434 |
| resqlite selectBytes() | 0.409 | 0.632 | 0.001 | 0.005 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 27.189 | 40.231 | 18.147 | 24.212 |
| sqlite3 + jsonEncode | 37.873 | 62.106 | 37.873 | 62.106 |
| sqlite_async + jsonEncode | 42.578 | 53.059 | 17.382 | 25.999 |
| drift + jsonEncode | 58.334 | 82.912 | 20.072 | 27.311 |
| resqlite selectBytes() | 4.254 | 8.917 | 0.006 | 0.011 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.139 | 0.373 | 0.040 | 0.292 |
| sqlite3 | 0.384 | 0.921 | 0.384 | 0.921 |
| sqlite_async | 0.458 | 0.982 | 0.047 | 0.071 |
| drift | 0.820 | 1.625 | 0.059 | 0.072 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.151 | 1.797 | 0.419 | 0.678 |
| sqlite3 | 3.867 | 4.806 | 3.867 | 4.806 |
| sqlite_async | 3.852 | 4.815 | 0.383 | 0.483 |
| drift | 7.166 | 15.201 | 0.391 | 0.805 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.034 | 1.976 | 0.158 | 0.456 |
| sqlite3 | 1.792 | 2.317 | 1.792 | 2.317 |
| sqlite_async | 1.958 | 2.504 | 0.146 | 0.178 |
| drift | 2.607 | 3.146 | 0.150 | 0.204 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.367 | 0.520 | 0.150 | 0.160 |
| sqlite3 | 1.281 | 2.341 | 1.281 | 2.341 |
| sqlite_async | 1.366 | 1.751 | 0.138 | 0.174 |
| drift | 1.908 | 2.784 | 0.147 | 0.190 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.397 | 0.863 | 0.155 | 0.301 |
| sqlite3 | 1.117 | 1.406 | 1.117 | 1.406 |
| sqlite_async | 1.320 | 1.678 | 0.135 | 0.155 |
| drift | 1.873 | 2.240 | 0.143 | 0.166 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.020 | 0.026 | 0.002 | 0.003 |
| sqlite3 | 0.023 | 0.024 | 0.023 | 0.024 |
| sqlite_async | 0.084 | 0.180 | 0.005 | 0.014 |
| drift | 0.086 | 0.379 | 0.006 | 0.033 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.038 | 0.040 | 0.007 | 0.008 |
| sqlite3 | 0.071 | 0.133 | 0.071 | 0.133 |
| sqlite_async | 0.142 | 0.247 | 0.008 | 0.015 |
| drift | 0.195 | 0.249 | 0.012 | 0.018 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.062 | 0.272 | 0.015 | 0.040 |
| sqlite3 | 0.132 | 0.284 | 0.132 | 0.284 |
| sqlite_async | 0.165 | 0.296 | 0.010 | 0.016 |
| drift | 0.295 | 0.410 | 0.015 | 0.026 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.239 | 0.292 | 0.072 | 0.076 |
| sqlite3 | 0.634 | 0.973 | 0.634 | 0.973 |
| sqlite_async | 0.765 | 0.987 | 0.054 | 0.069 |
| drift | 1.067 | 1.509 | 0.055 | 0.067 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.467 | 0.998 | 0.143 | 0.157 |
| sqlite3 | 1.385 | 2.004 | 1.385 | 2.004 |
| sqlite_async | 1.731 | 3.174 | 0.104 | 0.193 |
| drift | 2.175 | 3.112 | 0.105 | 0.163 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.130 | 1.733 | 0.291 | 0.381 |
| sqlite3 | 2.603 | 3.389 | 2.603 | 3.389 |
| sqlite_async | 2.892 | 3.297 | 0.187 | 0.245 |
| drift | 3.942 | 5.683 | 0.183 | 0.237 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.780 | 8.724 | 0.743 | 1.072 |
| sqlite3 | 6.262 | 8.988 | 6.262 | 8.988 |
| sqlite_async | 7.315 | 9.807 | 0.430 | 0.588 |
| drift | 11.219 | 16.550 | 0.421 | 0.521 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 5.803 | 15.806 | 1.451 | 2.959 |
| sqlite3 | 16.931 | 20.941 | 16.931 | 20.941 |
| sqlite_async | 16.911 | 23.410 | 0.824 | 3.092 |
| drift | 28.765 | 41.414 | 0.843 | 2.826 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 15.220 | 34.684 | 3.001 | 5.995 |
| sqlite3 | 58.502 | 98.348 | 58.502 | 98.348 |
| sqlite_async | 48.380 | 73.946 | 1.730 | 10.383 |
| drift | 53.636 | 84.522 | 1.628 | 9.472 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.055 | 0.253 | 0.055 | 0.253 |
| sqlite3 + jsonEncode | 0.039 | 0.051 | 0.039 | 0.051 |
| sqlite_async + jsonEncode | 0.076 | 0.846 | 0.076 | 0.846 |
| drift + jsonEncode | 0.074 | 0.933 | 0.074 | 0.933 |
| resqlite selectBytes() | 0.020 | 0.090 | 0.020 | 0.090 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.116 | 0.558 | 0.116 | 0.558 |
| sqlite3 + jsonEncode | 0.156 | 0.306 | 0.156 | 0.306 |
| sqlite_async + jsonEncode | 0.191 | 0.420 | 0.191 | 0.420 |
| drift + jsonEncode | 0.304 | 0.859 | 0.304 | 0.859 |
| resqlite selectBytes() | 0.060 | 0.177 | 0.060 | 0.177 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.235 | 0.375 | 0.235 | 0.375 |
| sqlite3 + jsonEncode | 0.288 | 0.866 | 0.288 | 0.866 |
| sqlite_async + jsonEncode | 0.494 | 0.964 | 0.494 | 0.964 |
| drift + jsonEncode | 0.436 | 0.546 | 0.436 | 0.546 |
| resqlite selectBytes() | 0.052 | 0.055 | 0.052 | 0.055 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.140 | 1.602 | 1.140 | 1.602 |
| sqlite3 + jsonEncode | 1.881 | 3.468 | 1.881 | 3.468 |
| sqlite_async + jsonEncode | 2.413 | 4.432 | 2.413 | 4.432 |
| drift + jsonEncode | 2.032 | 2.874 | 2.032 | 2.874 |
| resqlite selectBytes() | 0.202 | 0.284 | 0.202 | 0.284 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 2.202 | 3.083 | 2.202 | 3.083 |
| sqlite3 + jsonEncode | 3.012 | 3.882 | 3.012 | 3.882 |
| sqlite_async + jsonEncode | 3.242 | 3.985 | 3.242 | 3.985 |
| drift + jsonEncode | 3.816 | 5.297 | 3.816 | 5.297 |
| resqlite selectBytes() | 0.380 | 0.736 | 0.380 | 0.736 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 5.850 | 12.050 | 5.850 | 12.050 |
| sqlite3 + jsonEncode | 6.939 | 17.936 | 6.939 | 17.936 |
| sqlite_async + jsonEncode | 7.892 | 15.716 | 7.892 | 15.716 |
| drift + jsonEncode | 9.240 | 21.509 | 9.240 | 21.509 |
| resqlite selectBytes() | 1.169 | 3.461 | 1.169 | 3.461 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 12.142 | 19.250 | 12.142 | 19.250 |
| sqlite3 + jsonEncode | 20.593 | 31.207 | 20.593 | 31.207 |
| sqlite_async + jsonEncode | 20.496 | 32.390 | 20.496 | 32.390 |
| drift + jsonEncode | 26.575 | 40.368 | 26.575 | 40.368 |
| resqlite selectBytes() | 2.236 | 4.859 | 2.236 | 4.859 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 28.060 | 31.928 | 28.060 | 31.928 |
| sqlite3 + jsonEncode | 40.392 | 61.325 | 40.392 | 61.325 |
| sqlite_async + jsonEncode | 40.774 | 56.368 | 40.774 | 56.368 |
| drift + jsonEncode | 46.090 | 64.152 | 46.090 | 64.152 |
| resqlite selectBytes() | 4.224 | 8.768 | 4.224 | 8.768 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 49.883 | 54.874 | 49.883 | 54.874 |
| sqlite3 + jsonEncode | 83.552 | 109.980 | 83.552 | 109.980 |
| sqlite_async + jsonEncode | 89.988 | 120.923 | 89.988 | 120.923 |
| drift + jsonEncode | 121.578 | 160.563 | 121.578 | 160.563 |
| resqlite selectBytes() | 15.674 | 30.018 | 15.674 | 30.018 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.32 | 0.89 | 0.32 |
| sqlite_async | 1.53 | 3.95 | 1.53 |
| drift | 2.59 | 4.62 | 2.59 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.94 | 1.80 | 0.47 |
| sqlite_async | 2.47 | 3.29 | 1.24 |
| drift | 4.21 | 7.64 | 2.11 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.96 | 1.95 | 0.24 |
| sqlite_async | 3.54 | 7.39 | 0.89 |
| drift | 6.62 | 8.14 | 1.66 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 1.10 | 4.23 | 0.14 |
| sqlite_async | 5.70 | 7.66 | 0.71 |
| drift | 12.85 | 15.71 | 1.61 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 98371 |
| resqlite per query | 0.010 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 98371 | 94707..104088 | 4.8 | 13.3 |
| sqlite3 | 181068 | 179777..181560 | 0.5 | 1.9 |
| sqlite_async | 34517 | 32510..36175 | 5.3 | 17.0 |
| drift | 33960 | 28337..36903 | 12.6 | 32.5 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 17.287 | 24.399 | 17.287 | 24.399 |
| sqlite_async | 45.897 | 62.904 | 45.897 | 62.904 |
| drift | 65.568 | 71.859 | 65.568 | 71.859 |
| sqlite3 (no cache) | 31.594 | 37.060 | 31.594 | 37.060 |
| sqlite3 (cached stmt) | 32.139 | 39.705 | 32.139 | 39.705 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 2.534 | 4.258 | 2.534 | 4.258 |
| sqlite3 execute() | 1.065 | 2.449 | 1.065 | 2.449 |
| sqlite_async execute() | 4.032 | 5.599 | 4.032 | 5.599 |
| drift execute() | 5.422 | 9.144 | 5.422 | 9.144 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.057 | 0.064 | 0.057 | 0.064 |
| sqlite3 executeBatch() | 0.051 | 0.055 | 0.051 | 0.055 |
| sqlite_async executeBatch() | 0.116 | 0.214 | 0.116 | 0.214 |
| drift executeBatch() | 0.169 | 0.306 | 0.169 | 0.306 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.444 | 0.909 | 0.444 | 0.909 |
| sqlite3 executeBatch() | 0.455 | 0.489 | 0.455 | 0.489 |
| sqlite_async executeBatch() | 0.576 | 0.875 | 0.576 | 0.875 |
| drift executeBatch() | 0.879 | 1.207 | 0.879 | 1.207 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 6.129 | 12.063 | 6.129 | 12.063 |
| sqlite3 executeBatch() | 5.402 | 8.828 | 5.402 | 8.828 |
| sqlite_async executeBatch() | 6.833 | 9.910 | 6.833 | 9.910 |
| drift executeBatch() | 10.197 | 18.815 | 10.197 | 18.815 |

### Wide Batch Insert (10000 rows x 20 params)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 22.493 | 50.316 | 22.493 | 50.316 |
| sqlite3 executeBatch() | 32.941 | 47.308 | 32.941 | 47.308 |
| sqlite_async executeBatch() | 33.720 | 72.381 | 33.720 | 72.381 |
| drift executeBatch() | 34.485 | 46.068 | 34.485 | 46.068 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.066 | 0.119 | 0.066 | 0.119 |
| sqlite_async writeTransaction() | 0.149 | 0.326 | 0.149 | 0.326 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.088 | 0.277 | 0.088 | 0.277 |
| resqlite tx.execute() loop | 0.944 | 1.250 | 0.944 | 1.250 |
| sqlite_async tx.execute() loop | 1.757 | 2.309 | 1.757 | 2.309 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.481 | 0.798 | 0.481 | 0.798 |
| resqlite tx.execute() loop | 9.013 | 11.148 | 9.013 | 11.148 |
| sqlite_async tx.execute() loop | 16.457 | 18.354 | 16.457 | 18.354 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.109 | 0.192 | 0.109 | 0.192 |
| sqlite_async tx.getAll() | 0.228 | 0.327 | 0.228 | 0.327 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.212 | 0.450 | 0.212 | 0.450 |
| sqlite_async tx.getAll() | 0.383 | 0.521 | 0.383 | 0.521 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 1.557 | 1.963 | 1.557 | 1.963 |
| resqlite nested transaction() depth=5 | 0.130 | 0.168 | 0.130 | 0.168 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.104 | 0.166 | 0.104 | 0.166 |
| sqlite_async watch() | 0.162 | 0.573 | 0.162 | 0.573 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.082 | 0.201 | 0.082 | 0.201 |
| sqlite_async | 0.095 | 0.215 | 0.095 | 0.215 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.308 | 0.454 | 0.308 | 0.454 |
| sqlite_async | 1.015 | 1.950 | 1.015 | 1.950 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.255 | 6.719 | 3.255 | 6.719 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.334 | 0.586 | 0.334 | 0.586 |
| sqlite_async | 0.423 | 0.638 | 0.423 | 0.638 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.266 | 3.266 | 3.266 | 3.266 |
| sqlite_async | 13.860 | 13.860 | 13.860 | 13.860 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.306 | 6.011 | 4.306 | 6.011 |
| sqlite_async | 8.128 | 11.177 | 8.128 | 11.177 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.667 | 0.848 | 0.667 | 0.848 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 10.048 | 13.423 | 10.048 | 13.423 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. For resqlite, this emission metric can reflect writer-side column-level invalidation, experiment 075's native result-hash short-circuit, or both. Use A11c (Many-Streams Writer Throughput) when the question is specifically writer-side dispatch elision.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 76.5 | 0.000 |
| sqlite_async | 3561 | 1276.5 | 0.960 |
| drift | 5000 | 1572.5 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 95.1 | 0.000 |
| sqlite_async | 3710 | 1197.2 | 0.960 |
| drift | 5000 | 1482.2 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 217.15 | 221.87 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 435.11 | 484.36 | 0.00 | 0.00 | 1138 | 3 |
| drift stream() | 622.72 | 622.88 | 0.13 | 0.20 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.039 | 0.077 | 0.000 | 0.000 |
| sqlite3 | 0.028 | 0.103 | 0.028 | 0.103 |
| sqlite_async | 0.057 | 0.150 | 0.000 | 0.000 |
| drift | 0.086 | 0.155 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.031 | 0.062 | 0.000 | 0.000 |
| sqlite3 | 0.018 | 0.044 | 0.018 | 0.044 |
| sqlite_async | 0.047 | 0.105 | 0.000 | 0.000 |
| drift | 0.072 | 0.124 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.035 | 0.060 | 0.000 | 0.000 |
| sqlite3 | 0.035 | 0.073 | 0.035 | 0.073 |
| sqlite_async | 0.074 | 0.177 | 0.000 | 0.001 |
| drift | 0.072 | 0.124 | 0.000 | 0.001 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.014 | 0.031 | 0.000 | 0.000 |
| sqlite3 | 0.006 | 0.010 | 0.006 | 0.010 |
| sqlite_async | 0.028 | 0.067 | 0.000 | 0.000 |
| drift | 0.031 | 0.065 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.047 | 0.179 | 0.004 | 0.005 |
| sqlite3 | 0.072 | 0.096 | 0.072 | 0.096 |
| sqlite_async | 0.089 | 0.093 | 0.001 | 0.002 |
| drift | 0.122 | 0.152 | 0.001 | 0.002 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 105.788 | 108.345 | 0.000 | 0.000 | 0 |
| sqlite_async | 210.984 | 212.318 | 0.000 | 0.001 | 42 |
| drift | 226.663 | 226.761 | 0.001 | 0.001 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 249.83 | 249.83 | 0.04 | 0.04 | 12.42 | 237.41 | 2 |
| sqlite_async | 488.94 | 488.94 | 0.03 | 0.03 | 23.03 | 465.90 | 1158 |
| drift | 2355.61 | 2355.61 | 1.78 | 1.78 | 12.80 | 2342.79 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 3.02 | 11.02 | 0.00..7.45 | ±3.73 |
| sqlite3 select() | 5.95 | 9.58 | 0.00..8.38 | ±4.19 |
| sqlite_async select() | 0.41 | 1.66 | 0.00..0.98 | ±0.49 |
| drift select() | 5.34 | 15.55 | 0.00..13.09 | ±6.55 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 1.97 | 8.53 | 0.00..8.00 | ±4.00 |
| resqlite + jsonEncode | 0.00 | 32.69 | 0.00..24.73 | ±12.37 |
| sqlite3 + jsonEncode | 6.91 | 68.75 | 0.00..11.88 | ±5.94 |
| sqlite_async + jsonEncode | 0.00 | 19.17 | 0.00..3.02 | ±1.51 |
| drift + jsonEncode | 0.00 | 47.22 | 0.00..23.98 | ±11.99 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.00 | 3.86 | 0.00..2.73 | ±1.37 |
| sqlite3 executeBatch() | 0.00 | 0.55 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 7.03 | 0.00..0.00 | ±0.00 |
| drift batch() | 0.02 | 4.45 | 0.00..2.45 | ±1.23 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.02 | 0.14 | 0.00..0.06 | ±0.03 |
| sqlite_async watch() | 0.00 | 0.50 | 0.00..0.38 | ±0.19 |

## SQLite Diagnostics

resqlite-only internal SQLite counters captured via `Database.diagnostics()` after representative workloads. Values reflect the writer plus idle readers in this connection pool; they are not process-global SQLite totals.

### Warm read working set (20000 rows + 2000 point lookups)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | Readers busy |
|---|---|---|---|---|---|---|
| resqlite | 3209.7 | 3188.3 | 5.3 | 16.2 | 2048.0 | 0 |

### Statement cache footprint (48 distinct SELECT texts)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | Readers busy |
|---|---|---|---|---|---|---|
| resqlite | 3302.7 | 3188.3 | 5.3 | 109.2 | 2048.0 | 0 |

### WAL after write burst (1000 inserted rows)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | Readers busy |
|---|---|---|---|---|---|---|
| resqlite | 260.2 | 238.8 | 5.3 | 16.2 | 161.0 | 0 |

## Comparison vs Previous Run

Previous: `2026-05-02T07-25-17-exp120-flush-admit-bound.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.03 | 0.04 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.04 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.03 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.32 | 0.32 | +0.00 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.32 | 0.32 | +0.00 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.30 | 0.94 | +0.64 | ±10% / ±0.09 ms | 0.0% | single run | 🔴 Regression (+213%) |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.15 | 0.47 | +0.32 | ±10% / ±0.05 ms | 0.0% | single run | 🔴 Regression (+213%) |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.37 | 0.96 | +0.59 | ±10% / ±0.10 ms | 0.0% | single run | 🔴 Regression (+159%) |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.09 | 0.24 | +0.15 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+167%) |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.71 | 1.10 | +0.39 | ±10% / ±0.11 ms | 0.0% | single run | 🔴 Regression (+55%) |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.09 | 0.14 | +0.05 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+56%) |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.05 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 111.49 | 105.79 | -5.70 | ±10% / ±11.15 ms | 0.0% | single run | ⚪ Neutral |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 241.96 | 249.83 | +7.87 | ±10% / ±24.98 ms | 0.0% | single run | ⚪ Neutral |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.04 | +0.04 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (0%) |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 220.75 | 217.15 | -3.60 | ±10% / ±22.08 ms | 0.0% | single run | ⚪ Neutral |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 13.86 | 17.29 | +3.42 | ±10% / ±1.73 ms | 0.0% | single run | 🔴 Regression (+25%) |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 13.86 | 17.29 | +3.42 | ±10% / ±1.73 ms | 0.0% | single run | 🔴 Regression (+25%) |
| Point Query Throughput / resqlite qps | 156873.00 | 98371.00 | -58502.00 | ±10% / ±15687.30 ms | 0.0% | single run | 🔴 Regression (-37%) |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.02 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.06 | +0.03 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+90%) |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.06 | +0.03 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+90%) |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.02 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.02 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.06 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.23 | +0.04 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+24%) |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.23 | +0.04 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+24%) |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.05 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.05 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.37 | 0.47 | +0.10 | ±10% / ±0.05 ms | 0.0% | single run | 🔴 Regression (+26%) |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.73 | 2.20 | +0.47 | ±10% / ±0.22 ms | 0.0% | single run | 🔴 Regression (+27%) |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.73 | 2.20 | +0.47 | ±10% / ±0.22 ms | 0.0% | single run | 🔴 Regression (+27%) |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.08 | 0.14 | +0.06 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+70%) |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.38 | +0.03 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.38 | +0.03 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.47 | 5.80 | +1.33 | ±10% / ±0.58 ms | 0.0% | single run | 🔴 Regression (+30%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 22.50 | 28.06 | +5.56 | ±10% / ±2.81 ms | 0.0% | single run | 🔴 Regression (+25%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 22.50 | 28.06 | +5.56 | ±10% / ±2.81 ms | 0.0% | single run | 🔴 Regression (+25%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.83 | 1.45 | +0.62 | ±10% / ±0.15 ms | 0.0% | single run | 🔴 Regression (+74%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.59 | 4.22 | +0.64 | ±10% / ±0.42 ms | 0.0% | single run | 🔴 Regression (+18%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.59 | 4.22 | +0.64 | ±10% / ±0.42 ms | 0.0% | single run | 🔴 Regression (+18%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.79 | 1.13 | +0.34 | ±10% / ±0.11 ms | 0.0% | single run | 🔴 Regression (+44%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.75 | 5.85 | +2.10 | ±10% / ±0.58 ms | 0.0% | single run | 🔴 Regression (+56%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.75 | 5.85 | +2.10 | ±10% / ±0.58 ms | 0.0% | single run | 🔴 Regression (+56%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.17 | 0.29 | +0.12 | ±10% / ±0.03 ms | 0.0% | single run | 🔴 Regression (+70%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.75 | 1.17 | +0.42 | ±10% / ±0.12 ms | 0.0% | single run | 🔴 Regression (+56%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.75 | 1.17 | +0.42 | ±10% / ±0.12 ms | 0.0% | single run | 🔴 Regression (+56%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.79 | 15.22 | +4.43 | ±10% / ±1.52 ms | 0.0% | single run | 🔴 Regression (+41%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 42.49 | 49.88 | +7.39 | ±10% / ±4.99 ms | 0.0% | single run | 🔴 Regression (+17%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 42.49 | 49.88 | +7.39 | ±10% / ±4.99 ms | 0.0% | single run | 🔴 Regression (+17%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.66 | 3.00 | +1.35 | ±10% / ±0.30 ms | 0.0% | single run | 🔴 Regression (+81%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 7.30 | 15.67 | +8.37 | ±10% / ±1.57 ms | 0.0% | single run | 🔴 Regression (+115%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 7.30 | 15.67 | +8.37 | ±10% / ±1.57 ms | 0.0% | single run | 🔴 Regression (+115%) |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.04 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.12 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.10 | 0.12 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.06 | +0.04 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+150%) |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.06 | +0.04 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+150%) |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.19 | 0.24 | +0.05 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+25%) |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.89 | 1.14 | +0.25 | ±10% / ±0.11 ms | 0.0% | single run | 🔴 Regression (+28%) |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.89 | 1.14 | +0.25 | ±10% / ±0.11 ms | 0.0% | single run | 🔴 Regression (+28%) |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.07 | +0.03 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+71%) |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.20 | +0.03 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+14%) |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.20 | +0.03 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+14%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.06 | 2.78 | +0.72 | ±10% / ±0.28 ms | 0.0% | single run | 🔴 Regression (+35%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 9.57 | 12.14 | +2.57 | ±10% / ±1.21 ms | 0.0% | single run | 🔴 Regression (+27%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 9.57 | 12.14 | +2.57 | ±10% / ±1.21 ms | 0.0% | single run | 🔴 Regression (+27%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.41 | 0.74 | +0.33 | ±10% / ±0.07 ms | 0.0% | single run | 🔴 Regression (+79%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.84 | 2.24 | +0.40 | ±10% / ±0.22 ms | 0.0% | single run | 🔴 Regression (+22%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.84 | 2.24 | +0.40 | ±10% / ±0.22 ms | 0.0% | single run | 🔴 Regression (+22%) |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.10 | 0.14 | +0.04 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+42%) |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.03 | 0.04 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.29 | 0.40 | +0.10 | ±10% / ±0.04 ms | 0.0% | single run | 🔴 Regression (+35%) |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.10 | 0.15 | +0.06 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+57%) |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.29 | 0.37 | +0.08 | ±10% / ±0.04 ms | 0.0% | single run | 🔴 Regression (+27%) |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.10 | 0.15 | +0.05 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+56%) |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.53 | 1.03 | +0.50 | ±10% / ±0.10 ms | 0.0% | single run | 🔴 Regression (+94%) |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.10 | 0.16 | +0.06 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+55%) |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.90 | 1.15 | +0.26 | ±10% / ±0.12 ms | 0.0% | single run | 🔴 Regression (+28%) |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.27 | 0.42 | +0.15 | ±10% / ±0.04 ms | 0.0% | single run | 🔴 Regression (+58%) |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.10 | +0.07 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+259%) |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.07 | +0.06 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+356%) |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.02 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.19 | 0.25 | +0.06 | ±10% / ±0.03 ms | 0.0% | single run | 🔴 Regression (+31%) |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.15 | 0.19 | +0.04 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+23%) |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.06 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.72 | 2.45 | +0.74 | ±10% / ±0.25 ms | 0.0% | single run | 🔴 Regression (+43%) |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.43 | 1.91 | +0.48 | ±10% / ±0.19 ms | 0.0% | single run | 🔴 Regression (+34%) |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.35 | 0.41 | +0.05 | ±10% / ±0.04 ms | 0.0% | single run | 🔴 Regression (+15%) |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.15 | 27.19 | +7.04 | ±10% / ±2.72 ms | 0.0% | single run | 🔴 Regression (+35%) |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 14.71 | 18.15 | +3.44 | ±10% / ±1.81 ms | 0.0% | single run | 🔴 Regression (+23%) |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.60 | 4.25 | +0.66 | ±10% / ±0.43 ms | 0.0% | single run | 🔴 Regression (+18%) |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.01 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.09 | +0.07 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+625%) |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.02 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+2100%) |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.08 | +0.04 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+80%) |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 1000 rows / resqlite select() | 0.38 | 0.46 | +0.09 | ±10% / ±0.05 ms | 0.0% | single run | 🔴 Regression (+22%) |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.08 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 10000 rows / resqlite select() | 4.39 | 6.91 | +2.52 | ±10% / ±0.69 ms | 0.0% | single run | 🔴 Regression (+57%) |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.91 | 0.74 | -0.17 | ±10% / ±0.09 ms | 0.0% | single run | 🟢 Win (-19%) |
| Streaming / Fan-out (10 streams) / resqlite | 0.17 | 0.33 | +0.17 | ±10% / ±0.03 ms | 0.0% | single run | 🔴 Regression (+99%) |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.17 | 0.33 | +0.17 | ±10% / ±0.03 ms | 0.0% | single run | 🔴 Regression (+99%) |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.52 | 0.67 | +0.15 | ±10% / ±0.07 ms | 0.0% | single run | 🔴 Regression (+29%) |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.52 | 0.67 | +0.15 | ±10% / ±0.07 ms | 0.0% | single run | 🔴 Regression (+29%) |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.10 | +0.07 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+247%) |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.10 | +0.07 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+247%) |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.08 | +0.04 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+105%) |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.08 | +0.04 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+105%) |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 1.63 | 3.25 | +1.63 | ±10% / ±0.33 ms | 0.0% | single run | 🔴 Regression (+100%) |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 1.63 | 3.25 | +1.63 | ±10% / ±0.33 ms | 0.0% | single run | 🔴 Regression (+100%) |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.37 | 4.31 | +0.93 | ±10% / ±0.43 ms | 0.0% | single run | 🔴 Regression (+28%) |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.37 | 4.31 | +0.93 | ±10% / ±0.43 ms | 0.0% | single run | 🔴 Regression (+28%) |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.57 | 3.27 | +1.70 | ±10% / ±0.33 ms | 0.0% | single run | 🔴 Regression (+108%) |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.57 | 3.27 | +1.70 | ±10% / ±0.33 ms | 0.0% | single run | 🔴 Regression (+108%) |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 5.30 | 10.05 | +4.74 | ±10% / ±1.00 ms | 0.0% | single run | 🔴 Regression (+89%) |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 5.30 | 10.05 | +4.74 | ±10% / ±1.00 ms | 0.0% | single run | 🔴 Regression (+89%) |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.18 | 0.31 | +0.13 | ±10% / ±0.03 ms | 0.0% | single run | 🔴 Regression (+70%) |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.18 | 0.31 | +0.13 | ±10% / ±0.03 ms | 0.0% | single run | 🔴 Regression (+70%) |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.06 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.06 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.39 | 0.44 | +0.05 | ±10% / ±0.04 ms | 0.0% | single run | 🔴 Regression (+13%) |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.39 | 0.44 | +0.05 | ±10% / ±0.04 ms | 0.0% | single run | 🔴 Regression (+13%) |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.63 | 6.13 | +2.50 | ±10% / ±0.61 ms | 0.0% | single run | 🔴 Regression (+69%) |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.63 | 6.13 | +2.50 | ±10% / ±0.61 ms | 0.0% | single run | 🔴 Regression (+69%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.51 | 0.94 | +0.43 | ±10% / ±0.09 ms | 0.0% | single run | 🔴 Regression (+84%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.51 | 0.94 | +0.43 | ±10% / ±0.09 ms | 0.0% | single run | 🔴 Regression (+84%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.09 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+33%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.09 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+33%) |
| Write Performance / Batched Write Inside Transaction (100... | 4.98 | 9.01 | +4.03 | ±10% / ±0.90 ms | 0.0% | single run | 🔴 Regression (+81%) |
| Write Performance / Batched Write Inside Transaction (100... | 4.98 | 9.01 | +4.03 | ±10% / ±0.90 ms | 0.0% | single run | 🔴 Regression (+81%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.39 | 0.48 | +0.09 | ±10% / ±0.05 ms | 0.0% | single run | 🔴 Regression (+22%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.39 | 0.48 | +0.09 | ±10% / ±0.05 ms | 0.0% | single run | 🔴 Regression (+22%) |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.07 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.07 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Nested Transactions (savepoints) / re... | 0.08 | 0.13 | +0.05 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+69%) |
| Write Performance / Nested Transactions (savepoints) / re... | 0.08 | 0.13 | +0.05 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+69%) |
| Write Performance / Nested Transactions (savepoints) / re... | 0.80 | 1.56 | +0.76 | ±10% / ±0.16 ms | 0.0% | single run | 🔴 Regression (+95%) |
| Write Performance / Nested Transactions (savepoints) / re... | 0.80 | 1.56 | +0.76 | ±10% / ±0.16 ms | 0.0% | single run | 🔴 Regression (+95%) |
| Write Performance / Single Inserts (100 sequential) / res... | 1.59 | 2.53 | +0.94 | ±10% / ±0.25 ms | 0.0% | single run | 🔴 Regression (+59%) |
| Write Performance / Single Inserts (100 sequential) / res... | 1.59 | 2.53 | +0.94 | ±10% / ±0.25 ms | 0.0% | single run | 🔴 Regression (+59%) |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.21 | +0.03 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+17%) |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.21 | +0.03 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+17%) |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.11 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.11 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 16.93 | 22.49 | +5.56 | ±10% / ±2.25 ms | 0.0% | single run | 🔴 Regression (+33%) |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 16.93 | 22.49 | +5.56 | ±10% / ±2.25 ms | 0.0% | single run | 🔴 Regression (+33%) |

**Summary:** 1 wins, 114 regressions, 46 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.50 | 0.02 | -0.48 MB | ±1.23 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 0.44 | 0.00 | -0.44 MB | ±1.37 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 0.00 | 0.00 | +0.00 MB | ±11.99 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 1.27 | 0.00 | -1.27 MB | ±12.37 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 1.97 | +1.97 MB | ±4.00 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 0.00 | 6.91 | +6.91 MB | ±5.94 MB | 🔴 Regression (+6.91 MB) |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±1.51 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 6.34 | 5.34 | -1.00 MB | ±6.55 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / resqlite select() | 1.97 | 3.02 | +1.05 MB | ±3.73 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite3 select() | 5.30 | 5.95 | +0.65 MB | ±4.19 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 1.00 | 0.41 | -0.59 MB | ±0.50 MB | 🟢 Win (-0.59 MB) |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.00 | 0.02 | +0.02 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 1 wins, 1 regressions, 13 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 3951 | 3561 | -390 | ±100 | 🟢 Fewer re-emits (-390) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 4114 | 3710 | -404 | ±100 | 🔴 Invalidation elided (-404) — writes not firing |

**Granularity summary:** 1 fewer-re-emit, 1 more-re-emit, 4 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


