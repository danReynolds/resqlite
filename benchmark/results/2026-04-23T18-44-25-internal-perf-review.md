# resqlite Benchmark Results

Generated: 2026-04-23T18:44:24.800724

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `internal-perf-review`
- Repeats: `5`
- Runtime: `dart-vm / Dart 3.11.0`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `codex/benchmark-contract-goldens @ 02da8b80915d`
- Comparison baseline: `2026-04-23T11-08-40-MacBook Pro 14in.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.012 | 0.014 | 0.001 | 0.001 |
| sqlite3 select() | 0.015 | 0.015 | 0.015 | 0.015 |
| sqlite_async select() | 0.029 | 0.030 | 0.001 | 0.001 |
| drift select() | 0.038 | 0.039 | 0.001 | 0.001 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.044 | 0.048 | 0.008 | 0.009 |
| sqlite3 select() | 0.113 | 0.115 | 0.113 | 0.115 |
| sqlite_async select() | 0.118 | 0.122 | 0.010 | 0.010 |
| drift select() | 0.181 | 0.187 | 0.010 | 0.010 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.367 | 0.373 | 0.085 | 0.086 |
| sqlite3 select() | 1.075 | 1.085 | 1.075 | 1.085 |
| sqlite_async select() | 0.980 | 1.003 | 0.090 | 0.092 |
| drift select() | 1.544 | 1.848 | 0.090 | 0.093 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.427 | 10.449 | 0.859 | 2.692 |
| sqlite3 select() | 14.254 | 17.502 | 14.254 | 17.502 |
| sqlite_async select() | 11.739 | 14.256 | 0.916 | 1.418 |
| drift select() | 23.158 | 35.497 | 1.058 | 3.474 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.028 | 0.030 | 0.016 | 0.017 |
| sqlite3 + jsonEncode | 0.032 | 0.052 | 0.032 | 0.052 |
| sqlite_async + jsonEncode | 0.048 | 0.051 | 0.016 | 0.018 |
| drift + jsonEncode | 0.063 | 0.106 | 0.017 | 0.022 |
| resqlite selectBytes() | 0.010 | 0.011 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.193 | 0.197 | 0.152 | 0.155 |
| sqlite3 + jsonEncode | 0.260 | 0.284 | 0.260 | 0.284 |
| sqlite_async + jsonEncode | 0.323 | 0.511 | 0.167 | 0.307 |
| drift + jsonEncode | 0.345 | 0.700 | 0.160 | 0.182 |
| resqlite selectBytes() | 0.047 | 0.076 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.799 | 3.502 | 1.494 | 2.159 |
| sqlite3 + jsonEncode | 2.516 | 3.019 | 2.516 | 3.019 |
| sqlite_async + jsonEncode | 2.371 | 3.721 | 1.464 | 2.124 |
| drift + jsonEncode | 2.936 | 3.640 | 1.461 | 2.191 |
| resqlite selectBytes() | 0.366 | 0.383 | 0.000 | 0.001 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.818 | 23.681 | 15.011 | 16.653 |
| sqlite3 + jsonEncode | 29.246 | 40.601 | 29.246 | 40.601 |
| sqlite_async + jsonEncode | 29.599 | 33.149 | 15.488 | 16.441 |
| drift + jsonEncode | 38.028 | 49.808 | 15.638 | 20.040 |
| resqlite selectBytes() | 3.770 | 5.954 | 0.002 | 0.006 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.100 | 0.102 | 0.035 | 0.036 |
| sqlite3 | 0.324 | 0.335 | 0.324 | 0.335 |
| sqlite_async | 0.361 | 0.372 | 0.042 | 0.045 |
| drift | 0.576 | 0.610 | 0.041 | 0.042 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.894 | 0.951 | 0.269 | 0.275 |
| sqlite3 | 3.169 | 3.730 | 3.169 | 3.730 |
| sqlite_async | 2.793 | 3.208 | 0.318 | 0.328 |
| drift | 4.636 | 5.903 | 0.319 | 0.333 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.519 | 0.963 | 0.100 | 0.107 |
| sqlite3 | 1.424 | 1.469 | 1.424 | 1.469 |
| sqlite_async | 1.324 | 1.413 | 0.114 | 0.119 |
| drift | 1.978 | 2.254 | 0.115 | 0.125 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.296 | 0.313 | 0.098 | 0.104 |
| sqlite3 | 1.030 | 1.069 | 1.030 | 1.069 |
| sqlite_async | 0.966 | 1.129 | 0.122 | 0.139 |
| drift | 1.586 | 1.679 | 0.120 | 0.125 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.308 | 0.331 | 0.101 | 0.103 |
| sqlite3 | 0.966 | 1.003 | 0.966 | 1.003 |
| sqlite_async | 0.984 | 2.110 | 0.124 | 0.295 |
| drift | 1.571 | 1.755 | 0.121 | 0.127 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.010 | 0.010 | 0.001 | 0.001 |
| sqlite3 | 0.017 | 0.017 | 0.017 | 0.017 |
| sqlite_async | 0.030 | 0.036 | 0.001 | 0.001 |
| drift | 0.043 | 0.185 | 0.001 | 0.005 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.030 | 0.060 | 0.004 | 0.005 |
| sqlite3 | 0.064 | 0.066 | 0.064 | 0.066 |
| sqlite_async | 0.077 | 0.182 | 0.005 | 0.007 |
| drift | 0.105 | 0.158 | 0.005 | 0.006 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.047 | 0.107 | 0.009 | 0.016 |
| sqlite3 | 0.119 | 0.120 | 0.119 | 0.120 |
| sqlite_async | 0.122 | 0.129 | 0.010 | 0.011 |
| drift | 0.187 | 0.233 | 0.010 | 0.013 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.186 | 0.211 | 0.042 | 0.047 |
| sqlite3 | 0.544 | 0.569 | 0.544 | 0.569 |
| sqlite_async | 0.500 | 0.517 | 0.045 | 0.046 |
| drift | 0.783 | 0.804 | 0.045 | 0.047 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.371 | 0.381 | 0.085 | 0.087 |
| sqlite3 | 1.084 | 1.153 | 1.084 | 1.153 |
| sqlite_async | 0.982 | 0.995 | 0.091 | 0.092 |
| drift | 1.553 | 1.864 | 0.089 | 0.095 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.755 | 0.782 | 0.171 | 0.177 |
| sqlite3 | 2.150 | 2.966 | 2.150 | 2.966 |
| sqlite_async | 1.961 | 2.300 | 0.180 | 0.183 |
| drift | 3.096 | 3.522 | 0.179 | 0.555 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.256 | 7.198 | 0.445 | 2.183 |
| sqlite3 | 5.702 | 7.620 | 5.702 | 7.620 |
| sqlite_async | 5.022 | 5.653 | 0.454 | 0.478 |
| drift | 8.378 | 8.497 | 0.450 | 0.459 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.307 | 9.518 | 0.849 | 1.244 |
| sqlite3 | 15.046 | 18.426 | 15.046 | 18.426 |
| sqlite_async | 10.730 | 11.688 | 0.909 | 0.931 |
| drift | 18.540 | 25.338 | 0.945 | 2.205 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 10.434 | 18.626 | 1.707 | 1.795 |
| sqlite3 | 31.915 | 35.615 | 31.915 | 35.615 |
| sqlite_async | 33.154 | 52.960 | 1.843 | 7.509 |
| drift | 49.309 | 58.902 | 1.845 | 1.992 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.028 | 0.030 | 0.028 | 0.030 |
| sqlite3 + jsonEncode | 0.030 | 0.031 | 0.030 | 0.031 |
| sqlite_async + jsonEncode | 0.046 | 0.048 | 0.046 | 0.048 |
| drift + jsonEncode | 0.054 | 0.117 | 0.054 | 0.117 |
| resqlite selectBytes() | 0.011 | 0.014 | 0.011 | 0.014 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.104 | 0.107 | 0.104 | 0.107 |
| sqlite3 + jsonEncode | 0.134 | 0.144 | 0.134 | 0.144 |
| sqlite_async + jsonEncode | 0.140 | 0.172 | 0.140 | 0.172 |
| drift + jsonEncode | 0.170 | 0.174 | 0.170 | 0.174 |
| resqlite selectBytes() | 0.024 | 0.026 | 0.024 | 0.026 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.191 | 0.197 | 0.191 | 0.197 |
| sqlite3 + jsonEncode | 0.255 | 0.265 | 0.255 | 0.265 |
| sqlite_async + jsonEncode | 0.260 | 0.264 | 0.260 | 0.264 |
| drift + jsonEncode | 0.315 | 0.320 | 0.315 | 0.320 |
| resqlite selectBytes() | 0.042 | 0.045 | 0.042 | 0.045 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.885 | 0.912 | 0.885 | 0.912 |
| sqlite3 + jsonEncode | 1.243 | 1.258 | 1.243 | 1.258 |
| sqlite_async + jsonEncode | 1.220 | 1.397 | 1.220 | 1.397 |
| drift + jsonEncode | 1.623 | 3.761 | 1.623 | 3.761 |
| resqlite selectBytes() | 0.192 | 0.500 | 0.192 | 0.500 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.875 | 1.966 | 1.875 | 1.966 |
| sqlite3 + jsonEncode | 2.635 | 2.740 | 2.635 | 2.740 |
| sqlite_async + jsonEncode | 2.552 | 2.996 | 2.552 | 2.996 |
| drift + jsonEncode | 2.973 | 3.489 | 2.973 | 3.489 |
| resqlite selectBytes() | 0.353 | 0.365 | 0.353 | 0.365 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.845 | 6.846 | 3.845 | 6.846 |
| sqlite3 + jsonEncode | 5.304 | 8.294 | 5.304 | 8.294 |
| sqlite_async + jsonEncode | 5.309 | 9.344 | 5.309 | 9.344 |
| drift + jsonEncode | 6.380 | 10.009 | 6.380 | 10.009 |
| resqlite selectBytes() | 0.745 | 1.318 | 0.745 | 1.318 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 9.770 | 12.853 | 9.770 | 12.853 |
| sqlite3 + jsonEncode | 14.903 | 21.902 | 14.903 | 21.902 |
| sqlite_async + jsonEncode | 13.456 | 18.850 | 13.456 | 18.850 |
| drift + jsonEncode | 16.669 | 22.715 | 16.669 | 22.715 |
| resqlite selectBytes() | 1.826 | 3.128 | 1.826 | 3.128 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.735 | 28.995 | 20.735 | 28.995 |
| sqlite3 + jsonEncode | 28.464 | 36.886 | 28.464 | 36.886 |
| sqlite_async + jsonEncode | 31.229 | 37.792 | 31.229 | 37.792 |
| drift + jsonEncode | 36.023 | 37.774 | 36.023 | 37.774 |
| resqlite selectBytes() | 3.585 | 3.622 | 3.585 | 3.622 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 43.462 | 55.945 | 43.462 | 55.945 |
| sqlite3 + jsonEncode | 62.611 | 71.006 | 62.611 | 71.006 |
| sqlite_async + jsonEncode | 63.094 | 77.745 | 63.094 | 77.745 |
| drift + jsonEncode | 87.427 | 117.138 | 87.427 | 117.138 |
| resqlite selectBytes() | 8.341 | 9.548 | 8.341 | 9.548 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.32 | 0.30 |
| sqlite_async | 0.91 | 0.98 | 0.91 |
| drift | 1.46 | 1.52 | 1.46 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.30 | 0.15 |
| sqlite_async | 1.28 | 1.56 | 0.64 |
| drift | 2.68 | 3.22 | 1.34 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.36 | 0.73 | 0.09 |
| sqlite_async | 2.08 | 2.69 | 0.52 |
| drift | 5.22 | 5.58 | 1.30 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.66 | 1.05 | 0.08 |
| sqlite_async | 4.51 | 5.03 | 0.56 |
| drift | 10.74 | 11.53 | 1.34 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 143726 |
| resqlite per query | 0.007 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 143726 | 126095..145005 | 6.6 | 6.2 |
| sqlite3 | 194780 | 186941..198905 | 3.1 | 7.2 |
| sqlite_async | 52327 | 45275..55190 | 9.5 | 20.5 |
| drift | 45383 | 40748..47906 | 7.9 | 16.8 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.113 | 14.697 | 14.113 | 14.697 |
| sqlite_async | 34.784 | 37.386 | 34.784 | 37.386 |
| drift | 52.872 | 58.262 | 52.872 | 58.262 |
| sqlite3 (no cache) | 24.133 | 25.150 | 24.133 | 25.150 |
| sqlite3 (cached stmt) | 24.708 | 25.321 | 24.708 | 25.321 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.527 | 2.112 | 1.527 | 2.112 |
| sqlite3 execute() | 0.984 | 1.626 | 0.984 | 1.626 |
| sqlite_async execute() | 2.690 | 3.332 | 2.690 | 3.332 |
| drift execute() | 2.705 | 3.462 | 2.705 | 3.462 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.070 | 0.108 | 0.070 | 0.108 |
| sqlite3 executeBatch() | 0.055 | 0.079 | 0.055 | 0.079 |
| sqlite_async executeBatch() | 0.131 | 0.169 | 0.131 | 0.169 |
| drift executeBatch() | 0.122 | 0.164 | 0.122 | 0.164 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.470 | 0.579 | 0.470 | 0.579 |
| sqlite3 executeBatch() | 0.456 | 0.541 | 0.456 | 0.541 |
| sqlite_async executeBatch() | 0.559 | 0.687 | 0.559 | 0.687 |
| drift executeBatch() | 0.695 | 0.872 | 0.695 | 0.872 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.136 | 6.224 | 4.136 | 6.224 |
| sqlite3 executeBatch() | 4.065 | 4.254 | 4.065 | 4.254 |
| sqlite_async executeBatch() | 4.754 | 5.152 | 4.754 | 5.152 |
| drift executeBatch() | 5.926 | 6.760 | 5.926 | 6.760 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.048 | 0.055 | 0.048 | 0.055 |
| sqlite_async writeTransaction() | 0.071 | 0.075 | 0.071 | 0.075 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.072 | 0.078 | 0.072 | 0.078 |
| resqlite tx.execute() loop | 0.561 | 0.684 | 0.561 | 0.684 |
| sqlite_async tx.execute() loop | 1.086 | 1.185 | 1.086 | 1.185 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.432 | 0.444 | 0.432 | 0.444 |
| resqlite tx.execute() loop | 6.589 | 7.173 | 6.589 | 7.173 |
| sqlite_async tx.execute() loop | 11.721 | 14.285 | 11.721 | 14.285 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.102 | 0.105 | 0.102 | 0.105 |
| sqlite_async tx.getAll() | 0.195 | 0.211 | 0.195 | 0.211 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.189 | 0.205 | 0.189 | 0.205 |
| sqlite_async tx.getAll() | 0.347 | 0.387 | 0.347 | 0.387 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.033 | 0.045 | 0.033 | 0.045 |
| sqlite_async watch() | 0.101 | 0.112 | 0.101 | 0.112 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.045 | 0.066 | 0.045 | 0.066 |
| sqlite_async | 0.051 | 0.069 | 0.051 | 0.069 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.178 | 0.245 | 0.178 | 0.245 |
| sqlite_async | 0.740 | 2.923 | 0.740 | 2.923 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.245 | 0.471 | 0.245 | 0.471 |
| sqlite_async | 0.320 | 0.375 | 0.320 | 0.375 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.057 | 2.057 | 2.057 | 2.057 |
| sqlite_async | 8.385 | 8.385 | 8.385 | 8.385 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.360 | 3.970 | 3.360 | 3.970 |
| sqlite_async | 5.465 | 7.946 | 5.465 | 7.946 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.566 | 0.833 | 0.566 | 0.833 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 7.220 | 7.847 | 7.220 | 7.847 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. On resqlite's main branch this ratio is driven toward 0 by experiment 075 (C-side result-hash short-circuit), not by writer-side column-tracking (exp 052 is not implemented). The two mechanisms are indistinguishable on this read-side benchmark.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 69.4 | 0.000 |
| sqlite_async | 3969 | 955.3 | 1.023 |
| drift | 5000 | 1087.4 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 70.3 | 0.000 |
| sqlite_async | 3879 | 969.6 | 1.023 |
| drift | 5000 | 1124.1 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 220.53 | 222.52 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 442.02 | 445.19 | 0.00 | 0.00 | 1191 | 3 |
| drift stream() | 552.10 | 591.01 | 0.01 | 0.01 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.030 | 0.069 | 0.000 | 0.000 |
| sqlite3 | 0.018 | 0.023 | 0.018 | 0.023 |
| sqlite_async | 0.036 | 0.049 | 0.000 | 0.000 |
| drift | 0.040 | 0.066 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.021 | 0.048 | 0.000 | 0.000 |
| sqlite3 | 0.011 | 0.014 | 0.011 | 0.014 |
| sqlite_async | 0.029 | 0.039 | 0.000 | 0.000 |
| drift | 0.032 | 0.052 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.029 | 0.048 | 0.000 | 0.000 |
| sqlite3 | 0.030 | 0.031 | 0.030 | 0.031 |
| sqlite_async | 0.053 | 0.062 | 0.000 | 0.000 |
| drift | 0.054 | 0.065 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.011 | 0.023 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.019 | 0.023 | 0.000 | 0.000 |
| drift | 0.021 | 0.031 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.040 | 0.043 | 0.001 | 0.001 |
| sqlite3 | 0.067 | 0.209 | 0.067 | 0.209 |
| sqlite_async | 0.079 | 0.082 | 0.001 | 0.001 |
| drift | 0.105 | 0.184 | 0.001 | 0.002 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 110.219 | 111.003 | 0.000 | 0.000 | 0 |
| sqlite_async | 214.914 | 215.519 | 0.000 | 0.000 | 39 |
| drift | 227.545 | 233.383 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 238.40 | 238.40 | 0.00 | 0.00 | 11.80 | 226.59 | 0 |
| sqlite_async | 495.69 | 495.69 | 0.01 | 0.01 | 23.82 | 471.87 | 1188 |
| drift | 1828.63 | 1828.63 | 1.70 | 1.70 | 12.97 | 1816.72 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 5.45 | 9.98 | 3.34..7.56 | ±2.11 |
| sqlite3 select() | 2.66 | 8.16 | 1.66..6.73 | ±2.54 |
| sqlite_async select() | 1.00 | 1.02 | 1.00..1.00 | ±0.00 |
| drift select() | 11.36 | 74.28 | 0.00..18.69 | ±9.34 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 10.00 | 0.00..8.02 | ±4.01 |
| resqlite + jsonEncode | 2.00 | 49.42 | 0.00..5.31 | ±2.66 |
| sqlite3 + jsonEncode | 1.34 | 49.64 | 0.00..18.08 | ±9.04 |
| sqlite_async + jsonEncode | 0.00 | 35.28 | 0.00..0.00 | ±0.00 |
| drift + jsonEncode | 0.00 | 86.91 | 0.00..9.84 | ±4.92 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.00 | 2.80 | 0.00..0.41 | ±0.20 |
| sqlite3 executeBatch() | 0.00 | 0.03 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| drift batch() | 0.02 | 4.55 | 0.00..2.52 | ±1.26 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.08 | 0.00..0.06 | ±0.03 |
| sqlite_async watch() | 0.00 | 0.52 | 0.00..0.50 | ±0.25 |

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
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.03 | 0.03..0.03 | 3.4% | 6.9% | 3.4% | moderate |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 10.0% | 20.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.03 | 0.03..0.03 | 8.9% | 17.9% | 3.6% | moderate |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02..0.02 | 7.5% | 15.0% | 5.0% | moderate |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.30 | 0.30..0.34 | 6.7% | 13.3% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.30 | 0.30..0.34 | 6.7% | 13.3% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.33 | 0.30..0.45 | 22.7% | 45.5% | 9.1% | noisy |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.17 | 0.15..0.23 | 23.5% | 47.1% | 11.8% | noisy |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.44 | 0.36..0.59 | 26.1% | 52.3% | 2.3% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.11 | 0.09..0.15 | 27.3% | 54.5% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.82 | 0.66..1.01 | 21.3% | 42.7% | 17.1% | noisy |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.10 | 0.08..0.13 | 25.0% | 50.0% | 20.0% | noisy |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.04 | 4.9% | 9.8% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 150.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 105.32 | 104.86..110.22 | 2.5% | 5.1% | 0.4% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 232.31 | 230.11..238.40 | 1.8% | 3.6% | 0.9% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 220.78 | 216.07..221.25 | 1.2% | 2.3% | 0.2% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 14.88 | 14.11..18.49 | 14.7% | 29.4% | 1.6% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 14.88 | 14.11..18.49 | 14.7% | 29.4% | 1.6% | stable |
| Point Query Throughput / resqlite qps | 106670.00 | 99883.00..143726.00 | 20.6% | 41.1% | 6.4% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.02 | 29.2% | 58.3% | 16.7% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.04 | 25.9% | 51.7% | 3.4% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.04 | 25.9% | 51.7% | 3.4% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 50.0% | 100.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.01 | 22.7% | 45.5% | 9.1% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.01 | 22.7% | 45.5% | 9.1% | noisy |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05..0.06 | 7.7% | 15.4% | 3.8% | moderate |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.20 | 0.19..0.30 | 28.4% | 56.7% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.20 | 0.19..0.30 | 28.4% | 56.7% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.05 | 9.1% | 18.2% | 4.5% | moderate |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.04 | 0.04..0.05 | 9.1% | 18.2% | 4.5% | moderate |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.39 | 0.36..0.45 | 10.6% | 21.2% | 5.4% | moderate |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.94 | 1.88..2.04 | 4.3% | 8.5% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.94 | 1.88..2.04 | 4.3% | 8.5% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09..0.09 | 4.5% | 9.0% | 4.5% | moderate |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.37 | 0.35..0.38 | 4.1% | 8.1% | 3.8% | moderate |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.37 | 0.35..0.38 | 4.1% | 8.1% | 3.8% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.85 | 4.31..5.48 | 12.1% | 24.1% | 11.3% | noisy |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 22.44 | 20.58..24.07 | 7.8% | 15.5% | 7.3% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 22.44 | 20.58..24.07 | 7.8% | 15.5% | 7.3% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.89 | 0.85..0.92 | 3.8% | 7.7% | 3.5% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 3.94 | 3.58..4.13 | 6.9% | 13.7% | 4.6% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 3.94 | 3.58..4.13 | 6.9% | 13.7% | 4.6% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.81 | 0.76..1.28 | 32.3% | 64.6% | 6.3% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.99 | 3.85..4.15 | 3.8% | 7.7% | 1.3% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.99 | 3.85..4.15 | 3.8% | 7.7% | 1.3% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.17 | 0.17..0.19 | 5.4% | 10.9% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.78 | 0.74..0.86 | 7.5% | 14.9% | 4.9% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.78 | 0.74..0.86 | 7.5% | 14.9% | 4.9% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 11.74 | 10.43..22.36 | 50.8% | 101.6% | 11.1% | noisy |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 46.33 | 43.46..50.70 | 7.8% | 15.6% | 6.0% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 46.33 | 43.46..50.70 | 7.8% | 15.6% | 6.0% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.77 | 1.71..1.95 | 6.8% | 13.6% | 3.4% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 8.58 | 7.96..8.71 | 4.4% | 8.8% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 8.58 | 7.96..8.71 | 4.4% | 8.8% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03..0.04 | 13.3% | 26.7% | 10.0% | noisy |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.10..0.16 | 25.5% | 50.9% | 3.7% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.11 | 0.10..0.16 | 25.5% | 50.9% | 3.7% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.01 | 12.5% | 25.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.02..0.03 | 11.1% | 22.2% | 7.4% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.02..0.03 | 11.1% | 22.2% | 7.4% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.20 | 0.19..0.21 | 5.0% | 10.0% | 2.5% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.92 | 0.89..1.09 | 11.0% | 22.1% | 4.2% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.92 | 0.89..1.09 | 11.0% | 22.1% | 4.2% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04..0.04 | 2.3% | 4.5% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.19 | 0.18..0.20 | 3.2% | 6.3% | 2.6% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.19 | 0.18..0.20 | 3.2% | 6.3% | 2.6% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.27 | 2.22..3.68 | 32.1% | 64.1% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 10.45 | 9.77..10.98 | 5.8% | 11.6% | 5.1% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 10.45 | 9.77..10.98 | 5.8% | 11.6% | 5.1% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.44 | 0.44..0.51 | 7.8% | 15.6% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 2.05 | 1.83..2.14 | 7.7% | 15.4% | 3.8% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 2.05 | 1.83..2.14 | 7.7% | 15.4% | 3.8% | moderate |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.10 | 0.10..0.17 | 35.3% | 70.6% | 2.0% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.04 | 0.04..0.09 | 81.9% | 163.9% | 2.8% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.31 | 0.30..0.32 | 2.8% | 5.5% | 1.6% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.10 | 0.10..0.10 | 1.5% | 3.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.30 | 0.29..0.30 | 2.2% | 4.4% | 1.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.10 | 0.10..0.10 | 2.0% | 4.1% | 2.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.55 | 0.52..0.60 | 7.7% | 15.4% | 5.1% | moderate |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.10 | 0.10..0.11 | 3.4% | 6.9% | 1.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.91 | 0.89..0.93 | 1.8% | 3.6% | 1.5% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.27 | 0.27..0.28 | 2.2% | 4.4% | 1.5% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.13 | 178.6% | 357.1% | 7.1% | moderate |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02..0.10 | 268.7% | 537.5% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 58.3% | 116.7% | 8.3% | noisy |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.19..0.26 | 16.3% | 32.5% | 3.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.16 | 0.15..0.19 | 13.0% | 25.9% | 2.5% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.04..0.05 | 8.5% | 17.0% | 4.3% | moderate |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.91 | 1.75..2.15 | 10.4% | 20.9% | 6.6% | moderate |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.56 | 1.47..1.68 | 6.7% | 13.5% | 4.1% | moderate |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.37 | 0.36..0.45 | 11.8% | 23.6% | 3.2% | moderate |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.90 | 20.31..28.40 | 19.4% | 38.7% | 2.9% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 15.15 | 14.84..19.10 | 14.1% | 28.1% | 2.1% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.83 | 3.77..4.11 | 4.5% | 9.0% | 1.5% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.01 | 83.3% | 166.7% | 66.7% | noisy |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.08 | 308.3% | 616.7% | 16.7% | noisy |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 1050.0% | 2100.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.04..0.15 | 108.8% | 217.6% | 5.9% | moderate |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 11.1% | 22.2% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.39 | 0.37..0.42 | 7.1% | 14.2% | 1.3% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.08..0.09 | 7.4% | 14.8% | 1.1% | stable |
| Select → Maps / 10000 rows / resqlite select() | 5.06 | 4.43..7.25 | 27.9% | 55.8% | 10.0% | noisy |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.88 | 0.77..0.95 | 10.3% | 20.5% | 2.5% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.27 | 0.24..0.35 | 20.2% | 40.4% | 8.2% | noisy |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.27 | 0.24..0.35 | 20.2% | 40.4% | 8.2% | noisy |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.57 | 0.50..0.65 | 12.7% | 25.4% | 4.3% | moderate |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.57 | 0.50..0.65 | 12.7% | 25.4% | 4.3% | moderate |
| Streaming / Initial Emission / resqlite stream() | 0.04 | 0.03..0.04 | 11.1% | 22.2% | 8.3% | noisy |
| Streaming / Initial Emission / resqlite stream() [main] | 0.04 | 0.03..0.04 | 11.1% | 22.2% | 8.3% | noisy |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.04..0.06 | 16.7% | 33.3% | 11.8% | noisy |
| Streaming / Invalidation Latency / resqlite [main] | 0.05 | 0.04..0.06 | 16.7% | 33.3% | 11.8% | noisy |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 4.12 | 3.36..4.90 | 18.7% | 37.4% | 9.4% | noisy |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 4.12 | 3.36..4.90 | 18.7% | 37.4% | 9.4% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.90 | 1.67..2.65 | 25.8% | 51.6% | 10.3% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.90 | 1.67..2.65 | 25.8% | 51.6% | 10.3% | noisy |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 7.65 | 7.04..8.63 | 10.4% | 20.7% | 7.9% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 7.65 | 7.04..8.63 | 10.4% | 20.7% | 7.9% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.22 | 0.18..0.39 | 48.8% | 97.7% | 2.3% | stable |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.22 | 0.18..0.39 | 48.8% | 97.7% | 2.3% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.06..0.07 | 8.9% | 17.7% | 1.6% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.06 | 0.06..0.07 | 8.9% | 17.7% | 1.6% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.47 | 0.46..0.80 | 36.2% | 72.3% | 2.8% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.47 | 0.46..0.80 | 36.2% | 72.3% | 2.8% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.87 | 4.14..8.63 | 46.2% | 92.3% | 15.0% | noisy |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.87 | 4.14..8.63 | 46.2% | 92.3% | 15.0% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.57 | 0.56..0.88 | 28.0% | 56.0% | 3.1% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.57 | 0.56..0.88 | 28.0% | 56.0% | 3.1% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07..0.08 | 8.1% | 16.2% | 4.1% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07..0.08 | 8.1% | 16.2% | 4.1% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 6.70 | 6.20..8.77 | 19.2% | 38.4% | 1.7% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 6.70 | 6.20..8.77 | 19.2% | 38.4% | 1.7% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.52 | 0.43..0.62 | 18.3% | 36.6% | 8.1% | noisy |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.52 | 0.43..0.62 | 18.3% | 36.6% | 8.1% | noisy |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.06 | 0.05..0.08 | 31.6% | 63.2% | 15.8% | noisy |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.06 | 0.05..0.08 | 31.6% | 63.2% | 15.8% | noisy |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.99 | 1.53..4.41 | 72.5% | 144.9% | 15.1% | noisy |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.99 | 1.53..4.41 | 72.5% | 144.9% | 15.1% | noisy |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.20 | 0.19..0.21 | 5.1% | 10.2% | 4.1% | moderate |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.20 | 0.19..0.21 | 5.1% | 10.2% | 4.1% | moderate |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.11 | 0.10..0.11 | 4.1% | 8.3% | 1.8% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.11 | 0.10..0.11 | 4.1% | 8.3% | 1.8% | stable |


## Comparison vs Previous Run

Previous: `2026-04-23T11-08-40-MacBook Pro 14in.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.03 | 0.03 | -0.00 | ±10% / ±0.02 ms | 3.4% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | 10.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.03 | 0.03 | -0.01 | ±11% / ±0.02 ms | 8.9% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02 | -0.00 | ±15% / ±0.02 ms | 7.5% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.32 | 0.30 | -0.02 | ±10% / ±0.03 ms | 6.7% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.32 | 0.30 | -0.02 | ±10% / ±0.03 ms | 6.7% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.34 | 0.33 | -0.01 | ±27% / ±0.09 ms | 22.7% | noisy | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.17 | 0.17 | +0.00 | ±35% / ±0.06 ms | 23.5% | noisy | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.60 | 0.44 | -0.16 | ±26% / ±0.16 ms | 26.1% | stable | 🟢 Win (-27%) |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.15 | 0.11 | -0.04 | ±27% / ±0.04 ms | 27.3% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.87 | 0.82 | -0.05 | ±51% / ±0.45 ms | 21.3% | noisy | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.11 | 0.10 | -0.01 | ±60% / ±0.07 ms | 25.0% | noisy | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 4.9% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±150% / ±0.02 ms | 150.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 108.49 | 105.32 | -3.17 | ±10% / ±10.85 ms | 2.5% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 235.71 | 232.31 | -3.40 | ±10% / ±23.57 ms | 1.8% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 225.38 | 220.78 | -4.60 | ±10% / ±22.54 ms | 1.2% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 30.87 | 14.88 | -15.99 | ±15% / ±4.54 ms | 14.7% | stable | 🟢 Win (-52%) |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 30.87 | 14.88 | -15.99 | ±15% / ±4.54 ms | 14.7% | stable | 🟢 Win (-52%) |
| Point Query Throughput / resqlite qps | 83080.00 | 106670.00 | +23590.00 | ±21% / ±21921.50 ms | 20.6% | moderate | 🟢 Win (28%) |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01 | +0.00 | ±50% / ±0.02 ms | 29.2% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | -0.00 | ±26% / ±0.02 ms | 25.9% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.03 | -0.00 | ±26% / ±0.02 ms | 25.9% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±50% / ±0.02 ms | 50.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.02 | 0.01 | -0.01 | ±27% / ±0.02 ms | 22.7% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.02 | 0.01 | -0.01 | ±27% / ±0.02 ms | 22.7% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.06 | 0.05 | -0.00 | ±12% / ±0.02 ms | 7.7% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.20 | 0.20 | -0.00 | ±28% / ±0.06 ms | 28.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.20 | 0.20 | -0.00 | ±28% / ±0.06 ms | 28.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.05 | 0.04 | -0.01 | ±14% / ±0.02 ms | 9.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.05 | 0.04 | -0.01 | ±14% / ±0.02 ms | 9.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.54 | 0.39 | -0.15 | ±16% / ±0.09 ms | 10.6% | moderate | 🟢 Win (-27%) |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.93 | 1.94 | +0.00 | ±10% / ±0.19 ms | 4.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.93 | 1.94 | +0.00 | ±10% / ±0.19 ms | 4.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.11 | 0.09 | -0.02 | ±13% / ±0.02 ms | 4.5% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.37 | 0.37 | -0.00 | ±11% / ±0.04 ms | 4.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.37 | 0.37 | -0.00 | ±11% / ±0.04 ms | 4.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.95 | 4.85 | -0.10 | ±34% / ±1.67 ms | 12.1% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 28.18 | 22.44 | -5.75 | ±22% / ±6.14 ms | 7.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 28.18 | 22.44 | -5.75 | ±22% / ±6.14 ms | 7.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.91 | 0.89 | -0.02 | ±10% / ±0.10 ms | 3.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 4.54 | 3.94 | -0.60 | ±14% / ±0.63 ms | 6.9% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 4.54 | 3.94 | -0.60 | ±14% / ±0.63 ms | 6.9% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.95 | 0.81 | -0.15 | ±32% / ±0.31 ms | 32.3% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 4.12 | 3.99 | -0.12 | ±10% / ±0.41 ms | 3.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 4.12 | 3.99 | -0.12 | ±10% / ±0.41 ms | 3.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.18 | 0.17 | -0.01 | ±10% / ±0.02 ms | 5.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.96 | 0.78 | -0.18 | ±15% / ±0.14 ms | 7.5% | moderate | 🟢 Win (-19%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.96 | 0.78 | -0.18 | ±15% / ±0.14 ms | 7.5% | moderate | 🟢 Win (-19%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 16.34 | 11.74 | -4.60 | ±51% / ±8.30 ms | 50.8% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 57.66 | 46.33 | -11.33 | ±18% / ±10.41 ms | 7.8% | moderate | 🟢 Win (-20%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 57.66 | 46.33 | -11.33 | ±18% / ±10.41 ms | 7.8% | moderate | 🟢 Win (-20%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.81 | 1.77 | -0.04 | ±10% / ±0.19 ms | 6.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 7.98 | 8.58 | +0.60 | ±10% / ±0.86 ms | 4.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 7.98 | 8.58 | +0.60 | ±10% / ±0.86 ms | 4.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03 | -0.00 | ±30% / ±0.02 ms | 13.3% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.11 | -0.00 | ±25% / ±0.03 ms | 25.5% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.11 | 0.11 | -0.00 | ±25% / ±0.03 ms | 25.5% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.01 | 0.00 | -0.00 | ±13% / ±0.02 ms | 12.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | -0.00 | ±22% / ±0.02 ms | 11.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | -0.00 | ±22% / ±0.02 ms | 11.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.30 | 0.20 | -0.10 | ±10% / ±0.03 ms | 5.0% | stable | 🟢 Win (-33%) |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.98 | 0.92 | -0.06 | ±13% / ±0.12 ms | 11.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.98 | 0.92 | -0.06 | ±13% / ±0.12 ms | 11.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.05 | 0.04 | -0.00 | ±10% / ±0.02 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.20 | 0.19 | -0.01 | ±10% / ±0.02 ms | 3.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.20 | 0.19 | -0.01 | ±10% / ±0.02 ms | 3.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.41 | 2.27 | -0.14 | ±32% / ±0.77 ms | 32.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.78 | 10.45 | -0.33 | ±15% / ±1.65 ms | 5.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.78 | 10.45 | -0.33 | ±15% / ±1.65 ms | 5.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.45 | 0.44 | -0.00 | ±10% / ±0.04 ms | 7.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 2.78 | 2.05 | -0.73 | ±11% / ±0.32 ms | 7.7% | moderate | 🟢 Win (-26%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 2.78 | 2.05 | -0.73 | ±11% / ±0.32 ms | 7.7% | moderate | 🟢 Win (-26%) |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.11 | 0.10 | -0.00 | ±35% / ±0.04 ms | 35.3% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.04 | 0.04 | +0.00 | ±82% / ±0.03 ms | 81.9% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.32 | 0.31 | -0.01 | ±10% / ±0.03 ms | 2.8% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 1.5% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.30 | 0.30 | -0.01 | ±10% / ±0.03 ms | 2.2% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.58 | 0.55 | -0.03 | ±15% / ±0.09 ms | 7.7% | moderate | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 3.4% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.99 | 0.91 | -0.08 | ±10% / ±0.10 ms | 1.8% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.29 | 0.27 | -0.02 | ±10% / ±0.03 ms | 2.2% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | -0.01 | ±179% / ±0.06 ms | 178.6% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02 | -0.00 | ±269% / ±0.05 ms | 268.7% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | +0.00 | ±58% / ±0.02 ms | 58.3% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.20 | +0.00 | ±16% / ±0.03 ms | 16.3% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.16 | 0.16 | -0.00 | ±13% / ±0.02 ms | 13.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.05 | +0.00 | ±13% / ±0.02 ms | 8.5% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.96 | 1.91 | -0.05 | ±20% / ±0.39 ms | 10.4% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.63 | 1.56 | -0.07 | ±12% / ±0.20 ms | 6.7% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.38 | 0.37 | -0.01 | ±12% / ±0.05 ms | 11.8% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 36.18 | 20.90 | -15.28 | ±19% / ±7.01 ms | 19.4% | stable | 🟢 Win (-42%) |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 25.89 | 15.15 | -10.74 | ±14% / ±3.64 ms | 14.1% | stable | 🟢 Win (-41%) |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 4.25 | 3.83 | -0.42 | ±10% / ±0.42 ms | 4.5% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.01 | 0.00 | -0.00 | ±200% / ±0.02 ms | 83.3% | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | +0.00 | ±308% / ±0.04 ms | 308.3% | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±1050% / ±0.02 ms | 1050.0% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.05 | +0.00 | ±109% / ±0.06 ms | 108.8% | moderate | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±11% / ±0.02 ms | 11.1% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.37 | 0.39 | +0.02 | ±10% / ±0.04 ms | 7.1% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 7.4% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 4.78 | 5.06 | +0.28 | ±30% / ±1.52 ms | 27.9% | noisy | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.89 | 0.88 | -0.01 | ±10% / ±0.09 ms | 10.3% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.94 | 0.27 | -0.67 | ±25% / ±0.23 ms | 20.2% | noisy | 🟢 Win (-72%) |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.94 | 0.27 | -0.67 | ±25% / ±0.23 ms | 20.2% | noisy | 🟢 Win (-72%) |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.62 | 0.57 | -0.04 | ±13% / ±0.08 ms | 12.7% | moderate | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.62 | 0.57 | -0.04 | ±13% / ±0.08 ms | 12.7% | moderate | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.04 | +0.01 | ±25% / ±0.02 ms | 11.1% | noisy | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.04 | +0.01 | ±25% / ±0.02 ms | 11.1% | noisy | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.06 | 0.05 | -0.01 | ±35% / ±0.02 ms | 16.7% | noisy | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.06 | 0.05 | -0.01 | ±35% / ±0.02 ms | 16.7% | noisy | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 4.86 | 4.12 | -0.74 | ±28% / ±1.37 ms | 18.7% | noisy | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 4.86 | 4.12 | -0.74 | ±28% / ±1.37 ms | 18.7% | noisy | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 4.74 | 1.90 | -2.85 | ±31% / ±1.46 ms | 25.8% | noisy | 🟢 Win (-60%) |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 4.74 | 1.90 | -2.85 | ±31% / ±1.46 ms | 25.8% | noisy | 🟢 Win (-60%) |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 9.58 | 7.65 | -1.93 | ±24% / ±2.27 ms | 10.4% | moderate | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 9.58 | 7.65 | -1.93 | ±24% / ±2.27 ms | 10.4% | moderate | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.31 | 0.22 | -0.10 | ±49% / ±0.15 ms | 48.8% | stable | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.31 | 0.22 | -0.10 | ±49% / ±0.15 ms | 48.8% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 8.9% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 8.9% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.48 | 0.47 | -0.01 | ±36% / ±0.17 ms | 36.2% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.48 | 0.47 | -0.01 | ±36% / ±0.17 ms | 36.2% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 5.29 | 4.87 | -0.42 | ±46% / ±2.44 ms | 46.2% | noisy | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 5.29 | 4.87 | -0.42 | ±46% / ±2.44 ms | 46.2% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.87 | 0.57 | -0.30 | ±28% / ±0.24 ms | 28.0% | moderate | 🟢 Win (-34%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.87 | 0.57 | -0.30 | ±28% / ±0.24 ms | 28.0% | moderate | 🟢 Win (-34%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.10 | 0.07 | -0.02 | ±12% / ±0.02 ms | 8.1% | moderate | 🟢 Win (-24%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.10 | 0.07 | -0.02 | ±12% / ±0.02 ms | 8.1% | moderate | 🟢 Win (-24%) |
| Write Performance / Batched Write Inside Transaction (100... | 8.56 | 6.70 | -1.86 | ±19% / ±1.64 ms | 19.2% | stable | 🟢 Win (-22%) |
| Write Performance / Batched Write Inside Transaction (100... | 8.56 | 6.70 | -1.86 | ±19% / ±1.64 ms | 19.2% | stable | 🟢 Win (-22%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.56 | 0.52 | -0.04 | ±24% / ±0.14 ms | 18.3% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.56 | 0.52 | -0.04 | ±24% / ±0.14 ms | 18.3% | noisy | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.13 | 0.06 | -0.07 | ±47% / ±0.06 ms | 31.6% | noisy | 🟢 Win (-55%) |
| Write Performance / Interactive Transaction (insert + sel... | 0.13 | 0.06 | -0.07 | ±47% / ±0.06 ms | 31.6% | noisy | 🟢 Win (-55%) |
| Write Performance / Single Inserts (100 sequential) / res... | 2.49 | 1.99 | -0.50 | ±72% / ±1.80 ms | 72.5% | noisy | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 2.49 | 1.99 | -0.50 | ±72% / ±1.80 ms | 72.5% | noisy | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.21 | 0.20 | -0.01 | ±12% / ±0.03 ms | 5.1% | moderate | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.21 | 0.20 | -0.01 | ±12% / ±0.03 ms | 5.1% | moderate | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | 4.1% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | 4.1% | stable | ⚪ Within noise |

**Summary:** 26 wins, 0 regressions, 127 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

✅ **No regressions beyond noise.** 26 benchmarks improved.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.89 | 0.02 | -0.87 MB | ±1.26 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 0.00 | 0.00 | +0.00 MB | ±4.92 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 6.22 | 2.00 | -4.22 MB | ±2.66 MB | 🟢 Win (-4.22 MB) |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.03 | 0.00 | -0.03 MB | ±4.01 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 3.03 | 1.34 | -1.69 MB | ±9.04 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 1.27 | 11.36 | +10.09 MB | ±9.34 MB | 🔴 Regression (+10.09 MB) |
| Memory / Select 10k rows → Maps / resqlite select() | 0.42 | 5.45 | +5.03 MB | ±2.11 MB | 🔴 Regression (+5.03 MB) |
| Memory / Select 10k rows → Maps / sqlite3 select() | 2.41 | 2.66 | +0.25 MB | ±2.54 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 1.00 | 1.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.00 | 0.06 | +0.06 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 1 wins, 2 regressions, 12 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 2576 | 3969 | +1393 | ±100 | 🔴 More re-emits (+1393) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 450 | 10 | -440 | ±100 | 🔴 Invalidation elided (-440) — writes not firing |
| Streaming (Column Granularity) / Overlapping column write... | 3127 | 3879 | +752 | ±100 | 🔴 More re-emits (+752) |

**Granularity summary:** 0 fewer-re-emit, 3 more-re-emit, 3 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.
