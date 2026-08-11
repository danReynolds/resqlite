# resqlite Benchmark Results

Generated: 2026-08-11T08:08:05.118486

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp269-enforced-inline-reads`
- Repeats: `5`
- Runtime: `dart-vm / Dart 3.12.2`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `exp-269-enforced-inline-reads @ a01ea08e2667`
- Comparison baseline: `2026-08-11T07-54-12-baseline-for-exp269.md`
- Comparison mode: `explicit`
- Comparison baseline compatibility: `compatible`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.005 | 0.006 | 0.000 | 0.000 |
| sqlite3 select() | 0.016 | 0.016 | 0.016 | 0.016 |
| sqlite_async select() | 0.032 | 0.040 | 0.001 | 0.002 |
| drift select() | 0.046 | 0.093 | 0.001 | 0.003 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.040 | 0.045 | 0.005 | 0.006 |
| sqlite3 select() | 0.120 | 0.123 | 0.120 | 0.123 |
| sqlite_async select() | 0.133 | 0.142 | 0.010 | 0.010 |
| drift select() | 0.188 | 0.209 | 0.010 | 0.012 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.316 | 0.331 | 0.051 | 0.058 |
| sqlite3 select() | 1.159 | 1.284 | 1.159 | 1.284 |
| sqlite_async select() | 1.111 | 1.333 | 0.099 | 0.113 |
| drift select() | 1.620 | 1.835 | 0.095 | 0.101 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 3.607 | 11.077 | 0.529 | 2.505 |
| sqlite3 select() | 15.466 | 20.406 | 15.466 | 20.406 |
| sqlite_async select() | 14.089 | 17.501 | 0.973 | 2.705 |
| drift select() | 25.057 | 30.083 | 0.978 | 2.930 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row. The large-payload row isolates resqlite selectBytes because it guards the native bytes transfer policy without multiplying large JSON encoding work across every peer.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.022 | 0.023 | 0.017 | 0.018 |
| sqlite3 + jsonEncode | 0.031 | 0.033 | 0.031 | 0.033 |
| sqlite_async + jsonEncode | 0.046 | 0.049 | 0.017 | 0.018 |
| drift + jsonEncode | 0.056 | 0.080 | 0.018 | 0.022 |
| resqlite selectBytes() | 0.011 | 0.012 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.202 | 0.232 | 0.165 | 0.176 |
| sqlite3 + jsonEncode | 0.364 | 0.753 | 0.364 | 0.753 |
| sqlite_async + jsonEncode | 0.289 | 0.350 | 0.166 | 0.186 |
| drift + jsonEncode | 0.336 | 0.411 | 0.161 | 0.187 |
| resqlite selectBytes() | 0.038 | 0.056 | 0.000 | 0.001 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.917 | 3.565 | 1.604 | 3.229 |
| sqlite3 + jsonEncode | 2.716 | 4.201 | 2.716 | 4.201 |
| sqlite_async + jsonEncode | 2.748 | 4.610 | 1.614 | 2.056 |
| drift + jsonEncode | 3.246 | 5.592 | 1.613 | 2.271 |
| resqlite selectBytes() | 0.266 | 0.305 | 0.000 | 0.001 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 22.964 | 27.362 | 16.236 | 20.011 |
| sqlite3 + jsonEncode | 31.998 | 38.712 | 31.998 | 38.712 |
| sqlite_async + jsonEncode | 32.293 | 38.314 | 16.720 | 18.746 |
| drift + jsonEncode | 43.410 | 49.051 | 16.413 | 22.402 |
| resqlite selectBytes() | 2.689 | 2.844 | 0.001 | 0.004 |

### Large payload (~650KB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.273 | 0.293 | 0.000 | 0.000 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.088 | 0.101 | 0.024 | 0.026 |
| sqlite3 | 0.329 | 0.368 | 0.329 | 0.368 |
| sqlite_async | 0.371 | 0.402 | 0.032 | 0.035 |
| drift | 0.572 | 0.640 | 0.032 | 0.036 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.868 | 0.973 | 0.229 | 0.249 |
| sqlite3 | 3.410 | 3.752 | 3.410 | 3.752 |
| sqlite_async | 3.127 | 3.534 | 0.245 | 0.266 |
| drift | 4.839 | 6.505 | 0.246 | 0.261 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.395 | 1.149 | 0.061 | 0.082 |
| sqlite3 | 1.496 | 1.877 | 1.496 | 1.877 |
| sqlite_async | 1.451 | 1.683 | 0.088 | 0.097 |
| drift | 2.005 | 2.413 | 0.089 | 0.102 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.252 | 0.264 | 0.062 | 0.067 |
| sqlite3 | 1.029 | 1.115 | 1.029 | 1.115 |
| sqlite_async | 0.987 | 1.091 | 0.087 | 0.102 |
| drift | 1.493 | 1.674 | 0.085 | 0.090 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.254 | 0.264 | 0.062 | 0.064 |
| sqlite3 | 0.983 | 1.079 | 0.983 | 1.079 |
| sqlite_async | 0.962 | 1.138 | 0.085 | 0.105 |
| drift | 1.456 | 1.700 | 0.084 | 0.088 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.005 | 0.006 | 0.000 | 0.000 |
| sqlite3 | 0.016 | 0.017 | 0.016 | 0.017 |
| sqlite_async | 0.031 | 0.035 | 0.001 | 0.001 |
| drift | 0.040 | 0.053 | 0.001 | 0.001 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.017 | 0.018 | 0.002 | 0.003 |
| sqlite3 | 0.062 | 0.065 | 0.062 | 0.065 |
| sqlite_async | 0.074 | 0.077 | 0.004 | 0.004 |
| drift | 0.104 | 0.119 | 0.004 | 0.004 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.040 | 0.042 | 0.005 | 0.006 |
| sqlite3 | 0.121 | 0.132 | 0.121 | 0.132 |
| sqlite_async | 0.125 | 0.128 | 0.007 | 0.008 |
| drift | 0.184 | 0.231 | 0.007 | 0.010 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.164 | 0.166 | 0.026 | 0.026 |
| sqlite3 | 0.577 | 0.668 | 0.577 | 0.668 |
| sqlite_async | 0.532 | 0.594 | 0.036 | 0.038 |
| drift | 0.802 | 0.953 | 0.036 | 0.040 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.313 | 0.377 | 0.052 | 0.056 |
| sqlite3 | 1.152 | 1.338 | 1.152 | 1.338 |
| sqlite_async | 1.060 | 1.238 | 0.073 | 0.081 |
| drift | 1.595 | 1.787 | 0.073 | 0.084 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.639 | 0.725 | 0.107 | 0.114 |
| sqlite3 | 2.316 | 3.018 | 2.316 | 3.018 |
| sqlite_async | 2.195 | 2.511 | 0.149 | 0.162 |
| drift | 3.358 | 3.907 | 0.151 | 0.584 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.859 | 5.747 | 0.268 | 0.421 |
| sqlite3 | 5.854 | 8.427 | 5.854 | 8.427 |
| sqlite_async | 5.883 | 6.364 | 0.371 | 0.482 |
| drift | 8.627 | 9.121 | 0.370 | 0.392 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.626 | 9.495 | 0.535 | 0.863 |
| sqlite3 | 15.236 | 18.021 | 15.236 | 18.021 |
| sqlite_async | 12.137 | 14.119 | 0.742 | 0.801 |
| drift | 20.885 | 33.736 | 0.783 | 2.273 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 9.532 | 16.554 | 1.108 | 2.772 |
| sqlite3 | 36.808 | 40.934 | 36.808 | 40.934 |
| sqlite_async | 38.618 | 45.625 | 1.503 | 2.401 |
| drift | 55.015 | 66.762 | 1.504 | 2.232 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.020 | 0.021 | 0.020 | 0.021 |
| sqlite3 + jsonEncode | 0.032 | 0.033 | 0.032 | 0.033 |
| sqlite_async + jsonEncode | 0.050 | 0.062 | 0.050 | 0.062 |
| drift + jsonEncode | 0.056 | 0.070 | 0.056 | 0.070 |
| resqlite selectBytes() | 0.011 | 0.013 | 0.011 | 0.013 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.099 | 0.139 | 0.099 | 0.139 |
| sqlite3 + jsonEncode | 0.144 | 0.148 | 0.144 | 0.148 |
| sqlite_async + jsonEncode | 0.157 | 0.235 | 0.157 | 0.235 |
| drift + jsonEncode | 0.180 | 0.191 | 0.180 | 0.191 |
| resqlite selectBytes() | 0.021 | 0.024 | 0.021 | 0.024 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.200 | 0.222 | 0.200 | 0.222 |
| sqlite3 + jsonEncode | 0.273 | 0.322 | 0.273 | 0.322 |
| sqlite_async + jsonEncode | 0.283 | 0.305 | 0.283 | 0.305 |
| drift + jsonEncode | 0.345 | 0.426 | 0.345 | 0.426 |
| resqlite selectBytes() | 0.035 | 0.043 | 0.035 | 0.043 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.945 | 1.051 | 0.945 | 1.051 |
| sqlite3 + jsonEncode | 1.355 | 1.479 | 1.355 | 1.479 |
| sqlite_async + jsonEncode | 1.309 | 1.504 | 1.309 | 1.504 |
| drift + jsonEncode | 1.629 | 1.822 | 1.629 | 1.822 |
| resqlite selectBytes() | 0.134 | 0.139 | 0.134 | 0.139 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.912 | 2.024 | 1.912 | 2.024 |
| sqlite3 + jsonEncode | 2.754 | 3.070 | 2.754 | 3.070 |
| sqlite_async + jsonEncode | 2.630 | 2.934 | 2.630 | 2.934 |
| drift + jsonEncode | 3.265 | 4.317 | 3.265 | 4.317 |
| resqlite selectBytes() | 0.266 | 0.277 | 0.266 | 0.277 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 4.018 | 7.978 | 4.018 | 7.978 |
| sqlite3 + jsonEncode | 5.708 | 10.518 | 5.708 | 10.518 |
| sqlite_async + jsonEncode | 5.610 | 10.230 | 5.610 | 10.230 |
| drift + jsonEncode | 6.910 | 11.266 | 6.910 | 11.266 |
| resqlite selectBytes() | 0.502 | 0.537 | 0.502 | 0.537 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 10.779 | 14.817 | 10.779 | 14.817 |
| sqlite3 + jsonEncode | 14.838 | 21.703 | 14.838 | 21.703 |
| sqlite_async + jsonEncode | 14.670 | 21.645 | 14.670 | 21.645 |
| drift + jsonEncode | 20.141 | 24.507 | 20.141 | 24.507 |
| resqlite selectBytes() | 1.275 | 1.414 | 1.275 | 1.414 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 25.192 | 27.438 | 25.192 | 27.438 |
| sqlite3 + jsonEncode | 36.345 | 40.370 | 36.345 | 40.370 |
| sqlite_async + jsonEncode | 34.696 | 36.750 | 34.696 | 36.750 |
| drift + jsonEncode | 40.475 | 44.261 | 40.475 | 44.261 |
| resqlite selectBytes() | 2.666 | 2.796 | 2.666 | 2.796 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 46.921 | 49.187 | 46.921 | 49.187 |
| sqlite3 + jsonEncode | 69.974 | 77.521 | 69.974 | 77.521 |
| sqlite_async + jsonEncode | 76.871 | 83.599 | 76.871 | 83.599 |
| drift + jsonEncode | 94.101 | 108.960 | 94.101 | 108.960 |
| resqlite selectBytes() | 6.463 | 7.835 | 6.463 | 7.835 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.27 | 0.29 | 0.27 |
| sqlite_async | 0.96 | 1.15 | 0.96 |
| drift | 1.56 | 1.73 | 1.56 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.31 | 0.15 |
| sqlite_async | 1.46 | 1.73 | 0.73 |
| drift | 2.86 | 3.17 | 1.43 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.34 | 0.86 | 0.09 |
| sqlite_async | 2.38 | 3.05 | 0.60 |
| drift | 5.50 | 6.10 | 1.38 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.66 | 1.37 | 0.08 |
| sqlite_async | 5.27 | 6.26 | 0.66 |
| drift | 11.26 | 12.04 | 1.41 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 439593 |
| resqlite per query | 0.002 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 439593 | 438757..440742 | 0.2 | 0.7 |
| sqlite3 | 186052 | 185457..186419 | 0.3 | 1.0 |
| sqlite_async | 45629 | 44935..45902 | 1.1 | 3.6 |
| drift | 44045 | 43393..44300 | 1.0 | 2.2 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.602 | 14.898 | 14.602 | 14.898 |
| sqlite_async | 37.712 | 38.098 | 37.712 | 38.098 |
| drift | 54.735 | 55.425 | 54.735 | 55.425 |
| sqlite3 (no cache) | 24.882 | 25.181 | 24.882 | 25.181 |
| sqlite3 (cached stmt) | 24.495 | 24.681 | 24.495 | 24.681 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.651 | 3.054 | 1.651 | 3.054 |
| sqlite3 execute() | 0.980 | 2.438 | 0.980 | 2.438 |
| sqlite_async execute() | 3.135 | 5.589 | 3.135 | 5.589 |
| drift execute() | 3.030 | 4.431 | 3.030 | 4.431 |

### Concurrent Single Inserts (100 concurrent)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite concurrent execute() | 0.902 | 1.760 | 0.902 | 1.760 |
| sqlite3 concurrent execute() | 0.949 | 3.781 | 0.949 | 3.781 |
| sqlite_async concurrent execute() | 3.046 | 5.842 | 3.046 | 5.842 |
| drift concurrent execute() | 1.903 | 4.493 | 1.903 | 4.493 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.061 | 0.064 | 0.061 | 0.064 |
| sqlite3 executeBatch() | 0.057 | 0.068 | 0.057 | 0.068 |
| sqlite_async executeBatch() | 0.108 | 0.141 | 0.108 | 0.141 |
| drift executeBatch() | 0.121 | 0.153 | 0.121 | 0.153 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.481 | 0.526 | 0.481 | 0.526 |
| sqlite3 executeBatch() | 0.555 | 0.645 | 0.555 | 0.645 |
| sqlite_async executeBatch() | 0.624 | 0.682 | 0.624 | 0.682 |
| drift executeBatch() | 0.755 | 0.859 | 0.755 | 0.859 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.075 | 4.971 | 4.075 | 4.971 |
| sqlite3 executeBatch() | 4.397 | 4.981 | 4.397 | 4.981 |
| sqlite_async executeBatch() | 5.162 | 6.305 | 5.162 | 6.305 |
| drift executeBatch() | 6.454 | 7.933 | 6.454 | 7.933 |

### Wide Batch Insert (10000 rows x 20 params)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 13.622 | 26.801 | 13.622 | 26.801 |
| sqlite3 executeBatch() | 19.949 | 23.607 | 19.949 | 23.607 |
| sqlite_async executeBatch() | 23.116 | 28.260 | 23.116 | 28.260 |
| drift executeBatch() | 26.334 | 30.541 | 26.334 | 30.541 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.058 | 0.081 | 0.058 | 0.081 |
| sqlite_async writeTransaction() | 0.098 | 0.122 | 0.098 | 0.122 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.074 | 0.091 | 0.074 | 0.091 |
| resqlite tx.execute() loop | 0.430 | 0.567 | 0.430 | 0.567 |
| sqlite_async tx.execute() loop | 1.183 | 1.430 | 1.183 | 1.430 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.631 | 0.857 | 0.631 | 0.857 |
| resqlite tx.execute() loop | 5.114 | 5.841 | 5.114 | 5.841 |
| sqlite_async tx.execute() loop | 11.225 | 12.300 | 11.225 | 12.300 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.102 | 0.115 | 0.102 | 0.115 |
| sqlite_async tx.getAll() | 0.212 | 0.249 | 0.212 | 0.249 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.180 | 0.203 | 0.180 | 0.203 |
| sqlite_async tx.getAll() | 0.369 | 0.469 | 0.369 | 0.469 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 0.765 | 1.053 | 0.765 | 1.053 |
| resqlite nested transaction() depth=5 | 0.079 | 0.093 | 0.079 | 0.093 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.027 | 0.047 | 0.027 | 0.047 |
| sqlite_async watch() | 0.116 | 0.137 | 0.116 | 0.137 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.058 | 0.115 | 0.058 | 0.115 |
| sqlite_async | 0.083 | 0.131 | 0.083 | 0.131 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.234 | 0.284 | 0.234 | 0.284 |
| sqlite_async | 0.515 | 1.054 | 0.515 | 1.054 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.245 | 2.569 | 2.245 | 2.569 |

### Long-Payload Unchanged Fanout (8 streams, 64 rows x 32KB TEXT + 32KB BLOB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.802 | 3.279 | 2.802 | 3.279 |

### Long-Text 32KB Unchanged Fanout (8 unchanged streams, 64 rows x 32KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.001 | 3.446 | 3.001 | 3.446 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.206 | 0.268 | 0.206 | 0.268 |
| sqlite_async | 0.298 | 0.347 | 0.298 | 0.347 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.607 | 1.607 | 1.607 | 1.607 |
| sqlite_async | 9.881 | 9.881 | 9.881 | 9.881 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.281 | 5.096 | 3.281 | 5.096 |
| sqlite_async | 5.954 | 8.685 | 5.954 | 8.685 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.539 | 0.737 | 0.539 | 0.737 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 6.544 | 7.098 | 6.544 | 7.098 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. For resqlite, this emission metric can reflect writer-side column-level invalidation, experiment 075's native result-hash short-circuit, or both. Use A11c (Many-Streams Writer Throughput) when the question is specifically writer-side dispatch elision.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 78.8 | 0.000 |
| sqlite_async | 4320 | 1245.9 | 1.047 |
| drift | 5000 | 1107.8 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 71.6 | 0.000 |
| sqlite_async | 4127 | 1171.2 | 1.047 |
| drift | 5000 | 1076.9 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 224.13 | 229.83 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 444.82 | 446.29 | 0.00 | 0.00 | 1119 | 3 |
| drift stream() | 558.85 | 562.66 | 0.01 | 0.02 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.027 | 0.061 | 0.000 | 0.000 |
| sqlite3 | 0.035 | 0.049 | 0.035 | 0.049 |
| sqlite_async | 0.055 | 0.081 | 0.000 | 0.000 |
| drift | 0.056 | 0.078 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.021 | 0.040 | 0.000 | 0.000 |
| sqlite3 | 0.020 | 0.026 | 0.020 | 0.026 |
| sqlite_async | 0.040 | 0.055 | 0.000 | 0.000 |
| drift | 0.041 | 0.060 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.014 | 0.026 | 0.000 | 0.000 |
| sqlite3 | 0.031 | 0.036 | 0.031 | 0.036 |
| sqlite_async | 0.060 | 0.076 | 0.000 | 0.000 |
| drift | 0.056 | 0.067 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.002 | 0.008 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.023 | 0.029 | 0.000 | 0.000 |
| drift | 0.021 | 0.029 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.031 | 0.037 | 0.001 | 0.001 |
| sqlite3 | 0.068 | 0.071 | 0.068 | 0.071 |
| sqlite_async | 0.083 | 0.088 | 0.001 | 0.001 |
| drift | 0.093 | 0.104 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 108.524 | 111.580 | 0.000 | 0.000 | 0 |
| sqlite_async | 221.637 | 224.629 | 0.000 | 0.000 | 41 |
| drift | 235.478 | 238.828 | 0.000 | 0.001 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 447.15 | 447.15 | 0.00 | 0.00 | 13.59 | 433.56 | 2 |
| sqlite_async | 493.55 | 493.55 | 0.00 | 0.00 | 24.52 | 469.03 | 1185 |
| drift | 1792.48 | 1792.48 | 0.19 | 0.19 | 15.14 | 1777.97 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## SQLite Diagnostics

resqlite-only internal SQLite counters captured via `Database.diagnostics()` after representative workloads. Values reflect the writer plus idle readers in this connection pool; they are not process-global SQLite totals.

### Warm read working set (20000 rows + 2000 point lookups)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | JSON buf (KiB) | Readers busy |
|---|---|---|---|---|---|---|---|
| resqlite | 3199.9 | 3182.3 | 5.3 | 12.3 | 2048.0 | 80.0 | 0 |

### Statement cache footprint (48 distinct SELECT texts)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | JSON buf (KiB) | Readers busy |
|---|---|---|---|---|---|---|---|
| resqlite | 3292.9 | 3182.3 | 5.3 | 105.3 | 2048.0 | 80.0 | 0 |

### WAL after write burst (1000 inserted rows)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | JSON buf (KiB) | Readers busy |
|---|---|---|---|---|---|---|---|
| resqlite | 250.4 | 232.8 | 5.3 | 12.3 | 161.0 | 80.0 | 0 |

### JSON buffer reclaim (8 large selectBytes + 64 small settles)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | JSON buf (KiB) | Readers busy |
|---|---|---|---|---|---|---|---|
| resqlite | 2290.6 | 2260.0 | 6.6 | 24.0 | 2088.2 | 80.0 | 0 |

## Repeat Stability

These rows summarize resqlite wall medians across repeated full-suite runs.
Use this section to judge whether small deltas are real or just noise.

| Benchmark | Median (ms) | 95% CI (ms) | MDE_ci | Range | MAD | Stability |
|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.00 | 0.00..0.00 | 25.0% | 50.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.03 | 0.03..0.03 | 1.9% | 3.7% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02..0.02 | 4.8% | 9.5% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.27 | 0.27..0.28 | 1.9% | 3.7% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.27 | 0.27..0.28 | 1.9% | 3.7% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.30 | 0.29..0.30 | 1.7% | 3.3% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.15 | 0.15..0.15 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.35 | 0.34..0.39 | 7.1% | 14.3% | 2.9% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.09 | 0.08..0.10 | 11.1% | 22.2% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.66 | 0.64..0.72 | 6.1% | 12.1% | 1.5% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.08 | 0.08..0.09 | 6.2% | 12.5% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.03 | 0.03..0.03 | 1.6% | 3.1% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 150.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 109.51 | 107.01..110.64 | 1.7% | 3.3% | 0.9% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 243.58 | 236.29..447.15 | 43.3% | 86.6% | 1.6% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 224.13 | 216.07..225.64 | 2.1% | 4.3% | 0.7% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 14.60 | 14.49..14.73 | 0.8% | 1.7% | 0.5% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 14.60 | 14.49..14.73 | 0.8% | 1.7% | 0.5% | stable |
| Point Query Throughput / resqlite qps | 439593.00 | 435971.00..441157.00 | 0.6% | 1.2% | 0.1% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.01 | 20.0% | 40.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.02 | 0.02..0.03 | 19.0% | 38.1% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02..0.03 | 19.0% | 38.1% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 36.4% | 72.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.02 | 36.4% | 72.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.04..0.04 | 3.7% | 7.5% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.20 | 0.20..0.21 | 3.2% | 6.4% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.20 | 0.20..0.21 | 3.2% | 6.4% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.04 | 5.6% | 11.1% | 2.8% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.04 | 0.04..0.04 | 5.6% | 11.1% | 2.8% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.33 | 0.31..0.33 | 2.5% | 4.9% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.93 | 1.90..1.95 | 1.5% | 3.0% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.93 | 1.90..1.95 | 1.5% | 3.0% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.05 | 0.05..0.05 | 1.9% | 3.8% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.26 | 0.26..0.27 | 1.3% | 2.7% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.26 | 0.26..0.27 | 1.3% | 2.7% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 3.64 | 3.63..3.66 | 0.5% | 0.9% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 23.51 | 20.50..25.19 | 10.0% | 19.9% | 7.0% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 23.51 | 20.50..25.19 | 10.0% | 19.9% | 7.0% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.54 | 0.54..0.54 | 0.6% | 1.1% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 2.69 | 2.64..2.76 | 2.2% | 4.4% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 2.69 | 2.64..2.76 | 2.2% | 4.4% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.64 | 0.62..0.65 | 1.7% | 3.4% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.93 | 3.92..4.02 | 1.3% | 2.5% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.93 | 3.92..4.02 | 1.3% | 2.5% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.11 | 0.10..0.11 | 1.4% | 2.8% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.52 | 0.50..0.53 | 2.5% | 5.0% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.52 | 0.50..0.53 | 2.5% | 5.0% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 9.38 | 9.22..9.81 | 3.1% | 6.2% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 46.54 | 46.44..46.92 | 0.5% | 1.0% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 46.54 | 46.44..46.92 | 0.5% | 1.0% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.08 | 1.06..1.11 | 2.0% | 4.1% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 5.89 | 5.64..6.46 | 7.0% | 13.9% | 4.0% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 5.89 | 5.64..6.46 | 7.0% | 13.9% | 4.0% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.02 | 0.02..0.02 | 5.9% | 11.8% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10..0.13 | 16.0% | 32.0% | 3.9% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.10 | 0.10..0.13 | 16.0% | 32.0% | 3.9% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.00 | 25.0% | 50.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.02..0.03 | 12.0% | 24.0% | 8.0% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.02..0.03 | 12.0% | 24.0% | 8.0% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.17 | 0.16..0.17 | 2.1% | 4.1% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.98 | 0.94..1.00 | 2.8% | 5.6% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.98 | 0.94..1.00 | 2.8% | 5.6% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.03 | 0.03..0.03 | 1.9% | 3.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.14 | 0.13..0.14 | 2.6% | 5.1% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.14 | 0.13..0.14 | 2.6% | 5.1% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 1.90 | 1.85..1.93 | 2.1% | 4.3% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 10.46 | 9.98..10.82 | 4.0% | 8.0% | 3.1% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 10.46 | 9.98..10.82 | 4.0% | 8.0% | 3.1% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.27 | 0.27..0.27 | 0.6% | 1.1% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 1.28 | 1.27..1.34 | 2.5% | 5.0% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 1.28 | 1.27..1.34 | 2.5% | 5.0% | 0.7% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.09 | 0.09..0.09 | 2.3% | 4.5% | 0.0% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.02 | 0.01..0.02 | 18.8% | 37.5% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.26 | 0.25..0.26 | 2.2% | 4.3% | 0.8% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.06 | 0.06..0.06 | 2.4% | 4.8% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.25 | 0.24..0.26 | 2.6% | 5.2% | 1.6% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.06 | 0.06..0.06 | 2.4% | 4.8% | 1.6% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.39 | 0.38..0.40 | 1.5% | 3.1% | 0.3% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.06 | 0.06..0.06 | 1.6% | 3.3% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.79 | 0.78..0.87 | 5.9% | 11.7% | 2.4% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.21 | 0.20..0.23 | 6.0% | 12.0% | 1.9% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.02 | 0.02..0.05 | 68.2% | 136.4% | 4.5% | moderate |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02..0.04 | 70.6% | 141.2% | 5.9% | moderate |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 45.5% | 90.9% | 9.1% | noisy |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.20..0.24 | 8.8% | 17.6% | 1.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.17 | 0.17..0.19 | 7.2% | 14.4% | 0.6% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.04 | 6.8% | 13.5% | 2.7% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.92 | 1.87..1.96 | 2.4% | 4.9% | 2.2% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.60 | 1.58..1.65 | 2.0% | 4.1% | 1.5% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.27 | 0.26..0.28 | 2.8% | 5.6% | 2.2% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 22.96 | 21.11..25.90 | 10.4% | 20.9% | 7.3% | moderate |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 16.26 | 16.23..16.69 | 1.4% | 2.8% | 0.2% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 2.74 | 2.69..2.77 | 1.5% | 3.0% | 0.5% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 150.0% | 300.0% | 0.0% | stable |
| Select → JSON Bytes / Large payload (~650KB) / resqlite selectBytes() | 0.28 | 0.26..0.29 | 5.6% | 11.1% | 2.2% | stable |
| Select → JSON Bytes / Large payload (~650KB) / resqlite selectBytes... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.05 | 470.0% | 940.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.04 | 0.04..0.19 | 178.0% | 356.1% | 2.4% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 40.0% | 80.0% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.32 | 0.32..0.34 | 4.4% | 8.7% | 1.3% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.05 | 0.05..0.05 | 2.8% | 5.7% | 0.0% | stable |
| Select → Maps / 10000 rows / resqlite select() | 3.62 | 3.60..3.79 | 2.7% | 5.4% | 0.4% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.53 | 0.53..0.57 | 3.6% | 7.1% | 0.8% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.21 | 0.18..0.24 | 14.4% | 28.8% | 11.6% | noisy |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.21 | 0.18..0.24 | 14.4% | 28.8% | 11.6% | noisy |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.53 | 0.49..0.58 | 8.5% | 17.0% | 2.7% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.53 | 0.49..0.58 | 8.5% | 17.0% | 2.7% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03..0.07 | 79.6% | 159.3% | 3.7% | moderate |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03..0.07 | 79.6% | 159.3% | 3.7% | moderate |
| Streaming / Invalidation Latency / resqlite | 0.06 | 0.05..0.07 | 20.7% | 41.4% | 13.8% | noisy |
| Streaming / Invalidation Latency / resqlite [main] | 0.06 | 0.05..0.07 | 20.7% | 41.4% | 13.8% | noisy |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows x 32K... | 2.80 | 2.62..3.08 | 8.1% | 16.1% | 6.4% | moderate |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows x 32K... | 2.80 | 2.62..3.08 | 8.1% | 16.1% | 6.4% | moderate |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged streams, 6... | 3.00 | 2.90..3.06 | 2.6% | 5.3% | 1.8% | stable |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged streams, 6... | 3.00 | 2.90..3.06 | 2.6% | 5.3% | 1.8% | stable |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 2.32 | 2.13..2.43 | 6.4% | 12.7% | 3.3% | moderate |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 2.32 | 2.13..2.43 | 6.4% | 12.7% | 3.3% | moderate |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.46 | 3.28..4.92 | 23.6% | 47.2% | 4.7% | moderate |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.46 | 3.28..4.92 | 23.6% | 47.2% | 4.7% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.86 | 1.61..3.40 | 48.4% | 96.8% | 5.6% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.86 | 1.61..3.40 | 48.4% | 96.8% | 5.6% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.65 | 6.54..10.07 | 26.5% | 53.1% | 1.3% | stable |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.65 | 6.54..10.07 | 26.5% | 53.1% | 1.3% | stable |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.22 | 0.18..0.23 | 12.7% | 25.3% | 5.9% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.22 | 0.18..0.23 | 12.7% | 25.3% | 5.9% | moderate |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.06..0.08 | 12.9% | 25.8% | 1.6% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.06 | 0.06..0.08 | 12.9% | 25.8% | 1.6% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.50 | 0.48..0.55 | 6.5% | 13.1% | 3.2% | moderate |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.50 | 0.48..0.55 | 6.5% | 13.1% | 3.2% | moderate |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.08 | 4.00..4.32 | 4.0% | 7.9% | 0.8% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.08 | 4.00..4.32 | 4.0% | 7.9% | 0.8% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.53 | 0.43..0.69 | 24.4% | 48.8% | 18.6% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.53 | 0.43..0.69 | 24.4% | 48.8% | 18.6% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.08 | 0.07..0.08 | 4.5% | 9.1% | 1.3% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.08 | 0.07..0.08 | 4.5% | 9.1% | 1.3% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.16 | 4.98..5.24 | 2.5% | 4.9% | 0.9% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.16 | 4.98..5.24 | 2.5% | 4.9% | 0.9% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.52 | 0.48..0.65 | 15.6% | 31.1% | 7.4% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.52 | 0.48..0.65 | 15.6% | 31.1% | 7.4% | moderate |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 0.90 | 0.88..0.94 | 3.0% | 6.0% | 1.2% | stable |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 0.90 | 0.88..0.94 | 3.0% | 6.0% | 1.2% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.06 | 0.05..0.07 | 15.0% | 30.0% | 5.0% | moderate |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.06 | 0.05..0.07 | 15.0% | 30.0% | 5.0% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.08 | 0.08..0.10 | 15.9% | 31.7% | 3.7% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.08 | 0.08..0.10 | 15.9% | 31.7% | 3.7% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.88 | 0.77..0.98 | 12.2% | 24.4% | 4.3% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.88 | 0.77..0.98 | 12.2% | 24.4% | 4.3% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.65 | 1.64..1.73 | 2.7% | 5.3% | 0.6% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.65 | 1.64..1.73 | 2.7% | 5.3% | 0.6% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.18..0.18 | 1.4% | 2.8% | 0.6% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.18..0.18 | 1.4% | 2.8% | 0.6% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.10 | 0.10..0.10 | 2.9% | 5.8% | 1.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.10 | 0.10..0.10 | 2.9% | 5.8% | 1.0% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 13.75 | 13.62..14.73 | 4.0% | 8.1% | 0.9% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 13.75 | 13.62..14.73 | 4.0% | 8.1% | 0.9% | stable |


## Comparison vs Previous Run

Previous: `2026-08-11T07-54-12-baseline-for-exp269.md` (cross-repeat aggregate medians)

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.02 | 0.01 | -0.01 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.00 | -0.01 | ±25% / ±0.02 ms | 25.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.03 | +0.01 | ±10% / ±0.02 ms | 1.9% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02 | +0.01 | ±10% / ±0.02 ms | 4.8% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.27 | 0.27 | +0.00 | ±10% / ±0.03 ms | 1.9% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.27 | 0.27 | +0.00 | ±10% / ±0.03 ms | 1.9% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.29 | 0.30 | +0.01 | ±10% / ±0.03 ms | 1.7% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.15 | 0.15 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.34 | 0.35 | +0.01 | ±10% / ±0.03 ms | 7.1% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.09 | 0.09 | +0.00 | ±11% / ±0.02 ms | 11.1% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.64 | 0.66 | +0.02 | ±10% / ±0.07 ms | 6.1% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.08 | 0.08 | +0.00 | ±10% / ±0.02 ms | 6.2% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.03 | -0.01 | ±10% / ±0.02 ms | 1.6% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±150% / ±0.02 ms | 150.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 108.61 | 109.51 | +0.89 | ±10% / ±10.95 ms | 1.7% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 240.84 | 243.58 | +2.74 | ±43% / ±105.43 ms | 43.3% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 223.98 | 224.13 | +0.15 | ±10% / ±22.41 ms | 2.1% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.36 | 14.60 | +0.24 | ±10% / ±1.46 ms | 0.8% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.36 | 14.60 | +0.24 | ±10% / ±1.46 ms | 0.8% | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 153377.00 | 439593.00 | +286216.00 | ±10% / ±43959.30 ms | 0.6% | stable | 🟢 Win (187%) |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01 | -0.01 | ±20% / ±0.02 ms | 20.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.02 | -0.01 | ±19% / ±0.02 ms | 19.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.02 | -0.01 | ±19% / ±0.02 ms | 19.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±36% / ±0.02 ms | 36.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±36% / ±0.02 ms | 36.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 3.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.20 | 0.20 | +0.00 | ±10% / ±0.02 ms | 3.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.20 | 0.20 | +0.00 | ±10% / ±0.02 ms | 3.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 5.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 5.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.32 | 0.33 | +0.00 | ±10% / ±0.03 ms | 2.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.89 | 1.93 | +0.05 | ±10% / ±0.19 ms | 1.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.89 | 1.93 | +0.05 | ±10% / ±0.19 ms | 1.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.05 | 0.05 | -0.00 | ±10% / ±0.02 ms | 1.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.27 | 0.26 | -0.00 | ±10% / ±0.03 ms | 1.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.27 | 0.26 | -0.00 | ±10% / ±0.03 ms | 1.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 3.63 | 3.64 | +0.01 | ±10% / ±0.36 ms | 0.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 24.97 | 23.51 | -1.46 | ±21% / ±5.22 ms | 10.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 24.97 | 23.51 | -1.46 | ±21% / ±5.22 ms | 10.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.55 | 0.54 | -0.01 | ±10% / ±0.05 ms | 0.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 2.75 | 2.69 | -0.06 | ±10% / ±0.27 ms | 2.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 2.75 | 2.69 | -0.06 | ±10% / ±0.27 ms | 2.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.61 | 0.64 | +0.03 | ±10% / ±0.06 ms | 1.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.96 | 3.93 | -0.03 | ±10% / ±0.40 ms | 1.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.96 | 3.93 | -0.03 | ±10% / ±0.40 ms | 1.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.10 | 0.11 | +0.00 | ±10% / ±0.02 ms | 1.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.52 | 0.52 | +0.00 | ±10% / ±0.05 ms | 2.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.52 | 0.52 | +0.00 | ±10% / ±0.05 ms | 2.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 9.19 | 9.38 | +0.19 | ±10% / ±0.94 ms | 3.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 46.47 | 46.54 | +0.07 | ±10% / ±4.65 ms | 0.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 46.47 | 46.54 | +0.07 | ±10% / ±4.65 ms | 0.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.08 | 1.08 | +0.00 | ±10% / ±0.11 ms | 2.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 5.66 | 5.89 | +0.23 | ±12% / ±0.71 ms | 7.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 5.66 | 5.89 | +0.23 | ±12% / ±0.71 ms | 7.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.02 | 0.02 | -0.01 | ±10% / ±0.02 ms | 5.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.10 | -0.00 | ±16% / ±0.02 ms | 16.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.11 | 0.10 | -0.00 | ±16% / ±0.02 ms | 16.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00 | -0.00 | ±25% / ±0.02 ms | 25.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.03 | +0.00 | ±24% / ±0.02 ms | 12.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.03 | +0.00 | ±24% / ±0.02 ms | 12.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.16 | 0.17 | +0.01 | ±10% / ±0.02 ms | 2.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.94 | 0.98 | +0.04 | ±10% / ±0.10 ms | 2.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.94 | 0.98 | +0.04 | ±10% / ±0.10 ms | 2.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 1.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.14 | 0.14 | +0.00 | ±10% / ±0.02 ms | 2.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.14 | 0.14 | +0.00 | ±10% / ±0.02 ms | 2.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 1.82 | 1.90 | +0.07 | ±10% / ±0.19 ms | 2.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.52 | 10.46 | -0.06 | ±10% / ±1.05 ms | 4.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.52 | 10.46 | -0.06 | ±10% / ±1.05 ms | 4.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.27 | 0.27 | +0.00 | ±10% / ±0.03 ms | 0.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.31 | 1.28 | -0.02 | ±10% / ±0.13 ms | 2.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.31 | 1.28 | -0.02 | ±10% / ±0.13 ms | 2.5% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 2.3% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.02 | 0.02 | +0.00 | ±19% / ±0.02 ms | 18.8% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.25 | 0.26 | +0.01 | ±10% / ±0.03 ms | 2.2% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 2.4% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.25 | 0.25 | +0.00 | ±10% / ±0.02 ms | 2.6% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 2.4% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.39 | 0.39 | +0.00 | ±10% / ±0.04 ms | 1.5% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.06 | 0.06 | -0.00 | ±10% / ±0.02 ms | 1.6% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.81 | 0.79 | -0.01 | ±10% / ±0.08 ms | 5.9% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.23 | 0.21 | -0.02 | ±10% / ±0.02 ms | 6.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.02 | -0.01 | ±68% / ±0.02 ms | 68.2% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02 | +0.00 | ±71% / ±0.02 ms | 70.6% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | -0.00 | ±45% / ±0.02 ms | 45.5% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.20 | +0.00 | ±10% / ±0.02 ms | 8.8% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.17 | 0.17 | -0.00 | ±10% / ±0.02 ms | 7.2% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 6.8% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.92 | 1.92 | -0.00 | ±10% / ±0.19 ms | 2.4% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.61 | 1.60 | -0.01 | ±10% / ±0.16 ms | 2.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.27 | 0.27 | +0.00 | ±10% / ±0.03 ms | 2.8% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 21.61 | 22.96 | +1.36 | ±22% / ±5.05 ms | 10.4% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 16.24 | 16.26 | +0.02 | ±10% / ±1.63 ms | 1.4% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 2.73 | 2.74 | +0.01 | ±10% / ±0.27 ms | 1.5% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±150% / ±0.02 ms | 150.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / Large payload (~650KB) / resqlite s... | 0.26 | 0.28 | +0.02 | ±10% / ±0.03 ms | 5.6% | stable | ⚪ Within noise |
| Select → JSON Bytes / Large payload (~650KB) / resqlite s... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | -0.01 | ±470% / ±0.05 ms | 470.0% | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.04 | 0.04 | +0.00 | ±178% / ±0.07 ms | 178.0% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±40% / ±0.02 ms | 40.0% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.31 | 0.32 | +0.01 | ±10% / ±0.03 ms | 4.4% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 2.8% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 3.57 | 3.62 | +0.05 | ±10% / ±0.36 ms | 2.7% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.53 | 0.53 | +0.00 | ±10% / ±0.05 ms | 3.6% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.21 | 0.21 | +0.00 | ±35% / ±0.07 ms | 14.4% | noisy | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.21 | 0.21 | +0.00 | ±35% / ±0.07 ms | 14.4% | noisy | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.54 | 0.53 | -0.01 | ±10% / ±0.05 ms | 8.5% | stable | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.54 | 0.53 | -0.01 | ±10% / ±0.05 ms | 8.5% | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | +0.00 | ±80% / ±0.02 ms | 79.6% | moderate | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03 | +0.00 | ±80% / ±0.02 ms | 79.6% | moderate | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.07 | 0.06 | -0.02 | ±41% / ±0.03 ms | 20.7% | noisy | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.07 | 0.06 | -0.02 | ±41% / ±0.03 ms | 20.7% | noisy | ⚪ Within noise |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 ... | 3.03 | 2.80 | -0.23 | ±19% / ±0.58 ms | 8.1% | moderate | ⚪ Within noise |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 ... | 3.03 | 2.80 | -0.23 | ±19% / ±0.58 ms | 8.1% | moderate | ⚪ Within noise |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged ... | 2.94 | 3.00 | +0.06 | ±10% / ±0.30 ms | 2.6% | stable | ⚪ Within noise |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged ... | 2.94 | 3.00 | +0.06 | ±10% / ±0.30 ms | 2.6% | stable | ⚪ Within noise |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 2.32 | 2.32 | +0.00 | ±10% / ±0.23 ms | 6.4% | moderate | ⚪ Within noise |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 2.32 | 2.32 | +0.00 | ±10% / ±0.23 ms | 6.4% | moderate | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.54 | 3.46 | -0.08 | ±24% / ±0.84 ms | 23.6% | moderate | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.54 | 3.46 | -0.08 | ±24% / ±0.84 ms | 23.6% | moderate | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.82 | 1.86 | +0.03 | ±48% / ±0.90 ms | 48.4% | moderate | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.82 | 1.86 | +0.03 | ±48% / ±0.90 ms | 48.4% | moderate | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.61 | 6.65 | +0.04 | ±27% / ±1.76 ms | 26.5% | stable | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.61 | 6.65 | +0.04 | ±27% / ±1.76 ms | 26.5% | stable | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.21 | 0.22 | +0.01 | ±18% / ±0.04 ms | 12.7% | moderate | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.21 | 0.22 | +0.01 | ±18% / ±0.04 ms | 12.7% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | +0.00 | ±13% / ±0.02 ms | 12.9% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | +0.00 | ±13% / ±0.02 ms | 12.9% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.50 | 0.50 | +0.00 | ±10% / ±0.05 ms | 6.5% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.50 | 0.50 | +0.00 | ±10% / ±0.05 ms | 6.5% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.01 | 4.08 | +0.06 | ±10% / ±0.41 ms | 4.0% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.01 | 4.08 | +0.06 | ±10% / ±0.41 ms | 4.0% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.51 | 0.53 | +0.03 | ±56% / ±0.30 ms | 24.4% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.51 | 0.53 | +0.03 | ±56% / ±0.30 ms | 24.4% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.08 | 0.08 | -0.00 | ±10% / ±0.02 ms | 4.5% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.08 | 0.08 | -0.00 | ±10% / ±0.02 ms | 4.5% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 5.16 | 5.16 | +0.00 | ±10% / ±0.52 ms | 2.5% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 5.16 | 5.16 | +0.00 | ±10% / ±0.52 ms | 2.5% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.50 | 0.52 | +0.02 | ±22% / ±0.12 ms | 15.6% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.50 | 0.52 | +0.02 | ±22% / ±0.12 ms | 15.6% | moderate | ⚪ Within noise |
| Write Performance / Concurrent Single Inserts (100 concur... | 0.89 | 0.90 | +0.01 | ±10% / ±0.09 ms | 3.0% | stable | ⚪ Within noise |
| Write Performance / Concurrent Single Inserts (100 concur... | 0.89 | 0.90 | +0.01 | ±10% / ±0.09 ms | 3.0% | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.06 | +0.00 | ±15% / ±0.02 ms | 15.0% | moderate | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.06 | +0.00 | ±15% / ±0.02 ms | 15.0% | moderate | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.09 | 0.08 | -0.01 | ±16% / ±0.02 ms | 15.9% | moderate | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.09 | 0.08 | -0.01 | ±16% / ±0.02 ms | 15.9% | moderate | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.90 | 0.88 | -0.02 | ±13% / ±0.12 ms | 12.2% | moderate | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.90 | 0.88 | -0.02 | ±13% / ±0.12 ms | 12.2% | moderate | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.65 | 1.65 | +0.01 | ±10% / ±0.17 ms | 2.7% | stable | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.65 | 1.65 | +0.01 | ±10% / ±0.17 ms | 2.7% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.18 | +0.00 | ±10% / ±0.02 ms | 1.4% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.18 | +0.00 | ±10% / ±0.02 ms | 1.4% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 2.9% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 2.9% | stable | ⚪ Within noise |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 13.50 | 13.75 | +0.24 | ±10% / ±1.37 ms | 4.0% | stable | ⚪ Within noise |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 13.50 | 13.75 | +0.24 | ±10% / ±1.37 ms | 4.0% | stable | ⚪ Within noise |

**Summary:** 1 wins, 0 regressions, 168 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

✅ **No regressions beyond noise.** 1 benchmarks improved.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 4231 | 4320 | +89 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 4042 | 4127 | +85 | ±100 | ⚪ Within noise |

**Granularity summary:** 0 fewer-re-emit, 0 more-re-emit, 6 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


