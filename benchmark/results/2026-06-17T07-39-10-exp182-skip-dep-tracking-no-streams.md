# resqlite Benchmark Results

Generated: 2026-06-17T07:39:10.187708

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp182-skip-dep-tracking-no-streams`
- Repeats: `1`
- Runtime: `dart-vm / Dart 3.11.5`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `exp-182-skip-dep-tracking-no-streams @ 438ffb39606a (dirty)`
- Comparison baseline: `2026-06-17T07-36-54-baseline-for-exp182.md`
- Comparison mode: `explicit`
- Comparison baseline compatibility: `compatible`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.082 | 0.111 | 0.018 | 0.023 |
| sqlite3 select() | 0.124 | 0.252 | 0.124 | 0.252 |
| sqlite_async select() | 0.164 | 0.252 | 0.019 | 0.020 |
| drift select() | 0.140 | 0.204 | 0.008 | 0.011 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.055 | 0.125 | 0.007 | 0.010 |
| sqlite3 select() | 0.209 | 0.273 | 0.209 | 0.273 |
| sqlite_async select() | 0.226 | 0.272 | 0.012 | 0.014 |
| drift select() | 0.302 | 0.464 | 0.011 | 0.014 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.355 | 0.459 | 0.052 | 0.060 |
| sqlite3 select() | 1.140 | 1.408 | 1.140 | 1.408 |
| sqlite_async select() | 1.095 | 1.198 | 0.073 | 0.078 |
| drift select() | 1.599 | 1.818 | 0.075 | 0.083 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.199 | 9.040 | 0.511 | 0.755 |
| sqlite3 select() | 13.610 | 16.055 | 13.610 | 16.055 |
| sqlite_async select() | 12.227 | 13.252 | 0.728 | 1.764 |
| drift select() | 21.589 | 25.934 | 0.738 | 2.566 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.123 | 0.147 | 0.102 | 0.110 |
| sqlite3 + jsonEncode | 0.101 | 0.206 | 0.101 | 0.206 |
| sqlite_async + jsonEncode | 0.112 | 0.165 | 0.029 | 0.032 |
| drift + jsonEncode | 0.095 | 0.123 | 0.026 | 0.030 |
| resqlite selectBytes() | 0.019 | 0.024 | 0.000 | 0.001 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.224 | 0.285 | 0.175 | 0.218 |
| sqlite3 + jsonEncode | 0.270 | 0.532 | 0.270 | 0.532 |
| sqlite_async + jsonEncode | 0.306 | 0.527 | 0.154 | 0.179 |
| drift + jsonEncode | 0.346 | 0.375 | 0.154 | 0.165 |
| resqlite selectBytes() | 0.050 | 0.053 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.781 | 3.689 | 1.468 | 2.789 |
| sqlite3 + jsonEncode | 2.533 | 4.941 | 2.533 | 4.941 |
| sqlite_async + jsonEncode | 2.549 | 4.231 | 1.466 | 2.615 |
| drift + jsonEncode | 2.956 | 4.657 | 1.450 | 2.310 |
| resqlite selectBytes() | 0.359 | 0.385 | 0.000 | 0.000 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.719 | 22.098 | 14.654 | 17.225 |
| sqlite3 + jsonEncode | 30.207 | 32.173 | 30.207 | 32.173 |
| sqlite_async + jsonEncode | 29.464 | 33.261 | 14.916 | 16.473 |
| drift + jsonEncode | 36.269 | 42.853 | 14.900 | 17.378 |
| resqlite selectBytes() | 3.555 | 4.092 | 0.000 | 0.005 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.081 | 0.252 | 0.014 | 0.176 |
| sqlite3 | 0.328 | 0.540 | 0.328 | 0.540 |
| sqlite_async | 0.398 | 0.479 | 0.035 | 0.039 |
| drift | 0.594 | 0.846 | 0.033 | 0.043 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.849 | 0.869 | 0.204 | 0.213 |
| sqlite3 | 3.263 | 3.595 | 3.263 | 3.595 |
| sqlite_async | 2.967 | 3.284 | 0.235 | 0.242 |
| drift | 4.645 | 6.419 | 0.241 | 0.255 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.502 | 0.533 | 0.062 | 0.066 |
| sqlite3 | 1.447 | 1.483 | 1.447 | 1.483 |
| sqlite_async | 1.382 | 1.607 | 0.085 | 0.095 |
| drift | 1.960 | 2.238 | 0.088 | 0.095 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.257 | 0.275 | 0.061 | 0.067 |
| sqlite3 | 1.007 | 1.031 | 1.007 | 1.031 |
| sqlite_async | 0.957 | 1.115 | 0.084 | 0.090 |
| drift | 1.461 | 1.640 | 0.084 | 0.093 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.260 | 0.272 | 0.060 | 0.062 |
| sqlite3 | 0.973 | 1.629 | 0.973 | 1.629 |
| sqlite_async | 0.973 | 1.132 | 0.084 | 0.091 |
| drift | 1.447 | 1.607 | 0.085 | 0.088 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.013 | 0.014 | 0.001 | 0.001 |
| sqlite3 | 0.021 | 0.022 | 0.021 | 0.022 |
| sqlite_async | 0.067 | 0.080 | 0.004 | 0.005 |
| drift | 0.056 | 0.073 | 0.004 | 0.005 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.026 | 0.028 | 0.003 | 0.003 |
| sqlite3 | 0.066 | 0.069 | 0.066 | 0.069 |
| sqlite_async | 0.100 | 0.117 | 0.005 | 0.007 |
| drift | 0.117 | 0.123 | 0.006 | 0.006 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.044 | 0.046 | 0.005 | 0.006 |
| sqlite3 | 0.120 | 0.132 | 0.120 | 0.132 |
| sqlite_async | 0.149 | 0.165 | 0.009 | 0.010 |
| drift | 0.194 | 0.209 | 0.010 | 0.011 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.177 | 0.199 | 0.026 | 0.027 |
| sqlite3 | 0.566 | 0.592 | 0.566 | 0.592 |
| sqlite_async | 0.568 | 0.692 | 0.038 | 0.048 |
| drift | 0.797 | 0.865 | 0.037 | 0.041 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.349 | 0.358 | 0.053 | 0.054 |
| sqlite3 | 1.110 | 1.149 | 1.110 | 1.149 |
| sqlite_async | 1.048 | 1.106 | 0.072 | 0.077 |
| drift | 1.558 | 1.737 | 0.071 | 0.076 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.727 | 0.964 | 0.107 | 0.110 |
| sqlite3 | 2.224 | 2.586 | 2.224 | 2.586 |
| sqlite_async | 2.094 | 2.329 | 0.143 | 0.152 |
| drift | 3.099 | 4.020 | 0.142 | 0.154 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.971 | 5.018 | 0.262 | 0.323 |
| sqlite3 | 5.644 | 6.861 | 5.644 | 6.861 |
| sqlite_async | 5.325 | 7.161 | 0.358 | 0.385 |
| drift | 8.443 | 8.657 | 0.359 | 0.368 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.089 | 9.837 | 0.525 | 0.968 |
| sqlite3 | 13.904 | 16.419 | 13.904 | 16.419 |
| sqlite_async | 12.305 | 17.911 | 0.726 | 1.993 |
| drift | 22.659 | 27.218 | 0.751 | 2.621 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 10.796 | 15.603 | 1.043 | 1.863 |
| sqlite3 | 31.202 | 36.394 | 31.202 | 36.394 |
| sqlite_async | 34.388 | 38.766 | 1.446 | 1.668 |
| drift | 45.858 | 56.481 | 1.443 | 6.415 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.034 | 0.035 | 0.034 | 0.035 |
| sqlite3 + jsonEncode | 0.038 | 0.053 | 0.038 | 0.053 |
| sqlite_async + jsonEncode | 0.074 | 0.115 | 0.074 | 0.115 |
| drift + jsonEncode | 0.074 | 0.114 | 0.074 | 0.114 |
| resqlite selectBytes() | 0.011 | 0.015 | 0.011 | 0.015 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.104 | 0.121 | 0.104 | 0.121 |
| sqlite3 + jsonEncode | 0.152 | 0.471 | 0.152 | 0.471 |
| sqlite_async + jsonEncode | 0.169 | 0.175 | 0.169 | 0.175 |
| drift + jsonEncode | 0.191 | 0.219 | 0.191 | 0.219 |
| resqlite selectBytes() | 0.026 | 0.027 | 0.026 | 0.027 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.196 | 0.216 | 0.196 | 0.216 |
| sqlite3 + jsonEncode | 0.261 | 0.277 | 0.261 | 0.277 |
| sqlite_async + jsonEncode | 0.286 | 0.300 | 0.286 | 0.300 |
| drift + jsonEncode | 0.331 | 0.346 | 0.331 | 0.346 |
| resqlite selectBytes() | 0.044 | 0.046 | 0.044 | 0.046 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.906 | 1.899 | 0.906 | 1.899 |
| sqlite3 + jsonEncode | 1.279 | 2.585 | 1.279 | 2.585 |
| sqlite_async + jsonEncode | 1.267 | 2.062 | 1.267 | 2.062 |
| drift + jsonEncode | 1.502 | 2.457 | 1.502 | 2.457 |
| resqlite selectBytes() | 0.182 | 0.188 | 0.182 | 0.188 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.737 | 2.650 | 1.737 | 2.650 |
| sqlite3 + jsonEncode | 2.489 | 4.743 | 2.489 | 4.743 |
| sqlite_async + jsonEncode | 2.452 | 4.432 | 2.452 | 4.432 |
| drift + jsonEncode | 2.963 | 4.964 | 2.963 | 4.964 |
| resqlite selectBytes() | 0.348 | 0.365 | 0.348 | 0.365 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.745 | 5.640 | 3.745 | 5.640 |
| sqlite3 + jsonEncode | 5.127 | 7.760 | 5.127 | 7.760 |
| sqlite_async + jsonEncode | 5.148 | 7.749 | 5.148 | 7.749 |
| drift + jsonEncode | 6.285 | 8.908 | 6.285 | 8.908 |
| resqlite selectBytes() | 0.685 | 0.697 | 0.685 | 0.697 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 9.881 | 12.074 | 9.881 | 12.074 |
| sqlite3 + jsonEncode | 14.645 | 17.155 | 14.645 | 17.155 |
| sqlite_async + jsonEncode | 13.373 | 17.950 | 13.373 | 17.950 |
| drift + jsonEncode | 17.043 | 18.479 | 17.043 | 18.479 |
| resqlite selectBytes() | 1.730 | 1.761 | 1.730 | 1.761 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.298 | 22.566 | 20.298 | 22.566 |
| sqlite3 + jsonEncode | 29.947 | 31.882 | 29.947 | 31.882 |
| sqlite_async + jsonEncode | 30.000 | 32.500 | 30.000 | 32.500 |
| drift + jsonEncode | 38.502 | 42.476 | 38.502 | 42.476 |
| resqlite selectBytes() | 3.541 | 5.089 | 3.541 | 5.089 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 42.530 | 45.134 | 42.530 | 45.134 |
| sqlite3 + jsonEncode | 61.245 | 65.619 | 61.245 | 65.619 |
| sqlite_async + jsonEncode | 64.749 | 69.653 | 64.749 | 69.653 |
| drift + jsonEncode | 76.627 | 93.548 | 76.627 | 93.548 |
| resqlite selectBytes() | 7.138 | 8.186 | 7.138 | 8.186 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.29 | 0.31 | 0.29 |
| sqlite_async | 0.99 | 1.12 | 0.99 |
| drift | 1.48 | 1.56 | 1.48 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.31 | 0.15 |
| sqlite_async | 1.45 | 1.72 | 0.73 |
| drift | 2.72 | 3.29 | 1.36 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.36 | 0.57 | 0.09 |
| sqlite_async | 2.44 | 2.88 | 0.61 |
| drift | 5.24 | 5.64 | 1.31 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.70 | 0.99 | 0.09 |
| sqlite_async | 5.11 | 5.56 | 0.64 |
| drift | 10.71 | 11.55 | 1.34 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 153516 |
| resqlite per query | 0.007 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 153516 | 150886..154528 | 1.2 | 2.9 |
| sqlite3 | 200487 | 200258..201210 | 0.2 | 1.1 |
| sqlite_async | 52187 | 52087..52518 | 0.4 | 1.9 |
| drift | 48780 | 48439..49101 | 0.7 | 2.1 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.075 | 14.642 | 14.075 | 14.642 |
| sqlite_async | 36.099 | 36.920 | 36.099 | 36.920 |
| drift | 52.354 | 53.753 | 52.354 | 53.753 |
| sqlite3 (no cache) | 23.938 | 24.246 | 23.938 | 24.246 |
| sqlite3 (cached stmt) | 23.677 | 24.034 | 23.677 | 24.034 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.381 | 1.866 | 1.381 | 1.866 |
| sqlite3 execute() | 0.902 | 1.527 | 0.902 | 1.527 |
| sqlite_async execute() | 2.950 | 3.468 | 2.950 | 3.468 |
| drift execute() | 3.072 | 3.904 | 3.072 | 3.904 |

### Concurrent Single Inserts (100 concurrent)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite concurrent execute() | 0.964 | 1.321 | 0.964 | 1.321 |
| sqlite3 concurrent execute() | 0.895 | 1.540 | 0.895 | 1.540 |
| sqlite_async concurrent execute() | 2.651 | 3.473 | 2.651 | 3.473 |
| drift concurrent execute() | 1.765 | 2.389 | 1.765 | 2.389 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.046 | 0.049 | 0.046 | 0.049 |
| sqlite3 executeBatch() | 0.049 | 0.052 | 0.049 | 0.052 |
| sqlite_async executeBatch() | 0.092 | 0.119 | 0.092 | 0.119 |
| drift executeBatch() | 0.112 | 0.117 | 0.112 | 0.117 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.373 | 0.398 | 0.373 | 0.398 |
| sqlite3 executeBatch() | 0.434 | 0.465 | 0.434 | 0.465 |
| sqlite_async executeBatch() | 0.506 | 0.520 | 0.506 | 0.520 |
| drift executeBatch() | 0.631 | 0.669 | 0.631 | 0.669 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 3.458 | 4.143 | 3.458 | 4.143 |
| sqlite3 executeBatch() | 4.079 | 4.510 | 4.079 | 4.510 |
| sqlite_async executeBatch() | 4.787 | 5.324 | 4.787 | 5.324 |
| drift executeBatch() | 5.932 | 9.359 | 5.932 | 9.359 |

### Wide Batch Insert (10000 rows x 20 params)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 12.403 | 15.885 | 12.403 | 15.885 |
| sqlite3 executeBatch() | 18.768 | 21.110 | 18.768 | 21.110 |
| sqlite_async executeBatch() | 23.404 | 26.775 | 23.404 | 26.775 |
| drift executeBatch() | 26.884 | 29.418 | 26.884 | 29.418 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.049 | 0.069 | 0.049 | 0.069 |
| sqlite_async writeTransaction() | 0.078 | 0.089 | 0.078 | 0.089 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.067 | 0.073 | 0.067 | 0.073 |
| resqlite tx.execute() loop | 0.560 | 0.640 | 0.560 | 0.640 |
| sqlite_async tx.execute() loop | 0.987 | 1.186 | 0.987 | 1.186 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.410 | 0.421 | 0.410 | 0.421 |
| resqlite tx.execute() loop | 4.694 | 5.292 | 4.694 | 5.292 |
| sqlite_async tx.execute() loop | 9.454 | 9.938 | 9.454 | 9.938 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.102 | 0.110 | 0.102 | 0.110 |
| sqlite_async tx.getAll() | 0.201 | 0.212 | 0.201 | 0.212 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.179 | 0.187 | 0.179 | 0.187 |
| sqlite_async tx.getAll() | 0.348 | 0.383 | 0.348 | 0.383 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 0.767 | 0.934 | 0.767 | 0.934 |
| resqlite nested transaction() depth=5 | 0.073 | 0.082 | 0.073 | 0.082 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.065 | 0.070 | 0.065 | 0.070 |
| sqlite_async watch() | 0.134 | 0.210 | 0.134 | 0.210 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.050 | 0.080 | 0.050 | 0.080 |
| sqlite_async | 0.072 | 0.133 | 0.072 | 0.133 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.271 | 0.394 | 0.271 | 0.394 |
| sqlite_async | 0.625 | 0.997 | 0.625 | 0.997 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.654 | 3.274 | 1.654 | 3.274 |

### Long-Payload Unchanged Fanout (8 streams, 64 rows x 32KB TEXT + 32KB BLOB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.757 | 4.047 | 2.757 | 4.047 |

### Long-Text 32KB Unchanged Fanout (8 unchanged streams, 64 rows x 32KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.338 | 3.182 | 2.338 | 3.182 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.227 | 0.371 | 0.227 | 0.371 |
| sqlite_async | 0.261 | 0.416 | 0.261 | 0.416 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.994 | 2.994 | 2.994 | 2.994 |
| sqlite_async | 11.271 | 11.271 | 11.271 | 11.271 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.011 | 3.836 | 3.011 | 3.836 |
| sqlite_async | 5.330 | 6.368 | 5.330 | 6.368 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.557 | 0.681 | 0.557 | 0.681 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 6.928 | 10.322 | 6.928 | 10.322 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. For resqlite, this emission metric can reflect writer-side column-level invalidation, experiment 075's native result-hash short-circuit, or both. Use A11c (Many-Streams Writer Throughput) when the question is specifically writer-side dispatch elision.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 70.9 | 0.000 |
| sqlite_async | 4121 | 1157.6 | 1.060 |
| drift | 5000 | 1006.0 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 71.6 | 0.000 |
| sqlite_async | 3887 | 1075.6 | 1.060 |
| drift | 5000 | 1002.3 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 224.24 | 226.31 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 439.36 | 447.01 | 0.00 | 0.00 | 1107 | 3 |
| drift stream() | 552.40 | 553.15 | 0.01 | 0.01 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.017 | 0.028 | 0.000 | 0.000 |
| sqlite3 | 0.018 | 0.022 | 0.018 | 0.022 |
| sqlite_async | 0.036 | 0.045 | 0.000 | 0.000 |
| drift | 0.037 | 0.045 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.013 | 0.018 | 0.000 | 0.000 |
| sqlite3 | 0.011 | 0.014 | 0.011 | 0.014 |
| sqlite_async | 0.029 | 0.034 | 0.000 | 0.000 |
| drift | 0.030 | 0.036 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.023 | 0.032 | 0.000 | 0.000 |
| sqlite3 | 0.031 | 0.033 | 0.031 | 0.033 |
| sqlite_async | 0.055 | 0.065 | 0.000 | 0.000 |
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
| resqlite | 0.039 | 0.044 | 0.004 | 0.004 |
| sqlite3 | 0.066 | 0.076 | 0.066 | 0.076 |
| sqlite_async | 0.081 | 0.084 | 0.001 | 0.001 |
| drift | 0.091 | 0.095 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 108.553 | 109.305 | 0.000 | 0.000 | 0 |
| sqlite_async | 218.338 | 221.404 | 0.001 | 0.001 | 42 |
| drift | 231.756 | 233.326 | 0.000 | 0.001 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 239.88 | 239.88 | 0.00 | 0.00 | 13.63 | 226.58 | 0 |
| sqlite_async | 484.33 | 484.33 | 0.00 | 0.00 | 25.15 | 459.17 | 1183 |
| drift | 1756.05 | 1756.05 | 0.10 | 0.10 | 21.04 | 1734.99 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 0.00 | 7.34 | 0.00..5.55 | ±2.77 |
| sqlite3 select() | 4.95 | 7.67 | 2.97..5.77 | ±1.40 |
| sqlite_async select() | 0.50 | 1.00 | 0.50..0.50 | ±0.00 |
| drift select() | 6.97 | 74.52 | 0.00..11.89 | ±5.95 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 20.02 | 0.00..18.00 | ±9.00 |
| resqlite + jsonEncode | 0.00 | 13.25 | 0.00..5.80 | ±2.90 |
| sqlite3 + jsonEncode | 2.64 | 60.11 | 0.00..35.42 | ±17.71 |
| sqlite_async + jsonEncode | 0.00 | 7.55 | 0.00..0.00 | ±0.00 |
| drift + jsonEncode | 1.20 | 16.64 | 0.00..7.00 | ±3.50 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.44 | 3.72 | 0.00..2.11 | ±1.05 |
| sqlite3 executeBatch() | 0.00 | 1.50 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 3.47 | 0.00..0.50 | ±0.25 |
| drift batch() | 0.00 | 2.00 | 0.00..0.00 | ±0.00 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.14 | 0.06..0.06 | ±0.00 |
| sqlite_async watch() | 0.00 | 0.53 | 0.00..0.52 | ±0.26 |

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

## Comparison vs Previous Run

Previous: `2026-06-17T07-36-54-baseline-for-exp182.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.29 | -0.01 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.29 | -0.01 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.30 | 0.30 | +0.00 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.15 | 0.15 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.37 | 0.36 | -0.01 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.72 | 0.70 | -0.02 | ±10% / ±0.07 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 110.37 | 108.55 | -1.82 | ±10% / ±11.04 ms | 0.0% | single run | ⚪ Neutral |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 437.44 | 239.88 | -197.56 | ±10% / ±43.74 ms | 0.0% | single run | 🟢 Win (-45%) |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 226.20 | 224.24 | -1.96 | ±10% / ±22.62 ms | 0.0% | single run | ⚪ Neutral |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.00 | 14.07 | +0.07 | ±10% / ±1.41 ms | 0.0% | single run | ⚪ Neutral |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.00 | 14.07 | +0.07 | ±10% / ±1.41 ms | 0.0% | single run | ⚪ Neutral |
| Point Query Throughput / resqlite qps | 155783.00 | 153516.00 | -2267.00 | ±10% / ±15578.30 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.04 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.20 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.20 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.35 | 0.35 | +0.00 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.75 | 1.74 | -0.01 | ±10% / ±0.18 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.75 | 1.74 | -0.01 | ±10% / ±0.18 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.35 | +0.00 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.35 | +0.00 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.03 | 4.09 | +0.06 | ±10% / ±0.41 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 20.29 | 20.30 | +0.01 | ±10% / ±2.03 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 20.29 | 20.30 | +0.01 | ±10% / ±2.03 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.52 | 0.53 | +0.00 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.46 | 3.54 | +0.09 | ±10% / ±0.35 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.46 | 3.54 | +0.09 | ±10% / ±0.35 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.74 | 0.73 | -0.01 | ±10% / ±0.07 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.73 | 3.75 | +0.01 | ±10% / ±0.37 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.73 | 3.75 | +0.01 | ±10% / ±0.37 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.68 | 0.69 | +0.01 | ±10% / ±0.07 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.68 | 0.69 | +0.01 | ±10% / ±0.07 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.27 | 10.80 | +0.53 | ±10% / ±1.08 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 41.82 | 42.53 | +0.71 | ±10% / ±4.25 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 41.82 | 42.53 | +0.71 | ±10% / ±4.25 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.04 | 1.04 | +0.00 | ±10% / ±0.10 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 7.11 | 7.14 | +0.03 | ±10% / ±0.71 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 7.11 | 7.14 | +0.03 | ±10% / ±0.71 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.10 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.11 | 0.10 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.18 | 0.18 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.90 | 0.91 | +0.01 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.90 | 0.91 | +0.01 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.18 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.18 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 1.97 | 1.97 | +0.00 | ±10% / ±0.20 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.17 | 9.88 | -0.29 | ±10% / ±1.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.17 | 9.88 | -0.29 | ±10% / ±1.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.26 | 0.26 | -0.00 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.72 | 1.73 | +0.01 | ±10% / ±0.17 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.72 | 1.73 | +0.01 | ±10% / ±0.17 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.08 | 0.08 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.27 | 0.26 | -0.01 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.06 | 0.06 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.26 | 0.26 | -0.01 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.06 | 0.06 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.51 | 0.50 | -0.01 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.06 | 0.06 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.87 | 0.85 | -0.02 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.21 | 0.20 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.12 | 0.12 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.10 | 0.10 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.22 | 0.22 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.17 | 0.17 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.73 | 1.78 | +0.05 | ±10% / ±0.18 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.43 | 1.47 | +0.04 | ±10% / ±0.15 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.36 | 0.36 | -0.00 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.54 | 20.72 | +0.18 | ±10% / ±2.07 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 14.68 | 14.65 | -0.03 | ±10% / ±1.47 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.54 | 3.56 | +0.02 | ±10% / ±0.36 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 10 rows / resqlite select() | 0.08 | 0.08 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 10 rows / resqlite select() [main] | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 100 rows / resqlite select() | 0.06 | 0.06 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 1000 rows / resqlite select() | 0.36 | 0.35 | -0.01 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 10000 rows / resqlite select() | 4.17 | 4.20 | +0.03 | ±10% / ±0.42 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.51 | 0.51 | -0.00 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Fan-out (10 streams) / resqlite | 0.20 | 0.23 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+12%) |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.20 | 0.23 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+12%) |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.54 | 0.56 | +0.02 | ±10% / ±0.06 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.54 | 0.56 | +0.02 | ±10% / ±0.06 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Initial Emission / resqlite stream() | 0.07 | 0.07 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Initial Emission / resqlite stream() [main] | 0.07 | 0.07 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Invalidation Latency / resqlite [main] | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 ... | 2.82 | 2.76 | -0.07 | ±10% / ±0.28 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 ... | 2.82 | 2.76 | -0.07 | ±10% / ±0.28 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged ... | 2.81 | 2.34 | -0.47 | ±10% / ±0.28 ms | 0.0% | single run | 🟢 Win (-17%) |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged ... | 2.81 | 2.34 | -0.47 | ±10% / ±0.28 ms | 0.0% | single run | 🟢 Win (-17%) |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 1.92 | 1.65 | -0.27 | ±10% / ±0.19 ms | 0.0% | single run | 🟢 Win (-14%) |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 1.92 | 1.65 | -0.27 | ±10% / ±0.19 ms | 0.0% | single run | 🟢 Win (-14%) |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.24 | 3.01 | -0.23 | ±10% / ±0.32 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.24 | 3.01 | -0.23 | ±10% / ±0.32 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Stream Churn (100 cycles) / resqlite | 3.09 | 2.99 | -0.10 | ±10% / ±0.31 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 3.09 | 2.99 | -0.10 | ±10% / ±0.31 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.71 | 6.93 | +0.22 | ±10% / ±0.69 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.71 | 6.93 | +0.22 | ±10% / ±0.69 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.23 | 0.27 | +0.05 | ±10% / ±0.03 ms | 0.0% | single run | 🔴 Regression (+20%) |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.23 | 0.27 | +0.05 | ±10% / ±0.03 ms | 0.0% | single run | 🔴 Regression (+20%) |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.05 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.05 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.39 | 0.37 | -0.02 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.39 | 0.37 | -0.02 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.73 | 3.46 | -0.27 | ±10% / ±0.37 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.73 | 3.46 | -0.27 | ±10% / ±0.37 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.41 | 0.56 | +0.15 | ±10% / ±0.06 ms | 0.0% | single run | 🔴 Regression (+38%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.41 | 0.56 | +0.15 | ±10% / ±0.06 ms | 0.0% | single run | 🔴 Regression (+38%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.06 | 0.07 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.06 | 0.07 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 4.29 | 4.69 | +0.41 | ±10% / ±0.47 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 4.29 | 4.69 | +0.41 | ±10% / ±0.47 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.39 | 0.41 | +0.02 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.39 | 0.41 | +0.02 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Concurrent Single Inserts (100 concur... | 1.00 | 0.96 | -0.04 | ±10% / ±0.10 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Concurrent Single Inserts (100 concur... | 1.00 | 0.96 | -0.04 | ±10% / ±0.10 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Nested Transactions (savepoints) / re... | 0.08 | 0.07 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Nested Transactions (savepoints) / re... | 0.08 | 0.07 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Nested Transactions (savepoints) / re... | 0.81 | 0.77 | -0.05 | ±10% / ±0.08 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Nested Transactions (savepoints) / re... | 0.81 | 0.77 | -0.05 | ±10% / ±0.08 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Single Inserts (100 sequential) / res... | 1.46 | 1.38 | -0.08 | ±10% / ±0.15 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Single Inserts (100 sequential) / res... | 1.46 | 1.38 | -0.08 | ±10% / ±0.15 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.18 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.18 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 12.60 | 12.40 | -0.20 | ±10% / ±1.26 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 12.60 | 12.40 | -0.20 | ±10% / ±1.26 ms | 0.0% | single run | ⚪ Neutral |

**Summary:** 5 wins, 6 regressions, 156 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 1.47 | 0.44 | -1.03 MB | ±1.05 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 2.20 | 1.20 | -1.00 MB | ±3.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 0.00 | 0.00 | +0.00 MB | ±2.90 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 0.00 | +0.00 MB | ±9.00 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 7.22 | 2.64 | -4.58 MB | ±17.71 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 7.55 | 6.97 | -0.58 MB | ±5.95 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / resqlite select() | 1.08 | 0.00 | -1.08 MB | ±2.77 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite3 select() | 2.95 | 4.95 | +2.00 MB | ±1.40 MB | 🔴 Regression (+2.00 MB) |
| Memory / Select 10k rows → Maps / sqlite_async select() | 0.50 | 0.50 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.06 | 0.06 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 0 wins, 1 regressions, 14 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 3994 | 4121 | +127 | ±100 | 🔴 More re-emits (+127) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 4256 | 3887 | -369 | ±100 | 🔴 Invalidation elided (-369) — writes not firing |

**Granularity summary:** 0 fewer-re-emit, 2 more-re-emit, 4 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


