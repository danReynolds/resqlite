# resqlite Benchmark Results

Generated: 2026-06-17T10:23:22.160844

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp183-json-buf-retention-audit`
- Repeats: `1`
- Runtime: `dart-vm / Dart 3.11.5`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `exp-183-json-buf-retention-audit @ 3c840d9ad200 (dirty)`
- Comparison baseline: `2026-06-17T10-21-00-baseline-for-exp183.md`
- Comparison mode: `explicit`
- Comparison baseline compatibility: `compatible`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.085 | 0.124 | 0.018 | 0.033 |
| sqlite3 select() | 0.128 | 0.333 | 0.128 | 0.333 |
| sqlite_async select() | 0.233 | 0.329 | 0.022 | 0.029 |
| drift select() | 0.159 | 0.349 | 0.008 | 0.012 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.063 | 0.112 | 0.008 | 0.010 |
| sqlite3 select() | 0.217 | 0.337 | 0.217 | 0.337 |
| sqlite_async select() | 0.257 | 0.316 | 0.014 | 0.018 |
| drift select() | 0.342 | 0.469 | 0.014 | 0.022 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.381 | 0.470 | 0.055 | 0.060 |
| sqlite3 select() | 1.183 | 1.357 | 1.183 | 1.357 |
| sqlite_async select() | 1.233 | 1.341 | 0.085 | 0.092 |
| drift select() | 1.732 | 1.845 | 0.082 | 0.094 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.347 | 13.287 | 0.540 | 0.585 |
| sqlite3 select() | 14.601 | 18.828 | 14.601 | 18.828 |
| sqlite_async select() | 13.261 | 15.943 | 0.775 | 1.595 |
| drift select() | 20.919 | 25.893 | 0.764 | 1.005 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.126 | 0.151 | 0.102 | 0.109 |
| sqlite3 + jsonEncode | 0.105 | 0.197 | 0.105 | 0.197 |
| sqlite_async + jsonEncode | 0.113 | 0.199 | 0.028 | 0.036 |
| drift + jsonEncode | 0.099 | 0.164 | 0.025 | 0.034 |
| resqlite selectBytes() | 0.020 | 0.027 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.221 | 0.251 | 0.171 | 0.206 |
| sqlite3 + jsonEncode | 0.279 | 0.380 | 0.279 | 0.380 |
| sqlite_async + jsonEncode | 0.328 | 0.381 | 0.161 | 0.172 |
| drift + jsonEncode | 0.360 | 0.390 | 0.158 | 0.164 |
| resqlite selectBytes() | 0.053 | 0.056 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.859 | 3.039 | 1.520 | 2.471 |
| sqlite3 + jsonEncode | 2.664 | 5.331 | 2.664 | 5.331 |
| sqlite_async + jsonEncode | 2.673 | 4.333 | 1.536 | 2.451 |
| drift + jsonEncode | 3.169 | 5.904 | 1.533 | 3.153 |
| resqlite selectBytes() | 0.371 | 0.392 | 0.000 | 0.000 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 21.316 | 23.825 | 15.280 | 18.059 |
| sqlite3 + jsonEncode | 30.138 | 33.561 | 30.138 | 33.561 |
| sqlite_async + jsonEncode | 30.905 | 33.207 | 15.283 | 16.949 |
| drift + jsonEncode | 40.143 | 43.780 | 15.741 | 18.294 |
| resqlite selectBytes() | 3.625 | 5.122 | 0.001 | 0.006 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.082 | 0.235 | 0.014 | 0.161 |
| sqlite3 | 0.338 | 0.559 | 0.338 | 0.559 |
| sqlite_async | 0.402 | 0.483 | 0.036 | 0.042 |
| drift | 0.642 | 0.864 | 0.037 | 0.047 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.875 | 0.979 | 0.212 | 0.216 |
| sqlite3 | 3.402 | 3.734 | 3.402 | 3.734 |
| sqlite_async | 3.090 | 3.452 | 0.247 | 0.261 |
| drift | 4.954 | 7.328 | 0.263 | 0.271 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.503 | 0.532 | 0.063 | 0.066 |
| sqlite3 | 1.529 | 2.433 | 1.529 | 2.433 |
| sqlite_async | 1.506 | 1.681 | 0.092 | 0.097 |
| drift | 2.069 | 2.304 | 0.094 | 0.107 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.264 | 0.268 | 0.062 | 0.065 |
| sqlite3 | 1.057 | 1.148 | 1.057 | 1.148 |
| sqlite_async | 1.044 | 1.151 | 0.090 | 0.096 |
| drift | 1.553 | 1.767 | 0.091 | 0.106 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.285 | 0.323 | 0.064 | 0.078 |
| sqlite3 | 1.013 | 1.098 | 1.013 | 1.098 |
| sqlite_async | 1.009 | 1.143 | 0.088 | 0.103 |
| drift | 1.526 | 1.711 | 0.090 | 0.102 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.014 | 0.017 | 0.001 | 0.002 |
| sqlite3 | 0.022 | 0.027 | 0.022 | 0.027 |
| sqlite_async | 0.067 | 0.087 | 0.004 | 0.005 |
| drift | 0.056 | 0.070 | 0.004 | 0.005 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.027 | 0.028 | 0.003 | 0.003 |
| sqlite3 | 0.067 | 0.075 | 0.067 | 0.075 |
| sqlite_async | 0.103 | 0.137 | 0.005 | 0.006 |
| drift | 0.118 | 0.134 | 0.006 | 0.006 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.046 | 0.050 | 0.005 | 0.006 |
| sqlite3 | 0.123 | 0.127 | 0.123 | 0.127 |
| sqlite_async | 0.155 | 0.162 | 0.009 | 0.010 |
| drift | 0.200 | 0.215 | 0.010 | 0.011 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.183 | 0.187 | 0.027 | 0.028 |
| sqlite3 | 0.576 | 0.597 | 0.576 | 0.597 |
| sqlite_async | 0.566 | 0.590 | 0.038 | 0.040 |
| drift | 0.816 | 0.854 | 0.038 | 0.040 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.353 | 0.357 | 0.054 | 0.056 |
| sqlite3 | 1.152 | 1.254 | 1.152 | 1.254 |
| sqlite_async | 1.101 | 1.204 | 0.076 | 0.083 |
| drift | 1.615 | 1.844 | 0.076 | 0.085 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.764 | 1.434 | 0.109 | 0.131 |
| sqlite3 | 2.325 | 2.880 | 2.325 | 2.880 |
| sqlite_async | 2.220 | 2.512 | 0.150 | 0.164 |
| drift | 3.215 | 3.859 | 0.150 | 0.158 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.036 | 4.791 | 0.271 | 0.305 |
| sqlite3 | 5.878 | 7.416 | 5.878 | 7.416 |
| sqlite_async | 5.678 | 7.839 | 0.380 | 0.405 |
| drift | 8.880 | 9.608 | 0.382 | 0.398 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.285 | 10.449 | 0.545 | 0.894 |
| sqlite3 | 14.331 | 16.645 | 14.331 | 16.645 |
| sqlite_async | 13.512 | 18.747 | 0.777 | 1.977 |
| drift | 24.161 | 29.787 | 0.805 | 2.654 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 10.586 | 17.714 | 1.104 | 1.761 |
| sqlite3 | 33.993 | 38.985 | 33.993 | 38.985 |
| sqlite_async | 38.539 | 44.008 | 1.527 | 2.600 |
| drift | 48.764 | 62.119 | 1.480 | 8.776 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.034 | 0.036 | 0.034 | 0.036 |
| sqlite3 + jsonEncode | 0.037 | 0.041 | 0.037 | 0.041 |
| sqlite_async + jsonEncode | 0.079 | 0.105 | 0.079 | 0.105 |
| drift + jsonEncode | 0.073 | 0.097 | 0.073 | 0.097 |
| resqlite selectBytes() | 0.012 | 0.013 | 0.012 | 0.013 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.107 | 0.114 | 0.107 | 0.114 |
| sqlite3 + jsonEncode | 0.144 | 0.151 | 0.144 | 0.151 |
| sqlite_async + jsonEncode | 0.180 | 0.203 | 0.180 | 0.203 |
| drift + jsonEncode | 0.205 | 0.262 | 0.205 | 0.262 |
| resqlite selectBytes() | 0.027 | 0.028 | 0.027 | 0.028 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.200 | 0.213 | 0.200 | 0.213 |
| sqlite3 + jsonEncode | 0.277 | 0.308 | 0.277 | 0.308 |
| sqlite_async + jsonEncode | 0.299 | 0.345 | 0.299 | 0.345 |
| drift + jsonEncode | 0.341 | 0.475 | 0.341 | 0.475 |
| resqlite selectBytes() | 0.045 | 0.048 | 0.045 | 0.048 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.922 | 1.004 | 0.922 | 1.004 |
| sqlite3 + jsonEncode | 1.326 | 1.450 | 1.326 | 1.450 |
| sqlite_async + jsonEncode | 1.331 | 1.400 | 1.331 | 1.400 |
| drift + jsonEncode | 1.581 | 1.699 | 1.581 | 1.699 |
| resqlite selectBytes() | 0.181 | 0.190 | 0.181 | 0.190 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.740 | 1.833 | 1.740 | 1.833 |
| sqlite3 + jsonEncode | 2.521 | 2.754 | 2.521 | 2.754 |
| sqlite_async + jsonEncode | 2.441 | 2.657 | 2.441 | 2.657 |
| drift + jsonEncode | 2.937 | 4.142 | 2.937 | 4.142 |
| resqlite selectBytes() | 0.339 | 0.362 | 0.339 | 0.362 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.860 | 6.063 | 3.860 | 6.063 |
| sqlite3 + jsonEncode | 5.495 | 8.162 | 5.495 | 8.162 |
| sqlite_async + jsonEncode | 5.517 | 8.702 | 5.517 | 8.702 |
| drift + jsonEncode | 6.602 | 10.255 | 6.602 | 10.255 |
| resqlite selectBytes() | 0.686 | 0.718 | 0.686 | 0.718 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 9.821 | 12.143 | 9.821 | 12.143 |
| sqlite3 + jsonEncode | 15.052 | 17.567 | 15.052 | 17.567 |
| sqlite_async + jsonEncode | 14.348 | 17.692 | 14.348 | 17.692 |
| drift + jsonEncode | 17.072 | 19.510 | 17.072 | 19.510 |
| resqlite selectBytes() | 1.723 | 1.750 | 1.723 | 1.750 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.481 | 22.205 | 20.481 | 22.205 |
| sqlite3 + jsonEncode | 29.970 | 34.429 | 29.970 | 34.429 |
| sqlite_async + jsonEncode | 31.972 | 34.126 | 31.972 | 34.126 |
| drift + jsonEncode | 38.293 | 41.156 | 38.293 | 41.156 |
| resqlite selectBytes() | 3.482 | 3.552 | 3.482 | 3.552 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 43.051 | 46.628 | 43.051 | 46.628 |
| sqlite3 + jsonEncode | 62.223 | 67.633 | 62.223 | 67.633 |
| sqlite_async + jsonEncode | 70.881 | 78.342 | 70.881 | 78.342 |
| drift + jsonEncode | 83.707 | 101.147 | 83.707 | 101.147 |
| resqlite selectBytes() | 7.577 | 10.333 | 7.577 | 10.333 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.31 | 0.30 |
| sqlite_async | 1.06 | 1.18 | 1.06 |
| drift | 1.65 | 1.84 | 1.65 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.34 | 0.37 | 0.17 |
| sqlite_async | 1.56 | 1.93 | 0.78 |
| drift | 2.88 | 3.67 | 1.44 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.39 | 0.60 | 0.10 |
| sqlite_async | 2.69 | 5.04 | 0.67 |
| drift | 5.65 | 6.33 | 1.41 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.86 | 1.15 | 0.11 |
| sqlite_async | 5.16 | 6.05 | 0.65 |
| drift | 11.08 | 12.09 | 1.39 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 134620 |
| resqlite per query | 0.007 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 134620 | 133818..135639 | 0.7 | 2.3 |
| sqlite3 | 191404 | 190662..192420 | 0.5 | 1.5 |
| sqlite_async | 48594 | 47535..49392 | 1.9 | 6.5 |
| drift | 45744 | 44939..47113 | 2.4 | 5.3 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.572 | 15.100 | 14.572 | 15.100 |
| sqlite_async | 38.510 | 39.328 | 38.510 | 39.328 |
| drift | 54.668 | 56.560 | 54.668 | 56.560 |
| sqlite3 (no cache) | 25.127 | 28.063 | 25.127 | 28.063 |
| sqlite3 (cached stmt) | 24.806 | 25.357 | 24.806 | 25.357 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.594 | 2.410 | 1.594 | 2.410 |
| sqlite3 execute() | 0.956 | 1.672 | 0.956 | 1.672 |
| sqlite_async execute() | 3.166 | 3.959 | 3.166 | 3.959 |
| drift execute() | 3.436 | 4.884 | 3.436 | 4.884 |

### Concurrent Single Inserts (100 concurrent)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite concurrent execute() | 1.038 | 1.448 | 1.038 | 1.448 |
| sqlite3 concurrent execute() | 0.944 | 1.701 | 0.944 | 1.701 |
| sqlite_async concurrent execute() | 2.870 | 3.659 | 2.870 | 3.659 |
| drift concurrent execute() | 1.801 | 2.427 | 1.801 | 2.427 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.052 | 0.054 | 0.052 | 0.054 |
| sqlite3 executeBatch() | 0.050 | 0.051 | 0.050 | 0.051 |
| sqlite_async executeBatch() | 0.092 | 0.103 | 0.092 | 0.103 |
| drift executeBatch() | 0.111 | 0.116 | 0.111 | 0.116 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.409 | 0.429 | 0.409 | 0.429 |
| sqlite3 executeBatch() | 0.440 | 0.454 | 0.440 | 0.454 |
| sqlite_async executeBatch() | 0.531 | 0.674 | 0.531 | 0.674 |
| drift executeBatch() | 0.683 | 0.787 | 0.683 | 0.787 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 3.980 | 5.683 | 3.980 | 5.683 |
| sqlite3 executeBatch() | 4.377 | 4.758 | 4.377 | 4.758 |
| sqlite_async executeBatch() | 5.057 | 5.732 | 5.057 | 5.732 |
| drift executeBatch() | 6.266 | 8.710 | 6.266 | 8.710 |

### Wide Batch Insert (10000 rows x 20 params)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 13.322 | 23.198 | 13.322 | 23.198 |
| sqlite3 executeBatch() | 19.763 | 21.743 | 19.763 | 21.743 |
| sqlite_async executeBatch() | 22.997 | 26.356 | 22.997 | 26.356 |
| drift executeBatch() | 27.667 | 31.006 | 27.667 | 31.006 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.051 | 0.054 | 0.051 | 0.054 |
| sqlite_async writeTransaction() | 0.083 | 0.095 | 0.083 | 0.095 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.074 | 0.098 | 0.074 | 0.098 |
| resqlite tx.execute() loop | 0.580 | 0.641 | 0.580 | 0.641 |
| sqlite_async tx.execute() loop | 1.073 | 1.386 | 1.073 | 1.386 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.418 | 0.464 | 0.418 | 0.464 |
| resqlite tx.execute() loop | 5.345 | 6.435 | 5.345 | 6.435 |
| sqlite_async tx.execute() loop | 10.047 | 12.346 | 10.047 | 12.346 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.103 | 0.110 | 0.103 | 0.110 |
| sqlite_async tx.getAll() | 0.202 | 0.215 | 0.202 | 0.215 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.187 | 0.196 | 0.187 | 0.196 |
| sqlite_async tx.getAll() | 0.363 | 0.393 | 0.363 | 0.393 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 0.891 | 1.207 | 0.891 | 1.207 |
| resqlite nested transaction() depth=5 | 0.073 | 0.083 | 0.073 | 0.083 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.066 | 0.079 | 0.066 | 0.079 |
| sqlite_async watch() | 0.127 | 0.206 | 0.127 | 0.206 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.045 | 0.067 | 0.045 | 0.067 |
| sqlite_async | 0.078 | 0.131 | 0.078 | 0.131 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.211 | 0.278 | 0.211 | 0.278 |
| sqlite_async | 0.764 | 1.652 | 0.764 | 1.652 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.236 | 2.812 | 2.236 | 2.812 |

### Long-Payload Unchanged Fanout (8 streams, 64 rows x 32KB TEXT + 32KB BLOB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.010 | 3.932 | 3.010 | 3.932 |

### Long-Text 32KB Unchanged Fanout (8 unchanged streams, 64 rows x 32KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.254 | 4.485 | 3.254 | 4.485 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.228 | 0.304 | 0.228 | 0.304 |
| sqlite_async | 0.347 | 0.512 | 0.347 | 0.512 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.550 | 2.550 | 2.550 | 2.550 |
| sqlite_async | 9.338 | 9.338 | 9.338 | 9.338 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.359 | 4.063 | 3.359 | 4.063 |
| sqlite_async | 5.608 | 6.934 | 5.608 | 6.934 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.623 | 0.743 | 0.623 | 0.743 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 7.074 | 10.344 | 7.074 | 10.344 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. For resqlite, this emission metric can reflect writer-side column-level invalidation, experiment 075's native result-hash short-circuit, or both. Use A11c (Many-Streams Writer Throughput) when the question is specifically writer-side dispatch elision.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 69.7 | 0.000 |
| sqlite_async | 4433 | 1233.3 | 1.002 |
| drift | 5000 | 1073.7 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 73.7 | 0.000 |
| sqlite_async | 4424 | 1234.0 | 1.002 |
| drift | 5000 | 1063.7 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 214.20 | 215.42 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 431.84 | 432.99 | 0.00 | 0.00 | 1114 | 3 |
| drift stream() | 539.37 | 539.75 | 0.01 | 0.01 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.021 | 0.035 | 0.000 | 0.000 |
| sqlite3 | 0.019 | 0.027 | 0.019 | 0.027 |
| sqlite_async | 0.040 | 0.060 | 0.000 | 0.000 |
| drift | 0.043 | 0.068 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.016 | 0.025 | 0.000 | 0.000 |
| sqlite3 | 0.012 | 0.017 | 0.012 | 0.017 |
| sqlite_async | 0.032 | 0.047 | 0.000 | 0.000 |
| drift | 0.034 | 0.056 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.026 | 0.036 | 0.000 | 0.000 |
| sqlite3 | 0.032 | 0.035 | 0.032 | 0.035 |
| sqlite_async | 0.060 | 0.073 | 0.000 | 0.000 |
| drift | 0.056 | 0.064 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.009 | 0.017 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.022 | 0.027 | 0.000 | 0.000 |
| drift | 0.022 | 0.028 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.042 | 0.047 | 0.004 | 0.004 |
| sqlite3 | 0.070 | 0.083 | 0.070 | 0.083 |
| sqlite_async | 0.085 | 0.101 | 0.001 | 0.001 |
| drift | 0.101 | 0.131 | 0.001 | 0.002 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 105.358 | 105.557 | 0.000 | 0.000 | 0 |
| sqlite_async | 209.978 | 211.907 | 0.000 | 0.000 | 35 |
| drift | 218.306 | 219.730 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 434.03 | 434.03 | 0.00 | 0.00 | 13.36 | 420.67 | 2 |
| sqlite_async | 459.21 | 459.21 | 0.00 | 0.00 | 13.34 | 445.89 | 1186 |
| drift | 1735.75 | 1735.75 | 0.06 | 0.06 | 13.58 | 1722.17 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 0.00 | 13.42 | 0.00..6.45 | ±3.23 |
| sqlite3 select() | 5.08 | 19.86 | 1.16..8.73 | ±3.79 |
| sqlite_async select() | 1.00 | 1.50 | 0.95..1.00 | ±0.02 |
| drift select() | 3.84 | 10.47 | 0.00..6.84 | ±3.42 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 14.06 | 0.00..8.03 | ±4.02 |
| resqlite + jsonEncode | 0.00 | 58.23 | 0.00..0.00 | ±0.00 |
| sqlite3 + jsonEncode | 3.02 | 80.27 | 0.00..25.83 | ±12.91 |
| sqlite_async + jsonEncode | 0.00 | 19.16 | 0.00..3.03 | ±1.52 |
| drift + jsonEncode | 2.86 | 27.84 | 0.00..12.95 | ±6.48 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.44 | 29.83 | 0.00..0.53 | ±0.27 |
| sqlite3 executeBatch() | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 3.19 | 0.00..0.02 | ±0.01 |
| drift batch() | 0.00 | 2.50 | 0.00..0.00 | ±0.00 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.13 | 0.00..0.06 | ±0.03 |
| sqlite_async watch() | 0.00 | 0.50 | 0.00..0.03 | ±0.02 |

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

Previous: `2026-06-17T10-21-00-baseline-for-exp183.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.30 | +0.00 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.30 | +0.00 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.31 | 0.34 | +0.03 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.15 | 0.17 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+13%) |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.37 | 0.39 | +0.02 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.09 | 0.10 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.68 | 0.86 | +0.18 | ±10% / ±0.09 ms | 0.0% | single run | 🔴 Regression (+26%) |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.09 | 0.11 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+22%) |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 106.46 | 105.36 | -1.10 | ±10% / ±10.65 ms | 0.0% | single run | ⚪ Neutral |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 230.66 | 434.03 | +203.37 | ±10% / ±43.40 ms | 0.0% | single run | 🔴 Regression (+88%) |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 214.25 | 214.20 | -0.05 | ±10% / ±21.43 ms | 0.0% | single run | ⚪ Neutral |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.62 | 14.57 | -0.05 | ±10% / ±1.46 ms | 0.0% | single run | ⚪ Neutral |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.62 | 14.57 | -0.05 | ±10% / ±1.46 ms | 0.0% | single run | ⚪ Neutral |
| Point Query Throughput / resqlite qps | 112057.00 | 134620.00 | +22563.00 | ±10% / ±13462.00 ms | 0.0% | single run | 🟢 Win (20%) |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.02 | 0.01 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.04 | 0.03 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.04 | 0.03 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.20 | 0.20 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.20 | 0.20 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.36 | 0.35 | -0.00 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.84 | 1.74 | -0.10 | ±10% / ±0.18 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.84 | 1.74 | -0.10 | ±10% / ±0.18 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.34 | -0.01 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.34 | -0.01 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.20 | 4.29 | +0.08 | ±10% / ±0.43 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 21.49 | 20.48 | -1.00 | ±10% / ±2.15 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 21.49 | 20.48 | -1.00 | ±10% / ±2.15 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.54 | 0.55 | +0.01 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.46 | 3.48 | +0.02 | ±10% / ±0.35 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.46 | 3.48 | +0.02 | ±10% / ±0.35 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.76 | 0.76 | +0.01 | ±10% / ±0.08 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.85 | 3.86 | +0.01 | ±10% / ±0.39 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.85 | 3.86 | +0.01 | ±10% / ±0.39 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.70 | 0.69 | -0.02 | ±10% / ±0.07 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.70 | 0.69 | -0.02 | ±10% / ±0.07 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.21 | 10.59 | +0.38 | ±10% / ±1.06 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 41.88 | 43.05 | +1.17 | ±10% / ±4.31 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 41.88 | 43.05 | +1.17 | ±10% / ±4.31 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.07 | 1.10 | +0.04 | ±10% / ±0.11 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 7.12 | 7.58 | +0.46 | ±10% / ±0.76 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 7.12 | 7.58 | +0.46 | ±10% / ±0.76 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.18 | 0.18 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.93 | 0.92 | -0.01 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.93 | 0.92 | -0.01 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.18 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.18 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.05 | 2.04 | -0.01 | ±10% / ±0.20 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 11.59 | 9.82 | -1.77 | ±10% / ±1.16 ms | 0.0% | single run | 🟢 Win (-15%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 11.59 | 9.82 | -1.77 | ±10% / ±1.16 ms | 0.0% | single run | 🟢 Win (-15%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.27 | 0.27 | -0.00 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.80 | 1.72 | -0.07 | ±10% / ±0.18 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.80 | 1.72 | -0.07 | ±10% / ±0.18 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.09 | 0.08 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.27 | 0.28 | +0.02 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.27 | 0.26 | -0.00 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.54 | 0.50 | -0.03 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.06 | 0.06 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.86 | 0.88 | +0.01 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.21 | 0.21 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.12 | 0.13 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.23 | 0.22 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.18 | 0.17 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.90 | 1.86 | -0.04 | ±10% / ±0.19 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.56 | 1.52 | -0.04 | ±10% / ±0.16 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.38 | 0.37 | -0.01 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 21.51 | 21.32 | -0.20 | ±10% / ±2.15 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 15.71 | 15.28 | -0.43 | ±10% / ±1.57 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.77 | 3.63 | -0.15 | ±10% / ±0.38 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 10 rows / resqlite select() | 0.08 | 0.09 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 10 rows / resqlite select() [main] | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 100 rows / resqlite select() | 0.07 | 0.06 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 1000 rows / resqlite select() | 0.44 | 0.38 | -0.06 | ±10% / ±0.04 ms | 0.0% | single run | 🟢 Win (-13%) |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.06 | 0.06 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 10000 rows / resqlite select() | 4.37 | 4.35 | -0.02 | ±10% / ±0.44 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.53 | 0.54 | +0.01 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Fan-out (10 streams) / resqlite | 0.20 | 0.23 | +0.03 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+16%) |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.20 | 0.23 | +0.03 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+16%) |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.56 | 0.62 | +0.07 | ±10% / ±0.06 ms | 0.0% | single run | 🔴 Regression (+12%) |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.56 | 0.62 | +0.07 | ±10% / ±0.06 ms | 0.0% | single run | 🔴 Regression (+12%) |
| Streaming / Initial Emission / resqlite stream() | 0.07 | 0.07 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Initial Emission / resqlite stream() [main] | 0.07 | 0.07 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 ... | 2.87 | 3.01 | +0.14 | ±10% / ±0.30 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 ... | 2.87 | 3.01 | +0.14 | ±10% / ±0.30 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged ... | 3.11 | 3.25 | +0.14 | ±10% / ±0.33 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged ... | 3.11 | 3.25 | +0.14 | ±10% / ±0.33 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 1.89 | 2.24 | +0.34 | ±10% / ±0.22 ms | 0.0% | single run | 🔴 Regression (+18%) |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 1.89 | 2.24 | +0.34 | ±10% / ±0.22 ms | 0.0% | single run | 🔴 Regression (+18%) |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.39 | 3.36 | -0.04 | ±10% / ±0.34 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.39 | 3.36 | -0.04 | ±10% / ±0.34 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.83 | 2.55 | -0.28 | ±10% / ±0.28 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.83 | 2.55 | -0.28 | ±10% / ±0.28 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 7.21 | 7.07 | -0.14 | ±10% / ±0.72 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 7.21 | 7.07 | -0.14 | ±10% / ±0.72 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.21 | 0.21 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.21 | 0.21 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.41 | 0.41 | +0.00 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.41 | 0.41 | +0.00 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.09 | 3.98 | -0.11 | ±10% / ±0.41 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.09 | 3.98 | -0.11 | ±10% / ±0.41 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.65 | 0.58 | -0.07 | ±10% / ±0.07 ms | 0.0% | single run | 🟢 Win (-11%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.65 | 0.58 | -0.07 | ±10% / ±0.07 ms | 0.0% | single run | 🟢 Win (-11%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.07 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.07 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 4.74 | 5.34 | +0.60 | ±10% / ±0.53 ms | 0.0% | single run | 🔴 Regression (+13%) |
| Write Performance / Batched Write Inside Transaction (100... | 4.74 | 5.34 | +0.60 | ±10% / ±0.53 ms | 0.0% | single run | 🔴 Regression (+13%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.41 | 0.42 | +0.00 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.41 | 0.42 | +0.00 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Concurrent Single Inserts (100 concur... | 1.03 | 1.04 | +0.01 | ±10% / ±0.10 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Concurrent Single Inserts (100 concur... | 1.03 | 1.04 | +0.01 | ±10% / ±0.10 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Nested Transactions (savepoints) / re... | 0.08 | 0.07 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Nested Transactions (savepoints) / re... | 0.08 | 0.07 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Nested Transactions (savepoints) / re... | 0.83 | 0.89 | +0.06 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Nested Transactions (savepoints) / re... | 0.83 | 0.89 | +0.06 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Single Inserts (100 sequential) / res... | 1.46 | 1.59 | +0.13 | ±10% / ±0.16 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Single Inserts (100 sequential) / res... | 1.46 | 1.59 | +0.13 | ±10% / ±0.16 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.19 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.19 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.11 | 0.10 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.11 | 0.10 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 13.87 | 13.32 | -0.55 | ±10% / ±1.39 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 13.87 | 13.32 | -0.55 | ±10% / ±1.39 ms | 0.0% | single run | ⚪ Neutral |

**Summary:** 6 wins, 12 regressions, 149 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 0.78 | 0.44 | -0.34 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 0.00 | 2.86 | +2.86 MB | ±6.48 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 3.55 | 0.00 | -3.55 MB | ±0.50 MB | 🟢 Win (-3.55 MB) |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 0.00 | +0.00 MB | ±4.02 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 4.66 | 3.02 | -1.64 MB | ±12.91 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±1.52 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 1.83 | 3.84 | +2.01 MB | ±3.42 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / resqlite select() | 2.31 | 0.00 | -2.31 MB | ±3.23 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite3 select() | 6.22 | 5.08 | -1.14 MB | ±3.79 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 0.98 | 1.00 | +0.02 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.06 | 0.06 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 1 wins, 0 regressions, 14 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 4348 | 4433 | +85 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 4067 | 4424 | +357 | ±100 | 🔴 More re-emits (+357) |

**Granularity summary:** 0 fewer-re-emit, 1 more-re-emit, 5 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


