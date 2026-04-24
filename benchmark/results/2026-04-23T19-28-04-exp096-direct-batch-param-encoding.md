# resqlite Benchmark Results

Generated: 2026-04-23T19:28:04.150290

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp096-direct-batch-param-encoding`
- Repeats: `3`
- Runtime: `dart-vm / Dart 3.11.0`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `codex/benchmark-contract-goldens @ 02da8b80915d (dirty)`
- Comparison baseline: `2026-04-23T18-44-25-internal-perf-review.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.016 | 0.020 | 0.001 | 0.002 |
| sqlite3 select() | 0.018 | 0.020 | 0.018 | 0.020 |
| sqlite_async select() | 0.035 | 0.039 | 0.002 | 0.002 |
| drift select() | 0.054 | 0.092 | 0.002 | 0.003 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.055 | 0.070 | 0.010 | 0.013 |
| sqlite3 select() | 0.120 | 0.127 | 0.120 | 0.127 |
| sqlite_async select() | 0.130 | 0.163 | 0.010 | 0.014 |
| drift select() | 0.223 | 0.294 | 0.012 | 0.014 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.415 | 0.445 | 0.094 | 0.105 |
| sqlite3 select() | 1.211 | 1.326 | 1.211 | 1.326 |
| sqlite_async select() | 1.135 | 1.594 | 0.103 | 0.124 |
| drift select() | 1.858 | 2.171 | 0.104 | 0.114 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 5.407 | 16.469 | 0.913 | 2.872 |
| sqlite3 select() | 15.371 | 20.138 | 15.371 | 20.138 |
| sqlite_async select() | 13.082 | 14.820 | 0.972 | 1.093 |
| drift select() | 24.553 | 37.508 | 1.030 | 2.012 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.032 | 0.034 | 0.016 | 0.017 |
| sqlite3 + jsonEncode | 0.031 | 0.037 | 0.031 | 0.037 |
| sqlite_async + jsonEncode | 0.048 | 0.051 | 0.016 | 0.017 |
| drift + jsonEncode | 0.056 | 0.060 | 0.016 | 0.017 |
| resqlite selectBytes() | 0.008 | 0.009 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.215 | 0.223 | 0.170 | 0.176 |
| sqlite3 + jsonEncode | 0.271 | 0.308 | 0.271 | 0.308 |
| sqlite_async + jsonEncode | 0.275 | 2.457 | 0.160 | 1.668 |
| drift + jsonEncode | 0.335 | 0.364 | 0.159 | 0.176 |
| resqlite selectBytes() | 0.042 | 0.043 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.846 | 3.038 | 1.530 | 2.685 |
| sqlite3 + jsonEncode | 2.595 | 3.111 | 2.595 | 3.111 |
| sqlite_async + jsonEncode | 2.569 | 9.189 | 1.561 | 1.622 |
| drift + jsonEncode | 3.211 | 3.519 | 1.571 | 1.638 |
| resqlite selectBytes() | 0.375 | 0.409 | 0.000 | 0.001 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 25.850 | 28.165 | 15.597 | 18.492 |
| sqlite3 + jsonEncode | 30.510 | 43.082 | 30.510 | 43.082 |
| sqlite_async + jsonEncode | 32.203 | 37.408 | 15.846 | 17.774 |
| drift + jsonEncode | 42.338 | 53.033 | 15.835 | 19.044 |
| resqlite selectBytes() | 3.887 | 6.134 | 0.002 | 0.011 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.101 | 0.105 | 0.036 | 0.036 |
| sqlite3 | 0.337 | 0.345 | 0.337 | 0.345 |
| sqlite_async | 0.370 | 0.471 | 0.043 | 0.056 |
| drift | 0.579 | 0.676 | 0.041 | 0.046 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.917 | 0.999 | 0.276 | 0.288 |
| sqlite3 | 3.405 | 3.994 | 3.405 | 3.994 |
| sqlite_async | 2.975 | 3.464 | 0.340 | 0.358 |
| drift | 4.899 | 6.509 | 0.344 | 0.362 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.521 | 0.545 | 0.102 | 0.105 |
| sqlite3 | 1.471 | 1.536 | 1.471 | 1.536 |
| sqlite_async | 1.363 | 1.453 | 0.116 | 0.121 |
| drift | 2.023 | 2.297 | 0.119 | 0.124 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.292 | 0.297 | 0.099 | 0.103 |
| sqlite3 | 0.995 | 1.028 | 0.995 | 1.028 |
| sqlite_async | 0.951 | 1.081 | 0.119 | 0.136 |
| drift | 1.604 | 1.856 | 0.120 | 0.137 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.300 | 0.304 | 0.101 | 0.103 |
| sqlite3 | 0.989 | 1.109 | 0.989 | 1.109 |
| sqlite_async | 0.956 | 1.009 | 0.118 | 0.124 |
| drift | 1.497 | 1.560 | 0.115 | 0.126 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.015 | 0.025 | 0.001 | 0.001 |
| sqlite3 | 0.016 | 0.018 | 0.016 | 0.018 |
| sqlite_async | 0.035 | 0.039 | 0.001 | 0.002 |
| drift | 0.051 | 0.123 | 0.001 | 0.003 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.026 | 0.029 | 0.004 | 0.005 |
| sqlite3 | 0.066 | 0.274 | 0.066 | 0.274 |
| sqlite_async | 0.076 | 0.242 | 0.005 | 0.012 |
| drift | 0.102 | 0.109 | 0.005 | 0.005 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.046 | 0.048 | 0.009 | 0.009 |
| sqlite3 | 0.122 | 0.129 | 0.122 | 0.129 |
| sqlite_async | 0.130 | 0.189 | 0.010 | 0.015 |
| drift | 0.190 | 0.241 | 0.010 | 0.012 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.197 | 0.202 | 0.044 | 0.046 |
| sqlite3 | 0.571 | 0.593 | 0.571 | 0.593 |
| sqlite_async | 0.534 | 0.590 | 0.048 | 0.052 |
| drift | 0.866 | 0.939 | 0.049 | 0.051 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.379 | 0.404 | 0.088 | 0.092 |
| sqlite3 | 1.139 | 1.200 | 1.139 | 1.200 |
| sqlite_async | 1.025 | 1.040 | 0.094 | 0.097 |
| drift | 1.640 | 1.894 | 0.095 | 0.105 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.816 | 1.617 | 0.179 | 0.223 |
| sqlite3 | 2.224 | 2.837 | 2.224 | 2.837 |
| sqlite_async | 2.110 | 2.476 | 0.191 | 0.200 |
| drift | 3.356 | 3.851 | 0.191 | 0.206 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.164 | 6.021 | 0.440 | 0.643 |
| sqlite3 | 5.786 | 7.608 | 5.786 | 7.608 |
| sqlite_async | 5.405 | 6.487 | 0.484 | 0.500 |
| drift | 8.911 | 9.788 | 0.479 | 0.490 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.461 | 11.452 | 0.857 | 1.944 |
| sqlite3 | 14.142 | 16.719 | 14.142 | 16.719 |
| sqlite_async | 12.527 | 14.075 | 0.958 | 2.339 |
| drift | 24.263 | 32.655 | 0.982 | 2.417 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 13.712 | 24.416 | 1.775 | 5.974 |
| sqlite3 | 36.398 | 43.882 | 36.398 | 43.882 |
| sqlite_async | 45.826 | 77.701 | 1.987 | 6.690 |
| drift | 55.999 | 67.617 | 1.931 | 8.150 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.029 | 0.047 | 0.029 | 0.047 |
| sqlite3 + jsonEncode | 0.032 | 0.051 | 0.032 | 0.051 |
| sqlite_async + jsonEncode | 0.043 | 0.055 | 0.043 | 0.055 |
| drift + jsonEncode | 0.049 | 0.050 | 0.049 | 0.050 |
| resqlite selectBytes() | 0.008 | 0.009 | 0.008 | 0.009 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.104 | 0.299 | 0.104 | 0.299 |
| sqlite3 + jsonEncode | 0.138 | 0.142 | 0.138 | 0.142 |
| sqlite_async + jsonEncode | 0.148 | 0.150 | 0.148 | 0.150 |
| drift + jsonEncode | 0.179 | 0.183 | 0.179 | 0.183 |
| resqlite selectBytes() | 0.023 | 0.025 | 0.023 | 0.025 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.204 | 0.593 | 0.204 | 0.593 |
| sqlite3 + jsonEncode | 0.276 | 0.323 | 0.276 | 0.323 |
| sqlite_async + jsonEncode | 0.280 | 2.781 | 0.280 | 2.781 |
| drift + jsonEncode | 0.335 | 0.344 | 0.335 | 0.344 |
| resqlite selectBytes() | 0.045 | 0.799 | 0.045 | 0.799 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.018 | 4.461 | 1.018 | 4.461 |
| sqlite3 + jsonEncode | 1.392 | 2.757 | 1.392 | 2.757 |
| sqlite_async + jsonEncode | 1.305 | 3.827 | 1.305 | 3.827 |
| drift + jsonEncode | 1.702 | 2.831 | 1.702 | 2.831 |
| resqlite selectBytes() | 0.187 | 0.198 | 0.187 | 0.198 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.928 | 5.094 | 1.928 | 5.094 |
| sqlite3 + jsonEncode | 2.728 | 8.820 | 2.728 | 8.820 |
| sqlite_async + jsonEncode | 2.748 | 6.690 | 2.748 | 6.690 |
| drift + jsonEncode | 3.249 | 4.975 | 3.249 | 4.975 |
| resqlite selectBytes() | 0.371 | 0.472 | 0.371 | 0.472 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 4.937 | 14.155 | 4.937 | 14.155 |
| sqlite3 + jsonEncode | 6.703 | 25.772 | 6.703 | 25.772 |
| sqlite_async + jsonEncode | 6.087 | 46.049 | 6.087 | 46.049 |
| drift + jsonEncode | 13.092 | 30.803 | 13.092 | 30.803 |
| resqlite selectBytes() | 0.832 | 7.005 | 0.832 | 7.005 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 22.683 | 72.472 | 22.683 | 72.472 |
| sqlite3 + jsonEncode | 24.964 | 86.095 | 24.964 | 86.095 |
| sqlite_async + jsonEncode | 20.847 | 93.806 | 20.847 | 93.806 |
| drift + jsonEncode | 18.527 | 31.421 | 18.527 | 31.421 |
| resqlite selectBytes() | 2.349 | 5.526 | 2.349 | 5.526 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 23.431 | 29.388 | 23.431 | 29.388 |
| sqlite3 + jsonEncode | 29.506 | 36.197 | 29.506 | 36.197 |
| sqlite_async + jsonEncode | 35.287 | 138.188 | 35.287 | 138.188 |
| drift + jsonEncode | 75.734 | 140.195 | 75.734 | 140.195 |
| resqlite selectBytes() | 6.999 | 48.347 | 6.999 | 48.347 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 66.990 | 158.192 | 66.990 | 158.192 |
| sqlite3 + jsonEncode | 97.477 | 170.814 | 97.477 | 170.814 |
| sqlite_async + jsonEncode | 72.830 | 87.276 | 72.830 | 87.276 |
| drift + jsonEncode | 85.120 | 106.516 | 85.120 | 106.516 |
| resqlite selectBytes() | 8.188 | 10.810 | 8.188 | 10.810 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.29 | 0.32 | 0.29 |
| sqlite_async | 0.95 | 1.16 | 0.95 |
| drift | 1.60 | 1.97 | 1.60 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.32 | 0.35 | 0.16 |
| sqlite_async | 1.34 | 1.61 | 0.67 |
| drift | 2.72 | 3.18 | 1.36 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.40 | 0.44 | 0.10 |
| sqlite_async | 2.25 | 4.56 | 0.56 |
| drift | 5.61 | 6.42 | 1.40 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.80 | 2.06 | 0.10 |
| sqlite_async | 4.80 | 5.54 | 0.60 |
| drift | 12.14 | 20.26 | 1.52 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 109635 |
| resqlite per query | 0.009 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 109635 | 108482..126881 | 8.4 | 22.4 |
| sqlite3 | 184527 | 183008..186237 | 0.9 | 2.8 |
| sqlite_async | 44241 | 40137..46636 | 7.3 | 18.8 |
| drift | 41741 | 38617..43417 | 5.7 | 16.0 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.788 | 15.250 | 14.788 | 15.250 |
| sqlite_async | 36.528 | 38.132 | 36.528 | 38.132 |
| drift | 55.914 | 63.574 | 55.914 | 63.574 |
| sqlite3 (no cache) | 25.329 | 26.867 | 25.329 | 26.867 |
| sqlite3 (cached stmt) | 26.871 | 35.699 | 26.871 | 35.699 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 2.323 | 4.262 | 2.323 | 4.262 |
| sqlite3 execute() | 1.883 | 2.961 | 1.883 | 2.961 |
| sqlite_async execute() | 4.591 | 13.079 | 4.591 | 13.079 |
| drift execute() | 4.218 | 6.604 | 4.218 | 6.604 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.059 | 0.063 | 0.059 | 0.063 |
| sqlite3 executeBatch() | 0.052 | 0.056 | 0.052 | 0.056 |
| sqlite_async executeBatch() | 0.098 | 0.134 | 0.098 | 0.134 |
| drift executeBatch() | 0.119 | 0.158 | 0.119 | 0.158 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.443 | 0.482 | 0.443 | 0.482 |
| sqlite3 executeBatch() | 0.445 | 0.464 | 0.445 | 0.464 |
| sqlite_async executeBatch() | 0.534 | 0.586 | 0.534 | 0.586 |
| drift executeBatch() | 0.684 | 0.851 | 0.684 | 0.851 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.187 | 4.842 | 4.187 | 4.842 |
| sqlite3 executeBatch() | 4.229 | 4.518 | 4.229 | 4.518 |
| sqlite_async executeBatch() | 5.264 | 6.119 | 5.264 | 6.119 |
| drift executeBatch() | 6.735 | 8.095 | 6.735 | 8.095 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.087 | 0.112 | 0.087 | 0.112 |
| sqlite_async writeTransaction() | 0.126 | 0.184 | 0.126 | 0.184 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.077 | 0.104 | 0.077 | 0.104 |
| resqlite tx.execute() loop | 0.724 | 0.909 | 0.724 | 0.909 |
| sqlite_async tx.execute() loop | 1.198 | 1.406 | 1.198 | 1.406 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.461 | 0.592 | 0.461 | 0.592 |
| resqlite tx.execute() loop | 7.412 | 9.612 | 7.412 | 9.612 |
| sqlite_async tx.execute() loop | 11.599 | 13.651 | 11.599 | 13.651 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.113 | 0.134 | 0.113 | 0.134 |
| sqlite_async tx.getAll() | 0.206 | 0.218 | 0.206 | 0.218 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.204 | 0.237 | 0.204 | 0.237 |
| sqlite_async tx.getAll() | 0.375 | 0.474 | 0.375 | 0.474 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.034 | 0.040 | 0.034 | 0.040 |
| sqlite_async watch() | 0.119 | 0.207 | 0.119 | 0.207 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.060 | 0.108 | 0.060 | 0.108 |
| sqlite_async | 0.090 | 0.238 | 0.090 | 0.238 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.284 | 0.389 | 0.284 | 0.389 |
| sqlite_async | 0.883 | 3.484 | 0.883 | 3.484 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.250 | 0.338 | 0.250 | 0.338 |
| sqlite_async | 0.355 | 0.463 | 0.355 | 0.463 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.787 | 1.787 | 1.787 | 1.787 |
| sqlite_async | 10.156 | 10.156 | 10.156 | 10.156 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.047 | 4.913 | 4.047 | 4.913 |
| sqlite_async | 8.135 | 15.466 | 8.135 | 15.466 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.579 | 0.923 | 0.579 | 0.923 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 8.363 | 28.134 | 8.363 | 28.134 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. On resqlite's main branch this ratio is driven toward 0 by experiment 075 (C-side result-hash short-circuit), not by writer-side column-tracking (exp 052 is not implemented). The two mechanisms are indistinguishable on this read-side benchmark.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 101.1 | 0.000 |
| sqlite_async | 2614 | 1316.0 | 1.235 |
| drift | 5000 | 2717.1 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 600 | 122.1 | 0.000 |
| sqlite_async | 2116 | 1876.6 | 1.235 |
| drift | 5000 | 1187.2 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 215.91 | 217.51 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 443.18 | 447.39 | 0.00 | 0.01 | 1104 | 3 |
| drift stream() | 699.95 | 782.17 | 0.04 | 0.14 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.024 | 0.057 | 0.000 | 0.000 |
| sqlite3 | 0.022 | 0.045 | 0.022 | 0.045 |
| sqlite_async | 0.044 | 0.084 | 0.000 | 0.000 |
| drift | 0.044 | 0.092 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.018 | 0.039 | 0.000 | 0.000 |
| sqlite3 | 0.014 | 0.023 | 0.014 | 0.023 |
| sqlite_async | 0.035 | 0.066 | 0.000 | 0.000 |
| drift | 0.034 | 0.063 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.026 | 0.040 | 0.000 | 0.000 |
| sqlite3 | 0.032 | 0.035 | 0.032 | 0.035 |
| sqlite_async | 0.058 | 0.076 | 0.000 | 0.000 |
| drift | 0.053 | 0.064 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.008 | 0.018 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.007 | 0.005 | 0.007 |
| sqlite_async | 0.021 | 0.028 | 0.000 | 0.000 |
| drift | 0.019 | 0.025 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.039 | 0.119 | 0.001 | 0.003 |
| sqlite3 | 0.067 | 0.070 | 0.067 | 0.070 |
| sqlite_async | 0.076 | 0.077 | 0.001 | 0.001 |
| drift | 0.089 | 0.140 | 0.001 | 0.002 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 111.178 | 111.958 | 0.000 | 0.000 | 0 |
| sqlite_async | 218.997 | 219.070 | 0.000 | 0.000 | 47 |
| drift | 219.475 | 235.077 | 0.000 | 0.001 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 240.04 | 240.04 | 0.00 | 0.00 | 13.59 | 226.44 | 0 |
| sqlite_async | 460.54 | 460.54 | 0.00 | 0.00 | 13.31 | 447.23 | 1185 |
| drift | 1826.64 | 1826.64 | 0.28 | 0.28 | 12.14 | 1814.66 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 5.53 | 26.47 | 0.00..7.34 | ±3.67 |
| sqlite3 select() | 3.00 | 8.72 | 0.44..7.05 | ±3.30 |
| sqlite_async select() | 1.00 | 1.00 | 1.00..1.00 | ±0.00 |
| drift select() | 3.34 | 51.11 | 0.00..11.70 | ±5.85 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 8.00 | 0.00..8.00 | ±4.00 |
| resqlite + jsonEncode | 0.02 | 96.00 | 0.00..5.30 | ±2.65 |
| sqlite3 + jsonEncode | 0.00 | 24.17 | 0.00..10.50 | ±5.25 |
| sqlite_async + jsonEncode | 0.00 | 34.80 | 0.00..11.75 | ±5.88 |
| drift + jsonEncode | 7.88 | 48.44 | 0.00..25.31 | ±12.66 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 1.73 | 7.59 | 0.00..3.73 | ±1.87 |
| sqlite3 executeBatch() | 0.00 | 0.13 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| drift batch() | 0.00 | 4.52 | 0.00..1.66 | ±0.83 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.17 | 0.00..0.13 | ±0.06 |
| sqlite_async watch() | 0.00 | 0.52 | 0.00..0.06 | ±0.03 |

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
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.03 | 0.03..0.03 | 3.8% | 3.8% | 0.0% | stable |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 22.2% | 22.2% | 11.1% | noisy |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02..0.02 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02..0.02 | 5.6% | 5.6% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.29 | 0.28..0.30 | 6.9% | 6.9% | 3.4% | moderate |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.29 | 0.28..0.30 | 6.9% | 6.9% | 3.4% | moderate |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.31 | 0.30..0.32 | 6.5% | 6.5% | 3.2% | moderate |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.15 | 0.15..0.16 | 6.7% | 6.7% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.42 | 0.40..0.60 | 47.6% | 47.6% | 4.8% | moderate |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.10 | 0.10..0.15 | 50.0% | 50.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.72 | 0.69..0.80 | 15.3% | 15.3% | 4.2% | moderate |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.09 | 0.09..0.10 | 11.1% | 11.1% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.04 | 17.9% | 17.9% | 2.6% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 300.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 105.89 | 105.09..111.18 | 5.7% | 5.7% | 0.8% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 240.04 | 236.66..440.31 | 84.8% | 84.8% | 1.4% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 218.86 | 215.91..219.70 | 1.7% | 1.7% | 0.4% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 14.79 | 13.92..15.00 | 7.3% | 7.3% | 1.5% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 14.79 | 13.92..15.00 | 7.3% | 7.3% | 1.5% | stable |
| Point Query Throughput / resqlite qps | 106928.00 | 82822.00..109635.00 | 25.1% | 25.1% | 2.5% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.02 | 33.3% | 33.3% | 13.3% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.04 | 26.7% | 26.7% | 3.3% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.04 | 26.7% | 26.7% | 3.3% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 100.0% | 100.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 108.3% | 108.3% | 33.3% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.02 | 108.3% | 108.3% | 33.3% | noisy |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05..0.05 | 8.7% | 8.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.20 | 0.20..0.21 | 8.8% | 8.8% | 3.4% | moderate |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.20 | 0.20..0.21 | 8.8% | 8.8% | 3.4% | moderate |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.05 | 8.9% | 8.9% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.04 | 0.04..0.05 | 8.9% | 8.9% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.38 | 0.37..0.38 | 1.9% | 1.9% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.91 | 1.84..1.93 | 4.6% | 4.6% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.91 | 1.84..1.93 | 4.6% | 4.6% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09..0.09 | 2.3% | 2.3% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.36 | 0.35..0.37 | 4.8% | 4.8% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.36 | 0.35..0.37 | 4.8% | 4.8% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.46 | 4.37..4.90 | 11.8% | 11.8% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 21.53 | 20.35..23.43 | 14.3% | 14.3% | 5.5% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 21.53 | 20.35..23.43 | 14.3% | 14.3% | 5.5% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.85 | 0.85..0.86 | 1.1% | 1.1% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 4.13 | 3.94..7.00 | 74.3% | 74.3% | 4.6% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 4.13 | 3.94..7.00 | 74.3% | 74.3% | 4.6% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.82 | 0.82..0.83 | 2.1% | 2.1% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.94 | 3.67..4.94 | 32.2% | 32.2% | 7.0% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.94 | 3.67..4.94 | 32.2% | 32.2% | 7.0% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.18 | 0.18..0.18 | 1.1% | 1.1% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.77 | 0.75..0.83 | 11.1% | 11.1% | 3.4% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.77 | 0.75..0.83 | 11.1% | 11.1% | 3.4% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 11.38 | 10.49..13.71 | 28.3% | 28.3% | 7.8% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 45.27 | 43.53..66.99 | 51.8% | 51.8% | 3.8% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 45.27 | 43.53..66.99 | 51.8% | 51.8% | 3.8% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.72 | 1.70..1.77 | 4.1% | 4.1% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 8.19 | 7.67..8.38 | 8.6% | 8.6% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 8.19 | 7.67..8.38 | 8.6% | 8.6% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03..0.03 | 17.2% | 17.2% | 6.9% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10..0.12 | 12.4% | 12.4% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.10 | 0.10..0.12 | 12.4% | 12.4% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.02..0.09 | 246.2% | 246.2% | 11.5% | noisy |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.02..0.09 | 246.2% | 246.2% | 11.5% | noisy |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.20 | 0.19..0.20 | 4.6% | 4.6% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.95 | 0.94..1.02 | 8.5% | 8.5% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.95 | 0.94..1.02 | 8.5% | 8.5% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04..0.04 | 2.3% | 2.3% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.19 | 0.19..0.19 | 3.2% | 3.2% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.19 | 0.19..0.19 | 3.2% | 3.2% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.14 | 2.08..2.16 | 3.7% | 3.7% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 10.79 | 10.09..22.68 | 116.7% | 116.7% | 6.5% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 10.79 | 10.09..22.68 | 116.7% | 116.7% | 6.5% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.43 | 0.42..0.44 | 3.7% | 3.7% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 2.20 | 1.89..2.35 | 21.1% | 21.1% | 6.9% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 2.20 | 1.89..2.35 | 21.1% | 21.1% | 6.9% | moderate |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.10 | 0.10..0.10 | 1.0% | 1.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.04 | 0.03..0.04 | 31.4% | 31.4% | 2.9% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.30 | 0.30..0.30 | 2.7% | 2.7% | 1.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.10 | 0.10..0.10 | 2.0% | 2.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.29 | 0.28..0.29 | 2.4% | 2.4% | 0.3% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.10 | 0.10..0.10 | 3.1% | 3.1% | 1.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.52 | 0.51..0.52 | 1.9% | 1.9% | 0.6% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.10 | 0.10..0.10 | 3.9% | 3.9% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.92 | 0.88..0.92 | 4.7% | 4.7% | 0.2% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.28 | 0.27..0.28 | 4.0% | 4.0% | 0.7% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.13 | 312.5% | 312.5% | 9.4% | noisy |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02..0.10 | 550.0% | 550.0% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 108.3% | 108.3% | 33.3% | noisy |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.21 | 0.19..0.23 | 19.1% | 19.1% | 9.3% | noisy |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.17 | 0.15..0.19 | 21.2% | 21.2% | 10.6% | noisy |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.05 | 24.4% | 24.4% | 6.7% | moderate |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.85 | 1.78..1.95 | 9.2% | 9.2% | 3.5% | moderate |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.53 | 1.48..1.57 | 6.2% | 6.2% | 2.9% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.38 | 0.37..0.38 | 2.1% | 2.1% | 1.1% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 24.21 | 20.32..25.85 | 22.8% | 22.8% | 6.8% | moderate |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 15.60 | 15.10..15.88 | 5.0% | 5.0% | 1.8% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.89 | 3.88..3.98 | 2.5% | 2.5% | 0.1% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.01 | 100.0% | 100.0% | 33.3% | noisy |
| Select → Maps / 10 rows / resqlite select() | 0.02 | 0.01..0.09 | 456.3% | 456.3% | 18.8% | noisy |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 1050.0% | 1050.0% | 50.0% | noisy |
| Select → Maps / 100 rows / resqlite select() | 0.06 | 0.05..0.06 | 30.9% | 30.9% | 14.5% | noisy |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 11.1% | 11.1% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.41 | 0.40..0.46 | 14.5% | 14.5% | 3.4% | moderate |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.07..0.10 | 28.7% | 28.7% | 5.3% | moderate |
| Select → Maps / 10000 rows / resqlite select() | 5.41 | 4.32..7.24 | 53.9% | 53.9% | 20.1% | noisy |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.85 | 0.73..0.91 | 21.7% | 21.7% | 7.3% | moderate |
| Streaming / Fan-out (10 streams) / resqlite | 0.25 | 0.21..0.25 | 14.6% | 14.6% | 1.6% | stable |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.25 | 0.21..0.25 | 14.6% | 14.6% | 1.6% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.54 | 0.54..0.58 | 7.2% | 7.2% | 0.7% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.54 | 0.54..0.58 | 7.2% | 7.2% | 0.7% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03..0.04 | 20.6% | 20.6% | 5.9% | moderate |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03..0.04 | 20.6% | 20.6% | 5.9% | moderate |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.05..0.06 | 29.8% | 29.8% | 2.1% | stable |
| Streaming / Invalidation Latency / resqlite [main] | 0.05 | 0.05..0.06 | 29.8% | 29.8% | 2.1% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.85 | 3.62..4.05 | 11.0% | 11.0% | 5.1% | moderate |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.85 | 3.62..4.05 | 11.0% | 11.0% | 5.1% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.79 | 1.66..2.77 | 62.2% | 62.2% | 7.2% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.79 | 1.66..2.77 | 62.2% | 62.2% | 7.2% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 7.45 | 6.81..8.36 | 20.8% | 20.8% | 8.6% | noisy |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 7.45 | 6.81..8.36 | 20.8% | 20.8% | 8.6% | noisy |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.23 | 0.20..0.28 | 37.9% | 37.9% | 15.5% | noisy |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.23 | 0.20..0.28 | 37.9% | 37.9% | 15.5% | noisy |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.06..0.06 | 3.4% | 3.4% | 1.7% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.06 | 0.06..0.06 | 3.4% | 3.4% | 1.7% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.45 | 0.44..0.46 | 2.7% | 2.7% | 0.4% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.45 | 0.44..0.46 | 2.7% | 2.7% | 0.4% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.37 | 4.19..4.57 | 8.6% | 8.6% | 4.2% | moderate |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.37 | 4.19..4.57 | 8.6% | 8.6% | 4.2% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.72 | 0.56..0.79 | 30.7% | 30.7% | 8.7% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.72 | 0.56..0.79 | 30.7% | 30.7% | 8.7% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07..0.08 | 8.2% | 8.2% | 2.7% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07..0.08 | 8.2% | 8.2% | 2.7% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 7.18 | 5.22..7.41 | 30.6% | 30.6% | 3.2% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 7.18 | 5.22..7.41 | 30.6% | 30.6% | 3.2% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.46 | 0.44..0.62 | 39.0% | 39.0% | 4.3% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.46 | 0.44..0.62 | 39.0% | 39.0% | 4.3% | moderate |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.06 | 0.06..0.09 | 50.8% | 50.8% | 12.7% | noisy |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.06 | 0.06..0.09 | 50.8% | 50.8% | 12.7% | noisy |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.83 | 1.56..2.32 | 41.5% | 41.5% | 14.6% | noisy |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.83 | 1.56..2.32 | 41.5% | 41.5% | 14.6% | noisy |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.20 | 0.18..0.20 | 11.8% | 11.8% | 0.5% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.20 | 0.18..0.20 | 11.8% | 11.8% | 0.5% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.11 | 0.10..0.11 | 9.3% | 9.3% | 4.6% | moderate |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.11 | 0.10..0.11 | 9.3% | 9.3% | 4.6% | moderate |


## Comparison vs Previous Run

Previous: `2026-04-23T18-44-25-internal-perf-review.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.03 | 0.03 | -0.00 | ±10% / ±0.02 ms | 3.8% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | -0.00 | ±33% / ±0.02 ms | 22.2% | noisy | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.03 | 0.02 | -0.01 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02 | -0.00 | ±10% / ±0.02 ms | 5.6% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.29 | -0.01 | ±10% / ±0.03 ms | 6.9% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.29 | -0.01 | ±10% / ±0.03 ms | 6.9% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.30 | 0.31 | +0.01 | ±10% / ±0.03 ms | 6.5% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.15 | 0.15 | +0.00 | ±10% / ±0.02 ms | 6.7% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.36 | 0.42 | +0.06 | ±48% / ±0.20 ms | 47.6% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.09 | 0.10 | +0.01 | ±50% / ±0.05 ms | 50.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.66 | 0.72 | +0.06 | ±15% / ±0.11 ms | 15.3% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.08 | 0.09 | +0.01 | ±11% / ±0.02 ms | 11.1% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | -0.00 | ±18% / ±0.02 ms | 17.9% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±300% / ±0.02 ms | 300.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 110.22 | 105.89 | -4.33 | ±10% / ±11.02 ms | 5.7% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 238.40 | 240.04 | +1.64 | ±85% / ±203.65 ms | 84.8% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 220.53 | 218.86 | -1.67 | ±10% / ±22.05 ms | 1.7% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.11 | 14.79 | +0.68 | ±10% / ±1.48 ms | 7.3% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.11 | 14.79 | +0.68 | ±10% / ±1.48 ms | 7.3% | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 143726.00 | 106928.00 | -36798.00 | ±25% / ±36040.38 ms | 25.1% | stable | 🔴 Regression (-26%) |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01 | +0.00 | ±40% / ±0.02 ms | 33.3% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±27% / ±0.02 ms | 26.7% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.03 | +0.00 | ±27% / ±0.02 ms | 26.7% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±100% / ±0.02 ms | 100.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±108% / ±0.02 ms | 108.3% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±108% / ±0.02 ms | 108.3% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05 | -0.00 | ±10% / ±0.02 ms | 8.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.20 | +0.01 | ±10% / ±0.02 ms | 8.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.20 | +0.01 | ±10% / ±0.02 ms | 8.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 8.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 8.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.37 | 0.38 | +0.01 | ±10% / ±0.04 ms | 1.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.88 | 1.91 | +0.03 | ±10% / ±0.19 ms | 4.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.88 | 1.91 | +0.03 | ±10% / ±0.19 ms | 4.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.36 | +0.00 | ±10% / ±0.04 ms | 4.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.36 | +0.00 | ±10% / ±0.04 ms | 4.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.31 | 4.46 | +0.15 | ±12% / ±0.53 ms | 11.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 20.73 | 21.53 | +0.79 | ±16% / ±3.54 ms | 14.3% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 20.73 | 21.53 | +0.79 | ±16% / ±3.54 ms | 14.3% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.85 | 0.85 | -0.00 | ±10% / ±0.08 ms | 1.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.58 | 4.13 | +0.54 | ±74% / ±3.06 ms | 74.3% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.58 | 4.13 | +0.54 | ±74% / ±3.06 ms | 74.3% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.76 | 0.82 | +0.06 | ±10% / ±0.08 ms | 2.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.85 | 3.94 | +0.10 | ±32% / ±1.27 ms | 32.2% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.85 | 3.94 | +0.10 | ±32% / ±1.27 ms | 32.2% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.17 | 0.18 | +0.01 | ±10% / ±0.02 ms | 1.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.74 | 0.77 | +0.03 | ±11% / ±0.09 ms | 11.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.74 | 0.77 | +0.03 | ±11% / ±0.09 ms | 11.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.43 | 11.38 | +0.94 | ±28% / ±3.22 ms | 28.3% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 43.46 | 45.27 | +1.80 | ±52% / ±23.46 ms | 51.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 43.46 | 45.27 | +1.80 | ±52% / ±23.46 ms | 51.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.71 | 1.72 | +0.01 | ±10% / ±0.17 ms | 4.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.34 | 8.19 | -0.15 | ±10% / ±0.83 ms | 8.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.34 | 8.19 | -0.15 | ±10% / ±0.83 ms | 8.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03 | -0.00 | ±21% / ±0.02 ms | 17.2% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10 | +0.00 | ±12% / ±0.02 ms | 12.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.10 | 0.10 | +0.00 | ±12% / ±0.02 ms | 12.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.03 | +0.00 | ±246% / ±0.06 ms | 246.2% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.03 | +0.00 | ±246% / ±0.06 ms | 246.2% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.19 | 0.20 | +0.01 | ±10% / ±0.02 ms | 4.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.89 | 0.95 | +0.07 | ±10% / ±0.10 ms | 8.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.89 | 0.95 | +0.07 | ±10% / ±0.10 ms | 8.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.19 | 0.19 | -0.00 | ±10% / ±0.02 ms | 3.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.19 | 0.19 | -0.00 | ±10% / ±0.02 ms | 3.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.26 | 2.14 | -0.11 | ±10% / ±0.23 ms | 3.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 9.77 | 10.79 | +1.02 | ±117% / ±12.59 ms | 116.7% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 9.77 | 10.79 | +1.02 | ±117% / ±12.59 ms | 116.7% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.45 | 0.43 | -0.02 | ±10% / ±0.04 ms | 3.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.83 | 2.20 | +0.37 | ±21% / ±0.46 ms | 21.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.83 | 2.20 | +0.37 | ±21% / ±0.46 ms | 21.1% | moderate | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 1.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.04 | 0.04 | +0.00 | ±31% / ±0.02 ms | 31.4% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.31 | 0.30 | -0.01 | ±10% / ±0.03 ms | 2.7% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.30 | 0.29 | -0.01 | ±10% / ±0.03 ms | 2.4% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 3.1% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.52 | 0.52 | +0.00 | ±10% / ±0.05 ms | 1.9% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 3.9% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.89 | 0.92 | +0.02 | ±10% / ±0.09 ms | 4.7% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.27 | 0.28 | +0.01 | ±10% / ±0.03 ms | 4.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±313% / ±0.10 ms | 312.5% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02 | +0.00 | ±550% / ±0.09 ms | 550.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | +0.00 | ±108% / ±0.02 ms | 108.3% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.19 | 0.21 | +0.02 | ±28% / ±0.06 ms | 19.1% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.15 | 0.17 | +0.02 | ±32% / ±0.05 ms | 21.2% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.04 | -0.00 | ±24% / ±0.02 ms | 24.4% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.80 | 1.85 | +0.05 | ±10% / ±0.19 ms | 9.2% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.49 | 1.53 | +0.04 | ±10% / ±0.15 ms | 6.2% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.37 | 0.38 | +0.01 | ±10% / ±0.04 ms | 2.1% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.82 | 24.21 | +3.39 | ±23% / ±5.53 ms | 22.8% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 15.01 | 15.60 | +0.59 | ±10% / ±1.56 ms | 5.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.77 | 3.89 | +0.12 | ±10% / ±0.39 ms | 2.5% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±100% / ±0.02 ms | 100.0% | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.02 | +0.00 | ±456% / ±0.07 ms | 456.3% | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±1050% / ±0.02 ms | 1050.0% | noisy | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.04 | 0.06 | +0.01 | ±44% / ±0.02 ms | 30.9% | noisy | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±11% / ±0.02 ms | 11.1% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.37 | 0.41 | +0.05 | ±14% / ±0.06 ms | 14.5% | moderate | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.09 | +0.01 | ±29% / ±0.03 ms | 28.7% | moderate | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 4.43 | 5.41 | +0.98 | ±60% / ±3.25 ms | 53.9% | noisy | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.86 | 0.85 | -0.01 | ±22% / ±0.19 ms | 21.7% | moderate | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.24 | 0.25 | +0.00 | ±15% / ±0.04 ms | 14.6% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.24 | 0.25 | +0.00 | ±15% / ±0.04 ms | 14.6% | stable | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.57 | 0.54 | -0.02 | ±10% / ±0.06 ms | 7.2% | stable | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.57 | 0.54 | -0.02 | ±10% / ±0.06 ms | 7.2% | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | +0.00 | ±21% / ±0.02 ms | 20.6% | moderate | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03 | +0.00 | ±21% / ±0.02 ms | 20.6% | moderate | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.05 | +0.00 | ±30% / ±0.02 ms | 29.8% | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.05 | +0.00 | ±30% / ±0.02 ms | 29.8% | stable | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.36 | 3.85 | +0.49 | ±15% / ±0.59 ms | 11.0% | moderate | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.36 | 3.85 | +0.49 | ±15% / ±0.59 ms | 11.0% | moderate | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.06 | 1.79 | -0.27 | ±62% / ±1.28 ms | 62.2% | moderate | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.06 | 1.79 | -0.27 | ±62% / ±1.28 ms | 62.2% | moderate | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 7.22 | 7.45 | +0.23 | ±26% / ±1.92 ms | 20.8% | noisy | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 7.22 | 7.45 | +0.23 | ±26% / ±1.92 ms | 20.8% | noisy | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.18 | 0.23 | +0.05 | ±47% / ±0.11 ms | 37.9% | noisy | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.18 | 0.23 | +0.05 | ±47% / ±0.11 ms | 37.9% | noisy | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.07 | 0.06 | -0.01 | ±10% / ±0.02 ms | 3.4% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.07 | 0.06 | -0.01 | ±10% / ±0.02 ms | 3.4% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.47 | 0.45 | -0.02 | ±10% / ±0.05 ms | 2.7% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.47 | 0.45 | -0.02 | ±10% / ±0.05 ms | 2.7% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.14 | 4.37 | +0.23 | ±13% / ±0.55 ms | 8.6% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.14 | 4.37 | +0.23 | ±13% / ±0.55 ms | 8.6% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.56 | 0.72 | +0.16 | ±31% / ±0.22 ms | 30.7% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.56 | 0.72 | +0.16 | ±31% / ±0.22 ms | 30.7% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.07 | +0.00 | ±10% / ±0.02 ms | 8.2% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.07 | +0.00 | ±10% / ±0.02 ms | 8.2% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 6.59 | 7.18 | +0.59 | ±31% / ±2.20 ms | 30.6% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 6.59 | 7.18 | +0.59 | ±31% / ±2.20 ms | 30.6% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.43 | 0.46 | +0.03 | ±39% / ±0.18 ms | 39.0% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.43 | 0.46 | +0.03 | ±39% / ±0.18 ms | 39.0% | moderate | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.06 | +0.01 | ±51% / ±0.03 ms | 50.8% | noisy | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.06 | +0.01 | ±51% / ±0.03 ms | 50.8% | noisy | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.53 | 1.83 | +0.30 | ±44% / ±0.80 ms | 41.5% | noisy | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.53 | 1.83 | +0.30 | ±44% / ±0.80 ms | 41.5% | noisy | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.20 | +0.01 | ±12% / ±0.02 ms | 11.8% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.20 | +0.01 | ±12% / ±0.02 ms | 11.8% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.11 | +0.01 | ±14% / ±0.02 ms | 9.3% | moderate | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.11 | +0.01 | ±14% / ±0.02 ms | 9.3% | moderate | ⚪ Within noise |

**Summary:** 0 wins, 1 regressions, 152 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.02 | 0.00 | -0.02 MB | ±0.83 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 0.00 | 1.73 | +1.73 MB | ±1.87 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 0.00 | 7.88 | +7.88 MB | ±12.66 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 2.00 | 0.02 | -1.98 MB | ±2.65 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 0.00 | +0.00 MB | ±4.00 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 1.34 | 0.00 | -1.34 MB | ±5.25 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±5.88 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 11.36 | 3.34 | -8.02 MB | ±5.85 MB | 🟢 Win (-8.02 MB) |
| Memory / Select 10k rows → Maps / resqlite select() | 5.45 | 5.53 | +0.08 MB | ±3.67 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite3 select() | 2.66 | 3.00 | +0.34 MB | ±3.30 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 1.00 | 1.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.06 | 0.06 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 1 wins, 0 regressions, 14 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 3969 | 2614 | -1355 | ±100 | 🟢 Fewer re-emits (-1355) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 600 | +590 | ±100 | 🔴 More re-emits (+590) |
| Streaming (Column Granularity) / Overlapping column write... | 3879 | 2116 | -1763 | ±100 | 🔴 Invalidation elided (-1763) — writes not firing |

**Granularity summary:** 1 fewer-re-emit, 2 more-re-emit, 3 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.
