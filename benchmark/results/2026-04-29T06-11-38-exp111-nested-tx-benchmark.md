# resqlite Benchmark Results

Generated: 2026-04-29T06:11:38.821397

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp111-nested-tx-benchmark`
- Repeats: `3`
- Runtime: `dart-vm / Dart 3.11.0`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `HEAD @ 7ed23be9f314 (dirty)`
- Comparison baseline: `2026-04-27T15-46-01-exp110-fnv-8byte-long-text.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.012 | 0.014 | 0.001 | 0.001 |
| sqlite3 select() | 0.020 | 0.020 | 0.020 | 0.020 |
| sqlite_async select() | 0.042 | 0.046 | 0.002 | 0.002 |
| drift select() | 0.046 | 0.050 | 0.001 | 0.002 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.058 | 0.060 | 0.011 | 0.011 |
| sqlite3 select() | 0.134 | 0.136 | 0.134 | 0.136 |
| sqlite_async select() | 0.140 | 0.144 | 0.011 | 0.011 |
| drift select() | 0.190 | 0.206 | 0.010 | 0.011 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.375 | 0.390 | 0.085 | 0.087 |
| sqlite3 select() | 1.055 | 1.093 | 1.055 | 1.093 |
| sqlite_async select() | 0.972 | 1.026 | 0.088 | 0.090 |
| drift select() | 1.523 | 1.780 | 0.088 | 0.090 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.329 | 8.575 | 0.833 | 1.188 |
| sqlite3 select() | 13.112 | 15.610 | 13.112 | 15.610 |
| sqlite_async select() | 11.511 | 13.683 | 0.892 | 2.173 |
| drift select() | 19.874 | 25.544 | 0.922 | 1.974 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.026 | 0.030 | 0.015 | 0.016 |
| sqlite3 + jsonEncode | 0.029 | 0.030 | 0.029 | 0.030 |
| sqlite_async + jsonEncode | 0.045 | 0.049 | 0.016 | 0.017 |
| drift + jsonEncode | 0.052 | 0.054 | 0.016 | 0.017 |
| resqlite selectBytes() | 0.011 | 0.012 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.200 | 0.211 | 0.160 | 0.166 |
| sqlite3 + jsonEncode | 0.258 | 0.280 | 0.258 | 0.280 |
| sqlite_async + jsonEncode | 0.260 | 0.266 | 0.149 | 0.154 |
| drift + jsonEncode | 0.315 | 0.324 | 0.151 | 0.156 |
| resqlite selectBytes() | 0.044 | 0.047 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.763 | 3.785 | 1.462 | 2.930 |
| sqlite3 + jsonEncode | 2.423 | 4.925 | 2.423 | 4.925 |
| sqlite_async + jsonEncode | 2.345 | 2.912 | 1.450 | 2.024 |
| drift + jsonEncode | 2.892 | 3.458 | 1.441 | 2.031 |
| resqlite selectBytes() | 0.350 | 0.355 | 0.000 | 0.000 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.252 | 23.205 | 14.572 | 16.797 |
| sqlite3 + jsonEncode | 28.287 | 33.461 | 28.287 | 33.461 |
| sqlite_async + jsonEncode | 28.854 | 31.098 | 14.794 | 16.395 |
| drift + jsonEncode | 37.356 | 42.569 | 15.403 | 19.598 |
| resqlite selectBytes() | 3.736 | 5.693 | 0.001 | 0.006 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.103 | 0.106 | 0.036 | 0.037 |
| sqlite3 | 0.321 | 0.339 | 0.321 | 0.339 |
| sqlite_async | 0.360 | 0.405 | 0.042 | 0.045 |
| drift | 0.566 | 0.576 | 0.040 | 0.041 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.899 | 0.928 | 0.266 | 0.271 |
| sqlite3 | 3.132 | 3.626 | 3.132 | 3.626 |
| sqlite_async | 2.745 | 3.159 | 0.311 | 0.320 |
| drift | 4.568 | 5.995 | 0.314 | 0.330 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.535 | 1.109 | 0.101 | 0.113 |
| sqlite3 | 1.397 | 1.443 | 1.397 | 1.443 |
| sqlite_async | 1.301 | 1.583 | 0.112 | 0.120 |
| drift | 1.890 | 2.247 | 0.111 | 0.116 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.288 | 0.294 | 0.094 | 0.099 |
| sqlite3 | 0.951 | 0.975 | 0.951 | 0.975 |
| sqlite_async | 0.924 | 0.946 | 0.115 | 0.119 |
| drift | 1.477 | 1.551 | 0.113 | 0.118 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.307 | 0.312 | 0.100 | 0.104 |
| sqlite3 | 0.945 | 0.977 | 0.945 | 0.977 |
| sqlite_async | 0.882 | 0.926 | 0.112 | 0.114 |
| drift | 1.417 | 1.641 | 0.109 | 0.112 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.011 | 0.012 | 0.001 | 0.001 |
| sqlite3 | 0.015 | 0.015 | 0.015 | 0.015 |
| sqlite_async | 0.029 | 0.033 | 0.001 | 0.001 |
| drift | 0.036 | 0.043 | 0.001 | 0.001 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.026 | 0.027 | 0.004 | 0.004 |
| sqlite3 | 0.059 | 0.061 | 0.059 | 0.061 |
| sqlite_async | 0.070 | 0.073 | 0.005 | 0.005 |
| drift | 0.100 | 0.105 | 0.005 | 0.005 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.047 | 0.049 | 0.009 | 0.009 |
| sqlite3 | 0.117 | 0.138 | 0.117 | 0.138 |
| sqlite_async | 0.118 | 0.123 | 0.009 | 0.010 |
| drift | 0.182 | 0.188 | 0.010 | 0.010 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.191 | 0.202 | 0.042 | 0.045 |
| sqlite3 | 0.532 | 0.544 | 0.532 | 0.544 |
| sqlite_async | 0.499 | 0.535 | 0.045 | 0.047 |
| drift | 0.769 | 0.784 | 0.044 | 0.045 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.374 | 0.383 | 0.084 | 0.085 |
| sqlite3 | 1.054 | 1.077 | 1.054 | 1.077 |
| sqlite_async | 0.968 | 0.981 | 0.088 | 0.090 |
| drift | 1.522 | 1.849 | 0.088 | 0.090 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.772 | 0.801 | 0.167 | 0.175 |
| sqlite3 | 2.106 | 2.628 | 2.106 | 2.628 |
| sqlite_async | 1.937 | 2.294 | 0.177 | 0.182 |
| drift | 3.042 | 3.642 | 0.175 | 0.182 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.072 | 4.651 | 0.414 | 0.682 |
| sqlite3 | 5.275 | 6.633 | 5.275 | 6.633 |
| sqlite_async | 4.978 | 5.656 | 0.443 | 0.448 |
| drift | 8.272 | 8.467 | 0.440 | 0.452 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.381 | 10.075 | 0.834 | 0.870 |
| sqlite3 | 13.243 | 16.371 | 13.243 | 16.371 |
| sqlite_async | 11.419 | 13.980 | 0.887 | 1.395 |
| drift | 20.324 | 26.828 | 0.903 | 2.075 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 10.894 | 16.727 | 1.664 | 2.300 |
| sqlite3 | 28.165 | 37.207 | 28.165 | 37.207 |
| sqlite_async | 32.715 | 39.112 | 1.809 | 4.759 |
| drift | 49.582 | 58.244 | 1.796 | 7.033 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.027 | 0.028 | 0.027 | 0.028 |
| sqlite3 + jsonEncode | 0.030 | 0.034 | 0.030 | 0.034 |
| sqlite_async + jsonEncode | 0.046 | 0.048 | 0.046 | 0.048 |
| drift + jsonEncode | 0.051 | 0.054 | 0.051 | 0.054 |
| resqlite selectBytes() | 0.011 | 0.013 | 0.011 | 0.013 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.103 | 0.106 | 0.103 | 0.106 |
| sqlite3 + jsonEncode | 0.133 | 0.137 | 0.133 | 0.137 |
| sqlite_async + jsonEncode | 0.146 | 0.152 | 0.146 | 0.152 |
| drift + jsonEncode | 0.169 | 0.210 | 0.169 | 0.210 |
| resqlite selectBytes() | 0.024 | 0.028 | 0.024 | 0.028 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.190 | 0.199 | 0.190 | 0.199 |
| sqlite3 + jsonEncode | 0.252 | 0.255 | 0.252 | 0.255 |
| sqlite_async + jsonEncode | 0.258 | 0.262 | 0.258 | 0.262 |
| drift + jsonEncode | 0.316 | 0.320 | 0.316 | 0.320 |
| resqlite selectBytes() | 0.043 | 0.045 | 0.043 | 0.045 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.885 | 0.909 | 0.885 | 0.909 |
| sqlite3 + jsonEncode | 1.221 | 1.259 | 1.221 | 1.259 |
| sqlite_async + jsonEncode | 1.187 | 1.201 | 1.187 | 1.201 |
| drift + jsonEncode | 1.456 | 1.540 | 1.456 | 1.540 |
| resqlite selectBytes() | 0.179 | 0.182 | 0.179 | 0.182 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.801 | 3.474 | 1.801 | 3.474 |
| sqlite3 + jsonEncode | 2.534 | 4.652 | 2.534 | 4.652 |
| sqlite_async + jsonEncode | 2.362 | 5.135 | 2.362 | 5.135 |
| drift + jsonEncode | 2.894 | 3.509 | 2.894 | 3.509 |
| resqlite selectBytes() | 0.352 | 0.364 | 0.352 | 0.364 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.887 | 6.966 | 3.887 | 6.966 |
| sqlite3 + jsonEncode | 5.083 | 8.384 | 5.083 | 8.384 |
| sqlite_async + jsonEncode | 4.939 | 8.058 | 4.939 | 8.058 |
| drift + jsonEncode | 6.239 | 9.254 | 6.239 | 9.254 |
| resqlite selectBytes() | 0.762 | 1.005 | 0.762 | 1.005 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 9.597 | 13.015 | 9.597 | 13.015 |
| sqlite3 + jsonEncode | 14.145 | 16.611 | 14.145 | 16.611 |
| sqlite_async + jsonEncode | 13.326 | 18.143 | 13.326 | 18.143 |
| drift + jsonEncode | 17.317 | 20.599 | 17.317 | 20.599 |
| resqlite selectBytes() | 1.873 | 3.694 | 1.873 | 3.694 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 22.728 | 24.891 | 22.728 | 24.891 |
| sqlite3 + jsonEncode | 27.718 | 32.691 | 27.718 | 32.691 |
| sqlite_async + jsonEncode | 30.089 | 32.900 | 30.089 | 32.900 |
| drift + jsonEncode | 38.144 | 40.141 | 38.144 | 40.141 |
| resqlite selectBytes() | 3.814 | 5.982 | 3.814 | 5.982 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 41.118 | 44.003 | 41.118 | 44.003 |
| sqlite3 + jsonEncode | 59.387 | 64.596 | 59.387 | 64.596 |
| sqlite_async + jsonEncode | 62.777 | 67.523 | 62.777 | 67.523 |
| drift + jsonEncode | 75.453 | 92.700 | 75.453 | 92.700 |
| resqlite selectBytes() | 7.864 | 10.336 | 7.864 | 10.336 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.30 | 0.30 |
| sqlite_async | 0.89 | 1.56 | 0.89 |
| drift | 1.43 | 1.48 | 1.43 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.32 | 0.15 |
| sqlite_async | 1.27 | 1.52 | 0.64 |
| drift | 2.60 | 2.93 | 1.30 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.34 | 0.71 | 0.08 |
| sqlite_async | 2.07 | 2.55 | 0.52 |
| drift | 4.96 | 5.39 | 1.24 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.67 | 1.03 | 0.08 |
| sqlite_async | 4.42 | 6.28 | 0.55 |
| drift | 10.21 | 10.65 | 1.28 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 153929 |
| resqlite per query | 0.006 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 153929 | 152672..154419 | 0.6 | 2.2 |
| sqlite3 | 199889 | 198795..200648 | 0.5 | 1.1 |
| sqlite_async | 52489 | 52228..52560 | 0.3 | 0.7 |
| drift | 47658 | 47360..47944 | 0.6 | 1.9 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 13.942 | 14.597 | 13.942 | 14.597 |
| sqlite_async | 34.407 | 34.627 | 34.407 | 34.627 |
| drift | 51.174 | 51.985 | 51.174 | 51.985 |
| sqlite3 (no cache) | 23.696 | 23.852 | 23.696 | 23.852 |
| sqlite3 (cached stmt) | 23.539 | 24.384 | 23.539 | 24.384 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.525 | 2.022 | 1.525 | 2.022 |
| sqlite3 execute() | 0.857 | 1.506 | 0.857 | 1.506 |
| sqlite_async execute() | 2.650 | 3.299 | 2.650 | 3.299 |
| drift execute() | 2.625 | 3.293 | 2.625 | 3.293 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.048 | 0.051 | 0.048 | 0.051 |
| sqlite3 executeBatch() | 0.048 | 0.050 | 0.048 | 0.050 |
| sqlite_async executeBatch() | 0.091 | 0.094 | 0.091 | 0.094 |
| drift executeBatch() | 0.110 | 0.117 | 0.110 | 0.117 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.378 | 0.388 | 0.378 | 0.388 |
| sqlite3 executeBatch() | 0.428 | 0.435 | 0.428 | 0.435 |
| sqlite_async executeBatch() | 0.498 | 0.527 | 0.498 | 0.527 |
| drift executeBatch() | 0.631 | 0.646 | 0.631 | 0.646 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 3.573 | 4.620 | 3.573 | 4.620 |
| sqlite3 executeBatch() | 4.072 | 4.314 | 4.072 | 4.314 |
| sqlite_async executeBatch() | 4.684 | 5.017 | 4.684 | 5.017 |
| drift executeBatch() | 6.010 | 6.486 | 6.010 | 6.486 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.048 | 0.052 | 0.048 | 0.052 |
| sqlite_async writeTransaction() | 0.082 | 0.088 | 0.082 | 0.088 |

### Nested Transactions (depth 3 × 50 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite empty commit | 1.418 | 1.565 | 1.418 | 1.565 |
| resqlite write commit | 1.705 | 1.835 | 1.705 | 1.835 |
| resqlite write rollback | 2.062 | 2.240 | 2.062 | 2.240 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.063 | 0.068 | 0.063 | 0.068 |
| resqlite tx.execute() loop | 0.531 | 0.567 | 0.531 | 0.567 |
| sqlite_async tx.execute() loop | 0.977 | 1.105 | 0.977 | 1.105 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.377 | 0.386 | 0.377 | 0.386 |
| resqlite tx.execute() loop | 5.091 | 6.049 | 5.091 | 6.049 |
| sqlite_async tx.execute() loop | 9.524 | 9.990 | 9.524 | 9.990 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.101 | 0.105 | 0.101 | 0.105 |
| sqlite_async tx.getAll() | 0.199 | 0.207 | 0.199 | 0.207 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.180 | 0.181 | 0.180 | 0.181 |
| sqlite_async tx.getAll() | 0.351 | 0.372 | 0.351 | 0.372 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.029 | 0.035 | 0.029 | 0.035 |
| sqlite_async watch() | 0.103 | 0.130 | 0.103 | 0.130 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.043 | 0.060 | 0.043 | 0.060 |
| sqlite_async | 0.065 | 0.079 | 0.065 | 0.079 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.193 | 0.229 | 0.193 | 0.229 |
| sqlite_async | 0.510 | 2.032 | 0.510 | 2.032 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.765 | 3.807 | 1.765 | 3.807 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.163 | 0.213 | 0.163 | 0.213 |
| sqlite_async | 0.233 | 0.294 | 0.233 | 0.294 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.578 | 1.578 | 1.578 | 1.578 |
| sqlite_async | 9.832 | 9.832 | 9.832 | 9.832 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.146 | 3.950 | 3.146 | 3.950 |
| sqlite_async | 5.237 | 6.020 | 5.237 | 6.020 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.507 | 0.694 | 0.507 | 0.694 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 5.407 | 5.757 | 5.407 | 5.757 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. On resqlite's main branch this ratio is driven toward 0 by experiment 075 (C-side result-hash short-circuit), not by writer-side column-tracking (exp 052 is not implemented). The two mechanisms are indistinguishable on this read-side benchmark.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 68.9 | 0.000 |
| sqlite_async | 4275 | 996.8 | 1.056 |
| drift | 5000 | 983.8 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 72.3 | 0.000 |
| sqlite_async | 4049 | 937.3 | 1.056 |
| drift | 5000 | 999.9 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 226.85 | 227.56 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 442.82 | 443.45 | 0.00 | 0.00 | 1096 | 3 |
| drift stream() | 549.15 | 550.12 | 0.00 | 0.00 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.018 | 0.030 | 0.000 | 0.000 |
| sqlite3 | 0.017 | 0.022 | 0.017 | 0.022 |
| sqlite_async | 0.035 | 0.042 | 0.000 | 0.000 |
| drift | 0.035 | 0.042 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.014 | 0.021 | 0.000 | 0.000 |
| sqlite3 | 0.011 | 0.014 | 0.011 | 0.014 |
| sqlite_async | 0.028 | 0.033 | 0.000 | 0.000 |
| drift | 0.028 | 0.033 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.024 | 0.033 | 0.000 | 0.000 |
| sqlite3 | 0.029 | 0.031 | 0.029 | 0.031 |
| sqlite_async | 0.054 | 0.063 | 0.000 | 0.000 |
| drift | 0.052 | 0.056 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.008 | 0.015 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.020 | 0.024 | 0.000 | 0.000 |
| drift | 0.019 | 0.023 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.039 | 0.043 | 0.001 | 0.001 |
| sqlite3 | 0.061 | 0.063 | 0.061 | 0.063 |
| sqlite_async | 0.074 | 0.076 | 0.001 | 0.001 |
| drift | 0.089 | 0.092 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 109.845 | 110.120 | 0.000 | 0.000 | 0 |
| sqlite_async | 218.111 | 219.700 | 0.000 | 0.000 | 41 |
| drift | 226.928 | 231.955 | 0.000 | 0.001 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 242.60 | 242.60 | 0.00 | 0.00 | 13.70 | 228.89 | 0 |
| sqlite_async | 480.92 | 480.92 | 0.01 | 0.01 | 24.90 | 456.96 | 1179 |
| drift | 1682.82 | 1682.82 | 0.06 | 0.06 | 13.34 | 1669.81 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 0.34 | 9.08 | 0.00..7.31 | ±3.66 |
| sqlite3 select() | 5.02 | 9.39 | 2.45..8.38 | ±2.96 |
| sqlite_async select() | 1.00 | 1.00 | 1.00..1.00 | ±0.00 |
| drift select() | 7.02 | 77.06 | 0.00..13.56 | ±6.78 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 8.00 | 0.00..1.23 | ±0.62 |
| resqlite + jsonEncode | 0.00 | 70.72 | 0.00..4.53 | ±2.27 |
| sqlite3 + jsonEncode | 2.36 | 46.31 | 0.00..8.84 | ±4.42 |
| sqlite_async + jsonEncode | 0.00 | 42.86 | 0.00..19.16 | ±9.58 |
| drift + jsonEncode | 0.00 | 63.91 | 0.00..5.03 | ±2.52 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.00 | 1.66 | 0.00..0.00 | ±0.00 |
| sqlite3 executeBatch() | 0.00 | 0.02 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| drift batch() | 0.02 | 4.50 | 0.00..2.50 | ±1.25 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.13 | 0.00..0.06 | ±0.03 |
| sqlite_async watch() | 0.00 | 0.50 | 0.00..0.02 | ±0.01 |

## SQLite Diagnostics

resqlite-only internal SQLite counters captured via `Database.diagnostics()` after representative workloads. Values reflect the writer plus idle readers in this connection pool; they are not process-global SQLite totals.

### Warm read working set (20000 rows + 2000 point lookups)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | Readers busy |
|---|---|---|---|---|---|---|
| resqlite | 3211.0 | 3189.5 | 5.3 | 16.2 | 2048.0 | 0 |

### Statement cache footprint (48 distinct SELECT texts)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | Readers busy |
|---|---|---|---|---|---|---|
| resqlite | 3304.0 | 3189.5 | 5.3 | 109.2 | 2048.0 | 0 |

### WAL after write burst (1000 inserted rows)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | Readers busy |
|---|---|---|---|---|---|---|
| resqlite | 261.5 | 240.0 | 5.3 | 16.2 | 161.0 | 0 |

## Repeat Stability

These rows summarize resqlite wall medians across repeated full-suite runs.
Use this section to judge whether small deltas are real or just noise.

| Benchmark | Median (ms) | 95% CI (ms) | MDE_ci | Range | MAD | Stability |
|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.02 | 0.02..0.02 | 4.3% | 4.3% | 0.0% | stable |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02..0.02 | 5.6% | 5.6% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.30 | 0.30..0.30 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.30 | 0.30..0.30 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.30 | 0.30..0.31 | 3.3% | 3.3% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.15 | 0.15..0.15 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.36 | 0.34..0.37 | 8.3% | 8.3% | 2.8% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.09 | 0.08..0.09 | 11.1% | 11.1% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.68 | 0.67..0.71 | 5.9% | 5.9% | 1.5% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.08 | 0.08..0.09 | 12.5% | 12.5% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.04 | 5.1% | 5.1% | 2.6% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 300.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 109.84 | 109.16..110.76 | 1.5% | 1.5% | 0.6% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 241.24 | 235.80..242.60 | 2.8% | 2.8% | 0.6% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 226.85 | 224.19..230.22 | 2.7% | 2.7% | 1.2% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 13.94 | 13.83..13.96 | 0.9% | 0.9% | 0.1% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 13.94 | 13.83..13.96 | 0.9% | 0.9% | 0.1% | stable |
| Point Query Throughput / resqlite qps | 153929.00 | 149989.00..156582.00 | 4.3% | 4.3% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.01 | 36.4% | 36.4% | 9.1% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.04 | 27.6% | 27.6% | 6.9% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.04 | 27.6% | 27.6% | 6.9% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 100.0% | 100.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 41.7% | 41.7% | 8.3% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.02 | 41.7% | 41.7% | 8.3% | noisy |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.04..0.05 | 8.5% | 8.5% | 4.3% | moderate |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.19 | 0.19..0.19 | 2.1% | 2.1% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.19 | 0.19..0.19 | 2.1% | 2.1% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 11.1% | 11.1% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.05 | 11.6% | 11.6% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.04 | 0.04..0.05 | 11.6% | 11.6% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.38 | 0.37..0.39 | 3.7% | 3.7% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.76 | 1.73..1.80 | 4.0% | 4.0% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.76 | 1.73..1.80 | 4.0% | 4.0% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.08 | 0.08..0.09 | 3.6% | 3.6% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.35 | 0.35..0.36 | 2.3% | 2.3% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.35 | 0.35..0.36 | 2.3% | 2.3% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.38 | 4.31..4.45 | 3.2% | 3.2% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 22.73 | 20.30..23.22 | 12.9% | 12.9% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 22.73 | 20.30..23.22 | 12.9% | 12.9% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.83 | 0.83..0.85 | 1.8% | 1.8% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 3.78 | 3.69..3.81 | 3.2% | 3.2% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 3.78 | 3.69..3.81 | 3.2% | 3.2% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.78 | 0.77..0.80 | 3.7% | 3.7% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.73 | 3.68..3.89 | 5.5% | 5.5% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.73 | 3.68..3.89 | 5.5% | 5.5% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.17 | 0.17..0.17 | 4.0% | 4.0% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.76 | 0.75..0.77 | 1.8% | 1.8% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.76 | 0.75..0.77 | 1.8% | 1.8% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.89 | 10.53..10.93 | 3.6% | 3.6% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 42.16 | 41.12..43.02 | 4.5% | 4.5% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 42.16 | 41.12..43.02 | 4.5% | 4.5% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.66 | 1.65..1.66 | 0.7% | 0.7% | 0.1% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 7.66 | 7.54..7.86 | 4.3% | 4.3% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 7.66 | 7.54..7.86 | 4.3% | 4.3% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03..0.03 | 11.5% | 11.5% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.10..0.12 | 15.9% | 15.9% | 7.1% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.11 | 0.10..0.12 | 15.9% | 15.9% | 7.1% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.02..0.03 | 23.1% | 23.1% | 7.7% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.02..0.03 | 23.1% | 23.1% | 7.7% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.20 | 0.19..0.20 | 5.1% | 5.1% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.89 | 0.89..0.89 | 0.8% | 0.8% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.89 | 0.89..0.89 | 0.8% | 0.8% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04..0.04 | 4.5% | 4.5% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.18 | 0.18..0.18 | 1.1% | 1.1% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.18 | 0.18..0.18 | 1.1% | 1.1% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.07 | 2.07..2.12 | 2.2% | 2.2% | 0.1% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 9.60 | 8.97..10.00 | 10.7% | 10.7% | 4.2% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 9.60 | 8.97..10.00 | 10.7% | 10.7% | 4.2% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.41 | 0.41..0.42 | 1.2% | 1.2% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 1.91 | 1.87..1.98 | 5.4% | 5.4% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 1.91 | 1.87..1.98 | 5.4% | 5.4% | 1.7% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.10 | 0.10..0.10 | 5.8% | 5.8% | 1.9% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.04 | 0.03..0.04 | 30.6% | 30.6% | 2.8% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.30 | 0.30..0.31 | 3.3% | 3.3% | 1.7% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.10 | 0.10..0.10 | 2.0% | 2.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.29 | 0.29..0.29 | 1.7% | 1.7% | 0.3% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.09 | 0.09..0.10 | 3.2% | 3.2% | 1.1% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.54 | 0.53..0.54 | 3.0% | 3.0% | 1.5% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.10 | 0.10..0.10 | 1.0% | 1.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.90 | 0.90..0.91 | 0.8% | 0.8% | 0.2% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.27 | 0.26..0.27 | 0.8% | 0.8% | 0.4% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.06 | 119.2% | 119.2% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.01 | 0.01..0.04 | 140.0% | 140.0% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 63.6% | 63.6% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.19..0.22 | 15.0% | 15.0% | 4.5% | moderate |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.16 | 0.15..0.18 | 14.4% | 14.4% | 4.4% | moderate |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.05 | 15.9% | 15.9% | 2.3% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.75 | 1.73..1.76 | 1.9% | 1.9% | 0.9% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.45 | 1.44..1.46 | 1.6% | 1.6% | 0.6% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.35 | 0.35..0.36 | 2.3% | 2.3% | 0.8% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.25 | 19.59..20.30 | 3.5% | 3.5% | 0.2% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 14.57 | 14.56..14.83 | 1.9% | 1.9% | 0.1% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.69 | 3.68..3.74 | 1.6% | 1.6% | 0.5% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 100.0% | 100.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.09 | 569.2% | 569.2% | 7.7% | moderate |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 1000.0% | 1000.0% | 50.0% | noisy |
| Select → Maps / 100 rows / resqlite select() | 0.06 | 0.05..0.07 | 34.5% | 34.5% | 13.8% | noisy |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 33.3% | 33.3% | 11.1% | noisy |
| Select → Maps / 1000 rows / resqlite select() | 0.37 | 0.37..0.38 | 1.6% | 1.6% | 0.5% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.08 | 0.07..0.09 | 20.2% | 20.2% | 1.2% | stable |
| Select → Maps / 10000 rows / resqlite select() | 4.33 | 4.29..4.35 | 1.5% | 1.5% | 0.5% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.83 | 0.67..0.83 | 19.8% | 19.8% | 0.2% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.16 | 0.16..0.23 | 41.1% | 41.1% | 0.0% | stable |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.16 | 0.16..0.23 | 41.1% | 41.1% | 0.0% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.52 | 0.51..0.52 | 2.7% | 2.7% | 1.2% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.52 | 0.51..0.52 | 2.7% | 2.7% | 1.2% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03..0.06 | 117.2% | 117.2% | 6.9% | moderate |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03..0.06 | 117.2% | 117.2% | 6.9% | moderate |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.04..0.05 | 11.4% | 11.4% | 2.3% | stable |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.04..0.05 | 11.4% | 11.4% | 2.3% | stable |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 1.76 | 1.64..1.76 | 7.0% | 7.0% | 0.5% | stable |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 1.76 | 1.64..1.76 | 7.0% | 7.0% | 0.5% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.28 | 3.15..3.36 | 6.4% | 6.4% | 2.2% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.28 | 3.15..3.36 | 6.4% | 6.4% | 2.2% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.98 | 1.58..2.42 | 42.5% | 42.5% | 20.3% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.98 | 1.58..2.42 | 42.5% | 42.5% | 20.3% | noisy |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 5.47 | 5.41..6.37 | 17.6% | 17.6% | 1.1% | stable |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 5.47 | 5.41..6.37 | 17.6% | 17.6% | 1.1% | stable |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.19 | 0.17..0.22 | 24.4% | 24.4% | 10.4% | noisy |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.19 | 0.17..0.22 | 24.4% | 24.4% | 10.4% | noisy |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.05 | 0.05..0.05 | 7.8% | 7.8% | 2.0% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.05 | 0.05..0.05 | 7.8% | 7.8% | 2.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.38 | 0.38..0.40 | 5.6% | 5.6% | 0.8% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.38 | 0.38..0.40 | 5.6% | 5.6% | 0.8% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.59 | 3.57..3.92 | 9.8% | 9.8% | 0.4% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.59 | 3.57..3.92 | 9.8% | 9.8% | 0.4% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.56 | 0.53..0.58 | 9.2% | 9.2% | 4.5% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.56 | 0.53..0.58 | 9.2% | 9.2% | 4.5% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.06 | 0.06..0.07 | 3.2% | 3.2% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.06 | 0.06..0.07 | 3.2% | 3.2% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.09 | 4.99..5.13 | 2.7% | 2.7% | 0.8% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.09 | 4.99..5.13 | 2.7% | 2.7% | 0.8% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.38 | 0.38..0.40 | 6.3% | 6.3% | 0.5% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.38 | 0.38..0.40 | 6.3% | 6.3% | 0.5% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05..0.06 | 13.5% | 13.5% | 5.8% | moderate |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05..0.06 | 13.5% | 13.5% | 5.8% | moderate |
| Write Performance / Nested Transactions (depth 3 × 50 cycles) / res... | 1.60 | 1.42..1.88 | 28.6% | 28.6% | 11.2% | noisy |
| Write Performance / Nested Transactions (depth 3 × 50 cycles) / res... | 1.60 | 1.42..1.88 | 28.6% | 28.6% | 11.2% | noisy |
| Write Performance / Nested Transactions (depth 3 × 50 cycles) / res... | 1.87 | 1.71..2.20 | 26.5% | 26.5% | 9.0% | noisy |
| Write Performance / Nested Transactions (depth 3 × 50 cycles) / res... | 1.87 | 1.71..2.20 | 26.5% | 26.5% | 9.0% | noisy |
| Write Performance / Nested Transactions (depth 3 × 50 cycles) / res... | 2.32 | 2.06..2.33 | 11.5% | 11.5% | 0.5% | stable |
| Write Performance / Nested Transactions (depth 3 × 50 cycles) / res... | 2.32 | 2.06..2.33 | 11.5% | 11.5% | 0.5% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.52 | 1.50..1.57 | 4.9% | 4.9% | 2.0% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.52 | 1.50..1.57 | 4.9% | 4.9% | 2.0% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.18..0.19 | 4.3% | 4.3% | 1.6% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.18..0.19 | 4.3% | 4.3% | 1.6% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.10 | 0.10..0.10 | 1.0% | 1.0% | 0.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.10 | 0.10..0.10 | 1.0% | 1.0% | 0.0% | stable |


## Comparison vs Previous Run

Previous: `2026-04-27T15-46-01-exp110-fnv-8byte-long-text.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.03 | 0.02 | -0.01 | ±10% / ±0.02 ms | 4.3% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.03 | 0.02 | -0.01 | ±10% / ±0.02 ms | 5.6% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.01 | -0.01 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.32 | 0.30 | -0.02 | ±10% / ±0.03 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.32 | 0.30 | -0.02 | ±10% / ±0.03 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.34 | 0.30 | -0.04 | ±10% / ±0.03 ms | 3.3% | stable | 🟢 Win (-12%) |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.17 | 0.15 | -0.02 | ±10% / ±0.02 ms | 0.0% | stable | 🟢 Win (-12%) |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.41 | 0.36 | -0.05 | ±10% / ±0.04 ms | 8.3% | stable | 🟢 Win (-12%) |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.10 | 0.09 | -0.01 | ±11% / ±0.02 ms | 11.1% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.76 | 0.68 | -0.08 | ±10% / ±0.08 ms | 5.9% | stable | 🟢 Win (-11%) |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.09 | 0.08 | -0.01 | ±12% / ±0.02 ms | 12.5% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 5.1% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | -0.00 | ±300% / ±0.02 ms | 300.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 107.57 | 109.84 | +2.28 | ±10% / ±10.98 ms | 1.5% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 248.11 | 241.24 | -6.87 | ±10% / ±24.81 ms | 2.8% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 223.53 | 226.85 | +3.32 | ±10% / ±22.69 ms | 2.7% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.85 | 13.94 | -0.91 | ±10% / ±1.49 ms | 0.9% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.85 | 13.94 | -0.91 | ±10% / ±1.49 ms | 0.9% | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 124232.00 | 153929.00 | +29697.00 | ±10% / ±15392.90 ms | 4.3% | stable | 🟢 Win (24%) |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01 | -0.00 | ±36% / ±0.02 ms | 36.4% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.04 | 0.03 | -0.01 | ±28% / ±0.02 ms | 27.6% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.04 | 0.03 | -0.01 | ±28% / ±0.02 ms | 27.6% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | -0.00 | ±100% / ±0.02 ms | 100.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.02 | 0.01 | -0.01 | ±42% / ±0.02 ms | 41.7% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.02 | 0.01 | -0.01 | ±42% / ±0.02 ms | 41.7% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05 | -0.00 | ±13% / ±0.02 ms | 8.5% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.23 | 0.19 | -0.03 | ±10% / ±0.02 ms | 2.1% | stable | 🟢 Win (-15%) |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.23 | 0.19 | -0.03 | ±10% / ±0.02 ms | 2.1% | stable | 🟢 Win (-15%) |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±11% / ±0.02 ms | 11.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.05 | 0.04 | -0.01 | ±12% / ±0.02 ms | 11.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.05 | 0.04 | -0.01 | ±12% / ±0.02 ms | 11.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.40 | 0.38 | -0.02 | ±10% / ±0.04 ms | 3.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.97 | 1.76 | -0.21 | ±10% / ±0.20 ms | 4.0% | stable | 🟢 Win (-11%) |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.97 | 1.76 | -0.21 | ±10% / ±0.20 ms | 4.0% | stable | 🟢 Win (-11%) |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.08 | -0.01 | ±10% / ±0.02 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.39 | 0.35 | -0.03 | ±10% / ±0.04 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.39 | 0.35 | -0.03 | ±10% / ±0.04 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.84 | 4.38 | -0.46 | ±10% / ±0.48 ms | 3.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 22.44 | 22.73 | +0.28 | ±13% / ±2.93 ms | 12.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 22.44 | 22.73 | +0.28 | ±13% / ±2.93 ms | 12.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.90 | 0.83 | -0.06 | ±10% / ±0.09 ms | 1.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 4.01 | 3.78 | -0.24 | ±10% / ±0.40 ms | 3.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 4.01 | 3.78 | -0.24 | ±10% / ±0.40 ms | 3.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.85 | 0.78 | -0.07 | ±10% / ±0.08 ms | 3.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.87 | 3.73 | -0.14 | ±10% / ±0.39 ms | 5.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.87 | 3.73 | -0.14 | ±10% / ±0.39 ms | 5.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.18 | 0.17 | -0.00 | ±10% / ±0.02 ms | 4.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.85 | 0.76 | -0.09 | ±10% / ±0.08 ms | 1.8% | stable | 🟢 Win (-10%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.85 | 0.76 | -0.09 | ±10% / ±0.08 ms | 1.8% | stable | 🟢 Win (-10%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 11.93 | 10.89 | -1.03 | ±10% / ±1.19 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 47.18 | 42.16 | -5.02 | ±10% / ±4.72 ms | 4.5% | stable | 🟢 Win (-11%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 47.18 | 42.16 | -5.02 | ±10% / ±4.72 ms | 4.5% | stable | 🟢 Win (-11%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.79 | 1.66 | -0.13 | ±10% / ±0.18 ms | 0.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.28 | 7.66 | -0.63 | ±10% / ±0.83 ms | 4.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.28 | 7.66 | -0.63 | ±10% / ±0.83 ms | 4.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03 | -0.01 | ±12% / ±0.02 ms | 11.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.11 | +0.00 | ±21% / ±0.02 ms | 15.9% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.11 | 0.11 | +0.00 | ±21% / ±0.02 ms | 15.9% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.01 | 0.00 | -0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | -0.00 | ±23% / ±0.02 ms | 23.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | -0.00 | ±23% / ±0.02 ms | 23.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.20 | 0.20 | -0.01 | ±10% / ±0.02 ms | 5.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.93 | 0.89 | -0.04 | ±10% / ±0.09 ms | 0.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.93 | 0.89 | -0.04 | ±10% / ±0.09 ms | 0.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 4.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.20 | 0.18 | -0.02 | ±10% / ±0.02 ms | 1.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.20 | 0.18 | -0.02 | ±10% / ±0.02 ms | 1.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.31 | 2.07 | -0.23 | ±10% / ±0.23 ms | 2.2% | stable | 🟢 Win (-10%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 11.23 | 9.60 | -1.64 | ±13% / ±1.42 ms | 10.7% | moderate | 🟢 Win (-15%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 11.23 | 9.60 | -1.64 | ±13% / ±1.42 ms | 10.7% | moderate | 🟢 Win (-15%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.44 | 0.41 | -0.03 | ±10% / ±0.04 ms | 1.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 2.13 | 1.91 | -0.23 | ±10% / ±0.21 ms | 5.4% | stable | 🟢 Win (-11%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 2.13 | 1.91 | -0.23 | ±10% / ±0.21 ms | 5.4% | stable | 🟢 Win (-11%) |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.12 | 0.10 | -0.01 | ±10% / ±0.02 ms | 5.8% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.03 | 0.04 | +0.01 | ±31% / ±0.02 ms | 30.6% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.31 | 0.30 | -0.01 | ±10% / ±0.03 ms | 3.3% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.32 | 0.29 | -0.03 | ±10% / ±0.03 ms | 1.7% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.10 | 0.09 | -0.01 | ±10% / ±0.02 ms | 3.2% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.61 | 0.54 | -0.07 | ±10% / ±0.06 ms | 3.0% | stable | 🟢 Win (-12%) |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.11 | 0.10 | -0.00 | ±10% / ±0.02 ms | 1.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.95 | 0.90 | -0.04 | ±10% / ±0.09 ms | 0.8% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.27 | 0.27 | -0.01 | ±10% / ±0.03 ms | 0.8% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.10 | 0.03 | -0.07 | ±119% / ±0.12 ms | 119.2% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.08 | 0.01 | -0.06 | ±140% / ±0.11 ms | 140.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.02 | 0.01 | -0.01 | ±64% / ±0.02 ms | 63.6% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.23 | 0.20 | -0.03 | ±15% / ±0.03 ms | 15.0% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.18 | 0.16 | -0.02 | ±14% / ±0.03 ms | 14.4% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.06 | 0.04 | -0.01 | ±16% / ±0.02 ms | 15.9% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.95 | 1.75 | -0.20 | ±10% / ±0.19 ms | 1.9% | stable | 🟢 Win (-10%) |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.56 | 1.45 | -0.11 | ±10% / ±0.16 ms | 1.6% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.42 | 0.35 | -0.07 | ±10% / ±0.04 ms | 2.3% | stable | 🟢 Win (-16%) |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | -0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 21.40 | 20.25 | -1.14 | ±10% / ±2.14 ms | 3.5% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 15.48 | 14.57 | -0.90 | ±10% / ±1.55 ms | 1.9% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 4.11 | 3.69 | -0.42 | ±10% / ±0.41 ms | 1.6% | stable | 🟢 Win (-10%) |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | -0.00 | ±100% / ±0.02 ms | 100.0% | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.09 | 0.01 | -0.07 | ±569% / ±0.49 ms | 569.2% | moderate | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.02 | 0.00 | -0.02 | ±1000% / ±0.22 ms | 1000.0% | noisy | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.07 | 0.06 | -0.01 | ±41% / ±0.03 ms | 34.5% | noisy | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | -0.00 | ±33% / ±0.02 ms | 33.3% | noisy | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.43 | 0.37 | -0.06 | ±10% / ±0.04 ms | 1.6% | stable | 🟢 Win (-13%) |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.07 | 0.08 | +0.01 | ±20% / ±0.02 ms | 20.2% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 5.18 | 4.33 | -0.85 | ±10% / ±0.52 ms | 1.5% | stable | 🟢 Win (-16%) |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.72 | 0.83 | +0.11 | ±20% / ±0.16 ms | 19.8% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.44 | 0.16 | -0.28 | ±41% / ±0.18 ms | 41.1% | stable | 🟢 Win (-63%) |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.44 | 0.16 | -0.28 | ±41% / ±0.18 ms | 41.1% | stable | 🟢 Win (-63%) |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.51 | 0.52 | +0.01 | ±10% / ±0.05 ms | 2.7% | stable | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.51 | 0.52 | +0.01 | ±10% / ±0.05 ms | 2.7% | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.06 | 0.03 | -0.03 | ±117% / ±0.07 ms | 117.2% | moderate | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.06 | 0.03 | -0.03 | ±117% / ±0.07 ms | 117.2% | moderate | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.04 | -0.00 | ±11% / ±0.02 ms | 11.4% | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.04 | -0.00 | ±11% / ±0.02 ms | 11.4% | stable | ⚪ Within noise |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 2.44 | 1.76 | -0.68 | ±10% / ±0.24 ms | 7.0% | stable | 🟢 Win (-28%) |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 2.44 | 1.76 | -0.68 | ±10% / ±0.24 ms | 7.0% | stable | 🟢 Win (-28%) |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.78 | 3.28 | -0.49 | ±10% / ±0.38 ms | 6.4% | stable | 🟢 Win (-13%) |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.78 | 3.28 | -0.49 | ±10% / ±0.38 ms | 6.4% | stable | 🟢 Win (-13%) |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.63 | 1.98 | -0.65 | ±61% / ±1.60 ms | 42.5% | noisy | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.63 | 1.98 | -0.65 | ±61% / ±1.60 ms | 42.5% | noisy | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.85 | 5.47 | -1.38 | ±18% / ±1.21 ms | 17.6% | stable | 🟢 Win (-20%) |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.85 | 5.47 | -1.38 | ±18% / ±1.21 ms | 17.6% | stable | 🟢 Win (-20%) |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.40 | 0.19 | -0.21 | ±31% / ±0.12 ms | 24.4% | noisy | 🟢 Win (-52%) |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.40 | 0.19 | -0.21 | ±31% / ±0.12 ms | 24.4% | noisy | 🟢 Win (-52%) |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 7.8% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 7.8% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.39 | 0.38 | -0.02 | ±10% / ±0.04 ms | 5.6% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.39 | 0.38 | -0.02 | ±10% / ±0.04 ms | 5.6% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.51 | 3.59 | -0.92 | ±10% / ±0.45 ms | 9.8% | stable | 🟢 Win (-20%) |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.51 | 3.59 | -0.92 | ±10% / ±0.45 ms | 9.8% | stable | 🟢 Win (-20%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.83 | 0.56 | -0.27 | ±13% / ±0.11 ms | 9.2% | moderate | 🟢 Win (-33%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.83 | 0.56 | -0.27 | ±13% / ±0.11 ms | 9.2% | moderate | 🟢 Win (-33%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.06 | -0.01 | ±10% / ±0.02 ms | 3.2% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.06 | -0.01 | ±10% / ±0.02 ms | 3.2% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 5.85 | 5.09 | -0.75 | ±10% / ±0.58 ms | 2.7% | stable | 🟢 Win (-13%) |
| Write Performance / Batched Write Inside Transaction (100... | 5.85 | 5.09 | -0.75 | ±10% / ±0.58 ms | 2.7% | stable | 🟢 Win (-13%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.42 | 0.38 | -0.04 | ±10% / ±0.04 ms | 6.3% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.42 | 0.38 | -0.04 | ±10% / ±0.04 ms | 6.3% | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.05 | +0.00 | ±17% / ±0.02 ms | 13.5% | moderate | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.05 | +0.00 | ±17% / ±0.02 ms | 13.5% | moderate | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 2.13 | 1.52 | -0.60 | ±10% / ±0.21 ms | 4.9% | stable | 🟢 Win (-28%) |
| Write Performance / Single Inserts (100 sequential) / res... | 2.13 | 1.52 | -0.60 | ±10% / ±0.21 ms | 4.9% | stable | 🟢 Win (-28%) |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.20 | 0.18 | -0.01 | ±10% / ±0.02 ms | 4.3% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.20 | 0.18 | -0.01 | ±10% / ±0.02 ms | 4.3% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.12 | 0.10 | -0.02 | ±10% / ±0.02 ms | 1.0% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.12 | 0.10 | -0.02 | ±10% / ±0.02 ms | 1.0% | stable | ⚪ Within noise |

**Summary:** 42 wins, 0 regressions, 113 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

✅ **No regressions beyond noise.** 42 benchmarks improved.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.02 | 0.02 | +0.00 MB | ±1.25 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 1.22 | 0.00 | -1.22 MB | ±0.50 MB | 🟢 Win (-1.22 MB) |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.02 | 0.00 | -0.02 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 0.83 | 0.00 | -0.83 MB | ±2.52 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 0.00 | 0.00 | +0.00 MB | ±2.27 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 0.00 | +0.00 MB | ±0.62 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 3.50 | 2.36 | -1.14 MB | ±4.42 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±9.58 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 14.84 | 7.02 | -7.82 MB | ±6.78 MB | 🟢 Win (-7.82 MB) |
| Memory / Select 10k rows → Maps / resqlite select() | 3.59 | 0.34 | -3.25 MB | ±3.66 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite3 select() | 2.88 | 5.02 | +2.14 MB | ±2.96 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 1.00 | 1.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.13 | 0.06 | -0.07 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 2 wins, 0 regressions, 13 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 3534 | 4275 | +741 | ±100 | 🔴 More re-emits (+741) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 3128 | 4049 | +921 | ±100 | 🔴 More re-emits (+921) |

**Granularity summary:** 0 fewer-re-emit, 2 more-re-emit, 4 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


