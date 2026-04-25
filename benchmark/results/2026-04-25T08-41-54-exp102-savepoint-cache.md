# resqlite Benchmark Results

Generated: 2026-04-25T08:41:54.379442

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp102-savepoint-cache`
- Repeats: `5`
- Runtime: `dart-vm / Dart 3.11.0`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `danreynolds/naughty-meitner-9d8dbb @ d5223a25f8f0 (dirty)`
- Comparison baseline: `2026-04-25T07-52-01-exp101-tx-stmt-cache.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.011 | 0.012 | 0.001 | 0.001 |
| sqlite3 select() | 0.014 | 0.015 | 0.014 | 0.015 |
| sqlite_async select() | 0.030 | 0.036 | 0.001 | 0.002 |
| drift select() | 0.040 | 0.056 | 0.001 | 0.002 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.047 | 0.049 | 0.009 | 0.009 |
| sqlite3 select() | 0.110 | 0.114 | 0.110 | 0.114 |
| sqlite_async select() | 0.120 | 0.142 | 0.009 | 0.010 |
| drift select() | 0.179 | 0.193 | 0.010 | 0.012 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.379 | 0.403 | 0.087 | 0.090 |
| sqlite3 select() | 1.044 | 1.128 | 1.044 | 1.128 |
| sqlite_async select() | 1.005 | 1.118 | 0.092 | 0.098 |
| drift select() | 1.557 | 1.953 | 0.092 | 0.096 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.477 | 11.029 | 0.876 | 1.272 |
| sqlite3 select() | 14.591 | 19.010 | 14.591 | 19.010 |
| sqlite_async select() | 13.236 | 21.640 | 0.971 | 2.362 |
| drift select() | 20.665 | 29.049 | 0.939 | 3.352 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.027 | 0.040 | 0.016 | 0.017 |
| sqlite3 + jsonEncode | 0.031 | 0.032 | 0.031 | 0.032 |
| sqlite_async + jsonEncode | 0.049 | 0.056 | 0.017 | 0.020 |
| drift + jsonEncode | 0.054 | 0.058 | 0.016 | 0.018 |
| resqlite selectBytes() | 0.011 | 0.014 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.191 | 0.202 | 0.153 | 0.159 |
| sqlite3 + jsonEncode | 0.255 | 0.288 | 0.255 | 0.288 |
| sqlite_async + jsonEncode | 0.263 | 0.308 | 0.152 | 0.163 |
| drift + jsonEncode | 0.319 | 0.381 | 0.151 | 0.157 |
| resqlite selectBytes() | 0.044 | 0.046 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.852 | 3.161 | 1.499 | 2.608 |
| sqlite3 + jsonEncode | 2.525 | 4.175 | 2.525 | 4.175 |
| sqlite_async + jsonEncode | 2.453 | 4.302 | 1.494 | 2.081 |
| drift + jsonEncode | 3.155 | 4.905 | 1.557 | 2.550 |
| resqlite selectBytes() | 0.355 | 0.405 | 0.000 | 0.001 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 21.839 | 26.661 | 16.085 | 18.991 |
| sqlite3 + jsonEncode | 29.442 | 36.352 | 29.442 | 36.352 |
| sqlite_async + jsonEncode | 31.661 | 41.554 | 15.911 | 17.743 |
| drift + jsonEncode | 38.741 | 42.889 | 15.219 | 18.216 |
| resqlite selectBytes() | 4.673 | 8.998 | 0.004 | 0.008 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.106 | 0.108 | 0.035 | 0.036 |
| sqlite3 | 0.328 | 0.337 | 0.328 | 0.337 |
| sqlite_async | 0.380 | 0.494 | 0.043 | 0.050 |
| drift | 0.632 | 1.673 | 0.045 | 0.057 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.954 | 1.035 | 0.279 | 0.288 |
| sqlite3 | 3.166 | 3.750 | 3.166 | 3.750 |
| sqlite_async | 2.861 | 3.242 | 0.315 | 0.328 |
| drift | 4.712 | 6.994 | 0.327 | 0.341 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.541 | 1.182 | 0.098 | 0.116 |
| sqlite3 | 1.409 | 1.482 | 1.409 | 1.482 |
| sqlite_async | 1.334 | 1.481 | 0.111 | 0.123 |
| drift | 1.893 | 2.214 | 0.111 | 0.117 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.289 | 0.303 | 0.094 | 0.098 |
| sqlite3 | 0.944 | 1.004 | 0.944 | 1.004 |
| sqlite_async | 0.896 | 0.982 | 0.110 | 0.115 |
| drift | 1.434 | 1.537 | 0.109 | 0.115 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.289 | 0.319 | 0.093 | 0.101 |
| sqlite3 | 0.886 | 0.932 | 0.886 | 0.932 |
| sqlite_async | 0.863 | 0.911 | 0.109 | 0.111 |
| drift | 1.391 | 1.491 | 0.108 | 0.110 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.011 | 0.013 | 0.001 | 0.001 |
| sqlite3 | 0.015 | 0.016 | 0.015 | 0.016 |
| sqlite_async | 0.030 | 0.046 | 0.001 | 0.002 |
| drift | 0.037 | 0.039 | 0.001 | 0.001 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.028 | 0.029 | 0.004 | 0.005 |
| sqlite3 | 0.057 | 0.059 | 0.057 | 0.059 |
| sqlite_async | 0.071 | 0.074 | 0.005 | 0.005 |
| drift | 0.101 | 0.109 | 0.005 | 0.005 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.047 | 0.050 | 0.009 | 0.010 |
| sqlite3 | 0.109 | 0.112 | 0.109 | 0.112 |
| sqlite_async | 0.122 | 0.126 | 0.010 | 0.010 |
| drift | 0.179 | 0.187 | 0.010 | 0.010 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.191 | 0.196 | 0.043 | 0.044 |
| sqlite3 | 0.524 | 0.555 | 0.524 | 0.555 |
| sqlite_async | 0.502 | 0.533 | 0.045 | 0.047 |
| drift | 0.766 | 0.781 | 0.045 | 0.046 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.378 | 0.391 | 0.086 | 0.090 |
| sqlite3 | 1.035 | 1.112 | 1.035 | 1.112 |
| sqlite_async | 0.987 | 1.067 | 0.091 | 0.094 |
| drift | 1.563 | 1.877 | 0.090 | 0.095 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.876 | 1.467 | 0.182 | 0.189 |
| sqlite3 | 2.124 | 2.954 | 2.124 | 2.954 |
| sqlite_async | 2.024 | 2.527 | 0.186 | 0.195 |
| drift | 3.135 | 3.524 | 0.184 | 0.579 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.181 | 5.671 | 0.439 | 0.483 |
| sqlite3 | 5.653 | 7.950 | 5.653 | 7.950 |
| sqlite_async | 6.010 | 8.402 | 0.493 | 1.561 |
| drift | 8.485 | 8.708 | 0.474 | 0.491 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.930 | 10.752 | 0.887 | 1.583 |
| sqlite3 | 13.874 | 15.885 | 13.874 | 15.885 |
| sqlite_async | 11.840 | 18.033 | 0.930 | 1.186 |
| drift | 19.630 | 32.281 | 0.957 | 2.512 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 12.125 | 16.858 | 1.758 | 2.866 |
| sqlite3 | 32.367 | 44.255 | 32.367 | 44.255 |
| sqlite_async | 36.610 | 43.568 | 1.860 | 2.165 |
| drift | 51.697 | 79.712 | 1.833 | 2.005 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.026 | 0.029 | 0.026 | 0.029 |
| sqlite3 + jsonEncode | 0.030 | 0.037 | 0.030 | 0.037 |
| sqlite_async + jsonEncode | 0.048 | 0.051 | 0.048 | 0.051 |
| drift + jsonEncode | 0.058 | 0.141 | 0.058 | 0.141 |
| resqlite selectBytes() | 0.012 | 0.014 | 0.012 | 0.014 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.104 | 0.107 | 0.104 | 0.107 |
| sqlite3 + jsonEncode | 0.135 | 0.166 | 0.135 | 0.166 |
| sqlite_async + jsonEncode | 0.142 | 0.151 | 0.142 | 0.151 |
| drift + jsonEncode | 0.175 | 0.195 | 0.175 | 0.195 |
| resqlite selectBytes() | 0.026 | 0.028 | 0.026 | 0.028 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.219 | 0.334 | 0.219 | 0.334 |
| sqlite3 + jsonEncode | 0.266 | 1.116 | 0.266 | 1.116 |
| sqlite_async + jsonEncode | 0.289 | 0.473 | 0.289 | 0.473 |
| drift + jsonEncode | 0.337 | 0.694 | 0.337 | 0.694 |
| resqlite selectBytes() | 0.053 | 0.069 | 0.053 | 0.069 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.919 | 0.992 | 0.919 | 0.992 |
| sqlite3 + jsonEncode | 1.236 | 1.320 | 1.236 | 1.320 |
| sqlite_async + jsonEncode | 1.202 | 1.271 | 1.202 | 1.271 |
| drift + jsonEncode | 1.461 | 1.499 | 1.461 | 1.499 |
| resqlite selectBytes() | 0.188 | 0.194 | 0.188 | 0.194 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.733 | 1.762 | 1.733 | 1.762 |
| sqlite3 + jsonEncode | 2.409 | 2.787 | 2.409 | 2.787 |
| sqlite_async + jsonEncode | 2.376 | 2.675 | 2.376 | 2.675 |
| drift + jsonEncode | 2.995 | 4.035 | 2.995 | 4.035 |
| resqlite selectBytes() | 0.351 | 0.390 | 0.351 | 0.390 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.751 | 7.343 | 3.751 | 7.343 |
| sqlite3 + jsonEncode | 6.025 | 13.543 | 6.025 | 13.543 |
| sqlite_async + jsonEncode | 6.431 | 16.725 | 6.431 | 16.725 |
| drift + jsonEncode | 6.228 | 11.439 | 6.228 | 11.439 |
| resqlite selectBytes() | 0.779 | 1.103 | 0.779 | 1.103 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 10.056 | 15.734 | 10.056 | 15.734 |
| sqlite3 + jsonEncode | 13.914 | 17.446 | 13.914 | 17.446 |
| sqlite_async + jsonEncode | 14.626 | 23.023 | 14.626 | 23.023 |
| drift + jsonEncode | 17.300 | 24.414 | 17.300 | 24.414 |
| resqlite selectBytes() | 1.919 | 2.966 | 1.919 | 2.966 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.726 | 24.870 | 20.726 | 24.870 |
| sqlite3 + jsonEncode | 31.468 | 48.820 | 31.468 | 48.820 |
| sqlite_async + jsonEncode | 32.341 | 34.008 | 32.341 | 34.008 |
| drift + jsonEncode | 38.736 | 51.263 | 38.736 | 51.263 |
| resqlite selectBytes() | 3.744 | 5.872 | 3.744 | 5.872 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 44.497 | 62.835 | 44.497 | 62.835 |
| sqlite3 + jsonEncode | 62.452 | 78.433 | 62.452 | 78.433 |
| sqlite_async + jsonEncode | 68.240 | 77.534 | 68.240 | 77.534 |
| drift + jsonEncode | 83.437 | 97.999 | 83.437 | 97.999 |
| resqlite selectBytes() | 8.573 | 9.706 | 8.573 | 9.706 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.29 | 0.32 | 0.29 |
| sqlite_async | 0.91 | 1.22 | 0.91 |
| drift | 1.45 | 1.80 | 1.45 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.31 | 0.36 | 0.16 |
| sqlite_async | 1.29 | 1.69 | 0.64 |
| drift | 2.69 | 3.31 | 1.35 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.37 | 0.41 | 0.09 |
| sqlite_async | 2.17 | 2.97 | 0.54 |
| drift | 5.07 | 5.45 | 1.27 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.71 | 1.19 | 0.09 |
| sqlite_async | 4.67 | 7.50 | 0.58 |
| drift | 10.09 | 10.87 | 1.26 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 134912 |
| resqlite per query | 0.007 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 134912 | 133427..136115 | 1.0 | 2.7 |
| sqlite3 | 192298 | 180486..194015 | 3.5 | 3.3 |
| sqlite_async | 48243 | 47639..48748 | 1.1 | 3.1 |
| drift | 44493 | 44122..44729 | 0.7 | 2.5 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.600 | 15.956 | 14.600 | 15.956 |
| sqlite_async | 35.298 | 42.143 | 35.298 | 42.143 |
| drift | 54.512 | 75.777 | 54.512 | 75.777 |
| sqlite3 (no cache) | 23.304 | 25.591 | 23.304 | 25.591 |
| sqlite3 (cached stmt) | 23.109 | 24.487 | 23.109 | 24.487 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.946 | 2.939 | 1.946 | 2.939 |
| sqlite3 execute() | 1.127 | 1.827 | 1.127 | 1.827 |
| sqlite_async execute() | 4.012 | 7.287 | 4.012 | 7.287 |
| drift execute() | 4.551 | 7.951 | 4.551 | 7.951 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.053 | 0.056 | 0.053 | 0.056 |
| sqlite3 executeBatch() | 0.049 | 0.050 | 0.049 | 0.050 |
| sqlite_async executeBatch() | 0.095 | 0.119 | 0.095 | 0.119 |
| drift executeBatch() | 0.112 | 0.124 | 0.112 | 0.124 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.431 | 0.518 | 0.431 | 0.518 |
| sqlite3 executeBatch() | 0.426 | 0.489 | 0.426 | 0.489 |
| sqlite_async executeBatch() | 0.512 | 0.576 | 0.512 | 0.576 |
| drift executeBatch() | 0.658 | 0.812 | 0.658 | 0.812 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.275 | 6.315 | 4.275 | 6.315 |
| sqlite3 executeBatch() | 4.029 | 4.729 | 4.029 | 4.729 |
| sqlite_async executeBatch() | 4.626 | 5.107 | 4.626 | 5.107 |
| drift executeBatch() | 6.019 | 6.636 | 6.019 | 6.636 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.062 | 0.119 | 0.062 | 0.119 |
| sqlite_async writeTransaction() | 0.088 | 0.113 | 0.088 | 0.113 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.072 | 0.086 | 0.072 | 0.086 |
| resqlite tx.execute() loop | 0.599 | 0.683 | 0.599 | 0.683 |
| sqlite_async tx.execute() loop | 1.041 | 1.329 | 1.041 | 1.329 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.457 | 0.525 | 0.457 | 0.525 |
| resqlite tx.execute() loop | 5.701 | 6.766 | 5.701 | 6.766 |
| sqlite_async tx.execute() loop | 10.420 | 10.990 | 10.420 | 10.990 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.102 | 0.107 | 0.102 | 0.107 |
| sqlite_async tx.getAll() | 0.206 | 0.231 | 0.206 | 0.231 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.195 | 0.230 | 0.195 | 0.230 |
| sqlite_async tx.getAll() | 0.366 | 0.454 | 0.366 | 0.454 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.035 | 0.069 | 0.035 | 0.069 |
| sqlite_async watch() | 0.126 | 0.175 | 0.126 | 0.175 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.054 | 0.115 | 0.054 | 0.115 |
| sqlite_async | 0.084 | 0.430 | 0.084 | 0.430 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.417 | 0.816 | 0.417 | 0.816 |
| sqlite_async | 1.474 | 5.354 | 1.474 | 5.354 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.284 | 0.384 | 0.284 | 0.384 |
| sqlite_async | 0.345 | 0.413 | 0.345 | 0.413 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.745 | 1.745 | 1.745 | 1.745 |
| sqlite_async | 9.918 | 9.918 | 9.918 | 9.918 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.130 | 4.583 | 4.130 | 4.583 |
| sqlite_async | 7.794 | 10.424 | 7.794 | 10.424 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.514 | 0.756 | 0.514 | 0.756 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 5.863 | 6.513 | 5.863 | 6.513 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. On resqlite's main branch this ratio is driven toward 0 by experiment 075 (C-side result-hash short-circuit), not by writer-side column-tracking (exp 052 is not implemented). The two mechanisms are indistinguishable on this read-side benchmark.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 86.6 | 0.000 |
| sqlite_async | 3891 | 936.0 | 1.126 |
| drift | 5000 | 1021.4 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 67.6 | 0.000 |
| sqlite_async | 3456 | 965.5 | 1.126 |
| drift | 5000 | 1172.8 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 224.46 | 226.51 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 438.62 | 441.34 | 0.00 | 0.00 | 1117 | 3 |
| drift stream() | 557.36 | 557.95 | 0.01 | 0.40 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.022 | 0.037 | 0.000 | 0.000 |
| sqlite3 | 0.020 | 0.031 | 0.020 | 0.031 |
| sqlite_async | 0.046 | 0.072 | 0.000 | 0.000 |
| drift | 0.039 | 0.067 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.016 | 0.024 | 0.000 | 0.000 |
| sqlite3 | 0.013 | 0.018 | 0.013 | 0.018 |
| sqlite_async | 0.036 | 0.058 | 0.000 | 0.000 |
| drift | 0.031 | 0.056 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.026 | 0.036 | 0.000 | 0.000 |
| sqlite3 | 0.031 | 0.034 | 0.031 | 0.034 |
| sqlite_async | 0.061 | 0.079 | 0.000 | 0.000 |
| drift | 0.053 | 0.064 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.009 | 0.016 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.024 | 0.032 | 0.000 | 0.000 |
| drift | 0.020 | 0.030 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.040 | 0.044 | 0.001 | 0.001 |
| sqlite3 | 0.061 | 0.066 | 0.061 | 0.066 |
| sqlite_async | 0.075 | 0.082 | 0.001 | 0.001 |
| drift | 0.089 | 0.103 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 106.834 | 108.137 | 0.000 | 0.000 | 0 |
| sqlite_async | 215.860 | 217.363 | 0.000 | 0.000 | 35 |
| drift | 228.993 | 229.346 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 240.89 | 240.89 | 0.00 | 0.00 | 13.40 | 227.49 | 0 |
| sqlite_async | 481.81 | 481.81 | 0.01 | 0.01 | 23.60 | 459.56 | 1185 |
| drift | 1825.69 | 1825.69 | 0.08 | 0.08 | 14.46 | 1811.22 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 3.00 | 26.55 | 0.00..5.70 | ±2.85 |
| sqlite3 select() | 2.98 | 10.22 | 1.80..9.72 | ±3.96 |
| sqlite_async select() | 0.97 | 1.50 | 0.50..1.50 | ±0.50 |
| drift select() | 3.66 | 18.73 | 0.00..6.61 | ±3.30 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 4.50 | 0.00..0.00 | ±0.00 |
| resqlite + jsonEncode | 0.00 | 62.08 | 0.00..30.05 | ±15.02 |
| sqlite3 + jsonEncode | 0.00 | 74.19 | 0.00..31.59 | ±15.80 |
| sqlite_async + jsonEncode | 0.00 | 35.28 | 0.00..0.00 | ±0.00 |
| drift + jsonEncode | 4.94 | 79.94 | 0.00..47.05 | ±23.52 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.00 | 4.44 | 0.00..0.00 | ±0.00 |
| sqlite3 executeBatch() | 0.00 | 0.14 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| drift batch() | 0.52 | 4.50 | 0.00..2.52 | ±1.26 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.00 | 0.06 | 0.00..0.06 | ±0.03 |
| sqlite_async watch() | 0.00 | 0.52 | 0.00..0.02 | ±0.01 |

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
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.03 | 0.03..0.03 | 7.4% | 14.8% | 3.7% | moderate |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 11.1% | 22.2% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02..0.03 | 16.7% | 33.3% | 8.3% | noisy |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.01..0.02 | 16.7% | 33.3% | 11.1% | noisy |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.29 | 0.29..0.30 | 1.7% | 3.4% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.29 | 0.29..0.30 | 1.7% | 3.4% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.31 | 0.30..0.33 | 4.8% | 9.7% | 3.2% | moderate |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.16 | 0.15..0.17 | 6.3% | 12.5% | 6.3% | moderate |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.37 | 0.37..0.71 | 45.9% | 91.9% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.09 | 0.09..0.18 | 50.0% | 100.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.69 | 0.68..0.71 | 2.2% | 4.3% | 1.4% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.09 | 0.09..0.09 | 0.0% | 0.0% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.05 | 8.5% | 17.1% | 2.4% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 150.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 107.54 | 106.48..107.97 | 0.7% | 1.4% | 0.4% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 240.89 | 239.85..244.74 | 1.0% | 2.0% | 0.1% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 220.84 | 220.15..224.46 | 1.0% | 2.0% | 0.3% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 14.55 | 14.32..15.24 | 3.2% | 6.3% | 0.6% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 14.55 | 14.32..15.24 | 3.2% | 6.3% | 0.6% | stable |
| Point Query Throughput / resqlite qps | 134912.00 | 132145.00..139312.00 | 2.7% | 5.3% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.01 | 27.3% | 54.5% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.04 | 20.0% | 40.0% | 10.0% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.04 | 20.0% | 40.0% | 10.0% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 50.0% | 100.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 33.3% | 66.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.02 | 33.3% | 66.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05..0.05 | 6.4% | 12.8% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.20 | 0.20..0.22 | 5.6% | 11.3% | 2.9% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.20 | 0.20..0.22 | 5.6% | 11.3% | 2.9% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.05 | 11.1% | 22.2% | 4.4% | moderate |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.04 | 0.04..0.05 | 11.1% | 22.2% | 4.4% | moderate |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.38 | 0.38..0.39 | 1.4% | 2.9% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.82 | 1.73..1.91 | 4.8% | 9.7% | 3.4% | moderate |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.82 | 1.73..1.91 | 4.8% | 9.7% | 3.4% | moderate |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09..0.09 | 2.9% | 5.7% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.36 | 0.35..0.36 | 1.3% | 2.5% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.36 | 0.35..0.36 | 1.3% | 2.5% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.72 | 4.54..4.93 | 4.1% | 8.3% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 20.93 | 20.34..23.84 | 8.4% | 16.7% | 2.8% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 20.93 | 20.34..23.84 | 8.4% | 16.7% | 2.8% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.89 | 0.86..0.89 | 2.0% | 3.9% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 3.84 | 3.74..4.44 | 9.1% | 18.2% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 3.84 | 3.74..4.44 | 9.1% | 18.2% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.80 | 0.78..0.88 | 5.7% | 11.5% | 2.4% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.83 | 3.75..3.92 | 2.2% | 4.5% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.83 | 3.75..3.92 | 2.2% | 4.5% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.18 | 0.17..0.18 | 3.4% | 6.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.78 | 0.77..0.94 | 11.1% | 22.2% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.78 | 0.77..0.94 | 11.1% | 22.2% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 11.10 | 10.97..12.13 | 5.2% | 10.4% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 44.50 | 42.47..45.63 | 3.6% | 7.1% | 2.5% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 44.50 | 42.47..45.63 | 3.6% | 7.1% | 2.5% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.76 | 1.71..1.78 | 2.0% | 4.0% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 8.29 | 7.97..8.57 | 3.6% | 7.3% | 2.9% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 8.29 | 7.97..8.57 | 3.6% | 7.3% | 2.9% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03..0.03 | 5.4% | 10.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10..0.11 | 2.9% | 5.7% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.10 | 0.10..0.11 | 2.9% | 5.7% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.02..0.03 | 11.5% | 23.1% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.02..0.03 | 11.5% | 23.1% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.20 | 0.19..0.20 | 3.3% | 6.7% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.92 | 0.90..1.02 | 6.7% | 13.4% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.92 | 0.90..1.02 | 6.7% | 13.4% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04..0.04 | 2.3% | 4.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.18 | 0.18..0.19 | 1.9% | 3.8% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.18 | 0.18..0.19 | 1.9% | 3.8% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.18 | 2.12..2.26 | 3.3% | 6.6% | 2.7% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 10.23 | 10.05..11.31 | 6.2% | 12.4% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 10.23 | 10.05..11.31 | 6.2% | 12.4% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.43 | 0.43..0.45 | 2.9% | 5.7% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 1.95 | 1.92..2.02 | 2.5% | 4.9% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 1.95 | 1.92..2.02 | 2.5% | 4.9% | 1.5% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.11 | 0.10..0.11 | 3.8% | 7.5% | 0.9% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.04 | 0.03..0.04 | 15.7% | 31.4% | 2.9% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.30 | 0.29..0.30 | 2.3% | 4.7% | 1.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.10 | 0.09..0.10 | 3.2% | 6.3% | 1.1% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.30 | 0.29..0.30 | 1.8% | 3.7% | 0.7% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.10 | 0.09..0.10 | 1.6% | 3.1% | 1.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.54 | 0.53..0.87 | 32.2% | 64.3% | 3.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.10 | 0.10..0.11 | 5.1% | 10.2% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.94 | 0.91..0.95 | 2.3% | 4.7% | 1.1% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.27 | 0.27..0.28 | 2.4% | 4.8% | 1.8% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.05 | 48.1% | 96.3% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02..0.04 | 59.4% | 118.8% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 33.3% | 66.7% | 8.3% | noisy |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.19..0.22 | 8.4% | 16.8% | 2.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.15 | 0.15..0.17 | 5.6% | 11.1% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.05 | 11.4% | 22.7% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.83 | 1.77..1.87 | 2.7% | 5.5% | 2.5% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.50 | 1.45..1.53 | 2.6% | 5.3% | 1.7% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.36 | 0.35..0.37 | 2.5% | 5.0% | 0.8% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 21.84 | 19.37..25.05 | 13.0% | 26.0% | 11.3% | noisy |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 15.75 | 14.84..16.09 | 3.9% | 7.9% | 2.1% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.97 | 3.74..4.67 | 11.7% | 23.5% | 3.1% | moderate |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 50.0% | 100.0% | 33.3% | noisy |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.08 | 300.0% | 600.0% | 8.3% | noisy |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 1050.0% | 2100.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.05..0.07 | 21.3% | 42.6% | 2.1% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 5.6% | 11.1% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.38 | 0.38..0.42 | 5.5% | 11.1% | 0.8% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.07..0.09 | 10.3% | 20.7% | 0.0% | stable |
| Select → Maps / 10000 rows / resqlite select() | 4.48 | 4.41..4.53 | 1.4% | 2.8% | 1.0% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.87 | 0.69..0.88 | 10.7% | 21.3% | 0.7% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.21 | 0.20..0.28 | 19.8% | 39.5% | 4.3% | moderate |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.21 | 0.20..0.28 | 19.8% | 39.5% | 4.3% | moderate |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.57 | 0.50..0.65 | 12.9% | 25.9% | 10.1% | noisy |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.57 | 0.50..0.65 | 12.9% | 25.9% | 10.1% | noisy |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03..0.06 | 56.3% | 112.5% | 9.4% | noisy |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03..0.06 | 56.3% | 112.5% | 9.4% | noisy |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.04..0.06 | 18.3% | 36.5% | 15.4% | noisy |
| Streaming / Invalidation Latency / resqlite [main] | 0.05 | 0.04..0.06 | 18.3% | 36.5% | 15.4% | noisy |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.83 | 3.55..4.13 | 7.6% | 15.2% | 1.5% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.83 | 3.55..4.13 | 7.6% | 15.2% | 1.5% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.93 | 1.53..2.58 | 27.2% | 54.5% | 9.7% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.93 | 1.53..2.58 | 27.2% | 54.5% | 9.7% | noisy |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.01 | 5.79..7.64 | 15.4% | 30.8% | 3.6% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.01 | 5.79..7.64 | 15.4% | 30.8% | 3.6% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.20 | 0.18..0.42 | 59.4% | 118.9% | 6.1% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.20 | 0.18..0.42 | 59.4% | 118.9% | 6.1% | moderate |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.05..0.06 | 8.9% | 17.9% | 5.4% | moderate |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.06 | 0.05..0.06 | 8.9% | 17.9% | 5.4% | moderate |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.44 | 0.43..0.48 | 5.2% | 10.5% | 1.8% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.44 | 0.43..0.48 | 5.2% | 10.5% | 1.8% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.45 | 4.28..4.50 | 2.5% | 5.1% | 1.1% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.45 | 4.28..4.50 | 2.5% | 5.1% | 1.1% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.60 | 0.58..0.61 | 2.1% | 4.3% | 0.2% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.60 | 0.58..0.61 | 2.1% | 4.3% | 0.2% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07..0.07 | 4.2% | 8.3% | 1.4% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07..0.07 | 4.2% | 8.3% | 1.4% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 6.26 | 5.54..7.87 | 18.6% | 37.2% | 9.0% | noisy |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 6.26 | 5.54..7.87 | 18.6% | 37.2% | 9.0% | noisy |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.46 | 0.44..0.53 | 10.0% | 19.9% | 4.6% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.46 | 0.44..0.53 | 10.0% | 19.9% | 4.6% | moderate |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05..0.06 | 14.4% | 28.8% | 9.6% | noisy |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05..0.06 | 14.4% | 28.8% | 9.6% | noisy |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.73 | 1.67..3.02 | 39.1% | 78.2% | 3.7% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.73 | 1.67..3.02 | 39.1% | 78.2% | 3.7% | moderate |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.20 | 0.18..0.20 | 5.9% | 11.8% | 4.1% | moderate |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.20 | 0.18..0.20 | 5.9% | 11.8% | 4.1% | moderate |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.10 | 0.10..0.13 | 13.6% | 27.2% | 1.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.10 | 0.10..0.13 | 13.6% | 27.2% | 1.0% | stable |


## Comparison vs Previous Run

Previous: `2026-04-25T07-52-01-exp101-tx-stmt-cache.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.03 | 0.03 | -0.00 | ±11% / ±0.02 ms | 7.4% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | -0.00 | ±11% / ±0.02 ms | 11.1% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.03 | 0.02 | -0.00 | ±25% / ±0.02 ms | 16.7% | noisy | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02 | -0.00 | ±33% / ±0.02 ms | 16.7% | noisy | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.29 | 0.29 | +0.00 | ±10% / ±0.03 ms | 1.7% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.29 | 0.29 | +0.00 | ±10% / ±0.03 ms | 1.7% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.82 | 0.31 | -0.51 | ±10% / ±0.08 ms | 4.8% | moderate | 🟢 Win (-62%) |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.41 | 0.16 | -0.25 | ±19% / ±0.08 ms | 6.3% | moderate | 🟢 Win (-61%) |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.36 | 0.37 | +0.01 | ±46% / ±0.17 ms | 45.9% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.09 | 0.09 | +0.00 | ±50% / ±0.04 ms | 50.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.68 | 0.69 | +0.01 | ±10% / ±0.07 ms | 2.2% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 8.5% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±150% / ±0.02 ms | 150.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 111.19 | 107.54 | -3.65 | ±10% / ±11.12 ms | 0.7% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 242.67 | 240.89 | -1.78 | ±10% / ±24.27 ms | 1.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 225.65 | 220.84 | -4.81 | ±10% / ±22.57 ms | 1.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 15.36 | 14.55 | -0.81 | ±10% / ±1.54 ms | 3.2% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 15.36 | 14.55 | -0.81 | ±10% / ±1.54 ms | 3.2% | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 124414.00 | 134912.00 | +10498.00 | ±10% / ±13491.20 ms | 2.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01 | -0.00 | ±27% / ±0.02 ms | 27.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±30% / ±0.02 ms | 20.0% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.03 | +0.00 | ±30% / ±0.02 ms | 20.0% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±50% / ±0.02 ms | 50.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±33% / ±0.02 ms | 33.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±33% / ±0.02 ms | 33.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.05 | +0.00 | ±10% / ±0.02 ms | 6.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.20 | +0.01 | ±10% / ±0.02 ms | 5.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.20 | +0.01 | ±10% / ±0.02 ms | 5.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±13% / ±0.02 ms | 11.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±13% / ±0.02 ms | 11.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.38 | 0.38 | +0.01 | ±10% / ±0.04 ms | 1.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.74 | 1.82 | +0.07 | ±10% / ±0.19 ms | 4.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.74 | 1.82 | +0.07 | ±10% / ±0.19 ms | 4.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 2.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.36 | 0.36 | -0.01 | ±10% / ±0.04 ms | 1.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.36 | 0.36 | -0.01 | ±10% / ±0.04 ms | 1.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.25 | 4.72 | +0.47 | ±10% / ±0.47 ms | 4.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 19.96 | 20.93 | +0.97 | ±10% / ±2.09 ms | 8.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 19.96 | 20.93 | +0.97 | ±10% / ±2.09 ms | 8.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.84 | 0.89 | +0.05 | ±10% / ±0.09 ms | 2.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.68 | 3.84 | +0.16 | ±10% / ±0.38 ms | 9.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.68 | 3.84 | +0.16 | ±10% / ±0.38 ms | 9.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.77 | 0.80 | +0.03 | ±10% / ±0.08 ms | 5.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.89 | 3.83 | -0.06 | ±10% / ±0.39 ms | 2.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.89 | 3.83 | -0.06 | ±10% / ±0.39 ms | 2.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.17 | 0.18 | +0.01 | ±10% / ±0.02 ms | 3.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.77 | 0.78 | +0.01 | ±11% / ±0.09 ms | 11.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.77 | 0.78 | +0.01 | ±11% / ±0.09 ms | 11.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.86 | 11.10 | +0.24 | ±10% / ±1.11 ms | 5.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 46.03 | 44.50 | -1.53 | ±10% / ±4.60 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 46.03 | 44.50 | -1.53 | ±10% / ±4.60 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.70 | 1.76 | +0.06 | ±10% / ±0.18 ms | 2.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.68 | 8.29 | -0.39 | ±10% / ±0.87 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.68 | 8.29 | -0.39 | ±10% / ±0.87 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 5.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 2.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 2.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.03 | +0.00 | ±12% / ±0.02 ms | 11.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.03 | +0.00 | ±12% / ±0.02 ms | 11.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.19 | 0.20 | +0.01 | ±10% / ±0.02 ms | 3.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.89 | 0.92 | +0.03 | ±10% / ±0.09 ms | 6.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.89 | 0.92 | +0.03 | ±10% / ±0.09 ms | 6.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.18 | +0.00 | ±10% / ±0.02 ms | 1.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.18 | +0.00 | ±10% / ±0.02 ms | 1.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.06 | 2.18 | +0.12 | ±10% / ±0.22 ms | 3.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 9.79 | 10.23 | +0.44 | ±10% / ±1.02 ms | 6.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 9.79 | 10.23 | +0.44 | ±10% / ±1.02 ms | 6.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.42 | 0.43 | +0.02 | ±10% / ±0.04 ms | 2.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.81 | 1.95 | +0.14 | ±10% / ±0.20 ms | 2.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.81 | 1.95 | +0.14 | ±10% / ±0.20 ms | 2.5% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.11 | 0.11 | -0.00 | ±10% / ±0.02 ms | 3.8% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.04 | 0.04 | -0.00 | ±16% / ±0.02 ms | 15.7% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.29 | 0.30 | +0.01 | ±10% / ±0.03 ms | 2.3% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.09 | 0.10 | +0.00 | ±10% / ±0.02 ms | 3.2% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.29 | 0.30 | +0.01 | ±10% / ±0.03 ms | 1.8% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 1.6% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.52 | 0.54 | +0.02 | ±32% / ±0.17 ms | 32.2% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 5.1% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.93 | 0.94 | +0.01 | ±10% / ±0.09 ms | 2.3% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.27 | 0.27 | +0.00 | ±10% / ±0.03 ms | 2.4% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±48% / ±0.02 ms | 48.1% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.01 | 0.02 | +0.00 | ±59% / ±0.02 ms | 59.4% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | +0.00 | ±33% / ±0.02 ms | 33.3% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.19 | 0.20 | +0.00 | ±10% / ±0.02 ms | 8.4% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.15 | 0.15 | +0.00 | ±10% / ±0.02 ms | 5.6% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04 | +0.00 | ±11% / ±0.02 ms | 11.4% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.73 | 1.83 | +0.09 | ±10% / ±0.18 ms | 2.7% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.44 | 1.50 | +0.05 | ±10% / ±0.15 ms | 2.6% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.36 | 0.36 | -0.01 | ±10% / ±0.04 ms | 2.5% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 21.16 | 21.84 | +0.68 | ±34% / ±7.42 ms | 13.0% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 15.64 | 15.75 | +0.11 | ±10% / ±1.58 ms | 3.9% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 4.01 | 3.97 | -0.04 | ±12% / ±0.47 ms | 11.7% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±100% / ±0.02 ms | 50.0% | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | +0.00 | ±300% / ±0.04 ms | 300.0% | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±1050% / ±0.02 ms | 1050.0% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.05 | +0.00 | ±21% / ±0.02 ms | 21.3% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 5.6% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.38 | 0.38 | +0.00 | ±10% / ±0.04 ms | 5.5% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 10.3% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 4.27 | 4.48 | +0.21 | ±10% / ±0.45 ms | 1.4% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.83 | 0.87 | +0.04 | ±11% / ±0.09 ms | 10.7% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.39 | 0.21 | -0.18 | ±20% / ±0.08 ms | 19.8% | moderate | 🟢 Win (-45%) |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.39 | 0.21 | -0.18 | ±20% / ±0.08 ms | 19.8% | moderate | 🟢 Win (-45%) |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.55 | 0.57 | +0.02 | ±30% / ±0.17 ms | 12.9% | noisy | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.55 | 0.57 | +0.02 | ±30% / ±0.17 ms | 12.9% | noisy | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | +0.01 | ±56% / ±0.02 ms | 56.3% | noisy | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03 | +0.01 | ±56% / ±0.02 ms | 56.3% | noisy | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.06 | 0.05 | -0.00 | ±46% / ±0.03 ms | 18.3% | noisy | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.06 | 0.05 | -0.00 | ±46% / ±0.03 ms | 18.3% | noisy | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.76 | 3.83 | +0.07 | ±10% / ±0.38 ms | 7.6% | stable | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.76 | 3.83 | +0.07 | ±10% / ±0.38 ms | 7.6% | stable | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.79 | 1.93 | -0.86 | ±29% / ±0.82 ms | 27.2% | noisy | 🟢 Win (-31%) |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.79 | 1.93 | -0.86 | ±29% / ±0.82 ms | 27.2% | noisy | 🟢 Win (-31%) |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 5.79 | 6.01 | +0.22 | ±15% / ±0.93 ms | 15.4% | moderate | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 5.79 | 6.01 | +0.22 | ±15% / ±0.93 ms | 15.4% | moderate | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.26 | 0.20 | -0.07 | ±59% / ±0.16 ms | 59.4% | moderate | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.26 | 0.20 | -0.07 | ±59% / ±0.16 ms | 59.4% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | +0.00 | ±16% / ±0.02 ms | 8.9% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | +0.00 | ±16% / ±0.02 ms | 8.9% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.42 | 0.44 | +0.01 | ±10% / ±0.04 ms | 5.2% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.42 | 0.44 | +0.01 | ±10% / ±0.04 ms | 5.2% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.14 | 4.45 | +0.31 | ±10% / ±0.45 ms | 2.5% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.14 | 4.45 | +0.31 | ±10% / ±0.45 ms | 2.5% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.57 | 0.60 | +0.03 | ±10% / ±0.06 ms | 2.1% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.57 | 0.60 | +0.03 | ±10% / ±0.06 ms | 2.1% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.07 | +0.00 | ±10% / ±0.02 ms | 4.2% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.07 | +0.00 | ±10% / ±0.02 ms | 4.2% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 7.00 | 6.26 | -0.74 | ±27% / ±1.89 ms | 18.6% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 7.00 | 6.26 | -0.74 | ±27% / ±1.89 ms | 18.6% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.43 | 0.46 | +0.03 | ±14% / ±0.06 ms | 10.0% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.43 | 0.46 | +0.03 | ±14% / ±0.06 ms | 10.0% | moderate | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.05 | +0.00 | ±29% / ±0.02 ms | 14.4% | noisy | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.05 | +0.00 | ±29% / ±0.02 ms | 14.4% | noisy | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.57 | 1.73 | +0.16 | ±39% / ±0.68 ms | 39.1% | moderate | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.57 | 1.73 | +0.16 | ±39% / ±0.68 ms | 39.1% | moderate | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.20 | +0.00 | ±12% / ±0.02 ms | 5.9% | moderate | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.20 | +0.00 | ±12% / ±0.02 ms | 5.9% | moderate | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | -0.00 | ±14% / ±0.02 ms | 13.6% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | -0.00 | ±14% / ±0.02 ms | 13.6% | stable | ⚪ Within noise |

**Summary:** 6 wins, 0 regressions, 147 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

✅ **No regressions beyond noise.** 6 benchmarks improved.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.00 | 0.52 | +0.52 MB | ±1.26 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 0.00 | 4.94 | +4.94 MB | ±23.52 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 1.27 | 0.00 | -1.27 MB | ±15.02 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 3.69 | 0.00 | -3.69 MB | ±15.80 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 1.39 | 3.66 | +2.27 MB | ±3.30 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / resqlite select() | 7.09 | 3.00 | -4.09 MB | ±2.85 MB | 🟢 Win (-4.09 MB) |
| Memory / Select 10k rows → Maps / sqlite3 select() | 6.38 | 2.98 | -3.40 MB | ±3.96 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 1.00 | 0.97 | -0.03 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.02 | 0.00 | -0.02 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 1 wins, 0 regressions, 14 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 3814 | 3891 | +77 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 3764 | 3456 | -308 | ±100 | 🔴 Invalidation elided (-308) — writes not firing |

**Granularity summary:** 0 fewer-re-emit, 1 more-re-emit, 5 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


