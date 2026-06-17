# resqlite Benchmark Results

Generated: 2026-06-16T08:57:00.651950

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp176-containskey-identity`
- Repeats: `5`
- Runtime: `dart-vm / Dart 3.11.5`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `exp-176-containskey-identity-fastpath @ bf9066e1509c (dirty)`
- Comparison baseline: `none`
- Comparison mode: `none`
- Comparison baseline compatibility: `not applicable`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.012 | 0.014 | 0.000 | 0.000 |
| sqlite3 select() | 0.017 | 0.020 | 0.017 | 0.020 |
| sqlite_async select() | 0.031 | 0.041 | 0.001 | 0.002 |
| drift select() | 0.036 | 0.059 | 0.001 | 0.002 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.045 | 0.047 | 0.005 | 0.006 |
| sqlite3 select() | 0.116 | 0.119 | 0.116 | 0.119 |
| sqlite_async select() | 0.129 | 0.148 | 0.010 | 0.011 |
| drift select() | 0.184 | 0.238 | 0.010 | 0.012 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.352 | 0.418 | 0.052 | 0.064 |
| sqlite3 select() | 1.142 | 1.299 | 1.142 | 1.299 |
| sqlite_async select() | 1.132 | 1.414 | 0.097 | 0.112 |
| drift select() | 1.580 | 2.447 | 0.096 | 0.110 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.474 | 10.248 | 0.539 | 0.980 |
| sqlite3 select() | 13.852 | 17.224 | 13.852 | 17.224 |
| sqlite_async select() | 13.979 | 15.246 | 0.972 | 1.072 |
| drift select() | 21.432 | 31.853 | 1.034 | 4.495 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.028 | 0.030 | 0.016 | 0.017 |
| sqlite3 + jsonEncode | 0.031 | 0.034 | 0.031 | 0.034 |
| sqlite_async + jsonEncode | 0.050 | 0.059 | 0.016 | 0.017 |
| drift + jsonEncode | 0.055 | 0.060 | 0.016 | 0.018 |
| resqlite selectBytes() | 0.011 | 0.017 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.200 | 0.240 | 0.157 | 0.183 |
| sqlite3 + jsonEncode | 0.276 | 0.353 | 0.276 | 0.353 |
| sqlite_async + jsonEncode | 0.292 | 0.400 | 0.161 | 0.191 |
| drift + jsonEncode | 0.383 | 0.490 | 0.177 | 0.199 |
| resqlite selectBytes() | 0.053 | 0.114 | 0.000 | 0.001 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.885 | 3.722 | 1.549 | 2.606 |
| sqlite3 + jsonEncode | 2.645 | 4.927 | 2.645 | 4.927 |
| sqlite_async + jsonEncode | 2.605 | 4.924 | 1.504 | 2.070 |
| drift + jsonEncode | 3.117 | 5.587 | 1.520 | 2.027 |
| resqlite selectBytes() | 0.387 | 0.430 | 0.000 | 0.003 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 24.385 | 40.342 | 17.267 | 27.814 |
| sqlite3 + jsonEncode | 32.454 | 47.306 | 32.454 | 47.306 |
| sqlite_async + jsonEncode | 30.670 | 38.297 | 15.908 | 18.554 |
| drift + jsonEncode | 42.345 | 48.576 | 15.691 | 21.358 |
| resqlite selectBytes() | 3.766 | 3.922 | 0.003 | 0.005 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.092 | 0.105 | 0.024 | 0.025 |
| sqlite3 | 0.327 | 0.374 | 0.327 | 0.374 |
| sqlite_async | 0.375 | 0.401 | 0.034 | 0.035 |
| drift | 0.574 | 0.654 | 0.033 | 0.038 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.870 | 0.972 | 0.205 | 0.229 |
| sqlite3 | 3.387 | 4.014 | 3.387 | 4.014 |
| sqlite_async | 3.112 | 3.490 | 0.251 | 0.281 |
| drift | 4.859 | 6.495 | 0.261 | 0.316 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.562 | 0.619 | 0.065 | 0.068 |
| sqlite3 | 1.505 | 1.707 | 1.505 | 1.707 |
| sqlite_async | 1.483 | 1.731 | 0.093 | 0.113 |
| drift | 2.090 | 2.583 | 0.095 | 0.104 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.265 | 0.296 | 0.061 | 0.068 |
| sqlite3 | 1.015 | 1.123 | 1.015 | 1.123 |
| sqlite_async | 0.969 | 1.127 | 0.088 | 0.099 |
| drift | 1.457 | 1.814 | 0.089 | 0.096 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.267 | 0.281 | 0.062 | 0.063 |
| sqlite3 | 1.000 | 1.038 | 1.000 | 1.038 |
| sqlite_async | 1.013 | 1.130 | 0.092 | 0.103 |
| drift | 1.489 | 1.719 | 0.090 | 0.102 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.011 | 0.012 | 0.000 | 0.000 |
| sqlite3 | 0.015 | 0.016 | 0.015 | 0.016 |
| sqlite_async | 0.031 | 0.035 | 0.001 | 0.001 |
| drift | 0.037 | 0.047 | 0.001 | 0.001 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.026 | 0.029 | 0.003 | 0.003 |
| sqlite3 | 0.065 | 0.081 | 0.065 | 0.081 |
| sqlite_async | 0.075 | 0.087 | 0.004 | 0.004 |
| drift | 0.120 | 0.138 | 0.004 | 0.006 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.045 | 0.064 | 0.005 | 0.007 |
| sqlite3 | 0.120 | 0.142 | 0.120 | 0.142 |
| sqlite_async | 0.128 | 0.152 | 0.008 | 0.009 |
| drift | 0.194 | 0.235 | 0.008 | 0.010 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.183 | 0.207 | 0.027 | 0.028 |
| sqlite3 | 0.553 | 0.676 | 0.553 | 0.676 |
| sqlite_async | 0.592 | 0.645 | 0.040 | 0.048 |
| drift | 0.775 | 1.062 | 0.037 | 0.045 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.346 | 0.434 | 0.052 | 0.057 |
| sqlite3 | 1.137 | 2.500 | 1.137 | 2.500 |
| sqlite_async | 1.054 | 1.381 | 0.075 | 0.080 |
| drift | 1.767 | 2.012 | 0.086 | 0.091 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.768 | 0.829 | 0.109 | 0.115 |
| sqlite3 | 2.306 | 2.955 | 2.306 | 2.955 |
| sqlite_async | 2.200 | 2.496 | 0.157 | 0.168 |
| drift | 3.253 | 3.839 | 0.156 | 0.176 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.197 | 6.676 | 0.269 | 0.307 |
| sqlite3 | 5.852 | 7.983 | 5.852 | 7.983 |
| sqlite_async | 6.015 | 7.178 | 0.398 | 0.502 |
| drift | 8.919 | 17.170 | 0.397 | 0.429 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.344 | 10.007 | 0.546 | 0.924 |
| sqlite3 | 15.082 | 18.401 | 15.082 | 18.401 |
| sqlite_async | 12.261 | 14.915 | 0.769 | 0.845 |
| drift | 20.074 | 29.505 | 0.796 | 2.456 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 10.981 | 22.542 | 1.078 | 1.173 |
| sqlite3 | 35.833 | 46.467 | 35.833 | 46.467 |
| sqlite_async | 42.655 | 53.083 | 1.701 | 6.244 |
| drift | 59.492 | 70.815 | 1.608 | 8.037 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.030 | 0.032 | 0.030 | 0.032 |
| sqlite3 + jsonEncode | 0.030 | 0.031 | 0.030 | 0.031 |
| sqlite_async + jsonEncode | 0.050 | 0.063 | 0.050 | 0.063 |
| drift + jsonEncode | 0.057 | 0.079 | 0.057 | 0.079 |
| resqlite selectBytes() | 0.010 | 0.012 | 0.010 | 0.012 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.104 | 0.110 | 0.104 | 0.110 |
| sqlite3 + jsonEncode | 0.132 | 0.141 | 0.132 | 0.141 |
| sqlite_async + jsonEncode | 0.148 | 0.153 | 0.148 | 0.153 |
| drift + jsonEncode | 0.198 | 0.218 | 0.198 | 0.218 |
| resqlite selectBytes() | 0.032 | 0.335 | 0.032 | 0.335 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.193 | 0.208 | 0.193 | 0.208 |
| sqlite3 + jsonEncode | 0.261 | 0.287 | 0.261 | 0.287 |
| sqlite_async + jsonEncode | 0.272 | 0.320 | 0.272 | 0.320 |
| drift + jsonEncode | 0.362 | 0.432 | 0.362 | 0.432 |
| resqlite selectBytes() | 0.046 | 0.056 | 0.046 | 0.056 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.897 | 1.650 | 0.897 | 1.650 |
| sqlite3 + jsonEncode | 1.269 | 3.588 | 1.269 | 3.588 |
| sqlite_async + jsonEncode | 1.302 | 2.675 | 1.302 | 2.675 |
| drift + jsonEncode | 1.687 | 2.928 | 1.687 | 2.928 |
| resqlite selectBytes() | 0.171 | 0.194 | 0.171 | 0.194 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.949 | 5.087 | 1.949 | 5.087 |
| sqlite3 + jsonEncode | 2.589 | 5.297 | 2.589 | 5.297 |
| sqlite_async + jsonEncode | 2.665 | 5.472 | 2.665 | 5.472 |
| drift + jsonEncode | 3.247 | 5.868 | 3.247 | 5.868 |
| resqlite selectBytes() | 0.347 | 0.442 | 0.347 | 0.442 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.921 | 9.264 | 3.921 | 9.264 |
| sqlite3 + jsonEncode | 5.492 | 10.262 | 5.492 | 10.262 |
| sqlite_async + jsonEncode | 5.690 | 10.919 | 5.690 | 10.919 |
| drift + jsonEncode | 6.978 | 12.773 | 6.978 | 12.773 |
| resqlite selectBytes() | 0.770 | 0.883 | 0.770 | 0.883 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 10.821 | 16.360 | 10.821 | 16.360 |
| sqlite3 + jsonEncode | 15.251 | 20.440 | 15.251 | 20.440 |
| sqlite_async + jsonEncode | 15.401 | 20.709 | 15.401 | 20.709 |
| drift + jsonEncode | 18.503 | 25.453 | 18.503 | 25.453 |
| resqlite selectBytes() | 1.971 | 2.096 | 1.971 | 2.096 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 23.494 | 31.044 | 23.494 | 31.044 |
| sqlite3 + jsonEncode | 32.669 | 39.352 | 32.669 | 39.352 |
| sqlite_async + jsonEncode | 33.980 | 36.025 | 33.980 | 36.025 |
| drift + jsonEncode | 40.383 | 45.509 | 40.383 | 45.509 |
| resqlite selectBytes() | 3.684 | 3.834 | 3.684 | 3.834 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 47.768 | 50.227 | 47.768 | 50.227 |
| sqlite3 + jsonEncode | 66.428 | 74.903 | 66.428 | 74.903 |
| sqlite_async + jsonEncode | 74.695 | 87.824 | 74.695 | 87.824 |
| drift + jsonEncode | 96.954 | 125.611 | 96.954 | 125.611 |
| resqlite selectBytes() | 9.004 | 11.024 | 9.004 | 11.024 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.34 | 0.45 | 0.34 |
| sqlite_async | 1.17 | 1.69 | 1.17 |
| drift | 1.70 | 2.05 | 1.70 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.35 | 0.45 | 0.17 |
| sqlite_async | 1.62 | 1.97 | 0.81 |
| drift | 3.06 | 5.95 | 1.53 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.65 | 0.99 | 0.16 |
| sqlite_async | 2.83 | 3.69 | 0.71 |
| drift | 6.02 | 7.14 | 1.51 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.85 | 1.38 | 0.11 |
| sqlite_async | 5.57 | 6.70 | 0.70 |
| drift | 11.87 | 13.38 | 1.48 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 107348 |
| resqlite per query | 0.009 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 107348 | 103118..110474 | 3.4 | 10.9 |
| sqlite3 | 180666 | 177838..183382 | 1.5 | 4.7 |
| sqlite_async | 40953 | 39478..41605 | 2.6 | 5.8 |
| drift | 36103 | 35224..36713 | 2.1 | 7.3 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 15.467 | 16.866 | 15.467 | 16.866 |
| sqlite_async | 42.024 | 48.917 | 42.024 | 48.917 |
| drift | 57.264 | 67.276 | 57.264 | 67.276 |
| sqlite3 (no cache) | 24.111 | 27.663 | 24.111 | 27.663 |
| sqlite3 (cached stmt) | 24.203 | 26.446 | 24.203 | 26.446 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.802 | 4.590 | 1.802 | 4.590 |
| sqlite3 execute() | 1.278 | 1.798 | 1.278 | 1.798 |
| sqlite_async execute() | 3.357 | 4.085 | 3.357 | 4.085 |
| drift execute() | 3.597 | 4.484 | 3.597 | 4.484 |

### Concurrent Single Inserts (100 concurrent)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite concurrent execute() | 1.206 | 1.849 | 1.206 | 1.849 |
| sqlite3 concurrent execute() | 1.021 | 1.830 | 1.021 | 1.830 |
| sqlite_async concurrent execute() | 3.110 | 3.738 | 3.110 | 3.738 |
| drift concurrent execute() | 2.014 | 2.697 | 2.014 | 2.697 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.061 | 0.106 | 0.061 | 0.106 |
| sqlite3 executeBatch() | 0.052 | 0.054 | 0.052 | 0.054 |
| sqlite_async executeBatch() | 0.104 | 0.249 | 0.104 | 0.249 |
| drift executeBatch() | 0.117 | 0.185 | 0.117 | 0.185 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.416 | 0.488 | 0.416 | 0.488 |
| sqlite3 executeBatch() | 0.462 | 0.493 | 0.462 | 0.493 |
| sqlite_async executeBatch() | 0.588 | 0.667 | 0.588 | 0.667 |
| drift executeBatch() | 0.734 | 0.816 | 0.734 | 0.816 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.051 | 7.292 | 4.051 | 7.292 |
| sqlite3 executeBatch() | 4.484 | 4.892 | 4.484 | 4.892 |
| sqlite_async executeBatch() | 5.445 | 5.864 | 5.445 | 5.864 |
| drift executeBatch() | 6.696 | 7.727 | 6.696 | 7.727 |

### Wide Batch Insert (10000 rows x 20 params)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 14.049 | 26.795 | 14.049 | 26.795 |
| sqlite3 executeBatch() | 20.037 | 22.475 | 20.037 | 22.475 |
| sqlite_async executeBatch() | 25.173 | 34.216 | 25.173 | 34.216 |
| drift executeBatch() | 27.415 | 34.418 | 27.415 | 34.418 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.057 | 0.101 | 0.057 | 0.101 |
| sqlite_async writeTransaction() | 0.099 | 0.175 | 0.099 | 0.175 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.064 | 0.090 | 0.064 | 0.090 |
| resqlite tx.execute() loop | 0.520 | 0.650 | 0.520 | 0.650 |
| sqlite_async tx.execute() loop | 1.139 | 1.398 | 1.139 | 1.398 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.417 | 0.542 | 0.417 | 0.542 |
| resqlite tx.execute() loop | 5.047 | 6.195 | 5.047 | 6.195 |
| sqlite_async tx.execute() loop | 11.642 | 13.098 | 11.642 | 13.098 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.113 | 0.143 | 0.113 | 0.143 |
| sqlite_async tx.getAll() | 0.203 | 0.289 | 0.203 | 0.289 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.197 | 0.227 | 0.197 | 0.227 |
| sqlite_async tx.getAll() | 0.387 | 0.536 | 0.387 | 0.536 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 0.946 | 1.092 | 0.946 | 1.092 |
| resqlite nested transaction() depth=5 | 0.098 | 0.137 | 0.098 | 0.137 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.029 | 0.058 | 0.029 | 0.058 |
| sqlite_async watch() | 0.119 | 0.250 | 0.119 | 0.250 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.047 | 0.100 | 0.047 | 0.100 |
| sqlite_async | 0.083 | 0.196 | 0.083 | 0.196 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.201 | 0.258 | 0.201 | 0.258 |
| sqlite_async | 0.552 | 1.243 | 0.552 | 1.243 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.569 | 4.280 | 2.569 | 4.280 |

### Long-Payload Unchanged Fanout (8 streams, 64 rows x 32KB TEXT + 32KB BLOB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.636 | 6.326 | 3.636 | 6.326 |

### Long-Text 32KB Unchanged Fanout (8 unchanged streams, 64 rows x 32KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.598 | 5.465 | 3.598 | 5.465 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.247 | 0.297 | 0.247 | 0.297 |
| sqlite_async | 0.346 | 0.397 | 0.346 | 0.397 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.794 | 1.794 | 1.794 | 1.794 |
| sqlite_async | 9.303 | 9.303 | 9.303 | 9.303 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.582 | 4.585 | 3.582 | 4.585 |
| sqlite_async | 6.419 | 7.552 | 6.419 | 7.552 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.599 | 1.109 | 0.599 | 1.109 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 7.224 | 8.008 | 7.224 | 8.008 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. For resqlite, this emission metric can reflect writer-side column-level invalidation, experiment 075's native result-hash short-circuit, or both. Use A11c (Many-Streams Writer Throughput) when the question is specifically writer-side dispatch elision.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 67.3 | 0.000 |
| sqlite_async | 3925 | 1204.0 | 1.025 |
| drift | 5000 | 1115.3 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 74.0 | 0.000 |
| sqlite_async | 3830 | 1316.7 | 1.025 |
| drift | 5000 | 1115.0 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 213.06 | 214.88 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 431.82 | 432.32 | 0.00 | 0.00 | 1136 | 3 |
| drift stream() | 607.47 | 620.59 | 0.10 | 0.11 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.032 | 0.065 | 0.000 | 0.000 |
| sqlite3 | 0.021 | 0.040 | 0.021 | 0.040 |
| sqlite_async | 0.059 | 0.115 | 0.000 | 0.000 |
| drift | 0.051 | 0.087 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.023 | 0.050 | 0.000 | 0.000 |
| sqlite3 | 0.014 | 0.025 | 0.014 | 0.025 |
| sqlite_async | 0.045 | 0.098 | 0.000 | 0.000 |
| drift | 0.041 | 0.076 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.032 | 0.053 | 0.000 | 0.000 |
| sqlite3 | 0.033 | 0.038 | 0.033 | 0.038 |
| sqlite_async | 0.070 | 0.124 | 0.000 | 0.001 |
| drift | 0.058 | 0.076 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.012 | 0.026 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.007 | 0.005 | 0.007 |
| sqlite_async | 0.026 | 0.047 | 0.000 | 0.000 |
| drift | 0.023 | 0.036 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.046 | 0.110 | 0.001 | 0.001 |
| sqlite3 | 0.065 | 0.068 | 0.065 | 0.068 |
| sqlite_async | 0.092 | 0.131 | 0.001 | 0.002 |
| drift | 0.093 | 0.122 | 0.001 | 0.002 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 105.579 | 109.131 | 0.000 | 0.000 | 0 |
| sqlite_async | 210.027 | 210.936 | 0.000 | 0.000 | 40 |
| drift | 225.288 | 229.623 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 228.16 | 228.16 | 0.00 | 0.00 | 12.35 | 215.81 | 0 |
| sqlite_async | 466.38 | 466.38 | 0.01 | 0.01 | 12.28 | 454.11 | 1184 |
| drift | 1915.85 | 1915.85 | 0.08 | 0.08 | 14.18 | 1901.67 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 4.88 | 13.81 | 0.00..9.11 | ±4.55 |
| sqlite3 select() | 3.23 | 9.20 | 0.80..8.22 | ±3.71 |
| sqlite_async select() | 1.00 | 1.11 | 0.95..1.00 | ±0.02 |
| drift select() | 6.80 | 73.73 | 0.00..12.59 | ±6.30 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 1.00 | 20.08 | 0.00..14.05 | ±7.02 |
| resqlite + jsonEncode | 0.00 | 49.92 | 0.00..17.53 | ±8.77 |
| sqlite3 + jsonEncode | 0.00 | 63.30 | 0.00..0.00 | ±0.00 |
| sqlite_async + jsonEncode | 0.00 | 35.28 | 0.00..0.00 | ±0.00 |
| drift + jsonEncode | 0.86 | 17.02 | 0.00..8.00 | ±4.00 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 1.05 | 7.97 | 0.00..6.06 | ±3.03 |
| sqlite3 executeBatch() | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.02 | 3.88 | 0.00..3.86 | ±1.93 |
| drift batch() | 0.00 | 2.00 | 0.00..0.00 | ±0.00 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.00 | 0.13 | 0.00..0.06 | ±0.03 |
| sqlite_async watch() | 0.00 | 0.50 | 0.00..0.00 | ±0.00 |

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
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.03 | 0.03..0.03 | 8.6% | 17.2% | 3.4% | moderate |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 15.0% | 30.0% | 10.0% | noisy |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.03 | 0.02..0.03 | 17.3% | 34.6% | 11.5% | noisy |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02..0.02 | 15.8% | 31.6% | 10.5% | noisy |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.32 | 0.30..0.34 | 6.3% | 12.5% | 6.3% | moderate |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.32 | 0.30..0.34 | 6.3% | 12.5% | 6.3% | moderate |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.35 | 0.33..0.40 | 10.0% | 20.0% | 5.7% | moderate |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.17 | 0.17..0.20 | 8.8% | 17.6% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.46 | 0.41..0.65 | 26.1% | 52.2% | 10.9% | noisy |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.11 | 0.10..0.16 | 27.3% | 54.5% | 9.1% | noisy |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.85 | 0.80..1.04 | 14.1% | 28.2% | 2.4% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.11 | 0.10..0.13 | 13.6% | 27.3% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.05 | 6.0% | 11.9% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 150.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 104.93 | 104.76..105.58 | 0.4% | 0.8% | 0.2% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 429.36 | 228.16..434.95 | 24.1% | 48.2% | 1.3% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 213.78 | 213.06..215.90 | 0.7% | 1.3% | 0.3% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 15.47 | 14.90..17.47 | 8.3% | 16.6% | 3.7% | moderate |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 15.47 | 14.90..17.47 | 8.3% | 16.6% | 3.7% | moderate |
| Point Query Throughput / resqlite qps | 124665.00 | 100747.00..126671.00 | 10.4% | 20.8% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.01 | 13.6% | 27.3% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.04 | 11.7% | 23.3% | 6.7% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.04 | 11.7% | 23.3% | 6.7% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.01 | 9.1% | 18.2% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.01 | 9.1% | 18.2% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.04..0.05 | 2.2% | 4.4% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.20 | 0.19..0.22 | 6.2% | 12.4% | 2.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.20 | 0.19..0.22 | 6.2% | 12.4% | 2.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 10.0% | 20.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.05 | 10.5% | 20.9% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.04 | 0.04..0.05 | 10.5% | 20.9% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.35 | 0.35..0.35 | 1.3% | 2.6% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.92 | 1.88..2.03 | 4.1% | 8.2% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.92 | 1.88..2.03 | 4.1% | 8.2% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.05 | 0.05..0.05 | 1.9% | 3.8% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.36 | 0.35..0.38 | 5.0% | 9.9% | 3.6% | moderate |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.36 | 0.35..0.38 | 5.0% | 9.9% | 3.6% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.34 | 4.31..4.49 | 2.0% | 4.1% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 23.49 | 22.15..24.36 | 4.7% | 9.4% | 3.7% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 23.49 | 22.15..24.36 | 4.7% | 9.4% | 3.7% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.55 | 0.54..0.55 | 1.1% | 2.2% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 3.75 | 3.68..4.20 | 6.9% | 13.9% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 3.75 | 3.68..4.20 | 6.9% | 13.9% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.76 | 0.74..0.78 | 3.1% | 6.3% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.92 | 3.90..4.21 | 4.0% | 8.0% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.92 | 3.90..4.21 | 4.0% | 8.0% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.11 | 0.11..0.11 | 0.5% | 0.9% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.77 | 0.69..0.78 | 6.0% | 12.0% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.77 | 0.69..0.78 | 6.0% | 12.0% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.98 | 8.78..11.84 | 14.0% | 27.9% | 4.0% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 46.48 | 45.65..47.77 | 2.3% | 4.6% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 46.48 | 45.65..47.77 | 2.3% | 4.6% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.08 | 1.06..1.10 | 1.5% | 3.1% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 7.92 | 7.61..9.21 | 10.2% | 20.3% | 3.9% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 7.92 | 7.61..9.21 | 10.2% | 20.3% | 3.9% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03..0.03 | 5.8% | 11.5% | 3.8% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10..0.11 | 4.8% | 9.6% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.10 | 0.10..0.11 | 4.8% | 9.6% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.03..0.03 | 6.7% | 13.3% | 6.7% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.03..0.03 | 6.7% | 13.3% | 6.7% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.18 | 0.18..0.19 | 1.1% | 2.2% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.94 | 0.90..0.98 | 4.7% | 9.3% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.94 | 0.90..0.98 | 4.7% | 9.3% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.03 | 0.03..0.03 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.18 | 0.17..0.20 | 8.4% | 16.8% | 3.2% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.18 | 0.17..0.20 | 8.4% | 16.8% | 3.2% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.13 | 2.08..2.20 | 2.6% | 5.3% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 11.08 | 10.20..13.88 | 16.6% | 33.2% | 7.9% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 11.08 | 10.20..13.88 | 16.6% | 33.2% | 7.9% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.27 | 0.27..0.28 | 2.4% | 4.8% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 1.88 | 1.79..1.97 | 4.8% | 9.7% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 1.88 | 1.79..1.97 | 4.8% | 9.7% | 2.0% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.09 | 0.09..0.11 | 9.4% | 18.9% | 0.0% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.02 | 0.01..0.02 | 18.8% | 37.5% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.27 | 0.26..0.27 | 2.2% | 4.5% | 0.4% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.06 | 0.06..0.06 | 2.4% | 4.8% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.26 | 0.26..0.27 | 2.5% | 4.9% | 0.8% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.06 | 0.06..0.06 | 2.5% | 4.9% | 1.6% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.52 | 0.52..0.56 | 4.5% | 9.0% | 1.3% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.06 | 0.06..0.07 | 1.6% | 3.1% | 1.6% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.88 | 0.86..0.90 | 2.3% | 4.6% | 1.8% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.21 | 0.20..0.21 | 1.4% | 2.9% | 1.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.12 | 139.7% | 279.4% | 14.7% | noisy |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.01..0.10 | 227.8% | 455.6% | 11.1% | noisy |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 31.8% | 63.6% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.19..0.22 | 6.5% | 13.1% | 1.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.16 | 0.15..0.17 | 6.7% | 13.4% | 0.6% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.05..0.05 | 4.7% | 9.4% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.86 | 1.81..1.89 | 2.1% | 4.1% | 1.1% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.51 | 1.49..1.55 | 1.8% | 3.6% | 1.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.37 | 0.36..0.39 | 3.0% | 6.0% | 1.1% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 23.88 | 23.00..24.39 | 2.9% | 5.8% | 1.6% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 15.60 | 15.41..17.27 | 6.0% | 11.9% | 1.2% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.76 | 3.72..3.77 | 0.8% | 1.6% | 0.3% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 50.0% | 100.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.08 | 291.7% | 583.3% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.04 | 0.04..0.07 | 24.4% | 48.9% | 2.2% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 30.0% | 60.0% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.35 | 0.34..0.39 | 6.7% | 13.3% | 2.8% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.05 | 0.05..0.06 | 4.7% | 9.4% | 1.9% | stable |
| Select → Maps / 10000 rows / resqlite select() | 4.41 | 4.36..4.47 | 1.3% | 2.5% | 1.1% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.54 | 0.54..0.54 | 0.7% | 1.3% | 0.2% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.24 | 0.20..0.25 | 10.1% | 20.3% | 5.1% | moderate |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.24 | 0.20..0.25 | 10.1% | 20.3% | 5.1% | moderate |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.61 | 0.60..0.68 | 6.4% | 12.7% | 2.0% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.61 | 0.60..0.68 | 6.4% | 12.7% | 2.0% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03..0.07 | 70.3% | 140.6% | 6.3% | moderate |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03..0.07 | 70.3% | 140.6% | 6.3% | moderate |
| Streaming / Invalidation Latency / resqlite | 0.06 | 0.05..0.08 | 28.1% | 56.1% | 17.5% | noisy |
| Streaming / Invalidation Latency / resqlite [main] | 0.06 | 0.05..0.08 | 28.1% | 56.1% | 17.5% | noisy |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows x 32K... | 3.58 | 3.24..3.76 | 7.3% | 14.5% | 4.9% | moderate |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows x 32K... | 3.58 | 3.24..3.76 | 7.3% | 14.5% | 4.9% | moderate |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged streams, 6... | 3.53 | 3.34..3.65 | 4.5% | 9.0% | 2.0% | stable |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged streams, 6... | 3.53 | 3.34..3.65 | 4.5% | 9.0% | 2.0% | stable |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 2.63 | 2.57..2.85 | 5.3% | 10.6% | 2.4% | stable |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 2.63 | 2.57..2.85 | 5.3% | 10.6% | 2.4% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.58 | 3.44..4.02 | 8.0% | 16.1% | 3.9% | moderate |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.58 | 3.44..4.02 | 8.0% | 16.1% | 3.9% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.87 | 1.50..3.02 | 40.8% | 81.6% | 4.0% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.87 | 1.50..3.02 | 40.8% | 81.6% | 4.0% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 7.28 | 7.12..9.87 | 18.9% | 37.8% | 2.2% | stable |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 7.28 | 7.12..9.87 | 18.9% | 37.8% | 2.2% | stable |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.22 | 0.20..0.26 | 14.4% | 28.8% | 8.2% | noisy |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.22 | 0.20..0.26 | 14.4% | 28.8% | 8.2% | noisy |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.05..0.06 | 6.9% | 13.8% | 5.2% | moderate |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.06 | 0.05..0.06 | 6.9% | 13.8% | 5.2% | moderate |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.41 | 0.40..0.43 | 4.2% | 8.4% | 0.5% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.41 | 0.40..0.43 | 4.2% | 8.4% | 0.5% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.20 | 4.05..4.51 | 5.4% | 10.9% | 3.4% | moderate |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.20 | 4.05..4.51 | 5.4% | 10.9% | 3.4% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.52 | 0.50..0.66 | 15.8% | 31.5% | 4.2% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.52 | 0.50..0.66 | 15.8% | 31.5% | 4.2% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.06..0.08 | 14.2% | 28.4% | 4.5% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.06..0.08 | 14.2% | 28.4% | 4.5% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.70 | 5.05..6.57 | 13.4% | 26.8% | 6.8% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.70 | 5.05..6.57 | 13.4% | 26.8% | 6.8% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.43 | 0.41..0.48 | 7.9% | 15.9% | 2.6% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.43 | 0.41..0.48 | 7.9% | 15.9% | 2.6% | stable |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 1.21 | 1.07..1.45 | 15.5% | 31.1% | 7.5% | moderate |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 1.21 | 1.07..1.45 | 15.5% | 31.1% | 7.5% | moderate |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05..0.08 | 28.4% | 56.9% | 7.8% | moderate |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05..0.08 | 28.4% | 56.9% | 7.8% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.09 | 0.08..0.11 | 14.4% | 28.9% | 8.9% | noisy |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.09 | 0.08..0.11 | 14.4% | 28.9% | 8.9% | noisy |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.95 | 0.90..1.10 | 10.7% | 21.5% | 5.2% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.95 | 0.90..1.10 | 10.7% | 21.5% | 5.2% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.73 | 1.60..2.90 | 37.6% | 75.1% | 6.7% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.73 | 1.60..2.90 | 37.6% | 75.1% | 6.7% | moderate |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.19..0.20 | 3.9% | 7.7% | 1.5% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.19..0.20 | 3.9% | 7.7% | 1.5% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.11 | 0.11..0.12 | 5.5% | 10.9% | 2.7% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.11 | 0.11..0.12 | 5.5% | 10.9% | 2.7% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 14.03 | 13.87..14.66 | 2.8% | 5.7% | 0.9% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 14.03 | 13.87..14.66 | 2.8% | 5.7% | 0.9% | stable |


## Comparison

Automatic comparison is disabled. Use `--compare-to=...` for an explicit baseline comparison.

