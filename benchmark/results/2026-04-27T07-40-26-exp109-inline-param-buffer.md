# resqlite Benchmark Results

Generated: 2026-04-27T07:40:26.085866

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp109-inline-param-buffer`
- Repeats: `5`
- Runtime: `dart-vm / Dart 3.11.0`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `danreynolds/peaceful-engelbart-0bf523 @ fee929ce0d5e (dirty)`
- Comparison baseline: `2026-04-27T07-29-26-baseline-for-exp109.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.013 | 0.017 | 0.001 | 0.002 |
| sqlite3 select() | 0.015 | 0.019 | 0.015 | 0.019 |
| sqlite_async select() | 0.037 | 0.045 | 0.001 | 0.002 |
| drift select() | 0.056 | 0.071 | 0.002 | 0.003 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.047 | 0.053 | 0.009 | 0.010 |
| sqlite3 select() | 0.114 | 0.264 | 0.114 | 0.264 |
| sqlite_async select() | 0.128 | 0.184 | 0.010 | 0.012 |
| drift select() | 0.218 | 0.338 | 0.010 | 0.015 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.407 | 0.877 | 0.090 | 0.098 |
| sqlite3 select() | 1.107 | 2.942 | 1.107 | 2.942 |
| sqlite_async select() | 1.055 | 1.976 | 0.097 | 0.105 |
| drift select() | 1.683 | 2.411 | 0.099 | 0.106 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.580 | 10.321 | 0.850 | 1.107 |
| sqlite3 select() | 14.187 | 16.885 | 14.187 | 16.885 |
| sqlite_async select() | 11.548 | 14.377 | 0.906 | 2.271 |
| drift select() | 21.481 | 32.836 | 0.950 | 2.083 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.025 | 0.029 | 0.016 | 0.017 |
| sqlite3 + jsonEncode | 0.031 | 0.032 | 0.031 | 0.032 |
| sqlite_async + jsonEncode | 0.048 | 0.107 | 0.016 | 0.019 |
| drift + jsonEncode | 0.054 | 0.057 | 0.016 | 0.017 |
| resqlite selectBytes() | 0.009 | 0.010 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.222 | 0.574 | 0.175 | 0.463 |
| sqlite3 + jsonEncode | 0.263 | 0.304 | 0.263 | 0.304 |
| sqlite_async + jsonEncode | 0.278 | 0.469 | 0.161 | 0.246 |
| drift + jsonEncode | 0.337 | 0.563 | 0.162 | 0.176 |
| resqlite selectBytes() | 0.042 | 0.044 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.836 | 1.891 | 1.518 | 1.565 |
| sqlite3 + jsonEncode | 2.499 | 4.487 | 2.499 | 4.487 |
| sqlite_async + jsonEncode | 2.404 | 5.322 | 1.471 | 3.312 |
| drift + jsonEncode | 2.895 | 5.090 | 1.462 | 2.362 |
| resqlite selectBytes() | 0.352 | 0.366 | 0.000 | 0.000 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 22.290 | 24.895 | 15.218 | 18.211 |
| sqlite3 + jsonEncode | 30.173 | 39.507 | 30.173 | 39.507 |
| sqlite_async + jsonEncode | 29.519 | 32.456 | 15.595 | 17.610 |
| drift + jsonEncode | 38.385 | 50.803 | 15.648 | 22.222 |
| resqlite selectBytes() | 3.938 | 7.206 | 0.002 | 0.007 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.106 | 0.108 | 0.036 | 0.037 |
| sqlite3 | 0.316 | 0.350 | 0.316 | 0.350 |
| sqlite_async | 0.362 | 0.418 | 0.042 | 0.046 |
| drift | 0.582 | 0.669 | 0.042 | 0.048 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.906 | 0.957 | 0.268 | 0.274 |
| sqlite3 | 3.091 | 3.678 | 3.091 | 3.678 |
| sqlite_async | 2.771 | 3.214 | 0.318 | 0.321 |
| drift | 4.507 | 5.850 | 0.319 | 0.332 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.524 | 0.554 | 0.100 | 0.104 |
| sqlite3 | 1.368 | 1.391 | 1.368 | 1.391 |
| sqlite_async | 1.323 | 1.658 | 0.114 | 0.119 |
| drift | 1.871 | 2.280 | 0.113 | 0.115 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.290 | 0.312 | 0.095 | 0.102 |
| sqlite3 | 0.938 | 0.957 | 0.938 | 0.957 |
| sqlite_async | 0.889 | 0.915 | 0.114 | 0.116 |
| drift | 1.405 | 1.420 | 0.111 | 0.115 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.295 | 0.308 | 0.097 | 0.101 |
| sqlite3 | 0.904 | 1.558 | 0.904 | 1.558 |
| sqlite_async | 0.937 | 1.051 | 0.121 | 0.125 |
| drift | 1.569 | 2.009 | 0.122 | 0.125 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.013 | 0.014 | 0.001 | 0.001 |
| sqlite3 | 0.015 | 0.016 | 0.015 | 0.016 |
| sqlite_async | 0.034 | 0.036 | 0.001 | 0.001 |
| drift | 0.050 | 0.069 | 0.001 | 0.003 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.028 | 0.057 | 0.005 | 0.006 |
| sqlite3 | 0.060 | 0.198 | 0.060 | 0.198 |
| sqlite_async | 0.077 | 0.197 | 0.005 | 0.008 |
| drift | 0.141 | 0.433 | 0.007 | 0.022 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.047 | 0.055 | 0.009 | 0.010 |
| sqlite3 | 0.115 | 0.137 | 0.115 | 0.137 |
| sqlite_async | 0.125 | 0.127 | 0.010 | 0.010 |
| drift | 0.184 | 0.216 | 0.010 | 0.011 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.201 | 0.213 | 0.044 | 0.045 |
| sqlite3 | 0.548 | 0.598 | 0.548 | 0.598 |
| sqlite_async | 0.532 | 0.548 | 0.048 | 0.050 |
| drift | 0.801 | 0.901 | 0.047 | 0.053 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.387 | 0.393 | 0.088 | 0.090 |
| sqlite3 | 1.084 | 1.137 | 1.084 | 1.137 |
| sqlite_async | 1.048 | 1.132 | 0.096 | 0.099 |
| drift | 1.655 | 1.861 | 0.098 | 0.101 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.822 | 0.903 | 0.177 | 0.185 |
| sqlite3 | 2.078 | 2.613 | 2.078 | 2.613 |
| sqlite_async | 1.953 | 2.293 | 0.181 | 0.186 |
| drift | 2.992 | 3.496 | 0.179 | 0.182 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.057 | 4.931 | 0.419 | 0.501 |
| sqlite3 | 5.174 | 7.373 | 5.174 | 7.373 |
| sqlite_async | 5.476 | 6.396 | 0.481 | 0.564 |
| drift | 8.027 | 8.225 | 0.449 | 0.455 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.316 | 9.738 | 0.845 | 1.084 |
| sqlite3 | 14.592 | 21.814 | 14.592 | 21.814 |
| sqlite_async | 11.574 | 12.955 | 0.939 | 0.985 |
| drift | 18.630 | 25.450 | 0.921 | 2.366 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 10.884 | 16.030 | 1.706 | 2.460 |
| sqlite3 | 34.978 | 70.927 | 34.978 | 70.927 |
| sqlite_async | 36.800 | 45.437 | 1.864 | 2.111 |
| drift | 49.235 | 63.312 | 1.876 | 3.796 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.026 | 0.027 | 0.026 | 0.027 |
| sqlite3 + jsonEncode | 0.029 | 0.031 | 0.029 | 0.031 |
| sqlite_async + jsonEncode | 0.045 | 0.048 | 0.045 | 0.048 |
| drift + jsonEncode | 0.051 | 0.052 | 0.051 | 0.052 |
| resqlite selectBytes() | 0.010 | 0.010 | 0.010 | 0.010 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.100 | 0.104 | 0.100 | 0.104 |
| sqlite3 + jsonEncode | 0.129 | 0.135 | 0.129 | 0.135 |
| sqlite_async + jsonEncode | 0.145 | 0.161 | 0.145 | 0.161 |
| drift + jsonEncode | 0.168 | 0.171 | 0.168 | 0.171 |
| resqlite selectBytes() | 0.025 | 0.026 | 0.025 | 0.026 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.193 | 0.198 | 0.193 | 0.198 |
| sqlite3 + jsonEncode | 0.252 | 0.264 | 0.252 | 0.264 |
| sqlite_async + jsonEncode | 0.261 | 0.270 | 0.261 | 0.270 |
| drift + jsonEncode | 0.314 | 0.320 | 0.314 | 0.320 |
| resqlite selectBytes() | 0.042 | 0.043 | 0.042 | 0.043 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.900 | 1.435 | 0.900 | 1.435 |
| sqlite3 + jsonEncode | 1.222 | 3.288 | 1.222 | 3.288 |
| sqlite_async + jsonEncode | 1.285 | 2.634 | 1.285 | 2.634 |
| drift + jsonEncode | 1.567 | 3.102 | 1.567 | 3.102 |
| resqlite selectBytes() | 0.182 | 0.185 | 0.182 | 0.185 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.867 | 5.520 | 1.867 | 5.520 |
| sqlite3 + jsonEncode | 2.541 | 3.993 | 2.541 | 3.993 |
| sqlite_async + jsonEncode | 2.393 | 3.522 | 2.393 | 3.522 |
| drift + jsonEncode | 2.894 | 5.287 | 2.894 | 5.287 |
| resqlite selectBytes() | 0.354 | 0.360 | 0.354 | 0.360 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.868 | 6.102 | 3.868 | 6.102 |
| sqlite3 + jsonEncode | 5.430 | 10.074 | 5.430 | 10.074 |
| sqlite_async + jsonEncode | 5.091 | 7.715 | 5.091 | 7.715 |
| drift + jsonEncode | 6.264 | 9.426 | 6.264 | 9.426 |
| resqlite selectBytes() | 0.821 | 1.679 | 0.821 | 1.679 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 10.315 | 14.340 | 10.315 | 14.340 |
| sqlite3 + jsonEncode | 14.555 | 24.321 | 14.555 | 24.321 |
| sqlite_async + jsonEncode | 13.407 | 17.424 | 13.407 | 17.424 |
| drift + jsonEncode | 17.914 | 24.257 | 17.914 | 24.257 |
| resqlite selectBytes() | 1.904 | 1.981 | 1.904 | 1.981 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.480 | 30.246 | 20.480 | 30.246 |
| sqlite3 + jsonEncode | 29.327 | 35.026 | 29.327 | 35.026 |
| sqlite_async + jsonEncode | 30.600 | 36.947 | 30.600 | 36.947 |
| drift + jsonEncode | 37.224 | 43.345 | 37.224 | 43.345 |
| resqlite selectBytes() | 3.701 | 5.203 | 3.701 | 5.203 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 44.489 | 50.478 | 44.489 | 50.478 |
| sqlite3 + jsonEncode | 61.266 | 94.914 | 61.266 | 94.914 |
| sqlite_async + jsonEncode | 65.867 | 84.944 | 65.867 | 84.944 |
| drift + jsonEncode | 81.149 | 111.387 | 81.149 | 111.387 |
| resqlite selectBytes() | 8.844 | 11.004 | 8.844 | 11.004 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.30 | 0.30 |
| sqlite_async | 0.89 | 0.96 | 0.89 |
| drift | 1.43 | 1.78 | 1.43 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.32 | 0.15 |
| sqlite_async | 1.27 | 1.56 | 0.63 |
| drift | 2.57 | 2.89 | 1.28 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.36 | 0.45 | 0.09 |
| sqlite_async | 2.10 | 2.77 | 0.52 |
| drift | 4.91 | 5.43 | 1.23 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.79 | 1.41 | 0.10 |
| sqlite_async | 4.39 | 4.91 | 0.55 |
| drift | 10.09 | 12.58 | 1.26 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 146189 |
| resqlite per query | 0.007 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 146189 | 124039..147580 | 8.1 | 4.7 |
| sqlite3 | 182949 | 177489..189325 | 3.2 | 10.5 |
| sqlite_async | 50922 | 45096..51600 | 6.4 | 4.7 |
| drift | 47041 | 46331..47489 | 1.2 | 3.9 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.843 | 17.356 | 14.843 | 17.356 |
| sqlite_async | 34.511 | 37.504 | 34.511 | 37.504 |
| drift | 51.291 | 63.786 | 51.291 | 63.786 |
| sqlite3 (no cache) | 23.026 | 23.152 | 23.026 | 23.152 |
| sqlite3 (cached stmt) | 23.694 | 30.889 | 23.694 | 30.889 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.611 | 2.359 | 1.611 | 2.359 |
| sqlite3 execute() | 1.096 | 1.579 | 1.096 | 1.579 |
| sqlite_async execute() | 3.091 | 3.795 | 3.091 | 3.795 |
| drift execute() | 3.469 | 4.358 | 3.469 | 4.358 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.051 | 0.054 | 0.051 | 0.054 |
| sqlite3 executeBatch() | 0.048 | 0.049 | 0.048 | 0.049 |
| sqlite_async executeBatch() | 0.096 | 0.121 | 0.096 | 0.121 |
| drift executeBatch() | 0.115 | 0.121 | 0.115 | 0.121 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.385 | 0.409 | 0.385 | 0.409 |
| sqlite3 executeBatch() | 0.434 | 0.452 | 0.434 | 0.452 |
| sqlite_async executeBatch() | 0.522 | 0.617 | 0.522 | 0.617 |
| drift executeBatch() | 0.647 | 0.783 | 0.647 | 0.783 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 3.659 | 4.536 | 3.659 | 4.536 |
| sqlite3 executeBatch() | 4.010 | 4.237 | 4.010 | 4.237 |
| sqlite_async executeBatch() | 4.580 | 5.067 | 4.580 | 5.067 |
| drift executeBatch() | 5.850 | 6.396 | 5.850 | 6.396 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.051 | 0.083 | 0.051 | 0.083 |
| sqlite_async writeTransaction() | 0.078 | 0.088 | 0.078 | 0.088 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.064 | 0.069 | 0.064 | 0.069 |
| resqlite tx.execute() loop | 0.590 | 0.719 | 0.590 | 0.719 |
| sqlite_async tx.execute() loop | 0.987 | 1.070 | 0.987 | 1.070 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.384 | 0.465 | 0.384 | 0.465 |
| resqlite tx.execute() loop | 5.165 | 6.223 | 5.165 | 6.223 |
| sqlite_async tx.execute() loop | 10.114 | 13.437 | 10.114 | 13.437 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.107 | 0.111 | 0.107 | 0.111 |
| sqlite_async tx.getAll() | 0.208 | 0.226 | 0.208 | 0.226 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.192 | 0.242 | 0.192 | 0.242 |
| sqlite_async tx.getAll() | 0.366 | 0.393 | 0.366 | 0.393 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.027 | 0.032 | 0.027 | 0.032 |
| sqlite_async watch() | 0.116 | 0.157 | 0.116 | 0.157 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.059 | 0.107 | 0.059 | 0.107 |
| sqlite_async | 0.069 | 0.087 | 0.069 | 0.087 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.210 | 0.259 | 0.210 | 0.259 |
| sqlite_async | 0.864 | 5.770 | 0.864 | 5.770 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.396 | 0.707 | 0.396 | 0.707 |
| sqlite_async | 0.614 | 1.539 | 0.614 | 1.539 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.920 | 1.920 | 1.920 | 1.920 |
| sqlite_async | 10.803 | 10.803 | 10.803 | 10.803 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.463 | 4.478 | 3.463 | 4.478 |
| sqlite_async | 6.127 | 7.470 | 6.127 | 7.470 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.517 | 0.709 | 0.517 | 0.709 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 5.501 | 6.803 | 5.501 | 6.803 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. On resqlite's main branch this ratio is driven toward 0 by experiment 075 (C-side result-hash short-circuit), not by writer-side column-tracking (exp 052 is not implemented). The two mechanisms are indistinguishable on this read-side benchmark.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 69.1 | 0.000 |
| sqlite_async | 4244 | 984.5 | 1.218 |
| drift | 5000 | 992.3 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 73.7 | 0.000 |
| sqlite_async | 3484 | 1021.0 | 1.218 |
| drift | 5000 | 1073.6 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 227.00 | 227.72 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 442.54 | 442.98 | 0.00 | 0.00 | 1107 | 3 |
| drift stream() | 550.07 | 550.10 | 0.00 | 0.00 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.030 | 0.055 | 0.000 | 0.000 |
| sqlite3 | 0.019 | 0.028 | 0.019 | 0.028 |
| sqlite_async | 0.045 | 0.072 | 0.000 | 0.000 |
| drift | 0.036 | 0.046 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.022 | 0.041 | 0.000 | 0.000 |
| sqlite3 | 0.012 | 0.016 | 0.012 | 0.016 |
| sqlite_async | 0.036 | 0.055 | 0.000 | 0.000 |
| drift | 0.029 | 0.035 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.029 | 0.044 | 0.000 | 0.000 |
| sqlite3 | 0.030 | 0.034 | 0.030 | 0.034 |
| sqlite_async | 0.061 | 0.077 | 0.000 | 0.000 |
| drift | 0.051 | 0.055 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.011 | 0.021 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.024 | 0.033 | 0.000 | 0.000 |
| drift | 0.019 | 0.023 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.037 | 0.039 | 0.001 | 0.001 |
| sqlite3 | 0.065 | 0.070 | 0.065 | 0.070 |
| sqlite_async | 0.082 | 0.086 | 0.001 | 0.001 |
| drift | 0.087 | 0.089 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 110.280 | 112.609 | 0.000 | 0.000 | 0 |
| sqlite_async | 216.917 | 219.829 | 0.000 | 0.000 | 38 |
| drift | 222.076 | 227.161 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 241.00 | 241.00 | 0.00 | 0.00 | 11.87 | 229.12 | 0 |
| sqlite_async | 469.81 | 469.81 | 0.01 | 0.01 | 23.64 | 453.35 | 1173 |
| drift | 1724.55 | 1724.55 | 0.07 | 0.07 | 13.56 | 1710.99 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 1.36 | 14.19 | 0.00..9.86 | ±4.93 |
| sqlite3 select() | 4.73 | 22.95 | 0.00..8.77 | ±4.38 |
| sqlite_async select() | 1.00 | 1.50 | 0.50..1.00 | ±0.25 |
| drift select() | 5.16 | 19.55 | 0.00..10.55 | ±5.27 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 10.09 | 0.00..8.03 | ±4.02 |
| resqlite + jsonEncode | 0.00 | 23.06 | 0.00..2.72 | ±1.36 |
| sqlite3 + jsonEncode | 1.19 | 34.59 | 0.00..14.09 | ±7.05 |
| sqlite_async + jsonEncode | 0.00 | 19.66 | 0.00..19.16 | ±9.58 |
| drift + jsonEncode | 0.00 | 17.30 | 0.00..0.00 | ±0.00 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 1.00 | 2.16 | 0.52..1.08 | ±0.28 |
| sqlite3 executeBatch() | 0.00 | 0.08 | 0.00..0.06 | ±0.03 |
| sqlite_async executeBatch() | 0.02 | 0.02 | 0.00..0.02 | ±0.01 |
| drift batch() | 0.02 | 2.53 | 0.00..0.08 | ±0.04 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 1.06 | 0.05..0.06 | ±0.01 |
| sqlite_async watch() | 0.00 | 1.00 | 0.00..0.50 | ±0.25 |

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
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.02 | 0.02..0.03 | 10.4% | 20.8% | 0.0% | stable |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 16.7% | 33.3% | 11.1% | noisy |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02..0.03 | 26.2% | 52.4% | 9.5% | noisy |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.01..0.02 | 21.9% | 43.7% | 6.3% | moderate |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.29 | 0.29..0.30 | 1.7% | 3.4% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.29 | 0.29..0.30 | 1.7% | 3.4% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.30 | 0.30..0.31 | 1.7% | 3.3% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.15 | 0.15..0.15 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.36 | 0.36..0.37 | 1.4% | 2.8% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.09 | 0.09..0.09 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.70 | 0.67..0.95 | 20.0% | 40.0% | 4.3% | moderate |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.09 | 0.08..0.12 | 22.2% | 44.4% | 11.1% | noisy |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.04 | 6.0% | 11.9% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 150.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 109.03 | 107.76..110.91 | 1.4% | 2.9% | 1.1% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 241.00 | 238.03..243.35 | 1.1% | 2.2% | 1.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 222.53 | 218.09..227.00 | 2.0% | 4.0% | 1.4% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 14.48 | 14.15..15.04 | 3.1% | 6.1% | 2.2% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 14.48 | 14.15..15.04 | 3.1% | 6.1% | 2.2% | stable |
| Point Query Throughput / resqlite qps | 148419.00 | 146189.00..152664.00 | 2.2% | 4.4% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.01 | 15.4% | 30.8% | 15.4% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.04 | 18.5% | 37.0% | 3.7% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.04 | 18.5% | 37.0% | 3.7% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 50.0% | 100.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 27.3% | 54.5% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.02 | 27.3% | 54.5% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.04..0.05 | 5.3% | 10.6% | 4.3% | moderate |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.19 | 0.19..0.22 | 7.3% | 14.5% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.19 | 0.19..0.22 | 7.3% | 14.5% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 5.6% | 11.1% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.05 | 12.8% | 25.6% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.04 | 0.04..0.05 | 12.8% | 25.6% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.38 | 0.37..0.40 | 3.5% | 6.9% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.85 | 1.74..1.93 | 5.2% | 10.3% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.85 | 1.74..1.93 | 5.2% | 10.3% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.08 | 0.08..0.09 | 2.4% | 4.8% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.35 | 0.34..0.37 | 3.2% | 6.5% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.35 | 0.34..0.37 | 3.2% | 6.5% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.49 | 4.32..5.11 | 8.9% | 17.7% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 20.78 | 20.48..21.82 | 3.2% | 6.4% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 20.78 | 20.48..21.82 | 3.2% | 6.4% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.85 | 0.84..0.87 | 1.7% | 3.4% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 3.73 | 3.56..3.96 | 5.4% | 10.9% | 3.7% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 3.73 | 3.56..3.96 | 5.4% | 10.9% | 3.7% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.81 | 0.77..0.82 | 3.3% | 6.6% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.87 | 3.76..4.13 | 4.8% | 9.7% | 2.9% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.87 | 3.76..4.13 | 4.8% | 9.7% | 2.9% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.17 | 0.17..0.18 | 2.6% | 5.2% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.82 | 0.76..0.85 | 5.7% | 11.3% | 4.1% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.82 | 0.76..0.85 | 5.7% | 11.3% | 4.1% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.88 | 10.44..11.22 | 3.6% | 7.2% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 44.49 | 43.16..45.05 | 2.1% | 4.2% | 1.3% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 44.49 | 43.16..45.05 | 2.1% | 4.2% | 1.3% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.69 | 1.68..1.71 | 0.7% | 1.3% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 8.12 | 7.25..8.84 | 9.8% | 19.6% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 8.12 | 7.25..8.84 | 9.8% | 19.6% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03..0.03 | 8.9% | 17.9% | 3.6% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10..0.11 | 5.9% | 11.8% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.10 | 0.10..0.11 | 5.9% | 11.8% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.01 | 12.5% | 25.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.02..0.03 | 11.5% | 23.1% | 3.8% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.02..0.03 | 11.5% | 23.1% | 3.8% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.20 | 0.19..0.20 | 3.3% | 6.6% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.90 | 0.89..0.95 | 3.8% | 7.6% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.90 | 0.89..0.95 | 3.8% | 7.6% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04..0.04 | 2.3% | 4.7% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.18 | 0.18..0.19 | 3.6% | 7.1% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.18 | 0.18..0.19 | 3.6% | 7.1% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.23 | 2.06..2.62 | 12.6% | 25.2% | 6.9% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 10.40 | 10.13..10.93 | 3.8% | 7.6% | 2.5% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 10.40 | 10.13..10.93 | 3.8% | 7.6% | 2.5% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.44 | 0.42..0.45 | 3.4% | 6.8% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 1.90 | 1.80..1.95 | 4.0% | 7.9% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 1.90 | 1.80..1.95 | 4.0% | 7.9% | 1.6% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.10 | 0.10..0.11 | 5.6% | 11.2% | 1.0% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.03 | 0.03..0.04 | 16.2% | 32.4% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.31 | 0.29..0.31 | 2.3% | 4.6% | 1.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.10 | 0.10..0.10 | 2.1% | 4.1% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.29 | 0.29..0.30 | 1.9% | 3.8% | 0.3% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.10 | 0.10..0.10 | 1.6% | 3.1% | 1.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.53 | 0.52..0.56 | 3.3% | 6.6% | 0.8% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.10 | 0.10..0.10 | 1.0% | 2.0% | 1.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.91 | 0.90..0.91 | 0.7% | 1.3% | 0.2% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.27 | 0.26..0.27 | 1.1% | 2.2% | 1.1% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.06 | 63.5% | 126.9% | 3.8% | moderate |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.01..0.04 | 65.6% | 131.2% | 6.3% | moderate |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 45.5% | 90.9% | 18.2% | noisy |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.19..0.22 | 7.6% | 15.2% | 2.5% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.16 | 0.15..0.18 | 7.7% | 15.4% | 1.9% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.05 | 10.0% | 20.0% | 4.4% | moderate |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.76 | 1.74..1.87 | 3.7% | 7.5% | 1.1% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.46 | 1.45..1.53 | 2.9% | 5.9% | 0.9% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.35 | 0.35..0.37 | 3.3% | 6.5% | 0.3% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 21.41 | 20.17..23.72 | 8.3% | 16.6% | 4.1% | moderate |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 15.22 | 14.60..15.51 | 3.0% | 6.0% | 0.8% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.79 | 3.54..3.94 | 5.3% | 10.6% | 2.4% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 100.0% | 200.0% | 50.0% | noisy |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.09 | 311.5% | 623.1% | 7.7% | moderate |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 1100.0% | 2200.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.04..0.07 | 22.3% | 44.7% | 2.1% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 5.6% | 11.1% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.39 | 0.37..0.48 | 13.6% | 27.2% | 3.3% | moderate |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.08..0.09 | 5.1% | 10.2% | 2.3% | stable |
| Select → Maps / 10000 rows / resqlite select() | 4.56 | 4.31..4.85 | 6.0% | 12.0% | 4.7% | moderate |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.84 | 0.71..0.86 | 8.9% | 17.8% | 1.1% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.27 | 0.23..0.81 | 106.5% | 213.1% | 12.7% | noisy |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.27 | 0.23..0.81 | 106.5% | 213.1% | 12.7% | noisy |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.52 | 0.51..0.53 | 1.5% | 3.1% | 1.2% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.52 | 0.51..0.53 | 1.5% | 3.1% | 1.2% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.02..0.06 | 61.1% | 122.2% | 7.4% | moderate |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.02..0.06 | 61.1% | 122.2% | 7.4% | moderate |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.04..0.06 | 20.2% | 40.4% | 4.3% | moderate |
| Streaming / Invalidation Latency / resqlite [main] | 0.05 | 0.04..0.06 | 20.2% | 40.4% | 4.3% | moderate |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.40 | 3.32..3.46 | 2.2% | 4.3% | 0.4% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.40 | 3.32..3.46 | 2.2% | 4.3% | 0.4% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.84 | 1.50..2.47 | 26.3% | 52.5% | 12.8% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.84 | 1.50..2.47 | 26.3% | 52.5% | 12.8% | noisy |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 5.50 | 5.38..6.60 | 11.1% | 22.2% | 2.3% | stable |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 5.50 | 5.38..6.60 | 11.1% | 22.2% | 2.3% | stable |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.21 | 0.19..0.66 | 111.7% | 223.3% | 10.0% | noisy |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.21 | 0.19..0.66 | 111.7% | 223.3% | 10.0% | noisy |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.05 | 0.05..0.05 | 4.0% | 8.0% | 2.0% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.05 | 0.05..0.05 | 4.0% | 8.0% | 2.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.38 | 0.38..0.40 | 3.3% | 6.5% | 1.3% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.38 | 0.38..0.40 | 3.3% | 6.5% | 1.3% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.68 | 3.58..3.98 | 5.5% | 11.1% | 2.8% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.68 | 3.58..3.98 | 5.5% | 11.1% | 2.8% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.57 | 0.50..0.72 | 18.9% | 37.8% | 10.8% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.57 | 0.50..0.72 | 18.9% | 37.8% | 10.8% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.06 | 0.06..0.08 | 12.5% | 25.0% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.06 | 0.06..0.08 | 12.5% | 25.0% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.04 | 4.91..6.40 | 14.7% | 29.5% | 2.4% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.04 | 4.91..6.40 | 14.7% | 29.5% | 2.4% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.39 | 0.38..0.40 | 1.5% | 3.1% | 1.0% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.39 | 0.38..0.40 | 1.5% | 3.1% | 1.0% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05..0.06 | 9.8% | 19.6% | 2.0% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05..0.06 | 9.8% | 19.6% | 2.0% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.61 | 1.55..1.70 | 4.8% | 9.6% | 1.4% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.61 | 1.55..1.70 | 4.8% | 9.6% | 1.4% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.18..0.19 | 2.6% | 5.3% | 1.6% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.18..0.19 | 2.6% | 5.3% | 1.6% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.11 | 0.10..0.11 | 2.8% | 5.7% | 1.9% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.11 | 0.10..0.11 | 2.8% | 5.7% | 1.9% | stable |


## Comparison vs Previous Run

Previous: `2026-04-27T07-29-26-baseline-for-exp109.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.03 | 0.02 | -0.00 | ±10% / ±0.02 ms | 10.4% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | +0.00 | ±33% / ±0.02 ms | 16.7% | noisy | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02 | +0.00 | ±29% / ±0.02 ms | 26.2% | noisy | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.02 | +0.00 | ±22% / ±0.02 ms | 21.9% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.29 | -0.01 | ±10% / ±0.03 ms | 1.7% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.29 | -0.01 | ±10% / ±0.03 ms | 1.7% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.31 | 0.30 | -0.01 | ±10% / ±0.03 ms | 1.7% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.16 | 0.15 | -0.01 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 1.05 | 0.36 | -0.69 | ±10% / ±0.11 ms | 1.4% | stable | 🟢 Win (-66%) |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.26 | 0.09 | -0.17 | ±10% / ±0.03 ms | 0.0% | stable | 🟢 Win (-65%) |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.68 | 0.70 | +0.02 | ±20% / ±0.14 ms | 20.0% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.08 | 0.09 | +0.01 | ±33% / ±0.03 ms | 22.2% | noisy | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 6.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±150% / ±0.02 ms | 150.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 112.08 | 109.03 | -3.05 | ±10% / ±11.21 ms | 1.4% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 242.94 | 241.00 | -1.94 | ±10% / ±24.29 ms | 1.1% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 223.59 | 222.53 | -1.06 | ±10% / ±22.36 ms | 2.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 15.15 | 14.48 | -0.67 | ±10% / ±1.51 ms | 3.1% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 15.15 | 14.48 | -0.67 | ±10% / ±1.51 ms | 3.1% | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 144990.00 | 148419.00 | +3429.00 | ±10% / ±14841.90 ms | 2.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01 | +0.00 | ±46% / ±0.02 ms | 15.4% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±19% / ±0.02 ms | 18.5% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.03 | +0.00 | ±19% / ±0.02 ms | 18.5% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±50% / ±0.02 ms | 50.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±27% / ±0.02 ms | 27.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±27% / ±0.02 ms | 27.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.05 | +0.00 | ±13% / ±0.02 ms | 5.3% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.19 | +0.00 | ±10% / ±0.02 ms | 7.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.19 | +0.00 | ±10% / ±0.02 ms | 7.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 5.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±13% / ±0.02 ms | 12.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±13% / ±0.02 ms | 12.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.38 | 0.38 | +0.00 | ±10% / ±0.04 ms | 3.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.72 | 1.85 | +0.12 | ±10% / ±0.18 ms | 5.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.72 | 1.85 | +0.12 | ±10% / ±0.18 ms | 5.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.08 | -0.00 | ±10% / ±0.02 ms | 2.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.35 | +0.00 | ±10% / ±0.04 ms | 3.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.35 | +0.00 | ±10% / ±0.04 ms | 3.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.54 | 4.49 | -0.06 | ±10% / ±0.45 ms | 8.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 23.92 | 20.78 | -3.14 | ±10% / ±2.39 ms | 3.2% | stable | 🟢 Win (-13%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 23.92 | 20.78 | -3.14 | ±10% / ±2.39 ms | 3.2% | stable | 🟢 Win (-13%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.85 | 0.85 | -0.01 | ±10% / ±0.09 ms | 1.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.74 | 3.73 | -0.01 | ±11% / ±0.41 ms | 5.4% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.74 | 3.73 | -0.01 | ±11% / ±0.41 ms | 5.4% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.77 | 0.81 | +0.04 | ±10% / ±0.08 ms | 3.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.92 | 3.87 | -0.06 | ±10% / ±0.39 ms | 4.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.92 | 3.87 | -0.06 | ±10% / ±0.39 ms | 4.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.17 | 0.17 | +0.00 | ±10% / ±0.02 ms | 2.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.79 | 0.82 | +0.03 | ±12% / ±0.10 ms | 5.7% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.79 | 0.82 | +0.03 | ±12% / ±0.10 ms | 5.7% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 12.24 | 10.88 | -1.36 | ±10% / ±1.22 ms | 3.6% | stable | 🟢 Win (-11%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 45.01 | 44.49 | -0.52 | ±10% / ±4.50 ms | 2.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 45.01 | 44.49 | -0.52 | ±10% / ±4.50 ms | 2.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.77 | 1.69 | -0.08 | ±10% / ±0.18 ms | 0.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.50 | 8.12 | -0.38 | ±10% / ±0.85 ms | 9.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.50 | 8.12 | -0.38 | ±10% / ±0.85 ms | 9.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03 | +0.00 | ±11% / ±0.02 ms | 8.9% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 5.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 5.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±13% / ±0.02 ms | 12.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | +0.00 | ±12% / ±0.02 ms | 11.5% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | +0.00 | ±12% / ±0.02 ms | 11.5% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.19 | 0.20 | +0.01 | ±10% / ±0.02 ms | 3.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.87 | 0.90 | +0.03 | ±10% / ±0.09 ms | 3.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.87 | 0.90 | +0.03 | ±10% / ±0.09 ms | 3.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.18 | +0.00 | ±10% / ±0.02 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.18 | +0.00 | ±10% / ±0.02 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.07 | 2.23 | +0.16 | ±21% / ±0.46 ms | 12.6% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.88 | 10.40 | -0.48 | ±10% / ±1.09 ms | 3.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.88 | 10.40 | -0.48 | ±10% / ±1.09 ms | 3.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.42 | 0.44 | +0.02 | ±10% / ±0.04 ms | 3.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 2.08 | 1.90 | -0.17 | ±10% / ±0.21 ms | 4.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 2.08 | 1.90 | -0.17 | ±10% / ±0.21 ms | 4.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 5.6% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.04 | 0.03 | -0.00 | ±16% / ±0.02 ms | 16.2% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.31 | 0.31 | -0.00 | ±10% / ±0.03 ms | 2.3% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 2.1% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.29 | 0.29 | +0.00 | ±10% / ±0.03 ms | 1.9% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 1.6% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.57 | 0.53 | -0.04 | ±10% / ±0.06 ms | 3.3% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 1.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.96 | 0.91 | -0.05 | ±10% / ±0.10 ms | 0.7% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.28 | 0.27 | -0.01 | ±10% / ±0.03 ms | 1.1% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±63% / ±0.02 ms | 63.5% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.01 | 0.02 | +0.00 | ±66% / ±0.02 ms | 65.6% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | +0.00 | ±55% / ±0.02 ms | 45.5% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.20 | +0.00 | ±10% / ±0.02 ms | 7.6% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.16 | 0.16 | +0.00 | ±10% / ±0.02 ms | 7.7% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04 | +0.00 | ±13% / ±0.02 ms | 10.0% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.91 | 1.76 | -0.15 | ±10% / ±0.19 ms | 3.7% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.57 | 1.46 | -0.10 | ±10% / ±0.16 ms | 2.9% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.35 | 0.35 | +0.00 | ±10% / ±0.04 ms | 3.3% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.46 | 21.41 | +0.95 | ±12% / ±2.65 ms | 8.3% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 15.54 | 15.22 | -0.32 | ±10% / ±1.55 ms | 3.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.73 | 3.79 | +0.06 | ±10% / ±0.38 ms | 5.3% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±150% / ±0.02 ms | 100.0% | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | +0.00 | ±312% / ±0.04 ms | 311.5% | moderate | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±1100% / ±0.02 ms | 1100.0% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.05 | -0.00 | ±22% / ±0.02 ms | 22.3% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 5.6% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.38 | 0.39 | +0.01 | ±14% / ±0.05 ms | 13.6% | moderate | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 5.1% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 4.74 | 4.56 | -0.18 | ±14% / ±0.67 ms | 6.0% | moderate | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.89 | 0.84 | -0.04 | ±10% / ±0.09 ms | 8.9% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.27 | 0.27 | -0.00 | ±107% / ±0.29 ms | 106.5% | noisy | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.27 | 0.27 | -0.00 | ±107% / ±0.29 ms | 106.5% | noisy | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.52 | 0.52 | -0.00 | ±10% / ±0.05 ms | 1.5% | stable | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.52 | 0.52 | -0.00 | ±10% / ±0.05 ms | 1.5% | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | +0.00 | ±61% / ±0.02 ms | 61.1% | moderate | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03 | +0.00 | ±61% / ±0.02 ms | 61.1% | moderate | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.06 | 0.05 | -0.02 | ±20% / ±0.02 ms | 20.2% | moderate | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.06 | 0.05 | -0.02 | ±20% / ±0.02 ms | 20.2% | moderate | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 4.03 | 3.40 | -0.64 | ±10% / ±0.40 ms | 2.2% | stable | 🟢 Win (-16%) |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 4.03 | 3.40 | -0.64 | ±10% / ±0.40 ms | 2.2% | stable | 🟢 Win (-16%) |
| Streaming / Stream Churn (100 cycles) / resqlite | 3.50 | 1.84 | -1.66 | ±38% / ±1.34 ms | 26.3% | noisy | 🟢 Win (-48%) |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 3.50 | 1.84 | -1.66 | ±38% / ±1.34 ms | 26.3% | noisy | 🟢 Win (-48%) |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 5.79 | 5.50 | -0.28 | ±11% / ±0.64 ms | 11.1% | stable | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 5.79 | 5.50 | -0.28 | ±11% / ±0.64 ms | 11.1% | stable | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.28 | 0.21 | -0.07 | ±112% / ±0.31 ms | 111.7% | noisy | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.28 | 0.21 | -0.07 | ±112% / ±0.31 ms | 111.7% | noisy | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.05 | -0.00 | ±10% / ±0.02 ms | 4.0% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.05 | -0.00 | ±10% / ±0.02 ms | 4.0% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.42 | 0.38 | -0.04 | ±10% / ±0.04 ms | 3.3% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.42 | 0.38 | -0.04 | ±10% / ±0.04 ms | 3.3% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.21 | 3.68 | -0.53 | ±10% / ±0.42 ms | 5.5% | stable | 🟢 Win (-13%) |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.21 | 3.68 | -0.53 | ±10% / ±0.42 ms | 5.5% | stable | 🟢 Win (-13%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.58 | 0.57 | -0.00 | ±32% / ±0.19 ms | 18.9% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.58 | 0.57 | -0.00 | ±32% / ±0.19 ms | 18.9% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.06 | -0.00 | ±13% / ±0.02 ms | 12.5% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.06 | -0.00 | ±13% / ±0.02 ms | 12.5% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 5.57 | 5.04 | -0.53 | ±15% / ±0.82 ms | 14.7% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 5.57 | 5.04 | -0.53 | ±15% / ±0.82 ms | 14.7% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.43 | 0.39 | -0.04 | ±10% / ±0.04 ms | 1.5% | stable | 🟢 Win (-10%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.43 | 0.39 | -0.04 | ±10% / ±0.04 ms | 1.5% | stable | 🟢 Win (-10%) |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 9.8% | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 9.8% | stable | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.88 | 1.61 | -0.27 | ±10% / ±0.19 ms | 4.8% | stable | 🟢 Win (-14%) |
| Write Performance / Single Inserts (100 sequential) / res... | 1.88 | 1.61 | -0.27 | ±10% / ±0.19 ms | 4.8% | stable | 🟢 Win (-14%) |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.20 | 0.19 | -0.01 | ±10% / ±0.02 ms | 2.6% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.20 | 0.19 | -0.01 | ±10% / ±0.02 ms | 2.6% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.11 | 0.11 | -0.00 | ±10% / ±0.02 ms | 2.8% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.11 | 0.11 | -0.00 | ±10% / ±0.02 ms | 2.8% | stable | ⚪ Within noise |

**Summary:** 15 wins, 0 regressions, 138 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

✅ **No regressions beyond noise.** 15 benchmarks improved.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.56 | 0.02 | -0.54 MB | ±0.50 MB | 🟢 Win (-0.54 MB) |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 0.50 | 1.00 | +0.50 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.02 | +0.02 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 0.00 | 0.00 | +0.00 MB | ±1.36 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 0.00 | +0.00 MB | ±4.02 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 0.28 | 1.19 | +0.91 MB | ±7.05 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±9.58 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 10.56 | 5.16 | -5.40 MB | ±5.27 MB | 🟢 Win (-5.40 MB) |
| Memory / Select 10k rows → Maps / resqlite select() | 0.00 | 1.36 | +1.36 MB | ±4.93 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite3 select() | 5.56 | 4.73 | -0.83 MB | ±4.38 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 1.00 | 1.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.06 | 0.06 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 2 wins, 0 regressions, 13 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 3828 | 4244 | +416 | ±100 | 🔴 More re-emits (+416) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 3646 | 3484 | -162 | ±100 | 🔴 Invalidation elided (-162) — writes not firing |

**Granularity summary:** 0 fewer-re-emit, 2 more-re-emit, 4 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


