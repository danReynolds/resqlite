# resqlite Benchmark Results

Generated: 2026-04-27T15:46:01.368413

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp110-fnv-8byte-long-text`
- Repeats: `1`
- Runtime: `dart-vm / Dart 3.11.0`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `codex/dogfood-experiment-110 @ d559b6c9bd4f (dirty)`
- Comparison baseline: `2026-04-27T15-42-56-baseline-for-exp110-long-text.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.086 | 0.099 | 0.022 | 0.025 |
| sqlite3 select() | 0.151 | 0.337 | 0.151 | 0.337 |
| sqlite_async select() | 0.208 | 0.360 | 0.022 | 0.029 |
| drift select() | 0.144 | 0.264 | 0.009 | 0.018 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.066 | 0.113 | 0.010 | 0.011 |
| sqlite3 select() | 0.211 | 0.320 | 0.211 | 0.320 |
| sqlite_async select() | 0.232 | 0.331 | 0.012 | 0.019 |
| drift select() | 0.315 | 0.459 | 0.012 | 0.018 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.429 | 0.518 | 0.075 | 0.085 |
| sqlite3 select() | 1.088 | 1.515 | 1.088 | 1.515 |
| sqlite_async select() | 1.105 | 1.426 | 0.080 | 0.101 |
| drift select() | 1.671 | 1.781 | 0.082 | 0.091 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 5.182 | 14.351 | 0.719 | 1.090 |
| sqlite3 select() | 15.082 | 24.566 | 15.082 | 24.566 |
| sqlite_async select() | 13.154 | 15.289 | 0.775 | 0.970 |
| drift select() | 21.417 | 28.904 | 0.776 | 1.581 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.097 | 0.168 | 0.076 | 0.091 |
| sqlite3 + jsonEncode | 0.052 | 0.080 | 0.052 | 0.080 |
| sqlite_async + jsonEncode | 0.118 | 0.241 | 0.031 | 0.054 |
| drift + jsonEncode | 0.107 | 0.220 | 0.027 | 0.043 |
| resqlite selectBytes() | 0.020 | 0.026 | 0.000 | 0.001 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.228 | 0.266 | 0.177 | 0.198 |
| sqlite3 + jsonEncode | 0.271 | 0.311 | 0.271 | 0.311 |
| sqlite_async + jsonEncode | 0.341 | 0.423 | 0.166 | 0.183 |
| drift + jsonEncode | 0.350 | 0.414 | 0.156 | 0.171 |
| resqlite selectBytes() | 0.055 | 0.057 | 0.000 | 0.001 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.949 | 4.223 | 1.559 | 2.550 |
| sqlite3 + jsonEncode | 2.666 | 5.499 | 2.666 | 5.499 |
| sqlite_async + jsonEncode | 2.722 | 4.709 | 1.558 | 2.648 |
| drift + jsonEncode | 3.264 | 6.105 | 1.594 | 2.882 |
| resqlite selectBytes() | 0.418 | 1.043 | 0.001 | 0.009 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 21.396 | 30.980 | 15.476 | 17.927 |
| sqlite3 + jsonEncode | 32.293 | 36.648 | 32.293 | 36.648 |
| sqlite_async + jsonEncode | 32.628 | 41.846 | 15.975 | 18.643 |
| drift + jsonEncode | 40.883 | 53.995 | 16.389 | 20.963 |
| resqlite selectBytes() | 4.110 | 6.105 | 0.004 | 0.008 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.118 | 0.320 | 0.026 | 0.199 |
| sqlite3 | 0.335 | 0.543 | 0.335 | 0.543 |
| sqlite_async | 0.493 | 0.992 | 0.050 | 0.065 |
| drift | 0.922 | 6.313 | 0.061 | 0.359 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.949 | 1.088 | 0.274 | 0.307 |
| sqlite3 | 3.243 | 3.821 | 3.243 | 3.821 |
| sqlite_async | 3.077 | 3.501 | 0.335 | 0.380 |
| drift | 5.115 | 7.843 | 0.355 | 0.400 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.608 | 0.674 | 0.106 | 0.121 |
| sqlite3 | 1.469 | 2.350 | 1.469 | 2.350 |
| sqlite_async | 1.655 | 1.795 | 0.135 | 0.152 |
| drift | 2.156 | 2.370 | 0.136 | 0.155 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.315 | 0.493 | 0.103 | 0.119 |
| sqlite3 | 1.018 | 1.263 | 1.018 | 1.263 |
| sqlite_async | 1.071 | 1.424 | 0.127 | 0.143 |
| drift | 1.572 | 1.870 | 0.126 | 0.159 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.313 | 0.373 | 0.100 | 0.110 |
| sqlite3 | 0.950 | 1.039 | 0.950 | 1.039 |
| sqlite_async | 0.970 | 1.184 | 0.118 | 0.128 |
| drift | 1.507 | 1.743 | 0.122 | 0.135 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.015 | 0.020 | 0.002 | 0.002 |
| sqlite3 | 0.020 | 0.022 | 0.020 | 0.022 |
| sqlite_async | 0.069 | 0.112 | 0.004 | 0.007 |
| drift | 0.105 | 0.144 | 0.009 | 0.011 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.034 | 0.036 | 0.005 | 0.005 |
| sqlite3 | 0.065 | 0.071 | 0.065 | 0.071 |
| sqlite_async | 0.118 | 0.172 | 0.008 | 0.012 |
| drift | 0.126 | 0.173 | 0.007 | 0.011 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.051 | 0.054 | 0.009 | 0.010 |
| sqlite3 | 0.117 | 0.120 | 0.117 | 0.120 |
| sqlite_async | 0.165 | 0.287 | 0.012 | 0.017 |
| drift | 0.215 | 0.320 | 0.013 | 0.023 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.203 | 0.285 | 0.044 | 0.047 |
| sqlite3 | 0.551 | 0.634 | 0.551 | 0.634 |
| sqlite_async | 0.583 | 0.892 | 0.052 | 0.058 |
| drift | 0.958 | 1.192 | 0.058 | 0.067 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.404 | 1.153 | 0.090 | 0.114 |
| sqlite3 | 1.138 | 1.933 | 1.138 | 1.933 |
| sqlite_async | 1.154 | 1.470 | 0.105 | 0.124 |
| drift | 1.792 | 2.332 | 0.110 | 0.121 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.849 | 1.749 | 0.176 | 0.206 |
| sqlite3 | 2.172 | 2.664 | 2.172 | 2.664 |
| sqlite_async | 2.295 | 2.884 | 0.200 | 0.221 |
| drift | 3.308 | 4.211 | 0.202 | 0.212 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.307 | 5.997 | 0.441 | 1.529 |
| sqlite3 | 5.656 | 7.811 | 5.656 | 7.811 |
| sqlite_async | 6.012 | 7.177 | 0.489 | 0.526 |
| drift | 9.189 | 9.736 | 0.487 | 0.526 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.842 | 10.633 | 0.896 | 1.631 |
| sqlite3 | 15.334 | 21.945 | 15.334 | 21.945 |
| sqlite_async | 13.310 | 18.250 | 0.971 | 1.549 |
| drift | 21.492 | 28.794 | 0.953 | 2.507 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 11.927 | 19.490 | 1.795 | 2.613 |
| sqlite3 | 32.827 | 42.772 | 32.827 | 42.772 |
| sqlite_async | 38.506 | 52.991 | 1.958 | 6.008 |
| drift | 51.835 | 68.786 | 1.950 | 7.226 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.042 | 0.048 | 0.042 | 0.048 |
| sqlite3 + jsonEncode | 0.038 | 0.040 | 0.038 | 0.040 |
| sqlite_async + jsonEncode | 0.100 | 0.274 | 0.100 | 0.274 |
| drift + jsonEncode | 0.078 | 0.153 | 0.078 | 0.153 |
| resqlite selectBytes() | 0.017 | 0.024 | 0.017 | 0.024 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.113 | 0.130 | 0.113 | 0.130 |
| sqlite3 + jsonEncode | 0.144 | 0.167 | 0.144 | 0.167 |
| sqlite_async + jsonEncode | 0.175 | 0.214 | 0.175 | 0.214 |
| drift + jsonEncode | 0.267 | 0.512 | 0.267 | 0.512 |
| resqlite selectBytes() | 0.030 | 0.033 | 0.030 | 0.033 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.225 | 0.385 | 0.225 | 0.385 |
| sqlite3 + jsonEncode | 0.274 | 0.310 | 0.274 | 0.310 |
| sqlite_async + jsonEncode | 0.320 | 0.641 | 0.320 | 0.641 |
| drift + jsonEncode | 0.395 | 0.470 | 0.395 | 0.470 |
| resqlite selectBytes() | 0.052 | 0.053 | 0.052 | 0.053 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.930 | 1.090 | 0.930 | 1.090 |
| sqlite3 + jsonEncode | 1.232 | 1.375 | 1.232 | 1.375 |
| sqlite_async + jsonEncode | 1.300 | 1.545 | 1.300 | 1.545 |
| drift + jsonEncode | 1.679 | 1.820 | 1.679 | 1.820 |
| resqlite selectBytes() | 0.198 | 0.223 | 0.198 | 0.223 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.965 | 3.310 | 1.965 | 3.310 |
| sqlite3 + jsonEncode | 2.586 | 5.189 | 2.586 | 5.189 |
| sqlite_async + jsonEncode | 2.688 | 3.553 | 2.688 | 3.553 |
| drift + jsonEncode | 3.154 | 5.507 | 3.154 | 5.507 |
| resqlite selectBytes() | 0.385 | 0.418 | 0.385 | 0.418 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.873 | 7.068 | 3.873 | 7.068 |
| sqlite3 + jsonEncode | 5.305 | 8.434 | 5.305 | 8.434 |
| sqlite_async + jsonEncode | 6.283 | 13.077 | 6.283 | 13.077 |
| drift + jsonEncode | 6.856 | 11.129 | 6.856 | 11.129 |
| resqlite selectBytes() | 0.848 | 1.872 | 0.848 | 1.872 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 11.233 | 15.913 | 11.233 | 15.913 |
| sqlite3 + jsonEncode | 15.915 | 19.024 | 15.915 | 19.024 |
| sqlite_async + jsonEncode | 14.772 | 18.719 | 14.772 | 18.719 |
| drift + jsonEncode | 19.698 | 26.024 | 19.698 | 26.024 |
| resqlite selectBytes() | 2.135 | 5.413 | 2.135 | 5.413 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 22.444 | 25.468 | 22.444 | 25.468 |
| sqlite3 + jsonEncode | 29.549 | 47.937 | 29.549 | 47.937 |
| sqlite_async + jsonEncode | 31.519 | 34.931 | 31.519 | 34.931 |
| drift + jsonEncode | 41.494 | 61.680 | 41.494 | 61.680 |
| resqlite selectBytes() | 4.014 | 5.877 | 4.014 | 5.877 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 47.182 | 78.077 | 47.182 | 78.077 |
| sqlite3 + jsonEncode | 65.460 | 84.610 | 65.460 | 84.610 |
| sqlite_async + jsonEncode | 72.628 | 134.239 | 72.628 | 134.239 |
| drift + jsonEncode | 88.330 | 111.999 | 88.330 | 111.999 |
| resqlite selectBytes() | 8.282 | 12.457 | 8.282 | 12.457 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.32 | 0.34 | 0.32 |
| sqlite_async | 0.97 | 1.14 | 0.97 |
| drift | 1.55 | 1.67 | 1.55 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.34 | 0.37 | 0.17 |
| sqlite_async | 1.39 | 1.64 | 0.70 |
| drift | 2.95 | 3.33 | 1.48 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.41 | 0.66 | 0.10 |
| sqlite_async | 2.30 | 3.12 | 0.58 |
| drift | 5.33 | 5.81 | 1.33 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.76 | 1.15 | 0.09 |
| sqlite_async | 5.30 | 8.13 | 0.66 |
| drift | 11.19 | 12.48 | 1.40 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 124232 |
| resqlite per query | 0.008 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 124232 | 99319..128165 | 11.6 | 16.0 |
| sqlite3 | 187520 | 183634..188158 | 1.2 | 1.8 |
| sqlite_async | 45640 | 43165..46295 | 3.4 | 5.2 |
| drift | 44358 | 42506..44957 | 2.8 | 5.6 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.850 | 16.314 | 14.850 | 16.314 |
| sqlite_async | 37.394 | 52.075 | 37.394 | 52.075 |
| drift | 54.239 | 67.432 | 54.239 | 67.432 |
| sqlite3 (no cache) | 23.961 | 25.444 | 23.961 | 25.444 |
| sqlite3 (cached stmt) | 23.483 | 24.126 | 23.483 | 24.126 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 2.125 | 3.084 | 2.125 | 3.084 |
| sqlite3 execute() | 1.583 | 3.009 | 1.583 | 3.009 |
| sqlite_async execute() | 5.200 | 11.617 | 5.200 | 11.617 |
| drift execute() | 3.329 | 4.804 | 3.329 | 4.804 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.051 | 0.060 | 0.051 | 0.060 |
| sqlite3 executeBatch() | 0.052 | 0.056 | 0.052 | 0.056 |
| sqlite_async executeBatch() | 0.099 | 0.119 | 0.099 | 0.119 |
| drift executeBatch() | 0.115 | 0.181 | 0.115 | 0.181 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.394 | 0.542 | 0.394 | 0.542 |
| sqlite3 executeBatch() | 0.456 | 0.658 | 0.456 | 0.658 |
| sqlite_async executeBatch() | 0.628 | 3.936 | 0.628 | 3.936 |
| drift executeBatch() | 0.849 | 1.215 | 0.849 | 1.215 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.508 | 5.801 | 4.508 | 5.801 |
| sqlite3 executeBatch() | 4.697 | 5.222 | 4.697 | 5.222 |
| sqlite_async executeBatch() | 5.613 | 6.080 | 5.613 | 6.080 |
| drift executeBatch() | 6.868 | 8.967 | 6.868 | 8.967 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.050 | 0.058 | 0.050 | 0.058 |
| sqlite_async writeTransaction() | 0.083 | 0.096 | 0.083 | 0.096 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.070 | 0.110 | 0.070 | 0.110 |
| resqlite tx.execute() loop | 0.830 | 0.998 | 0.830 | 0.998 |
| sqlite_async tx.execute() loop | 1.395 | 1.791 | 1.395 | 1.791 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.418 | 0.538 | 0.418 | 0.538 |
| resqlite tx.execute() loop | 5.846 | 6.691 | 5.846 | 6.691 |
| sqlite_async tx.execute() loop | 11.968 | 13.280 | 11.968 | 13.280 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.116 | 0.169 | 0.116 | 0.169 |
| sqlite_async tx.getAll() | 0.233 | 0.449 | 0.233 | 0.449 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.195 | 0.204 | 0.195 | 0.204 |
| sqlite_async tx.getAll() | 0.401 | 0.527 | 0.401 | 0.527 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.059 | 0.192 | 0.059 | 0.192 |
| sqlite_async watch() | 0.157 | 1.328 | 0.157 | 1.328 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.045 | 0.338 | 0.045 | 0.338 |
| sqlite_async | 0.071 | 0.268 | 0.071 | 0.268 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.401 | 0.829 | 0.401 | 0.829 |
| sqlite_async | 1.917 | 4.416 | 1.917 | 4.416 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.435 | 3.871 | 2.435 | 3.871 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.443 | 0.823 | 0.443 | 0.823 |
| sqlite_async | 0.550 | 2.046 | 0.550 | 2.046 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.632 | 2.632 | 2.632 | 2.632 |
| sqlite_async | 12.021 | 12.021 | 12.021 | 12.021 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.778 | 4.302 | 3.778 | 4.302 |
| sqlite_async | 6.658 | 8.145 | 6.658 | 8.145 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.507 | 0.735 | 0.507 | 0.735 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 6.851 | 8.442 | 6.851 | 8.442 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. On resqlite's main branch this ratio is driven toward 0 by experiment 075 (C-side result-hash short-circuit), not by writer-side column-tracking (exp 052 is not implemented). The two mechanisms are indistinguishable on this read-side benchmark.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 72.1 | 0.000 |
| sqlite_async | 3534 | 974.6 | 1.130 |
| drift | 5000 | 1144.6 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 72.9 | 0.000 |
| sqlite_async | 3128 | 951.0 | 1.130 |
| drift | 5000 | 1143.7 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 223.53 | 229.29 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 434.35 | 445.15 | 0.00 | 0.00 | 1127 | 3 |
| drift stream() | 553.38 | 563.85 | 0.01 | 0.02 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.032 | 0.075 | 0.000 | 0.000 |
| sqlite3 | 0.021 | 0.039 | 0.021 | 0.039 |
| sqlite_async | 0.044 | 0.068 | 0.000 | 0.000 |
| drift | 0.047 | 0.075 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.023 | 0.050 | 0.000 | 0.000 |
| sqlite3 | 0.014 | 0.021 | 0.014 | 0.021 |
| sqlite_async | 0.035 | 0.050 | 0.000 | 0.000 |
| drift | 0.038 | 0.061 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.030 | 0.053 | 0.000 | 0.000 |
| sqlite3 | 0.031 | 0.035 | 0.031 | 0.035 |
| sqlite_async | 0.060 | 0.077 | 0.000 | 0.000 |
| drift | 0.056 | 0.067 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.011 | 0.026 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.007 | 0.005 | 0.007 |
| sqlite_async | 0.023 | 0.031 | 0.000 | 0.000 |
| drift | 0.022 | 0.030 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.041 | 0.046 | 0.004 | 0.004 |
| sqlite3 | 0.072 | 0.086 | 0.072 | 0.086 |
| sqlite_async | 0.084 | 0.096 | 0.001 | 0.002 |
| drift | 0.111 | 0.139 | 0.001 | 0.002 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 107.566 | 113.694 | 0.000 | 0.000 | 0 |
| sqlite_async | 215.586 | 216.064 | 0.000 | 0.000 | 39 |
| drift | 224.741 | 230.609 | 0.000 | 0.003 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 248.11 | 248.11 | 0.00 | 0.00 | 12.32 | 236.37 | 0 |
| sqlite_async | 502.42 | 502.42 | 0.01 | 0.01 | 22.91 | 479.51 | 1180 |
| drift | 1795.75 | 1795.75 | 0.06 | 0.06 | 14.91 | 1780.83 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 3.59 | 13.25 | 0.00..10.22 | ±5.11 |
| sqlite3 select() | 2.88 | 10.55 | 0.00..8.72 | ±4.36 |
| sqlite_async select() | 1.00 | 1.50 | 0.97..1.50 | ±0.27 |
| drift select() | 14.84 | 74.42 | 0.00..51.97 | ±25.98 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 7.78 | 0.00..2.02 | ±1.01 |
| resqlite + jsonEncode | 0.00 | 31.23 | 0.00..23.58 | ±11.79 |
| sqlite3 + jsonEncode | 3.50 | 60.13 | 0.00..59.23 | ±29.62 |
| sqlite_async + jsonEncode | 0.00 | 35.75 | 0.00..23.20 | ±11.60 |
| drift + jsonEncode | 0.83 | 24.55 | 0.00..9.88 | ±4.94 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 1.22 | 2.64 | 0.00..2.06 | ±1.03 |
| sqlite3 executeBatch() | 0.00 | 0.02 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.02 | 6.72 | 0.00..0.53 | ±0.27 |
| drift batch() | 0.02 | 2.11 | 0.00..1.09 | ±0.55 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.13 | 0.22 | 0.00..0.13 | ±0.06 |
| sqlite_async watch() | 0.00 | 0.64 | 0.00..0.00 | ±0.00 |

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

Previous: `2026-04-27T15-42-56-baseline-for-exp110-long-text.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Insert message / resqlite | 0.03 | 0.03 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.32 | +0.02 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.32 | +0.02 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.34 | 0.34 | +0.00 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.17 | 0.17 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.44 | 0.41 | -0.03 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.11 | 0.10 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 1.42 | 0.76 | -0.66 | ±10% / ±0.14 ms | 0.0% | single run | 🟢 Win (-46%) |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.18 | 0.09 | -0.09 | ±10% / ±0.02 ms | 0.0% | single run | 🟢 Win (-50%) |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 108.40 | 107.57 | -0.83 | ±10% / ±10.84 ms | 0.0% | single run | ⚪ Neutral |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 241.23 | 248.11 | +6.88 | ±10% / ±24.81 ms | 0.0% | single run | ⚪ Neutral |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 221.72 | 223.53 | +1.81 | ±10% / ±22.35 ms | 0.0% | single run | ⚪ Neutral |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 15.30 | 14.85 | -0.45 | ±10% / ±1.53 ms | 0.0% | single run | ⚪ Neutral |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 15.30 | 14.85 | -0.45 | ±10% / ±1.53 ms | 0.0% | single run | ⚪ Neutral |
| Point Query Throughput / resqlite qps | 118654.00 | 124232.00 | +5578.00 | ±10% / ±12423.20 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.02 | 0.01 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.02 | 0.02 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.02 | 0.02 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.20 | 0.23 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.20 | 0.23 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.05 | 0.05 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.05 | 0.05 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.40 | 0.40 | +0.00 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.91 | 1.97 | +0.05 | ±10% / ±0.20 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.91 | 1.97 | +0.05 | ±10% / ±0.20 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.37 | 0.39 | +0.01 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.37 | 0.39 | +0.01 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.79 | 4.84 | +0.05 | ±10% / ±0.48 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 23.77 | 22.44 | -1.32 | ±10% / ±2.38 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 23.77 | 22.44 | -1.32 | ±10% / ±2.38 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.89 | 0.90 | +0.01 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.90 | 4.01 | +0.12 | ±10% / ±0.40 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.90 | 4.01 | +0.12 | ±10% / ±0.40 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.98 | 0.85 | -0.13 | ±10% / ±0.10 ms | 0.0% | single run | 🟢 Win (-13%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 4.25 | 3.87 | -0.37 | ±10% / ±0.42 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 4.25 | 3.87 | -0.37 | ±10% / ±0.42 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.18 | 0.18 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.87 | 0.85 | -0.02 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.87 | 0.85 | -0.02 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 14.23 | 11.93 | -2.31 | ±10% / ±1.42 ms | 0.0% | single run | 🟢 Win (-16%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 45.38 | 47.18 | +1.80 | ±10% / ±4.72 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 45.38 | 47.18 | +1.80 | ±10% / ±4.72 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.80 | 1.79 | -0.01 | ±10% / ±0.18 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 7.79 | 8.28 | +0.49 | ±10% / ±0.83 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 7.79 | 8.28 | +0.49 | ±10% / ±0.83 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.04 | 0.03 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.29 | 0.20 | -0.09 | ±10% / ±0.03 ms | 0.0% | single run | 🟢 Win (-30%) |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.95 | 0.93 | -0.02 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.95 | 0.93 | -0.02 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.05 | 0.04 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.19 | 0.20 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.19 | 0.20 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.44 | 2.31 | -0.13 | ±10% / ±0.24 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 12.08 | 11.23 | -0.85 | ±10% / ±1.21 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 12.08 | 11.23 | -0.85 | ±10% / ±1.21 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.45 | 0.44 | -0.01 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 2.05 | 2.13 | +0.08 | ±10% / ±0.21 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 2.05 | 2.13 | +0.08 | ±10% / ±0.21 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.14 | 0.12 | -0.02 | ±10% / ±0.02 ms | 0.0% | single run | 🟢 Win (-14%) |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.03 | 0.03 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.31 | 0.31 | +0.01 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.30 | 0.32 | +0.01 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.58 | 0.61 | +0.03 | ±10% / ±0.06 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.10 | 0.11 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.99 | 0.95 | -0.04 | ±10% / ±0.10 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.30 | 0.27 | -0.03 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.06 | 0.10 | +0.03 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+54%) |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.04 | 0.08 | +0.03 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+85%) |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.03 | 0.02 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.24 | 0.23 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.19 | 0.18 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.06 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.98 | 1.95 | -0.03 | ±10% / ±0.20 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.57 | 1.56 | -0.01 | ±10% / ±0.16 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.39 | 0.42 | +0.03 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 23.36 | 21.40 | -1.96 | ±10% / ±2.34 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 16.22 | 15.48 | -0.74 | ±10% / ±1.62 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.93 | 4.11 | +0.18 | ±10% / ±0.41 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.01 | 0.00 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 10 rows / resqlite select() | 0.09 | 0.09 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 10 rows / resqlite select() [main] | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 100 rows / resqlite select() | 0.07 | 0.07 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 1000 rows / resqlite select() | 0.46 | 0.43 | -0.03 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.08 | 0.07 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 10000 rows / resqlite select() | 4.59 | 5.18 | +0.60 | ±10% / ±0.52 ms | 0.0% | single run | 🔴 Regression (+13%) |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.69 | 0.72 | +0.03 | ±10% / ±0.07 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Fan-out (10 streams) / resqlite | 0.26 | 0.44 | +0.18 | ±10% / ±0.04 ms | 0.0% | single run | 🔴 Regression (+69%) |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.26 | 0.44 | +0.18 | ±10% / ±0.04 ms | 0.0% | single run | 🔴 Regression (+69%) |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.53 | 0.51 | -0.02 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.53 | 0.51 | -0.02 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Initial Emission / resqlite stream() | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Initial Emission / resqlite stream() [main] | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Invalidation Latency / resqlite | 0.07 | 0.04 | -0.02 | ±10% / ±0.02 ms | 0.0% | single run | 🟢 Win (-32%) |
| Streaming / Invalidation Latency / resqlite [main] | 0.07 | 0.04 | -0.02 | ±10% / ±0.02 ms | 0.0% | single run | 🟢 Win (-32%) |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 10.33 | 2.44 | -7.89 | ±10% / ±1.03 ms | 0.0% | single run | 🟢 Win (-76%) |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 10.33 | 2.44 | -7.89 | ±10% / ±1.03 ms | 0.0% | single run | 🟢 Win (-76%) |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 5.49 | 3.78 | -1.71 | ±10% / ±0.55 ms | 0.0% | single run | 🟢 Win (-31%) |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 5.49 | 3.78 | -1.71 | ±10% / ±0.55 ms | 0.0% | single run | 🟢 Win (-31%) |
| Streaming / Stream Churn (100 cycles) / resqlite | 3.07 | 2.63 | -0.44 | ±10% / ±0.31 ms | 0.0% | single run | 🟢 Win (-14%) |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 3.07 | 2.63 | -0.44 | ±10% / ±0.31 ms | 0.0% | single run | 🟢 Win (-14%) |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 7.97 | 6.85 | -1.12 | ±10% / ±0.80 ms | 0.0% | single run | 🟢 Win (-14%) |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 7.97 | 6.85 | -1.12 | ±10% / ±0.80 ms | 0.0% | single run | 🟢 Win (-14%) |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.34 | 0.40 | +0.06 | ±10% / ±0.04 ms | 0.0% | single run | 🔴 Regression (+18%) |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.34 | 0.40 | +0.06 | ±10% / ±0.04 ms | 0.0% | single run | 🔴 Regression (+18%) |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.14 | 0.05 | -0.09 | ±10% / ±0.02 ms | 0.0% | single run | 🟢 Win (-65%) |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.14 | 0.05 | -0.09 | ±10% / ±0.02 ms | 0.0% | single run | 🟢 Win (-65%) |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.42 | 0.39 | -0.03 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.42 | 0.39 | -0.03 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.58 | 4.51 | -0.07 | ±10% / ±0.46 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.58 | 4.51 | -0.07 | ±10% / ±0.46 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.64 | 0.83 | +0.19 | ±10% / ±0.08 ms | 0.0% | single run | 🔴 Regression (+30%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.64 | 0.83 | +0.19 | ±10% / ±0.08 ms | 0.0% | single run | 🔴 Regression (+30%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.07 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.07 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 7.56 | 5.85 | -1.72 | ±10% / ±0.76 ms | 0.0% | single run | 🟢 Win (-23%) |
| Write Performance / Batched Write Inside Transaction (100... | 7.56 | 5.85 | -1.72 | ±10% / ±0.76 ms | 0.0% | single run | 🟢 Win (-23%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.46 | 0.42 | -0.04 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.46 | 0.42 | -0.04 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.05 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.05 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Single Inserts (100 sequential) / res... | 1.91 | 2.13 | +0.21 | ±10% / ±0.21 ms | 0.0% | single run | 🔴 Regression (+11%) |
| Write Performance / Single Inserts (100 sequential) / res... | 1.91 | 2.13 | +0.21 | ±10% / ±0.21 ms | 0.0% | single run | 🔴 Regression (+11%) |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.20 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.20 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.13 | 0.12 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.13 | 0.12 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |

**Summary:** 20 wins, 11 regressions, 124 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.00 | 0.02 | +0.02 MB | ±0.55 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 1.56 | 1.22 | -0.34 MB | ±1.03 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.02 | +0.02 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 2.47 | 0.83 | -1.64 MB | ±4.94 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 0.00 | 0.00 | +0.00 MB | ±11.79 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 0.00 | +0.00 MB | ±1.01 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 0.00 | 3.50 | +3.50 MB | ±29.62 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±11.60 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 9.58 | 14.84 | +5.26 MB | ±25.98 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / resqlite select() | 7.63 | 3.59 | -4.04 MB | ±5.11 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite3 select() | 4.91 | 2.88 | -2.03 MB | ±4.36 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 1.00 | 1.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.06 | 0.13 | +0.07 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 0 wins, 0 regressions, 15 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 3623 | 3534 | -89 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 3530 | 3128 | -402 | ±100 | 🔴 Invalidation elided (-402) — writes not firing |

**Granularity summary:** 0 fewer-re-emit, 1 more-re-emit, 5 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


