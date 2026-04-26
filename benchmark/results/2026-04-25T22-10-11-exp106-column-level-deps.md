# resqlite Benchmark Results

Generated: 2026-04-25T22:10:11.587168

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp106-column-level-deps`
- Repeats: `5`
- Runtime: `dart-vm / Dart 3.11.0`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `exp-106-column-level-deps @ 6661015cb14e (dirty)`
- Comparison baseline: `2026-04-25T19-43-21-baseline-for-exp105.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.012 | 0.013 | 0.001 | 0.001 |
| sqlite3 select() | 0.016 | 0.017 | 0.016 | 0.017 |
| sqlite_async select() | 0.031 | 0.033 | 0.001 | 0.001 |
| drift select() | 0.037 | 0.039 | 0.001 | 0.001 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.045 | 0.047 | 0.008 | 0.009 |
| sqlite3 select() | 0.109 | 0.111 | 0.109 | 0.111 |
| sqlite_async select() | 0.119 | 0.121 | 0.010 | 0.010 |
| drift select() | 0.174 | 0.183 | 0.010 | 0.010 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.396 | 0.655 | 0.090 | 0.119 |
| sqlite3 select() | 1.013 | 1.033 | 1.013 | 1.033 |
| sqlite_async select() | 0.957 | 0.989 | 0.089 | 0.090 |
| drift select() | 1.493 | 1.864 | 0.089 | 0.094 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.253 | 11.505 | 0.834 | 0.875 |
| sqlite3 select() | 14.037 | 18.697 | 14.037 | 18.697 |
| sqlite_async select() | 11.660 | 16.481 | 0.919 | 2.520 |
| drift select() | 20.100 | 27.231 | 0.907 | 1.452 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.027 | 0.029 | 0.016 | 0.017 |
| sqlite3 + jsonEncode | 0.030 | 0.033 | 0.030 | 0.033 |
| sqlite_async + jsonEncode | 0.046 | 0.049 | 0.016 | 0.018 |
| drift + jsonEncode | 0.054 | 0.061 | 0.016 | 0.020 |
| resqlite selectBytes() | 0.011 | 0.012 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.205 | 0.288 | 0.160 | 0.193 |
| sqlite3 + jsonEncode | 0.249 | 0.509 | 0.249 | 0.509 |
| sqlite_async + jsonEncode | 0.259 | 0.262 | 0.149 | 0.151 |
| drift + jsonEncode | 0.322 | 0.328 | 0.154 | 0.158 |
| resqlite selectBytes() | 0.043 | 0.046 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.709 | 3.185 | 1.425 | 2.148 |
| sqlite3 + jsonEncode | 2.379 | 4.238 | 2.379 | 4.238 |
| sqlite_async + jsonEncode | 2.373 | 4.676 | 1.457 | 2.525 |
| drift + jsonEncode | 2.862 | 3.559 | 1.435 | 2.102 |
| resqlite selectBytes() | 0.350 | 0.363 | 0.000 | 0.000 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.973 | 27.397 | 15.607 | 19.583 |
| sqlite3 + jsonEncode | 27.749 | 34.534 | 27.749 | 34.534 |
| sqlite_async + jsonEncode | 26.775 | 49.927 | 14.968 | 18.258 |
| drift + jsonEncode | 37.550 | 40.622 | 14.886 | 20.069 |
| resqlite selectBytes() | 4.557 | 10.448 | 0.004 | 0.010 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.102 | 0.105 | 0.036 | 0.037 |
| sqlite3 | 0.329 | 0.335 | 0.329 | 0.335 |
| sqlite_async | 0.382 | 1.005 | 0.044 | 0.053 |
| drift | 0.628 | 1.703 | 0.045 | 0.056 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.970 | 1.042 | 0.281 | 0.288 |
| sqlite3 | 3.091 | 3.658 | 3.091 | 3.658 |
| sqlite_async | 2.778 | 3.246 | 0.317 | 0.334 |
| drift | 4.472 | 9.357 | 0.315 | 0.413 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.526 | 0.537 | 0.101 | 0.105 |
| sqlite3 | 1.424 | 2.718 | 1.424 | 2.718 |
| sqlite_async | 1.317 | 1.371 | 0.115 | 0.117 |
| drift | 1.853 | 2.195 | 0.112 | 0.117 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.290 | 0.294 | 0.096 | 0.100 |
| sqlite3 | 0.935 | 0.975 | 0.935 | 0.975 |
| sqlite_async | 0.885 | 0.896 | 0.113 | 0.115 |
| drift | 1.397 | 1.447 | 0.110 | 0.114 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.295 | 0.302 | 0.098 | 0.102 |
| sqlite3 | 0.899 | 0.906 | 0.899 | 0.906 |
| sqlite_async | 0.867 | 0.880 | 0.111 | 0.112 |
| drift | 1.371 | 1.400 | 0.109 | 0.112 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.011 | 0.012 | 0.001 | 0.001 |
| sqlite3 | 0.015 | 0.015 | 0.015 | 0.015 |
| sqlite_async | 0.030 | 0.032 | 0.001 | 0.001 |
| drift | 0.036 | 0.038 | 0.001 | 0.001 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.027 | 0.030 | 0.004 | 0.005 |
| sqlite3 | 0.055 | 0.057 | 0.055 | 0.057 |
| sqlite_async | 0.069 | 0.072 | 0.005 | 0.005 |
| drift | 0.098 | 0.101 | 0.005 | 0.005 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.046 | 0.049 | 0.008 | 0.009 |
| sqlite3 | 0.106 | 0.111 | 0.106 | 0.111 |
| sqlite_async | 0.118 | 0.120 | 0.009 | 0.010 |
| drift | 0.175 | 0.181 | 0.009 | 0.010 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.189 | 0.196 | 0.042 | 0.044 |
| sqlite3 | 0.523 | 0.562 | 0.523 | 0.562 |
| sqlite_async | 0.498 | 0.518 | 0.045 | 0.047 |
| drift | 0.757 | 0.822 | 0.045 | 0.047 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.376 | 0.389 | 0.085 | 0.089 |
| sqlite3 | 1.014 | 1.067 | 1.014 | 1.067 |
| sqlite_async | 0.979 | 1.069 | 0.090 | 0.098 |
| drift | 1.476 | 1.779 | 0.088 | 0.091 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.764 | 0.788 | 0.170 | 0.176 |
| sqlite3 | 2.031 | 2.933 | 2.031 | 2.933 |
| sqlite_async | 1.929 | 2.288 | 0.178 | 0.189 |
| drift | 2.962 | 3.412 | 0.178 | 0.589 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.285 | 4.765 | 0.449 | 3.001 |
| sqlite3 | 5.528 | 7.297 | 5.528 | 7.297 |
| sqlite_async | 5.739 | 8.223 | 0.492 | 0.507 |
| drift | 8.190 | 8.535 | 0.450 | 0.486 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.444 | 10.590 | 0.854 | 0.915 |
| sqlite3 | 13.098 | 15.888 | 13.098 | 15.888 |
| sqlite_async | 10.555 | 11.373 | 0.894 | 0.913 |
| drift | 20.327 | 31.406 | 0.959 | 2.407 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 11.940 | 18.471 | 1.740 | 2.454 |
| sqlite3 | 30.872 | 34.968 | 30.872 | 34.968 |
| sqlite_async | 33.353 | 57.094 | 1.851 | 2.160 |
| drift | 48.956 | 60.530 | 1.892 | 7.840 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.027 | 0.028 | 0.027 | 0.028 |
| sqlite3 + jsonEncode | 0.029 | 0.030 | 0.029 | 0.030 |
| sqlite_async + jsonEncode | 0.046 | 0.049 | 0.046 | 0.049 |
| drift + jsonEncode | 0.052 | 0.055 | 0.052 | 0.055 |
| resqlite selectBytes() | 0.011 | 0.012 | 0.011 | 0.012 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.105 | 0.149 | 0.105 | 0.149 |
| sqlite3 + jsonEncode | 0.137 | 0.149 | 0.137 | 0.149 |
| sqlite_async + jsonEncode | 0.148 | 0.163 | 0.148 | 0.163 |
| drift + jsonEncode | 0.177 | 0.193 | 0.177 | 0.193 |
| resqlite selectBytes() | 0.025 | 0.027 | 0.025 | 0.027 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.191 | 0.222 | 0.191 | 0.222 |
| sqlite3 + jsonEncode | 0.251 | 0.271 | 0.251 | 0.271 |
| sqlite_async + jsonEncode | 0.259 | 0.282 | 0.259 | 0.282 |
| drift + jsonEncode | 0.309 | 0.318 | 0.309 | 0.318 |
| resqlite selectBytes() | 0.043 | 0.048 | 0.043 | 0.048 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.880 | 0.907 | 0.880 | 0.907 |
| sqlite3 + jsonEncode | 1.205 | 2.572 | 1.205 | 2.572 |
| sqlite_async + jsonEncode | 1.190 | 1.787 | 1.190 | 1.787 |
| drift + jsonEncode | 1.432 | 1.764 | 1.432 | 1.764 |
| resqlite selectBytes() | 0.186 | 0.194 | 0.186 | 0.194 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.731 | 3.539 | 1.731 | 3.539 |
| sqlite3 + jsonEncode | 2.393 | 3.149 | 2.393 | 3.149 |
| sqlite_async + jsonEncode | 2.343 | 3.576 | 2.343 | 3.576 |
| drift + jsonEncode | 2.831 | 3.275 | 2.831 | 3.275 |
| resqlite selectBytes() | 0.347 | 0.355 | 0.347 | 0.355 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.803 | 8.848 | 3.803 | 8.848 |
| sqlite3 + jsonEncode | 5.150 | 7.818 | 5.150 | 7.818 |
| sqlite_async + jsonEncode | 5.032 | 7.755 | 5.032 | 7.755 |
| drift + jsonEncode | 6.617 | 15.979 | 6.617 | 15.979 |
| resqlite selectBytes() | 1.011 | 2.024 | 1.011 | 2.024 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 9.525 | 12.556 | 9.525 | 12.556 |
| sqlite3 + jsonEncode | 13.371 | 19.426 | 13.371 | 19.426 |
| sqlite_async + jsonEncode | 13.549 | 17.406 | 13.549 | 17.406 |
| drift + jsonEncode | 16.488 | 27.068 | 16.488 | 27.068 |
| resqlite selectBytes() | 1.865 | 2.535 | 1.865 | 2.535 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.586 | 23.750 | 20.586 | 23.750 |
| sqlite3 + jsonEncode | 28.158 | 34.150 | 28.158 | 34.150 |
| sqlite_async + jsonEncode | 29.877 | 34.735 | 29.877 | 34.735 |
| drift + jsonEncode | 38.315 | 51.867 | 38.315 | 51.867 |
| resqlite selectBytes() | 3.650 | 5.290 | 3.650 | 5.290 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 44.044 | 58.523 | 44.044 | 58.523 |
| sqlite3 + jsonEncode | 63.495 | 86.480 | 63.495 | 86.480 |
| sqlite_async + jsonEncode | 64.515 | 80.740 | 64.515 | 80.740 |
| drift + jsonEncode | 82.046 | 98.233 | 82.046 | 98.233 |
| resqlite selectBytes() | 8.287 | 9.618 | 8.287 | 9.618 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.34 | 0.30 |
| sqlite_async | 0.96 | 1.25 | 0.96 |
| drift | 1.54 | 1.83 | 1.54 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.32 | 0.33 | 0.16 |
| sqlite_async | 1.33 | 1.68 | 0.67 |
| drift | 2.78 | 3.28 | 1.39 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.41 | 0.89 | 0.10 |
| sqlite_async | 2.19 | 3.04 | 0.55 |
| drift | 5.71 | 9.91 | 1.43 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.95 | 1.57 | 0.12 |
| sqlite_async | 4.51 | 4.67 | 0.56 |
| drift | 9.86 | 10.42 | 1.23 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 122562 |
| resqlite per query | 0.008 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 122562 | 114067..137079 | 9.4 | 27.8 |
| sqlite3 | 189756 | 187561..192521 | 1.3 | 4.4 |
| sqlite_async | 49976 | 45275..51384 | 6.1 | 13.3 |
| drift | 47169 | 45820..48115 | 2.4 | 6.6 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.956 | 15.358 | 14.956 | 15.358 |
| sqlite_async | 34.499 | 37.602 | 34.499 | 37.602 |
| drift | 52.362 | 56.690 | 52.362 | 56.690 |
| sqlite3 (no cache) | 22.994 | 24.104 | 22.994 | 24.104 |
| sqlite3 (cached stmt) | 22.736 | 23.995 | 22.736 | 23.995 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.895 | 2.686 | 1.895 | 2.686 |
| sqlite3 execute() | 1.010 | 1.656 | 1.010 | 1.656 |
| sqlite_async execute() | 3.385 | 3.939 | 3.385 | 3.939 |
| drift execute() | 3.666 | 4.586 | 3.666 | 4.586 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.064 | 0.082 | 0.064 | 0.082 |
| sqlite3 executeBatch() | 0.056 | 0.088 | 0.056 | 0.088 |
| sqlite_async executeBatch() | 0.109 | 0.184 | 0.109 | 0.184 |
| drift executeBatch() | 0.108 | 0.128 | 0.108 | 0.128 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.486 | 0.624 | 0.486 | 0.624 |
| sqlite3 executeBatch() | 0.474 | 0.516 | 0.474 | 0.516 |
| sqlite_async executeBatch() | 0.531 | 0.592 | 0.531 | 0.592 |
| drift executeBatch() | 0.644 | 0.658 | 0.644 | 0.658 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.414 | 5.180 | 4.414 | 5.180 |
| sqlite3 executeBatch() | 4.065 | 4.695 | 4.065 | 4.695 |
| sqlite_async executeBatch() | 4.609 | 4.948 | 4.609 | 4.948 |
| drift executeBatch() | 6.200 | 7.917 | 6.200 | 7.917 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.079 | 0.108 | 0.079 | 0.108 |
| sqlite_async writeTransaction() | 0.124 | 0.171 | 0.124 | 0.171 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.091 | 0.151 | 0.091 | 0.151 |
| resqlite tx.execute() loop | 0.796 | 0.957 | 0.796 | 0.957 |
| sqlite_async tx.execute() loop | 0.987 | 1.344 | 0.987 | 1.344 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.461 | 0.495 | 0.461 | 0.495 |
| resqlite tx.execute() loop | 5.497 | 6.942 | 5.497 | 6.942 |
| sqlite_async tx.execute() loop | 9.482 | 10.295 | 9.482 | 10.295 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.108 | 0.113 | 0.108 | 0.113 |
| sqlite_async tx.getAll() | 0.195 | 0.200 | 0.195 | 0.200 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.189 | 0.196 | 0.189 | 0.196 |
| sqlite_async tx.getAll() | 0.352 | 0.380 | 0.352 | 0.380 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.030 | 0.033 | 0.030 | 0.033 |
| sqlite_async watch() | 0.107 | 0.134 | 0.107 | 0.134 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.050 | 0.071 | 0.050 | 0.071 |
| sqlite_async | 0.077 | 0.113 | 0.077 | 0.113 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.215 | 0.292 | 0.215 | 0.292 |
| sqlite_async | 0.718 | 2.649 | 0.718 | 2.649 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.280 | 0.367 | 0.280 | 0.367 |
| sqlite_async | 0.357 | 0.463 | 0.357 | 0.463 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.887 | 1.887 | 1.887 | 1.887 |
| sqlite_async | 8.706 | 8.706 | 8.706 | 8.706 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.336 | 5.036 | 4.336 | 5.036 |
| sqlite_async | 6.999 | 10.355 | 6.999 | 10.355 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.530 | 0.709 | 0.530 | 0.709 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 6.008 | 6.575 | 6.008 | 6.575 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. On resqlite's main branch this ratio is driven toward 0 by experiment 075 (C-side result-hash short-circuit), not by writer-side column-tracking (exp 052 is not implemented). The two mechanisms are indistinguishable on this read-side benchmark.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 68.2 | 0.000 |
| sqlite_async | 3788 | 960.8 | 0.993 |
| drift | 5000 | 1019.2 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 69.7 | 0.000 |
| sqlite_async | 3813 | 975.9 | 0.993 |
| drift | 5000 | 1050.0 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 227.06 | 227.50 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 437.12 | 444.21 | 0.00 | 0.00 | 1114 | 3 |
| drift stream() | 554.66 | 584.38 | 0.00 | 0.01 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.020 | 0.031 | 0.000 | 0.000 |
| sqlite3 | 0.018 | 0.024 | 0.018 | 0.024 |
| sqlite_async | 0.045 | 0.074 | 0.000 | 0.000 |
| drift | 0.036 | 0.047 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.016 | 0.023 | 0.000 | 0.000 |
| sqlite3 | 0.011 | 0.014 | 0.011 | 0.014 |
| sqlite_async | 0.036 | 0.059 | 0.000 | 0.000 |
| drift | 0.029 | 0.037 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.024 | 0.033 | 0.000 | 0.000 |
| sqlite3 | 0.029 | 0.031 | 0.029 | 0.031 |
| sqlite_async | 0.061 | 0.082 | 0.000 | 0.000 |
| drift | 0.052 | 0.056 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.008 | 0.015 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.024 | 0.035 | 0.000 | 0.000 |
| drift | 0.019 | 0.024 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.041 | 0.065 | 0.001 | 0.001 |
| sqlite3 | 0.060 | 0.061 | 0.060 | 0.061 |
| sqlite_async | 0.078 | 0.081 | 0.001 | 0.001 |
| drift | 0.087 | 0.089 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 109.665 | 110.612 | 0.000 | 0.000 | 0 |
| sqlite_async | 217.861 | 219.820 | 0.000 | 0.000 | 36 |
| drift | 231.032 | 233.741 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 245.86 | 245.86 | 0.00 | 0.00 | 13.69 | 232.16 | 0 |
| sqlite_async | 482.89 | 482.89 | 0.00 | 0.00 | 24.64 | 459.24 | 1183 |
| drift | 2005.76 | 2005.76 | 4.08 | 4.08 | 13.63 | 1993.51 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 7.58 | 17.73 | 2.34..9.42 | ±3.54 |
| sqlite3 select() | 5.73 | 9.45 | 1.16..9.19 | ±4.02 |
| sqlite_async select() | 1.00 | 1.02 | 1.00..1.00 | ±0.00 |
| drift select() | 14.38 | 74.33 | 0.00..52.91 | ±26.45 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 8.00 | 0.00..0.00 | ±0.00 |
| resqlite + jsonEncode | 5.95 | 14.75 | 0.00..6.80 | ±3.40 |
| sqlite3 + jsonEncode | 0.00 | 33.55 | 0.00..12.06 | ±6.03 |
| sqlite_async + jsonEncode | 0.00 | 7.55 | 0.00..7.39 | ±3.70 |
| drift + jsonEncode | 0.00 | 3.66 | 0.00..0.00 | ±0.00 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 3.52 | 8.31 | 0.00..4.81 | ±2.41 |
| sqlite3 executeBatch() | 0.00 | 0.11 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 1.03 | 0.00..0.52 | ±0.26 |
| drift batch() | 0.36 | 4.50 | 0.00..2.50 | ±1.25 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.03 | 0.06 | 0.00..0.06 | ±0.03 |
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

## Sync Burst (v1)

50K bulk insert via executeBatch in 500-row chunks, then 10 × 100-row INSERT OR REPLACE merges. A COUNT(*) stream stays active throughout on reactive peers. Models offline-first sync: a client pulling from a server, applying batched changes, while the local UI shows live counts. Opt-in via --include-slow.

### Bulk insert: 50000 rows × 500-row chunks

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 59.65 | 59.65 | 0.00 | 0.00 |
| sqlite3 | 64.52 | 64.52 | 64.52 | 64.52 |
| sqlite_async | 69.18 | 69.18 | 0.00 | 0.00 |
| drift | 103.30 | 103.30 | 0.00 | 0.00 |

### Merge rounds: 10 × 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.40 | 2.40 | 0.00 | 0.00 |
| sqlite3 | 1.06 | 1.06 | 1.06 | 1.06 |
| sqlite_async | 1.79 | 1.79 | 0.00 | 0.00 |
| drift | 2.04 | 2.04 | 0.00 | 0.00 |

### Stream emissions during burst (COUNT(*))

| Library | Emissions |
|---|---|
| resqlite | 104 |
| sqlite_async | 110 |
| drift | 2 |

Every batch commit invalidates the COUNT(*) stream. Fewer emissions under the same write load signals better coalescing; more emissions may indicate per-commit re-emit without the suppression logic resqlite's engine applies (exp 031/033/075 + PR #17's per-stream re-query coalescing).

## Large Working Set (v1)

Random-point and range-scan latency on a ~1 GB database. Measures behavior at scale, where mmap and page cache matter. Cold-cache and warm-cache variants reported separately. Seed is cached across runs. Opt-in via --include-slow.

### Warm cache (5 rounds)

Random-point (1000/round) and range-scan (10/round, LIMIT 500) against a 5000K-row table.

| Library | Point p50 (ms) | Point p90 (ms) | Range p50 (ms) | Range p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.116 | 0.207 | 0.705 | 1.020 |
| sqlite3 | 0.107 | 0.198 | 0.853 | 1.123 |
| sqlite_async | 0.141 | 0.263 | 0.873 | 1.152 |
| drift | 0.130 | 0.211 | 0.984 | 1.246 |

### Cold cache (3 rounds with shrink_memory)

Random-point (1000/round) and range-scan (10/round, LIMIT 500) against a 5000K-row table.

| Library | Point p50 (ms) | Point p90 (ms) | Range p50 (ms) | Range p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.094 | 0.179 | 0.142 | 0.855 |
| sqlite3 | 0.092 | 0.174 | 0.772 | 1.054 |
| sqlite_async | 0.117 | 0.207 | 0.778 | 1.027 |
| drift | 0.111 | 0.200 | 0.848 | 1.099 |

## Many-Streams Writer Throughput (v1)

Writer throughput (writes/sec) under stream fan-out. A wide 20-column table is watched by N streams, each projecting a subset of columns over a partition of the row space. The writer issues 500 single-row updates first against a column NOT in any stream's projection (disjoint) and then against a column IN every stream's projection (overlapping). The disjoint-vs-overlapping spread reveals whether a library elides per-stream dispatch on column-disjoint writes — the writer-side counterpart to disjoint_columns.dart's stream-side ratio. A no-streams baseline run is reported as a writer-only reference.

### 50 streams × 500 writes per scenario

### No-streams baseline (500 writes, no subscribers)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Writes/sec |
|---|---|---|---|---|---|
| resqlite | 9.55 | 18.73 | 0.00 | 0.00 | 52372 |
| sqlite_async | 20.85 | 21.88 | 0.00 | 0.00 | 23980 |
| drift | 16.40 | 16.73 | 0.00 | 0.00 | 30484 |

### Disjoint column writes (SET c = ?, projection = id, a, b)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Writes/sec | Emissions |
|---|---|---|---|---|---|---|
| resqlite | 69.43 | 69.56 | 0.00 | 0.00 | 7201 | 0 |
| sqlite_async | 248.98 | 260.12 | 0.00 | 0.01 | 2008 | 3789 |
| drift | 2148.93 | 2167.13 | 0.36 | 0.65 | 233 | 25000 |

### Overlapping column writes (SET a = ?, projection = id, a, b)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Writes/sec | Emissions |
|---|---|---|---|---|---|---|
| resqlite | 109.14 | 109.72 | 0.00 | 0.00 | 4581 | 0 |
| sqlite_async | 221.23 | 221.83 | 0.01 | 0.02 | 2260 | 4243 |
| drift | 2159.56 | 2177.73 | 0.20 | 2.29 | 232 | 25000 |

### Overlap-vs-disjoint writer-throughput ratio

| Library | Disjoint w/s | Overlap w/s | Overlap/disjoint |
|---|---|---|---|
| resqlite | 7201 | 4581 | 0.636 |
| sqlite_async | 2008 | 2260 | 1.125 |
| drift | 233 | 232 | 0.995 |

**Writes/sec** is `writeCount / wall_time_seconds`. Higher is better. **Baseline** is the same write loop with no streams subscribed — the writer's ceiling on this hardware.

**Emissions** are post-baseline emissions summed across all 50 streams during the timed write loop. A library with hash-based result suppression (resqlite exp 075) reports low emission counts on the disjoint scenario even when its writer throughput is unchanged — that signal lives in `disjoint_columns.dart`, not here. This suite is about the writer-side cost of the dispatch itself.

**Overlap/disjoint ratio**: writes/sec under overlap divided by writes/sec under disjoint. A ratio close to 1.0 means the library performs similar writer-side work in both scenarios; a ratio ≪ 1.0 means it is actually eliding per-stream dispatch on disjoint writes. resqlite today is expected near 1.0; this benchmark exists to make a future column-tracking optimization (exp 052) visible by driving that ratio down.

## Repeat Stability

These rows summarize resqlite wall medians across repeated full-suite runs.
Use this section to judge whether small deltas are real or just noise.

| Benchmark | Median (ms) | 95% CI (ms) | MDE_ci | Range | MAD | Stability |
|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.02 | 0.02..0.03 | 4.2% | 8.3% | 0.0% | stable |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02..0.02 | 5.0% | 10.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02..0.02 | 3.1% | 6.3% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.30 | 0.29..0.31 | 3.3% | 6.7% | 3.3% | moderate |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.30 | 0.29..0.31 | 3.3% | 6.7% | 3.3% | moderate |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.35 | 0.30..0.78 | 68.6% | 137.1% | 14.3% | noisy |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.17 | 0.15..0.39 | 70.6% | 141.2% | 11.8% | noisy |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.41 | 0.37..0.77 | 48.8% | 97.6% | 9.8% | noisy |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.10 | 0.09..0.19 | 50.0% | 100.0% | 10.0% | noisy |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.70 | 0.69..0.95 | 18.6% | 37.1% | 1.4% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.09 | 0.09..0.12 | 16.7% | 33.3% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.04 | 3.8% | 7.7% | 2.6% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 150.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 109.67 | 108.77..111.22 | 1.1% | 2.2% | 0.8% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 245.86 | 240.21..250.18 | 2.0% | 4.1% | 0.4% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 226.51 | 221.62..227.47 | 1.3% | 2.6% | 0.2% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Large Working Set (v1) / Cold cache (3 rounds with shrink_memory) /... | 0.13 | 0.09..0.14 | 17.2% | 34.4% | 4.8% | moderate |
| Large Working Set (v1) / Cold cache (3 rounds with shrink_memory) /... | 0.67 | 0.14..0.79 | 48.2% | 96.4% | 17.6% | noisy |
| Large Working Set (v1) / Warm cache (5 rounds) / resqlite | 0.13 | 0.12..0.13 | 6.8% | 13.6% | 2.4% | stable |
| Large Working Set (v1) / Warm cache (5 rounds) / resqlite [main] | 0.77 | 0.67..0.83 | 10.7% | 21.4% | 7.8% | moderate |
| Many-Streams Writer Throughput (v1) / Disjoint column writes (SET c... | 69.43 | 67.82..69.76 | 1.4% | 2.8% | 0.5% | stable |
| Many-Streams Writer Throughput (v1) / Disjoint column writes (SET c... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Many-Streams Writer Throughput (v1) / No-streams baseline (500 writ... | 11.65 | 9.55..16.67 | 30.6% | 61.1% | 17.8% | noisy |
| Many-Streams Writer Throughput (v1) / No-streams baseline (500 writ... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Many-Streams Writer Throughput (v1) / Overlap-vs-disjoint writer-th... | 7201.00 | 7167.00..7373.00 | 1.4% | 2.9% | 0.5% | stable |
| Many-Streams Writer Throughput (v1) / Overlap-vs-disjoint writer-th... | 0.63 | 0.58..0.65 | 4.9% | 9.8% | 2.4% | stable |
| Many-Streams Writer Throughput (v1) / Overlapping column writes (SE... | 109.90 | 107.78..115.98 | 3.7% | 7.5% | 1.9% | stable |
| Many-Streams Writer Throughput (v1) / Overlapping column writes (SE... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 15.04 | 14.06..15.21 | 3.8% | 7.6% | 0.7% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 15.04 | 14.06..15.21 | 3.8% | 7.6% | 0.7% | stable |
| Point Query Throughput / resqlite qps | 139018.00 | 122562.00..151168.00 | 10.3% | 20.6% | 3.7% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.02 | 16.7% | 33.3% | 6.7% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.03 | 13.3% | 26.7% | 10.0% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.03 | 13.3% | 26.7% | 10.0% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 50.0% | 100.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.01 | 27.3% | 54.5% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.01 | 27.3% | 54.5% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.04..0.05 | 4.3% | 8.5% | 4.3% | moderate |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.19 | 0.19..0.20 | 3.7% | 7.3% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.19 | 0.19..0.20 | 3.7% | 7.3% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 6.2% | 12.5% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.05 | 6.7% | 13.3% | 4.4% | moderate |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.04 | 0.04..0.05 | 6.7% | 13.3% | 4.4% | moderate |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.38 | 0.37..0.40 | 3.3% | 6.6% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.74 | 1.73..1.88 | 4.3% | 8.7% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.74 | 1.73..1.88 | 4.3% | 8.7% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09..0.09 | 2.4% | 4.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.35 | 0.35..0.37 | 3.1% | 6.2% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.35 | 0.35..0.37 | 3.1% | 6.2% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.44 | 4.35..4.95 | 6.8% | 13.6% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 22.25 | 20.10..23.39 | 7.4% | 14.8% | 5.1% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 22.25 | 20.10..23.39 | 7.4% | 14.8% | 5.1% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.85 | 0.83..0.89 | 3.2% | 6.3% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 3.67 | 3.57..3.84 | 3.7% | 7.3% | 2.7% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 3.67 | 3.57..3.84 | 3.7% | 7.3% | 2.7% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.77 | 0.76..0.78 | 1.0% | 1.9% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.80 | 3.67..3.86 | 2.5% | 5.0% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.80 | 3.67..3.86 | 2.5% | 5.0% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.17 | 0.17..0.17 | 0.3% | 0.6% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.76 | 0.74..1.01 | 18.1% | 36.2% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.76 | 0.74..1.01 | 18.1% | 36.2% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 11.52 | 10.63..12.47 | 8.0% | 16.0% | 6.6% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 43.95 | 43.00..44.04 | 1.2% | 2.4% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 43.95 | 43.00..44.04 | 1.2% | 2.4% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.73 | 1.67..1.74 | 2.1% | 4.2% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 7.80 | 7.30..8.29 | 6.3% | 12.7% | 5.4% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 7.80 | 7.30..8.29 | 6.3% | 12.7% | 5.4% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03..0.03 | 10.0% | 20.0% | 6.7% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.10..0.11 | 4.2% | 8.5% | 2.8% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.11 | 0.10..0.11 | 4.2% | 8.5% | 2.8% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.01 | 12.5% | 25.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.02..0.03 | 13.5% | 26.9% | 3.8% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.02..0.03 | 13.5% | 26.9% | 3.8% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.19 | 0.19..0.20 | 3.6% | 7.3% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.89 | 0.88..1.02 | 7.7% | 15.4% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.89 | 0.88..1.02 | 7.7% | 15.4% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04..0.04 | 2.4% | 4.8% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.19 | 0.18..0.20 | 5.1% | 10.2% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.19 | 0.18..0.20 | 5.1% | 10.2% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.11 | 2.07..2.29 | 5.2% | 10.4% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 9.63 | 9.46..10.93 | 7.6% | 15.3% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 9.63 | 9.46..10.93 | 7.6% | 15.3% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.42 | 0.42..0.45 | 3.8% | 7.6% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 1.86 | 1.83..2.00 | 4.4% | 8.8% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 1.86 | 1.83..2.00 | 4.4% | 8.8% | 1.9% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.10 | 0.10..0.10 | 1.5% | 3.0% | 1.0% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.04 | 0.03..0.04 | 12.9% | 25.7% | 2.9% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.30 | 0.29..0.31 | 2.2% | 4.3% | 1.7% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.10 | 0.10..0.10 | 1.0% | 2.0% | 1.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.29 | 0.29..0.31 | 2.9% | 5.8% | 0.7% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.10 | 0.10..0.10 | 2.6% | 5.2% | 1.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.53 | 0.53..0.63 | 10.1% | 20.2% | 0.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.10 | 0.10..0.11 | 2.5% | 4.9% | 1.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.91 | 0.90..0.97 | 3.9% | 7.7% | 0.8% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.27 | 0.27..0.28 | 3.0% | 6.0% | 0.7% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.05 | 51.9% | 103.7% | 3.7% | moderate |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.01 | 0.01..0.04 | 70.0% | 140.0% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 36.4% | 72.7% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.19..0.22 | 7.3% | 14.6% | 3.9% | moderate |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.16 | 0.15..0.17 | 5.6% | 11.3% | 4.4% | moderate |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.05 | 6.8% | 13.6% | 4.5% | moderate |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.75 | 1.71..1.75 | 1.3% | 2.6% | 0.3% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.44 | 1.43..1.46 | 1.2% | 2.4% | 0.4% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.35 | 0.35..0.36 | 1.6% | 3.1% | 0.6% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 21.16 | 19.98..22.32 | 5.5% | 11.1% | 1.4% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 15.19 | 14.75..15.61 | 2.8% | 5.6% | 2.6% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.96 | 3.73..4.56 | 10.5% | 21.0% | 2.8% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 50.0% | 100.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.08 | 276.9% | 553.8% | 7.7% | moderate |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 1000.0% | 2000.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.04..0.08 | 33.3% | 66.7% | 2.1% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 11.1% | 22.2% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.37 | 0.36..0.40 | 4.3% | 8.6% | 1.1% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.07..0.09 | 12.9% | 25.9% | 0.0% | stable |
| Select → Maps / 10000 rows / resqlite select() | 4.33 | 4.21..4.57 | 4.1% | 8.2% | 1.7% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.83 | 0.66..0.85 | 11.2% | 22.3% | 0.1% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.25 | 0.22..0.59 | 74.1% | 148.2% | 11.6% | noisy |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.25 | 0.22..0.59 | 74.1% | 148.2% | 11.6% | noisy |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.54 | 0.53..0.54 | 1.5% | 3.0% | 0.9% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.54 | 0.53..0.54 | 1.5% | 3.0% | 0.9% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03..0.07 | 75.0% | 150.0% | 6.7% | moderate |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03..0.07 | 75.0% | 150.0% | 6.7% | moderate |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.04..0.05 | 6.4% | 12.8% | 2.1% | stable |
| Streaming / Invalidation Latency / resqlite [main] | 0.05 | 0.04..0.05 | 6.4% | 12.8% | 2.1% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 4.22 | 3.51..4.81 | 15.4% | 30.9% | 13.8% | noisy |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 4.22 | 3.51..4.81 | 15.4% | 30.9% | 13.8% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.89 | 1.83..2.47 | 17.1% | 34.3% | 3.2% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.89 | 1.83..2.47 | 17.1% | 34.3% | 3.2% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.46 | 6.01..6.99 | 7.6% | 15.2% | 5.3% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.46 | 6.01..6.99 | 7.6% | 15.2% | 5.3% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.20 | 0.19..0.63 | 113.2% | 226.4% | 5.6% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.20 | 0.19..0.63 | 113.2% | 226.4% | 5.6% | moderate |
| Sync Burst (v1) / Bulk insert: 50000 rows × 500-row chunks / resqlite | 53.16 | 47.46..61.90 | 13.6% | 27.2% | 10.7% | noisy |
| Sync Burst (v1) / Bulk insert: 50000 rows × 500-row chunks / resqli... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Sync Burst (v1) / Merge rounds: 10 × 100 rows / resqlite | 2.59 | 2.40..3.37 | 18.7% | 37.5% | 1.2% | stable |
| Sync Burst (v1) / Merge rounds: 10 × 100 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Sync Burst (v1) / Stream emissions during burst (COUNT(*)) / resqlite | 104.00 | 103.00..105.00 | 1.0% | 1.9% | 1.0% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.06..0.06 | 6.0% | 12.1% | 1.7% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.06 | 0.06..0.06 | 6.0% | 12.1% | 1.7% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.46 | 0.45..0.49 | 3.5% | 7.0% | 0.9% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.46 | 0.45..0.49 | 3.5% | 7.0% | 0.9% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.62 | 4.41..4.90 | 5.4% | 10.7% | 4.5% | moderate |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.62 | 4.41..4.90 | 5.4% | 10.7% | 4.5% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.59 | 0.53..0.80 | 22.5% | 44.9% | 10.5% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.59 | 0.53..0.80 | 22.5% | 44.9% | 10.5% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07..0.09 | 14.4% | 28.8% | 4.1% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07..0.09 | 14.4% | 28.8% | 4.1% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.41 | 5.31..5.50 | 1.8% | 3.5% | 1.6% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.41 | 5.31..5.50 | 1.8% | 3.5% | 1.6% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.46 | 0.46..0.47 | 1.2% | 2.4% | 0.2% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.46 | 0.46..0.47 | 1.2% | 2.4% | 0.2% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.06 | 0.05..0.08 | 25.0% | 50.0% | 1.8% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.06 | 0.05..0.08 | 25.0% | 50.0% | 1.8% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 2.08 | 1.61..2.67 | 25.3% | 50.7% | 8.9% | noisy |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 2.08 | 1.61..2.67 | 25.3% | 50.7% | 8.9% | noisy |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.18..0.20 | 3.7% | 7.4% | 3.2% | moderate |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.18..0.20 | 3.7% | 7.4% | 3.2% | moderate |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.11 | 0.10..0.13 | 10.6% | 21.3% | 3.7% | moderate |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.11 | 0.10..0.13 | 10.6% | 21.3% | 3.7% | moderate |


## Comparison vs Previous Run

Previous: `2026-04-25T19-43-21-baseline-for-exp105.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.03 | 0.02 | -0.01 | ±10% / ±0.02 ms | 4.2% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.03 | 0.02 | -0.01 | ±10% / ±0.02 ms | 5.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02 | -0.01 | ±10% / ±0.02 ms | 3.1% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.29 | 0.30 | +0.01 | ±10% / ±0.03 ms | 3.3% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.29 | 0.30 | +0.01 | ±10% / ±0.03 ms | 3.3% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.37 | 0.35 | -0.02 | ±69% / ±0.25 ms | 68.6% | noisy | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.19 | 0.17 | -0.02 | ±71% / ±0.13 ms | 70.6% | noisy | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.41 | 0.41 | +0.00 | ±49% / ±0.20 ms | 48.8% | noisy | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.10 | 0.10 | +0.00 | ±50% / ±0.05 ms | 50.0% | noisy | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.76 | 0.70 | -0.06 | ±19% / ±0.14 ms | 18.6% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.10 | 0.09 | -0.01 | ±17% / ±0.02 ms | 16.7% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 3.8% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | -0.00 | ±150% / ±0.02 ms | 150.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 110.75 | 109.67 | -1.08 | ±10% / ±11.07 ms | 1.1% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 240.15 | 245.86 | +5.71 | ±10% / ±24.59 ms | 2.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 218.84 | 226.51 | +7.67 | ±10% / ±22.65 ms | 1.3% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Large Working Set (v1) / Cold cache (3 rounds with shrink... | 0.10 | 0.13 | +0.02 | ±17% / ±0.02 ms | 17.2% | moderate | 🔴 Regression (+25%) |
| Large Working Set (v1) / Cold cache (3 rounds with shrink... | 0.64 | 0.67 | +0.03 | ±53% / ±0.35 ms | 48.2% | noisy | ⚪ Within noise |
| Large Working Set (v1) / Warm cache (5 rounds) / resqlite | 0.12 | 0.13 | +0.01 | ±10% / ±0.02 ms | 6.8% | stable | ⚪ Within noise |
| Large Working Set (v1) / Warm cache (5 rounds) / resqlite... | 0.74 | 0.77 | +0.02 | ±24% / ±0.18 ms | 10.7% | moderate | ⚪ Within noise |
| Many-Streams Writer Throughput (v1) / Disjoint column wri... | 126.39 | 69.43 | -56.96 | ±10% / ±12.64 ms | 1.4% | stable | 🟢 Win (-45%) |
| Many-Streams Writer Throughput (v1) / Disjoint column wri... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Many-Streams Writer Throughput (v1) / No-streams baseline... | 9.98 | 11.65 | +1.67 | ±53% / ±6.21 ms | 30.6% | noisy | ⚪ Within noise |
| Many-Streams Writer Throughput (v1) / No-streams baseline... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Many-Streams Writer Throughput (v1) / Overlap-vs-disjoint... | 3956.00 | 7201.00 | +3245.00 | ±10% / ±720.10 ms | 1.4% | stable | 🔴 Regression (+82%) |
| Many-Streams Writer Throughput (v1) / Overlap-vs-disjoint... | 1.13 | 0.63 | -0.50 | ±10% / ±0.11 ms | 4.9% | stable | 🟢 Win (-44%) |
| Many-Streams Writer Throughput (v1) / Overlapping column ... | 111.69 | 109.90 | -1.79 | ±10% / ±11.17 ms | 3.7% | stable | ⚪ Within noise |
| Many-Streams Writer Throughput (v1) / Overlapping column ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 15.86 | 15.04 | -0.82 | ±10% / ±1.59 ms | 3.8% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 15.86 | 15.04 | -0.82 | ±10% / ±1.59 ms | 3.8% | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 118279.00 | 139018.00 | +20739.00 | ±11% / ±15234.00 ms | 10.3% | moderate | 🟢 Win (18%) |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.02 | 0.01 | -0.00 | ±20% / ±0.02 ms | 16.7% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.04 | 0.03 | -0.01 | ±30% / ±0.02 ms | 13.3% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.04 | 0.03 | -0.01 | ±30% / ±0.02 ms | 13.3% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | -0.00 | ±50% / ±0.02 ms | 50.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | -0.00 | ±27% / ±0.02 ms | 27.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | -0.00 | ±27% / ±0.02 ms | 27.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05 | -0.00 | ±13% / ±0.02 ms | 4.3% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.20 | 0.19 | -0.01 | ±10% / ±0.02 ms | 3.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.20 | 0.19 | -0.01 | ±10% / ±0.02 ms | 3.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | 6.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.05 | 0.04 | -0.01 | ±13% / ±0.02 ms | 6.7% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.05 | 0.04 | -0.01 | ±13% / ±0.02 ms | 6.7% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.40 | 0.38 | -0.03 | ±10% / ±0.04 ms | 3.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.85 | 1.74 | -0.12 | ±10% / ±0.19 ms | 4.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.85 | 1.74 | -0.12 | ±10% / ±0.19 ms | 4.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09 | -0.00 | ±10% / ±0.02 ms | 2.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.35 | +0.00 | ±10% / ±0.04 ms | 3.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.35 | +0.00 | ±10% / ±0.04 ms | 3.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 7.73 | 4.44 | -3.29 | ±10% / ±0.77 ms | 6.8% | stable | 🟢 Win (-43%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 21.08 | 22.25 | +1.17 | ±15% / ±3.43 ms | 7.4% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 21.08 | 22.25 | +1.17 | ±15% / ±3.43 ms | 7.4% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.94 | 0.85 | -0.09 | ±10% / ±0.09 ms | 3.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.93 | 3.67 | -0.26 | ±10% / ±0.39 ms | 3.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.93 | 3.67 | -0.26 | ±10% / ±0.39 ms | 3.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.85 | 0.77 | -0.08 | ±10% / ±0.09 ms | 1.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 4.77 | 3.80 | -0.97 | ±10% / ±0.48 ms | 2.5% | stable | 🟢 Win (-20%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 4.77 | 3.80 | -0.97 | ±10% / ±0.48 ms | 2.5% | stable | 🟢 Win (-20%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.18 | 0.17 | -0.01 | ±10% / ±0.02 ms | 0.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.86 | 0.76 | -0.10 | ±18% / ±0.16 ms | 18.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.86 | 0.76 | -0.10 | ±18% / ±0.16 ms | 18.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 12.21 | 11.52 | -0.69 | ±20% / ±2.42 ms | 8.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 43.14 | 43.95 | +0.81 | ±10% / ±4.39 ms | 1.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 43.14 | 43.95 | +0.81 | ±10% / ±4.39 ms | 1.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.70 | 1.73 | +0.03 | ±10% / ±0.17 ms | 2.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 7.57 | 7.80 | +0.23 | ±16% / ±1.26 ms | 6.3% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 7.57 | 7.80 | +0.23 | ±16% / ±1.26 ms | 6.3% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03 | -0.00 | ±20% / ±0.02 ms | 10.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.11 | -0.00 | ±10% / ±0.02 ms | 4.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.11 | 0.11 | -0.00 | ±10% / ±0.02 ms | 4.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±13% / ±0.02 ms | 12.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | -0.00 | ±13% / ±0.02 ms | 13.5% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | -0.00 | ±13% / ±0.02 ms | 13.5% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.20 | 0.19 | -0.01 | ±10% / ±0.02 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.89 | 0.89 | +0.00 | ±10% / ±0.09 ms | 7.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.89 | 0.89 | +0.00 | ±10% / ±0.09 ms | 7.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 2.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.19 | +0.01 | ±10% / ±0.02 ms | 5.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.19 | +0.01 | ±10% / ±0.02 ms | 5.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.24 | 2.11 | -0.13 | ±10% / ±0.22 ms | 5.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.19 | 9.63 | -0.55 | ±10% / ±1.02 ms | 7.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.19 | 9.63 | -0.55 | ±10% / ±1.02 ms | 7.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.44 | 0.42 | -0.02 | ±10% / ±0.04 ms | 3.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.95 | 1.86 | -0.08 | ±10% / ±0.19 ms | 4.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.95 | 1.86 | -0.08 | ±10% / ±0.19 ms | 4.4% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.11 | 0.10 | -0.01 | ±10% / ±0.02 ms | 1.5% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.03 | 0.04 | +0.01 | ±13% / ±0.02 ms | 12.9% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.32 | 0.30 | -0.02 | ±10% / ±0.03 ms | 2.2% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 1.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.31 | 0.29 | -0.02 | ±10% / ±0.03 ms | 2.9% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 2.6% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.57 | 0.53 | -0.04 | ±10% / ±0.06 ms | 10.1% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 2.5% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.93 | 0.91 | -0.02 | ±10% / ±0.09 ms | 3.9% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.28 | 0.27 | -0.01 | ±10% / ±0.03 ms | 3.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.10 | 0.03 | -0.07 | ±52% / ±0.05 ms | 51.9% | moderate | 🟢 Win (-72%) |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.07 | 0.01 | -0.06 | ±70% / ±0.05 ms | 70.0% | stable | 🟢 Win (-80%) |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.02 | 0.01 | -0.01 | ±36% / ±0.02 ms | 36.4% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.24 | 0.20 | -0.04 | ±12% / ±0.03 ms | 7.3% | moderate | 🟢 Win (-16%) |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.19 | 0.16 | -0.03 | ±13% / ±0.03 ms | 5.6% | moderate | 🟢 Win (-16%) |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.04 | -0.01 | ±14% / ±0.02 ms | 6.8% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.99 | 1.75 | -0.24 | ±10% / ±0.20 ms | 1.3% | stable | 🟢 Win (-12%) |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.59 | 1.44 | -0.15 | ±10% / ±0.16 ms | 1.2% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.36 | 0.35 | -0.01 | ±10% / ±0.04 ms | 1.6% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 21.34 | 21.16 | -0.18 | ±10% / ±2.13 ms | 5.5% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 15.25 | 15.19 | -0.06 | ±10% / ±1.53 ms | 2.8% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.85 | 3.96 | +0.10 | ±11% / ±0.42 ms | 10.5% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±50% / ±0.02 ms | 50.0% | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.10 | 0.01 | -0.08 | ±277% / ±0.26 ms | 276.9% | moderate | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.02 | 0.00 | -0.02 | ±1000% / ±0.22 ms | 1000.0% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.07 | 0.05 | -0.02 | ±33% / ±0.02 ms | 33.3% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±11% / ±0.02 ms | 11.1% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.39 | 0.37 | -0.01 | ±10% / ±0.04 ms | 4.3% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.07 | 0.09 | +0.01 | ±13% / ±0.02 ms | 12.9% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 7.78 | 4.33 | -3.45 | ±10% / ±0.78 ms | 4.1% | stable | 🟢 Win (-44%) |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.76 | 0.83 | +0.08 | ±11% / ±0.09 ms | 11.2% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.47 | 0.25 | -0.22 | ±74% / ±0.35 ms | 74.1% | noisy | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.47 | 0.25 | -0.22 | ±74% / ±0.35 ms | 74.1% | noisy | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.51 | 0.54 | +0.03 | ±10% / ±0.05 ms | 1.5% | stable | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.51 | 0.54 | +0.03 | ±10% / ±0.05 ms | 1.5% | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.06 | 0.03 | -0.03 | ±75% / ±0.05 ms | 75.0% | moderate | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.06 | 0.03 | -0.03 | ±75% / ±0.05 ms | 75.0% | moderate | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.05 | +0.00 | ±10% / ±0.02 ms | 6.4% | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.05 | +0.00 | ±10% / ±0.02 ms | 6.4% | stable | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.87 | 4.22 | +0.35 | ±41% / ±1.75 ms | 15.4% | noisy | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.87 | 4.22 | +0.35 | ±41% / ±1.75 ms | 15.4% | noisy | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 3.07 | 1.89 | -1.18 | ±17% / ±0.53 ms | 17.1% | moderate | 🟢 Win (-39%) |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 3.07 | 1.89 | -1.18 | ±17% / ±0.53 ms | 17.1% | moderate | 🟢 Win (-39%) |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 7.35 | 6.46 | -0.89 | ±16% / ±1.16 ms | 7.6% | moderate | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 7.35 | 6.46 | -0.89 | ±16% / ±1.16 ms | 7.6% | moderate | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.51 | 0.20 | -0.31 | ±113% / ±0.57 ms | 113.2% | moderate | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.51 | 0.20 | -0.31 | ±113% / ±0.57 ms | 113.2% | moderate | ⚪ Within noise |
| Sync Burst (v1) / Bulk insert: 50000 rows × 500-row chunk... | 59.34 | 53.16 | -6.18 | ±32% / ±19.09 ms | 13.6% | noisy | ⚪ Within noise |
| Sync Burst (v1) / Bulk insert: 50000 rows × 500-row chunk... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Sync Burst (v1) / Merge rounds: 10 × 100 rows / resqlite | 2.76 | 2.59 | -0.17 | ±19% / ±0.52 ms | 18.7% | stable | ⚪ Within noise |
| Sync Burst (v1) / Merge rounds: 10 × 100 rows / resqlite ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Sync Burst (v1) / Stream emissions during burst (COUNT(*)... | 102.00 | 104.00 | +2.00 | ±10% / ±10.40 ms | 1.0% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | -0.00 | ±10% / ±0.02 ms | 6.0% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | -0.00 | ±10% / ±0.02 ms | 6.0% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.45 | 0.46 | +0.01 | ±10% / ±0.05 ms | 3.5% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.45 | 0.46 | +0.01 | ±10% / ±0.05 ms | 3.5% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.61 | 4.62 | +0.01 | ±14% / ±0.62 ms | 5.4% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.61 | 4.62 | +0.01 | ±14% / ±0.62 ms | 5.4% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.97 | 0.59 | -0.38 | ±31% / ±0.31 ms | 22.5% | noisy | 🟢 Win (-39%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.97 | 0.59 | -0.38 | ±31% / ±0.31 ms | 22.5% | noisy | 🟢 Win (-39%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.09 | 0.07 | -0.01 | ±14% / ±0.02 ms | 14.4% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.09 | 0.07 | -0.01 | ±14% / ±0.02 ms | 14.4% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 6.08 | 5.41 | -0.67 | ±10% / ±0.61 ms | 1.8% | stable | 🟢 Win (-11%) |
| Write Performance / Batched Write Inside Transaction (100... | 6.08 | 5.41 | -0.67 | ±10% / ±0.61 ms | 1.8% | stable | 🟢 Win (-11%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.47 | 0.46 | -0.01 | ±10% / ±0.05 ms | 1.2% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.47 | 0.46 | -0.01 | ±10% / ±0.05 ms | 1.2% | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.08 | 0.06 | -0.03 | ±25% / ±0.02 ms | 25.0% | stable | 🟢 Win (-33%) |
| Write Performance / Interactive Transaction (insert + sel... | 0.08 | 0.06 | -0.03 | ±25% / ±0.02 ms | 25.0% | stable | 🟢 Win (-33%) |
| Write Performance / Single Inserts (100 sequential) / res... | 1.92 | 2.08 | +0.16 | ±27% / ±0.55 ms | 25.3% | noisy | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.92 | 2.08 | +0.16 | ±27% / ±0.55 ms | 25.3% | noisy | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.21 | 0.19 | -0.03 | ±10% / ±0.02 ms | 3.7% | moderate | 🟢 Win (-12%) |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.21 | 0.19 | -0.03 | ±10% / ±0.02 ms | 3.7% | moderate | 🟢 Win (-12%) |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.13 | 0.11 | -0.02 | ±11% / ±0.02 ms | 10.6% | moderate | 🟢 Win (-16%) |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.13 | 0.11 | -0.02 | ±11% / ±0.02 ms | 10.6% | moderate | 🟢 Win (-16%) |

**Summary:** 24 wins, 2 regressions, 144 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.00 | 0.36 | +0.36 MB | ±1.25 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 0.08 | 3.52 | +3.44 MB | ±2.41 MB | 🔴 Regression (+3.44 MB) |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 5.50 | 0.00 | -5.50 MB | ±0.50 MB | 🟢 Win (-5.50 MB) |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 2.53 | 5.95 | +3.42 MB | ±3.40 MB | 🔴 Regression (+3.42 MB) |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.41 | 0.00 | -0.41 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 0.00 | 0.00 | +0.00 MB | ±6.03 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±3.70 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 7.70 | 14.38 | +6.68 MB | ±26.45 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / resqlite select() | 2.11 | 7.58 | +5.47 MB | ±3.54 MB | 🔴 Regression (+5.47 MB) |
| Memory / Select 10k rows → Maps / sqlite3 select() | 2.69 | 5.73 | +3.04 MB | ±4.02 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 1.00 | 1.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.06 | 0.03 | -0.03 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 1 wins, 3 regressions, 11 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 3699 | 3788 | +89 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 3195 | 3813 | +618 | ±100 | 🔴 More re-emits (+618) |

**Granularity summary:** 0 fewer-re-emit, 1 more-re-emit, 5 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


