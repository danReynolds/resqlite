# resqlite Benchmark Results

Generated: 2026-04-22T08:49:48.919927

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp093-alias-read-tables`
- Repeats: `1`
- Comparison baseline: `2026-04-20T12-27-09-exp088-setlk-timeout.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.092 | 0.197 | 0.022 | 0.042 |
| sqlite3 select() | 0.137 | 0.262 | 0.137 | 0.262 |
| sqlite_async select() | 0.262 | 1.130 | 0.028 | 0.099 |
| drift select() | 0.273 | 0.706 | 0.013 | 0.037 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.081 | 0.318 | 0.011 | 0.046 |
| sqlite3 select() | 0.292 | 0.825 | 0.292 | 0.825 |
| sqlite_async select() | 0.380 | 0.970 | 0.018 | 0.061 |
| drift select() | 0.562 | 1.175 | 0.025 | 0.153 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.445 | 0.947 | 0.077 | 0.104 |
| sqlite3 select() | 1.295 | 1.519 | 1.295 | 1.519 |
| sqlite_async select() | 1.363 | 1.660 | 0.104 | 0.126 |
| drift select() | 1.861 | 2.199 | 0.097 | 0.131 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.824 | 9.570 | 0.719 | 1.117 |
| sqlite3 select() | 15.684 | 18.886 | 15.684 | 18.886 |
| sqlite_async select() | 14.524 | 21.883 | 0.784 | 0.943 |
| drift select() | 25.061 | 41.208 | 0.793 | 2.208 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.097 | 0.209 | 0.075 | 0.120 |
| sqlite3 + jsonEncode | 0.052 | 0.158 | 0.052 | 0.158 |
| sqlite_async + jsonEncode | 0.130 | 0.232 | 0.032 | 0.044 |
| drift + jsonEncode | 0.098 | 0.175 | 0.026 | 0.035 |
| resqlite selectBytes() | 0.019 | 0.021 | 0.000 | 0.003 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.234 | 0.300 | 0.178 | 0.233 |
| sqlite3 + jsonEncode | 0.270 | 0.331 | 0.270 | 0.331 |
| sqlite_async + jsonEncode | 0.329 | 0.434 | 0.161 | 0.223 |
| drift + jsonEncode | 0.394 | 0.478 | 0.164 | 0.184 |
| resqlite selectBytes() | 0.053 | 0.056 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 2.075 | 4.236 | 1.647 | 3.610 |
| sqlite3 + jsonEncode | 2.884 | 4.597 | 2.884 | 4.597 |
| sqlite_async + jsonEncode | 2.829 | 3.120 | 1.584 | 1.712 |
| drift + jsonEncode | 3.394 | 3.818 | 1.618 | 1.728 |
| resqlite selectBytes() | 0.367 | 0.440 | 0.000 | 0.006 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 22.559 | 25.140 | 15.531 | 17.127 |
| sqlite3 + jsonEncode | 34.611 | 50.189 | 34.611 | 50.189 |
| sqlite_async + jsonEncode | 31.219 | 33.646 | 15.580 | 17.015 |
| drift + jsonEncode | 51.206 | 101.376 | 20.307 | 30.178 |
| resqlite selectBytes() | 4.685 | 14.061 | 0.006 | 0.010 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.141 | 0.509 | 0.032 | 0.350 |
| sqlite3 | 0.371 | 1.301 | 0.371 | 1.301 |
| sqlite_async | 0.449 | 0.766 | 0.050 | 0.070 |
| drift | 0.853 | 5.248 | 0.062 | 0.092 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.956 | 1.040 | 0.286 | 0.297 |
| sqlite3 | 3.461 | 4.022 | 3.461 | 4.022 |
| sqlite_async | 3.238 | 3.630 | 0.364 | 0.377 |
| drift | 8.032 | 13.218 | 0.411 | 0.832 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.667 | 1.253 | 0.110 | 0.143 |
| sqlite3 | 1.640 | 2.156 | 1.640 | 2.156 |
| sqlite_async | 1.580 | 1.839 | 0.133 | 0.147 |
| drift | 2.332 | 2.676 | 0.143 | 0.158 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.300 | 0.305 | 0.101 | 0.105 |
| sqlite3 | 1.196 | 4.858 | 1.196 | 4.858 |
| sqlite_async | 1.178 | 1.598 | 0.132 | 0.146 |
| drift | 1.800 | 5.032 | 0.145 | 0.316 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.292 | 0.307 | 0.095 | 0.101 |
| sqlite3 | 1.036 | 1.431 | 1.036 | 1.431 |
| sqlite_async | 1.055 | 1.657 | 0.128 | 0.150 |
| drift | 1.629 | 1.941 | 0.128 | 0.170 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.021 | 0.050 | 0.002 | 0.004 |
| sqlite3 | 0.022 | 0.024 | 0.022 | 0.024 |
| sqlite_async | 0.094 | 0.239 | 0.005 | 0.017 |
| drift | 0.095 | 0.183 | 0.006 | 0.017 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.033 | 0.066 | 0.005 | 0.005 |
| sqlite3 | 0.069 | 0.084 | 0.069 | 0.084 |
| sqlite_async | 0.132 | 0.234 | 0.008 | 0.014 |
| drift | 0.148 | 0.212 | 0.008 | 0.013 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.054 | 0.061 | 0.009 | 0.011 |
| sqlite3 | 0.126 | 0.129 | 0.126 | 0.129 |
| sqlite_async | 0.167 | 0.296 | 0.013 | 0.020 |
| drift | 0.222 | 0.319 | 0.013 | 0.021 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.253 | 0.420 | 0.049 | 0.064 |
| sqlite3 | 0.591 | 0.643 | 0.591 | 0.643 |
| sqlite_async | 0.545 | 0.661 | 0.050 | 0.064 |
| drift | 0.926 | 1.039 | 0.055 | 0.068 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.392 | 0.523 | 0.089 | 0.122 |
| sqlite3 | 1.249 | 1.652 | 1.249 | 1.652 |
| sqlite_async | 1.203 | 1.552 | 0.108 | 0.133 |
| drift | 2.090 | 5.872 | 0.115 | 0.370 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.230 | 5.468 | 0.194 | 0.489 |
| sqlite3 | 2.665 | 5.840 | 2.665 | 5.840 |
| sqlite_async | 3.137 | 8.915 | 0.228 | 1.251 |
| drift | 3.709 | 4.765 | 0.218 | 0.249 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.374 | 6.544 | 0.458 | 0.602 |
| sqlite3 | 7.663 | 10.904 | 7.663 | 10.904 |
| sqlite_async | 6.569 | 8.253 | 0.517 | 0.620 |
| drift | 10.299 | 14.527 | 0.520 | 0.871 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 6.435 | 14.998 | 0.961 | 4.924 |
| sqlite3 | 21.805 | 52.076 | 21.805 | 52.076 |
| sqlite_async | 13.701 | 19.153 | 0.983 | 2.879 |
| drift | 23.360 | 32.304 | 0.968 | 1.799 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 13.801 | 29.472 | 1.856 | 4.571 |
| sqlite3 | 34.138 | 41.052 | 34.138 | 41.052 |
| sqlite_async | 39.647 | 61.567 | 1.988 | 6.126 |
| drift | 55.315 | 75.553 | 1.958 | 7.230 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.039 | 0.060 | 0.039 | 0.060 |
| sqlite3 + jsonEncode | 0.036 | 0.038 | 0.036 | 0.038 |
| sqlite_async + jsonEncode | 0.086 | 0.152 | 0.086 | 0.152 |
| drift + jsonEncode | 0.074 | 0.136 | 0.074 | 0.136 |
| resqlite selectBytes() | 0.016 | 0.020 | 0.016 | 0.020 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.111 | 0.177 | 0.111 | 0.177 |
| sqlite3 + jsonEncode | 0.143 | 0.163 | 0.143 | 0.163 |
| sqlite_async + jsonEncode | 0.175 | 0.228 | 0.175 | 0.228 |
| drift + jsonEncode | 0.201 | 0.268 | 0.201 | 0.268 |
| resqlite selectBytes() | 0.034 | 0.049 | 0.034 | 0.049 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.209 | 0.263 | 0.209 | 0.263 |
| sqlite3 + jsonEncode | 0.292 | 0.399 | 0.292 | 0.399 |
| sqlite_async + jsonEncode | 0.325 | 0.584 | 0.325 | 0.584 |
| drift + jsonEncode | 0.389 | 0.503 | 0.389 | 0.503 |
| resqlite selectBytes() | 0.053 | 0.068 | 0.053 | 0.068 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.912 | 1.037 | 0.912 | 1.037 |
| sqlite3 + jsonEncode | 1.354 | 2.781 | 1.354 | 2.781 |
| sqlite_async + jsonEncode | 1.328 | 1.893 | 1.328 | 1.893 |
| drift + jsonEncode | 1.704 | 1.851 | 1.704 | 1.851 |
| resqlite selectBytes() | 0.187 | 0.234 | 0.187 | 0.234 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.936 | 3.189 | 1.936 | 3.189 |
| sqlite3 + jsonEncode | 2.633 | 4.992 | 2.633 | 4.992 |
| sqlite_async + jsonEncode | 2.703 | 4.668 | 2.703 | 4.668 |
| drift + jsonEncode | 3.243 | 6.102 | 3.243 | 6.102 |
| resqlite selectBytes() | 0.358 | 0.409 | 0.358 | 0.409 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.960 | 6.486 | 3.960 | 6.486 |
| sqlite3 + jsonEncode | 5.382 | 8.118 | 5.382 | 8.118 |
| sqlite_async + jsonEncode | 5.856 | 10.235 | 5.856 | 10.235 |
| drift + jsonEncode | 7.465 | 15.693 | 7.465 | 15.693 |
| resqlite selectBytes() | 1.112 | 3.126 | 1.112 | 3.126 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 11.383 | 14.056 | 11.383 | 14.056 |
| sqlite3 + jsonEncode | 15.180 | 17.632 | 15.180 | 17.632 |
| sqlite_async + jsonEncode | 15.205 | 19.013 | 15.205 | 19.013 |
| drift + jsonEncode | 18.864 | 25.571 | 18.864 | 25.571 |
| resqlite selectBytes() | 2.011 | 3.583 | 2.011 | 3.583 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 21.256 | 24.039 | 21.256 | 24.039 |
| sqlite3 + jsonEncode | 33.045 | 45.050 | 33.045 | 45.050 |
| sqlite_async + jsonEncode | 32.578 | 36.145 | 32.578 | 36.145 |
| drift + jsonEncode | 42.931 | 55.879 | 42.931 | 55.879 |
| resqlite selectBytes() | 3.905 | 6.106 | 3.905 | 6.106 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 44.808 | 53.779 | 44.808 | 53.779 |
| sqlite3 + jsonEncode | 90.908 | 139.384 | 90.908 | 139.384 |
| sqlite_async + jsonEncode | 74.221 | 123.401 | 74.221 | 123.401 |
| drift + jsonEncode | 92.191 | 116.030 | 92.191 | 116.030 |
| resqlite selectBytes() | 8.155 | 13.369 | 8.155 | 13.369 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.38 | 0.30 |
| sqlite_async | 0.95 | 1.32 | 0.95 |
| drift | 1.61 | 2.15 | 1.61 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.34 | 0.38 | 0.17 |
| sqlite_async | 1.59 | 2.50 | 0.79 |
| drift | 3.10 | 3.77 | 1.55 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.49 | 0.73 | 0.12 |
| sqlite_async | 2.74 | 4.28 | 0.69 |
| drift | 7.05 | 9.25 | 1.76 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.92 | 1.32 | 0.11 |
| sqlite_async | 4.93 | 6.05 | 0.62 |
| drift | 14.01 | 19.65 | 1.75 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each iteration runs 500 sequential queries over 100 iterations per library. 95% CI and MDE values derive from per-iteration QPS samples via percentile bootstrap (deterministic, seed=202440478).

| Metric | Value |
|---|---:|
| resqlite qps | 80535 |
| resqlite per query | 0.012 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 80535 | 76389..85647 | 5.7 | 52.0 |
| sqlite3 | 172384 | 167065..178571 | 3.3 | 27.1 |
| sqlite_async | 38062 | 36528..38956 | 3.2 | 25.5 |
| drift | 39888 | 38914..40989 | 2.6 | 22.0 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.566 | 15.008 | 14.566 | 15.008 |
| sqlite_async | 37.643 | 45.716 | 37.643 | 45.716 |
| drift | 57.451 | 63.382 | 57.451 | 63.382 |
| sqlite3 (no cache) | 26.634 | 38.165 | 26.634 | 38.165 |
| sqlite3 (cached stmt) | 25.562 | 29.559 | 25.562 | 29.559 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 2.577 | 5.238 | 2.577 | 5.238 |
| sqlite3 execute() | 1.003 | 2.426 | 1.003 | 2.426 |
| sqlite_async execute() | 4.218 | 7.951 | 4.218 | 7.951 |
| drift execute() | 4.281 | 8.061 | 4.281 | 8.061 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.060 | 0.087 | 0.060 | 0.087 |
| sqlite3 executeBatch() | 0.052 | 0.067 | 0.052 | 0.067 |
| sqlite_async executeBatch() | 0.125 | 0.161 | 0.125 | 0.161 |
| drift executeBatch() | 0.123 | 0.173 | 0.123 | 0.173 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.499 | 1.334 | 0.499 | 1.334 |
| sqlite3 executeBatch() | 0.473 | 0.559 | 0.473 | 0.559 |
| sqlite_async executeBatch() | 0.622 | 0.891 | 0.622 | 0.891 |
| drift executeBatch() | 0.946 | 2.339 | 0.946 | 2.339 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 6.874 | 10.512 | 6.874 | 10.512 |
| sqlite3 executeBatch() | 4.797 | 5.411 | 4.797 | 5.411 |
| sqlite_async executeBatch() | 6.072 | 8.324 | 6.072 | 8.324 |
| drift executeBatch() | 7.111 | 7.930 | 7.111 | 7.930 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.054 | 0.068 | 0.054 | 0.068 |
| sqlite_async writeTransaction() | 0.089 | 0.117 | 0.089 | 0.117 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.078 | 0.118 | 0.078 | 0.118 |
| resqlite tx.execute() loop | 0.758 | 0.986 | 0.758 | 0.986 |
| sqlite_async tx.execute() loop | 1.225 | 1.557 | 1.225 | 1.557 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.510 | 0.653 | 0.510 | 0.653 |
| resqlite tx.execute() loop | 6.439 | 7.450 | 6.439 | 7.450 |
| sqlite_async tx.execute() loop | 11.897 | 15.553 | 11.897 | 15.553 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.118 | 0.163 | 0.118 | 0.163 |
| sqlite_async tx.getAll() | 0.226 | 0.388 | 0.226 | 0.388 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.199 | 0.228 | 0.199 | 0.228 |
| sqlite_async tx.getAll() | 0.389 | 0.519 | 0.389 | 0.519 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.043 | 0.093 | 0.043 | 0.093 |
| sqlite_async watch() | 0.138 | 0.226 | 0.138 | 0.226 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.066 | 0.229 | 0.066 | 0.229 |
| sqlite_async | 0.099 | 0.213 | 0.099 | 0.213 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.258 | 0.480 | 0.258 | 0.480 |
| sqlite_async | 1.102 | 2.668 | 1.102 | 2.668 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.263 | 0.435 | 0.263 | 0.435 |
| sqlite_async | 0.400 | 0.644 | 0.400 | 0.644 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.470 | 2.470 | 2.470 | 2.470 |
| sqlite_async | 11.571 | 11.571 | 11.571 | 11.571 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.231 | 5.789 | 4.231 | 5.789 |
| sqlite_async | 9.023 | 13.370 | 9.023 | 13.370 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.520 | 0.820 | 0.520 | 0.820 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 7.706 | 10.390 | 7.706 | 10.390 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. On resqlite's main branch this ratio is driven toward 0 by experiment 075 (C-side result-hash short-circuit), not by writer-side column-tracking (exp 052 is not implemented). The two mechanisms are indistinguishable on this read-side benchmark.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 78.5 | 0.000 |
| sqlite_async | 3736 | 1032.7 | 1.027 |
| drift | 5000 | 1155.3 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 79.3 | 0.000 |
| sqlite_async | 3639 | 1110.0 | 1.027 |
| drift | 5000 | 1242.1 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 226.85 | 230.60 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 437.39 | 443.59 | 0.00 | 0.00 | 1127 | 3 |
| drift stream() | 759.66 | 1032.14 | 0.19 | 0.75 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.029 | 0.062 | 0.000 | 0.000 |
| sqlite3 | 0.021 | 0.047 | 0.021 | 0.047 |
| sqlite_async | 0.050 | 0.089 | 0.000 | 0.000 |
| drift | 0.078 | 0.320 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.021 | 0.049 | 0.000 | 0.000 |
| sqlite3 | 0.014 | 0.030 | 0.014 | 0.030 |
| sqlite_async | 0.040 | 0.077 | 0.000 | 0.000 |
| drift | 0.059 | 0.246 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.029 | 0.047 | 0.000 | 0.000 |
| sqlite3 | 0.032 | 0.039 | 0.032 | 0.039 |
| sqlite_async | 0.065 | 0.093 | 0.000 | 0.000 |
| drift | 0.062 | 0.202 | 0.000 | 0.001 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.010 | 0.022 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.007 | 0.005 | 0.007 |
| sqlite_async | 0.026 | 0.037 | 0.000 | 0.000 |
| drift | 0.022 | 0.077 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.041 | 0.054 | 0.004 | 0.004 |
| sqlite3 | 0.068 | 0.117 | 0.068 | 0.117 |
| sqlite_async | 0.080 | 0.086 | 0.001 | 0.001 |
| drift | 0.112 | 0.311 | 0.001 | 0.003 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 108.337 | 119.150 | 0.000 | 0.000 | 0 |
| sqlite_async | 210.007 | 212.401 | 0.000 | 0.000 | 35 |
| drift | 230.682 | 242.057 | 0.000 | 0.013 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 233.68 | 233.68 | 0.00 | 0.00 | 12.33 | 222.13 | 0 |
| sqlite_async | 511.08 | 511.08 | 0.04 | 0.04 | 37.95 | 473.12 | 1160 |
| drift | 2105.86 | 2105.86 | 0.81 | 0.81 | 12.74 | 2093.11 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 5.56 | 17.53 | 0.00..8.19 | ±4.09 |
| sqlite3 select() | 6.95 | 9.72 | 1.58..8.72 | ±3.57 |
| sqlite_async select() | 1.00 | 1.50 | 0.50..1.00 | ±0.25 |
| drift select() | 11.13 | 59.06 | 0.00..17.06 | ±8.53 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 4.16 | 8.00 | 0.00..8.00 | ±4.00 |
| resqlite + jsonEncode | 0.00 | 58.11 | 0.00..11.02 | ±5.51 |
| sqlite3 + jsonEncode | 2.11 | 53.72 | 0.00..12.78 | ±6.39 |
| sqlite_async + jsonEncode | 0.00 | 7.56 | 0.00..5.45 | ±2.73 |
| drift + jsonEncode | 0.52 | 56.63 | 0.00..19.02 | ±9.51 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.00 | 2.42 | 0.00..0.00 | ±0.00 |
| sqlite3 executeBatch() | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 3.39 | 0.00..0.00 | ±0.00 |
| drift batch() | 0.80 | 4.52 | 0.05..2.53 | ±1.24 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.08 | 0.20 | 0.00..0.11 | ±0.05 |
| sqlite_async watch() | 0.00 | 0.63 | 0.00..0.13 | ±0.06 |

## SQLite Diagnostics

resqlite-only internal SQLite counters captured via `Database.diagnostics()` after representative workloads. Values reflect the writer plus idle readers in this connection pool; they are not process-global SQLite totals.

### Warm read working set (20000 rows + 2000 point lookups)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | Readers busy |
|---|---|---|---|---|---|---|
| resqlite | 3207.0 | 3189.5 | 5.3 | 12.2 | 2048.0 | 0 |

### Statement cache footprint (48 distinct SELECT texts)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | Readers busy |
|---|---|---|---|---|---|---|
| resqlite | 3300.0 | 3189.5 | 5.3 | 105.2 | 2048.0 | 0 |

### WAL after write burst (1000 inserted rows)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | Readers busy |
|---|---|---|---|---|---|---|
| resqlite | 257.5 | 240.0 | 5.3 | 12.2 | 161.0 | 0 |

## Comparison vs Previous Run

Previous: `2026-04-20T12-27-09-exp088-setlk-timeout.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Noise threshold | Stability | Status |
|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Chat Sim (v1) / Insert message / resqlite | 0.03 | 0.03 | -0.01 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.30 | +0.00 | ±10% / ±0.03 ms | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.30 | +0.00 | ±10% / ±0.03 ms | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.70 | 0.34 | -0.36 | ±10% / ±0.07 ms | single run | 🟢 Win (-51%) |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.35 | 0.17 | -0.18 | ±10% / ±0.03 ms | single run | 🟢 Win (-51%) |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.67 | 0.49 | -0.18 | ±10% / ±0.07 ms | single run | 🟢 Win (-27%) |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.17 | 0.12 | -0.05 | ±10% / ±0.02 ms | single run | 🟢 Win (-29%) |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 3.81 | 0.92 | -2.89 | ±10% / ±0.38 ms | single run | 🟢 Win (-76%) |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.48 | 0.11 | -0.37 | ±10% / ±0.05 ms | single run | 🟢 Win (-77%) |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.05 | 0.04 | -0.01 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 109.95 | 108.34 | -1.61 | ±10% / ±11.00 ms | single run | ⚪ Neutral |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 295.96 | 233.68 | -62.28 | ±10% / ±29.60 ms | single run | 🟢 Win (-21%) |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 284.92 | 226.85 | -58.07 | ±10% / ±28.49 ms | single run | 🟢 Win (-20%) |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 16.89 | 14.57 | -2.33 | ±10% / ±1.69 ms | single run | 🟢 Win (-14%) |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 16.89 | 14.57 | -2.33 | ±10% / ±1.69 ms | single run | 🟢 Win (-14%) |
| Point Query Throughput / resqlite qps | 73977.00 | 80535.00 | +6558.00 | ±10% / ±8053.50 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.02 | 0.02 | +0.01 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.02 | 0.02 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.02 | 0.02 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.06 | 0.05 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.21 | 0.21 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.21 | 0.21 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.06 | 0.05 | -0.01 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.06 | 0.05 | -0.01 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.41 | 0.39 | -0.01 | ±10% / ±0.04 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 3.48 | 1.94 | -1.54 | ±10% / ±0.35 ms | single run | 🟢 Win (-44%) |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 3.48 | 1.94 | -1.54 | ±10% / ±0.35 ms | single run | 🟢 Win (-44%) |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.37 | 0.36 | -0.01 | ±10% / ±0.04 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.37 | 0.36 | -0.01 | ±10% / ±0.04 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 12.76 | 6.43 | -6.32 | ±10% / ±1.28 ms | single run | 🟢 Win (-50%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 25.73 | 21.26 | -4.47 | ±10% / ±2.57 ms | single run | 🟢 Win (-17%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 25.73 | 21.26 | -4.47 | ±10% / ±2.57 ms | single run | 🟢 Win (-17%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 1.19 | 0.96 | -0.23 | ±10% / ±0.12 ms | single run | 🟢 Win (-19%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 4.42 | 3.90 | -0.51 | ±10% / ±0.44 ms | single run | 🟢 Win (-12%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 4.42 | 3.90 | -0.51 | ±10% / ±0.44 ms | single run | 🟢 Win (-12%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.85 | 1.23 | +0.38 | ±10% / ±0.12 ms | single run | 🔴 Regression (+45%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 4.32 | 3.96 | -0.36 | ±10% / ±0.43 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 4.32 | 3.96 | -0.36 | ±10% / ±0.43 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.18 | 0.19 | +0.02 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 1.78 | 1.11 | -0.67 | ±10% / ±0.18 ms | single run | 🟢 Win (-38%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 1.78 | 1.11 | -0.67 | ±10% / ±0.18 ms | single run | 🟢 Win (-38%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 15.93 | 13.80 | -2.13 | ±10% / ±1.59 ms | single run | 🟢 Win (-13%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 53.69 | 44.81 | -8.88 | ±10% / ±5.37 ms | single run | 🟢 Win (-17%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 53.69 | 44.81 | -8.88 | ±10% / ±5.37 ms | single run | 🟢 Win (-17%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.84 | 1.86 | +0.01 | ±10% / ±0.19 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 9.97 | 8.15 | -1.82 | ±10% / ±1.00 ms | single run | 🟢 Win (-18%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 9.97 | 8.15 | -1.82 | ±10% / ±1.00 ms | single run | 🟢 Win (-18%) |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.11 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.11 | 0.11 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.04 | 0.03 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.04 | 0.03 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.20 | 0.25 | +0.05 | ±10% / ±0.03 ms | single run | 🔴 Regression (+23%) |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 1.30 | 0.91 | -0.39 | ±10% / ±0.13 ms | single run | 🟢 Win (-30%) |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 1.30 | 0.91 | -0.39 | ±10% / ±0.13 ms | single run | 🟢 Win (-30%) |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.05 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.20 | 0.19 | -0.02 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.20 | 0.19 | -0.02 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 3.81 | 2.37 | -1.44 | ±10% / ±0.38 ms | single run | 🟢 Win (-38%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 17.55 | 11.38 | -6.17 | ±10% / ±1.76 ms | single run | 🟢 Win (-35%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 17.55 | 11.38 | -6.17 | ±10% / ±1.76 ms | single run | 🟢 Win (-35%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.47 | 0.46 | -0.01 | ±10% / ±0.05 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 3.13 | 2.01 | -1.11 | ±10% / ±0.31 ms | single run | 🟢 Win (-36%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 3.13 | 2.01 | -1.11 | ±10% / ±0.31 ms | single run | 🟢 Win (-36%) |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.17 | 0.14 | -0.03 | ±10% / ±0.02 ms | single run | 🟢 Win (-16%) |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.04 | 0.03 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.34 | 0.29 | -0.04 | ±10% / ±0.03 ms | single run | 🟢 Win (-13%) |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.10 | 0.10 | -0.01 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.70 | 0.30 | -0.40 | ±10% / ±0.07 ms | single run | 🟢 Win (-57%) |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.14 | 0.10 | -0.04 | ±10% / ±0.02 ms | single run | 🟢 Win (-28%) |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.69 | 0.67 | -0.02 | ±10% / ±0.07 ms | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.11 | 0.11 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 2.80 | 0.96 | -1.84 | ±10% / ±0.28 ms | single run | 🟢 Win (-66%) |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.43 | 0.29 | -0.15 | ±10% / ±0.04 ms | single run | 🟢 Win (-34%) |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.08 | 0.10 | +0.02 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.05 | 0.07 | +0.02 | ±10% / ±0.02 ms | single run | 🔴 Regression (+47%) |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.03 | 0.02 | -0.01 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.30 | 0.23 | -0.07 | ±10% / ±0.03 ms | single run | 🟢 Win (-23%) |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.21 | 0.18 | -0.03 | ±10% / ±0.02 ms | single run | 🟢 Win (-14%) |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.06 | 0.05 | -0.01 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 2.08 | 2.08 | +0.00 | ±10% / ±0.21 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.61 | 1.65 | +0.03 | ±10% / ±0.16 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.40 | 0.37 | -0.03 | ±10% / ±0.04 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 27.92 | 22.56 | -5.36 | ±10% / ±2.79 ms | single run | 🟢 Win (-19%) |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 19.25 | 15.53 | -3.72 | ±10% / ±1.93 ms | single run | 🟢 Win (-19%) |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 4.89 | 4.68 | -0.21 | ±10% / ±0.49 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Select → Maps / 10 rows / resqlite select() | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Select → Maps / 10 rows / resqlite select() [main] | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Select → Maps / 100 rows / resqlite select() | 0.08 | 0.08 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Select → Maps / 1000 rows / resqlite select() | 0.45 | 0.45 | -0.01 | ±10% / ±0.05 ms | single run | ⚪ Neutral |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.08 | 0.08 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Select → Maps / 10000 rows / resqlite select() | 5.73 | 4.82 | -0.91 | ±10% / ±0.57 ms | single run | 🟢 Win (-16%) |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.71 | 0.72 | +0.00 | ±10% / ±0.07 ms | single run | ⚪ Neutral |
| Streaming / Fan-out (10 streams) / resqlite | 0.42 | 0.26 | -0.16 | ±10% / ±0.04 ms | single run | 🟢 Win (-38%) |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.42 | 0.26 | -0.16 | ±10% / ±0.04 ms | single run | 🟢 Win (-38%) |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.93 | 0.52 | -0.41 | ±10% / ±0.09 ms | single run | 🟢 Win (-44%) |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.93 | 0.52 | -0.41 | ±10% / ±0.09 ms | single run | 🟢 Win (-44%) |
| Streaming / Initial Emission / resqlite stream() | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Streaming / Initial Emission / resqlite stream() [main] | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Streaming / Invalidation Latency / resqlite | 0.06 | 0.07 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Streaming / Invalidation Latency / resqlite [main] | 0.06 | 0.07 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 6.05 | 4.23 | -1.82 | ±10% / ±0.60 ms | single run | 🟢 Win (-30%) |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 6.05 | 4.23 | -1.82 | ±10% / ±0.60 ms | single run | 🟢 Win (-30%) |
| Streaming / Stream Churn (100 cycles) / resqlite | 4.65 | 2.47 | -2.18 | ±10% / ±0.46 ms | single run | 🟢 Win (-47%) |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 4.65 | 2.47 | -2.18 | ±10% / ±0.46 ms | single run | 🟢 Win (-47%) |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 12.27 | 7.71 | -4.57 | ±10% / ±1.23 ms | single run | 🟢 Win (-37%) |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 12.27 | 7.71 | -4.57 | ±10% / ±1.23 ms | single run | 🟢 Win (-37%) |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.31 | 0.26 | -0.05 | ±10% / ±0.03 ms | single run | 🟢 Win (-16%) |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.31 | 0.26 | -0.05 | ±10% / ±0.03 ms | single run | 🟢 Win (-16%) |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.45 | 0.50 | +0.05 | ±10% / ±0.05 ms | single run | ⚪ Neutral |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.45 | 0.50 | +0.05 | ±10% / ±0.05 ms | single run | ⚪ Neutral |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 5.94 | 6.87 | +0.93 | ±10% / ±0.69 ms | single run | 🔴 Regression (+16%) |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 5.94 | 6.87 | +0.93 | ±10% / ±0.69 ms | single run | 🔴 Regression (+16%) |
| Write Performance / Batched Write Inside Transaction (100... | 1.13 | 0.76 | -0.37 | ±10% / ±0.11 ms | single run | 🟢 Win (-33%) |
| Write Performance / Batched Write Inside Transaction (100... | 1.13 | 0.76 | -0.37 | ±10% / ±0.11 ms | single run | 🟢 Win (-33%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.08 | 0.08 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.08 | 0.08 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 9.41 | 6.44 | -2.97 | ±10% / ±0.94 ms | single run | 🟢 Win (-32%) |
| Write Performance / Batched Write Inside Transaction (100... | 9.41 | 6.44 | -2.97 | ±10% / ±0.94 ms | single run | 🟢 Win (-32%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.64 | 0.51 | -0.13 | ±10% / ±0.06 ms | single run | 🟢 Win (-21%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.64 | 0.51 | -0.13 | ±10% / ±0.06 ms | single run | 🟢 Win (-21%) |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.05 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.05 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Write Performance / Single Inserts (100 sequential) / res... | 4.56 | 2.58 | -1.98 | ±10% / ±0.46 ms | single run | 🟢 Win (-43%) |
| Write Performance / Single Inserts (100 sequential) / res... | 4.56 | 2.58 | -1.98 | ±10% / ±0.46 ms | single run | 🟢 Win (-43%) |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.20 | 0.20 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.20 | 0.20 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.13 | 0.12 | -0.02 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.13 | 0.12 | -0.02 | ±10% / ±0.02 ms | single run | ⚪ Neutral |

**Summary:** 63 wins, 5 regressions, 85 neutral

Comparison threshold uses `max(10%, 3 × current MAD%)`, plus an absolute floor of `±0.02 ms`.
That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.42 | 0.80 | +0.38 MB | ±1.24 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 0.00 | 0.52 | +0.52 MB | ±9.51 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 0.00 | 0.00 | +0.00 MB | ±5.51 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 4.16 | +4.16 MB | ±4.00 MB | 🔴 Regression (+4.16 MB) |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 12.55 | 2.11 | -10.44 MB | ±6.39 MB | 🟢 Win (-10.44 MB) |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±2.73 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 12.31 | 11.13 | -1.18 MB | ±8.53 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / resqlite select() | 6.81 | 5.56 | -1.25 MB | ±4.09 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite3 select() | 3.42 | 6.95 | +3.53 MB | ±3.57 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 1.00 | 1.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.06 | 0.08 | +0.02 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 1 wins, 1 regressions, 13 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 3392 | 3736 | +344 | ±100 | 🔴 More re-emits (+344) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 2671 | 3639 | +968 | ±100 | 🔴 More re-emits (+968) |

**Granularity summary:** 0 fewer-re-emit, 2 more-re-emit, 4 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


