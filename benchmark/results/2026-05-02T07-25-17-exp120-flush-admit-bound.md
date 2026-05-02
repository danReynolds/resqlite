# resqlite Benchmark Results

Generated: 2026-05-02T07:25:17.039308

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp120-flush-admit-bound`
- Repeats: `3`
- Runtime: `dart-vm / Dart 3.11.0`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `exp-120-flush-admit-bound @ 113e6cf6385d (dirty)`
- Comparison baseline: `2026-05-02T07-18-52-baseline-for-exp120.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.012 | 0.014 | 0.001 | 0.001 |
| sqlite3 select() | 0.014 | 0.016 | 0.014 | 0.016 |
| sqlite_async select() | 0.030 | 0.032 | 0.001 | 0.001 |
| drift select() | 0.037 | 0.039 | 0.001 | 0.001 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.046 | 0.048 | 0.009 | 0.009 |
| sqlite3 select() | 0.106 | 0.115 | 0.106 | 0.115 |
| sqlite_async select() | 0.118 | 0.123 | 0.009 | 0.010 |
| drift select() | 0.178 | 0.182 | 0.010 | 0.010 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.379 | 0.388 | 0.090 | 0.093 |
| sqlite3 select() | 1.008 | 1.022 | 1.008 | 1.022 |
| sqlite_async select() | 0.980 | 1.017 | 0.088 | 0.093 |
| drift select() | 1.472 | 1.727 | 0.088 | 0.090 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.392 | 10.704 | 0.912 | 0.955 |
| sqlite3 select() | 12.608 | 15.139 | 12.608 | 15.139 |
| sqlite_async select() | 11.405 | 14.102 | 0.894 | 2.164 |
| drift select() | 19.247 | 25.789 | 0.907 | 1.188 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.027 | 0.030 | 0.016 | 0.016 |
| sqlite3 + jsonEncode | 0.029 | 0.030 | 0.029 | 0.030 |
| sqlite_async + jsonEncode | 0.044 | 0.047 | 0.016 | 0.016 |
| drift + jsonEncode | 0.052 | 0.056 | 0.016 | 0.017 |
| resqlite selectBytes() | 0.011 | 0.011 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.192 | 0.227 | 0.152 | 0.172 |
| sqlite3 + jsonEncode | 0.247 | 0.251 | 0.247 | 0.251 |
| sqlite_async + jsonEncode | 0.258 | 0.286 | 0.148 | 0.152 |
| drift + jsonEncode | 0.352 | 0.366 | 0.174 | 0.186 |
| resqlite selectBytes() | 0.047 | 0.065 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.716 | 1.769 | 1.428 | 1.469 |
| sqlite3 + jsonEncode | 2.368 | 2.639 | 2.368 | 2.639 |
| sqlite_async + jsonEncode | 2.319 | 2.581 | 1.436 | 1.464 |
| drift + jsonEncode | 2.878 | 5.595 | 1.443 | 2.781 |
| resqlite selectBytes() | 0.355 | 0.363 | 0.000 | 0.000 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.154 | 25.531 | 14.710 | 16.748 |
| sqlite3 + jsonEncode | 31.586 | 36.048 | 31.586 | 36.048 |
| sqlite_async + jsonEncode | 26.935 | 32.163 | 14.750 | 15.568 |
| drift + jsonEncode | 37.983 | 40.671 | 15.245 | 20.646 |
| resqlite selectBytes() | 3.598 | 4.469 | 0.000 | 0.003 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.098 | 0.100 | 0.034 | 0.035 |
| sqlite3 | 0.305 | 0.318 | 0.305 | 0.318 |
| sqlite_async | 0.347 | 0.360 | 0.040 | 0.042 |
| drift | 0.555 | 0.566 | 0.040 | 0.041 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.896 | 0.911 | 0.266 | 0.272 |
| sqlite3 | 3.030 | 3.521 | 3.030 | 3.521 |
| sqlite_async | 2.725 | 3.161 | 0.312 | 0.322 |
| drift | 4.409 | 5.834 | 0.313 | 0.320 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.532 | 1.122 | 0.102 | 0.112 |
| sqlite3 | 1.346 | 1.362 | 1.346 | 1.362 |
| sqlite_async | 1.288 | 1.354 | 0.112 | 0.114 |
| drift | 1.835 | 2.095 | 0.110 | 0.113 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.289 | 0.295 | 0.096 | 0.101 |
| sqlite3 | 0.925 | 0.942 | 0.925 | 0.942 |
| sqlite_async | 0.881 | 0.891 | 0.111 | 0.113 |
| drift | 1.382 | 1.404 | 0.109 | 0.116 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.295 | 0.299 | 0.099 | 0.100 |
| sqlite3 | 0.883 | 0.926 | 0.883 | 0.926 |
| sqlite_async | 0.881 | 0.926 | 0.111 | 0.116 |
| drift | 1.370 | 1.429 | 0.109 | 0.111 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.012 | 0.015 | 0.001 | 0.001 |
| sqlite3 | 0.015 | 0.015 | 0.015 | 0.015 |
| sqlite_async | 0.030 | 0.036 | 0.001 | 0.001 |
| drift | 0.036 | 0.037 | 0.001 | 0.001 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.027 | 0.030 | 0.004 | 0.004 |
| sqlite3 | 0.056 | 0.058 | 0.056 | 0.058 |
| sqlite_async | 0.069 | 0.071 | 0.005 | 0.005 |
| drift | 0.098 | 0.100 | 0.005 | 0.005 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.045 | 0.049 | 0.008 | 0.009 |
| sqlite3 | 0.107 | 0.110 | 0.107 | 0.110 |
| sqlite_async | 0.119 | 0.126 | 0.010 | 0.010 |
| drift | 0.173 | 0.178 | 0.009 | 0.010 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.191 | 0.196 | 0.042 | 0.044 |
| sqlite3 | 0.510 | 0.514 | 0.510 | 0.514 |
| sqlite_async | 0.491 | 0.494 | 0.044 | 0.045 |
| drift | 0.789 | 0.800 | 0.047 | 0.048 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.370 | 0.384 | 0.084 | 0.086 |
| sqlite3 | 1.083 | 1.163 | 1.083 | 1.163 |
| sqlite_async | 1.021 | 1.066 | 0.094 | 0.097 |
| drift | 1.560 | 1.659 | 0.093 | 0.099 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.787 | 0.826 | 0.171 | 0.175 |
| sqlite3 | 2.089 | 2.533 | 2.089 | 2.533 |
| sqlite_async | 1.932 | 2.278 | 0.178 | 0.185 |
| drift | 2.942 | 4.478 | 0.175 | 0.200 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.055 | 4.955 | 0.414 | 0.635 |
| sqlite3 | 5.078 | 6.492 | 5.078 | 6.492 |
| sqlite_async | 4.942 | 6.817 | 0.444 | 0.466 |
| drift | 7.993 | 8.200 | 0.439 | 0.448 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.472 | 10.315 | 0.833 | 1.171 |
| sqlite3 | 13.148 | 15.446 | 13.148 | 15.446 |
| sqlite_async | 11.573 | 13.817 | 0.904 | 1.162 |
| drift | 19.903 | 25.496 | 0.888 | 1.578 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 10.787 | 17.089 | 1.655 | 2.390 |
| sqlite3 | 29.618 | 33.980 | 29.618 | 33.980 |
| sqlite_async | 32.784 | 40.137 | 1.807 | 6.979 |
| drift | 43.437 | 57.521 | 1.778 | 7.857 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.029 | 0.034 | 0.029 | 0.034 |
| sqlite3 + jsonEncode | 0.031 | 0.035 | 0.031 | 0.035 |
| sqlite_async + jsonEncode | 0.049 | 0.053 | 0.049 | 0.053 |
| drift + jsonEncode | 0.055 | 0.082 | 0.055 | 0.082 |
| resqlite selectBytes() | 0.011 | 0.013 | 0.011 | 0.013 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.099 | 0.102 | 0.099 | 0.102 |
| sqlite3 + jsonEncode | 0.125 | 0.130 | 0.125 | 0.130 |
| sqlite_async + jsonEncode | 0.143 | 0.147 | 0.143 | 0.147 |
| drift + jsonEncode | 0.175 | 0.188 | 0.175 | 0.188 |
| resqlite selectBytes() | 0.024 | 0.028 | 0.024 | 0.028 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.190 | 0.193 | 0.190 | 0.193 |
| sqlite3 + jsonEncode | 0.246 | 0.249 | 0.246 | 0.249 |
| sqlite_async + jsonEncode | 0.256 | 0.260 | 0.256 | 0.260 |
| drift + jsonEncode | 0.310 | 0.317 | 0.310 | 0.317 |
| resqlite selectBytes() | 0.044 | 0.047 | 0.044 | 0.047 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.889 | 1.490 | 0.889 | 1.490 |
| sqlite3 + jsonEncode | 1.199 | 2.581 | 1.199 | 2.581 |
| sqlite_async + jsonEncode | 1.181 | 1.462 | 1.181 | 1.462 |
| drift + jsonEncode | 1.434 | 2.243 | 1.434 | 2.243 |
| resqlite selectBytes() | 0.177 | 0.184 | 0.177 | 0.184 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.728 | 3.289 | 1.728 | 3.289 |
| sqlite3 + jsonEncode | 2.392 | 2.810 | 2.392 | 2.810 |
| sqlite_async + jsonEncode | 2.343 | 4.896 | 2.343 | 4.896 |
| drift + jsonEncode | 2.832 | 3.567 | 2.832 | 3.567 |
| resqlite selectBytes() | 0.354 | 0.366 | 0.354 | 0.366 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.751 | 6.589 | 3.751 | 6.589 |
| sqlite3 + jsonEncode | 5.011 | 8.460 | 5.011 | 8.460 |
| sqlite_async + jsonEncode | 4.867 | 8.536 | 4.867 | 8.536 |
| drift + jsonEncode | 6.044 | 10.106 | 6.044 | 10.106 |
| resqlite selectBytes() | 0.751 | 1.229 | 0.751 | 1.229 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 9.574 | 13.586 | 9.574 | 13.586 |
| sqlite3 + jsonEncode | 12.878 | 18.067 | 12.878 | 18.067 |
| sqlite_async + jsonEncode | 13.488 | 19.359 | 13.488 | 19.359 |
| drift + jsonEncode | 16.200 | 20.689 | 16.200 | 20.689 |
| resqlite selectBytes() | 1.836 | 3.629 | 1.836 | 3.629 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 22.504 | 23.243 | 22.504 | 23.243 |
| sqlite3 + jsonEncode | 27.177 | 31.245 | 27.177 | 31.245 |
| sqlite_async + jsonEncode | 28.871 | 31.457 | 28.871 | 31.457 |
| drift + jsonEncode | 37.246 | 39.705 | 37.246 | 39.705 |
| resqlite selectBytes() | 3.586 | 3.777 | 3.586 | 3.777 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 42.495 | 45.324 | 42.495 | 45.324 |
| sqlite3 + jsonEncode | 59.655 | 64.244 | 59.655 | 64.244 |
| sqlite_async + jsonEncode | 64.525 | 72.397 | 64.525 | 72.397 |
| drift + jsonEncode | 79.425 | 96.604 | 79.425 | 96.604 |
| resqlite selectBytes() | 7.304 | 10.749 | 7.304 | 10.749 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.32 | 0.34 | 0.32 |
| sqlite_async | 0.87 | 0.89 | 0.87 |
| drift | 1.38 | 1.48 | 1.38 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.31 | 0.15 |
| sqlite_async | 1.25 | 1.49 | 0.63 |
| drift | 2.51 | 2.81 | 1.25 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.37 | 0.64 | 0.09 |
| sqlite_async | 2.04 | 2.54 | 0.51 |
| drift | 4.78 | 5.18 | 1.20 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.71 | 1.13 | 0.09 |
| sqlite_async | 4.48 | 4.83 | 0.56 |
| drift | 9.62 | 10.18 | 1.20 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 156873 |
| resqlite per query | 0.006 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 156873 | 155744..157018 | 0.4 | 0.7 |
| sqlite3 | 201264 | 200392..201700 | 0.3 | 0.9 |
| sqlite_async | 50765 | 46445..51092 | 4.6 | 7.7 |
| drift | 47599 | 47474..47749 | 0.3 | 1.1 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 13.862 | 14.061 | 13.862 | 14.061 |
| sqlite_async | 33.796 | 34.068 | 33.796 | 34.068 |
| drift | 49.803 | 52.887 | 49.803 | 52.887 |
| sqlite3 (no cache) | 22.410 | 22.521 | 22.410 | 22.521 |
| sqlite3 (cached stmt) | 22.104 | 22.253 | 22.104 | 22.253 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.590 | 1.998 | 1.590 | 1.998 |
| sqlite3 execute() | 0.866 | 1.501 | 0.866 | 1.501 |
| sqlite_async execute() | 2.621 | 3.354 | 2.621 | 3.354 |
| drift execute() | 2.615 | 3.288 | 2.615 | 3.288 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.050 | 0.053 | 0.050 | 0.053 |
| sqlite3 executeBatch() | 0.046 | 0.047 | 0.046 | 0.047 |
| sqlite_async executeBatch() | 0.090 | 0.096 | 0.090 | 0.096 |
| drift executeBatch() | 0.111 | 0.115 | 0.111 | 0.115 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.393 | 0.404 | 0.393 | 0.404 |
| sqlite3 executeBatch() | 0.427 | 0.432 | 0.427 | 0.432 |
| sqlite_async executeBatch() | 0.496 | 0.502 | 0.496 | 0.502 |
| drift executeBatch() | 0.633 | 0.657 | 0.633 | 0.657 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 3.626 | 4.189 | 3.626 | 4.189 |
| sqlite3 executeBatch() | 3.920 | 4.077 | 3.920 | 4.077 |
| sqlite_async executeBatch() | 4.530 | 5.068 | 4.530 | 5.068 |
| drift executeBatch() | 5.810 | 6.734 | 5.810 | 6.734 |

### Wide Batch Insert (10000 rows x 20 params)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 16.930 | 23.550 | 16.930 | 23.550 |
| sqlite3 executeBatch() | 18.677 | 20.892 | 18.677 | 20.892 |
| sqlite_async executeBatch() | 22.499 | 24.958 | 22.499 | 24.958 |
| drift executeBatch() | 24.765 | 27.449 | 24.765 | 27.449 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.051 | 0.055 | 0.051 | 0.055 |
| sqlite_async writeTransaction() | 0.081 | 0.092 | 0.081 | 0.092 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.066 | 0.076 | 0.066 | 0.076 |
| resqlite tx.execute() loop | 0.513 | 0.767 | 0.513 | 0.767 |
| sqlite_async tx.execute() loop | 0.975 | 1.103 | 0.975 | 1.103 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.394 | 0.401 | 0.394 | 0.401 |
| resqlite tx.execute() loop | 4.979 | 5.751 | 4.979 | 5.751 |
| sqlite_async tx.execute() loop | 9.539 | 10.002 | 9.539 | 10.002 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.103 | 0.106 | 0.103 | 0.106 |
| sqlite_async tx.getAll() | 0.199 | 0.209 | 0.199 | 0.209 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.181 | 0.185 | 0.181 | 0.185 |
| sqlite_async tx.getAll() | 0.350 | 0.403 | 0.350 | 0.403 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 0.798 | 1.055 | 0.798 | 1.055 |
| resqlite nested transaction() depth=5 | 0.077 | 0.085 | 0.077 | 0.085 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.030 | 0.036 | 0.030 | 0.036 |
| sqlite_async watch() | 0.106 | 0.165 | 0.106 | 0.165 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.040 | 0.051 | 0.040 | 0.051 |
| sqlite_async | 0.072 | 0.084 | 0.072 | 0.084 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.181 | 0.260 | 0.181 | 0.260 |
| sqlite_async | 0.596 | 2.014 | 0.596 | 2.014 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.627 | 2.560 | 1.627 | 2.560 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.168 | 0.214 | 0.168 | 0.214 |
| sqlite_async | 0.236 | 0.309 | 0.236 | 0.309 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.570 | 1.570 | 1.570 | 1.570 |
| sqlite_async | 9.867 | 9.867 | 9.867 | 9.867 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.374 | 4.025 | 3.374 | 4.025 |
| sqlite_async | 5.274 | 6.128 | 5.274 | 6.128 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.516 | 0.698 | 0.516 | 0.698 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 5.305 | 5.683 | 5.305 | 5.683 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. For resqlite, this emission metric can reflect writer-side column-level invalidation, experiment 075's native result-hash short-circuit, or both. Use A11c (Many-Streams Writer Throughput) when the question is specifically writer-side dispatch elision.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 68.7 | 0.000 |
| sqlite_async | 3951 | 931.8 | 0.960 |
| drift | 5000 | 965.4 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 69.3 | 0.000 |
| sqlite_async | 4114 | 943.3 | 0.960 |
| drift | 5000 | 978.4 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 220.75 | 230.65 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 443.07 | 443.43 | 0.00 | 0.00 | 1104 | 3 |
| drift stream() | 541.07 | 545.47 | 0.00 | 0.02 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.020 | 0.033 | 0.000 | 0.000 |
| sqlite3 | 0.017 | 0.020 | 0.017 | 0.020 |
| sqlite_async | 0.037 | 0.056 | 0.000 | 0.000 |
| drift | 0.035 | 0.042 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.015 | 0.023 | 0.000 | 0.000 |
| sqlite3 | 0.011 | 0.013 | 0.011 | 0.013 |
| sqlite_async | 0.030 | 0.042 | 0.000 | 0.000 |
| drift | 0.028 | 0.033 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.025 | 0.036 | 0.000 | 0.000 |
| sqlite3 | 0.029 | 0.030 | 0.029 | 0.030 |
| sqlite_async | 0.056 | 0.067 | 0.000 | 0.000 |
| drift | 0.051 | 0.055 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.008 | 0.015 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.021 | 0.026 | 0.000 | 0.000 |
| drift | 0.019 | 0.023 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.038 | 0.041 | 0.001 | 0.001 |
| sqlite3 | 0.060 | 0.061 | 0.060 | 0.061 |
| sqlite_async | 0.075 | 0.078 | 0.001 | 0.001 |
| drift | 0.088 | 0.092 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 111.488 | 111.759 | 0.000 | 0.000 | 0 |
| sqlite_async | 220.408 | 221.386 | 0.001 | 0.001 | 41 |
| drift | 231.847 | 232.580 | 0.002 | 0.003 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 241.96 | 241.96 | 0.00 | 0.00 | 14.23 | 229.02 | 0 |
| sqlite_async | 482.95 | 482.95 | 0.01 | 0.01 | 24.98 | 458.66 | 1184 |
| drift | 1643.35 | 1643.35 | 0.04 | 0.04 | 15.93 | 1628.64 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 1.97 | 6.84 | 0.00..5.00 | ±2.50 |
| sqlite3 select() | 5.30 | 9.66 | 0.00..9.14 | ±4.57 |
| sqlite_async select() | 1.00 | 1.00 | 1.00..1.00 | ±0.00 |
| drift select() | 6.34 | 73.95 | 0.00..11.89 | ±5.95 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 20.00 | 0.00..0.00 | ±0.00 |
| resqlite + jsonEncode | 1.27 | 52.69 | 0.00..12.75 | ±6.38 |
| sqlite3 + jsonEncode | 0.00 | 8.58 | 0.00..0.83 | ±0.41 |
| sqlite_async + jsonEncode | 0.00 | 7.06 | 0.00..0.00 | ±0.00 |
| drift + jsonEncode | 0.00 | 66.22 | 0.00..15.36 | ±7.68 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.44 | 0.53 | 0.00..0.52 | ±0.26 |
| sqlite3 executeBatch() | 0.00 | 0.02 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 0.03 | 0.00..0.00 | ±0.00 |
| drift batch() | 0.50 | 4.52 | 0.00..2.52 | ±1.26 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.00 | 0.06 | 0.00..0.06 | ±0.03 |
| sqlite_async watch() | 0.00 | 0.03 | 0.00..0.02 | ±0.01 |

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
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.02 | 0.02..0.03 | 8.7% | 8.7% | 0.0% | stable |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02..0.02 | 10.5% | 10.5% | 5.3% | moderate |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.01..0.01 | 6.7% | 6.7% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.32 | 0.29..0.32 | 9.4% | 9.4% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.32 | 0.29..0.32 | 9.4% | 9.4% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.30 | 0.30..0.31 | 3.3% | 3.3% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.15 | 0.15..0.15 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.36 | 0.35..0.37 | 5.6% | 5.6% | 2.8% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.09 | 0.09..0.09 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.71 | 0.69..0.75 | 8.5% | 8.5% | 2.8% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.09 | 0.09..0.09 | 0.0% | 0.0% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.04 | 5.1% | 5.1% | 2.6% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 300.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 112.06 | 111.49..112.08 | 0.5% | 0.5% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 241.96 | 241.96..242.70 | 0.3% | 0.3% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 220.75 | 220.26..229.62 | 4.2% | 4.2% | 0.2% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 13.86 | 13.84..14.27 | 3.1% | 3.1% | 0.2% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 13.86 | 13.84..14.27 | 3.1% | 3.1% | 0.2% | stable |
| Point Query Throughput / resqlite qps | 159253.00 | 156873.00..161917.00 | 3.2% | 3.2% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.02 | 41.7% | 41.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.04 | 20.0% | 20.0% | 3.3% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.04 | 20.0% | 20.0% | 3.3% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 100.0% | 100.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.01 | 33.3% | 33.3% | 8.3% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.01 | 33.3% | 33.3% | 8.3% | noisy |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.04..0.05 | 6.7% | 6.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.19 | 0.19..0.20 | 4.2% | 4.2% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.19 | 0.19..0.20 | 4.2% | 4.2% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 12.5% | 12.5% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.05 | 11.4% | 11.4% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.04 | 0.04..0.05 | 11.4% | 11.4% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.38 | 0.37..0.38 | 2.4% | 2.4% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.73 | 1.72..1.73 | 0.2% | 0.2% | 0.1% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.73 | 1.72..1.73 | 0.2% | 0.2% | 0.1% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.08 | 0.08..0.09 | 1.2% | 1.2% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.35 | 0.35..0.36 | 1.1% | 1.1% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.35 | 0.35..0.36 | 1.1% | 1.1% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.39 | 4.30..4.47 | 3.9% | 3.9% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 20.36 | 20.19..22.50 | 11.3% | 11.3% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 20.36 | 20.19..22.50 | 11.3% | 11.3% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.83 | 0.83..0.84 | 0.7% | 0.7% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 3.59 | 3.58..3.74 | 4.4% | 4.4% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 3.59 | 3.58..3.74 | 4.4% | 4.4% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.78 | 0.78..0.79 | 1.3% | 1.3% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.65 | 3.64..3.75 | 3.1% | 3.1% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.65 | 3.64..3.75 | 3.1% | 3.1% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.17 | 0.17..0.17 | 1.8% | 1.8% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.76 | 0.75..0.77 | 1.8% | 1.8% | 0.1% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.76 | 0.75..0.77 | 1.8% | 1.8% | 0.1% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.68 | 10.59..10.79 | 1.9% | 1.9% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 42.07 | 41.91..42.49 | 1.4% | 1.4% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 42.07 | 41.91..42.49 | 1.4% | 1.4% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.66 | 1.65..1.66 | 0.5% | 0.5% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 7.37 | 7.30..7.86 | 7.5% | 7.5% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 7.37 | 7.30..7.86 | 7.5% | 7.5% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03..0.03 | 11.1% | 11.1% | 3.7% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10..0.11 | 10.7% | 10.7% | 3.9% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.10 | 0.10..0.11 | 10.7% | 10.7% | 3.9% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.02..0.03 | 29.6% | 29.6% | 11.1% | noisy |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.02..0.03 | 29.6% | 29.6% | 11.1% | noisy |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.19 | 0.19..0.20 | 2.6% | 2.6% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.89 | 0.89..0.89 | 0.2% | 0.2% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.89 | 0.89..0.89 | 0.2% | 0.2% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04..0.04 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.18 | 0.18..0.18 | 2.8% | 2.8% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.18 | 0.18..0.18 | 2.8% | 2.8% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.06 | 2.06..2.10 | 2.3% | 2.3% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 9.59 | 9.57..9.62 | 0.5% | 0.5% | 0.1% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 9.59 | 9.57..9.62 | 0.5% | 0.5% | 0.1% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.41 | 0.41..0.42 | 1.4% | 1.4% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 1.84 | 1.82..1.84 | 1.0% | 1.0% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 1.84 | 1.82..1.84 | 1.0% | 1.0% | 0.4% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.10 | 0.10..0.11 | 10.1% | 10.1% | 1.0% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.03 | 0.03..0.03 | 26.5% | 26.5% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.30 | 0.29..0.30 | 0.7% | 0.7% | 0.3% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.10 | 0.10..0.10 | 2.0% | 2.0% | 1.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.29 | 0.29..0.29 | 1.4% | 1.4% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.10 | 0.10..0.10 | 1.0% | 1.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.53 | 0.53..0.54 | 3.2% | 3.2% | 1.1% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.10 | 0.10..0.10 | 2.9% | 2.9% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.90 | 0.89..0.91 | 2.7% | 2.7% | 0.7% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.27 | 0.26..0.27 | 1.5% | 1.5% | 0.4% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.10 | 263.0% | 263.0% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02..0.08 | 375.0% | 375.0% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 72.7% | 72.7% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.19..0.23 | 17.4% | 17.4% | 1.5% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.15 | 0.15..0.17 | 10.3% | 10.3% | 1.9% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.04..0.05 | 12.8% | 12.8% | 6.4% | moderate |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.72 | 1.72..1.72 | 0.3% | 0.3% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.43 | 1.43..1.44 | 0.6% | 0.6% | 0.2% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.35 | 0.35..0.36 | 2.8% | 2.8% | 0.8% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.15 | 20.12..20.39 | 1.3% | 1.3% | 0.2% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 14.54 | 14.53..14.71 | 1.2% | 1.2% | 0.1% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.60 | 3.58..3.72 | 3.7% | 3.7% | 0.4% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.08 | 530.8% | 530.8% | 7.7% | moderate |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 1000.0% | 1000.0% | 50.0% | noisy |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.05..0.06 | 38.3% | 38.3% | 2.1% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 11.1% | 11.1% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.39 | 0.38..0.41 | 7.4% | 7.4% | 3.6% | moderate |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.07..0.09 | 24.4% | 24.4% | 3.3% | moderate |
| Select → Maps / 10000 rows / resqlite select() | 4.46 | 4.39..4.92 | 11.9% | 11.9% | 1.5% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.91 | 0.67..0.91 | 27.2% | 27.2% | 0.3% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.20 | 0.17..0.20 | 17.3% | 17.3% | 3.1% | moderate |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.20 | 0.17..0.20 | 17.3% | 17.3% | 3.1% | moderate |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.52 | 0.52..0.55 | 5.6% | 5.6% | 0.6% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.52 | 0.52..0.55 | 5.6% | 5.6% | 0.6% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03..0.06 | 113.3% | 113.3% | 13.3% | noisy |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03..0.06 | 113.3% | 113.3% | 13.3% | noisy |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.04..0.05 | 14.6% | 14.6% | 2.4% | stable |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.04..0.05 | 14.6% | 14.6% | 2.4% | stable |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 1.64 | 1.63..1.73 | 6.4% | 6.4% | 0.6% | stable |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 1.64 | 1.63..1.73 | 6.4% | 6.4% | 0.6% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.45 | 3.37..3.53 | 4.6% | 4.6% | 2.2% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.45 | 3.37..3.53 | 4.6% | 4.6% | 2.2% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.57 | 1.51..2.27 | 48.1% | 48.1% | 3.8% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.57 | 1.51..2.27 | 48.1% | 48.1% | 3.8% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 5.30 | 5.29..5.72 | 8.0% | 8.0% | 0.2% | stable |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 5.30 | 5.29..5.72 | 8.0% | 8.0% | 0.2% | stable |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.18 | 0.18..0.22 | 22.8% | 22.8% | 1.6% | stable |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.18 | 0.18..0.22 | 22.8% | 22.8% | 1.6% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.05 | 0.05..0.05 | 2.0% | 2.0% | 0.0% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.05 | 0.05..0.05 | 2.0% | 2.0% | 0.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.39 | 0.39..0.39 | 1.3% | 1.3% | 0.3% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.39 | 0.39..0.39 | 1.3% | 1.3% | 0.3% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.63 | 3.63..3.66 | 0.9% | 0.9% | 0.2% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.63 | 3.63..3.66 | 0.9% | 0.9% | 0.2% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.51 | 0.48..0.54 | 11.7% | 11.7% | 4.9% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.51 | 0.48..0.54 | 11.7% | 11.7% | 4.9% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.06..0.07 | 3.1% | 3.1% | 1.5% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.06..0.07 | 3.1% | 3.1% | 1.5% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 4.98 | 4.97..5.02 | 0.8% | 0.8% | 0.1% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 4.98 | 4.97..5.02 | 0.8% | 0.8% | 0.1% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.39 | 0.39..0.40 | 0.5% | 0.5% | 0.3% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.39 | 0.39..0.40 | 0.5% | 0.5% | 0.3% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05..0.05 | 7.8% | 7.8% | 2.0% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05..0.05 | 7.8% | 7.8% | 2.0% | stable |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.08 | 0.08..0.10 | 24.7% | 24.7% | 1.3% | stable |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.08 | 0.08..0.10 | 24.7% | 24.7% | 1.3% | stable |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.85 | 0.80..1.17 | 43.7% | 43.7% | 5.7% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.85 | 0.80..1.17 | 43.7% | 43.7% | 5.7% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.60 | 1.59..1.60 | 0.7% | 0.7% | 0.0% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.60 | 1.59..1.60 | 0.7% | 0.7% | 0.0% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.18..0.19 | 5.9% | 5.9% | 2.2% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.18..0.19 | 5.9% | 5.9% | 2.2% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.11 | 0.10..0.11 | 2.8% | 2.8% | 0.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.11 | 0.10..0.11 | 2.8% | 2.8% | 0.0% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 18.94 | 16.93..19.36 | 12.8% | 12.8% | 2.2% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 18.94 | 16.93..19.36 | 12.8% | 12.8% | 2.2% | stable |


## Comparison vs Previous Run

Previous: `2026-05-02T07-18-52-baseline-for-exp120.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 8.7% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02 | +0.00 | ±16% / ±0.02 ms | 10.5% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 6.7% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.32 | +0.02 | ±10% / ±0.03 ms | 9.4% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.32 | +0.02 | ±10% / ±0.03 ms | 9.4% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.30 | 0.30 | +0.00 | ±10% / ±0.03 ms | 3.3% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.15 | 0.15 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.36 | 0.36 | +0.00 | ±10% / ±0.04 ms | 5.6% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.68 | 0.71 | +0.03 | ±10% / ±0.07 ms | 8.5% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 5.1% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±300% / ±0.02 ms | 300.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 110.45 | 112.06 | +1.61 | ±10% / ±11.21 ms | 0.5% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 238.59 | 241.96 | +3.37 | ±10% / ±24.20 ms | 0.3% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 227.56 | 220.75 | -6.81 | ±10% / ±22.76 ms | 4.2% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 13.90 | 13.86 | -0.04 | ±10% / ±1.39 ms | 3.1% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 13.90 | 13.86 | -0.04 | ±10% / ±1.39 ms | 3.1% | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 156553.00 | 159253.00 | +2700.00 | ±10% / ±15925.30 ms | 3.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01 | +0.00 | ±42% / ±0.02 ms | 41.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±20% / ±0.02 ms | 20.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.03 | +0.00 | ±20% / ±0.02 ms | 20.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±100% / ±0.02 ms | 100.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±33% / ±0.02 ms | 33.3% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±33% / ±0.02 ms | 33.3% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.04 | -0.00 | ±10% / ±0.02 ms | 6.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.19 | +0.00 | ±10% / ±0.02 ms | 4.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.19 | +0.00 | ±10% / ±0.02 ms | 4.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | -0.00 | ±12% / ±0.02 ms | 12.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±11% / ±0.02 ms | 11.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±11% / ±0.02 ms | 11.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.39 | 0.38 | -0.02 | ±10% / ±0.04 ms | 2.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.72 | 1.73 | +0.00 | ±10% / ±0.17 ms | 0.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.72 | 1.73 | +0.00 | ±10% / ±0.17 ms | 0.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.10 | 0.08 | -0.02 | ±10% / ±0.02 ms | 1.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.35 | +0.01 | ±10% / ±0.04 ms | 1.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.35 | +0.01 | ±10% / ±0.04 ms | 1.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.49 | 4.39 | -0.11 | ±10% / ±0.45 ms | 3.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 21.94 | 20.36 | -1.58 | ±11% / ±2.49 ms | 11.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 21.94 | 20.36 | -1.58 | ±11% / ±2.49 ms | 11.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.98 | 0.83 | -0.15 | ±10% / ±0.10 ms | 0.7% | stable | 🟢 Win (-15%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.60 | 3.59 | -0.02 | ±10% / ±0.36 ms | 4.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.60 | 3.59 | -0.02 | ±10% / ±0.36 ms | 4.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.80 | 0.78 | -0.02 | ±10% / ±0.08 ms | 1.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.83 | 3.65 | -0.17 | ±10% / ±0.38 ms | 3.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.83 | 3.65 | -0.17 | ±10% / ±0.38 ms | 3.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.20 | 0.17 | -0.03 | ±10% / ±0.02 ms | 1.8% | stable | 🟢 Win (-14%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.75 | 0.76 | +0.01 | ±10% / ±0.08 ms | 1.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.75 | 0.76 | +0.01 | ±10% / ±0.08 ms | 1.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.84 | 10.68 | -0.16 | ±10% / ±1.08 ms | 1.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 42.32 | 42.07 | -0.25 | ±10% / ±4.23 ms | 1.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 42.32 | 42.07 | -0.25 | ±10% / ±4.23 ms | 1.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.95 | 1.66 | -0.30 | ±10% / ±0.20 ms | 0.5% | stable | 🟢 Win (-15%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 7.52 | 7.37 | -0.15 | ±10% / ±0.75 ms | 7.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 7.52 | 7.37 | -0.15 | ±10% / ±0.75 ms | 7.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03 | -0.00 | ±11% / ±0.02 ms | 11.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10 | +0.00 | ±12% / ±0.02 ms | 10.7% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.10 | 0.10 | +0.00 | ±12% / ±0.02 ms | 10.7% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.01 | 0.00 | -0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | +0.00 | ±33% / ±0.02 ms | 29.6% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | +0.00 | ±33% / ±0.02 ms | 29.6% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.20 | 0.19 | -0.01 | ±10% / ±0.02 ms | 2.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.90 | 0.89 | -0.01 | ±10% / ±0.09 ms | 0.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.90 | 0.89 | -0.01 | ±10% / ±0.09 ms | 0.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.05 | 0.04 | -0.01 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.18 | +0.00 | ±10% / ±0.02 ms | 2.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.18 | +0.00 | ±10% / ±0.02 ms | 2.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.15 | 2.06 | -0.09 | ±10% / ±0.21 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 9.60 | 9.59 | -0.01 | ±10% / ±0.96 ms | 0.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 9.60 | 9.59 | -0.01 | ±10% / ±0.96 ms | 0.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.49 | 0.41 | -0.08 | ±10% / ±0.05 ms | 1.4% | stable | 🟢 Win (-15%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.91 | 1.84 | -0.07 | ±10% / ±0.19 ms | 1.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.91 | 1.84 | -0.07 | ±10% / ±0.19 ms | 1.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 10.1% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.04 | 0.03 | -0.01 | ±26% / ±0.02 ms | 26.5% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.32 | 0.30 | -0.02 | ±10% / ±0.03 ms | 0.7% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.12 | 0.10 | -0.02 | ±10% / ±0.02 ms | 2.0% | stable | 🟢 Win (-19%) |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.33 | 0.29 | -0.04 | ±10% / ±0.03 ms | 1.4% | stable | 🟢 Win (-12%) |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.13 | 0.10 | -0.04 | ±10% / ±0.02 ms | 1.0% | stable | 🟢 Win (-28%) |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.56 | 0.53 | -0.02 | ±10% / ±0.06 ms | 3.2% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.13 | 0.10 | -0.03 | ±10% / ±0.02 ms | 2.9% | stable | 🟢 Win (-20%) |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.97 | 0.90 | -0.07 | ±10% / ±0.10 ms | 2.7% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.34 | 0.27 | -0.08 | ±10% / ±0.03 ms | 1.5% | stable | 🟢 Win (-23%) |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±263% / ±0.07 ms | 263.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.01 | 0.02 | +0.00 | ±375% / ±0.06 ms | 375.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | +0.00 | ±73% / ±0.02 ms | 72.7% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.22 | 0.20 | -0.03 | ±17% / ±0.04 ms | 17.4% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.17 | 0.15 | -0.02 | ±10% / ±0.02 ms | 10.3% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.05 | +0.00 | ±19% / ±0.02 ms | 12.8% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.74 | 1.72 | -0.02 | ±10% / ±0.17 ms | 0.3% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.45 | 1.43 | -0.01 | ±10% / ±0.14 ms | 0.6% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.35 | 0.35 | +0.01 | ±10% / ±0.04 ms | 2.8% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.23 | 20.15 | -0.08 | ±10% / ±2.02 ms | 1.3% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 14.55 | 14.54 | -0.01 | ±10% / ±1.45 ms | 1.2% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.73 | 3.60 | -0.13 | ±10% / ±0.37 ms | 3.7% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | -0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | +0.00 | ±531% / ±0.07 ms | 530.8% | moderate | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±1000% / ±0.02 ms | 1000.0% | noisy | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.05 | +0.00 | ±38% / ±0.02 ms | 38.3% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±11% / ±0.02 ms | 11.1% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.38 | 0.39 | +0.02 | ±11% / ±0.04 ms | 7.4% | moderate | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.09 | +0.00 | ±24% / ±0.02 ms | 24.4% | moderate | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 4.34 | 4.46 | +0.12 | ±12% / ±0.53 ms | 11.9% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.85 | 0.91 | +0.06 | ±27% / ±0.25 ms | 27.2% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.17 | 0.20 | +0.02 | ±17% / ±0.03 ms | 17.3% | moderate | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.17 | 0.20 | +0.02 | ±17% / ±0.03 ms | 17.3% | moderate | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.52 | 0.52 | +0.00 | ±10% / ±0.05 ms | 5.6% | stable | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.52 | 0.52 | +0.00 | ±10% / ±0.05 ms | 5.6% | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | +0.00 | ±113% / ±0.03 ms | 113.3% | noisy | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03 | +0.00 | ±113% / ±0.03 ms | 113.3% | noisy | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.04 | -0.00 | ±15% / ±0.02 ms | 14.6% | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.04 | -0.00 | ±15% / ±0.02 ms | 14.6% | stable | ⚪ Within noise |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 1.64 | 1.64 | -0.00 | ±10% / ±0.16 ms | 6.4% | stable | ⚪ Within noise |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 1.64 | 1.64 | -0.00 | ±10% / ±0.16 ms | 6.4% | stable | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.42 | 3.45 | +0.03 | ±10% / ±0.35 ms | 4.6% | stable | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.42 | 3.45 | +0.03 | ±10% / ±0.35 ms | 4.6% | stable | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.64 | 1.57 | -0.07 | ±48% / ±0.79 ms | 48.1% | moderate | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.64 | 1.57 | -0.07 | ±48% / ±0.79 ms | 48.1% | moderate | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 5.17 | 5.30 | +0.13 | ±10% / ±0.53 ms | 8.0% | stable | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 5.17 | 5.30 | +0.13 | ±10% / ±0.53 ms | 8.0% | stable | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.18 | 0.18 | +0.00 | ±23% / ±0.04 ms | 22.8% | stable | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.18 | 0.18 | +0.00 | ±23% / ±0.04 ms | 22.8% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.39 | 0.39 | +0.00 | ±10% / ±0.04 ms | 1.3% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.39 | 0.39 | +0.00 | ±10% / ±0.04 ms | 1.3% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.63 | 3.63 | +0.00 | ±10% / ±0.36 ms | 0.9% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.63 | 3.63 | +0.00 | ±10% / ±0.36 ms | 0.9% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.48 | 0.51 | +0.03 | ±15% / ±0.08 ms | 11.7% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.48 | 0.51 | +0.03 | ±15% / ±0.08 ms | 11.7% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.06 | 0.07 | +0.00 | ±10% / ±0.02 ms | 3.1% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.06 | 0.07 | +0.00 | ±10% / ±0.02 ms | 3.1% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 4.85 | 4.98 | +0.13 | ±10% / ±0.50 ms | 0.8% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 4.85 | 4.98 | +0.13 | ±10% / ±0.50 ms | 0.8% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.39 | 0.39 | +0.00 | ±10% / ±0.04 ms | 0.5% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.39 | 0.39 | +0.00 | ±10% / ±0.04 ms | 0.5% | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 7.8% | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 7.8% | stable | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.08 | 0.08 | -0.00 | ±25% / ±0.02 ms | 24.7% | stable | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.08 | 0.08 | -0.00 | ±25% / ±0.02 ms | 24.7% | stable | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.80 | 0.85 | +0.04 | ±44% / ±0.37 ms | 43.7% | moderate | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.80 | 0.85 | +0.04 | ±44% / ±0.37 ms | 43.7% | moderate | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.56 | 1.60 | +0.04 | ±10% / ±0.16 ms | 0.7% | stable | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.56 | 1.60 | +0.04 | ±10% / ±0.16 ms | 0.7% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.18 | +0.00 | ±10% / ±0.02 ms | 5.9% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.18 | +0.00 | ±10% / ±0.02 ms | 5.9% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.11 | +0.00 | ±10% / ±0.02 ms | 2.8% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.11 | +0.00 | ±10% / ±0.02 ms | 2.8% | stable | ⚪ Within noise |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 18.75 | 18.94 | +0.20 | ±13% / ±2.43 ms | 12.8% | stable | ⚪ Within noise |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 18.75 | 18.94 | +0.20 | ±13% / ±2.43 ms | 12.8% | stable | ⚪ Within noise |

**Summary:** 9 wins, 0 regressions, 152 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

✅ **No regressions beyond noise.** 9 benchmarks improved.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.02 | 0.50 | +0.48 MB | ±1.26 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 5.53 | 0.44 | -5.09 MB | ±0.50 MB | 🟢 Win (-5.09 MB) |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 4.59 | 0.00 | -4.59 MB | ±7.68 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 0.00 | 1.27 | +1.27 MB | ±6.38 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 7.84 | 0.00 | -7.84 MB | ±0.50 MB | 🟢 Win (-7.84 MB) |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 6.34 | 6.34 | +0.00 MB | ±5.95 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / resqlite select() | 5.00 | 1.97 | -3.03 MB | ±2.50 MB | 🟢 Win (-3.03 MB) |
| Memory / Select 10k rows → Maps / sqlite3 select() | 2.98 | 5.30 | +2.32 MB | ±4.57 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 0.50 | 1.00 | +0.50 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.06 | 0.00 | -0.06 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 3 wins, 0 regressions, 12 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 4177 | 3951 | -226 | ±100 | 🟢 Fewer re-emits (-226) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 4191 | 4114 | -77 | ±100 | ⚪ Within noise |

**Granularity summary:** 1 fewer-re-emit, 0 more-re-emit, 5 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


