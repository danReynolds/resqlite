# resqlite Benchmark Results

Generated: 2026-04-28T13:24:34.394017

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp111-savepoint-cache`
- Repeats: `5`
- Runtime: `dart-vm / Dart 3.11.0`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `danreynolds/trusting-leavitt-c4d4b6 @ 7ed23be9f314 (dirty)`
- Comparison baseline: `2026-04-28T13-13-50-baseline-for-exp111.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.012 | 0.015 | 0.001 | 0.001 |
| sqlite3 select() | 0.015 | 0.016 | 0.015 | 0.016 |
| sqlite_async select() | 0.031 | 0.034 | 0.001 | 0.002 |
| drift select() | 0.036 | 0.039 | 0.001 | 0.001 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.047 | 0.050 | 0.009 | 0.010 |
| sqlite3 select() | 0.115 | 0.121 | 0.115 | 0.121 |
| sqlite_async select() | 0.124 | 0.127 | 0.010 | 0.010 |
| drift select() | 0.181 | 0.197 | 0.010 | 0.010 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.372 | 0.413 | 0.084 | 0.091 |
| sqlite3 select() | 1.053 | 1.158 | 1.053 | 1.158 |
| sqlite_async select() | 1.014 | 1.068 | 0.093 | 0.098 |
| drift select() | 1.529 | 2.159 | 0.092 | 0.094 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.358 | 10.120 | 0.865 | 1.870 |
| sqlite3 select() | 12.598 | 14.015 | 12.598 | 14.015 |
| sqlite_async select() | 12.040 | 14.490 | 0.929 | 1.507 |
| drift select() | 21.225 | 29.968 | 0.979 | 2.417 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.029 | 0.032 | 0.017 | 0.018 |
| sqlite3 + jsonEncode | 0.031 | 0.035 | 0.031 | 0.035 |
| sqlite_async + jsonEncode | 0.047 | 0.052 | 0.016 | 0.020 |
| drift + jsonEncode | 0.053 | 0.059 | 0.016 | 0.017 |
| resqlite selectBytes() | 0.011 | 0.012 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.202 | 0.212 | 0.161 | 0.170 |
| sqlite3 + jsonEncode | 0.321 | 0.512 | 0.321 | 0.512 |
| sqlite_async + jsonEncode | 0.270 | 0.307 | 0.151 | 0.169 |
| drift + jsonEncode | 0.339 | 0.406 | 0.159 | 0.170 |
| resqlite selectBytes() | 0.045 | 0.047 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.843 | 4.037 | 1.519 | 3.570 |
| sqlite3 + jsonEncode | 2.535 | 4.008 | 2.535 | 4.008 |
| sqlite_async + jsonEncode | 2.491 | 4.993 | 1.518 | 2.663 |
| drift + jsonEncode | 3.009 | 4.928 | 1.484 | 1.786 |
| resqlite selectBytes() | 0.363 | 0.403 | 0.000 | 0.000 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 21.092 | 25.166 | 15.121 | 17.233 |
| sqlite3 + jsonEncode | 30.638 | 36.070 | 30.638 | 36.070 |
| sqlite_async + jsonEncode | 30.796 | 33.289 | 15.187 | 16.535 |
| drift + jsonEncode | 37.251 | 42.034 | 15.071 | 18.056 |
| resqlite selectBytes() | 3.652 | 6.339 | 0.001 | 0.009 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.106 | 0.110 | 0.040 | 0.042 |
| sqlite3 | 0.321 | 0.333 | 0.321 | 0.333 |
| sqlite_async | 0.364 | 0.390 | 0.045 | 0.048 |
| drift | 0.576 | 0.603 | 0.045 | 0.047 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.994 | 1.025 | 0.355 | 0.363 |
| sqlite3 | 3.169 | 3.742 | 3.169 | 3.742 |
| sqlite_async | 2.864 | 3.306 | 0.375 | 0.381 |
| drift | 4.692 | 6.862 | 0.378 | 0.400 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.556 | 0.573 | 0.128 | 0.130 |
| sqlite3 | 1.404 | 1.481 | 1.404 | 1.481 |
| sqlite_async | 1.346 | 1.709 | 0.133 | 0.136 |
| drift | 1.911 | 2.339 | 0.132 | 0.134 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.331 | 0.338 | 0.136 | 0.140 |
| sqlite3 | 0.985 | 1.008 | 0.985 | 1.008 |
| sqlite_async | 0.951 | 0.978 | 0.148 | 0.159 |
| drift | 1.507 | 1.573 | 0.147 | 0.152 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.329 | 0.333 | 0.125 | 0.126 |
| sqlite3 | 0.965 | 1.014 | 0.965 | 1.014 |
| sqlite_async | 0.953 | 1.029 | 0.135 | 0.138 |
| drift | 1.460 | 1.772 | 0.129 | 0.134 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.011 | 0.013 | 0.001 | 0.001 |
| sqlite3 | 0.016 | 0.016 | 0.016 | 0.016 |
| sqlite_async | 0.031 | 0.032 | 0.001 | 0.002 |
| drift | 0.036 | 0.038 | 0.001 | 0.001 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.028 | 0.030 | 0.005 | 0.005 |
| sqlite3 | 0.061 | 0.063 | 0.061 | 0.063 |
| sqlite_async | 0.074 | 0.080 | 0.006 | 0.006 |
| drift | 0.102 | 0.105 | 0.006 | 0.006 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.048 | 0.051 | 0.010 | 0.010 |
| sqlite3 | 0.114 | 0.123 | 0.114 | 0.123 |
| sqlite_async | 0.123 | 0.128 | 0.012 | 0.012 |
| drift | 0.181 | 0.186 | 0.012 | 0.012 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.201 | 0.207 | 0.050 | 0.052 |
| sqlite3 | 0.534 | 0.548 | 0.534 | 0.548 |
| sqlite_async | 0.514 | 0.529 | 0.055 | 0.056 |
| drift | 0.805 | 0.846 | 0.056 | 0.060 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.400 | 0.408 | 0.103 | 0.104 |
| sqlite3 | 1.065 | 1.167 | 1.065 | 1.167 |
| sqlite_async | 1.027 | 1.081 | 0.110 | 0.117 |
| drift | 1.544 | 1.666 | 0.108 | 0.112 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.810 | 0.829 | 0.206 | 0.215 |
| sqlite3 | 2.125 | 2.727 | 2.125 | 2.727 |
| sqlite_async | 2.023 | 2.365 | 0.220 | 0.229 |
| drift | 3.082 | 3.590 | 0.215 | 0.223 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.247 | 6.289 | 0.514 | 0.679 |
| sqlite3 | 5.353 | 7.411 | 5.353 | 7.411 |
| sqlite_async | 5.170 | 5.837 | 0.554 | 0.572 |
| drift | 8.375 | 8.886 | 0.555 | 0.574 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.537 | 10.018 | 1.006 | 1.384 |
| sqlite3 | 13.281 | 14.964 | 13.281 | 14.964 |
| sqlite_async | 10.970 | 11.737 | 1.104 | 1.115 |
| drift | 18.382 | 26.448 | 1.106 | 2.626 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 11.196 | 16.259 | 2.000 | 2.690 |
| sqlite3 | 31.503 | 35.343 | 31.503 | 35.343 |
| sqlite_async | 32.735 | 38.001 | 2.228 | 2.371 |
| drift | 46.808 | 54.129 | 2.179 | 2.286 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.027 | 0.035 | 0.027 | 0.035 |
| sqlite3 + jsonEncode | 0.030 | 0.032 | 0.030 | 0.032 |
| sqlite_async + jsonEncode | 0.047 | 0.049 | 0.047 | 0.049 |
| drift + jsonEncode | 0.055 | 0.069 | 0.055 | 0.069 |
| resqlite selectBytes() | 0.011 | 0.012 | 0.011 | 0.012 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.103 | 0.109 | 0.103 | 0.109 |
| sqlite3 + jsonEncode | 0.135 | 0.138 | 0.135 | 0.138 |
| sqlite_async + jsonEncode | 0.148 | 0.150 | 0.148 | 0.150 |
| drift + jsonEncode | 0.175 | 0.199 | 0.175 | 0.199 |
| resqlite selectBytes() | 0.026 | 0.027 | 0.026 | 0.027 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.196 | 0.204 | 0.196 | 0.204 |
| sqlite3 + jsonEncode | 0.254 | 0.263 | 0.254 | 0.263 |
| sqlite_async + jsonEncode | 0.262 | 0.288 | 0.262 | 0.288 |
| drift + jsonEncode | 0.318 | 0.334 | 0.318 | 0.334 |
| resqlite selectBytes() | 0.044 | 0.047 | 0.044 | 0.047 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.888 | 0.928 | 0.888 | 0.928 |
| sqlite3 + jsonEncode | 1.219 | 1.246 | 1.219 | 1.246 |
| sqlite_async + jsonEncode | 1.190 | 1.216 | 1.190 | 1.216 |
| drift + jsonEncode | 1.456 | 1.471 | 1.456 | 1.471 |
| resqlite selectBytes() | 0.180 | 0.184 | 0.180 | 0.184 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.734 | 1.892 | 1.734 | 1.892 |
| sqlite3 + jsonEncode | 2.585 | 4.855 | 2.585 | 4.855 |
| sqlite_async + jsonEncode | 2.510 | 4.984 | 2.510 | 4.984 |
| drift + jsonEncode | 2.910 | 4.559 | 2.910 | 4.559 |
| resqlite selectBytes() | 0.353 | 0.358 | 0.353 | 0.358 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.658 | 6.779 | 3.658 | 6.779 |
| sqlite3 + jsonEncode | 5.192 | 8.522 | 5.192 | 8.522 |
| sqlite_async + jsonEncode | 5.155 | 7.930 | 5.155 | 7.930 |
| drift + jsonEncode | 6.032 | 9.239 | 6.032 | 9.239 |
| resqlite selectBytes() | 0.747 | 0.965 | 0.747 | 0.965 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 9.822 | 12.914 | 9.822 | 12.914 |
| sqlite3 + jsonEncode | 13.011 | 18.019 | 13.011 | 18.019 |
| sqlite_async + jsonEncode | 13.552 | 17.233 | 13.552 | 17.233 |
| drift + jsonEncode | 16.850 | 20.952 | 16.850 | 20.952 |
| resqlite selectBytes() | 1.849 | 3.280 | 1.849 | 3.280 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.314 | 23.632 | 20.314 | 23.632 |
| sqlite3 + jsonEncode | 28.008 | 32.560 | 28.008 | 32.560 |
| sqlite_async + jsonEncode | 30.026 | 32.012 | 30.026 | 32.012 |
| drift + jsonEncode | 36.477 | 39.302 | 36.477 | 39.302 |
| resqlite selectBytes() | 3.592 | 4.142 | 3.592 | 4.142 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 42.119 | 46.812 | 42.119 | 46.812 |
| sqlite3 + jsonEncode | 60.651 | 64.257 | 60.651 | 64.257 |
| sqlite_async + jsonEncode | 64.425 | 70.241 | 64.425 | 70.241 |
| drift + jsonEncode | 77.679 | 91.085 | 77.679 | 91.085 |
| resqlite selectBytes() | 8.126 | 9.146 | 8.126 | 9.146 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.31 | 0.30 |
| sqlite_async | 0.89 | 0.91 | 0.89 |
| drift | 1.43 | 1.77 | 1.43 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.32 | 0.15 |
| sqlite_async | 1.30 | 1.62 | 0.65 |
| drift | 2.60 | 2.97 | 1.30 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.37 | 0.39 | 0.09 |
| sqlite_async | 2.16 | 2.75 | 0.54 |
| drift | 4.98 | 5.47 | 1.25 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.67 | 1.16 | 0.08 |
| sqlite_async | 4.40 | 4.84 | 0.55 |
| drift | 10.12 | 10.59 | 1.27 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 149854 |
| resqlite per query | 0.007 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 149854 | 149406..151588 | 0.7 | 3.5 |
| sqlite3 | 202792 | 199997..203236 | 0.8 | 2.1 |
| sqlite_async | 51511 | 50874..51712 | 0.8 | 2.8 |
| drift | 47550 | 47179..47895 | 0.8 | 2.3 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.064 | 14.854 | 14.064 | 14.854 |
| sqlite_async | 35.412 | 36.836 | 35.412 | 36.836 |
| drift | 51.482 | 52.636 | 51.482 | 52.636 |
| sqlite3 (no cache) | 22.718 | 23.536 | 22.718 | 23.536 |
| sqlite3 (cached stmt) | 22.345 | 22.709 | 22.345 | 22.709 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.547 | 2.306 | 1.547 | 2.306 |
| sqlite3 execute() | 0.894 | 1.505 | 0.894 | 1.505 |
| sqlite_async execute() | 2.606 | 3.308 | 2.606 | 3.308 |
| drift execute() | 2.657 | 3.213 | 2.657 | 3.213 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.050 | 0.054 | 0.050 | 0.054 |
| sqlite3 executeBatch() | 0.048 | 0.051 | 0.048 | 0.051 |
| sqlite_async executeBatch() | 0.093 | 0.098 | 0.093 | 0.098 |
| drift executeBatch() | 0.110 | 0.118 | 0.110 | 0.118 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.387 | 0.400 | 0.387 | 0.400 |
| sqlite3 executeBatch() | 0.437 | 0.449 | 0.437 | 0.449 |
| sqlite_async executeBatch() | 0.516 | 0.544 | 0.516 | 0.544 |
| drift executeBatch() | 0.665 | 0.740 | 0.665 | 0.740 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 3.642 | 5.361 | 3.642 | 5.361 |
| sqlite3 executeBatch() | 4.001 | 4.336 | 4.001 | 4.336 |
| sqlite_async executeBatch() | 4.681 | 5.428 | 4.681 | 5.428 |
| drift executeBatch() | 6.011 | 6.726 | 6.011 | 6.726 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.049 | 0.051 | 0.049 | 0.051 |
| sqlite_async writeTransaction() | 0.080 | 0.090 | 0.080 | 0.090 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.064 | 0.068 | 0.064 | 0.068 |
| resqlite tx.execute() loop | 0.516 | 0.767 | 0.516 | 0.767 |
| sqlite_async tx.execute() loop | 0.967 | 1.051 | 0.967 | 1.051 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.388 | 0.452 | 0.388 | 0.452 |
| resqlite tx.execute() loop | 5.012 | 6.053 | 5.012 | 6.053 |
| sqlite_async tx.execute() loop | 9.576 | 11.343 | 9.576 | 11.343 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.104 | 0.112 | 0.104 | 0.112 |
| sqlite_async tx.getAll() | 0.201 | 0.217 | 0.201 | 0.217 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.183 | 0.194 | 0.183 | 0.194 |
| sqlite_async tx.getAll() | 0.354 | 0.386 | 0.354 | 0.386 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 0.768 | 0.976 | 0.768 | 0.976 |
| resqlite nested transaction() depth=5 | 0.074 | 0.088 | 0.074 | 0.088 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.027 | 0.030 | 0.027 | 0.030 |
| sqlite_async watch() | 0.139 | 0.193 | 0.139 | 0.193 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.070 | 0.160 | 0.070 | 0.160 |
| sqlite_async | 0.115 | 0.349 | 0.115 | 0.349 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.241 | 0.428 | 0.241 | 0.428 |
| sqlite_async | 0.556 | 2.318 | 0.556 | 2.318 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.750 | 4.176 | 1.750 | 4.176 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.165 | 0.325 | 0.165 | 0.325 |
| sqlite_async | 0.237 | 0.308 | 0.237 | 0.308 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.641 | 1.641 | 1.641 | 1.641 |
| sqlite_async | 9.335 | 9.335 | 9.335 | 9.335 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.402 | 4.401 | 3.402 | 4.401 |
| sqlite_async | 5.656 | 7.286 | 5.656 | 7.286 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.519 | 0.691 | 0.519 | 0.691 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 5.361 | 5.976 | 5.361 | 5.976 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. On resqlite's main branch this ratio is driven toward 0 by experiment 075 (C-side result-hash short-circuit), not by writer-side column-tracking (exp 052 is not implemented). The two mechanisms are indistinguishable on this read-side benchmark.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 69.2 | 0.000 |
| sqlite_async | 3992 | 974.6 | 1.001 |
| drift | 5000 | 993.0 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 71.3 | 0.000 |
| sqlite_async | 3990 | 976.2 | 1.001 |
| drift | 5000 | 996.5 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 224.86 | 227.00 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 443.28 | 444.90 | 0.00 | 0.00 | 1107 | 3 |
| drift stream() | 548.85 | 557.50 | 0.00 | 0.01 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.019 | 0.029 | 0.000 | 0.000 |
| sqlite3 | 0.018 | 0.022 | 0.018 | 0.022 |
| sqlite_async | 0.036 | 0.044 | 0.000 | 0.000 |
| drift | 0.036 | 0.046 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.014 | 0.021 | 0.000 | 0.000 |
| sqlite3 | 0.011 | 0.014 | 0.011 | 0.014 |
| sqlite_async | 0.029 | 0.033 | 0.000 | 0.000 |
| drift | 0.028 | 0.034 | 0.000 | 0.000 |

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
| resqlite | 0.038 | 0.041 | 0.001 | 0.001 |
| sqlite3 | 0.061 | 0.063 | 0.061 | 0.063 |
| sqlite_async | 0.076 | 0.079 | 0.001 | 0.001 |
| drift | 0.089 | 0.096 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 109.670 | 109.923 | 0.000 | 0.000 | 0 |
| sqlite_async | 213.650 | 221.813 | 0.000 | 0.000 | 39 |
| drift | 227.634 | 232.908 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 235.62 | 235.62 | 0.00 | 0.00 | 13.77 | 221.84 | 0 |
| sqlite_async | 489.08 | 489.08 | 0.00 | 0.00 | 22.92 | 466.21 | 1208 |
| drift | 1698.85 | 1698.85 | 0.10 | 0.10 | 15.09 | 1683.76 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 1.14 | 9.98 | 0.00..5.45 | ±2.73 |
| sqlite3 select() | 5.55 | 9.55 | 0.00..8.03 | ±4.02 |
| sqlite_async select() | 1.00 | 1.00 | 1.00..1.00 | ±0.00 |
| drift select() | 5.16 | 74.16 | 0.00..10.39 | ±5.20 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.02 | 10.00 | 0.00..6.02 | ±3.01 |
| resqlite + jsonEncode | 2.53 | 57.27 | 0.00..9.22 | ±4.61 |
| sqlite3 + jsonEncode | 0.00 | 36.92 | 0.00..13.20 | ±6.60 |
| sqlite_async + jsonEncode | 0.00 | 10.16 | 0.00..7.52 | ±3.76 |
| drift + jsonEncode | 1.67 | 87.28 | 0.00..18.00 | ±9.00 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.00 | 1.61 | 0.00..0.19 | ±0.09 |
| sqlite3 executeBatch() | 0.00 | 0.09 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| drift batch() | 0.52 | 4.53 | 0.02..2.53 | ±1.26 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.00 | 0.06 | 0.00..0.06 | ±0.03 |
| sqlite_async watch() | 0.00 | 0.52 | 0.00..0.00 | ±0.00 |

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
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.03 | 0.02..0.03 | 2.0% | 4.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 6.2% | 12.5% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02..0.02 | 6.8% | 13.6% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.01..0.02 | 9.4% | 18.8% | 6.3% | moderate |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.29 | 0.29..0.33 | 6.9% | 13.8% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.29 | 0.29..0.33 | 6.9% | 13.8% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.30 | 0.30..0.31 | 1.7% | 3.3% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.15 | 0.15..0.15 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.37 | 0.36..0.37 | 1.4% | 2.7% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.09 | 0.09..0.09 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.68 | 0.67..0.70 | 2.2% | 4.4% | 1.5% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.09 | 0.08..0.09 | 5.6% | 11.1% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.04 | 1.3% | 2.6% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 150.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 110.25 | 109.49..110.68 | 0.5% | 1.1% | 0.4% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 243.09 | 235.62..243.75 | 1.7% | 3.3% | 0.3% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 226.22 | 224.86..229.00 | 0.9% | 1.8% | 0.3% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 14.25 | 13.99..14.63 | 2.2% | 4.5% | 1.3% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 14.25 | 13.99..14.63 | 2.2% | 4.5% | 1.3% | stable |
| Point Query Throughput / resqlite qps | 147007.00 | 135225.00..149854.00 | 5.0% | 10.0% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.02 | 33.3% | 66.7% | 8.3% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.04 | 19.6% | 39.3% | 3.6% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.04 | 19.6% | 39.3% | 3.6% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 50.0% | 100.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 27.3% | 54.5% | 9.1% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.02 | 27.3% | 54.5% | 9.1% | noisy |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05..0.05 | 4.1% | 8.2% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.20 | 0.19..0.20 | 2.6% | 5.1% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.20 | 0.19..0.20 | 2.6% | 5.1% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 5.0% | 10.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.05 | 6.7% | 13.3% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.04 | 0.04..0.05 | 6.7% | 13.3% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.39 | 0.39..0.40 | 1.7% | 3.3% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.80 | 1.73..1.87 | 3.8% | 7.6% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.80 | 1.73..1.87 | 3.8% | 7.6% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.10 | 0.09..0.10 | 7.4% | 14.9% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.36 | 0.35..0.37 | 2.2% | 4.4% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.36 | 0.35..0.37 | 2.2% | 4.4% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.63 | 4.54..5.02 | 5.2% | 10.5% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 20.38 | 19.51..23.74 | 10.4% | 20.8% | 4.3% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 20.38 | 19.51..23.74 | 10.4% | 20.8% | 4.3% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 1.01 | 0.87..1.02 | 7.5% | 15.0% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 3.73 | 3.56..3.76 | 2.6% | 5.2% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 3.73 | 3.56..3.76 | 2.6% | 5.2% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.82 | 0.80..0.86 | 3.8% | 7.5% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.81 | 3.66..3.88 | 2.9% | 5.9% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.81 | 3.66..3.88 | 2.9% | 5.9% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.21 | 0.18..0.21 | 7.8% | 15.5% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.76 | 0.75..0.77 | 1.7% | 3.4% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.76 | 0.75..0.77 | 1.7% | 3.4% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.97 | 10.85..11.89 | 4.8% | 9.5% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 43.05 | 42.12..43.83 | 2.0% | 4.0% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 43.05 | 42.12..43.83 | 2.0% | 4.0% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 2.00 | 1.74..2.08 | 8.7% | 17.4% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 7.94 | 7.42..8.13 | 4.5% | 8.9% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 7.94 | 7.42..8.13 | 4.5% | 8.9% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03..0.03 | 6.9% | 13.8% | 3.4% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10..0.11 | 3.8% | 7.7% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.10 | 0.10..0.11 | 3.8% | 7.7% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.03..0.03 | 11.5% | 23.1% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.03..0.03 | 11.5% | 23.1% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.20 | 0.20..0.21 | 2.0% | 4.0% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.94 | 0.89..0.96 | 4.0% | 8.0% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.94 | 0.89..0.96 | 4.0% | 8.0% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.05 | 0.04..0.05 | 8.0% | 16.0% | 4.0% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.18 | 0.18..0.19 | 1.6% | 3.3% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.18 | 0.18..0.19 | 1.6% | 3.3% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.20 | 2.13..2.39 | 5.9% | 11.8% | 3.0% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 10.32 | 9.64..11.54 | 9.2% | 18.4% | 6.5% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 10.32 | 9.64..11.54 | 9.2% | 18.4% | 6.5% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.51 | 0.42..0.53 | 10.7% | 21.4% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 1.91 | 1.85..2.69 | 22.0% | 44.0% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 1.91 | 1.85..2.69 | 22.0% | 44.0% | 1.4% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.11 | 0.10..0.11 | 8.5% | 17.0% | 1.9% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.04 | 0.03..0.04 | 22.5% | 45.0% | 5.0% | moderate |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.33 | 0.31..0.33 | 3.2% | 6.4% | 0.9% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.12 | 0.10..0.13 | 10.1% | 20.2% | 0.8% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.34 | 0.30..0.34 | 6.1% | 12.2% | 1.5% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.14 | 0.10..0.14 | 15.2% | 30.4% | 1.4% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.56 | 0.55..0.58 | 2.5% | 5.0% | 0.7% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.13 | 0.10..0.13 | 10.3% | 20.6% | 1.6% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.99 | 0.91..1.05 | 6.8% | 13.6% | 4.3% | moderate |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.35 | 0.27..0.37 | 13.8% | 27.6% | 1.4% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.06 | 56.9% | 113.8% | 6.9% | moderate |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02..0.04 | 61.8% | 123.5% | 5.9% | moderate |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 45.5% | 90.9% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.19..0.23 | 9.7% | 19.4% | 3.1% | moderate |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.16 | 0.15..0.18 | 10.2% | 20.4% | 2.5% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.05 | 11.1% | 22.2% | 2.2% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.79 | 1.73..1.84 | 3.2% | 6.3% | 0.3% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.48 | 1.44..1.52 | 2.7% | 5.3% | 0.5% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.36 | 0.35..0.36 | 1.7% | 3.3% | 0.8% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 22.59 | 20.12..22.88 | 6.1% | 12.2% | 1.3% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 15.11 | 14.63..15.35 | 2.4% | 4.8% | 0.2% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.80 | 3.64..3.85 | 2.7% | 5.3% | 1.2% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 25.0% | 50.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.08 | 295.8% | 591.7% | 8.3% | noisy |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 1000.0% | 2000.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.05..0.07 | 21.3% | 42.6% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.39 | 0.37..0.42 | 6.8% | 13.7% | 2.8% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.07..0.09 | 9.2% | 18.4% | 3.4% | moderate |
| Select → Maps / 10000 rows / resqlite select() | 4.44 | 4.31..4.71 | 4.5% | 8.9% | 2.9% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.86 | 0.70..0.92 | 12.7% | 25.4% | 3.1% | moderate |
| Streaming / Fan-out (10 streams) / resqlite | 0.17 | 0.16..0.18 | 5.9% | 11.8% | 3.6% | moderate |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.17 | 0.16..0.18 | 5.9% | 11.8% | 3.6% | moderate |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.52 | 0.51..0.55 | 4.4% | 8.9% | 2.1% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.52 | 0.51..0.55 | 4.4% | 8.9% | 2.1% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03..0.05 | 51.9% | 103.7% | 0.0% | stable |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03..0.05 | 51.9% | 103.7% | 0.0% | stable |
| Streaming / Invalidation Latency / resqlite | 0.06 | 0.04..0.07 | 22.0% | 44.1% | 11.9% | noisy |
| Streaming / Invalidation Latency / resqlite [main] | 0.06 | 0.04..0.07 | 22.0% | 44.1% | 11.9% | noisy |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 2.21 | 1.75..2.38 | 14.2% | 28.5% | 7.6% | moderate |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 2.21 | 1.75..2.38 | 14.2% | 28.5% | 7.6% | moderate |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.47 | 3.20..3.87 | 9.6% | 19.2% | 6.3% | moderate |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.47 | 3.20..3.87 | 9.6% | 19.2% | 6.3% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.64 | 1.59..2.35 | 23.1% | 46.2% | 3.0% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.64 | 1.59..2.35 | 23.1% | 46.2% | 3.0% | stable |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 5.48 | 5.36..6.40 | 9.5% | 18.9% | 2.1% | stable |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 5.48 | 5.36..6.40 | 9.5% | 18.9% | 2.1% | stable |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.21 | 0.17..0.24 | 16.3% | 32.5% | 7.8% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.21 | 0.17..0.24 | 16.3% | 32.5% | 7.8% | moderate |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.05 | 0.05..0.05 | 3.8% | 7.7% | 1.9% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.05 | 0.05..0.05 | 3.8% | 7.7% | 1.9% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.39 | 0.39..0.40 | 2.2% | 4.4% | 0.8% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.39 | 0.39..0.40 | 2.2% | 4.4% | 0.8% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.88 | 3.64..4.12 | 6.1% | 12.2% | 4.4% | moderate |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.88 | 3.64..4.12 | 6.1% | 12.2% | 4.4% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.52 | 0.50..0.72 | 21.2% | 42.3% | 1.7% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.52 | 0.50..0.72 | 21.2% | 42.3% | 1.7% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.06 | 0.06..0.07 | 6.3% | 12.5% | 3.1% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.06 | 0.06..0.07 | 6.3% | 12.5% | 3.1% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.05 | 4.99..5.39 | 4.0% | 7.9% | 1.3% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.05 | 4.99..5.39 | 4.0% | 7.9% | 1.3% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.39 | 0.38..0.41 | 4.1% | 8.2% | 2.3% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.39 | 0.38..0.41 | 4.1% | 8.2% | 2.3% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05..0.05 | 4.7% | 9.4% | 1.9% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05..0.05 | 4.7% | 9.4% | 1.9% | stable |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.08 | 0.07..0.09 | 9.5% | 19.0% | 6.3% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.08 | 0.07..0.09 | 9.5% | 19.0% | 6.3% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.79 | 0.75..1.01 | 16.9% | 33.9% | 4.8% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.79 | 0.75..1.01 | 16.9% | 33.9% | 4.8% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.66 | 1.55..1.77 | 6.8% | 13.5% | 1.9% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.66 | 1.55..1.77 | 6.8% | 13.5% | 1.9% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.18..0.19 | 2.2% | 4.4% | 1.1% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.18..0.19 | 2.2% | 4.4% | 1.1% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.10 | 0.10..0.11 | 1.4% | 2.9% | 0.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.10 | 0.10..0.11 | 1.4% | 2.9% | 0.0% | stable |


## Comparison vs Previous Run

Previous: `2026-04-28T13-13-50-baseline-for-exp111.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.03 | 0.03 | -0.00 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | 6.2% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.03 | 0.02 | -0.00 | ±10% / ±0.02 ms | 6.8% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02 | -0.00 | ±19% / ±0.02 ms | 9.4% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.29 | -0.01 | ±10% / ±0.03 ms | 6.9% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.29 | -0.01 | ±10% / ±0.03 ms | 6.9% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.35 | 0.30 | -0.05 | ±10% / ±0.03 ms | 1.7% | stable | 🟢 Win (-14%) |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.18 | 0.15 | -0.03 | ±10% / ±0.02 ms | 0.0% | stable | 🟢 Win (-17%) |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.38 | 0.37 | -0.01 | ±10% / ±0.04 ms | 1.4% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.75 | 0.68 | -0.07 | ±10% / ±0.08 ms | 2.2% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 5.6% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 1.3% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±150% / ±0.02 ms | 150.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 108.89 | 110.25 | +1.35 | ±10% / ±11.02 ms | 0.5% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 242.04 | 243.09 | +1.05 | ±10% / ±24.31 ms | 1.7% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 226.63 | 226.22 | -0.41 | ±10% / ±22.66 ms | 0.9% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.55 | 14.25 | -0.31 | ±10% / ±1.46 ms | 2.2% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.55 | 14.25 | -0.31 | ±10% / ±1.46 ms | 2.2% | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 134113.00 | 147007.00 | +12894.00 | ±10% / ±14700.70 ms | 5.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01 | -0.00 | ±33% / ±0.02 ms | 33.3% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | -0.00 | ±20% / ±0.02 ms | 19.6% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.03 | -0.00 | ±20% / ±0.02 ms | 19.6% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±50% / ±0.02 ms | 50.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | -0.00 | ±27% / ±0.02 ms | 27.3% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | -0.00 | ±27% / ±0.02 ms | 27.3% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05 | -0.00 | ±10% / ±0.02 ms | 4.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.20 | 0.20 | +0.00 | ±10% / ±0.02 ms | 2.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.20 | 0.20 | +0.00 | ±10% / ±0.02 ms | 2.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 5.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 6.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 6.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.40 | 0.39 | -0.01 | ±10% / ±0.04 ms | 1.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.85 | 1.80 | -0.05 | ±10% / ±0.19 ms | 3.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.85 | 1.80 | -0.05 | ±10% / ±0.19 ms | 3.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 7.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.36 | 0.36 | +0.00 | ±10% / ±0.04 ms | 2.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.36 | 0.36 | +0.00 | ±10% / ±0.04 ms | 2.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.62 | 4.63 | +0.01 | ±10% / ±0.46 ms | 5.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 23.07 | 20.38 | -2.69 | ±13% / ±2.95 ms | 10.4% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 23.07 | 20.38 | -2.69 | ±13% / ±2.95 ms | 10.4% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 1.01 | 1.01 | +0.00 | ±10% / ±0.10 ms | 7.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.87 | 3.73 | -0.14 | ±10% / ±0.39 ms | 2.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.87 | 3.73 | -0.14 | ±10% / ±0.39 ms | 2.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.85 | 0.82 | -0.02 | ±10% / ±0.08 ms | 3.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.79 | 3.81 | +0.03 | ±10% / ±0.38 ms | 2.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.79 | 3.81 | +0.03 | ±10% / ±0.38 ms | 2.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.21 | 0.21 | -0.00 | ±10% / ±0.02 ms | 7.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.77 | 0.76 | -0.00 | ±10% / ±0.08 ms | 1.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.77 | 0.76 | -0.00 | ±10% / ±0.08 ms | 1.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 11.71 | 10.97 | -0.74 | ±10% / ±1.17 ms | 4.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 45.32 | 43.05 | -2.27 | ±10% / ±4.53 ms | 2.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 45.32 | 43.05 | -2.27 | ±10% / ±4.53 ms | 2.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 2.03 | 2.00 | -0.03 | ±10% / ±0.20 ms | 8.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.57 | 7.94 | -0.63 | ±10% / ±0.86 ms | 4.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.57 | 7.94 | -0.63 | ±10% / ±0.86 ms | 4.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 6.9% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 3.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 3.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | -0.00 | ±12% / ±0.02 ms | 11.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | -0.00 | ±12% / ±0.02 ms | 11.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.20 | 0.20 | -0.00 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.90 | 0.94 | +0.04 | ±10% / ±0.09 ms | 4.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.90 | 0.94 | +0.04 | ±10% / ±0.09 ms | 4.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.05 | 0.05 | -0.00 | ±12% / ±0.02 ms | 8.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.18 | -0.00 | ±10% / ±0.02 ms | 1.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.18 | -0.00 | ±10% / ±0.02 ms | 1.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.28 | 2.20 | -0.08 | ±10% / ±0.23 ms | 5.9% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.35 | 10.32 | -0.03 | ±20% / ±2.02 ms | 9.2% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.35 | 10.32 | -0.03 | ±20% / ±2.02 ms | 9.2% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.52 | 0.51 | -0.01 | ±11% / ±0.06 ms | 10.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 2.04 | 1.91 | -0.13 | ±22% / ±0.45 ms | 22.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 2.04 | 1.91 | -0.13 | ±22% / ±0.45 ms | 22.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.11 | 0.11 | -0.00 | ±10% / ±0.02 ms | 8.5% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.04 | 0.04 | -0.00 | ±22% / ±0.02 ms | 22.5% | moderate | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.33 | 0.33 | -0.00 | ±10% / ±0.03 ms | 3.2% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.12 | 0.12 | +0.00 | ±10% / ±0.02 ms | 10.1% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.34 | 0.34 | -0.00 | ±10% / ±0.03 ms | 6.1% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.14 | 0.14 | -0.00 | ±15% / ±0.02 ms | 15.2% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.58 | 0.56 | -0.03 | ±10% / ±0.06 ms | 2.5% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.13 | 0.13 | -0.00 | ±10% / ±0.02 ms | 10.3% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 1.03 | 0.99 | -0.04 | ±13% / ±0.13 ms | 6.8% | moderate | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.36 | 0.35 | -0.01 | ±14% / ±0.05 ms | 13.8% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±57% / ±0.02 ms | 56.9% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02 | +0.00 | ±62% / ±0.02 ms | 61.8% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | +0.00 | ±45% / ±0.02 ms | 45.5% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.20 | -0.00 | ±10% / ±0.02 ms | 9.7% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.16 | 0.16 | +0.00 | ±10% / ±0.02 ms | 10.2% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04 | +0.00 | ±11% / ±0.02 ms | 11.1% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.84 | 1.79 | -0.06 | ±10% / ±0.18 ms | 3.2% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.51 | 1.48 | -0.03 | ±10% / ±0.15 ms | 2.7% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.36 | 0.36 | +0.00 | ±10% / ±0.04 ms | 1.7% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 21.35 | 22.59 | +1.23 | ±10% / ±2.26 ms | 6.1% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 15.91 | 15.11 | -0.80 | ±10% / ±1.59 ms | 2.4% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.81 | 3.80 | -0.01 | ±10% / ±0.38 ms | 2.7% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±25% / ±0.02 ms | 25.0% | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | +0.00 | ±296% / ±0.04 ms | 295.8% | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±1000% / ±0.02 ms | 1000.0% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.05 | -0.00 | ±21% / ±0.02 ms | 21.3% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.38 | 0.39 | +0.01 | ±10% / ±0.04 ms | 6.8% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 9.2% | moderate | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 4.53 | 4.44 | -0.09 | ±10% / ±0.45 ms | 4.5% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.89 | 0.86 | -0.03 | ±13% / ±0.11 ms | 12.7% | moderate | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.19 | 0.17 | -0.02 | ±11% / ±0.02 ms | 5.9% | moderate | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.19 | 0.17 | -0.02 | ±11% / ±0.02 ms | 5.9% | moderate | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.52 | 0.52 | +0.00 | ±10% / ±0.05 ms | 4.4% | stable | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.52 | 0.52 | +0.00 | ±10% / ±0.05 ms | 4.4% | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | +0.00 | ±52% / ±0.02 ms | 51.9% | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03 | +0.00 | ±52% / ±0.02 ms | 51.9% | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.06 | +0.02 | ±36% / ±0.02 ms | 22.0% | noisy | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.06 | +0.02 | ±36% / ±0.02 ms | 22.0% | noisy | ⚪ Within noise |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 2.14 | 2.21 | +0.07 | ±23% / ±0.50 ms | 14.2% | moderate | ⚪ Within noise |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 2.14 | 2.21 | +0.07 | ±23% / ±0.50 ms | 14.2% | moderate | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.62 | 3.47 | -0.15 | ±19% / ±0.68 ms | 9.6% | moderate | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.62 | 3.47 | -0.15 | ±19% / ±0.68 ms | 9.6% | moderate | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.55 | 1.64 | +0.09 | ±23% / ±0.38 ms | 23.1% | stable | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.55 | 1.64 | +0.09 | ±23% / ±0.38 ms | 23.1% | stable | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.58 | 5.48 | -1.11 | ±10% / ±0.66 ms | 9.5% | stable | 🟢 Win (-17%) |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.58 | 5.48 | -1.11 | ±10% / ±0.66 ms | 9.5% | stable | 🟢 Win (-17%) |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.20 | 0.21 | +0.01 | ±23% / ±0.05 ms | 16.3% | moderate | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.20 | 0.21 | +0.01 | ±23% / ±0.05 ms | 16.3% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.05 | -0.00 | ±10% / ±0.02 ms | 3.8% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.05 | -0.00 | ±10% / ±0.02 ms | 3.8% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.41 | 0.39 | -0.02 | ±10% / ±0.04 ms | 2.2% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.41 | 0.39 | -0.02 | ±10% / ±0.04 ms | 2.2% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.76 | 3.88 | +0.12 | ±13% / ±0.51 ms | 6.1% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.76 | 3.88 | +0.12 | ±13% / ±0.51 ms | 6.1% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.77 | 0.52 | -0.25 | ±21% / ±0.16 ms | 21.2% | stable | 🟢 Win (-33%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.77 | 0.52 | -0.25 | ±21% / ±0.16 ms | 21.2% | stable | 🟢 Win (-33%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.06 | -0.01 | ±10% / ±0.02 ms | 6.3% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.06 | -0.01 | ±10% / ±0.02 ms | 6.3% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 5.88 | 5.05 | -0.83 | ±10% / ±0.59 ms | 4.0% | stable | 🟢 Win (-14%) |
| Write Performance / Batched Write Inside Transaction (100... | 5.88 | 5.05 | -0.83 | ±10% / ±0.59 ms | 4.0% | stable | 🟢 Win (-14%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.41 | 0.39 | -0.01 | ±10% / ±0.04 ms | 4.1% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.41 | 0.39 | -0.01 | ±10% / ±0.04 ms | 4.1% | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.05 | -0.01 | ±10% / ±0.02 ms | 4.7% | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.05 | -0.01 | ±10% / ±0.02 ms | 4.7% | stable | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.08 | 0.08 | -0.00 | ±19% / ±0.02 ms | 9.5% | moderate | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.08 | 0.08 | -0.00 | ±19% / ±0.02 ms | 9.5% | moderate | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.87 | 0.79 | -0.08 | ±17% / ±0.15 ms | 16.9% | moderate | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.87 | 0.79 | -0.08 | ±17% / ±0.15 ms | 16.9% | moderate | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.77 | 1.66 | -0.11 | ±10% / ±0.18 ms | 6.8% | stable | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.77 | 1.66 | -0.11 | ±10% / ±0.18 ms | 6.8% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.18 | -0.01 | ±10% / ±0.02 ms | 2.2% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.18 | -0.01 | ±10% / ±0.02 ms | 2.2% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 1.4% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 1.4% | stable | ⚪ Within noise |

**Summary:** 8 wins, 0 regressions, 151 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

✅ **No regressions beyond noise.** 8 benchmarks improved.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.50 | 0.52 | +0.02 MB | ±1.26 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 0.83 | 0.00 | -0.83 MB | ±0.50 MB | 🟢 Win (-0.83 MB) |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 0.00 | 1.67 | +1.67 MB | ±9.00 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 0.00 | 2.53 | +2.53 MB | ±4.61 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 0.02 | +0.02 MB | ±3.01 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 0.00 | 0.00 | +0.00 MB | ±6.60 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±3.76 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 14.59 | 5.16 | -9.43 MB | ±5.20 MB | 🟢 Win (-9.43 MB) |
| Memory / Select 10k rows → Maps / resqlite select() | 1.78 | 1.14 | -0.64 MB | ±2.73 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite3 select() | 3.03 | 5.55 | +2.52 MB | ±4.02 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 1.00 | 1.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.03 | 0.00 | -0.03 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 2 wins, 0 regressions, 13 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 3999 | 3992 | -7 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 3657 | 3990 | +333 | ±100 | 🔴 More re-emits (+333) |

**Granularity summary:** 0 fewer-re-emit, 1 more-re-emit, 5 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


