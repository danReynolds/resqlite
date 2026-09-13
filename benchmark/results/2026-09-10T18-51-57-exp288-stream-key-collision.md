# resqlite Benchmark Results

Generated: 2026-09-10T19:02:43.804622

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp288-stream-key-collision`
- Repeats: `5`
- Runtime: `dart-vm / Dart 3.12.2`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `exp-288-stream-key-collision @ 74aad8e07d5e`
- Comparison baseline: `2026-08-09T20-36-47-exp266-headline-refresh.md`
- Comparison mode: `explicit`
- Comparison baseline compatibility: `incompatible (explicit comparison)`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.010 | 0.012 | 0.000 | 0.000 |
| sqlite3 select() | 0.016 | 0.016 | 0.016 | 0.016 |
| sqlite_async select() | 0.030 | 0.032 | 0.001 | 0.001 |
| drift select() | 0.035 | 0.038 | 0.001 | 0.001 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.039 | 0.044 | 0.005 | 0.006 |
| sqlite3 select() | 0.118 | 0.120 | 0.118 | 0.120 |
| sqlite_async select() | 0.130 | 0.134 | 0.010 | 0.011 |
| drift select() | 0.175 | 0.180 | 0.010 | 0.011 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.319 | 0.324 | 0.053 | 0.054 |
| sqlite3 select() | 1.127 | 1.140 | 1.127 | 1.140 |
| sqlite_async select() | 1.066 | 1.081 | 0.092 | 0.093 |
| drift select() | 1.535 | 1.863 | 0.090 | 0.091 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 3.348 | 8.444 | 0.517 | 0.935 |
| sqlite3 select() | 13.924 | 16.831 | 13.924 | 16.831 |
| sqlite_async select() | 12.443 | 14.113 | 0.929 | 2.157 |
| drift select() | 20.914 | 28.031 | 0.915 | 1.344 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row. The large-payload row isolates resqlite selectBytes because it guards the native bytes transfer policy without multiplying large JSON encoding work across every peer.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.028 | 0.029 | 0.017 | 0.017 |
| sqlite3 + jsonEncode | 0.031 | 0.032 | 0.031 | 0.032 |
| sqlite_async + jsonEncode | 0.049 | 0.051 | 0.017 | 0.018 |
| drift + jsonEncode | 0.053 | 0.055 | 0.017 | 0.017 |
| resqlite selectBytes() | 0.012 | 0.013 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.202 | 0.206 | 0.167 | 0.171 |
| sqlite3 + jsonEncode | 0.270 | 0.275 | 0.270 | 0.275 |
| sqlite_async + jsonEncode | 0.283 | 0.303 | 0.162 | 0.166 |
| drift + jsonEncode | 0.337 | 0.352 | 0.167 | 0.170 |
| resqlite selectBytes() | 0.035 | 0.038 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.907 | 3.806 | 1.631 | 3.201 |
| sqlite3 + jsonEncode | 2.609 | 3.448 | 2.609 | 3.448 |
| sqlite_async + jsonEncode | 2.561 | 4.959 | 1.575 | 2.930 |
| drift + jsonEncode | 3.038 | 3.634 | 1.570 | 1.882 |
| resqlite selectBytes() | 0.261 | 0.262 | 0.000 | 0.000 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.161 | 24.281 | 15.901 | 17.923 |
| sqlite3 + jsonEncode | 29.542 | 35.346 | 29.542 | 35.346 |
| sqlite_async + jsonEncode | 31.132 | 34.809 | 16.202 | 17.903 |
| drift + jsonEncode | 39.777 | 42.353 | 16.182 | 21.309 |
| resqlite selectBytes() | 2.667 | 2.728 | 0.000 | 0.000 |

### Large payload (~650KB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.235 | 0.365 | 0.000 | 0.000 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.085 | 0.088 | 0.023 | 0.027 |
| sqlite3 | 0.330 | 0.333 | 0.330 | 0.333 |
| sqlite_async | 0.375 | 0.381 | 0.033 | 0.033 |
| drift | 0.568 | 0.631 | 0.032 | 0.033 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.797 | 0.823 | 0.228 | 0.233 |
| sqlite3 | 3.234 | 3.706 | 3.234 | 3.706 |
| sqlite_async | 2.934 | 3.367 | 0.237 | 0.244 |
| drift | 4.541 | 5.733 | 0.236 | 0.244 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.381 | 0.853 | 0.062 | 0.070 |
| sqlite3 | 1.435 | 1.501 | 1.435 | 1.501 |
| sqlite_async | 1.377 | 1.702 | 0.086 | 0.087 |
| drift | 1.877 | 2.188 | 0.085 | 0.086 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.239 | 0.250 | 0.060 | 0.062 |
| sqlite3 | 0.986 | 0.994 | 0.986 | 0.994 |
| sqlite_async | 0.943 | 0.949 | 0.085 | 0.086 |
| drift | 1.418 | 1.436 | 0.083 | 0.085 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.253 | 0.256 | 0.062 | 0.063 |
| sqlite3 | 0.958 | 0.968 | 0.958 | 0.968 |
| sqlite_async | 0.946 | 0.953 | 0.084 | 0.085 |
| drift | 1.402 | 1.713 | 0.083 | 0.085 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.010 | 0.011 | 0.000 | 0.000 |
| sqlite3 | 0.016 | 0.016 | 0.016 | 0.016 |
| sqlite_async | 0.031 | 0.032 | 0.001 | 0.001 |
| drift | 0.035 | 0.036 | 0.001 | 0.001 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.023 | 0.024 | 0.003 | 0.003 |
| sqlite3 | 0.061 | 0.063 | 0.061 | 0.063 |
| sqlite_async | 0.074 | 0.076 | 0.004 | 0.004 |
| drift | 0.097 | 0.099 | 0.004 | 0.004 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.040 | 0.041 | 0.005 | 0.005 |
| sqlite3 | 0.116 | 0.122 | 0.116 | 0.122 |
| sqlite_async | 0.126 | 0.128 | 0.008 | 0.008 |
| drift | 0.178 | 0.211 | 0.008 | 0.009 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.167 | 0.171 | 0.027 | 0.028 |
| sqlite3 | 0.559 | 0.573 | 0.559 | 0.573 |
| sqlite_async | 0.535 | 0.540 | 0.036 | 0.037 |
| drift | 0.765 | 0.789 | 0.036 | 0.036 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.319 | 0.323 | 0.053 | 0.054 |
| sqlite3 | 1.109 | 1.121 | 1.109 | 1.121 |
| sqlite_async | 1.042 | 1.059 | 0.073 | 0.074 |
| drift | 1.516 | 1.606 | 0.072 | 0.073 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.613 | 0.635 | 0.105 | 0.108 |
| sqlite3 | 2.217 | 2.673 | 2.217 | 2.673 |
| sqlite_async | 2.079 | 2.379 | 0.144 | 0.147 |
| drift | 3.169 | 3.554 | 0.146 | 0.156 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.759 | 4.810 | 0.264 | 0.277 |
| sqlite3 | 5.579 | 6.916 | 5.579 | 6.916 |
| sqlite_async | 5.329 | 5.936 | 0.362 | 0.379 |
| drift | 8.131 | 8.220 | 0.358 | 0.363 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.370 | 8.599 | 0.527 | 0.647 |
| sqlite3 | 13.692 | 17.285 | 13.692 | 17.285 |
| sqlite_async | 11.255 | 12.049 | 0.729 | 0.739 |
| drift | 17.966 | 27.306 | 0.745 | 1.183 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 8.709 | 14.133 | 1.056 | 2.077 |
| sqlite3 | 32.483 | 36.367 | 32.483 | 36.367 |
| sqlite_async | 33.919 | 38.362 | 1.461 | 1.864 |
| drift | 47.921 | 57.740 | 1.457 | 2.079 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.028 | 0.029 | 0.028 | 0.029 |
| sqlite3 + jsonEncode | 0.031 | 0.033 | 0.031 | 0.033 |
| sqlite_async + jsonEncode | 0.048 | 0.050 | 0.048 | 0.050 |
| drift + jsonEncode | 0.054 | 0.061 | 0.054 | 0.061 |
| resqlite selectBytes() | 0.011 | 0.014 | 0.011 | 0.014 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.106 | 0.109 | 0.106 | 0.109 |
| sqlite3 + jsonEncode | 0.141 | 0.145 | 0.141 | 0.145 |
| sqlite_async + jsonEncode | 0.155 | 0.193 | 0.155 | 0.193 |
| drift + jsonEncode | 0.172 | 0.173 | 0.172 | 0.173 |
| resqlite selectBytes() | 0.022 | 0.025 | 0.022 | 0.025 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.203 | 0.206 | 0.203 | 0.206 |
| sqlite3 + jsonEncode | 0.270 | 0.282 | 0.270 | 0.282 |
| sqlite_async + jsonEncode | 0.291 | 0.300 | 0.291 | 0.300 |
| drift + jsonEncode | 0.327 | 0.356 | 0.327 | 0.356 |
| resqlite selectBytes() | 0.034 | 0.037 | 0.034 | 0.037 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.932 | 0.952 | 0.932 | 0.952 |
| sqlite3 + jsonEncode | 1.317 | 1.335 | 1.317 | 1.335 |
| sqlite_async + jsonEncode | 1.295 | 1.302 | 1.295 | 1.302 |
| drift + jsonEncode | 1.528 | 1.550 | 1.528 | 1.550 |
| resqlite selectBytes() | 0.137 | 0.140 | 0.137 | 0.140 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.830 | 1.925 | 1.830 | 1.925 |
| sqlite3 + jsonEncode | 2.612 | 2.953 | 2.612 | 2.953 |
| sqlite_async + jsonEncode | 2.544 | 2.585 | 2.544 | 2.585 |
| drift + jsonEncode | 3.021 | 3.889 | 3.021 | 3.889 |
| resqlite selectBytes() | 0.265 | 0.267 | 0.265 | 0.267 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.804 | 6.730 | 3.804 | 6.730 |
| sqlite3 + jsonEncode | 5.529 | 8.736 | 5.529 | 8.736 |
| sqlite_async + jsonEncode | 5.362 | 9.518 | 5.362 | 9.518 |
| drift + jsonEncode | 6.516 | 9.421 | 6.516 | 9.421 |
| resqlite selectBytes() | 0.525 | 0.528 | 0.525 | 0.528 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 10.317 | 14.413 | 10.317 | 14.413 |
| sqlite3 + jsonEncode | 15.227 | 19.474 | 15.227 | 19.474 |
| sqlite_async + jsonEncode | 13.927 | 19.127 | 13.927 | 19.127 |
| drift + jsonEncode | 17.197 | 21.244 | 17.197 | 21.244 |
| resqlite selectBytes() | 1.330 | 1.352 | 1.330 | 1.352 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 23.291 | 23.998 | 23.291 | 23.998 |
| sqlite3 + jsonEncode | 32.785 | 39.738 | 32.785 | 39.738 |
| sqlite_async + jsonEncode | 32.031 | 33.442 | 32.031 | 33.442 |
| drift + jsonEncode | 36.814 | 41.264 | 36.814 | 41.264 |
| resqlite selectBytes() | 2.574 | 2.647 | 2.574 | 2.647 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 44.898 | 46.543 | 44.898 | 46.543 |
| sqlite3 + jsonEncode | 65.022 | 69.475 | 65.022 | 69.475 |
| sqlite_async + jsonEncode | 68.729 | 73.789 | 68.729 | 73.789 |
| drift + jsonEncode | 83.973 | 95.130 | 83.973 | 95.130 |
| resqlite selectBytes() | 5.398 | 6.980 | 5.398 | 6.980 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.26 | 0.26 | 0.26 |
| sqlite_async | 0.97 | 0.98 | 0.97 |
| drift | 1.44 | 1.50 | 1.44 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.29 | 0.31 | 0.14 |
| sqlite_async | 1.44 | 1.71 | 0.72 |
| drift | 2.63 | 2.97 | 1.32 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.38 | 0.64 | 0.10 |
| sqlite_async | 2.39 | 3.30 | 0.60 |
| drift | 5.03 | 5.59 | 1.26 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.73 | 1.11 | 0.09 |
| sqlite_async | 4.95 | 5.57 | 0.62 |
| drift | 10.21 | 10.77 | 1.28 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 163203 |
| resqlite per query | 0.006 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 163203 | 162728..164936 | 0.7 | 2.1 |
| sqlite3 | 194250 | 192570..194987 | 0.6 | 1.1 |
| sqlite_async | 50036 | 49775..50062 | 0.3 | 1.2 |
| drift | 49317 | 49255..49594 | 0.3 | 1.7 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.007 | 14.154 | 14.007 | 14.154 |
| sqlite_async | 36.755 | 37.457 | 36.755 | 37.457 |
| drift | 51.449 | 52.476 | 51.449 | 52.476 |
| sqlite3 (no cache) | 22.902 | 23.183 | 22.902 | 23.183 |
| sqlite3 (cached stmt) | 22.579 | 22.722 | 22.579 | 22.722 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.565 | 2.468 | 1.565 | 2.468 |
| sqlite3 execute() | 0.915 | 1.566 | 0.915 | 1.566 |
| sqlite_async execute() | 2.921 | 3.334 | 2.921 | 3.334 |
| drift execute() | 2.864 | 3.400 | 2.864 | 3.400 |

### Concurrent Single Inserts (100 concurrent)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite concurrent execute() | 0.887 | 1.303 | 0.887 | 1.303 |
| sqlite3 concurrent execute() | 0.957 | 1.677 | 0.957 | 1.677 |
| sqlite_async concurrent execute() | 2.691 | 3.394 | 2.691 | 3.394 |
| drift concurrent execute() | 1.691 | 2.427 | 1.691 | 2.427 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.052 | 0.054 | 0.052 | 0.054 |
| sqlite3 executeBatch() | 0.049 | 0.054 | 0.049 | 0.054 |
| sqlite_async executeBatch() | 0.096 | 0.104 | 0.096 | 0.104 |
| drift executeBatch() | 0.113 | 0.118 | 0.113 | 0.118 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.404 | 0.409 | 0.404 | 0.409 |
| sqlite3 executeBatch() | 0.437 | 0.447 | 0.437 | 0.447 |
| sqlite_async executeBatch() | 0.520 | 0.523 | 0.520 | 0.523 |
| drift executeBatch() | 0.647 | 0.657 | 0.647 | 0.657 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 3.791 | 4.661 | 3.791 | 4.661 |
| sqlite3 executeBatch() | 3.977 | 5.236 | 3.977 | 5.236 |
| sqlite_async executeBatch() | 4.664 | 5.446 | 4.664 | 5.446 |
| drift executeBatch() | 5.942 | 7.462 | 5.942 | 7.462 |

### Wide Batch Insert (10000 rows x 20 params)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 12.527 | 21.438 | 12.527 | 21.438 |
| sqlite3 executeBatch() | 19.280 | 21.512 | 19.280 | 21.512 |
| sqlite_async executeBatch() | 23.305 | 27.609 | 23.305 | 27.609 |
| drift executeBatch() | 25.482 | 28.515 | 25.482 | 28.515 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.053 | 0.057 | 0.053 | 0.057 |
| sqlite_async writeTransaction() | 0.087 | 0.095 | 0.087 | 0.095 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.062 | 0.072 | 0.062 | 0.072 |
| resqlite tx.execute() loop | 0.464 | 0.559 | 0.464 | 0.559 |
| sqlite_async tx.execute() loop | 1.004 | 1.087 | 1.004 | 1.087 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.406 | 0.431 | 0.406 | 0.431 |
| resqlite tx.execute() loop | 4.646 | 5.393 | 4.646 | 5.393 |
| sqlite_async tx.execute() loop | 9.667 | 10.179 | 9.667 | 10.179 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.102 | 0.106 | 0.102 | 0.106 |
| sqlite_async tx.getAll() | 0.203 | 0.213 | 0.203 | 0.213 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.170 | 0.179 | 0.170 | 0.179 |
| sqlite_async tx.getAll() | 0.352 | 0.368 | 0.352 | 0.368 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 0.719 | 0.875 | 0.719 | 0.875 |
| resqlite nested transaction() depth=5 | 0.073 | 0.086 | 0.073 | 0.086 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.026 | 0.028 | 0.026 | 0.028 |
| sqlite_async watch() | 0.103 | 0.130 | 0.103 | 0.130 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.043 | 0.059 | 0.043 | 0.059 |
| sqlite_async | 0.064 | 0.073 | 0.064 | 0.073 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.185 | 0.255 | 0.185 | 0.255 |
| sqlite_async | 0.492 | 1.014 | 0.492 | 1.014 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.062 | 2.388 | 2.062 | 2.388 |

### Long-Payload Unchanged Fanout (8 streams, 64 rows x 32KB TEXT + 32KB BLOB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.320 | 3.319 | 2.320 | 3.319 |

### Long-Text 32KB Unchanged Fanout (8 unchanged streams, 64 rows x 32KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.784 | 3.774 | 2.784 | 3.774 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.175 | 0.214 | 0.175 | 0.214 |
| sqlite_async | 0.276 | 0.301 | 0.276 | 0.301 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.273 | 1.273 | 1.273 | 1.273 |
| sqlite_async | 7.535 | 7.535 | 7.535 | 7.535 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.301 | 3.788 | 3.301 | 3.788 |
| sqlite_async | 5.338 | 6.307 | 5.338 | 6.307 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.469 | 0.655 | 0.469 | 0.655 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 6.271 | 7.037 | 6.271 | 7.037 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. For resqlite, this emission metric can reflect writer-side column-level invalidation, experiment 075's native result-hash short-circuit, or both. Use A11c (Many-Streams Writer Throughput) when the question is specifically writer-side dispatch elision.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 66.9 | 0.000 |
| sqlite_async | 4059 | 1136.8 | 0.951 |
| drift | 5000 | 1006.2 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 67.2 | 0.000 |
| sqlite_async | 4268 | 1183.4 | 0.951 |
| drift | 5000 | 1002.7 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 215.27 | 216.34 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 432.65 | 434.93 | 0.00 | 0.00 | 1114 | 3 |
| drift stream() | 527.85 | 529.67 | 0.00 | 0.01 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.019 | 0.027 | 0.000 | 0.000 |
| sqlite3 | 0.019 | 0.021 | 0.019 | 0.021 |
| sqlite_async | 0.037 | 0.043 | 0.000 | 0.000 |
| drift | 0.038 | 0.045 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.014 | 0.018 | 0.000 | 0.000 |
| sqlite3 | 0.012 | 0.013 | 0.012 | 0.013 |
| sqlite_async | 0.029 | 0.032 | 0.000 | 0.000 |
| drift | 0.030 | 0.035 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.018 | 0.028 | 0.000 | 0.000 |
| sqlite3 | 0.031 | 0.032 | 0.031 | 0.032 |
| sqlite_async | 0.056 | 0.065 | 0.000 | 0.000 |
| drift | 0.053 | 0.058 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.006 | 0.012 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.021 | 0.024 | 0.000 | 0.000 |
| drift | 0.020 | 0.024 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.038 | 0.040 | 0.001 | 0.001 |
| sqlite3 | 0.067 | 0.067 | 0.067 | 0.067 |
| sqlite_async | 0.083 | 0.085 | 0.001 | 0.001 |
| drift | 0.093 | 0.113 | 0.001 | 0.002 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 106.769 | 108.354 | 0.000 | 0.000 | 0 |
| sqlite_async | 212.510 | 212.529 | 0.000 | 0.000 | 35 |
| drift | 220.804 | 223.428 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 431.93 | 431.93 | 0.00 | 0.00 | 11.69 | 420.24 | 2 |
| sqlite_async | 471.88 | 471.88 | 0.00 | 0.00 | 12.70 | 459.18 | 1172 |
| drift | 1726.56 | 1726.56 | 0.74 | 0.74 | 12.98 | 1713.57 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 2.34 | 14.08 | 0.00..10.13 | ±5.06 |
| sqlite3 select() | 6.75 | 8.78 | 0.00..8.20 | ±4.10 |
| sqlite_async select() | 1.00 | 1.00 | 1.00..1.00 | ±0.00 |
| drift select() | 7.27 | 74.22 | 3.20..73.98 | ±35.39 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 4.02 | 0.00..1.50 | ±0.75 |
| resqlite + jsonEncode | 0.00 | 8.14 | 0.00..2.14 | ±1.07 |
| sqlite3 + jsonEncode | 0.00 | 18.97 | 0.00..11.56 | ±5.78 |
| sqlite_async + jsonEncode | 0.00 | 1.61 | 0.00..0.00 | ±0.00 |
| drift + jsonEncode | 0.00 | 21.17 | 0.00..6.39 | ±3.20 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.00 | 34.23 | 0.00..0.00 | ±0.00 |
| sqlite3 executeBatch() | 0.00 | 0.50 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 0.50 | 0.00..0.02 | ±0.01 |
| drift batch() | 0.00 | 2.00 | 0.00..0.05 | ±0.02 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.13 | 0.05..0.09 | ±0.02 |
| sqlite_async watch() | 0.00 | 0.52 | 0.00..0.02 | ±0.01 |

## SQLite Diagnostics

resqlite-only internal SQLite counters captured via `Database.diagnostics()` after representative workloads. Values reflect the writer plus idle readers in this connection pool; they are not process-global SQLite totals.

### Warm read working set (20000 rows + 2000 point lookups)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | JSON buf (KiB) | Readers busy |
|---|---|---|---|---|---|---|---|
| resqlite | 3178.6 | 3164.0 | 4.2 | 10.4 | 2048.0 | 64.0 | 0 |

### Statement cache footprint (48 distinct SELECT texts)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | JSON buf (KiB) | Readers busy |
|---|---|---|---|---|---|---|---|
| resqlite | 3271.6 | 3164.0 | 4.2 | 103.4 | 2048.0 | 64.0 | 0 |

### WAL after write burst (1000 inserted rows)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | JSON buf (KiB) | Readers busy |
|---|---|---|---|---|---|---|---|
| resqlite | 229.1 | 214.5 | 4.2 | 10.4 | 161.0 | 64.0 | 0 |

### JSON buffer reclaim (8 large selectBytes + 64 small settles)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | JSON buf (KiB) | Readers busy |
|---|---|---|---|---|---|---|---|
| resqlite | 2280.1 | 2250.3 | 5.9 | 24.0 | 2088.2 | 64.0 | 0 |

## Repeat Stability

These rows summarize resqlite wall medians across repeated full-suite runs.
Use this section to judge whether small deltas are real or just noise.

| Benchmark | Median (ms) | 95% CI (ms) | MDE_ci | Range | MAD | Stability |
|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.02 | 0.02..0.02 | 2.8% | 5.6% | 0.0% | stable |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 8.3% | 16.7% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02..0.02 | 7.9% | 15.8% | 5.3% | moderate |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.01..0.02 | 7.1% | 14.3% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.27 | 0.26..0.27 | 1.9% | 3.7% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.27 | 0.26..0.27 | 1.9% | 3.7% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.29 | 0.27..0.29 | 3.4% | 6.9% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.14 | 0.14..0.15 | 3.6% | 7.1% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.35 | 0.33..0.38 | 7.1% | 14.3% | 5.7% | moderate |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.09 | 0.08..0.10 | 11.1% | 22.2% | 11.1% | noisy |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.62 | 0.60..0.80 | 16.1% | 32.3% | 3.2% | moderate |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.08 | 0.07..0.10 | 18.8% | 37.5% | 12.5% | noisy |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.04 | 2.6% | 5.1% | 2.6% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 150.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 106.94 | 106.75..107.93 | 0.6% | 1.1% | 0.2% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 230.38 | 228.80..431.93 | 44.1% | 88.2% | 0.5% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 215.22 | 213.99..215.85 | 0.4% | 0.9% | 0.3% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 14.01 | 13.91..14.61 | 2.5% | 5.0% | 0.7% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 14.01 | 13.91..14.61 | 2.5% | 5.0% | 0.7% | stable |
| Point Query Throughput / resqlite qps | 163441.00 | 159326.00..166913.00 | 2.3% | 4.6% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.01 | 25.0% | 50.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.04 | 13.8% | 27.6% | 3.4% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.04 | 13.8% | 27.6% | 3.4% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.01 | 9.1% | 18.2% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.01 | 9.1% | 18.2% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.04..0.04 | 3.8% | 7.5% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.20 | 0.20..0.21 | 1.2% | 2.5% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.20 | 0.20..0.21 | 1.2% | 2.5% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.04 | 0.03..0.04 | 5.6% | 11.1% | 5.6% | moderate |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.04 | 0.03..0.04 | 5.6% | 11.1% | 5.6% | moderate |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.32 | 0.32..0.32 | 0.5% | 0.9% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.83 | 1.83..1.88 | 1.4% | 2.8% | 0.1% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.83 | 1.83..1.88 | 1.4% | 2.8% | 0.1% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.05 | 0.05..0.05 | 0.9% | 1.9% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.26 | 0.26..0.27 | 1.0% | 1.9% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.26 | 0.26..0.27 | 1.0% | 1.9% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 3.48 | 3.37..3.53 | 2.3% | 4.6% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 23.57 | 20.98..24.28 | 7.0% | 14.0% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 23.57 | 20.98..24.28 | 7.0% | 14.0% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.53 | 0.53..0.54 | 1.4% | 2.8% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 2.66 | 2.55..2.67 | 2.1% | 4.3% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 2.66 | 2.55..2.67 | 2.1% | 4.3% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.62 | 0.61..0.63 | 1.1% | 2.3% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.80 | 3.79..3.84 | 0.6% | 1.1% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.80 | 3.79..3.84 | 0.6% | 1.1% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.11 | 0.10..0.11 | 1.4% | 2.8% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.51 | 0.49..0.54 | 4.3% | 8.7% | 2.8% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.51 | 0.49..0.54 | 4.3% | 8.7% | 2.8% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 8.81 | 8.66..9.04 | 2.2% | 4.4% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 44.55 | 43.79..45.29 | 1.7% | 3.4% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 44.55 | 43.79..45.29 | 1.7% | 3.4% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.06 | 1.05..1.06 | 0.4% | 0.9% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 5.41 | 5.36..5.72 | 3.4% | 6.7% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 5.41 | 5.36..5.72 | 3.4% | 6.7% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.02 | 0.02..0.03 | 6.5% | 13.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.11..0.11 | 2.8% | 5.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.11 | 0.11..0.11 | 2.8% | 5.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.02 | 0.02..0.03 | 8.7% | 17.4% | 4.3% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.02 | 0.02..0.03 | 8.7% | 17.4% | 4.3% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.17 | 0.16..0.17 | 1.5% | 3.0% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.94 | 0.93..1.19 | 13.7% | 27.3% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.94 | 0.93..1.19 | 13.7% | 27.3% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.03 | 0.03..0.03 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.14 | 0.13..0.14 | 2.2% | 4.4% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.14 | 0.13..0.14 | 2.2% | 4.4% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 1.78 | 1.76..1.81 | 1.5% | 3.1% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 10.32 | 10.10..12.33 | 10.8% | 21.7% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 10.32 | 10.10..12.33 | 10.8% | 21.7% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.27 | 0.26..0.27 | 0.4% | 0.8% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 1.29 | 1.25..1.33 | 3.0% | 5.9% | 2.5% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 1.29 | 1.25..1.33 | 3.0% | 5.9% | 2.5% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.09 | 0.09..0.11 | 14.5% | 29.1% | 1.2% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.02 | 0.01..0.02 | 19.6% | 39.1% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.25 | 0.25..0.26 | 0.8% | 1.6% | 0.4% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.06 | 0.06..0.06 | 0.0% | 0.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.25 | 0.24..0.25 | 2.2% | 4.5% | 0.4% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.06 | 0.06..0.06 | 1.6% | 3.2% | 0.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.38 | 0.38..0.38 | 1.0% | 2.1% | 0.3% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.06 | 0.06..0.06 | 0.0% | 0.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.80 | 0.80..0.81 | 0.6% | 1.1% | 0.2% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.23 | 0.23..0.23 | 0.4% | 0.9% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.06 | 53.6% | 107.1% | 3.6% | moderate |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02..0.04 | 55.9% | 111.8% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 20.8% | 41.7% | 8.3% | noisy |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.20..0.22 | 4.4% | 8.9% | 0.5% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.17 | 0.16..0.17 | 3.6% | 7.2% | 0.6% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.03..0.04 | 10.0% | 20.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.85 | 1.84..1.91 | 1.8% | 3.6% | 0.6% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.58 | 1.56..1.63 | 2.1% | 4.2% | 0.8% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.27 | 0.26..0.28 | 2.6% | 5.3% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.82 | 20.16..22.05 | 4.5% | 9.1% | 3.2% | moderate |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 15.90 | 15.89..16.25 | 1.1% | 2.2% | 0.1% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 2.68 | 2.63..2.72 | 1.8% | 3.7% | 0.3% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / Large payload (~650KB) / resqlite selectBytes() | 0.23 | 0.23..0.28 | 10.4% | 20.9% | 0.4% | stable |
| Select → JSON Bytes / Large payload (~650KB) / resqlite selectBytes... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.06 | 218.2% | 436.4% | 9.1% | noisy |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.04 | 0.04..0.15 | 138.7% | 277.5% | 2.5% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 20.0% | 40.0% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.32 | 0.32..0.38 | 9.4% | 18.9% | 0.3% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.05 | 0.05..0.06 | 4.7% | 9.4% | 0.0% | stable |
| Select → Maps / 10000 rows / resqlite select() | 3.44 | 3.35..3.56 | 3.1% | 6.3% | 2.5% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.52 | 0.52..0.53 | 1.4% | 2.9% | 0.6% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.17 | 0.16..0.21 | 14.9% | 29.7% | 8.6% | noisy |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.17 | 0.16..0.21 | 14.9% | 29.7% | 8.6% | noisy |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.47 | 0.47..0.60 | 14.2% | 28.3% | 0.8% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.47 | 0.47..0.60 | 14.2% | 28.3% | 0.8% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03..0.07 | 75.0% | 150.0% | 10.0% | noisy |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03..0.07 | 75.0% | 150.0% | 10.0% | noisy |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.04..0.04 | 4.5% | 9.1% | 2.3% | stable |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.04..0.04 | 4.5% | 9.1% | 2.3% | stable |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows x 32K... | 2.37 | 1.97..2.67 | 14.7% | 29.4% | 11.9% | noisy |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows x 32K... | 2.37 | 1.97..2.67 | 14.7% | 29.4% | 11.9% | noisy |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged streams, 6... | 2.55 | 2.35..2.78 | 8.6% | 17.1% | 5.1% | moderate |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged streams, 6... | 2.55 | 2.35..2.78 | 8.6% | 17.1% | 5.1% | moderate |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 1.67 | 1.43..2.06 | 19.0% | 38.1% | 14.6% | noisy |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 1.67 | 1.43..2.06 | 19.0% | 38.1% | 14.6% | noisy |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.22 | 3.06..3.30 | 3.7% | 7.4% | 1.9% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.22 | 3.06..3.30 | 3.7% | 7.4% | 1.9% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.40 | 1.27..2.65 | 49.3% | 98.5% | 9.3% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.40 | 1.27..2.65 | 49.3% | 98.5% | 9.3% | noisy |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.27 | 6.19..7.43 | 9.9% | 19.7% | 1.3% | stable |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.27 | 6.19..7.43 | 9.9% | 19.7% | 1.3% | stable |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.18 | 0.17..0.23 | 16.2% | 32.4% | 7.0% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.18 | 0.17..0.23 | 16.2% | 32.4% | 7.0% | moderate |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.05 | 0.05..0.05 | 1.9% | 3.8% | 1.9% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.05 | 0.05..0.05 | 1.9% | 3.8% | 1.9% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.41 | 0.40..0.41 | 0.7% | 1.5% | 0.5% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.41 | 0.40..0.41 | 0.7% | 1.5% | 0.5% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.81 | 3.76..4.02 | 3.4% | 6.9% | 1.4% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.81 | 3.76..4.02 | 3.4% | 6.9% | 1.4% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.48 | 0.40..0.58 | 18.5% | 37.0% | 12.4% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.48 | 0.40..0.58 | 18.5% | 37.0% | 12.4% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.06 | 0.06..0.07 | 4.7% | 9.4% | 3.1% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.06 | 0.06..0.07 | 4.7% | 9.4% | 3.1% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 4.84 | 4.65..5.20 | 5.7% | 11.5% | 4.1% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 4.84 | 4.65..5.20 | 5.7% | 11.5% | 4.1% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.41 | 0.41..0.41 | 1.0% | 2.0% | 0.5% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.41 | 0.41..0.41 | 1.0% | 2.0% | 0.5% | stable |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 0.86 | 0.83..0.89 | 3.1% | 6.1% | 2.8% | stable |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 0.86 | 0.83..0.89 | 3.1% | 6.1% | 2.8% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05..0.05 | 7.0% | 14.0% | 6.0% | moderate |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05..0.05 | 7.0% | 14.0% | 6.0% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.07 | 0.06..0.08 | 11.1% | 22.2% | 2.8% | stable |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.07 | 0.06..0.08 | 11.1% | 22.2% | 2.8% | stable |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.76 | 0.72..0.84 | 7.7% | 15.4% | 5.1% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.76 | 0.72..0.84 | 7.7% | 15.4% | 5.1% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.56 | 1.49..1.65 | 4.9% | 9.8% | 3.7% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.56 | 1.49..1.65 | 4.9% | 9.8% | 3.7% | moderate |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.17..0.18 | 2.3% | 4.5% | 0.6% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.17..0.18 | 2.3% | 4.5% | 0.6% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.10 | 0.10..0.11 | 4.4% | 8.8% | 1.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.10 | 0.10..0.11 | 4.4% | 8.8% | 1.0% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 12.69 | 12.53..13.69 | 4.6% | 9.2% | 1.3% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 12.69 | 12.53..13.69 | 4.6% | 9.2% | 1.3% | stable |


## Baseline Compatibility

This is an explicit comparison against `2026-08-09T20-36-47-exp266-headline-refresh.md`, but the baseline environment differs from the current run:
- hostname differs: current `macbookpro.lan` vs baseline `enterprise.local`

Treat the comparison as a reference check, not a gate.


## Comparison vs Previous Run

Previous: `2026-08-09T20-36-47-exp266-headline-refresh.md` (cross-repeat aggregate medians)

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 2.8% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 8.3% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02 | +0.00 | ±16% / ±0.02 ms | 7.9% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 7.1% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.26 | 0.27 | +0.01 | ±10% / ±0.03 ms | 1.9% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.26 | 0.27 | +0.01 | ±10% / ±0.03 ms | 1.9% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.29 | 0.29 | +0.00 | ±10% / ±0.03 ms | 3.4% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.14 | 0.14 | +0.00 | ±10% / ±0.02 ms | 3.6% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.33 | 0.35 | +0.02 | ±17% / ±0.06 ms | 7.1% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.08 | 0.09 | +0.01 | ±33% / ±0.03 ms | 11.1% | noisy | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.61 | 0.62 | +0.01 | ±16% / ±0.10 ms | 16.1% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.08 | 0.08 | +0.00 | ±37% / ±0.03 ms | 18.8% | noisy | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 2.6% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±150% / ±0.02 ms | 150.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 109.26 | 106.94 | -2.32 | ±10% / ±10.93 ms | 0.6% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 237.79 | 230.38 | -7.41 | ±44% / ±104.83 ms | 44.1% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 217.93 | 215.22 | -2.71 | ±10% / ±21.79 ms | 0.4% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.08 | 14.01 | -0.08 | ±10% / ±1.41 ms | 2.5% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.08 | 14.01 | -0.08 | ±10% / ±1.41 ms | 2.5% | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 164941.00 | 163441.00 | -1500.00 | ±10% / ±16494.10 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01 | +0.00 | ±25% / ±0.02 ms | 25.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±14% / ±0.02 ms | 13.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.03 | +0.00 | ±14% / ±0.02 ms | 13.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | 9.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | 9.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 3.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.20 | 0.20 | +0.00 | ±10% / ±0.02 ms | 1.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.20 | 0.20 | +0.00 | ±10% / ±0.02 ms | 1.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | -0.00 | ±17% / ±0.02 ms | 5.6% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | -0.00 | ±17% / ±0.02 ms | 5.6% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.32 | 0.32 | +0.00 | ±10% / ±0.03 ms | 0.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.89 | 1.83 | -0.06 | ±10% / ±0.19 ms | 1.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.89 | 1.83 | -0.06 | ±10% / ±0.19 ms | 1.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 0.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.27 | 0.26 | -0.01 | ±10% / ±0.03 ms | 1.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.27 | 0.26 | -0.01 | ±10% / ±0.03 ms | 1.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 3.44 | 3.48 | +0.04 | ±10% / ±0.35 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 23.34 | 23.57 | +0.23 | ±10% / ±2.36 ms | 7.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 23.34 | 23.57 | +0.23 | ±10% / ±2.36 ms | 7.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.53 | 0.53 | -0.00 | ±10% / ±0.05 ms | 1.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 2.60 | 2.66 | +0.06 | ±10% / ±0.27 ms | 2.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 2.60 | 2.66 | +0.06 | ±10% / ±0.27 ms | 2.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.63 | 0.62 | -0.01 | ±10% / ±0.06 ms | 1.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.84 | 3.80 | -0.03 | ±10% / ±0.38 ms | 0.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.84 | 3.80 | -0.03 | ±10% / ±0.38 ms | 0.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.11 | 0.11 | -0.00 | ±10% / ±0.02 ms | 1.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.52 | 0.51 | -0.02 | ±10% / ±0.05 ms | 4.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.52 | 0.51 | -0.02 | ±10% / ±0.05 ms | 4.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 8.76 | 8.81 | +0.05 | ±10% / ±0.88 ms | 2.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 44.32 | 44.55 | +0.22 | ±10% / ±4.45 ms | 1.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 44.32 | 44.55 | +0.22 | ±10% / ±4.45 ms | 1.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.07 | 1.06 | -0.01 | ±10% / ±0.11 ms | 0.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 5.49 | 5.41 | -0.07 | ±10% / ±0.55 ms | 3.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 5.49 | 5.41 | -0.07 | ±10% / ±0.55 ms | 3.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.02 | 0.02 | -0.00 | ±10% / ±0.02 ms | 6.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | 2.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | 2.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.02 | -0.00 | ±13% / ±0.02 ms | 8.7% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.02 | -0.00 | ±13% / ±0.02 ms | 8.7% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.16 | 0.17 | +0.00 | ±10% / ±0.02 ms | 1.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.98 | 0.94 | -0.04 | ±14% / ±0.13 ms | 13.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.98 | 0.94 | -0.04 | ±14% / ±0.13 ms | 13.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.14 | 0.14 | +0.00 | ±10% / ±0.02 ms | 2.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.14 | 0.14 | +0.00 | ±10% / ±0.02 ms | 2.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 1.78 | 1.78 | +0.00 | ±10% / ±0.18 ms | 1.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.55 | 10.32 | -0.23 | ±11% / ±1.14 ms | 10.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.55 | 10.32 | -0.23 | ±11% / ±1.14 ms | 10.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.27 | 0.27 | -0.00 | ±10% / ±0.03 ms | 0.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.33 | 1.29 | -0.04 | ±10% / ±0.13 ms | 3.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.33 | 1.29 | -0.04 | ±10% / ±0.13 ms | 3.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.09 | 0.09 | +0.00 | ±15% / ±0.02 ms | 14.5% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.02 | 0.02 | +0.00 | ±20% / ±0.02 ms | 19.6% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.25 | 0.25 | -0.00 | ±10% / ±0.03 ms | 0.8% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.24 | 0.25 | +0.00 | ±10% / ±0.02 ms | 2.2% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 1.6% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.38 | 0.38 | +0.01 | ±10% / ±0.04 ms | 1.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.81 | 0.80 | -0.01 | ±10% / ±0.08 ms | 0.6% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.23 | 0.23 | -0.00 | ±10% / ±0.02 ms | 0.4% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±54% / ±0.02 ms | 53.6% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02 | +0.00 | ±56% / ±0.02 ms | 55.9% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | +0.00 | ±25% / ±0.02 ms | 20.8% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.20 | +0.00 | ±10% / ±0.02 ms | 4.4% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.17 | 0.17 | +0.00 | ±10% / ±0.02 ms | 3.6% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 10.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.88 | 1.85 | -0.03 | ±10% / ±0.19 ms | 1.8% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.60 | 1.58 | -0.02 | ±10% / ±0.16 ms | 2.1% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.26 | 0.27 | +0.01 | ±10% / ±0.03 ms | 2.6% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.41 | 20.82 | +0.41 | ±10% / ±2.08 ms | 4.5% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 15.79 | 15.90 | +0.12 | ±10% / ±1.59 ms | 1.1% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 2.68 | 2.68 | -0.00 | ±10% / ±0.27 ms | 1.8% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / Large payload (~650KB) / resqlite s... | 0.24 | 0.23 | -0.01 | ±10% / ±0.03 ms | 10.4% | stable | ⚪ Within noise |
| Select → JSON Bytes / Large payload (~650KB) / resqlite s... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | +0.00 | ±218% / ±0.02 ms | 218.2% | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.04 | 0.04 | +0.00 | ±139% / ±0.06 ms | 138.7% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±20% / ±0.02 ms | 20.0% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.31 | 0.32 | +0.01 | ±10% / ±0.03 ms | 9.4% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 4.7% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 3.44 | 3.44 | -0.01 | ±10% / ±0.34 ms | 3.1% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.51 | 0.52 | +0.01 | ±10% / ±0.05 ms | 1.4% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.19 | 0.17 | -0.02 | ±26% / ±0.05 ms | 14.9% | noisy | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.19 | 0.17 | -0.02 | ±26% / ±0.05 ms | 14.9% | noisy | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.48 | 0.47 | -0.01 | ±14% / ±0.07 ms | 14.2% | stable | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.48 | 0.47 | -0.01 | ±14% / ±0.07 ms | 14.2% | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | +0.00 | ±75% / ±0.02 ms | 75.0% | noisy | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03 | +0.00 | ±75% / ±0.02 ms | 75.0% | noisy | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.04 | -0.00 | ±10% / ±0.02 ms | 4.5% | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.05 | 0.04 | -0.00 | ±10% / ±0.02 ms | 4.5% | stable | ⚪ Within noise |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 ... | 2.65 | 2.37 | -0.28 | ±36% / ±0.95 ms | 14.7% | noisy | ⚪ Within noise |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 ... | 2.65 | 2.37 | -0.28 | ±36% / ±0.95 ms | 14.7% | noisy | ⚪ Within noise |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged ... | 2.76 | 2.55 | -0.21 | ±15% / ±0.42 ms | 8.6% | moderate | ⚪ Within noise |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged ... | 2.76 | 2.55 | -0.21 | ±15% / ±0.42 ms | 8.6% | moderate | ⚪ Within noise |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 1.55 | 1.67 | +0.12 | ±44% / ±0.73 ms | 19.0% | noisy | ⚪ Within noise |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 1.55 | 1.67 | +0.12 | ±44% / ±0.73 ms | 19.0% | noisy | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.18 | 3.22 | +0.04 | ±10% / ±0.32 ms | 3.7% | stable | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.18 | 3.22 | +0.04 | ±10% / ±0.32 ms | 3.7% | stable | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.58 | 1.40 | -0.17 | ±49% / ±0.78 ms | 49.3% | noisy | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.58 | 1.40 | -0.17 | ±49% / ±0.78 ms | 49.3% | noisy | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.27 | 6.27 | +0.00 | ±10% / ±0.63 ms | 9.9% | stable | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.27 | 6.27 | +0.00 | ±10% / ±0.63 ms | 9.9% | stable | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.19 | 0.18 | -0.00 | ±21% / ±0.04 ms | 16.2% | moderate | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.19 | 0.18 | -0.00 | ±21% / ±0.04 ms | 16.2% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 1.9% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 1.9% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.41 | 0.41 | -0.00 | ±10% / ±0.04 ms | 0.7% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.41 | 0.41 | -0.00 | ±10% / ±0.04 ms | 0.7% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.93 | 3.81 | -0.12 | ±10% / ±0.39 ms | 3.4% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.93 | 3.81 | -0.12 | ±10% / ±0.39 ms | 3.4% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.52 | 0.48 | -0.04 | ±37% / ±0.19 ms | 18.5% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.52 | 0.48 | -0.04 | ±37% / ±0.19 ms | 18.5% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.06 | -0.00 | ±10% / ±0.02 ms | 4.7% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.06 | -0.00 | ±10% / ±0.02 ms | 4.7% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 5.01 | 4.84 | -0.16 | ±12% / ±0.62 ms | 5.7% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 5.01 | 4.84 | -0.16 | ±12% / ±0.62 ms | 5.7% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.40 | 0.41 | +0.01 | ±10% / ±0.04 ms | 1.0% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.40 | 0.41 | +0.01 | ±10% / ±0.04 ms | 1.0% | stable | ⚪ Within noise |
| Write Performance / Concurrent Single Inserts (100 concur... | 0.83 | 0.86 | +0.03 | ±10% / ±0.09 ms | 3.1% | stable | ⚪ Within noise |
| Write Performance / Concurrent Single Inserts (100 concur... | 0.83 | 0.86 | +0.03 | ±10% / ±0.09 ms | 3.1% | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.05 | +0.00 | ±18% / ±0.02 ms | 7.0% | moderate | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.05 | +0.00 | ±18% / ±0.02 ms | 7.0% | moderate | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.07 | 0.07 | +0.00 | ±11% / ±0.02 ms | 11.1% | stable | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.07 | 0.07 | +0.00 | ±11% / ±0.02 ms | 11.1% | stable | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.88 | 0.76 | -0.12 | ±15% / ±0.14 ms | 7.7% | moderate | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.88 | 0.76 | -0.12 | ±15% / ±0.14 ms | 7.7% | moderate | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.54 | 1.56 | +0.02 | ±11% / ±0.17 ms | 4.9% | moderate | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.54 | 1.56 | +0.02 | ±11% / ±0.17 ms | 4.9% | moderate | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.18 | +0.00 | ±10% / ±0.02 ms | 2.3% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.18 | +0.00 | ±10% / ±0.02 ms | 2.3% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 4.4% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 4.4% | stable | ⚪ Within noise |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 13.18 | 12.69 | -0.49 | ±10% / ±1.32 ms | 4.6% | stable | ⚪ Within noise |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 13.18 | 12.69 | -0.49 | ±10% / ±1.32 ms | 4.6% | stable | ⚪ Within noise |

**Summary:** 0 wins, 0 regressions, 169 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

✅ **No changes beyond noise.**


## Memory Comparison vs Previous Run

Previous run has no `## Memory` section — baseline unavailable. Current values recorded for next-run comparison.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 4193 | 4059 | -134 | ±100 | 🟢 Fewer re-emits (-134) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 3595 | 4268 | +673 | ±100 | 🔴 More re-emits (+673) |

**Granularity summary:** 1 fewer-re-emit, 1 more-re-emit, 4 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


