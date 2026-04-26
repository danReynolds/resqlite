# resqlite Benchmark Results

Generated: 2026-04-26T07:28:32.416927

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp104-querybytes-persistent-slots`
- Repeats: `5`
- Runtime: `dart-vm / Dart 3.11.0`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `danreynolds/agitated-payne-9771ef @ 3f88e24c75b3 (dirty)`
- Comparison baseline: `2026-04-25T14-06-42-baseline-for-exp100.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.012 | 0.016 | 0.001 | 0.001 |
| sqlite3 select() | 0.015 | 0.016 | 0.015 | 0.016 |
| sqlite_async select() | 0.032 | 0.034 | 0.001 | 0.001 |
| drift select() | 0.046 | 0.083 | 0.001 | 0.003 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.050 | 0.059 | 0.009 | 0.010 |
| sqlite3 select() | 0.113 | 0.136 | 0.113 | 0.136 |
| sqlite_async select() | 0.120 | 0.122 | 0.009 | 0.010 |
| drift select() | 0.179 | 0.202 | 0.010 | 0.011 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.379 | 0.404 | 0.085 | 0.089 |
| sqlite3 select() | 1.051 | 1.090 | 1.051 | 1.090 |
| sqlite_async select() | 1.005 | 1.104 | 0.092 | 0.097 |
| drift select() | 1.571 | 2.049 | 0.091 | 0.098 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.485 | 12.272 | 0.852 | 1.288 |
| sqlite3 select() | 13.616 | 16.490 | 13.616 | 16.490 |
| sqlite_async select() | 13.019 | 18.581 | 0.959 | 2.594 |
| drift select() | 21.223 | 34.566 | 0.944 | 2.842 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.029 | 0.034 | 0.017 | 0.020 |
| sqlite3 + jsonEncode | 0.033 | 0.039 | 0.033 | 0.039 |
| sqlite_async + jsonEncode | 0.048 | 0.061 | 0.016 | 0.019 |
| drift + jsonEncode | 0.054 | 0.056 | 0.017 | 0.019 |
| resqlite selectBytes() | 0.010 | 0.011 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.194 | 0.225 | 0.154 | 0.169 |
| sqlite3 + jsonEncode | 0.255 | 0.293 | 0.255 | 0.293 |
| sqlite_async + jsonEncode | 0.262 | 0.269 | 0.152 | 0.156 |
| drift + jsonEncode | 0.316 | 0.345 | 0.152 | 0.156 |
| resqlite selectBytes() | 0.043 | 0.045 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.717 | 1.770 | 1.426 | 1.464 |
| sqlite3 + jsonEncode | 2.402 | 2.553 | 2.402 | 2.553 |
| sqlite_async + jsonEncode | 2.368 | 2.709 | 1.464 | 1.813 |
| drift + jsonEncode | 3.139 | 8.937 | 1.556 | 1.788 |
| resqlite selectBytes() | 0.350 | 0.374 | 0.000 | 0.000 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 23.626 | 29.815 | 15.745 | 22.214 |
| sqlite3 + jsonEncode | 29.435 | 37.125 | 29.435 | 37.125 |
| sqlite_async + jsonEncode | 28.986 | 33.301 | 15.693 | 18.072 |
| drift + jsonEncode | 39.689 | 46.222 | 15.411 | 20.678 |
| resqlite selectBytes() | 3.793 | 6.308 | 0.003 | 0.009 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.102 | 0.104 | 0.036 | 0.037 |
| sqlite3 | 0.321 | 0.372 | 0.321 | 0.372 |
| sqlite_async | 0.370 | 0.489 | 0.043 | 0.051 |
| drift | 0.609 | 0.699 | 0.044 | 0.046 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.953 | 2.043 | 0.278 | 0.335 |
| sqlite3 | 3.294 | 3.985 | 3.294 | 3.985 |
| sqlite_async | 3.017 | 4.264 | 0.345 | 0.368 |
| drift | 4.970 | 7.407 | 0.348 | 0.362 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.663 | 1.386 | 0.105 | 0.127 |
| sqlite3 | 1.471 | 1.525 | 1.471 | 1.525 |
| sqlite_async | 1.378 | 1.495 | 0.116 | 0.127 |
| drift | 1.938 | 2.345 | 0.115 | 0.122 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.294 | 0.320 | 0.097 | 0.102 |
| sqlite3 | 0.944 | 0.994 | 0.944 | 0.994 |
| sqlite_async | 0.900 | 1.008 | 0.114 | 0.119 |
| drift | 1.446 | 1.580 | 0.114 | 0.118 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.297 | 0.312 | 0.098 | 0.103 |
| sqlite3 | 0.896 | 0.997 | 0.896 | 0.997 |
| sqlite_async | 0.909 | 0.966 | 0.115 | 0.121 |
| drift | 1.431 | 1.501 | 0.114 | 0.119 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.012 | 0.015 | 0.001 | 0.001 |
| sqlite3 | 0.014 | 0.015 | 0.014 | 0.015 |
| sqlite_async | 0.036 | 0.057 | 0.001 | 0.002 |
| drift | 0.040 | 0.057 | 0.001 | 0.002 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.027 | 0.029 | 0.004 | 0.004 |
| sqlite3 | 0.056 | 0.059 | 0.056 | 0.059 |
| sqlite_async | 0.069 | 0.072 | 0.005 | 0.005 |
| drift | 0.102 | 0.107 | 0.005 | 0.005 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.045 | 0.047 | 0.008 | 0.009 |
| sqlite3 | 0.112 | 0.120 | 0.112 | 0.120 |
| sqlite_async | 0.120 | 0.128 | 0.010 | 0.010 |
| drift | 0.174 | 0.196 | 0.010 | 0.011 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.188 | 0.192 | 0.041 | 0.042 |
| sqlite3 | 0.528 | 0.568 | 0.528 | 0.568 |
| sqlite_async | 0.501 | 0.526 | 0.046 | 0.048 |
| drift | 0.760 | 0.864 | 0.045 | 0.047 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.377 | 0.398 | 0.085 | 0.089 |
| sqlite3 | 1.032 | 1.106 | 1.032 | 1.106 |
| sqlite_async | 1.052 | 1.737 | 0.095 | 0.113 |
| drift | 1.642 | 1.929 | 0.097 | 0.101 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.795 | 1.851 | 0.174 | 0.191 |
| sqlite3 | 2.102 | 2.676 | 2.102 | 2.676 |
| sqlite_async | 2.013 | 2.345 | 0.184 | 0.190 |
| drift | 3.095 | 3.742 | 0.183 | 0.192 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.256 | 4.563 | 0.434 | 0.661 |
| sqlite3 | 5.300 | 7.251 | 5.300 | 7.251 |
| sqlite_async | 5.346 | 6.322 | 0.468 | 0.492 |
| drift | 8.602 | 11.315 | 0.484 | 0.510 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.769 | 13.493 | 0.894 | 2.018 |
| sqlite3 | 13.932 | 15.023 | 13.932 | 15.023 |
| sqlite_async | 11.208 | 12.412 | 0.911 | 0.956 |
| drift | 18.969 | 26.891 | 0.948 | 1.114 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 11.217 | 21.199 | 1.758 | 3.843 |
| sqlite3 | 32.157 | 37.003 | 32.157 | 37.003 |
| sqlite_async | 36.301 | 45.541 | 1.866 | 2.040 |
| drift | 51.227 | 60.436 | 1.838 | 1.969 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.030 | 0.039 | 0.030 | 0.039 |
| sqlite3 + jsonEncode | 0.028 | 0.029 | 0.028 | 0.029 |
| sqlite_async + jsonEncode | 0.047 | 0.048 | 0.047 | 0.048 |
| drift + jsonEncode | 0.052 | 0.056 | 0.052 | 0.056 |
| resqlite selectBytes() | 0.011 | 0.012 | 0.011 | 0.012 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.106 | 0.119 | 0.106 | 0.119 |
| sqlite3 + jsonEncode | 0.137 | 0.146 | 0.137 | 0.146 |
| sqlite_async + jsonEncode | 0.146 | 0.181 | 0.146 | 0.181 |
| drift + jsonEncode | 0.169 | 0.172 | 0.169 | 0.172 |
| resqlite selectBytes() | 0.025 | 0.026 | 0.025 | 0.026 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.194 | 0.217 | 0.194 | 0.217 |
| sqlite3 + jsonEncode | 0.256 | 0.271 | 0.256 | 0.271 |
| sqlite_async + jsonEncode | 0.263 | 0.290 | 0.263 | 0.290 |
| drift + jsonEncode | 0.315 | 0.373 | 0.315 | 0.373 |
| resqlite selectBytes() | 0.043 | 0.046 | 0.043 | 0.046 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.898 | 0.965 | 0.898 | 0.965 |
| sqlite3 + jsonEncode | 1.231 | 1.312 | 1.231 | 1.312 |
| sqlite_async + jsonEncode | 1.260 | 1.419 | 1.260 | 1.419 |
| drift + jsonEncode | 1.646 | 2.012 | 1.646 | 2.012 |
| resqlite selectBytes() | 0.179 | 0.186 | 0.179 | 0.186 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.783 | 1.884 | 1.783 | 1.884 |
| sqlite3 + jsonEncode | 2.540 | 4.725 | 2.540 | 4.725 |
| sqlite_async + jsonEncode | 2.478 | 3.902 | 2.478 | 3.902 |
| drift + jsonEncode | 3.217 | 5.230 | 3.217 | 5.230 |
| resqlite selectBytes() | 0.340 | 0.377 | 0.340 | 0.377 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.741 | 6.685 | 3.741 | 6.685 |
| sqlite3 + jsonEncode | 5.294 | 8.626 | 5.294 | 8.626 |
| sqlite_async + jsonEncode | 5.229 | 8.779 | 5.229 | 8.779 |
| drift + jsonEncode | 6.210 | 10.476 | 6.210 | 10.476 |
| resqlite selectBytes() | 0.917 | 2.130 | 0.917 | 2.130 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 10.535 | 13.863 | 10.535 | 13.863 |
| sqlite3 + jsonEncode | 14.173 | 21.353 | 14.173 | 21.353 |
| sqlite_async + jsonEncode | 14.067 | 17.856 | 14.067 | 17.856 |
| drift + jsonEncode | 18.671 | 25.014 | 18.671 | 25.014 |
| resqlite selectBytes() | 1.977 | 3.681 | 1.977 | 3.681 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 21.710 | 25.427 | 21.710 | 25.427 |
| sqlite3 + jsonEncode | 29.353 | 37.509 | 29.353 | 37.509 |
| sqlite_async + jsonEncode | 32.107 | 35.241 | 32.107 | 35.241 |
| drift + jsonEncode | 38.916 | 50.591 | 38.916 | 50.591 |
| resqlite selectBytes() | 3.975 | 5.554 | 3.975 | 5.554 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 45.889 | 56.167 | 45.889 | 56.167 |
| sqlite3 + jsonEncode | 65.373 | 78.113 | 65.373 | 78.113 |
| sqlite_async + jsonEncode | 68.618 | 79.895 | 68.618 | 79.895 |
| drift + jsonEncode | 82.525 | 102.220 | 82.525 | 102.220 |
| resqlite selectBytes() | 9.520 | 12.946 | 9.520 | 12.946 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.29 | 0.32 | 0.29 |
| sqlite_async | 0.93 | 1.16 | 0.93 |
| drift | 1.55 | 1.88 | 1.55 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.31 | 0.34 | 0.15 |
| sqlite_async | 1.28 | 1.58 | 0.64 |
| drift | 2.58 | 2.96 | 1.29 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.36 | 0.41 | 0.09 |
| sqlite_async | 2.12 | 2.89 | 0.53 |
| drift | 5.05 | 5.57 | 1.26 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.68 | 1.14 | 0.09 |
| sqlite_async | 4.55 | 5.27 | 0.57 |
| drift | 10.33 | 10.99 | 1.29 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 136446 |
| resqlite per query | 0.007 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 136446 | 133706..137335 | 1.3 | 2.7 |
| sqlite3 | 187328 | 185007..196804 | 3.1 | 6.4 |
| sqlite_async | 48546 | 41976..51080 | 9.4 | 21.7 |
| drift | 44616 | 32744..44697 | 13.4 | 11.3 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.527 | 14.818 | 14.527 | 14.818 |
| sqlite_async | 35.516 | 36.921 | 35.516 | 36.921 |
| drift | 52.937 | 57.677 | 52.937 | 57.677 |
| sqlite3 (no cache) | 23.970 | 26.322 | 23.970 | 26.322 |
| sqlite3 (cached stmt) | 23.336 | 24.329 | 23.336 | 24.329 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.956 | 2.585 | 1.956 | 2.585 |
| sqlite3 execute() | 1.021 | 1.789 | 1.021 | 1.789 |
| sqlite_async execute() | 2.988 | 3.878 | 2.988 | 3.878 |
| drift execute() | 2.807 | 3.352 | 2.807 | 3.352 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.054 | 0.058 | 0.054 | 0.058 |
| sqlite3 executeBatch() | 0.050 | 0.056 | 0.050 | 0.056 |
| sqlite_async executeBatch() | 0.093 | 0.103 | 0.093 | 0.103 |
| drift executeBatch() | 0.117 | 0.135 | 0.117 | 0.135 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.435 | 0.485 | 0.435 | 0.485 |
| sqlite3 executeBatch() | 0.432 | 0.455 | 0.432 | 0.455 |
| sqlite_async executeBatch() | 0.516 | 0.561 | 0.516 | 0.561 |
| drift executeBatch() | 0.673 | 0.780 | 0.673 | 0.780 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.275 | 6.838 | 4.275 | 6.838 |
| sqlite3 executeBatch() | 4.137 | 4.903 | 4.137 | 4.903 |
| sqlite_async executeBatch() | 4.933 | 5.300 | 4.933 | 5.300 |
| drift executeBatch() | 6.211 | 7.416 | 6.211 | 7.416 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.054 | 0.058 | 0.054 | 0.058 |
| sqlite_async writeTransaction() | 0.084 | 0.146 | 0.084 | 0.146 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.086 | 0.119 | 0.086 | 0.119 |
| resqlite tx.execute() loop | 0.767 | 0.963 | 0.767 | 0.963 |
| sqlite_async tx.execute() loop | 1.475 | 1.812 | 1.475 | 1.812 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.473 | 0.522 | 0.473 | 0.522 |
| resqlite tx.execute() loop | 7.961 | 10.289 | 7.961 | 10.289 |
| sqlite_async tx.execute() loop | 10.292 | 11.782 | 10.292 | 11.782 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.105 | 0.111 | 0.105 | 0.111 |
| sqlite_async tx.getAll() | 0.204 | 0.233 | 0.204 | 0.233 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.185 | 0.194 | 0.185 | 0.194 |
| sqlite_async tx.getAll() | 0.357 | 0.458 | 0.357 | 0.458 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.026 | 0.029 | 0.026 | 0.029 |
| sqlite_async watch() | 0.111 | 0.136 | 0.111 | 0.136 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.042 | 0.059 | 0.042 | 0.059 |
| sqlite_async | 0.065 | 0.070 | 0.065 | 0.070 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.190 | 0.246 | 0.190 | 0.246 |
| sqlite_async | 0.651 | 2.402 | 0.651 | 2.402 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.213 | 0.289 | 0.213 | 0.289 |
| sqlite_async | 0.292 | 0.421 | 0.292 | 0.421 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.446 | 1.446 | 1.446 | 1.446 |
| sqlite_async | 9.259 | 9.259 | 9.259 | 9.259 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.479 | 4.146 | 3.479 | 4.146 |
| sqlite_async | 5.553 | 6.473 | 5.553 | 6.473 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.538 | 0.759 | 0.538 | 0.759 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 5.663 | 6.133 | 5.663 | 6.133 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. On resqlite's main branch this ratio is driven toward 0 by experiment 075 (C-side result-hash short-circuit), not by writer-side column-tracking (exp 052 is not implemented). The two mechanisms are indistinguishable on this read-side benchmark.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 76.7 | 0.000 |
| sqlite_async | 3129 | 916.0 | 0.847 |
| drift | 5000 | 1058.8 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 68.0 | 0.000 |
| sqlite_async | 3693 | 923.0 | 0.847 |
| drift | 5000 | 1077.9 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 223.51 | 223.84 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 441.38 | 444.02 | 0.00 | 0.00 | 1111 | 3 |
| drift stream() | 554.23 | 569.47 | 0.00 | 0.02 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.025 | 0.048 | 0.000 | 0.000 |
| sqlite3 | 0.022 | 0.037 | 0.022 | 0.037 |
| sqlite_async | 0.039 | 0.058 | 0.000 | 0.000 |
| drift | 0.041 | 0.067 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.018 | 0.043 | 0.000 | 0.000 |
| sqlite3 | 0.014 | 0.020 | 0.014 | 0.020 |
| sqlite_async | 0.030 | 0.040 | 0.000 | 0.000 |
| drift | 0.032 | 0.051 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.027 | 0.041 | 0.000 | 0.000 |
| sqlite3 | 0.030 | 0.034 | 0.030 | 0.034 |
| sqlite_async | 0.056 | 0.069 | 0.000 | 0.000 |
| drift | 0.054 | 0.063 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.009 | 0.020 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.021 | 0.026 | 0.000 | 0.000 |
| drift | 0.020 | 0.029 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.038 | 0.043 | 0.001 | 0.001 |
| sqlite3 | 0.062 | 0.065 | 0.062 | 0.065 |
| sqlite_async | 0.083 | 0.090 | 0.001 | 0.001 |
| drift | 0.088 | 0.092 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 108.887 | 109.378 | 0.000 | 0.000 | 0 |
| sqlite_async | 218.485 | 218.701 | 0.000 | 0.000 | 40 |
| drift | 229.229 | 240.722 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 240.09 | 240.09 | 0.00 | 0.00 | 13.51 | 226.57 | 0 |
| sqlite_async | 491.16 | 491.16 | 1.60 | 1.60 | 24.63 | 466.53 | 1160 |
| drift | 1814.09 | 1814.09 | 0.16 | 0.16 | 13.63 | 1800.53 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 3.84 | 10.50 | 1.77..7.67 | ±2.95 |
| sqlite3 select() | 2.95 | 9.89 | 2.27..8.88 | ±3.30 |
| sqlite_async select() | 1.00 | 3.36 | 1.00..1.53 | ±0.27 |
| drift select() | 6.70 | 74.17 | 0.00..17.45 | ±8.73 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 1.38 | 8.00 | 0.00..6.00 | ±3.00 |
| resqlite + jsonEncode | 0.00 | 9.22 | 0.00..4.22 | ±2.11 |
| sqlite3 + jsonEncode | 2.20 | 39.63 | 0.00..25.75 | ±12.88 |
| sqlite_async + jsonEncode | 1.47 | 59.47 | 0.00..15.13 | ±7.56 |
| drift + jsonEncode | 0.00 | 8.83 | 0.00..4.80 | ±2.40 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.00 | 33.98 | 0.00..29.50 | ±14.75 |
| sqlite3 executeBatch() | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.02 | 0.50 | 0.00..0.02 | ±0.01 |
| drift batch() | 0.00 | 2.48 | 0.00..0.03 | ±0.02 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.13 | 0.00..0.06 | ±0.03 |
| sqlite_async watch() | 0.02 | 0.52 | 0.00..0.39 | ±0.20 |

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
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.03 | 0.03..0.03 | 3.8% | 7.7% | 3.8% | moderate |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02..0.03 | 11.4% | 22.7% | 4.5% | moderate |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02..0.02 | 6.2% | 12.5% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.30 | 0.29..0.33 | 6.7% | 13.3% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.30 | 0.29..0.33 | 6.7% | 13.3% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.32 | 0.31..0.66 | 54.7% | 109.4% | 3.1% | moderate |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.16 | 0.15..0.33 | 56.3% | 112.5% | 6.3% | moderate |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.37 | 0.36..0.57 | 28.4% | 56.8% | 2.7% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.09 | 0.09..0.14 | 27.8% | 55.6% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.70 | 0.68..1.21 | 37.9% | 75.7% | 2.9% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.09 | 0.09..0.15 | 33.3% | 66.7% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.04 | 2.6% | 5.3% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 150.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 108.25 | 107.69..108.89 | 0.6% | 1.1% | 0.3% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 240.09 | 237.18..249.09 | 2.5% | 5.0% | 1.2% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 222.78 | 222.08..225.58 | 0.8% | 1.6% | 0.3% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 14.53 | 14.27..14.72 | 1.6% | 3.1% | 1.3% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 14.53 | 14.27..14.72 | 1.6% | 3.1% | 1.3% | stable |
| Point Query Throughput / resqlite qps | 135131.00 | 121508.00..139902.00 | 6.8% | 13.6% | 3.5% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.02 | 37.5% | 75.0% | 8.3% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.04 | 21.7% | 43.3% | 13.3% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.04 | 21.7% | 43.3% | 13.3% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 50.0% | 100.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.03 | 100.0% | 200.0% | 9.1% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.03 | 100.0% | 200.0% | 9.1% | noisy |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.04..0.06 | 10.6% | 21.3% | 4.3% | moderate |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.20 | 0.19..0.20 | 2.5% | 5.0% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.20 | 0.19..0.20 | 2.5% | 5.0% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 5.6% | 11.1% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.05 | 0.04..0.05 | 8.5% | 17.0% | 8.5% | noisy |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.05 | 0.04..0.05 | 8.5% | 17.0% | 8.5% | noisy |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.38 | 0.38..0.40 | 2.5% | 5.0% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.81 | 1.77..1.91 | 3.7% | 7.5% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.81 | 1.77..1.91 | 3.7% | 7.5% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09..0.09 | 1.7% | 3.5% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.35 | 0.34..0.37 | 4.2% | 8.3% | 2.6% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.35 | 0.34..0.37 | 4.2% | 8.3% | 2.6% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.77 | 4.44..6.37 | 20.2% | 40.4% | 3.3% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 21.71 | 20.83..25.35 | 10.4% | 20.8% | 2.6% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 21.71 | 20.83..25.35 | 10.4% | 20.8% | 2.6% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.89 | 0.84..0.90 | 3.5% | 7.1% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 3.89 | 3.77..4.05 | 3.7% | 7.3% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 3.89 | 3.77..4.05 | 3.7% | 7.3% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.80 | 0.78..0.82 | 2.9% | 5.8% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.84 | 3.69..3.92 | 3.0% | 6.1% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.84 | 3.69..3.92 | 3.0% | 6.1% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.17 | 0.17..0.17 | 1.2% | 2.3% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.86 | 0.77..0.97 | 12.0% | 24.0% | 10.5% | noisy |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.86 | 0.77..0.97 | 12.0% | 24.0% | 10.5% | noisy |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 11.22 | 10.71..13.08 | 10.5% | 21.1% | 3.7% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 44.29 | 40.70..45.89 | 5.9% | 11.7% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 44.29 | 40.70..45.89 | 5.9% | 11.7% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.76 | 1.68..1.82 | 3.9% | 7.7% | 3.3% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 7.58 | 7.49..9.52 | 13.4% | 26.8% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 7.58 | 7.49..9.52 | 13.4% | 26.8% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03..0.04 | 14.8% | 29.6% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.10..0.12 | 9.0% | 17.9% | 3.8% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.11 | 0.10..0.12 | 9.0% | 17.9% | 3.8% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.01 | 12.5% | 25.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.03..0.03 | 11.1% | 22.2% | 7.4% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.03..0.03 | 11.1% | 22.2% | 7.4% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.19 | 0.19..0.20 | 3.6% | 7.2% | 2.6% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.90 | 0.89..0.94 | 2.6% | 5.1% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.90 | 0.89..0.94 | 2.6% | 5.1% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04..0.04 | 3.5% | 7.0% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.18 | 0.18..0.19 | 2.2% | 4.3% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.18 | 0.18..0.19 | 2.2% | 4.3% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.23 | 2.20..3.06 | 19.4% | 38.9% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 10.54 | 9.72..13.09 | 16.0% | 31.9% | 4.0% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 10.54 | 9.72..13.09 | 16.0% | 31.9% | 4.0% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.43 | 0.42..0.45 | 3.6% | 7.1% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 1.98 | 1.88..2.45 | 14.4% | 28.8% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 1.98 | 1.88..2.45 | 14.4% | 28.8% | 2.3% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.10 | 0.10..0.11 | 4.4% | 8.8% | 2.0% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.04 | 0.03..0.04 | 14.3% | 28.6% | 2.9% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.30 | 0.30..0.31 | 1.8% | 3.7% | 1.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.10 | 0.10..0.10 | 1.5% | 3.1% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.29 | 0.28..0.32 | 5.1% | 10.2% | 3.1% | moderate |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.10 | 0.09..0.10 | 4.6% | 9.3% | 4.1% | moderate |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.56 | 0.54..0.66 | 10.7% | 21.4% | 3.0% | moderate |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.10 | 0.10..0.11 | 2.4% | 4.9% | 1.9% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.92 | 0.91..0.95 | 2.6% | 5.1% | 0.2% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.27 | 0.27..0.28 | 2.2% | 4.5% | 0.7% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.09 | 96.7% | 193.3% | 3.3% | moderate |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02..0.07 | 152.9% | 305.9% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.03 | 85.0% | 170.0% | 10.0% | noisy |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.19..0.25 | 13.2% | 26.4% | 1.5% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.16 | 0.15..0.18 | 9.6% | 19.1% | 1.9% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.06 | 13.6% | 27.3% | 2.3% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.81 | 1.72..1.88 | 4.5% | 9.1% | 2.9% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.47 | 1.43..1.53 | 3.5% | 7.0% | 2.9% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.36 | 0.35..0.37 | 3.1% | 6.2% | 1.7% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 23.20 | 20.52..23.63 | 6.7% | 13.4% | 1.8% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 15.02 | 14.87..15.74 | 2.9% | 5.8% | 1.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.79 | 3.78..3.94 | 2.1% | 4.1% | 0.4% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 16.7% | 33.3% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.09 | 280.8% | 561.5% | 7.7% | moderate |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 1050.0% | 2100.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.05..0.07 | 24.0% | 48.0% | 2.0% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 5.6% | 11.1% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.38 | 0.37..0.45 | 10.7% | 21.4% | 1.8% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.08..0.09 | 7.6% | 15.3% | 1.2% | stable |
| Select → Maps / 10000 rows / resqlite select() | 4.49 | 4.43..5.38 | 10.7% | 21.3% | 1.2% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.85 | 0.71..0.86 | 9.3% | 18.7% | 1.4% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.23 | 0.21..0.43 | 49.3% | 98.7% | 5.8% | moderate |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.23 | 0.21..0.43 | 49.3% | 98.7% | 5.8% | moderate |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.55 | 0.51..0.60 | 8.4% | 16.8% | 1.6% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.55 | 0.51..0.60 | 8.4% | 16.8% | 1.6% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03..0.06 | 64.8% | 129.6% | 3.7% | moderate |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03..0.06 | 64.8% | 129.6% | 3.7% | moderate |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.04..0.06 | 21.1% | 42.2% | 6.7% | moderate |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.04..0.06 | 21.1% | 42.2% | 6.7% | moderate |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.54 | 3.48..3.96 | 6.9% | 13.7% | 1.7% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.54 | 3.48..3.96 | 6.9% | 13.7% | 1.7% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.61 | 1.45..2.70 | 39.0% | 77.9% | 10.4% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.61 | 1.45..2.70 | 39.0% | 77.9% | 10.4% | noisy |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.29 | 5.66..6.31 | 5.1% | 10.3% | 0.3% | stable |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.29 | 5.66..6.31 | 5.1% | 10.3% | 0.3% | stable |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.19 | 0.19..0.21 | 6.2% | 12.4% | 1.6% | stable |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.19 | 0.19..0.21 | 6.2% | 12.4% | 1.6% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.05..0.07 | 9.6% | 19.3% | 5.3% | moderate |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.06 | 0.05..0.07 | 9.6% | 19.3% | 5.3% | moderate |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.45 | 0.43..0.47 | 4.3% | 8.5% | 2.7% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.45 | 0.43..0.47 | 4.3% | 8.5% | 2.7% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.35 | 4.28..4.59 | 3.6% | 7.3% | 1.7% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.35 | 4.28..4.59 | 3.6% | 7.3% | 1.7% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.72 | 0.60..0.77 | 11.7% | 23.4% | 5.8% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.72 | 0.60..0.77 | 11.7% | 23.4% | 5.8% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.08 | 0.07..0.09 | 14.3% | 28.6% | 9.1% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.08 | 0.07..0.09 | 14.3% | 28.6% | 9.1% | noisy |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 7.23 | 5.62..7.96 | 16.2% | 32.4% | 10.1% | noisy |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 7.23 | 5.62..7.96 | 16.2% | 32.4% | 10.1% | noisy |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.50 | 0.43..0.53 | 9.9% | 19.7% | 5.4% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.50 | 0.43..0.53 | 9.9% | 19.7% | 5.4% | moderate |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05..0.06 | 8.3% | 16.7% | 7.4% | moderate |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05..0.06 | 8.3% | 16.7% | 7.4% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.78 | 1.62..2.20 | 16.2% | 32.5% | 8.7% | noisy |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.78 | 1.62..2.20 | 16.2% | 32.5% | 8.7% | noisy |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.18..0.19 | 1.9% | 3.7% | 1.6% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.18..0.19 | 1.9% | 3.7% | 1.6% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.11 | 0.10..0.11 | 2.8% | 5.7% | 0.9% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.11 | 0.10..0.11 | 2.8% | 5.7% | 0.9% | stable |


## Comparison vs Previous Run

Previous: `2026-04-25T14-06-42-baseline-for-exp100.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.02 | 0.03 | +0.00 | ±12% / ±0.02 ms | 3.8% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02 | +0.00 | ±14% / ±0.02 ms | 11.4% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.02 | +0.00 | ±10% / ±0.02 ms | 6.2% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.30 | +0.00 | ±10% / ±0.03 ms | 6.7% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.30 | +0.00 | ±10% / ±0.03 ms | 6.7% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.35 | 0.32 | -0.03 | ±55% / ±0.19 ms | 54.7% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.17 | 0.16 | -0.01 | ±56% / ±0.10 ms | 56.3% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.37 | 0.37 | +0.00 | ±28% / ±0.10 ms | 28.4% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.09 | 0.09 | +0.00 | ±28% / ±0.03 ms | 27.8% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.68 | 0.70 | +0.02 | ±38% / ±0.26 ms | 37.9% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.09 | 0.09 | +0.00 | ±33% / ±0.03 ms | 33.3% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 2.6% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±150% / ±0.02 ms | 150.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 108.43 | 108.25 | -0.18 | ±10% / ±10.84 ms | 0.6% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 236.54 | 240.09 | +3.55 | ±10% / ±24.01 ms | 2.5% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 216.78 | 222.78 | +6.00 | ±10% / ±22.28 ms | 0.8% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.56 | 14.53 | -0.03 | ±10% / ±1.46 ms | 1.6% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.56 | 14.53 | -0.03 | ±10% / ±1.46 ms | 1.6% | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 146594.00 | 135131.00 | -11463.00 | ±11% / ±15527.15 ms | 6.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01 | +0.00 | ±38% / ±0.02 ms | 37.5% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | -0.00 | ±40% / ±0.02 ms | 21.7% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.03 | -0.00 | ±40% / ±0.02 ms | 21.7% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±50% / ±0.02 ms | 50.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±100% / ±0.02 ms | 100.0% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±100% / ±0.02 ms | 100.0% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05 | -0.00 | ±13% / ±0.02 ms | 10.6% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.20 | 0.20 | +0.00 | ±10% / ±0.02 ms | 2.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.20 | 0.20 | +0.00 | ±10% / ±0.02 ms | 2.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 5.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.05 | +0.00 | ±26% / ±0.02 ms | 8.5% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.05 | +0.00 | ±26% / ±0.02 ms | 8.5% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.39 | 0.38 | -0.01 | ±10% / ±0.04 ms | 2.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.82 | 1.81 | -0.01 | ±10% / ±0.18 ms | 3.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.82 | 1.81 | -0.01 | ±10% / ±0.18 ms | 3.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09 | -0.00 | ±10% / ±0.02 ms | 1.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.35 | -0.00 | ±10% / ±0.04 ms | 4.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.35 | -0.00 | ±10% / ±0.04 ms | 4.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.99 | 4.77 | -0.22 | ±20% / ±1.01 ms | 20.2% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 23.81 | 21.71 | -2.10 | ±10% / ±2.48 ms | 10.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 23.81 | 21.71 | -2.10 | ±10% / ±2.48 ms | 10.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.90 | 0.89 | -0.00 | ±10% / ±0.09 ms | 3.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.88 | 3.89 | +0.01 | ±10% / ±0.39 ms | 3.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.88 | 3.89 | +0.01 | ±10% / ±0.39 ms | 3.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.81 | 0.80 | -0.02 | ±10% / ±0.08 ms | 2.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.85 | 3.84 | -0.01 | ±10% / ±0.38 ms | 3.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.85 | 3.84 | -0.01 | ±10% / ±0.38 ms | 3.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.17 | 0.17 | +0.00 | ±10% / ±0.02 ms | 1.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.77 | 0.86 | +0.09 | ±31% / ±0.27 ms | 12.0% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.77 | 0.86 | +0.09 | ±31% / ±0.27 ms | 12.0% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 11.76 | 11.22 | -0.54 | ±11% / ±1.30 ms | 10.5% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 43.44 | 44.29 | +0.85 | ±10% / ±4.43 ms | 5.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 43.44 | 44.29 | +0.85 | ±10% / ±4.43 ms | 5.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.74 | 1.76 | +0.02 | ±10% / ±0.18 ms | 3.9% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.02 | 7.58 | -0.44 | ±13% / ±1.08 ms | 13.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.02 | 7.58 | -0.44 | ±13% / ±1.08 ms | 13.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03 | -0.00 | ±15% / ±0.02 ms | 14.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.11 | +0.00 | ±11% / ±0.02 ms | 9.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.10 | 0.11 | +0.00 | ±11% / ±0.02 ms | 9.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±13% / ±0.02 ms | 12.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | +0.00 | ±22% / ±0.02 ms | 11.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | +0.00 | ±22% / ±0.02 ms | 11.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.20 | 0.19 | -0.01 | ±10% / ±0.02 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.89 | 0.90 | +0.01 | ±10% / ±0.09 ms | 2.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.89 | 0.90 | +0.01 | ±10% / ±0.09 ms | 2.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 3.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.18 | +0.01 | ±10% / ±0.02 ms | 2.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.18 | +0.01 | ±10% / ±0.02 ms | 2.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.17 | 2.23 | +0.06 | ±19% / ±0.43 ms | 19.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.23 | 10.54 | +0.30 | ±16% / ±1.68 ms | 16.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.23 | 10.54 | +0.30 | ±16% / ±1.68 ms | 16.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.43 | 0.43 | +0.00 | ±10% / ±0.04 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 2.33 | 1.98 | -0.36 | ±14% / ±0.34 ms | 14.4% | stable | 🟢 Win (-15%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 2.33 | 1.98 | -0.36 | ±14% / ±0.34 ms | 14.4% | stable | 🟢 Win (-15%) |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 4.4% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.04 | 0.04 | -0.00 | ±14% / ±0.02 ms | 14.3% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.30 | 0.30 | +0.00 | ±10% / ±0.03 ms | 1.8% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 1.5% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.31 | 0.29 | -0.01 | ±10% / ±0.03 ms | 5.1% | moderate | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.10 | 0.10 | -0.00 | ±12% / ±0.02 ms | 4.6% | moderate | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.60 | 0.56 | -0.04 | ±11% / ±0.06 ms | 10.7% | moderate | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 2.4% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.93 | 0.92 | -0.02 | ±10% / ±0.09 ms | 2.6% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.28 | 0.27 | -0.01 | ±10% / ±0.03 ms | 2.2% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±97% / ±0.03 ms | 96.7% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.01 | 0.02 | +0.00 | ±153% / ±0.03 ms | 152.9% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | -0.00 | ±85% / ±0.02 ms | 85.0% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.19 | 0.20 | +0.01 | ±13% / ±0.03 ms | 13.2% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.15 | 0.16 | +0.01 | ±10% / ±0.02 ms | 9.6% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04 | +0.00 | ±14% / ±0.02 ms | 13.6% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.75 | 1.81 | +0.06 | ±10% / ±0.18 ms | 4.5% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.46 | 1.47 | +0.01 | ±10% / ±0.15 ms | 3.5% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.37 | 0.36 | -0.01 | ±10% / ±0.04 ms | 3.1% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.85 | 23.20 | +2.35 | ±10% / ±2.32 ms | 6.7% | stable | 🔴 Regression (+11%) |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 15.43 | 15.02 | -0.41 | ±10% / ±1.54 ms | 2.9% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.77 | 3.79 | +0.03 | ±10% / ±0.38 ms | 2.1% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±17% / ±0.02 ms | 16.7% | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | +0.00 | ±281% / ±0.04 ms | 280.8% | moderate | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±1050% / ±0.02 ms | 1050.0% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.06 | 0.05 | -0.01 | ±24% / ±0.02 ms | 24.0% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 5.6% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.40 | 0.38 | -0.02 | ±11% / ±0.04 ms | 10.7% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.09 | -0.00 | ±10% / ±0.02 ms | 7.6% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 4.53 | 4.49 | -0.04 | ±11% / ±0.48 ms | 10.7% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.86 | 0.85 | -0.01 | ±10% / ±0.09 ms | 9.3% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.21 | 0.23 | +0.01 | ±49% / ±0.11 ms | 49.3% | moderate | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.21 | 0.23 | +0.01 | ±49% / ±0.11 ms | 49.3% | moderate | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.53 | 0.55 | +0.02 | ±10% / ±0.05 ms | 8.4% | stable | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.53 | 0.55 | +0.02 | ±10% / ±0.05 ms | 8.4% | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | +0.00 | ±65% / ±0.02 ms | 64.8% | moderate | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03 | +0.00 | ±65% / ±0.02 ms | 64.8% | moderate | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.06 | 0.04 | -0.02 | ±21% / ±0.02 ms | 21.1% | moderate | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.06 | 0.04 | -0.02 | ±21% / ±0.02 ms | 21.1% | moderate | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.55 | 3.54 | -0.01 | ±10% / ±0.35 ms | 6.9% | stable | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.55 | 3.54 | -0.01 | ±10% / ±0.35 ms | 6.9% | stable | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.67 | 1.61 | -0.05 | ±39% / ±0.65 ms | 39.0% | noisy | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.67 | 1.61 | -0.05 | ±39% / ±0.65 ms | 39.0% | noisy | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 7.72 | 6.29 | -1.43 | ±10% / ±0.77 ms | 5.1% | stable | 🟢 Win (-19%) |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 7.72 | 6.29 | -1.43 | ±10% / ±0.77 ms | 5.1% | stable | 🟢 Win (-19%) |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.20 | 0.19 | -0.01 | ±10% / ±0.02 ms | 6.2% | stable | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.20 | 0.19 | -0.01 | ±10% / ±0.02 ms | 6.2% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | -0.00 | ±16% / ±0.02 ms | 9.6% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | -0.00 | ±16% / ±0.02 ms | 9.6% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.45 | 0.45 | -0.00 | ±10% / ±0.05 ms | 4.3% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.45 | 0.45 | -0.00 | ±10% / ±0.05 ms | 4.3% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.53 | 4.35 | -0.18 | ±10% / ±0.45 ms | 3.6% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.53 | 4.35 | -0.18 | ±10% / ±0.45 ms | 3.6% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.83 | 0.72 | -0.11 | ±18% / ±0.15 ms | 11.7% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.83 | 0.72 | -0.11 | ±18% / ±0.15 ms | 11.7% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.09 | 0.08 | -0.02 | ±27% / ±0.03 ms | 14.3% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.09 | 0.08 | -0.02 | ±27% / ±0.03 ms | 14.3% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 7.75 | 7.23 | -0.52 | ±30% / ±2.35 ms | 16.2% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 7.75 | 7.23 | -0.52 | ±30% / ±2.35 ms | 16.2% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.49 | 0.50 | +0.01 | ±16% / ±0.08 ms | 9.9% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.49 | 0.50 | +0.01 | ±16% / ±0.08 ms | 9.9% | moderate | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.05 | +0.00 | ±22% / ±0.02 ms | 8.3% | moderate | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.05 | +0.00 | ±22% / ±0.02 ms | 8.3% | moderate | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 2.46 | 1.78 | -0.68 | ±26% / ±0.64 ms | 16.2% | noisy | 🟢 Win (-28%) |
| Write Performance / Single Inserts (100 sequential) / res... | 2.46 | 1.78 | -0.68 | ±26% / ±0.64 ms | 16.2% | noisy | 🟢 Win (-28%) |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.20 | 0.19 | -0.01 | ±10% / ±0.02 ms | 1.9% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.20 | 0.19 | -0.01 | ±10% / ±0.02 ms | 1.9% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.12 | 0.11 | -0.02 | ±10% / ±0.02 ms | 2.8% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.12 | 0.11 | -0.02 | ±10% / ±0.02 ms | 2.8% | stable | ⚪ Within noise |

**Summary:** 6 wins, 1 regressions, 146 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.31 | 0.00 | -0.31 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 0.00 | 0.00 | +0.00 MB | ±14.75 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.02 | +0.02 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 7.41 | 0.00 | -7.41 MB | ±2.40 MB | 🟢 Win (-7.41 MB) |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 0.00 | 0.00 | +0.00 MB | ±2.11 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 1.38 | +1.38 MB | ±3.00 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 9.14 | 2.20 | -6.94 MB | ±12.88 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 1.47 | +1.47 MB | ±7.56 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 5.30 | 6.70 | +1.40 MB | ±8.73 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / resqlite select() | 5.00 | 3.84 | -1.16 MB | ±2.95 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite3 select() | 4.48 | 2.95 | -1.53 MB | ±3.30 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 0.86 | 1.00 | +0.14 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.02 | 0.06 | +0.04 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.02 | +0.02 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 1 wins, 0 regressions, 14 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 2551 | 3129 | +578 | ±100 | 🔴 More re-emits (+578) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 3277 | 3693 | +416 | ±100 | 🔴 More re-emits (+416) |

**Granularity summary:** 0 fewer-re-emit, 2 more-re-emit, 4 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


