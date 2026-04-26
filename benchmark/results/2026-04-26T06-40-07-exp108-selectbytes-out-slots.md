# resqlite Benchmark Results

Generated: 2026-04-26T06:40:06.749330

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp108-selectbytes-out-slots`
- Repeats: `5`
- Runtime: `dart-vm / Dart 3.11.0`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `codex/selectbytes-out-slots-108 @ 3f88e24c75b3 (dirty)`
- Comparison baseline: `2026-04-25T07-52-01-exp101-tx-stmt-cache.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.013 | 0.014 | 0.001 | 0.001 |
| sqlite3 select() | 0.015 | 0.016 | 0.015 | 0.016 |
| sqlite_async select() | 0.031 | 0.033 | 0.001 | 0.001 |
| drift select() | 0.037 | 0.040 | 0.001 | 0.001 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.046 | 0.048 | 0.009 | 0.009 |
| sqlite3 select() | 0.113 | 0.117 | 0.113 | 0.117 |
| sqlite_async select() | 0.122 | 0.126 | 0.010 | 0.010 |
| drift select() | 0.184 | 0.191 | 0.010 | 0.010 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.376 | 0.389 | 0.087 | 0.088 |
| sqlite3 select() | 1.097 | 1.130 | 1.097 | 1.130 |
| sqlite_async select() | 1.010 | 1.073 | 0.092 | 0.097 |
| drift select() | 1.565 | 2.077 | 0.090 | 0.092 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.407 | 10.423 | 0.856 | 1.138 |
| sqlite3 select() | 14.140 | 19.450 | 14.140 | 19.450 |
| sqlite_async select() | 11.868 | 12.931 | 0.927 | 1.466 |
| drift select() | 21.532 | 37.407 | 0.953 | 1.498 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.026 | 0.030 | 0.015 | 0.017 |
| sqlite3 + jsonEncode | 0.030 | 0.031 | 0.030 | 0.031 |
| sqlite_async + jsonEncode | 0.048 | 0.053 | 0.017 | 0.018 |
| drift + jsonEncode | 0.052 | 0.055 | 0.016 | 0.017 |
| resqlite selectBytes() | 0.010 | 0.010 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.192 | 0.213 | 0.153 | 0.168 |
| sqlite3 + jsonEncode | 0.254 | 0.273 | 0.254 | 0.273 |
| sqlite_async + jsonEncode | 0.260 | 0.262 | 0.148 | 0.150 |
| drift + jsonEncode | 0.323 | 0.342 | 0.151 | 0.162 |
| resqlite selectBytes() | 0.043 | 0.061 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.732 | 3.585 | 1.429 | 2.181 |
| sqlite3 + jsonEncode | 2.535 | 2.839 | 2.535 | 2.839 |
| sqlite_async + jsonEncode | 2.532 | 4.855 | 1.536 | 2.686 |
| drift + jsonEncode | 2.990 | 5.442 | 1.439 | 2.602 |
| resqlite selectBytes() | 0.354 | 0.378 | 0.000 | 0.000 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 22.966 | 25.648 | 15.432 | 19.795 |
| sqlite3 + jsonEncode | 28.343 | 34.969 | 28.343 | 34.969 |
| sqlite_async + jsonEncode | 30.056 | 37.155 | 15.359 | 16.455 |
| drift + jsonEncode | 38.836 | 42.802 | 14.689 | 17.712 |
| resqlite selectBytes() | 3.994 | 8.270 | 0.002 | 0.004 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.113 | 0.119 | 0.042 | 0.045 |
| sqlite3 | 0.346 | 0.404 | 0.346 | 0.404 |
| sqlite_async | 0.384 | 0.463 | 0.048 | 0.059 |
| drift | 0.616 | 0.728 | 0.047 | 0.050 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.994 | 1.022 | 0.351 | 0.358 |
| sqlite3 | 3.258 | 3.803 | 3.258 | 3.803 |
| sqlite_async | 3.162 | 3.506 | 0.411 | 0.432 |
| drift | 4.781 | 5.729 | 0.377 | 0.385 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.717 | 0.928 | 0.134 | 0.263 |
| sqlite3 | 1.605 | 2.225 | 1.605 | 2.225 |
| sqlite_async | 1.492 | 1.671 | 0.144 | 0.168 |
| drift | 2.003 | 2.362 | 0.135 | 0.145 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.329 | 0.332 | 0.135 | 0.136 |
| sqlite3 | 1.030 | 1.047 | 1.030 | 1.047 |
| sqlite_async | 0.947 | 0.958 | 0.146 | 0.148 |
| drift | 1.507 | 1.552 | 0.152 | 0.156 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.319 | 0.326 | 0.121 | 0.123 |
| sqlite3 | 0.960 | 0.978 | 0.960 | 0.978 |
| sqlite_async | 0.929 | 0.937 | 0.130 | 0.132 |
| drift | 1.467 | 1.489 | 0.127 | 0.128 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.012 | 0.013 | 0.001 | 0.001 |
| sqlite3 | 0.015 | 0.017 | 0.015 | 0.017 |
| sqlite_async | 0.030 | 0.031 | 0.001 | 0.001 |
| drift | 0.037 | 0.039 | 0.001 | 0.001 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.028 | 0.030 | 0.005 | 0.005 |
| sqlite3 | 0.064 | 0.066 | 0.064 | 0.066 |
| sqlite_async | 0.075 | 0.075 | 0.006 | 0.006 |
| drift | 0.107 | 0.112 | 0.006 | 0.006 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.046 | 0.047 | 0.010 | 0.010 |
| sqlite3 | 0.118 | 0.121 | 0.118 | 0.121 |
| sqlite_async | 0.129 | 0.132 | 0.012 | 0.012 |
| drift | 0.183 | 0.192 | 0.012 | 0.012 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.199 | 0.203 | 0.050 | 0.051 |
| sqlite3 | 0.564 | 0.577 | 0.564 | 0.577 |
| sqlite_async | 0.534 | 0.551 | 0.057 | 0.059 |
| drift | 0.839 | 0.887 | 0.056 | 0.059 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.394 | 0.433 | 0.100 | 0.103 |
| sqlite3 | 1.102 | 1.143 | 1.102 | 1.143 |
| sqlite_async | 1.030 | 1.046 | 0.112 | 0.113 |
| drift | 1.584 | 1.892 | 0.107 | 0.111 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.805 | 0.816 | 0.202 | 0.207 |
| sqlite3 | 2.204 | 2.744 | 2.204 | 2.744 |
| sqlite_async | 2.016 | 2.357 | 0.219 | 0.224 |
| drift | 3.160 | 3.573 | 0.215 | 0.606 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.150 | 5.211 | 0.500 | 0.528 |
| sqlite3 | 5.597 | 7.013 | 5.597 | 7.013 |
| sqlite_async | 5.808 | 6.974 | 0.601 | 1.332 |
| drift | 8.662 | 9.996 | 0.547 | 0.588 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.913 | 11.895 | 1.053 | 1.277 |
| sqlite3 | 14.148 | 16.499 | 14.148 | 16.499 |
| sqlite_async | 11.833 | 13.132 | 1.108 | 1.194 |
| drift | 21.893 | 32.542 | 1.171 | 2.673 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 11.776 | 17.034 | 2.069 | 3.838 |
| sqlite3 | 29.475 | 39.177 | 29.475 | 39.177 |
| sqlite_async | 34.777 | 46.874 | 2.261 | 2.513 |
| drift | 51.857 | 77.254 | 2.239 | 3.814 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.030 | 0.031 | 0.030 | 0.031 |
| sqlite3 + jsonEncode | 0.034 | 0.035 | 0.034 | 0.035 |
| sqlite_async + jsonEncode | 0.052 | 0.057 | 0.052 | 0.057 |
| drift + jsonEncode | 0.059 | 0.073 | 0.059 | 0.073 |
| resqlite selectBytes() | 0.011 | 0.012 | 0.011 | 0.012 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.103 | 0.107 | 0.103 | 0.107 |
| sqlite3 + jsonEncode | 0.134 | 0.139 | 0.134 | 0.139 |
| sqlite_async + jsonEncode | 0.171 | 0.257 | 0.171 | 0.257 |
| drift + jsonEncode | 0.173 | 0.185 | 0.173 | 0.185 |
| resqlite selectBytes() | 0.024 | 0.026 | 0.024 | 0.026 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.192 | 0.215 | 0.192 | 0.215 |
| sqlite3 + jsonEncode | 0.253 | 0.271 | 0.253 | 0.271 |
| sqlite_async + jsonEncode | 0.264 | 0.289 | 0.264 | 0.289 |
| drift + jsonEncode | 0.322 | 0.344 | 0.322 | 0.344 |
| resqlite selectBytes() | 0.043 | 0.043 | 0.043 | 0.043 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.886 | 1.563 | 0.886 | 1.563 |
| sqlite3 + jsonEncode | 1.231 | 2.720 | 1.231 | 2.720 |
| sqlite_async + jsonEncode | 1.195 | 1.519 | 1.195 | 1.519 |
| drift + jsonEncode | 1.590 | 2.777 | 1.590 | 2.777 |
| resqlite selectBytes() | 0.181 | 0.186 | 0.181 | 0.186 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.730 | 3.494 | 1.730 | 3.494 |
| sqlite3 + jsonEncode | 2.421 | 3.065 | 2.421 | 3.065 |
| sqlite_async + jsonEncode | 2.362 | 2.910 | 2.362 | 2.910 |
| drift + jsonEncode | 2.920 | 5.455 | 2.920 | 5.455 |
| resqlite selectBytes() | 0.353 | 0.368 | 0.353 | 0.368 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.544 | 7.286 | 3.544 | 7.286 |
| sqlite3 + jsonEncode | 5.040 | 8.908 | 5.040 | 8.908 |
| sqlite_async + jsonEncode | 5.437 | 9.592 | 5.437 | 9.592 |
| drift + jsonEncode | 6.881 | 27.105 | 6.881 | 27.105 |
| resqlite selectBytes() | 0.832 | 1.473 | 0.832 | 1.473 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 10.013 | 14.256 | 10.013 | 14.256 |
| sqlite3 + jsonEncode | 14.167 | 17.118 | 14.167 | 17.118 |
| sqlite_async + jsonEncode | 13.299 | 17.319 | 13.299 | 17.319 |
| drift + jsonEncode | 18.577 | 29.412 | 18.577 | 29.412 |
| resqlite selectBytes() | 1.810 | 3.244 | 1.810 | 3.244 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.171 | 23.197 | 20.171 | 23.197 |
| sqlite3 + jsonEncode | 31.929 | 47.658 | 31.929 | 47.658 |
| sqlite_async + jsonEncode | 30.482 | 31.640 | 30.482 | 31.640 |
| drift + jsonEncode | 38.060 | 67.066 | 38.060 | 67.066 |
| resqlite selectBytes() | 3.696 | 5.324 | 3.696 | 5.324 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 44.740 | 62.285 | 44.740 | 62.285 |
| sqlite3 + jsonEncode | 60.888 | 71.201 | 60.888 | 71.201 |
| sqlite_async + jsonEncode | 68.893 | 89.662 | 68.893 | 89.662 |
| drift + jsonEncode | 85.138 | 111.350 | 85.138 | 111.350 |
| resqlite selectBytes() | 8.656 | 10.585 | 8.656 | 10.585 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.34 | 0.30 |
| sqlite_async | 0.99 | 1.13 | 0.99 |
| drift | 1.64 | 1.92 | 1.64 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.31 | 0.33 | 0.15 |
| sqlite_async | 1.33 | 1.69 | 0.67 |
| drift | 2.71 | 3.11 | 1.36 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.36 | 0.39 | 0.09 |
| sqlite_async | 2.14 | 2.68 | 0.54 |
| drift | 5.19 | 5.70 | 1.30 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.67 | 1.15 | 0.08 |
| sqlite_async | 4.56 | 4.82 | 0.57 |
| drift | 10.69 | 15.87 | 1.34 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 148079 |
| resqlite per query | 0.007 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 148079 | 146915..149347 | 0.8 | 2.6 |
| sqlite3 | 186058 | 181730..191302 | 2.6 | 7.9 |
| sqlite_async | 46407 | 45703..50882 | 5.6 | 19.8 |
| drift | 45841 | 42777..47032 | 4.6 | 8.6 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 15.008 | 15.701 | 15.008 | 15.701 |
| sqlite_async | 35.587 | 39.782 | 35.587 | 39.782 |
| drift | 54.035 | 63.851 | 54.035 | 63.851 |
| sqlite3 (no cache) | 24.054 | 25.293 | 24.054 | 25.293 |
| sqlite3 (cached stmt) | 25.032 | 25.959 | 25.032 | 25.959 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.727 | 2.366 | 1.727 | 2.366 |
| sqlite3 execute() | 0.928 | 1.533 | 0.928 | 1.533 |
| sqlite_async execute() | 2.709 | 3.310 | 2.709 | 3.310 |
| drift execute() | 2.742 | 3.317 | 2.742 | 3.317 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.057 | 0.058 | 0.057 | 0.058 |
| sqlite3 executeBatch() | 0.049 | 0.051 | 0.049 | 0.051 |
| sqlite_async executeBatch() | 0.099 | 0.102 | 0.099 | 0.102 |
| drift executeBatch() | 0.112 | 0.122 | 0.112 | 0.122 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.440 | 0.450 | 0.440 | 0.450 |
| sqlite3 executeBatch() | 0.421 | 0.425 | 0.421 | 0.425 |
| sqlite_async executeBatch() | 0.503 | 0.514 | 0.503 | 0.514 |
| drift executeBatch() | 0.634 | 0.699 | 0.634 | 0.699 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.550 | 8.917 | 4.550 | 8.917 |
| sqlite3 executeBatch() | 4.013 | 4.345 | 4.013 | 4.345 |
| sqlite_async executeBatch() | 4.585 | 5.328 | 4.585 | 5.328 |
| drift executeBatch() | 5.831 | 6.666 | 5.831 | 6.666 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.050 | 0.055 | 0.050 | 0.055 |
| sqlite_async writeTransaction() | 0.081 | 0.087 | 0.081 | 0.087 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.069 | 0.074 | 0.069 | 0.074 |
| resqlite tx.execute() loop | 0.523 | 0.759 | 0.523 | 0.759 |
| sqlite_async tx.execute() loop | 0.970 | 1.054 | 0.970 | 1.054 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.429 | 0.487 | 0.429 | 0.487 |
| resqlite tx.execute() loop | 5.324 | 6.722 | 5.324 | 6.722 |
| sqlite_async tx.execute() loop | 12.755 | 16.887 | 12.755 | 16.887 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.109 | 0.171 | 0.109 | 0.171 |
| sqlite_async tx.getAll() | 0.234 | 0.314 | 0.234 | 0.314 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.190 | 0.405 | 0.190 | 0.405 |
| sqlite_async tx.getAll() | 0.384 | 0.487 | 0.384 | 0.487 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.028 | 0.037 | 0.028 | 0.037 |
| sqlite_async watch() | 0.130 | 0.205 | 0.130 | 0.205 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.057 | 0.186 | 0.057 | 0.186 |
| sqlite_async | 0.086 | 0.201 | 0.086 | 0.201 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.399 | 0.688 | 0.399 | 0.688 |
| sqlite_async | 0.815 | 6.840 | 0.815 | 6.840 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.244 | 0.403 | 0.244 | 0.403 |
| sqlite_async | 0.280 | 0.353 | 0.280 | 0.353 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.573 | 1.573 | 1.573 | 1.573 |
| sqlite_async | 10.400 | 10.400 | 10.400 | 10.400 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.346 | 4.207 | 3.346 | 4.207 |
| sqlite_async | 5.278 | 6.494 | 5.278 | 6.494 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.572 | 0.735 | 0.572 | 0.735 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 6.407 | 15.139 | 6.407 | 15.139 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. On resqlite's main branch this ratio is driven toward 0 by experiment 075 (C-side result-hash short-circuit), not by writer-side column-tracking (exp 052 is not implemented). The two mechanisms are indistinguishable on this read-side benchmark.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 68.6 | 0.000 |
| sqlite_async | 3959 | 1090.7 | 1.256 |
| drift | 5000 | 1003.9 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 71.3 | 0.000 |
| sqlite_async | 3153 | 918.1 | 1.256 |
| drift | 5000 | 1141.5 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 222.48 | 227.02 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 444.23 | 446.42 | 0.00 | 0.00 | 1110 | 3 |
| drift stream() | 555.86 | 556.49 | 0.01 | 0.02 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.020 | 0.034 | 0.000 | 0.000 |
| sqlite3 | 0.024 | 0.068 | 0.024 | 0.068 |
| sqlite_async | 0.037 | 0.051 | 0.000 | 0.000 |
| drift | 0.037 | 0.046 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.015 | 0.022 | 0.000 | 0.000 |
| sqlite3 | 0.016 | 0.031 | 0.016 | 0.031 |
| sqlite_async | 0.030 | 0.038 | 0.000 | 0.000 |
| drift | 0.029 | 0.036 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.024 | 0.034 | 0.000 | 0.000 |
| sqlite3 | 0.033 | 0.049 | 0.033 | 0.049 |
| sqlite_async | 0.056 | 0.067 | 0.000 | 0.000 |
| drift | 0.053 | 0.057 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.008 | 0.015 | 0.000 | 0.000 |
| sqlite3 | 0.006 | 0.009 | 0.006 | 0.009 |
| sqlite_async | 0.021 | 0.026 | 0.000 | 0.000 |
| drift | 0.019 | 0.024 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.037 | 0.039 | 0.001 | 0.001 |
| sqlite3 | 0.063 | 0.065 | 0.063 | 0.065 |
| sqlite_async | 0.077 | 0.078 | 0.001 | 0.001 |
| drift | 0.092 | 0.095 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 109.926 | 109.984 | 0.000 | 0.000 | 0 |
| sqlite_async | 216.708 | 219.765 | 0.000 | 0.000 | 42 |
| drift | 232.684 | 234.904 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 242.98 | 242.98 | 0.00 | 0.00 | 14.26 | 229.13 | 0 |
| sqlite_async | 494.69 | 494.69 | 0.00 | 0.00 | 24.21 | 470.87 | 1187 |
| drift | 1870.79 | 1870.79 | 0.63 | 0.63 | 16.69 | 1854.09 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 1.63 | 9.33 | 0.00..9.13 | ±4.56 |
| sqlite3 select() | 5.72 | 8.73 | 0.97..7.08 | ±3.05 |
| sqlite_async select() | 1.00 | 1.50 | 1.00..1.00 | ±0.00 |
| drift select() | 6.13 | 59.06 | 0.00..11.42 | ±5.71 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 6.00 | 8.02 | 0.00..6.02 | ±3.01 |
| resqlite + jsonEncode | 1.77 | 88.89 | 0.00..24.95 | ±12.48 |
| sqlite3 + jsonEncode | 0.00 | 16.80 | 0.00..4.83 | ±2.41 |
| sqlite_async + jsonEncode | 0.00 | 19.16 | 0.00..19.16 | ±9.58 |
| drift + jsonEncode | 0.00 | 22.30 | 0.00..5.25 | ±2.63 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 3.50 | 4.98 | 0.00..4.02 | ±2.01 |
| sqlite3 executeBatch() | 0.00 | 0.39 | 0.00..0.05 | ±0.02 |
| sqlite_async executeBatch() | 0.03 | 0.52 | 0.00..0.50 | ±0.25 |
| drift batch() | 0.02 | 2.41 | 0.00..0.50 | ±0.25 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.06 | 0.00..0.06 | ±0.03 |
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
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.03 | 0.02..0.03 | 8.0% | 16.0% | 4.0% | moderate |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 6.2% | 12.5% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02..0.02 | 11.9% | 23.8% | 9.5% | noisy |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.01..0.02 | 9.4% | 18.8% | 6.3% | moderate |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.30 | 0.29..0.32 | 5.0% | 10.0% | 3.3% | moderate |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.30 | 0.29..0.32 | 5.0% | 10.0% | 3.3% | moderate |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.31 | 0.30..1.08 | 125.8% | 251.6% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.16 | 0.15..0.54 | 121.9% | 243.8% | 6.3% | moderate |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.36 | 0.36..0.59 | 31.9% | 63.9% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.09 | 0.09..0.15 | 33.3% | 66.7% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.68 | 0.67..0.78 | 8.1% | 16.2% | 1.5% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.09 | 0.08..0.10 | 11.1% | 22.2% | 11.1% | noisy |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.04 | 3.8% | 7.7% | 2.6% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 150.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 110.17 | 109.42..110.99 | 0.7% | 1.4% | 0.2% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 242.62 | 239.60..242.98 | 0.7% | 1.4% | 0.1% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 224.38 | 222.48..228.42 | 1.3% | 2.6% | 0.7% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 14.64 | 14.50..15.11 | 2.1% | 4.2% | 1.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 14.64 | 14.50..15.11 | 2.1% | 4.2% | 1.0% | stable |
| Point Query Throughput / resqlite qps | 146458.00 | 144965.00..148205.00 | 1.1% | 2.2% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.02 | 20.8% | 41.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.04 | 13.3% | 26.7% | 3.3% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.04 | 13.3% | 26.7% | 3.3% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 50.0% | 100.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 27.3% | 54.5% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.02 | 27.3% | 54.5% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05..0.05 | 6.2% | 12.5% | 4.2% | moderate |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.19 | 0.19..0.20 | 2.3% | 4.6% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.19 | 0.19..0.20 | 2.3% | 4.6% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 10.0% | 20.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.06 | 14.0% | 27.9% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.04 | 0.04..0.06 | 14.0% | 27.9% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.41 | 0.39..0.42 | 3.1% | 6.2% | 2.7% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.78 | 1.72..1.95 | 6.5% | 13.0% | 2.6% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.78 | 1.72..1.95 | 6.5% | 13.0% | 2.6% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.10 | 0.09..0.10 | 5.9% | 11.9% | 3.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.35 | 0.35..0.37 | 2.8% | 5.6% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.35 | 0.35..0.37 | 2.8% | 5.6% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.75 | 4.47..4.93 | 4.8% | 9.7% | 3.7% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 21.06 | 20.17..23.06 | 6.9% | 13.7% | 3.1% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 21.06 | 20.17..23.06 | 6.9% | 13.7% | 3.1% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 1.00 | 0.87..1.06 | 9.4% | 18.8% | 5.5% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 3.68 | 3.54..3.70 | 2.1% | 4.3% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 3.68 | 3.54..3.70 | 2.1% | 4.3% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.81 | 0.79..0.82 | 2.2% | 4.3% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.72 | 3.54..3.89 | 4.7% | 9.4% | 4.1% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.72 | 3.54..3.89 | 4.7% | 9.4% | 4.1% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.20 | 0.17..0.20 | 8.5% | 16.9% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.83 | 0.75..0.86 | 6.6% | 13.2% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.83 | 0.75..0.86 | 6.6% | 13.2% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 11.61 | 11.10..12.51 | 6.1% | 12.1% | 3.4% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 42.36 | 41.33..44.74 | 4.0% | 8.1% | 2.4% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 42.36 | 41.33..44.74 | 4.0% | 8.1% | 2.4% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 2.04 | 1.72..2.07 | 8.5% | 17.0% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 8.11 | 7.41..8.83 | 8.7% | 17.5% | 8.4% | noisy |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 8.11 | 7.41..8.83 | 8.7% | 17.5% | 8.4% | noisy |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03..0.03 | 3.6% | 7.1% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10..0.11 | 3.4% | 6.7% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.10 | 0.10..0.11 | 3.4% | 6.7% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.01 | 0.00..0.01 | 10.0% | 20.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.02..0.03 | 12.0% | 24.0% | 4.0% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.02..0.03 | 12.0% | 24.0% | 4.0% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.21 | 0.19..0.21 | 3.9% | 7.8% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.92 | 0.88..0.95 | 3.8% | 7.5% | 3.3% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.92 | 0.88..0.95 | 3.8% | 7.5% | 3.3% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.05 | 0.04..0.05 | 9.6% | 19.2% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.18 | 0.18..0.19 | 3.6% | 7.2% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.18 | 0.18..0.19 | 3.6% | 7.2% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.17 | 2.14..2.23 | 1.9% | 3.9% | 1.3% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 9.82 | 9.43..11.60 | 11.1% | 22.2% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 9.82 | 9.43..11.60 | 11.1% | 22.2% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.49 | 0.42..0.51 | 8.2% | 16.4% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 1.81 | 1.80..2.41 | 16.9% | 33.8% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 1.81 | 1.80..2.41 | 16.9% | 33.8% | 0.6% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.11 | 0.10..0.11 | 6.9% | 13.9% | 3.7% | moderate |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.04 | 0.03..0.04 | 19.0% | 38.1% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.32 | 0.30..0.32 | 3.4% | 6.9% | 0.3% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.12 | 0.10..0.12 | 10.7% | 21.5% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.33 | 0.29..0.34 | 8.1% | 16.1% | 0.9% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.14 | 0.09..0.14 | 17.0% | 34.1% | 0.7% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.57 | 0.55..0.72 | 14.5% | 28.9% | 4.0% | moderate |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.13 | 0.10..0.13 | 11.6% | 23.3% | 2.3% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.99 | 0.90..1.03 | 6.2% | 12.4% | 1.1% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.35 | 0.26..0.36 | 14.1% | 28.2% | 1.2% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.10 | 140.7% | 281.5% | 3.7% | moderate |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.01..0.08 | 193.8% | 387.5% | 6.3% | moderate |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.05 | 215.0% | 430.0% | 10.0% | noisy |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.19..0.26 | 15.6% | 31.2% | 5.0% | moderate |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.16 | 0.15..0.19 | 12.6% | 25.2% | 3.1% | moderate |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.05 | 8.0% | 15.9% | 2.3% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.87 | 1.73..1.96 | 6.2% | 12.4% | 4.8% | moderate |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.55 | 1.43..1.58 | 5.0% | 10.0% | 2.4% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.36 | 0.35..0.37 | 2.1% | 4.2% | 1.4% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 22.06 | 19.80..22.97 | 7.2% | 14.3% | 4.1% | moderate |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 15.43 | 14.80..15.55 | 2.4% | 4.8% | 0.8% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.85 | 3.56..3.99 | 5.7% | 11.3% | 3.8% | moderate |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 75.0% | 150.0% | 50.0% | noisy |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.09 | 296.2% | 592.3% | 15.4% | noisy |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 1000.0% | 2000.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.05..0.07 | 21.7% | 43.5% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 5.6% | 11.1% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.38 | 0.38..0.43 | 7.6% | 15.1% | 0.3% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.08..0.09 | 7.5% | 14.9% | 0.0% | stable |
| Select → Maps / 10000 rows / resqlite select() | 4.50 | 4.22..4.62 | 4.5% | 8.9% | 2.2% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.87 | 0.66..0.90 | 13.7% | 27.4% | 1.8% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.21 | 0.19..0.56 | 88.0% | 175.9% | 12.3% | noisy |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.21 | 0.19..0.56 | 88.0% | 175.9% | 12.3% | noisy |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.55 | 0.53..0.57 | 4.2% | 8.3% | 4.0% | moderate |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.55 | 0.53..0.57 | 4.2% | 8.3% | 4.0% | moderate |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03..0.06 | 55.4% | 110.7% | 3.6% | moderate |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03..0.06 | 55.4% | 110.7% | 3.6% | moderate |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.05..0.07 | 24.5% | 48.9% | 2.1% | stable |
| Streaming / Invalidation Latency / resqlite [main] | 0.05 | 0.05..0.07 | 24.5% | 48.9% | 2.1% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.44 | 3.33..3.46 | 1.9% | 3.7% | 0.7% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.44 | 3.33..3.46 | 1.9% | 3.7% | 0.7% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.69 | 1.57..2.50 | 27.4% | 54.8% | 6.8% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.69 | 1.57..2.50 | 27.4% | 54.8% | 6.8% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 5.94 | 5.42..6.58 | 9.7% | 19.4% | 7.8% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 5.94 | 5.42..6.58 | 9.7% | 19.4% | 7.8% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.40 | 0.18..0.85 | 83.7% | 167.4% | 46.1% | noisy |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.40 | 0.18..0.85 | 83.7% | 167.4% | 46.1% | noisy |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.06..0.07 | 8.8% | 17.5% | 3.5% | moderate |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.06 | 0.06..0.07 | 8.8% | 17.5% | 3.5% | moderate |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.45 | 0.43..0.50 | 8.1% | 16.1% | 2.7% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.45 | 0.43..0.50 | 8.1% | 16.1% | 2.7% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.15 | 4.05..4.55 | 6.0% | 12.1% | 2.4% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.15 | 4.05..4.55 | 6.0% | 12.1% | 2.4% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.56 | 0.52..0.63 | 9.0% | 18.1% | 7.3% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.56 | 0.52..0.63 | 9.0% | 18.1% | 7.3% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07..0.08 | 11.4% | 22.9% | 2.9% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07..0.08 | 11.4% | 22.9% | 2.9% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.42 | 5.29..7.07 | 16.4% | 32.8% | 2.4% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.42 | 5.29..7.07 | 16.4% | 32.8% | 2.4% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.43 | 0.43..0.44 | 1.9% | 3.7% | 0.7% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.43 | 0.43..0.44 | 1.9% | 3.7% | 0.7% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05..0.07 | 15.4% | 30.8% | 5.8% | moderate |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05..0.07 | 15.4% | 30.8% | 5.8% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.65 | 1.59..1.73 | 4.0% | 8.1% | 2.9% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.65 | 1.59..1.73 | 4.0% | 8.1% | 2.9% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.18..0.19 | 3.2% | 6.3% | 1.1% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.18..0.19 | 3.2% | 6.3% | 1.1% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.11 | 0.10..0.12 | 6.4% | 12.8% | 3.7% | moderate |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.11 | 0.10..0.12 | 6.4% | 12.8% | 3.7% | moderate |


## Comparison vs Previous Run

Previous: `2026-04-25T07-52-01-exp101-tx-stmt-cache.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.03 | 0.03 | -0.00 | ±12% / ±0.02 ms | 8.0% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | 6.2% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.03 | 0.02 | -0.00 | ±29% / ±0.02 ms | 11.9% | noisy | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02 | -0.00 | ±19% / ±0.02 ms | 9.4% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.29 | 0.30 | +0.01 | ±10% / ±0.03 ms | 5.0% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.29 | 0.30 | +0.01 | ±10% / ±0.03 ms | 5.0% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.82 | 0.31 | -0.51 | ±126% / ±1.03 ms | 125.8% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.41 | 0.16 | -0.25 | ±122% / ±0.50 ms | 121.9% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.36 | 0.36 | +0.00 | ±32% / ±0.11 ms | 31.9% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.09 | 0.09 | +0.00 | ±33% / ±0.03 ms | 33.3% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.68 | 0.68 | +0.00 | ±10% / ±0.07 ms | 8.1% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.09 | 0.09 | +0.00 | ±33% / ±0.03 ms | 11.1% | noisy | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 3.8% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±150% / ±0.02 ms | 150.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 111.19 | 110.17 | -1.02 | ±10% / ±11.12 ms | 0.7% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 242.67 | 242.62 | -0.05 | ±10% / ±24.27 ms | 0.7% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 225.65 | 224.38 | -1.27 | ±10% / ±22.57 ms | 1.3% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 15.36 | 14.64 | -0.72 | ±10% / ±1.54 ms | 2.1% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 15.36 | 14.64 | -0.72 | ±10% / ±1.54 ms | 2.1% | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 124414.00 | 146458.00 | +22044.00 | ±10% / ±14645.80 ms | 1.1% | stable | 🟢 Win (18%) |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01 | +0.00 | ±21% / ±0.02 ms | 20.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±13% / ±0.02 ms | 13.3% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.03 | +0.00 | ±13% / ±0.02 ms | 13.3% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±50% / ±0.02 ms | 50.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±27% / ±0.02 ms | 27.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±27% / ±0.02 ms | 27.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.05 | +0.00 | ±13% / ±0.02 ms | 6.2% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.19 | +0.00 | ±10% / ±0.02 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.19 | +0.00 | ±10% / ±0.02 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 10.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±14% / ±0.02 ms | 14.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±14% / ±0.02 ms | 14.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.38 | 0.41 | +0.03 | ±10% / ±0.04 ms | 3.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.74 | 1.78 | +0.03 | ±10% / ±0.18 ms | 6.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.74 | 1.78 | +0.03 | ±10% / ±0.18 ms | 6.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.10 | +0.02 | ±10% / ±0.02 ms | 5.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.36 | 0.35 | -0.01 | ±10% / ±0.04 ms | 2.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.36 | 0.35 | -0.01 | ±10% / ±0.04 ms | 2.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.25 | 4.75 | +0.50 | ±11% / ±0.53 ms | 4.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 19.96 | 21.06 | +1.10 | ±10% / ±2.11 ms | 6.9% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 19.96 | 21.06 | +1.10 | ±10% / ±2.11 ms | 6.9% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.84 | 1.00 | +0.16 | ±17% / ±0.16 ms | 9.4% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.68 | 3.68 | +0.00 | ±10% / ±0.37 ms | 2.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.68 | 3.68 | +0.00 | ±10% / ±0.37 ms | 2.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.77 | 0.81 | +0.04 | ±10% / ±0.08 ms | 2.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.89 | 3.72 | -0.17 | ±12% / ±0.48 ms | 4.7% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.89 | 3.72 | -0.17 | ±12% / ±0.48 ms | 4.7% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.17 | 0.20 | +0.03 | ±10% / ±0.02 ms | 8.5% | stable | 🔴 Regression (+18%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.77 | 0.83 | +0.06 | ±10% / ±0.08 ms | 6.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.77 | 0.83 | +0.06 | ±10% / ±0.08 ms | 6.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.86 | 11.61 | +0.75 | ±10% / ±1.18 ms | 6.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 46.03 | 42.36 | -3.67 | ±10% / ±4.60 ms | 4.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 46.03 | 42.36 | -3.67 | ±10% / ±4.60 ms | 4.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.70 | 2.04 | +0.34 | ±10% / ±0.20 ms | 8.5% | stable | 🔴 Regression (+20%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.68 | 8.11 | -0.57 | ±25% / ±2.19 ms | 8.7% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.68 | 8.11 | -0.57 | ±25% / ±2.19 ms | 8.7% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 3.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 3.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.01 | +0.00 | ±10% / ±0.02 ms | 10.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.03 | +0.00 | ±12% / ±0.02 ms | 12.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.03 | +0.00 | ±12% / ±0.02 ms | 12.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.19 | 0.21 | +0.02 | ±10% / ±0.02 ms | 3.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.89 | 0.92 | +0.03 | ±10% / ±0.09 ms | 3.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.89 | 0.92 | +0.03 | ±10% / ±0.09 ms | 3.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.05 | +0.01 | ±10% / ±0.02 ms | 9.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.18 | +0.00 | ±10% / ±0.02 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.18 | +0.00 | ±10% / ±0.02 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.06 | 2.17 | +0.11 | ±10% / ±0.22 ms | 1.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 9.79 | 9.82 | +0.03 | ±11% / ±1.09 ms | 11.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 9.79 | 9.82 | +0.03 | ±11% / ±1.09 ms | 11.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.42 | 0.49 | +0.08 | ±10% / ±0.05 ms | 8.2% | stable | 🔴 Regression (+18%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.81 | 1.81 | -0.00 | ±17% / ±0.31 ms | 16.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.81 | 1.81 | -0.00 | ±17% / ±0.31 ms | 16.9% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.11 | 0.11 | +0.00 | ±11% / ±0.02 ms | 6.9% | moderate | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.04 | 0.04 | +0.01 | ±19% / ±0.02 ms | 19.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.29 | 0.32 | +0.03 | ±10% / ±0.03 ms | 3.4% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.09 | 0.12 | +0.03 | ±11% / ±0.02 ms | 10.7% | stable | 🔴 Regression (+29%) |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.29 | 0.33 | +0.04 | ±10% / ±0.03 ms | 8.1% | stable | 🔴 Regression (+14%) |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.10 | 0.14 | +0.04 | ±17% / ±0.02 ms | 17.0% | stable | 🔴 Regression (+42%) |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.52 | 0.57 | +0.05 | ±14% / ±0.08 ms | 14.5% | moderate | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.10 | 0.13 | +0.03 | ±12% / ±0.02 ms | 11.6% | stable | 🔴 Regression (+29%) |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.93 | 0.99 | +0.06 | ±10% / ±0.10 ms | 6.2% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.27 | 0.35 | +0.08 | ±14% / ±0.05 ms | 14.1% | stable | 🔴 Regression (+29%) |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±141% / ±0.04 ms | 140.7% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.01 | 0.02 | +0.00 | ±194% / ±0.03 ms | 193.8% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | +0.00 | ±215% / ±0.02 ms | 215.0% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.19 | 0.20 | +0.01 | ±16% / ±0.03 ms | 15.6% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.15 | 0.16 | +0.01 | ±13% / ±0.02 ms | 12.6% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 8.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.73 | 1.87 | +0.14 | ±14% / ±0.27 ms | 6.2% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.44 | 1.55 | +0.10 | ±10% / ±0.15 ms | 5.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.36 | 0.36 | -0.01 | ±10% / ±0.04 ms | 2.1% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 21.16 | 22.06 | +0.90 | ±12% / ±2.71 ms | 7.2% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 15.64 | 15.43 | -0.21 | ±10% / ±1.56 ms | 2.4% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 4.01 | 3.85 | -0.16 | ±11% / ±0.46 ms | 5.7% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | -0.00 | ±150% / ±0.02 ms | 75.0% | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | +0.00 | ±296% / ±0.04 ms | 296.2% | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±1000% / ±0.02 ms | 1000.0% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.05 | +0.00 | ±22% / ±0.02 ms | 21.7% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 5.6% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.38 | 0.38 | +0.00 | ±10% / ±0.04 ms | 7.6% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 7.5% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 4.27 | 4.50 | +0.24 | ±10% / ±0.45 ms | 4.5% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.83 | 0.87 | +0.04 | ±14% / ±0.12 ms | 13.7% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.39 | 0.21 | -0.17 | ±88% / ±0.34 ms | 88.0% | noisy | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.39 | 0.21 | -0.17 | ±88% / ±0.34 ms | 88.0% | noisy | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.55 | 0.55 | +0.00 | ±12% / ±0.07 ms | 4.2% | moderate | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.55 | 0.55 | +0.00 | ±12% / ±0.07 ms | 4.2% | moderate | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | +0.00 | ±55% / ±0.02 ms | 55.4% | moderate | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03 | +0.00 | ±55% / ±0.02 ms | 55.4% | moderate | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.06 | 0.05 | -0.01 | ±24% / ±0.02 ms | 24.5% | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.06 | 0.05 | -0.01 | ±24% / ±0.02 ms | 24.5% | stable | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.76 | 3.44 | -0.32 | ±10% / ±0.38 ms | 1.9% | stable | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.76 | 3.44 | -0.32 | ±10% / ±0.38 ms | 1.9% | stable | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.79 | 1.69 | -1.11 | ±27% / ±0.77 ms | 27.4% | moderate | 🟢 Win (-40%) |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.79 | 1.69 | -1.11 | ±27% / ±0.77 ms | 27.4% | moderate | 🟢 Win (-40%) |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 5.79 | 5.94 | +0.15 | ±23% / ±1.39 ms | 9.7% | moderate | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 5.79 | 5.94 | +0.15 | ±23% / ±1.39 ms | 9.7% | moderate | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.26 | 0.40 | +0.14 | ±138% / ±0.55 ms | 83.7% | noisy | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.26 | 0.40 | +0.14 | ±138% / ±0.55 ms | 83.7% | noisy | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | +0.00 | ±11% / ±0.02 ms | 8.8% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | +0.00 | ±11% / ±0.02 ms | 8.8% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.42 | 0.45 | +0.02 | ±10% / ±0.04 ms | 8.1% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.42 | 0.45 | +0.02 | ±10% / ±0.04 ms | 8.1% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.14 | 4.15 | +0.00 | ±10% / ±0.41 ms | 6.0% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.14 | 4.15 | +0.00 | ±10% / ±0.41 ms | 6.0% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.57 | 0.56 | -0.01 | ±22% / ±0.13 ms | 9.0% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.57 | 0.56 | -0.01 | ±22% / ±0.13 ms | 9.0% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.07 | -0.00 | ±11% / ±0.02 ms | 11.4% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.07 | -0.00 | ±11% / ±0.02 ms | 11.4% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 7.00 | 5.42 | -1.58 | ±16% / ±1.15 ms | 16.4% | stable | 🟢 Win (-23%) |
| Write Performance / Batched Write Inside Transaction (100... | 7.00 | 5.42 | -1.58 | ±16% / ±1.15 ms | 16.4% | stable | 🟢 Win (-23%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.43 | 0.43 | +0.00 | ±10% / ±0.04 ms | 1.9% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.43 | 0.43 | +0.00 | ±10% / ±0.04 ms | 1.9% | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.05 | +0.00 | ±17% / ±0.02 ms | 15.4% | moderate | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.05 | +0.00 | ±17% / ±0.02 ms | 15.4% | moderate | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.57 | 1.65 | +0.07 | ±10% / ±0.16 ms | 4.0% | stable | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.57 | 1.65 | +0.07 | ±10% / ±0.16 ms | 4.0% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.19 | -0.00 | ±10% / ±0.02 ms | 3.2% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.19 | -0.00 | ±10% / ±0.02 ms | 3.2% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.11 | +0.01 | ±11% / ±0.02 ms | 6.4% | moderate | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.11 | +0.01 | ±11% / ±0.02 ms | 6.4% | moderate | ⚪ Within noise |

**Summary:** 5 wins, 8 regressions, 140 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.00 | 0.02 | +0.02 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 0.00 | 3.50 | +3.50 MB | ±2.01 MB | 🔴 Regression (+3.50 MB) |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.03 | +0.03 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 0.00 | 0.00 | +0.00 MB | ±2.63 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 1.27 | 1.77 | +0.50 MB | ±12.48 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 6.00 | +6.00 MB | ±3.01 MB | 🔴 Regression (+6.00 MB) |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 3.69 | 0.00 | -3.69 MB | ±2.41 MB | 🟢 Win (-3.69 MB) |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±9.58 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 1.39 | 6.13 | +4.74 MB | ±5.71 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / resqlite select() | 7.09 | 1.63 | -5.46 MB | ±4.56 MB | 🟢 Win (-5.46 MB) |
| Memory / Select 10k rows → Maps / sqlite3 select() | 6.38 | 5.72 | -0.66 MB | ±3.05 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 1.00 | 1.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.02 | 0.06 | +0.04 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 2 wins, 2 regressions, 11 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 3814 | 3959 | +145 | ±100 | 🔴 More re-emits (+145) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 3764 | 3153 | -611 | ±100 | 🔴 Invalidation elided (-611) — writes not firing |

**Granularity summary:** 0 fewer-re-emit, 2 more-re-emit, 4 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


