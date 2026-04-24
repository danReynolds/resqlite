# resqlite Benchmark Results

Generated: 2026-04-24T07:27:09.939607

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp098-json-col-prefix-cache`
- Repeats: `3`
- Runtime: `dart-vm / Dart 3.11.0`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `danreynolds/sad-payne-786cf2 @ 9f6b4f6648e2 (dirty)`
- Comparison baseline: `2026-04-23T19-38-11-exp097-one-pass-initial-stream-hash.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.011 | 0.013 | 0.001 | 0.001 |
| sqlite3 select() | 0.015 | 0.016 | 0.015 | 0.016 |
| sqlite_async select() | 0.030 | 0.034 | 0.001 | 0.001 |
| drift select() | 0.036 | 0.039 | 0.001 | 0.001 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.046 | 0.052 | 0.008 | 0.009 |
| sqlite3 select() | 0.112 | 0.141 | 0.112 | 0.141 |
| sqlite_async select() | 0.121 | 0.124 | 0.009 | 0.010 |
| drift select() | 0.193 | 0.201 | 0.012 | 0.014 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.377 | 0.429 | 0.086 | 0.091 |
| sqlite3 select() | 1.089 | 1.241 | 1.089 | 1.241 |
| sqlite_async select() | 1.055 | 1.176 | 0.096 | 0.104 |
| drift select() | 1.575 | 1.787 | 0.092 | 0.095 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.416 | 12.050 | 0.853 | 2.070 |
| sqlite3 select() | 13.300 | 15.956 | 13.300 | 15.956 |
| sqlite_async select() | 12.411 | 13.515 | 0.941 | 2.329 |
| drift select() | 23.033 | 32.827 | 0.981 | 3.192 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.029 | 0.031 | 0.017 | 0.018 |
| sqlite3 + jsonEncode | 0.031 | 0.033 | 0.031 | 0.033 |
| sqlite_async + jsonEncode | 0.046 | 0.057 | 0.016 | 0.017 |
| drift + jsonEncode | 0.052 | 0.054 | 0.016 | 0.017 |
| resqlite selectBytes() | 0.011 | 0.011 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.198 | 0.228 | 0.158 | 0.163 |
| sqlite3 + jsonEncode | 0.252 | 0.299 | 0.252 | 0.299 |
| sqlite_async + jsonEncode | 0.264 | 0.286 | 0.152 | 0.158 |
| drift + jsonEncode | 0.335 | 0.384 | 0.154 | 0.169 |
| resqlite selectBytes() | 0.042 | 0.044 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.825 | 2.118 | 1.509 | 1.597 |
| sqlite3 + jsonEncode | 2.503 | 2.613 | 2.503 | 2.613 |
| sqlite_async + jsonEncode | 2.518 | 4.793 | 1.519 | 2.503 |
| drift + jsonEncode | 3.049 | 4.025 | 1.492 | 2.518 |
| resqlite selectBytes() | 0.331 | 0.359 | 0.000 | 0.000 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.204 | 25.622 | 15.081 | 16.821 |
| sqlite3 + jsonEncode | 30.912 | 35.794 | 30.912 | 35.794 |
| sqlite_async + jsonEncode | 29.940 | 36.919 | 15.518 | 17.009 |
| drift + jsonEncode | 38.611 | 47.240 | 15.655 | 20.295 |
| resqlite selectBytes() | 3.413 | 3.551 | 0.001 | 0.004 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.102 | 0.108 | 0.035 | 0.037 |
| sqlite3 | 0.321 | 0.344 | 0.321 | 0.344 |
| sqlite_async | 0.359 | 0.413 | 0.041 | 0.045 |
| drift | 0.586 | 0.630 | 0.041 | 0.045 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.917 | 0.972 | 0.266 | 0.282 |
| sqlite3 | 3.411 | 5.598 | 3.411 | 5.598 |
| sqlite_async | 2.911 | 3.329 | 0.327 | 0.342 |
| drift | 4.749 | 5.904 | 0.324 | 0.342 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.560 | 0.629 | 0.103 | 0.106 |
| sqlite3 | 1.496 | 1.617 | 1.496 | 1.617 |
| sqlite_async | 1.404 | 1.699 | 0.118 | 0.127 |
| drift | 2.047 | 2.444 | 0.119 | 0.128 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.302 | 0.348 | 0.098 | 0.102 |
| sqlite3 | 1.018 | 1.101 | 1.018 | 1.101 |
| sqlite_async | 0.962 | 1.081 | 0.120 | 0.131 |
| drift | 1.600 | 1.839 | 0.121 | 0.124 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.311 | 0.501 | 0.101 | 0.143 |
| sqlite3 | 0.988 | 1.052 | 0.988 | 1.052 |
| sqlite_async | 0.945 | 1.055 | 0.118 | 0.125 |
| drift | 1.612 | 2.152 | 0.122 | 0.129 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.010 | 0.012 | 0.001 | 0.001 |
| sqlite3 | 0.016 | 0.019 | 0.016 | 0.019 |
| sqlite_async | 0.034 | 0.297 | 0.001 | 0.008 |
| drift | 0.050 | 0.087 | 0.001 | 0.003 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.031 | 0.053 | 0.005 | 0.005 |
| sqlite3 | 0.063 | 0.068 | 0.063 | 0.068 |
| sqlite_async | 0.076 | 0.079 | 0.005 | 0.005 |
| drift | 0.114 | 0.147 | 0.005 | 0.006 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.051 | 0.063 | 0.009 | 0.010 |
| sqlite3 | 0.119 | 0.121 | 0.119 | 0.121 |
| sqlite_async | 0.130 | 0.142 | 0.010 | 0.011 |
| drift | 0.208 | 0.269 | 0.011 | 0.015 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.207 | 0.221 | 0.046 | 0.050 |
| sqlite3 | 0.558 | 0.635 | 0.558 | 0.635 |
| sqlite_async | 0.516 | 0.549 | 0.046 | 0.050 |
| drift | 0.802 | 0.861 | 0.047 | 0.049 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.375 | 0.382 | 0.087 | 0.090 |
| sqlite3 | 1.080 | 1.173 | 1.080 | 1.173 |
| sqlite_async | 0.991 | 1.049 | 0.090 | 0.093 |
| drift | 1.548 | 1.599 | 0.090 | 0.091 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.784 | 0.808 | 0.175 | 0.185 |
| sqlite3 | 2.178 | 2.789 | 2.178 | 2.789 |
| sqlite_async | 2.066 | 2.366 | 0.184 | 0.196 |
| drift | 3.153 | 4.816 | 0.183 | 0.208 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.196 | 5.017 | 0.446 | 0.493 |
| sqlite3 | 5.504 | 7.488 | 5.504 | 7.488 |
| sqlite_async | 5.732 | 10.706 | 0.480 | 0.518 |
| drift | 8.689 | 9.131 | 0.477 | 0.504 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.703 | 10.940 | 0.925 | 4.202 |
| sqlite3 | 14.360 | 17.540 | 14.360 | 17.540 |
| sqlite_async | 12.326 | 15.685 | 0.921 | 1.581 |
| drift | 22.080 | 29.034 | 0.938 | 3.353 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 11.548 | 23.852 | 1.876 | 4.146 |
| sqlite3 | 31.166 | 42.355 | 31.166 | 42.355 |
| sqlite_async | 37.731 | 51.226 | 1.886 | 5.625 |
| drift | 51.624 | 65.729 | 1.859 | 7.469 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.029 | 0.036 | 0.029 | 0.036 |
| sqlite3 + jsonEncode | 0.031 | 0.035 | 0.031 | 0.035 |
| sqlite_async + jsonEncode | 0.052 | 0.084 | 0.052 | 0.084 |
| drift + jsonEncode | 0.054 | 0.078 | 0.054 | 0.078 |
| resqlite selectBytes() | 0.011 | 0.012 | 0.011 | 0.012 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.104 | 0.108 | 0.104 | 0.108 |
| sqlite3 + jsonEncode | 0.133 | 0.143 | 0.133 | 0.143 |
| sqlite_async + jsonEncode | 0.146 | 0.152 | 0.146 | 0.152 |
| drift + jsonEncode | 0.179 | 0.225 | 0.179 | 0.225 |
| resqlite selectBytes() | 0.025 | 0.028 | 0.025 | 0.028 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.195 | 0.234 | 0.195 | 0.234 |
| sqlite3 + jsonEncode | 0.263 | 0.292 | 0.263 | 0.292 |
| sqlite_async + jsonEncode | 0.264 | 0.283 | 0.264 | 0.283 |
| drift + jsonEncode | 0.321 | 0.354 | 0.321 | 0.354 |
| resqlite selectBytes() | 0.042 | 0.045 | 0.042 | 0.045 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.909 | 0.998 | 0.909 | 0.998 |
| sqlite3 + jsonEncode | 1.320 | 2.839 | 1.320 | 2.839 |
| sqlite_async + jsonEncode | 1.224 | 1.951 | 1.224 | 1.951 |
| drift + jsonEncode | 1.548 | 1.774 | 1.548 | 1.774 |
| resqlite selectBytes() | 0.170 | 0.180 | 0.170 | 0.180 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.806 | 3.652 | 1.806 | 3.652 |
| sqlite3 + jsonEncode | 2.535 | 4.144 | 2.535 | 4.144 |
| sqlite_async + jsonEncode | 2.387 | 2.680 | 2.387 | 2.680 |
| drift + jsonEncode | 2.948 | 4.262 | 2.948 | 4.262 |
| resqlite selectBytes() | 0.334 | 0.343 | 0.334 | 0.343 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.949 | 14.793 | 3.949 | 14.793 |
| sqlite3 + jsonEncode | 5.315 | 9.335 | 5.315 | 9.335 |
| sqlite_async + jsonEncode | 5.306 | 9.530 | 5.306 | 9.530 |
| drift + jsonEncode | 7.138 | 13.829 | 7.138 | 13.829 |
| resqlite selectBytes() | 0.766 | 1.498 | 0.766 | 1.498 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 10.614 | 20.100 | 10.614 | 20.100 |
| sqlite3 + jsonEncode | 14.173 | 18.230 | 14.173 | 18.230 |
| sqlite_async + jsonEncode | 14.851 | 21.194 | 14.851 | 21.194 |
| drift + jsonEncode | 17.556 | 25.935 | 17.556 | 25.935 |
| resqlite selectBytes() | 2.065 | 3.355 | 2.065 | 3.355 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.575 | 25.219 | 20.575 | 25.219 |
| sqlite3 + jsonEncode | 30.788 | 36.080 | 30.788 | 36.080 |
| sqlite_async + jsonEncode | 29.721 | 36.904 | 29.721 | 36.904 |
| drift + jsonEncode | 39.505 | 50.073 | 39.505 | 50.073 |
| resqlite selectBytes() | 3.409 | 3.536 | 3.409 | 3.536 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 42.240 | 47.970 | 42.240 | 47.970 |
| sqlite3 + jsonEncode | 65.441 | 76.249 | 65.441 | 76.249 |
| sqlite_async + jsonEncode | 69.541 | 89.295 | 69.541 | 89.295 |
| drift + jsonEncode | 84.041 | 106.905 | 84.041 | 106.905 |
| resqlite selectBytes() | 8.204 | 14.225 | 8.204 | 14.225 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.32 | 0.41 | 0.32 |
| sqlite_async | 0.97 | 1.34 | 0.97 |
| drift | 1.65 | 2.04 | 1.65 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.34 | 0.39 | 0.17 |
| sqlite_async | 1.36 | 1.67 | 0.68 |
| drift | 2.79 | 3.03 | 1.39 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.39 | 0.46 | 0.10 |
| sqlite_async | 2.18 | 3.01 | 0.54 |
| drift | 5.27 | 5.97 | 1.32 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 1.30 | 3.28 | 0.16 |
| sqlite_async | 4.65 | 5.24 | 0.58 |
| drift | 10.40 | 11.12 | 1.30 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 136897 |
| resqlite per query | 0.007 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 136897 | 112232..140690 | 10.4 | 10.5 |
| sqlite3 | 187696 | 176369..192001 | 4.2 | 10.8 |
| sqlite_async | 49367 | 48074..49678 | 1.6 | 2.3 |
| drift | 45258 | 45165..45575 | 0.5 | 2.1 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.903 | 17.977 | 14.903 | 17.977 |
| sqlite_async | 35.479 | 35.929 | 35.479 | 35.929 |
| drift | 53.868 | 67.939 | 53.868 | 67.939 |
| sqlite3 (no cache) | 24.433 | 24.801 | 24.433 | 24.801 |
| sqlite3 (cached stmt) | 25.278 | 31.416 | 25.278 | 31.416 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.661 | 2.274 | 1.661 | 2.274 |
| sqlite3 execute() | 0.916 | 1.606 | 0.916 | 1.606 |
| sqlite_async execute() | 2.875 | 3.630 | 2.875 | 3.630 |
| drift execute() | 2.765 | 3.362 | 2.765 | 3.362 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.055 | 0.059 | 0.055 | 0.059 |
| sqlite3 executeBatch() | 0.047 | 0.049 | 0.047 | 0.049 |
| sqlite_async executeBatch() | 0.097 | 0.107 | 0.097 | 0.107 |
| drift executeBatch() | 0.115 | 0.121 | 0.115 | 0.121 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.428 | 0.452 | 0.428 | 0.452 |
| sqlite3 executeBatch() | 0.442 | 0.479 | 0.442 | 0.479 |
| sqlite_async executeBatch() | 0.516 | 0.538 | 0.516 | 0.538 |
| drift executeBatch() | 0.639 | 0.679 | 0.639 | 0.679 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.260 | 5.286 | 4.260 | 5.286 |
| sqlite3 executeBatch() | 4.172 | 4.955 | 4.172 | 4.955 |
| sqlite_async executeBatch() | 4.901 | 5.367 | 4.901 | 5.367 |
| drift executeBatch() | 6.250 | 7.074 | 6.250 | 7.074 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.049 | 0.053 | 0.049 | 0.053 |
| sqlite_async writeTransaction() | 0.079 | 0.088 | 0.079 | 0.088 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.071 | 0.080 | 0.071 | 0.080 |
| resqlite tx.execute() loop | 0.573 | 0.769 | 0.573 | 0.769 |
| sqlite_async tx.execute() loop | 1.000 | 1.196 | 1.000 | 1.196 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.440 | 0.550 | 0.440 | 0.550 |
| resqlite tx.execute() loop | 5.526 | 6.559 | 5.526 | 6.559 |
| sqlite_async tx.execute() loop | 15.874 | 20.334 | 15.874 | 20.334 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.105 | 0.112 | 0.105 | 0.112 |
| sqlite_async tx.getAll() | 0.232 | 0.381 | 0.232 | 0.381 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.184 | 0.187 | 0.184 | 0.187 |
| sqlite_async tx.getAll() | 0.351 | 0.371 | 0.351 | 0.371 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.026 | 0.033 | 0.026 | 0.033 |
| sqlite_async watch() | 0.116 | 0.251 | 0.116 | 0.251 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.044 | 0.065 | 0.044 | 0.065 |
| sqlite_async | 0.066 | 0.082 | 0.066 | 0.082 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.180 | 0.248 | 0.180 | 0.248 |
| sqlite_async | 0.618 | 2.338 | 0.618 | 2.338 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.232 | 0.314 | 0.232 | 0.314 |
| sqlite_async | 0.254 | 0.310 | 0.254 | 0.310 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.254 | 1.254 | 1.254 | 1.254 |
| sqlite_async | 8.268 | 8.268 | 8.268 | 8.268 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.382 | 3.922 | 3.382 | 3.922 |
| sqlite_async | 5.880 | 11.225 | 5.880 | 11.225 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.522 | 0.785 | 0.522 | 0.785 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 5.607 | 5.935 | 5.607 | 5.935 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. On resqlite's main branch this ratio is driven toward 0 by experiment 075 (C-side result-hash short-circuit), not by writer-side column-tracking (exp 052 is not implemented). The two mechanisms are indistinguishable on this read-side benchmark.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 70.2 | 0.000 |
| sqlite_async | 3756 | 959.3 | 1.011 |
| drift | 5000 | 1012.5 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 71.1 | 0.000 |
| sqlite_async | 3714 | 1049.0 | 1.011 |
| drift | 5000 | 1156.8 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 227.82 | 228.84 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 441.10 | 442.11 | 0.00 | 0.00 | 1112 | 3 |
| drift stream() | 543.98 | 554.89 | 0.01 | 0.01 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.033 | 0.084 | 0.000 | 0.000 |
| sqlite3 | 0.022 | 0.042 | 0.022 | 0.042 |
| sqlite_async | 0.038 | 0.051 | 0.000 | 0.000 |
| drift | 0.039 | 0.058 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.023 | 0.064 | 0.000 | 0.000 |
| sqlite3 | 0.014 | 0.022 | 0.014 | 0.022 |
| sqlite_async | 0.030 | 0.038 | 0.000 | 0.000 |
| drift | 0.031 | 0.043 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.030 | 0.061 | 0.000 | 0.000 |
| sqlite3 | 0.032 | 0.036 | 0.032 | 0.036 |
| sqlite_async | 0.056 | 0.067 | 0.000 | 0.000 |
| drift | 0.054 | 0.061 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.010 | 0.028 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.007 | 0.005 | 0.007 |
| sqlite_async | 0.021 | 0.025 | 0.000 | 0.000 |
| drift | 0.020 | 0.026 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.039 | 0.045 | 0.001 | 0.001 |
| sqlite3 | 0.066 | 0.068 | 0.066 | 0.068 |
| sqlite_async | 0.083 | 0.091 | 0.001 | 0.001 |
| drift | 0.090 | 0.100 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 107.387 | 109.203 | 0.000 | 0.000 | 0 |
| sqlite_async | 215.639 | 216.603 | 0.000 | 0.000 | 43 |
| drift | 225.391 | 226.130 | 0.000 | 0.023 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 238.53 | 238.53 | 0.00 | 0.00 | 13.39 | 225.13 | 0 |
| sqlite_async | 482.18 | 482.18 | 0.00 | 0.00 | 24.08 | 458.10 | 1165 |
| drift | 1796.57 | 1796.57 | 0.11 | 0.11 | 14.88 | 1781.68 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 1.39 | 10.31 | 0.00..7.13 | ±3.56 |
| sqlite3 select() | 5.19 | 9.08 | 0.00..8.14 | ±4.07 |
| sqlite_async select() | 1.00 | 1.00 | 1.00..1.00 | ±0.00 |
| drift select() | 5.84 | 73.27 | 0.00..10.52 | ±5.26 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 10.00 | 0.00..8.00 | ±4.00 |
| resqlite + jsonEncode | 0.00 | 44.88 | 0.00..22.84 | ±11.42 |
| sqlite3 + jsonEncode | 1.64 | 41.22 | 0.00..9.67 | ±4.84 |
| sqlite_async + jsonEncode | 0.00 | 19.69 | 0.00..14.61 | ±7.30 |
| drift + jsonEncode | 8.11 | 50.25 | 0.00..13.56 | ±6.78 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.00 | 4.09 | 0.00..1.66 | ±0.83 |
| sqlite3 executeBatch() | 0.00 | 0.50 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| drift batch() | 0.00 | 4.50 | 0.00..2.50 | ±1.25 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.05 | 0.14 | 0.00..0.06 | ±0.03 |
| sqlite_async watch() | 0.00 | 0.50 | 0.00..0.03 | ±0.02 |

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
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.03 | 0.03..0.03 | 14.3% | 14.3% | 7.1% | moderate |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 20.0% | 20.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.03 | 0.02..0.03 | 35.7% | 35.7% | 17.9% | noisy |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02..0.02 | 30.0% | 30.0% | 15.0% | noisy |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.31 | 0.30..0.32 | 6.5% | 6.5% | 3.2% | moderate |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.31 | 0.30..0.32 | 6.5% | 6.5% | 3.2% | moderate |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.34 | 0.32..0.35 | 8.8% | 8.8% | 2.9% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.17 | 0.16..0.18 | 11.8% | 11.8% | 5.9% | moderate |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.39 | 0.37..0.39 | 5.1% | 5.1% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.10 | 0.09..0.10 | 10.0% | 10.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.78 | 0.72..1.30 | 74.4% | 74.4% | 7.7% | moderate |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.10 | 0.09..0.16 | 70.0% | 70.0% | 10.0% | noisy |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.04 | 2.5% | 2.5% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 300.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 108.33 | 107.39..109.26 | 1.7% | 1.7% | 0.9% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 240.05 | 238.53..240.08 | 0.6% | 0.6% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 226.00 | 221.46..227.82 | 2.8% | 2.8% | 0.8% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 14.90 | 14.80..15.14 | 2.3% | 2.3% | 0.7% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 14.90 | 14.80..15.14 | 2.3% | 2.3% | 0.7% | stable |
| Point Query Throughput / resqlite qps | 140873.00 | 136897.00..142061.00 | 3.7% | 3.7% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.02 | 63.6% | 63.6% | 9.1% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.04 | 37.9% | 37.9% | 3.4% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.04 | 37.9% | 37.9% | 3.4% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 100.0% | 100.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 63.6% | 63.6% | 9.1% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.02 | 63.6% | 63.6% | 9.1% | noisy |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.04..0.05 | 12.0% | 12.0% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.20 | 0.19..0.20 | 3.6% | 3.6% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.20 | 0.19..0.20 | 3.6% | 3.6% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.05 | 19.0% | 19.0% | 2.4% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.04 | 0.04..0.05 | 19.0% | 19.0% | 2.4% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.39 | 0.38..0.40 | 7.5% | 7.5% | 2.6% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.81 | 1.78..1.81 | 1.6% | 1.6% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.81 | 1.78..1.81 | 1.6% | 1.6% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09..0.09 | 2.3% | 2.3% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.33 | 0.33..0.33 | 1.5% | 1.5% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.33 | 0.33..0.33 | 1.5% | 1.5% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.71 | 4.70..5.10 | 8.4% | 8.4% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 20.96 | 20.57..23.22 | 12.6% | 12.6% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 20.96 | 20.57..23.22 | 12.6% | 12.6% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.90 | 0.84..0.93 | 9.2% | 9.2% | 2.4% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 3.51 | 3.41..3.56 | 4.2% | 4.2% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 3.51 | 3.41..3.56 | 4.2% | 4.2% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.81 | 0.78..0.82 | 5.0% | 5.0% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.81 | 3.78..3.95 | 4.4% | 4.4% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.81 | 3.78..3.95 | 4.4% | 4.4% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.18 | 0.17..0.18 | 1.1% | 1.1% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.79 | 0.77..0.80 | 4.6% | 4.6% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.79 | 0.77..0.80 | 4.6% | 4.6% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 11.55 | 10.78..14.36 | 30.9% | 30.9% | 6.6% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 43.87 | 42.24..44.48 | 5.1% | 5.1% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 43.87 | 42.24..44.48 | 5.1% | 5.1% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.88 | 1.69..1.88 | 10.4% | 10.4% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 8.02 | 8.01..8.20 | 2.4% | 2.4% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 8.02 | 8.01..8.20 | 2.4% | 2.4% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03..0.03 | 13.3% | 13.3% | 3.3% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10..0.11 | 5.8% | 5.8% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.10 | 0.10..0.11 | 5.8% | 5.8% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.01 | 25.0% | 25.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.02..0.03 | 28.0% | 28.0% | 8.0% | noisy |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.02..0.03 | 28.0% | 28.0% | 8.0% | noisy |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.22 | 0.21..0.23 | 12.0% | 12.0% | 4.2% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.91 | 0.91..0.92 | 1.4% | 1.4% | 0.1% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.91 | 0.91..0.92 | 1.4% | 1.4% | 0.1% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.05 | 0.04..0.05 | 6.5% | 6.5% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.17 | 0.17..0.17 | 3.5% | 3.5% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.17 | 0.17..0.17 | 3.5% | 3.5% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.20 | 2.19..2.29 | 4.3% | 4.3% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 11.19 | 10.61..12.32 | 15.2% | 15.2% | 5.2% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 11.19 | 10.61..12.32 | 15.2% | 15.2% | 5.2% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.44 | 0.44..0.45 | 1.8% | 1.8% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 2.11 | 2.06..2.27 | 9.6% | 9.6% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 2.11 | 2.06..2.27 | 9.6% | 9.6% | 1.9% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.10 | 0.10..0.10 | 2.0% | 2.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.04 | 0.03..0.04 | 31.4% | 31.4% | 2.9% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.31 | 0.31..0.31 | 1.6% | 1.6% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.10 | 0.10..0.10 | 2.0% | 2.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.30 | 0.30..0.31 | 4.0% | 4.0% | 1.7% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.10 | 0.10..0.10 | 3.1% | 3.1% | 1.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.54 | 0.53..0.56 | 4.9% | 4.9% | 0.4% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.10 | 0.10..0.10 | 3.0% | 3.0% | 1.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.92 | 0.91..0.92 | 0.5% | 0.5% | 0.2% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.27 | 0.27..0.27 | 0.7% | 0.7% | 0.4% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.05 | 89.7% | 89.7% | 6.9% | moderate |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02..0.04 | 117.6% | 117.6% | 5.9% | moderate |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 72.7% | 72.7% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.21 | 0.20..0.23 | 13.6% | 13.6% | 6.1% | moderate |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.17 | 0.16..0.18 | 12.4% | 12.4% | 5.9% | moderate |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.05 | 21.4% | 21.4% | 4.8% | moderate |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.82 | 1.76..1.85 | 4.8% | 4.8% | 1.3% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.50 | 1.45..1.51 | 4.3% | 4.3% | 0.5% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.33 | 0.33..0.34 | 1.8% | 1.8% | 0.6% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.69 | 20.20..23.72 | 17.0% | 17.0% | 2.3% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 14.87 | 14.85..15.08 | 1.6% | 1.6% | 0.1% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.52 | 3.41..3.54 | 3.6% | 3.6% | 0.6% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 100.0% | 100.0% | 33.3% | noisy |
| Select → Maps / 10 rows / resqlite select() | 0.02 | 0.01..0.08 | 405.6% | 405.6% | 38.9% | noisy |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 1050.0% | 1050.0% | 50.0% | noisy |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.04..0.06 | 39.1% | 39.1% | 2.2% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 25.0% | 25.0% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.38 | 0.38..0.42 | 12.7% | 12.7% | 0.5% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.07..0.09 | 14.1% | 14.1% | 1.2% | stable |
| Select → Maps / 10000 rows / resqlite select() | 4.50 | 4.42..4.50 | 1.8% | 1.8% | 0.0% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.85 | 0.69..0.86 | 20.3% | 20.3% | 0.7% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.23 | 0.23..0.47 | 104.7% | 104.7% | 2.6% | stable |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.23 | 0.23..0.47 | 104.7% | 104.7% | 2.6% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.52 | 0.52..0.54 | 3.1% | 3.1% | 0.0% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.52 | 0.52..0.54 | 3.1% | 3.1% | 0.0% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03..0.06 | 125.0% | 125.0% | 7.1% | moderate |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03..0.06 | 125.0% | 125.0% | 7.1% | moderate |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.04..0.06 | 40.0% | 40.0% | 12.0% | noisy |
| Streaming / Invalidation Latency / resqlite [main] | 0.05 | 0.04..0.06 | 40.0% | 40.0% | 12.0% | noisy |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.44 | 3.38..3.58 | 5.7% | 5.7% | 1.8% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.44 | 3.38..3.58 | 5.7% | 5.7% | 1.8% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.35 | 1.25..2.62 | 100.5% | 100.5% | 7.5% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.35 | 1.25..2.62 | 100.5% | 100.5% | 7.5% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 5.88 | 5.61..6.04 | 7.3% | 7.3% | 2.7% | stable |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 5.88 | 5.61..6.04 | 7.3% | 7.3% | 2.7% | stable |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.28 | 0.18..0.49 | 111.7% | 111.7% | 35.9% | noisy |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.28 | 0.18..0.49 | 111.7% | 111.7% | 35.9% | noisy |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.06..0.06 | 3.5% | 3.5% | 0.0% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.06 | 0.06..0.06 | 3.5% | 3.5% | 0.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.43 | 0.43..0.43 | 0.9% | 0.9% | 0.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.43 | 0.43..0.43 | 0.9% | 0.9% | 0.0% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.47 | 4.26..4.62 | 7.9% | 7.9% | 3.3% | moderate |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.47 | 4.26..4.62 | 7.9% | 7.9% | 3.3% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.57 | 0.56..0.59 | 6.1% | 6.1% | 2.8% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.57 | 0.56..0.59 | 6.1% | 6.1% | 2.8% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07..0.07 | 7.0% | 7.0% | 1.4% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07..0.07 | 7.0% | 7.0% | 1.4% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.55 | 5.53..5.93 | 7.2% | 7.2% | 0.5% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.55 | 5.53..5.93 | 7.2% | 7.2% | 0.5% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.44 | 0.44..0.45 | 2.3% | 2.3% | 0.5% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.44 | 0.44..0.45 | 2.3% | 2.3% | 0.5% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05..0.09 | 75.5% | 75.5% | 2.0% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05..0.09 | 75.5% | 75.5% | 2.0% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.68 | 1.66..1.74 | 4.7% | 4.7% | 0.8% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.68 | 1.66..1.74 | 4.7% | 4.7% | 0.8% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.18..0.20 | 5.8% | 5.8% | 2.1% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.18..0.20 | 5.8% | 5.8% | 2.1% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.11 | 0.10..0.11 | 4.7% | 4.7% | 1.9% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.11 | 0.10..0.11 | 4.7% | 4.7% | 1.9% | stable |


## Comparison vs Previous Run

Previous: `2026-04-23T19-38-11-exp097-one-pass-initial-stream-hash.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.02 | 0.03 | +0.01 | ±21% / ±0.02 ms | 14.3% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | +0.00 | ±20% / ±0.02 ms | 20.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.03 | +0.01 | ±54% / ±0.02 ms | 35.7% | noisy | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.02 | +0.01 | ±45% / ±0.02 ms | 30.0% | noisy | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.29 | 0.31 | +0.02 | ±10% / ±0.03 ms | 6.5% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.29 | 0.31 | +0.02 | ±10% / ±0.03 ms | 6.5% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.31 | 0.34 | +0.03 | ±10% / ±0.03 ms | 8.8% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.16 | 0.17 | +0.01 | ±18% / ±0.03 ms | 11.8% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.81 | 0.39 | -0.42 | ±10% / ±0.08 ms | 5.1% | stable | 🟢 Win (-52%) |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.20 | 0.10 | -0.10 | ±10% / ±0.02 ms | 10.0% | stable | 🟢 Win (-50%) |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.65 | 0.78 | +0.13 | ±74% / ±0.58 ms | 74.4% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.08 | 0.10 | +0.02 | ±70% / ±0.07 ms | 70.0% | noisy | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 2.5% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±300% / ±0.02 ms | 300.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 108.94 | 108.33 | -0.61 | ±10% / ±10.89 ms | 1.7% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 240.69 | 240.05 | -0.64 | ±10% / ±24.07 ms | 0.6% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 225.54 | 226.00 | +0.46 | ±10% / ±22.60 ms | 2.8% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.19 | 14.90 | +0.71 | ±10% / ±1.49 ms | 2.3% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.19 | 14.90 | +0.71 | ±10% / ±1.49 ms | 2.3% | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 129410.00 | 140873.00 | +11463.00 | ±10% / ±14087.30 ms | 3.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01 | +0.00 | ±64% / ±0.02 ms | 63.6% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±38% / ±0.02 ms | 37.9% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.03 | +0.00 | ±38% / ±0.02 ms | 37.9% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±100% / ±0.02 ms | 100.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±64% / ±0.02 ms | 63.6% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±64% / ±0.02 ms | 63.6% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.05 | +0.01 | ±12% / ±0.02 ms | 12.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.20 | +0.00 | ±10% / ±0.02 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.20 | +0.00 | ±10% / ±0.02 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | -0.00 | ±19% / ±0.02 ms | 19.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | -0.00 | ±19% / ±0.02 ms | 19.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.37 | 0.39 | +0.02 | ±10% / ±0.04 ms | 7.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.71 | 1.81 | +0.09 | ±10% / ±0.18 ms | 1.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.71 | 1.81 | +0.09 | ±10% / ±0.18 ms | 1.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.33 | -0.02 | ±10% / ±0.03 ms | 1.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.33 | -0.02 | ±10% / ±0.03 ms | 1.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.19 | 4.71 | +0.53 | ±10% / ±0.47 ms | 8.4% | stable | 🔴 Regression (+13%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 21.96 | 20.96 | -1.01 | ±13% / ±2.77 ms | 12.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 21.96 | 20.96 | -1.01 | ±13% / ±2.77 ms | 12.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.83 | 0.90 | +0.07 | ±10% / ±0.09 ms | 9.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.68 | 3.51 | -0.18 | ±10% / ±0.37 ms | 4.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.68 | 3.51 | -0.18 | ±10% / ±0.37 ms | 4.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.75 | 0.81 | +0.06 | ±10% / ±0.08 ms | 5.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.62 | 3.81 | +0.19 | ±10% / ±0.38 ms | 4.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.62 | 3.81 | +0.19 | ±10% / ±0.38 ms | 4.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.17 | 0.18 | +0.01 | ±10% / ±0.02 ms | 1.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.86 | 0.79 | -0.07 | ±10% / ±0.09 ms | 4.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.86 | 0.79 | -0.07 | ±10% / ±0.09 ms | 4.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.44 | 11.55 | +1.11 | ±31% / ±3.57 ms | 30.9% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 44.76 | 43.87 | -0.89 | ±10% / ±4.48 ms | 5.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 44.76 | 43.87 | -0.89 | ±10% / ±4.48 ms | 5.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.65 | 1.88 | +0.22 | ±10% / ±0.19 ms | 10.4% | stable | 🔴 Regression (+13%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.08 | 8.02 | -0.05 | ±10% / ±0.81 ms | 2.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.08 | 8.02 | -0.05 | ±10% / ±0.81 ms | 2.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03 | +0.00 | ±13% / ±0.02 ms | 13.3% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 5.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 5.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±25% / ±0.02 ms | 25.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | +0.00 | ±28% / ±0.02 ms | 28.0% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | +0.00 | ±28% / ±0.02 ms | 28.0% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.18 | 0.22 | +0.03 | ±13% / ±0.03 ms | 12.0% | moderate | 🔴 Regression (+17%) |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.88 | 0.91 | +0.03 | ±10% / ±0.09 ms | 1.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.88 | 0.91 | +0.03 | ±10% / ±0.09 ms | 1.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.05 | +0.00 | ±10% / ±0.02 ms | 6.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.17 | -0.01 | ±10% / ±0.02 ms | 3.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.17 | -0.01 | ±10% / ±0.02 ms | 3.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.21 | 2.20 | -0.02 | ±10% / ±0.22 ms | 4.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 9.74 | 11.19 | +1.45 | ±15% / ±1.73 ms | 15.2% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 9.74 | 11.19 | +1.45 | ±15% / ±1.73 ms | 15.2% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.44 | 0.44 | +0.00 | ±10% / ±0.04 ms | 1.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.99 | 2.11 | +0.11 | ±10% / ±0.21 ms | 9.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.99 | 2.11 | +0.11 | ±10% / ±0.21 ms | 9.6% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.04 | 0.04 | -0.00 | ±31% / ±0.02 ms | 31.4% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.29 | 0.31 | +0.02 | ±10% / ±0.03 ms | 1.6% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.28 | 0.30 | +0.02 | ±10% / ±0.03 ms | 4.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 3.1% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.51 | 0.54 | +0.02 | ±10% / ±0.05 ms | 4.9% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 3.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.92 | 0.92 | -0.00 | ±10% / ±0.09 ms | 0.5% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.28 | 0.27 | -0.01 | ±10% / ±0.03 ms | 0.7% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±90% / ±0.03 ms | 89.7% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.01 | 0.02 | +0.00 | ±118% / ±0.02 ms | 117.6% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | +0.00 | ±73% / ±0.02 ms | 72.7% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.19 | 0.21 | +0.02 | ±18% / ±0.04 ms | 13.6% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.15 | 0.17 | +0.02 | ±18% / ±0.03 ms | 12.4% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04 | -0.00 | ±21% / ±0.02 ms | 21.4% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.76 | 1.82 | +0.07 | ±10% / ±0.18 ms | 4.8% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.45 | 1.50 | +0.05 | ±10% / ±0.15 ms | 4.3% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.37 | 0.33 | -0.04 | ±10% / ±0.04 ms | 1.8% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 21.89 | 20.69 | -1.20 | ±17% / ±3.72 ms | 17.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 15.07 | 14.87 | -0.20 | ±10% / ±1.51 ms | 1.6% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.88 | 3.52 | -0.36 | ±10% / ±0.39 ms | 3.6% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±100% / ±0.02 ms | 100.0% | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.02 | +0.01 | ±406% / ±0.07 ms | 405.6% | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±1050% / ±0.02 ms | 1050.0% | noisy | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.05 | +0.00 | ±39% / ±0.02 ms | 39.1% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | -0.00 | ±25% / ±0.02 ms | 25.0% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.38 | 0.38 | +0.00 | ±13% / ±0.05 ms | 12.7% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.09 | -0.00 | ±14% / ±0.02 ms | 14.1% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 4.68 | 4.50 | -0.18 | ±10% / ±0.47 ms | 1.8% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.88 | 0.85 | -0.03 | ±20% / ±0.18 ms | 20.3% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.20 | 0.23 | +0.03 | ±105% / ±0.24 ms | 104.7% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.20 | 0.23 | +0.03 | ±105% / ±0.24 ms | 104.7% | stable | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.53 | 0.52 | -0.01 | ±10% / ±0.05 ms | 3.1% | stable | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.53 | 0.52 | -0.01 | ±10% / ±0.05 ms | 3.1% | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | +0.00 | ±125% / ±0.04 ms | 125.0% | moderate | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03 | +0.00 | ±125% / ±0.04 ms | 125.0% | moderate | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.05 | +0.01 | ±40% / ±0.02 ms | 40.0% | noisy | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.05 | +0.01 | ±40% / ±0.02 ms | 40.0% | noisy | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.33 | 3.44 | +0.12 | ±10% / ±0.34 ms | 5.7% | stable | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.33 | 3.44 | +0.12 | ±10% / ±0.34 ms | 5.7% | stable | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.50 | 1.35 | -0.15 | ±101% / ±1.51 ms | 100.5% | moderate | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.50 | 1.35 | -0.15 | ±101% / ±1.51 ms | 100.5% | moderate | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.08 | 5.88 | -0.21 | ±10% / ±0.61 ms | 7.3% | stable | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.08 | 5.88 | -0.21 | ±10% / ±0.61 ms | 7.3% | stable | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.19 | 0.28 | +0.09 | ±112% / ±0.31 ms | 111.7% | noisy | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.19 | 0.28 | +0.09 | ±112% / ±0.31 ms | 111.7% | noisy | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 3.5% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 3.5% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.46 | 0.43 | -0.02 | ±10% / ±0.05 ms | 0.9% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.46 | 0.43 | -0.02 | ±10% / ±0.05 ms | 0.9% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.67 | 4.47 | -0.20 | ±10% / ±0.47 ms | 7.9% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.67 | 4.47 | -0.20 | ±10% / ±0.47 ms | 7.9% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.61 | 0.57 | -0.04 | ±10% / ±0.06 ms | 6.1% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.61 | 0.57 | -0.04 | ±10% / ±0.06 ms | 6.1% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.07 | +0.00 | ±10% / ±0.02 ms | 7.0% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.07 | +0.00 | ±10% / ±0.02 ms | 7.0% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 5.30 | 5.55 | +0.25 | ±10% / ±0.56 ms | 7.2% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 5.30 | 5.55 | +0.25 | ±10% / ±0.56 ms | 7.2% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.43 | 0.44 | +0.01 | ±10% / ±0.04 ms | 2.3% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.43 | 0.44 | +0.01 | ±10% / ±0.04 ms | 2.3% | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.09 | 0.05 | -0.04 | ±76% / ±0.06 ms | 75.5% | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.09 | 0.05 | -0.04 | ±76% / ±0.06 ms | 75.5% | stable | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.84 | 1.68 | -0.16 | ±10% / ±0.18 ms | 4.7% | stable | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.84 | 1.68 | -0.16 | ±10% / ±0.18 ms | 4.7% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.19 | +0.01 | ±10% / ±0.02 ms | 5.8% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.19 | +0.01 | ±10% / ±0.02 ms | 5.8% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.11 | +0.01 | ±10% / ±0.02 ms | 4.7% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.11 | +0.01 | ±10% / ±0.02 ms | 4.7% | stable | ⚪ Within noise |

**Summary:** 2 wins, 3 regressions, 148 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.02 | 0.00 | -0.02 MB | ±1.25 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.83 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 2.97 | 8.11 | +5.14 MB | ±6.78 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 3.69 | 0.00 | -3.69 MB | ±11.42 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 0.00 | +0.00 MB | ±4.00 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 0.03 | 1.64 | +1.61 MB | ±4.84 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±7.30 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 14.34 | 5.84 | -8.50 MB | ±5.26 MB | 🟢 Win (-8.50 MB) |
| Memory / Select 10k rows → Maps / resqlite select() | 4.52 | 1.39 | -3.13 MB | ±3.56 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite3 select() | 3.39 | 5.19 | +1.80 MB | ±4.07 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 1.00 | 1.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.06 | 0.05 | -0.01 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 1 wins, 0 regressions, 14 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 3877 | 3756 | -121 | ±100 | 🟢 Fewer re-emits (-121) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 20 | 10 | -10 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 3992 | 3714 | -278 | ±100 | 🔴 Invalidation elided (-278) — writes not firing |

**Granularity summary:** 1 fewer-re-emit, 1 more-re-emit, 4 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


