# resqlite Benchmark Results

Generated: 2026-06-16T15:30:05.820712

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp179-single-row-ascii`
- Repeats: `5`
- Runtime: `dart-vm / Dart 3.11.5`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `exp-179-single-pass-ascii-batch @ d51ff4023b8b (dirty)`
- Comparison baseline: `2026-06-16T15-19-02-baseline-for-exp179.md`
- Comparison mode: `explicit`
- Comparison baseline compatibility: `compatible`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.011 | 0.012 | 0.000 | 0.000 |
| sqlite3 select() | 0.015 | 0.016 | 0.015 | 0.016 |
| sqlite_async select() | 0.031 | 0.035 | 0.001 | 0.002 |
| drift select() | 0.037 | 0.039 | 0.001 | 0.001 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.043 | 0.044 | 0.005 | 0.005 |
| sqlite3 select() | 0.117 | 0.123 | 0.117 | 0.123 |
| sqlite_async select() | 0.125 | 0.129 | 0.010 | 0.010 |
| drift select() | 0.178 | 0.187 | 0.010 | 0.011 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.341 | 0.350 | 0.051 | 0.052 |
| sqlite3 select() | 1.136 | 1.165 | 1.136 | 1.165 |
| sqlite_async select() | 1.061 | 1.162 | 0.094 | 0.100 |
| drift select() | 1.554 | 1.857 | 0.091 | 0.097 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.139 | 10.209 | 0.521 | 0.845 |
| sqlite3 select() | 14.049 | 16.916 | 14.049 | 16.916 |
| sqlite_async select() | 12.238 | 14.878 | 0.930 | 2.212 |
| drift select() | 22.448 | 25.320 | 0.942 | 1.232 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.026 | 0.030 | 0.015 | 0.017 |
| sqlite3 + jsonEncode | 0.030 | 0.032 | 0.030 | 0.032 |
| sqlite_async + jsonEncode | 0.045 | 0.048 | 0.016 | 0.016 |
| drift + jsonEncode | 0.054 | 0.056 | 0.016 | 0.019 |
| resqlite selectBytes() | 0.010 | 0.011 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.192 | 0.201 | 0.153 | 0.159 |
| sqlite3 + jsonEncode | 0.261 | 0.275 | 0.261 | 0.275 |
| sqlite_async + jsonEncode | 0.269 | 0.295 | 0.150 | 0.164 |
| drift + jsonEncode | 0.317 | 0.340 | 0.151 | 0.156 |
| resqlite selectBytes() | 0.041 | 0.044 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.741 | 3.635 | 1.442 | 2.284 |
| sqlite3 + jsonEncode | 2.512 | 3.232 | 2.512 | 3.232 |
| sqlite_async + jsonEncode | 2.415 | 3.653 | 1.449 | 2.212 |
| drift + jsonEncode | 2.941 | 3.292 | 1.444 | 1.770 |
| resqlite selectBytes() | 0.354 | 0.364 | 0.000 | 0.000 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 21.616 | 24.040 | 14.771 | 18.130 |
| sqlite3 + jsonEncode | 29.165 | 35.209 | 29.165 | 35.209 |
| sqlite_async + jsonEncode | 27.417 | 34.207 | 14.822 | 16.547 |
| drift + jsonEncode | 38.333 | 42.140 | 14.938 | 20.011 |
| resqlite selectBytes() | 3.476 | 3.527 | 0.000 | 0.000 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.087 | 0.090 | 0.023 | 0.024 |
| sqlite3 | 0.318 | 0.342 | 0.318 | 0.342 |
| sqlite_async | 0.353 | 0.365 | 0.032 | 0.034 |
| drift | 0.579 | 0.620 | 0.032 | 0.035 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.841 | 0.879 | 0.200 | 0.207 |
| sqlite3 | 3.230 | 3.756 | 3.230 | 3.756 |
| sqlite_async | 2.895 | 3.277 | 0.229 | 0.238 |
| drift | 4.538 | 5.718 | 0.231 | 0.238 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.486 | 0.517 | 0.062 | 0.065 |
| sqlite3 | 1.449 | 1.505 | 1.449 | 1.505 |
| sqlite_async | 1.352 | 1.663 | 0.083 | 0.085 |
| drift | 1.891 | 2.152 | 0.082 | 0.083 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.255 | 0.259 | 0.060 | 0.063 |
| sqlite3 | 0.987 | 1.027 | 0.987 | 1.027 |
| sqlite_async | 0.922 | 0.964 | 0.082 | 0.085 |
| drift | 1.413 | 1.462 | 0.081 | 0.083 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.258 | 0.266 | 0.060 | 0.062 |
| sqlite3 | 0.960 | 1.005 | 0.960 | 1.005 |
| sqlite_async | 0.927 | 0.942 | 0.082 | 0.083 |
| drift | 1.411 | 1.678 | 0.081 | 0.086 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.011 | 0.012 | 0.000 | 0.000 |
| sqlite3 | 0.015 | 0.016 | 0.015 | 0.016 |
| sqlite_async | 0.029 | 0.030 | 0.001 | 0.001 |
| drift | 0.035 | 0.037 | 0.001 | 0.001 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.025 | 0.026 | 0.003 | 0.003 |
| sqlite3 | 0.060 | 0.062 | 0.060 | 0.062 |
| sqlite_async | 0.072 | 0.076 | 0.004 | 0.004 |
| drift | 0.102 | 0.103 | 0.004 | 0.004 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.044 | 0.048 | 0.005 | 0.006 |
| sqlite3 | 0.124 | 0.129 | 0.124 | 0.129 |
| sqlite_async | 0.126 | 0.130 | 0.007 | 0.008 |
| drift | 0.175 | 0.183 | 0.007 | 0.008 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.176 | 0.180 | 0.026 | 0.029 |
| sqlite3 | 0.560 | 0.574 | 0.560 | 0.574 |
| sqlite_async | 0.518 | 0.535 | 0.035 | 0.036 |
| drift | 0.772 | 0.780 | 0.034 | 0.035 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.338 | 0.351 | 0.052 | 0.053 |
| sqlite3 | 1.115 | 1.133 | 1.115 | 1.133 |
| sqlite_async | 1.016 | 1.045 | 0.069 | 0.072 |
| drift | 1.529 | 1.565 | 0.068 | 0.070 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.710 | 0.737 | 0.104 | 0.109 |
| sqlite3 | 2.226 | 2.696 | 2.226 | 2.696 |
| sqlite_async | 2.031 | 2.376 | 0.138 | 0.143 |
| drift | 3.063 | 3.471 | 0.137 | 0.142 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.980 | 5.382 | 0.259 | 0.380 |
| sqlite3 | 5.634 | 6.991 | 5.634 | 6.991 |
| sqlite_async | 5.185 | 5.800 | 0.347 | 0.388 |
| drift | 8.173 | 8.297 | 0.343 | 0.346 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.984 | 8.779 | 0.515 | 0.669 |
| sqlite3 | 14.019 | 16.973 | 14.019 | 16.973 |
| sqlite_async | 11.040 | 11.881 | 0.694 | 0.711 |
| drift | 18.573 | 26.900 | 0.718 | 1.064 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 10.067 | 16.176 | 1.020 | 1.097 |
| sqlite3 | 32.735 | 36.113 | 32.735 | 36.113 |
| sqlite_async | 34.038 | 37.695 | 1.431 | 4.638 |
| drift | 52.515 | 63.760 | 1.476 | 2.963 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.031 | 0.035 | 0.031 | 0.035 |
| sqlite3 + jsonEncode | 0.032 | 0.035 | 0.032 | 0.035 |
| sqlite_async + jsonEncode | 0.046 | 0.050 | 0.046 | 0.050 |
| drift + jsonEncode | 0.052 | 0.064 | 0.052 | 0.064 |
| resqlite selectBytes() | 0.011 | 0.012 | 0.011 | 0.012 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.101 | 0.130 | 0.101 | 0.130 |
| sqlite3 + jsonEncode | 0.134 | 0.144 | 0.134 | 0.144 |
| sqlite_async + jsonEncode | 0.148 | 0.158 | 0.148 | 0.158 |
| drift + jsonEncode | 0.171 | 0.178 | 0.171 | 0.178 |
| resqlite selectBytes() | 0.024 | 0.024 | 0.024 | 0.024 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.190 | 0.195 | 0.190 | 0.195 |
| sqlite3 + jsonEncode | 0.259 | 0.272 | 0.259 | 0.272 |
| sqlite_async + jsonEncode | 0.265 | 0.302 | 0.265 | 0.302 |
| drift + jsonEncode | 0.319 | 0.336 | 0.319 | 0.336 |
| resqlite selectBytes() | 0.041 | 0.044 | 0.041 | 0.044 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.889 | 0.929 | 0.889 | 0.929 |
| sqlite3 + jsonEncode | 1.306 | 1.671 | 1.306 | 1.671 |
| sqlite_async + jsonEncode | 1.240 | 2.005 | 1.240 | 2.005 |
| drift + jsonEncode | 1.483 | 3.402 | 1.483 | 3.402 |
| resqlite selectBytes() | 0.174 | 0.177 | 0.174 | 0.177 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.744 | 3.324 | 1.744 | 3.324 |
| sqlite3 + jsonEncode | 2.522 | 4.911 | 2.522 | 4.911 |
| sqlite_async + jsonEncode | 2.411 | 3.286 | 2.411 | 3.286 |
| drift + jsonEncode | 2.976 | 3.436 | 2.976 | 3.436 |
| resqlite selectBytes() | 0.347 | 0.363 | 0.347 | 0.363 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.852 | 7.526 | 3.852 | 7.526 |
| sqlite3 + jsonEncode | 5.359 | 9.271 | 5.359 | 9.271 |
| sqlite_async + jsonEncode | 5.145 | 9.406 | 5.145 | 9.406 |
| drift + jsonEncode | 6.246 | 9.305 | 6.246 | 9.305 |
| resqlite selectBytes() | 0.682 | 0.695 | 0.682 | 0.695 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 9.702 | 13.276 | 9.702 | 13.276 |
| sqlite3 + jsonEncode | 14.011 | 16.832 | 14.011 | 16.832 |
| sqlite_async + jsonEncode | 13.468 | 18.275 | 13.468 | 18.275 |
| drift + jsonEncode | 15.940 | 21.314 | 15.940 | 21.314 |
| resqlite selectBytes() | 1.664 | 1.785 | 1.664 | 1.785 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.228 | 23.891 | 20.228 | 23.891 |
| sqlite3 + jsonEncode | 28.613 | 34.168 | 28.613 | 34.168 |
| sqlite_async + jsonEncode | 30.511 | 32.022 | 30.511 | 32.022 |
| drift + jsonEncode | 35.932 | 39.337 | 35.932 | 39.337 |
| resqlite selectBytes() | 3.443 | 3.770 | 3.443 | 3.770 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 43.338 | 45.448 | 43.338 | 45.448 |
| sqlite3 + jsonEncode | 61.367 | 64.980 | 61.367 | 64.980 |
| sqlite_async + jsonEncode | 61.484 | 70.115 | 61.484 | 70.115 |
| drift + jsonEncode | 80.364 | 93.764 | 80.364 | 93.764 |
| resqlite selectBytes() | 7.050 | 7.319 | 7.050 | 7.319 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.29 | 0.30 | 0.29 |
| sqlite_async | 0.95 | 0.99 | 0.95 |
| drift | 1.46 | 1.49 | 1.46 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.33 | 0.15 |
| sqlite_async | 1.41 | 1.68 | 0.70 |
| drift | 2.68 | 3.13 | 1.34 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.36 | 0.64 | 0.09 |
| sqlite_async | 2.35 | 3.18 | 0.59 |
| drift | 5.21 | 5.67 | 1.30 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.69 | 1.16 | 0.09 |
| sqlite_async | 4.97 | 5.48 | 0.62 |
| drift | 10.38 | 10.86 | 1.30 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 149712 |
| resqlite per query | 0.007 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 149712 | 148287..150873 | 0.9 | 2.4 |
| sqlite3 | 201264 | 200594..201815 | 0.3 | 0.9 |
| sqlite_async | 52504 | 52214..52585 | 0.4 | 1.0 |
| drift | 47764 | 47671..48014 | 0.4 | 1.5 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.052 | 14.315 | 14.052 | 14.315 |
| sqlite_async | 36.442 | 37.037 | 36.442 | 37.037 |
| drift | 52.575 | 53.516 | 52.575 | 53.516 |
| sqlite3 (no cache) | 24.136 | 24.394 | 24.136 | 24.394 |
| sqlite3 (cached stmt) | 23.894 | 24.194 | 23.894 | 24.194 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.398 | 1.994 | 1.398 | 1.994 |
| sqlite3 execute() | 0.892 | 1.510 | 0.892 | 1.510 |
| sqlite_async execute() | 2.632 | 3.258 | 2.632 | 3.258 |
| drift execute() | 2.774 | 3.279 | 2.774 | 3.279 |

### Concurrent Single Inserts (100 concurrent)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite concurrent execute() | 1.001 | 1.359 | 1.001 | 1.359 |
| sqlite3 concurrent execute() | 0.883 | 1.486 | 0.883 | 1.486 |
| sqlite_async concurrent execute() | 2.528 | 3.340 | 2.528 | 3.340 |
| drift concurrent execute() | 1.623 | 2.281 | 1.623 | 2.281 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.049 | 0.050 | 0.049 | 0.050 |
| sqlite3 executeBatch() | 0.047 | 0.049 | 0.047 | 0.049 |
| sqlite_async executeBatch() | 0.089 | 0.094 | 0.089 | 0.094 |
| drift executeBatch() | 0.108 | 0.112 | 0.108 | 0.112 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.396 | 0.408 | 0.396 | 0.408 |
| sqlite3 executeBatch() | 0.431 | 0.447 | 0.431 | 0.447 |
| sqlite_async executeBatch() | 0.502 | 0.515 | 0.502 | 0.515 |
| drift executeBatch() | 0.638 | 0.708 | 0.638 | 0.708 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 3.721 | 4.245 | 3.721 | 4.245 |
| sqlite3 executeBatch() | 4.050 | 4.262 | 4.050 | 4.262 |
| sqlite_async executeBatch() | 4.665 | 5.320 | 4.665 | 5.320 |
| drift executeBatch() | 5.855 | 8.094 | 5.855 | 8.094 |

### Wide Batch Insert (10000 rows x 20 params)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 12.336 | 19.256 | 12.336 | 19.256 |
| sqlite3 executeBatch() | 18.786 | 20.915 | 18.786 | 20.915 |
| sqlite_async executeBatch() | 21.391 | 25.371 | 21.391 | 25.371 |
| drift executeBatch() | 24.771 | 26.779 | 24.771 | 26.779 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.045 | 0.049 | 0.045 | 0.049 |
| sqlite_async writeTransaction() | 0.079 | 0.088 | 0.079 | 0.088 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.062 | 0.068 | 0.062 | 0.068 |
| resqlite tx.execute() loop | 0.506 | 0.647 | 0.506 | 0.647 |
| sqlite_async tx.execute() loop | 0.939 | 1.139 | 0.939 | 1.139 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.392 | 0.411 | 0.392 | 0.411 |
| resqlite tx.execute() loop | 4.076 | 5.167 | 4.076 | 5.167 |
| sqlite_async tx.execute() loop | 9.371 | 9.805 | 9.371 | 9.805 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.100 | 0.103 | 0.100 | 0.103 |
| sqlite_async tx.getAll() | 0.198 | 0.209 | 0.198 | 0.209 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.176 | 0.182 | 0.176 | 0.182 |
| sqlite_async tx.getAll() | 0.346 | 0.356 | 0.346 | 0.356 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 0.600 | 0.908 | 0.600 | 0.908 |
| resqlite nested transaction() depth=5 | 0.063 | 0.069 | 0.063 | 0.069 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.027 | 0.030 | 0.027 | 0.030 |
| sqlite_async watch() | 0.101 | 0.109 | 0.101 | 0.109 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.043 | 0.068 | 0.043 | 0.068 |
| sqlite_async | 0.075 | 0.134 | 0.075 | 0.134 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.217 | 0.267 | 0.217 | 0.267 |
| sqlite_async | 0.490 | 1.141 | 0.490 | 1.141 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.646 | 1.911 | 1.646 | 1.911 |

### Long-Payload Unchanged Fanout (8 streams, 64 rows x 32KB TEXT + 32KB BLOB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.829 | 3.117 | 2.829 | 3.117 |

### Long-Text 32KB Unchanged Fanout (8 unchanged streams, 64 rows x 32KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.769 | 3.467 | 2.769 | 3.467 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.175 | 0.201 | 0.175 | 0.201 |
| sqlite_async | 0.249 | 0.310 | 0.249 | 0.310 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.740 | 1.740 | 1.740 | 1.740 |
| sqlite_async | 8.790 | 8.790 | 8.790 | 8.790 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.077 | 3.717 | 3.077 | 3.717 |
| sqlite_async | 5.315 | 6.114 | 5.315 | 6.114 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.515 | 0.680 | 0.515 | 0.680 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 6.077 | 6.619 | 6.077 | 6.619 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. For resqlite, this emission metric can reflect writer-side column-level invalidation, experiment 075's native result-hash short-circuit, or both. Use A11c (Many-Streams Writer Throughput) when the question is specifically writer-side dispatch elision.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 68.4 | 0.000 |
| sqlite_async | 3914 | 1106.8 | 0.951 |
| drift | 5000 | 1004.3 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 72.0 | 0.000 |
| sqlite_async | 4117 | 1123.4 | 0.951 |
| drift | 5000 | 1016.6 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 225.14 | 225.59 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 441.95 | 442.94 | 0.00 | 0.00 | 1109 | 3 |
| drift stream() | 544.87 | 555.58 | 0.00 | 0.01 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.018 | 0.029 | 0.000 | 0.000 |
| sqlite3 | 0.018 | 0.022 | 0.018 | 0.022 |
| sqlite_async | 0.035 | 0.043 | 0.000 | 0.000 |
| drift | 0.035 | 0.044 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.014 | 0.019 | 0.000 | 0.000 |
| sqlite3 | 0.011 | 0.014 | 0.011 | 0.014 |
| sqlite_async | 0.028 | 0.032 | 0.000 | 0.000 |
| drift | 0.028 | 0.034 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.024 | 0.033 | 0.000 | 0.000 |
| sqlite3 | 0.030 | 0.032 | 0.030 | 0.032 |
| sqlite_async | 0.055 | 0.063 | 0.000 | 0.000 |
| drift | 0.053 | 0.057 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.008 | 0.014 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.020 | 0.024 | 0.000 | 0.000 |
| drift | 0.019 | 0.023 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.039 | 0.041 | 0.001 | 0.001 |
| sqlite3 | 0.065 | 0.067 | 0.065 | 0.067 |
| sqlite_async | 0.086 | 0.106 | 0.001 | 0.001 |
| drift | 0.089 | 0.094 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 109.409 | 111.140 | 0.000 | 0.000 | 0 |
| sqlite_async | 218.435 | 221.066 | 0.000 | 0.000 | 43 |
| drift | 233.290 | 233.941 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 239.98 | 239.98 | 0.00 | 0.00 | 13.68 | 227.21 | 0 |
| sqlite_async | 480.05 | 480.05 | 0.00 | 0.00 | 24.35 | 455.70 | 1178 |
| drift | 1702.09 | 1702.09 | 0.05 | 0.05 | 15.20 | 1686.89 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 6.83 | 23.56 | 0.84..10.84 | ±5.00 |
| sqlite3 select() | 2.33 | 9.17 | 0.00..8.69 | ±4.34 |
| sqlite_async select() | 1.00 | 1.00 | 1.00..1.00 | ±0.00 |
| drift select() | 7.11 | 74.48 | 0.00..42.67 | ±21.34 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 1.38 | 0.00..0.00 | ±0.00 |
| resqlite + jsonEncode | 5.45 | 72.94 | 0.00..11.25 | ±5.63 |
| sqlite3 + jsonEncode | 5.63 | 37.55 | 0.00..8.17 | ±4.09 |
| sqlite_async + jsonEncode | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| drift + jsonEncode | 0.00 | 33.48 | 0.00..8.69 | ±4.34 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.58 | 6.72 | 0.00..2.02 | ±1.01 |
| sqlite3 executeBatch() | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 1.55 | 0.00..0.02 | ±0.01 |
| drift batch() | 0.00 | 2.00 | 0.00..0.50 | ±0.25 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.13 | 0.00..0.06 | ±0.03 |
| sqlite_async watch() | 0.00 | 0.02 | 0.00..0.00 | ±0.00 |

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
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.02 | 0.02..0.03 | 4.2% | 8.3% | 4.2% | moderate |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 6.3% | 12.5% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02..0.02 | 5.6% | 11.1% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.01..0.01 | 7.1% | 14.3% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.29 | 0.29..0.31 | 3.4% | 6.9% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.29 | 0.29..0.31 | 3.4% | 6.9% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.30 | 0.30..0.31 | 1.7% | 3.3% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.15 | 0.15..0.15 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.36 | 0.36..0.37 | 1.4% | 2.8% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.09 | 0.09..0.09 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.69 | 0.69..0.77 | 5.8% | 11.6% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.09 | 0.09..0.10 | 5.6% | 11.1% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.04 | 3.8% | 7.7% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 150.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 109.41 | 108.62..111.22 | 1.2% | 2.4% | 0.5% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 237.90 | 236.88..241.51 | 1.0% | 1.9% | 0.4% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 225.14 | 224.90..226.91 | 0.4% | 0.9% | 0.1% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 14.03 | 13.92..14.09 | 0.6% | 1.2% | 0.2% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 14.03 | 13.92..14.09 | 0.6% | 1.2% | 0.2% | stable |
| Point Query Throughput / resqlite qps | 150347.00 | 149712.00..151740.00 | 0.7% | 1.3% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.01 | 18.2% | 36.4% | 9.1% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.03 | 13.0% | 25.9% | 3.7% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.03 | 13.0% | 25.9% | 3.7% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.01 | 9.1% | 18.2% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.01 | 9.1% | 18.2% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.04..0.04 | 3.5% | 7.0% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.19 | 0.19..0.20 | 1.8% | 3.6% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.19 | 0.19..0.20 | 1.8% | 3.6% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.04 | 3.7% | 7.3% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.04 | 0.04..0.04 | 3.7% | 7.3% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.34 | 0.34..0.35 | 1.3% | 2.6% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.75 | 1.74..1.82 | 2.3% | 4.5% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.75 | 1.74..1.82 | 2.3% | 4.5% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.05 | 0.05..0.05 | 1.0% | 1.9% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.34 | 0.34..0.35 | 1.0% | 2.0% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.34 | 0.34..0.35 | 1.0% | 2.0% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.07 | 3.96..4.17 | 2.5% | 5.0% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 20.09 | 19.66..20.37 | 1.8% | 3.5% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 20.09 | 19.66..20.37 | 1.8% | 3.5% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.52 | 0.51..0.53 | 1.4% | 2.9% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 3.42 | 3.38..3.49 | 1.6% | 3.1% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 3.42 | 3.38..3.49 | 1.6% | 3.1% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.71 | 0.71..0.74 | 1.9% | 3.8% | 0.1% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.75 | 3.66..3.85 | 2.6% | 5.1% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.75 | 3.66..3.85 | 2.6% | 5.1% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.11 | 0.10..0.11 | 1.9% | 3.8% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.67 | 0.67..0.68 | 1.1% | 2.2% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.67 | 0.67..0.68 | 1.1% | 2.2% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.06 | 9.89..10.36 | 2.3% | 4.6% | 0.1% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 43.20 | 41.82..45.97 | 4.8% | 9.6% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 43.20 | 41.82..45.97 | 4.8% | 9.6% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.03 | 1.02..1.05 | 1.4% | 2.8% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 7.12 | 7.05..7.20 | 1.1% | 2.1% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 7.12 | 7.05..7.20 | 1.1% | 2.1% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03..0.03 | 2.0% | 4.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10..0.10 | 3.0% | 5.9% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.10 | 0.10..0.10 | 3.0% | 5.9% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.00 | 16.7% | 33.3% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.02..0.03 | 5.8% | 11.5% | 3.8% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.02..0.03 | 5.8% | 11.5% | 3.8% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.18 | 0.17..0.18 | 2.0% | 4.0% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.90 | 0.89..0.93 | 2.3% | 4.6% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.90 | 0.89..0.93 | 2.3% | 4.6% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.03 | 0.03..0.03 | 1.9% | 3.8% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.17 | 0.17..0.18 | 2.0% | 4.0% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.17 | 0.17..0.18 | 2.0% | 4.0% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 1.98 | 1.93..2.02 | 2.3% | 4.7% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 9.86 | 9.43..10.39 | 4.9% | 9.7% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 9.86 | 9.43..10.39 | 4.9% | 9.7% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.26 | 0.26..0.27 | 1.9% | 3.8% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 1.66 | 1.66..1.73 | 2.2% | 4.3% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 1.66 | 1.66..1.73 | 2.2% | 4.3% | 0.2% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.09 | 0.08..0.09 | 3.4% | 6.9% | 0.0% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.02 | 0.01..0.02 | 17.4% | 34.8% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.26 | 0.26..0.27 | 1.9% | 3.9% | 0.4% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.06 | 0.06..0.06 | 1.7% | 3.3% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.26 | 0.25..0.26 | 1.6% | 3.1% | 0.4% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.06 | 0.06..0.06 | 0.8% | 1.7% | 0.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.49 | 0.49..0.50 | 1.1% | 2.2% | 1.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.06 | 0.06..0.06 | 0.8% | 1.6% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.84 | 0.84..0.85 | 0.4% | 0.8% | 0.1% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.20 | 0.20..0.20 | 1.2% | 2.5% | 1.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.10 | 132.7% | 265.4% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.01 | 0.01..0.07 | 196.7% | 393.3% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 40.9% | 81.8% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.19 | 0.19..0.21 | 4.9% | 9.8% | 1.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.15 | 0.15..0.16 | 3.5% | 7.1% | 1.9% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.05 | 12.2% | 24.4% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.76 | 1.74..1.78 | 1.2% | 2.4% | 0.9% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.45 | 1.44..1.46 | 0.7% | 1.4% | 0.2% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.35 | 0.35..0.36 | 1.1% | 2.3% | 0.8% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 21.62 | 20.34..22.28 | 4.5% | 9.0% | 3.1% | moderate |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 14.74 | 14.69..15.13 | 1.5% | 3.0% | 0.2% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.46 | 3.41..3.48 | 1.0% | 2.0% | 0.5% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.08 | 295.8% | 591.7% | 8.3% | noisy |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.04 | 0.04..0.06 | 19.8% | 39.5% | 2.3% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 20.0% | 40.0% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.34 | 0.34..0.35 | 1.6% | 3.2% | 0.9% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.05 | 0.05..0.05 | 1.0% | 2.0% | 0.0% | stable |
| Select → Maps / 10000 rows / resqlite select() | 4.08 | 4.05..4.14 | 1.1% | 2.2% | 0.8% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.51 | 0.51..0.52 | 1.3% | 2.5% | 0.2% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.17 | 0.17..0.21 | 14.2% | 28.5% | 1.7% | stable |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.17 | 0.17..0.21 | 14.2% | 28.5% | 1.7% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.52 | 0.52..0.57 | 5.7% | 11.5% | 1.5% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.52 | 0.52..0.57 | 5.7% | 11.5% | 1.5% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03..0.07 | 73.2% | 146.4% | 3.6% | moderate |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03..0.07 | 73.2% | 146.4% | 3.6% | moderate |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.04..0.05 | 10.5% | 20.9% | 9.3% | noisy |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.04..0.05 | 10.5% | 20.9% | 9.3% | noisy |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows x 32K... | 2.81 | 2.66..2.85 | 3.3% | 6.7% | 1.4% | stable |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows x 32K... | 2.81 | 2.66..2.85 | 3.3% | 6.7% | 1.4% | stable |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged streams, 6... | 2.76 | 2.71..2.80 | 1.5% | 3.0% | 1.2% | stable |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged streams, 6... | 2.76 | 2.71..2.80 | 1.5% | 3.0% | 1.2% | stable |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 1.71 | 1.65..2.04 | 11.5% | 23.0% | 3.3% | moderate |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 1.71 | 1.65..2.04 | 11.5% | 23.0% | 3.3% | moderate |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.08 | 2.98..3.31 | 5.4% | 10.7% | 3.1% | moderate |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.08 | 2.98..3.31 | 5.4% | 10.7% | 3.1% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.74 | 1.60..3.26 | 47.8% | 95.6% | 3.9% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.74 | 1.60..3.26 | 47.8% | 95.6% | 3.9% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.08 | 6.00..6.71 | 5.8% | 11.6% | 0.6% | stable |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.08 | 6.00..6.71 | 5.8% | 11.6% | 0.6% | stable |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.18 | 0.17..0.22 | 13.0% | 26.0% | 2.3% | stable |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.18 | 0.17..0.22 | 13.0% | 26.0% | 2.3% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.05 | 0.05..0.05 | 2.0% | 4.0% | 2.0% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.05 | 0.05..0.05 | 2.0% | 4.0% | 2.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.40 | 0.39..0.40 | 0.9% | 1.8% | 0.3% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.40 | 0.39..0.40 | 0.9% | 1.8% | 0.3% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.72 | 3.69..3.76 | 1.0% | 1.9% | 0.8% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.72 | 3.69..3.76 | 1.0% | 1.9% | 0.8% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.54 | 0.38..0.54 | 14.6% | 29.1% | 0.7% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.54 | 0.38..0.54 | 14.6% | 29.1% | 0.7% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.06 | 0.06..0.07 | 4.0% | 8.1% | 1.6% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.06 | 0.06..0.07 | 4.0% | 8.1% | 1.6% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 4.14 | 4.08..4.70 | 7.5% | 15.1% | 0.3% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 4.14 | 4.08..4.70 | 7.5% | 15.1% | 0.3% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.40 | 0.39..0.40 | 1.0% | 2.0% | 0.8% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.40 | 0.39..0.40 | 1.0% | 2.0% | 0.8% | stable |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 1.01 | 0.99..1.06 | 3.6% | 7.2% | 2.3% | stable |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 1.01 | 0.99..1.06 | 3.6% | 7.2% | 2.3% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.04 | 0.04..0.05 | 4.4% | 8.9% | 2.2% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.04 | 0.04..0.05 | 4.4% | 8.9% | 2.2% | stable |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.06 | 0.06..0.07 | 10.3% | 20.6% | 1.6% | stable |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.06 | 0.06..0.07 | 10.3% | 20.6% | 1.6% | stable |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.62 | 0.60..0.81 | 16.9% | 33.8% | 3.8% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.62 | 0.60..0.81 | 16.9% | 33.8% | 3.8% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.44 | 1.40..1.62 | 7.8% | 15.5% | 2.7% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.44 | 1.40..1.62 | 7.8% | 15.5% | 2.7% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.18..0.18 | 1.7% | 3.4% | 0.6% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.18..0.18 | 1.7% | 3.4% | 0.6% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.10 | 0.10..0.10 | 1.5% | 3.0% | 0.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.10 | 0.10..0.10 | 1.5% | 3.0% | 0.0% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 12.40 | 12.29..13.19 | 3.6% | 7.3% | 0.7% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 12.40 | 12.29..13.19 | 3.6% | 7.3% | 0.7% | stable |


## Comparison vs Previous Run

Previous: `2026-06-16T15-19-02-baseline-for-exp179.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.02 | 0.02 | +0.00 | ±13% / ±0.02 ms | 4.2% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 6.3% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 5.6% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 7.1% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.29 | 0.29 | +0.00 | ±10% / ±0.03 ms | 3.4% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.29 | 0.29 | +0.00 | ±10% / ±0.03 ms | 3.4% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.30 | 0.30 | +0.00 | ±10% / ±0.03 ms | 1.7% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.15 | 0.15 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.36 | 0.36 | +0.00 | ±10% / ±0.04 ms | 1.4% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.70 | 0.69 | -0.01 | ±10% / ±0.07 ms | 5.8% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 5.6% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 3.8% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±150% / ±0.02 ms | 150.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 111.39 | 109.41 | -1.98 | ±10% / ±11.14 ms | 1.2% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 441.21 | 237.90 | -203.31 | ±10% / ±44.12 ms | 1.0% | stable | 🟢 Win (-46%) |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 224.59 | 225.14 | +0.55 | ±10% / ±22.51 ms | 0.4% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.05 | 14.03 | -0.02 | ±10% / ±1.40 ms | 0.6% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.05 | 14.03 | -0.02 | ±10% / ±1.40 ms | 0.6% | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 152194.00 | 150347.00 | -1847.00 | ±10% / ±15219.40 ms | 0.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01 | +0.00 | ±27% / ±0.02 ms | 18.2% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | -0.00 | ±13% / ±0.02 ms | 13.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.03 | -0.00 | ±13% / ±0.02 ms | 13.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 9.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 9.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 3.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.19 | +0.00 | ±10% / ±0.02 ms | 1.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.19 | +0.00 | ±10% / ±0.02 ms | 1.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 3.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 3.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.34 | 0.34 | +0.00 | ±10% / ±0.03 ms | 1.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.75 | 1.75 | +0.00 | ±10% / ±0.18 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.75 | 1.75 | +0.00 | ±10% / ±0.18 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 1.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.34 | 0.34 | +0.00 | ±10% / ±0.03 ms | 1.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.34 | 0.34 | +0.00 | ±10% / ±0.03 ms | 1.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.12 | 4.07 | -0.05 | ±10% / ±0.41 ms | 2.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 20.55 | 20.09 | -0.46 | ±10% / ±2.06 ms | 1.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 20.55 | 20.09 | -0.46 | ±10% / ±2.06 ms | 1.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.52 | 0.52 | -0.00 | ±10% / ±0.05 ms | 1.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.39 | 3.42 | +0.03 | ±10% / ±0.34 ms | 1.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.39 | 3.42 | +0.03 | ±10% / ±0.34 ms | 1.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.71 | 0.71 | +0.00 | ±10% / ±0.07 ms | 1.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.67 | 3.75 | +0.08 | ±10% / ±0.37 ms | 2.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.67 | 3.75 | +0.08 | ±10% / ±0.37 ms | 2.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.10 | 0.11 | +0.00 | ±10% / ±0.02 ms | 1.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.66 | 0.67 | +0.01 | ±10% / ±0.07 ms | 1.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.66 | 0.67 | +0.01 | ±10% / ±0.07 ms | 1.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.16 | 10.06 | -0.10 | ±10% / ±1.02 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 43.14 | 43.20 | +0.06 | ±10% / ±4.32 ms | 4.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 43.14 | 43.20 | +0.06 | ±10% / ±4.32 ms | 4.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.02 | 1.03 | +0.01 | ±10% / ±0.10 ms | 1.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 7.08 | 7.12 | +0.04 | ±10% / ±0.71 ms | 1.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 7.08 | 7.12 | +0.04 | ±10% / ±0.71 ms | 1.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.02 | 0.03 | +0.00 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 3.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 3.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±17% / ±0.02 ms | 16.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.03 | +0.00 | ±12% / ±0.02 ms | 5.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.03 | +0.00 | ±12% / ±0.02 ms | 5.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.18 | 0.18 | +0.00 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.95 | 0.90 | -0.05 | ±10% / ±0.09 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.95 | 0.90 | -0.05 | ±10% / ±0.09 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 1.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.17 | 0.17 | +0.00 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.17 | 0.17 | +0.00 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 1.99 | 1.98 | -0.01 | ±10% / ±0.20 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 9.72 | 9.86 | +0.14 | ±10% / ±0.99 ms | 4.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 9.72 | 9.86 | +0.14 | ±10% / ±0.99 ms | 4.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.26 | 0.26 | -0.00 | ±10% / ±0.03 ms | 1.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.66 | 1.66 | +0.00 | ±10% / ±0.17 ms | 2.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.66 | 1.66 | +0.00 | ±10% / ±0.17 ms | 2.2% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.09 | 0.09 | -0.01 | ±10% / ±0.02 ms | 3.4% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.03 | 0.02 | -0.00 | ±17% / ±0.02 ms | 17.4% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.26 | 0.26 | -0.00 | ±10% / ±0.03 ms | 1.9% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 1.7% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.27 | 0.26 | -0.01 | ±10% / ±0.03 ms | 1.6% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.06 | 0.06 | -0.00 | ±10% / ±0.02 ms | 0.8% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.49 | 0.49 | +0.00 | ±10% / ±0.05 ms | 1.1% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 0.8% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.84 | 0.84 | +0.00 | ±10% / ±0.08 ms | 0.4% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.20 | 0.20 | +0.00 | ±10% / ±0.02 ms | 1.2% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±133% / ±0.03 ms | 132.7% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.01 | 0.01 | +0.00 | ±197% / ±0.03 ms | 196.7% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | +0.00 | ±41% / ±0.02 ms | 40.9% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.19 | -0.00 | ±10% / ±0.02 ms | 4.9% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.16 | 0.15 | -0.00 | ±10% / ±0.02 ms | 3.5% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04 | +0.00 | ±12% / ±0.02 ms | 12.2% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.73 | 1.76 | +0.03 | ±10% / ±0.18 ms | 1.2% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.44 | 1.45 | +0.01 | ±10% / ±0.15 ms | 0.7% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.35 | 0.35 | +0.00 | ±10% / ±0.04 ms | 1.1% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.47 | 21.62 | +1.14 | ±10% / ±2.16 ms | 4.5% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 14.82 | 14.74 | -0.07 | ±10% / ±1.48 ms | 1.5% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.47 | 3.46 | -0.01 | ±10% / ±0.35 ms | 1.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | +0.00 | ±296% / ±0.04 ms | 295.8% | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.04 | 0.04 | +0.00 | ±20% / ±0.02 ms | 19.8% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±20% / ±0.02 ms | 20.0% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.34 | 0.34 | +0.00 | ±10% / ±0.03 ms | 1.6% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 1.0% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 4.13 | 4.08 | -0.05 | ±10% / ±0.41 ms | 1.1% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.52 | 0.51 | -0.01 | ±10% / ±0.05 ms | 1.3% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.18 | 0.17 | -0.01 | ±14% / ±0.03 ms | 14.2% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.18 | 0.17 | -0.01 | ±14% / ±0.03 ms | 14.2% | stable | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.52 | 0.52 | +0.01 | ±10% / ±0.05 ms | 5.7% | stable | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.52 | 0.52 | +0.01 | ±10% / ±0.05 ms | 5.7% | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | +0.00 | ±73% / ±0.02 ms | 73.2% | moderate | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03 | +0.00 | ±73% / ±0.02 ms | 73.2% | moderate | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.04 | +0.00 | ±28% / ±0.02 ms | 10.5% | noisy | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.04 | +0.00 | ±28% / ±0.02 ms | 10.5% | noisy | ⚪ Within noise |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 ... | 2.63 | 2.81 | +0.18 | ±10% / ±0.28 ms | 3.3% | stable | ⚪ Within noise |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 ... | 2.63 | 2.81 | +0.18 | ±10% / ±0.28 ms | 3.3% | stable | ⚪ Within noise |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged ... | 2.75 | 2.76 | +0.01 | ±10% / ±0.28 ms | 1.5% | stable | ⚪ Within noise |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged ... | 2.75 | 2.76 | +0.01 | ±10% / ±0.28 ms | 1.5% | stable | ⚪ Within noise |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 1.78 | 1.71 | -0.07 | ±12% / ±0.21 ms | 11.5% | moderate | ⚪ Within noise |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 1.78 | 1.71 | -0.07 | ±12% / ±0.21 ms | 11.5% | moderate | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.19 | 3.08 | -0.11 | ±10% / ±0.32 ms | 5.4% | moderate | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.19 | 3.08 | -0.11 | ±10% / ±0.32 ms | 5.4% | moderate | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.64 | 1.74 | +0.10 | ±48% / ±0.83 ms | 47.8% | moderate | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.64 | 1.74 | +0.10 | ±48% / ±0.83 ms | 47.8% | moderate | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 5.99 | 6.08 | +0.08 | ±10% / ±0.61 ms | 5.8% | stable | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 5.99 | 6.08 | +0.08 | ±10% / ±0.61 ms | 5.8% | stable | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.19 | 0.18 | -0.01 | ±13% / ±0.02 ms | 13.0% | stable | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.19 | 0.18 | -0.01 | ±13% / ±0.02 ms | 13.0% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.40 | 0.40 | +0.00 | ±10% / ±0.04 ms | 0.9% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.40 | 0.40 | +0.00 | ±10% / ±0.04 ms | 0.9% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.71 | 3.72 | +0.01 | ±10% / ±0.37 ms | 1.0% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.71 | 3.72 | +0.01 | ±10% / ±0.37 ms | 1.0% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.53 | 0.54 | +0.01 | ±15% / ±0.08 ms | 14.6% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.53 | 0.54 | +0.01 | ±15% / ±0.08 ms | 14.6% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.06 | 0.06 | -0.00 | ±10% / ±0.02 ms | 4.0% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.06 | 0.06 | -0.00 | ±10% / ±0.02 ms | 4.0% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 4.47 | 4.14 | -0.33 | ±10% / ±0.45 ms | 7.5% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 4.47 | 4.14 | -0.33 | ±10% / ±0.45 ms | 7.5% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.40 | 0.40 | -0.00 | ±10% / ±0.04 ms | 1.0% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.40 | 0.40 | -0.00 | ±10% / ±0.04 ms | 1.0% | stable | ⚪ Within noise |
| Write Performance / Concurrent Single Inserts (100 concur... | 0.99 | 1.01 | +0.02 | ±10% / ±0.10 ms | 3.6% | stable | ⚪ Within noise |
| Write Performance / Concurrent Single Inserts (100 concur... | 0.99 | 1.01 | +0.02 | ±10% / ±0.10 ms | 3.6% | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 4.4% | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 4.4% | stable | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.07 | 0.06 | -0.00 | ±10% / ±0.02 ms | 10.3% | stable | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.07 | 0.06 | -0.00 | ±10% / ±0.02 ms | 10.3% | stable | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.73 | 0.62 | -0.10 | ±17% / ±0.12 ms | 16.9% | moderate | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.73 | 0.62 | -0.10 | ±17% / ±0.12 ms | 16.9% | moderate | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.42 | 1.44 | +0.02 | ±10% / ±0.14 ms | 7.8% | stable | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.42 | 1.44 | +0.02 | ±10% / ±0.14 ms | 7.8% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.18 | -0.00 | ±10% / ±0.02 ms | 1.7% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.18 | -0.00 | ±10% / ±0.02 ms | 1.7% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 1.5% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 1.5% | stable | ⚪ Within noise |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 12.46 | 12.40 | -0.06 | ±10% / ±1.25 ms | 3.6% | stable | ⚪ Within noise |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 12.46 | 12.40 | -0.06 | ±10% / ±1.25 ms | 3.6% | stable | ⚪ Within noise |

**Summary:** 1 wins, 0 regressions, 166 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

✅ **No regressions beyond noise.** 1 benchmarks improved.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 0.00 | 0.58 | +0.58 MB | ±1.01 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 0.00 | 0.00 | +0.00 MB | ±4.34 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 1.00 | 5.45 | +4.45 MB | ±5.63 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 7.83 | 5.63 | -2.20 MB | ±4.09 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 8.08 | 7.11 | -0.97 MB | ±21.34 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / resqlite select() | 0.48 | 6.83 | +6.35 MB | ±5.00 MB | 🔴 Regression (+6.35 MB) |
| Memory / Select 10k rows → Maps / sqlite3 select() | 2.17 | 2.33 | +0.16 MB | ±4.34 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 1.00 | 1.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.06 | 0.06 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 0 wins, 1 regressions, 14 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 4411 | 3914 | -497 | ±100 | 🟢 Fewer re-emits (-497) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 4067 | 4117 | +50 | ±100 | ⚪ Within noise |

**Granularity summary:** 1 fewer-re-emit, 0 more-re-emit, 5 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


