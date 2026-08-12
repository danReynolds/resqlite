# resqlite Benchmark Results

Generated: 2026-08-12T07:53:22.890738

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp270-parent-baseline`
- Repeats: `5`
- Runtime: `dart-vm / Dart 3.12.2`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `HEAD @ 1237587795be`
- Comparison baseline: `2026-08-12T10-15-00Z-exp269-opaque-work.md`
- Comparison mode: `automatic`
- Comparison baseline compatibility: `incompatible (automatic comparison skipped)`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.010 | 0.013 | 0.000 | 0.001 |
| sqlite3 select() | 0.015 | 0.017 | 0.015 | 0.017 |
| sqlite_async select() | 0.032 | 0.034 | 0.001 | 0.002 |
| drift select() | 0.037 | 0.045 | 0.001 | 0.002 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.037 | 0.041 | 0.005 | 0.006 |
| sqlite3 select() | 0.118 | 0.126 | 0.118 | 0.126 |
| sqlite_async select() | 0.123 | 0.125 | 0.009 | 0.010 |
| drift select() | 0.175 | 0.184 | 0.009 | 0.010 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.289 | 0.295 | 0.051 | 0.052 |
| sqlite3 select() | 1.123 | 1.178 | 1.123 | 1.178 |
| sqlite_async select() | 1.039 | 1.345 | 0.089 | 0.093 |
| drift select() | 1.546 | 1.598 | 0.087 | 0.090 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 3.205 | 8.743 | 0.508 | 0.982 |
| sqlite3 select() | 14.582 | 16.498 | 14.582 | 16.498 |
| sqlite_async select() | 12.054 | 14.237 | 0.915 | 2.154 |
| drift select() | 20.143 | 27.293 | 0.914 | 2.308 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row. The large-payload row isolates resqlite selectBytes because it guards the native bytes transfer policy without multiplying large JSON encoding work across every peer.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.027 | 0.028 | 0.017 | 0.018 |
| sqlite3 + jsonEncode | 0.032 | 0.033 | 0.032 | 0.033 |
| sqlite_async + jsonEncode | 0.049 | 0.055 | 0.018 | 0.018 |
| drift + jsonEncode | 0.053 | 0.056 | 0.017 | 0.018 |
| resqlite selectBytes() | 0.013 | 0.026 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.202 | 0.205 | 0.168 | 0.170 |
| sqlite3 + jsonEncode | 0.283 | 0.293 | 0.283 | 0.293 |
| sqlite_async + jsonEncode | 0.298 | 0.308 | 0.171 | 0.176 |
| drift + jsonEncode | 0.353 | 0.386 | 0.170 | 0.182 |
| resqlite selectBytes() | 0.040 | 0.043 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.841 | 1.886 | 1.584 | 1.606 |
| sqlite3 + jsonEncode | 2.694 | 5.680 | 2.694 | 5.680 |
| sqlite_async + jsonEncode | 2.608 | 5.129 | 1.600 | 2.325 |
| drift + jsonEncode | 3.176 | 6.178 | 1.590 | 3.326 |
| resqlite selectBytes() | 0.271 | 0.277 | 0.000 | 0.000 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.071 | 23.774 | 15.528 | 17.559 |
| sqlite3 + jsonEncode | 30.245 | 36.091 | 30.245 | 36.091 |
| sqlite_async + jsonEncode | 32.351 | 37.709 | 16.155 | 17.389 |
| drift + jsonEncode | 39.391 | 43.940 | 15.861 | 19.223 |
| resqlite selectBytes() | 2.826 | 2.901 | 0.001 | 0.002 |

### Large payload (~650KB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.240 | 0.274 | 0.000 | 0.001 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.086 | 0.087 | 0.024 | 0.024 |
| sqlite3 | 0.353 | 0.359 | 0.353 | 0.359 |
| sqlite_async | 0.378 | 0.456 | 0.033 | 0.041 |
| drift | 0.615 | 0.677 | 0.034 | 0.038 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.785 | 0.807 | 0.225 | 0.230 |
| sqlite3 | 3.373 | 3.995 | 3.373 | 3.995 |
| sqlite_async | 3.017 | 3.600 | 0.242 | 0.262 |
| drift | 4.543 | 5.976 | 0.231 | 0.239 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.361 | 0.702 | 0.061 | 0.068 |
| sqlite3 | 1.445 | 1.456 | 1.445 | 1.456 |
| sqlite_async | 1.350 | 1.646 | 0.083 | 0.084 |
| drift | 1.877 | 2.165 | 0.082 | 0.083 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.241 | 0.250 | 0.062 | 0.064 |
| sqlite3 | 0.993 | 1.041 | 0.993 | 1.041 |
| sqlite_async | 0.920 | 0.937 | 0.082 | 0.083 |
| drift | 1.432 | 1.546 | 0.082 | 0.086 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.244 | 0.255 | 0.061 | 0.063 |
| sqlite3 | 0.966 | 1.005 | 0.966 | 1.005 |
| sqlite_async | 0.937 | 0.965 | 0.082 | 0.085 |
| drift | 1.400 | 1.695 | 0.080 | 0.081 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.010 | 0.010 | 0.000 | 0.000 |
| sqlite3 | 0.015 | 0.016 | 0.015 | 0.016 |
| sqlite_async | 0.030 | 0.031 | 0.001 | 0.001 |
| drift | 0.036 | 0.036 | 0.001 | 0.001 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.022 | 0.022 | 0.002 | 0.003 |
| sqlite3 | 0.060 | 0.063 | 0.060 | 0.063 |
| sqlite_async | 0.071 | 0.076 | 0.004 | 0.004 |
| drift | 0.101 | 0.105 | 0.004 | 0.004 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.037 | 0.038 | 0.005 | 0.005 |
| sqlite3 | 0.116 | 0.127 | 0.116 | 0.127 |
| sqlite_async | 0.121 | 0.124 | 0.007 | 0.008 |
| drift | 0.179 | 0.184 | 0.007 | 0.008 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.154 | 0.161 | 0.026 | 0.026 |
| sqlite3 | 0.557 | 0.589 | 0.557 | 0.589 |
| sqlite_async | 0.515 | 0.523 | 0.035 | 0.036 |
| drift | 0.771 | 0.784 | 0.035 | 0.035 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.295 | 0.299 | 0.052 | 0.053 |
| sqlite3 | 1.100 | 1.149 | 1.100 | 1.149 |
| sqlite_async | 1.008 | 1.019 | 0.070 | 0.072 |
| drift | 1.517 | 1.537 | 0.069 | 0.070 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.593 | 0.608 | 0.108 | 0.109 |
| sqlite3 | 2.286 | 2.772 | 2.286 | 2.772 |
| sqlite_async | 2.118 | 2.466 | 0.145 | 0.147 |
| drift | 3.208 | 3.656 | 0.144 | 0.151 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.733 | 5.606 | 0.265 | 0.447 |
| sqlite3 | 5.932 | 7.741 | 5.932 | 7.741 |
| sqlite_async | 5.209 | 5.714 | 0.352 | 0.377 |
| drift | 8.170 | 8.243 | 0.347 | 0.355 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.154 | 9.088 | 0.514 | 0.977 |
| sqlite3 | 13.933 | 17.196 | 13.933 | 17.196 |
| sqlite_async | 12.077 | 12.876 | 0.745 | 0.800 |
| drift | 17.923 | 24.352 | 0.714 | 2.075 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 7.957 | 14.913 | 1.061 | 3.059 |
| sqlite3 | 30.463 | 39.500 | 30.463 | 39.500 |
| sqlite_async | 34.493 | 38.095 | 1.455 | 2.752 |
| drift | 51.098 | 65.077 | 1.441 | 3.429 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.026 | 0.027 | 0.026 | 0.027 |
| sqlite3 + jsonEncode | 0.031 | 0.033 | 0.031 | 0.033 |
| sqlite_async + jsonEncode | 0.050 | 0.060 | 0.050 | 0.060 |
| drift + jsonEncode | 0.054 | 0.057 | 0.054 | 0.057 |
| resqlite selectBytes() | 0.011 | 0.034 | 0.011 | 0.034 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.101 | 0.102 | 0.101 | 0.102 |
| sqlite3 + jsonEncode | 0.136 | 0.146 | 0.136 | 0.146 |
| sqlite_async + jsonEncode | 0.155 | 0.163 | 0.155 | 0.163 |
| drift + jsonEncode | 0.182 | 0.217 | 0.182 | 0.217 |
| resqlite selectBytes() | 0.026 | 0.030 | 0.026 | 0.030 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.198 | 0.203 | 0.198 | 0.203 |
| sqlite3 + jsonEncode | 0.267 | 0.306 | 0.267 | 0.306 |
| sqlite_async + jsonEncode | 0.271 | 0.274 | 0.271 | 0.274 |
| drift + jsonEncode | 0.329 | 0.356 | 0.329 | 0.356 |
| resqlite selectBytes() | 0.034 | 0.035 | 0.034 | 0.035 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.913 | 1.482 | 0.913 | 1.482 |
| sqlite3 + jsonEncode | 1.312 | 2.303 | 1.312 | 2.303 |
| sqlite_async + jsonEncode | 1.266 | 1.520 | 1.266 | 1.520 |
| drift + jsonEncode | 1.646 | 2.176 | 1.646 | 2.176 |
| resqlite selectBytes() | 0.137 | 0.139 | 0.137 | 0.139 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.844 | 4.170 | 1.844 | 4.170 |
| sqlite3 + jsonEncode | 3.071 | 4.553 | 3.071 | 4.553 |
| sqlite_async + jsonEncode | 2.661 | 4.005 | 2.661 | 4.005 |
| drift + jsonEncode | 3.207 | 5.600 | 3.207 | 5.600 |
| resqlite selectBytes() | 0.268 | 0.272 | 0.268 | 0.272 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.867 | 9.120 | 3.867 | 9.120 |
| sqlite3 + jsonEncode | 5.758 | 11.586 | 5.758 | 11.586 |
| sqlite_async + jsonEncode | 5.625 | 10.849 | 5.625 | 10.849 |
| drift + jsonEncode | 6.299 | 9.581 | 6.299 | 9.581 |
| resqlite selectBytes() | 0.508 | 0.528 | 0.508 | 0.528 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 9.910 | 12.866 | 9.910 | 12.866 |
| sqlite3 + jsonEncode | 14.549 | 18.913 | 14.549 | 18.913 |
| sqlite_async + jsonEncode | 14.478 | 18.360 | 14.478 | 18.360 |
| drift + jsonEncode | 16.811 | 20.293 | 16.811 | 20.293 |
| resqlite selectBytes() | 1.263 | 1.323 | 1.263 | 1.323 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 23.238 | 25.340 | 23.238 | 25.340 |
| sqlite3 + jsonEncode | 29.541 | 36.465 | 29.541 | 36.465 |
| sqlite_async + jsonEncode | 32.379 | 34.367 | 32.379 | 34.367 |
| drift + jsonEncode | 38.617 | 42.996 | 38.617 | 42.996 |
| resqlite selectBytes() | 2.596 | 2.642 | 2.596 | 2.642 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 45.039 | 48.507 | 45.039 | 48.507 |
| sqlite3 + jsonEncode | 66.284 | 70.702 | 66.284 | 70.702 |
| sqlite_async + jsonEncode | 68.275 | 72.791 | 68.275 | 72.791 |
| drift + jsonEncode | 84.186 | 96.666 | 84.186 | 96.666 |
| resqlite selectBytes() | 5.535 | 6.831 | 5.535 | 6.831 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.24 | 0.29 | 0.24 |
| sqlite_async | 0.94 | 0.97 | 0.94 |
| drift | 1.47 | 1.49 | 1.47 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.25 | 0.26 | 0.13 |
| sqlite_async | 1.38 | 1.64 | 0.69 |
| drift | 2.67 | 3.01 | 1.34 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.31 | 0.35 | 0.08 |
| sqlite_async | 2.29 | 2.83 | 0.57 |
| drift | 5.47 | 5.96 | 1.37 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.61 | 1.03 | 0.08 |
| sqlite_async | 4.82 | 5.47 | 0.60 |
| drift | 10.94 | 11.58 | 1.37 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 164594 |
| resqlite per query | 0.006 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 164594 | 155918..173913 | 5.5 | 17.0 |
| sqlite3 | 166219 | 163678..168936 | 1.6 | 4.6 |
| sqlite_async | 49848 | 48812..49974 | 1.2 | 6.3 |
| drift | 47960 | 47632..48107 | 0.5 | 1.3 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 13.367 | 13.787 | 13.367 | 13.787 |
| sqlite_async | 36.285 | 37.802 | 36.285 | 37.802 |
| drift | 53.268 | 54.533 | 53.268 | 54.533 |
| sqlite3 (no cache) | 23.618 | 23.894 | 23.618 | 23.894 |
| sqlite3 (cached stmt) | 24.125 | 24.648 | 24.125 | 24.648 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.494 | 2.283 | 1.494 | 2.283 |
| sqlite3 execute() | 0.943 | 1.667 | 0.943 | 1.667 |
| sqlite_async execute() | 2.994 | 3.659 | 2.994 | 3.659 |
| drift execute() | 2.758 | 3.475 | 2.758 | 3.475 |

### Concurrent Single Inserts (100 concurrent)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite concurrent execute() | 0.846 | 1.263 | 0.846 | 1.263 |
| sqlite3 concurrent execute() | 0.908 | 1.586 | 0.908 | 1.586 |
| sqlite_async concurrent execute() | 2.606 | 3.415 | 2.606 | 3.415 |
| drift concurrent execute() | 1.634 | 2.307 | 1.634 | 2.307 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.050 | 0.053 | 0.050 | 0.053 |
| sqlite3 executeBatch() | 0.047 | 0.048 | 0.047 | 0.048 |
| sqlite_async executeBatch() | 0.090 | 0.095 | 0.090 | 0.095 |
| drift executeBatch() | 0.110 | 0.115 | 0.110 | 0.115 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.394 | 0.407 | 0.394 | 0.407 |
| sqlite3 executeBatch() | 0.425 | 0.435 | 0.425 | 0.435 |
| sqlite_async executeBatch() | 0.502 | 0.513 | 0.502 | 0.513 |
| drift executeBatch() | 0.631 | 0.644 | 0.631 | 0.644 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 3.627 | 4.347 | 3.627 | 4.347 |
| sqlite3 executeBatch() | 3.981 | 4.158 | 3.981 | 4.158 |
| sqlite_async executeBatch() | 4.564 | 5.266 | 4.564 | 5.266 |
| drift executeBatch() | 6.078 | 8.276 | 6.078 | 8.276 |

### Wide Batch Insert (10000 rows x 20 params)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 13.077 | 25.335 | 13.077 | 25.335 |
| sqlite3 executeBatch() | 19.477 | 21.833 | 19.477 | 21.833 |
| sqlite_async executeBatch() | 22.195 | 26.261 | 22.195 | 26.261 |
| drift executeBatch() | 25.215 | 28.831 | 25.215 | 28.831 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.046 | 0.052 | 0.046 | 0.052 |
| sqlite_async writeTransaction() | 0.080 | 0.086 | 0.080 | 0.086 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.059 | 0.061 | 0.059 | 0.061 |
| resqlite tx.execute() loop | 0.403 | 0.504 | 0.403 | 0.504 |
| sqlite_async tx.execute() loop | 0.967 | 1.134 | 0.967 | 1.134 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.395 | 0.407 | 0.395 | 0.407 |
| resqlite tx.execute() loop | 4.797 | 5.198 | 4.797 | 5.198 |
| sqlite_async tx.execute() loop | 9.977 | 12.074 | 9.977 | 12.074 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.096 | 0.100 | 0.096 | 0.100 |
| sqlite_async tx.getAll() | 0.205 | 0.225 | 0.205 | 0.225 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.168 | 0.175 | 0.168 | 0.175 |
| sqlite_async tx.getAll() | 0.360 | 0.385 | 0.360 | 0.385 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 0.811 | 0.860 | 0.811 | 0.860 |
| resqlite nested transaction() depth=5 | 0.072 | 0.083 | 0.072 | 0.083 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.026 | 0.028 | 0.026 | 0.028 |
| sqlite_async watch() | 0.104 | 0.118 | 0.104 | 0.118 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.046 | 0.091 | 0.046 | 0.091 |
| sqlite_async | 0.068 | 0.077 | 0.068 | 0.077 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.191 | 0.272 | 0.191 | 0.272 |
| sqlite_async | 0.524 | 1.061 | 0.524 | 1.061 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.899 | 2.427 | 1.899 | 2.427 |

### Long-Payload Unchanged Fanout (8 streams, 64 rows x 32KB TEXT + 32KB BLOB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.684 | 3.824 | 2.684 | 3.824 |

### Long-Text 32KB Unchanged Fanout (8 unchanged streams, 64 rows x 32KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.462 | 3.551 | 2.462 | 3.551 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.202 | 0.252 | 0.202 | 0.252 |
| sqlite_async | 0.230 | 0.314 | 0.230 | 0.314 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.325 | 1.325 | 1.325 | 1.325 |
| sqlite_async | 7.201 | 7.201 | 7.201 | 7.201 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.088 | 3.584 | 3.088 | 3.584 |
| sqlite_async | 5.156 | 6.057 | 5.156 | 6.057 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.470 | 0.642 | 0.470 | 0.642 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 5.789 | 6.285 | 5.789 | 6.285 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. For resqlite, this emission metric can reflect writer-side column-level invalidation, experiment 075's native result-hash short-circuit, or both. Use A11c (Many-Streams Writer Throughput) when the question is specifically writer-side dispatch elision.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 68.8 | 0.000 |
| sqlite_async | 3801 | 1076.6 | 0.937 |
| drift | 5000 | 1018.2 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 68.8 | 0.000 |
| sqlite_async | 4058 | 1110.5 | 0.937 |
| drift | 5000 | 1051.4 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 215.23 | 218.86 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 437.18 | 442.96 | 0.00 | 0.00 | 1107 | 3 |
| drift stream() | 548.59 | 559.15 | 0.00 | 0.00 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.019 | 0.030 | 0.000 | 0.000 |
| sqlite3 | 0.019 | 0.023 | 0.019 | 0.023 |
| sqlite_async | 0.040 | 0.057 | 0.000 | 0.000 |
| drift | 0.036 | 0.047 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.015 | 0.020 | 0.000 | 0.000 |
| sqlite3 | 0.012 | 0.015 | 0.012 | 0.015 |
| sqlite_async | 0.032 | 0.046 | 0.000 | 0.000 |
| drift | 0.029 | 0.036 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.018 | 0.028 | 0.000 | 0.000 |
| sqlite3 | 0.031 | 0.033 | 0.031 | 0.033 |
| sqlite_async | 0.059 | 0.071 | 0.000 | 0.000 |
| drift | 0.052 | 0.056 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.006 | 0.012 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.021 | 0.026 | 0.000 | 0.000 |
| drift | 0.019 | 0.023 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.037 | 0.038 | 0.001 | 0.001 |
| sqlite3 | 0.071 | 0.073 | 0.071 | 0.073 |
| sqlite_async | 0.083 | 0.088 | 0.001 | 0.001 |
| drift | 0.092 | 0.098 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 108.514 | 109.924 | 0.000 | 0.000 | 0 |
| sqlite_async | 214.671 | 217.517 | 0.000 | 0.001 | 40 |
| drift | 220.473 | 221.770 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 239.18 | 239.18 | 0.00 | 0.00 | 13.46 | 225.72 | 0 |
| sqlite_async | 483.03 | 483.03 | 0.01 | 0.01 | 24.10 | 458.94 | 1184 |
| drift | 1688.22 | 1688.22 | 0.06 | 0.06 | 13.75 | 1675.24 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 1.42 | 12.84 | 0.00..12.66 | ±6.33 |
| sqlite3 select() | 4.45 | 9.23 | 0.00..8.70 | ±4.35 |
| sqlite_async select() | 1.00 | 1.78 | 1.00..1.00 | ±0.00 |
| drift select() | 9.25 | 73.95 | 2.20..19.59 | ±8.70 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 20.08 | 0.00..1.50 | ±0.75 |
| resqlite + jsonEncode | 0.50 | 79.81 | 0.00..26.89 | ±13.45 |
| sqlite3 + jsonEncode | 0.00 | 9.59 | 0.00..6.00 | ±3.00 |
| sqlite_async + jsonEncode | 0.00 | 35.23 | 0.00..3.52 | ±1.76 |
| drift + jsonEncode | 0.00 | 10.83 | 0.00..4.58 | ±2.29 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.19 | 7.94 | 0.00..0.97 | ±0.48 |
| sqlite3 executeBatch() | 0.00 | 0.80 | 0.00..0.05 | ±0.02 |
| sqlite_async executeBatch() | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| drift batch() | 0.52 | 4.52 | 0.02..2.52 | ±1.25 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.28 | 0.06..0.09 | ±0.02 |
| sqlite_async watch() | 0.00 | 0.50 | 0.00..0.02 | ±0.01 |

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
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02..0.02 | 2.6% | 5.3% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.25 | 0.24..0.25 | 2.0% | 4.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.25 | 0.24..0.25 | 2.0% | 4.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.28 | 0.25..0.28 | 5.4% | 10.7% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.14 | 0.13..0.14 | 3.6% | 7.1% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.32 | 0.31..0.34 | 4.7% | 9.4% | 3.1% | moderate |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.08 | 0.08..0.08 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.59 | 0.58..0.61 | 2.5% | 5.1% | 1.7% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.07 | 0.07..0.08 | 7.1% | 14.3% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.04 | 3.8% | 7.7% | 2.6% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 150.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 108.56 | 108.50..109.87 | 0.6% | 1.3% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 231.78 | 231.22..239.18 | 1.7% | 3.4% | 0.2% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 218.28 | 215.23..223.01 | 1.8% | 3.6% | 1.4% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 13.37 | 13.25..13.82 | 2.2% | 4.3% | 0.9% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 13.37 | 13.25..13.82 | 2.2% | 4.3% | 0.9% | stable |
| Point Query Throughput / resqlite qps | 168401.00 | 164594.00..173740.00 | 2.7% | 5.4% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.01 | 20.0% | 40.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.04 | 16.7% | 33.3% | 3.7% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.04 | 16.7% | 33.3% | 3.7% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.01 | 8.3% | 16.7% | 8.3% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.01 | 8.3% | 16.7% | 8.3% | noisy |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.04..0.04 | 5.3% | 10.5% | 2.6% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.20 | 0.19..0.21 | 3.0% | 6.1% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.20 | 0.19..0.21 | 3.0% | 6.1% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.04 | 0.03..0.04 | 9.7% | 19.4% | 2.8% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.04 | 0.03..0.04 | 9.7% | 19.4% | 2.8% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.30 | 0.29..0.31 | 2.2% | 4.3% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.79 | 1.78..1.85 | 2.0% | 4.0% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.79 | 1.78..1.85 | 2.0% | 4.0% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.05 | 0.05..0.05 | 1.9% | 3.8% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.27 | 0.26..0.29 | 4.8% | 9.7% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.27 | 0.26..0.29 | 4.8% | 9.7% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 3.34 | 3.15..3.43 | 4.1% | 8.2% | 1.3% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 22.46 | 20.39..23.24 | 6.3% | 12.7% | 3.5% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 22.46 | 20.39..23.24 | 6.3% | 12.7% | 3.5% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.54 | 0.51..0.54 | 2.5% | 5.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 2.69 | 2.60..3.05 | 8.4% | 16.8% | 3.3% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 2.69 | 2.60..3.05 | 8.4% | 16.8% | 3.3% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.59 | 0.57..0.60 | 2.4% | 4.9% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.79 | 3.70..3.89 | 2.5% | 5.0% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.79 | 3.70..3.89 | 2.5% | 5.0% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.11 | 0.10..0.11 | 2.3% | 4.6% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.53 | 0.50..0.56 | 5.0% | 9.9% | 3.2% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.53 | 0.50..0.56 | 5.0% | 9.9% | 3.2% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 8.28 | 7.96..8.99 | 6.2% | 12.5% | 3.9% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 45.04 | 42.63..46.83 | 4.7% | 9.3% | 2.5% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 45.04 | 42.63..46.83 | 4.7% | 9.3% | 2.5% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.06 | 1.02..1.09 | 3.2% | 6.4% | 2.8% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 5.54 | 5.26..5.68 | 3.8% | 7.6% | 2.6% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 5.54 | 5.26..5.68 | 3.8% | 7.6% | 2.6% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.02 | 0.02..0.03 | 6.8% | 13.6% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10..0.11 | 4.3% | 8.7% | 2.9% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.10 | 0.10..0.11 | 4.3% | 8.7% | 2.9% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.00 | 16.7% | 33.3% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.02..0.03 | 3.8% | 7.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.02..0.03 | 3.8% | 7.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.16 | 0.15..0.16 | 1.9% | 3.8% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.93 | 0.91..0.95 | 1.9% | 3.9% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.93 | 0.91..0.95 | 1.9% | 3.9% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.03 | 0.03..0.03 | 1.9% | 3.8% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.14 | 0.13..0.15 | 6.6% | 13.1% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.14 | 0.13..0.15 | 6.6% | 13.1% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 1.65 | 1.64..1.73 | 2.9% | 5.8% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 10.24 | 9.57..11.30 | 8.4% | 16.9% | 3.2% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 10.24 | 9.57..11.30 | 8.4% | 16.9% | 3.2% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.26 | 0.26..0.27 | 1.7% | 3.5% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 1.28 | 1.24..1.35 | 4.2% | 8.4% | 3.1% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 1.28 | 1.24..1.35 | 4.2% | 8.4% | 3.1% | moderate |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.09 | 0.08..0.15 | 37.6% | 75.3% | 4.5% | moderate |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.02 | 0.02..0.09 | 129.2% | 258.3% | 4.2% | moderate |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.25 | 0.24..0.26 | 2.8% | 5.6% | 2.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.06 | 0.06..0.06 | 2.4% | 4.8% | 1.6% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.24 | 0.23..0.25 | 2.7% | 5.3% | 1.2% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.06 | 0.06..0.06 | 1.6% | 3.2% | 1.6% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.37 | 0.36..0.39 | 3.9% | 7.8% | 0.5% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.06 | 0.06..0.06 | 2.4% | 4.8% | 1.6% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.78 | 0.76..0.80 | 2.9% | 5.9% | 2.4% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.22 | 0.22..0.23 | 3.1% | 6.3% | 2.7% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.06 | 57.4% | 114.8% | 3.7% | moderate |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02..0.04 | 58.8% | 117.6% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.01 | 22.7% | 45.5% | 9.1% | noisy |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.20..0.21 | 5.1% | 10.3% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.16 | 0.16..0.17 | 3.4% | 6.7% | 0.6% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.04 | 6.4% | 12.8% | 2.6% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.81 | 1.78..1.84 | 1.9% | 3.8% | 1.7% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.55 | 1.53..1.58 | 1.6% | 3.2% | 1.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.27 | 0.26..0.28 | 3.7% | 7.4% | 1.1% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.25 | 19.61..23.51 | 9.6% | 19.2% | 3.1% | moderate |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 15.99 | 15.49..16.41 | 2.9% | 5.7% | 2.6% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 2.72 | 2.58..3.00 | 7.7% | 15.5% | 4.0% | moderate |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / Large payload (~650KB) / resqlite selectBytes() | 0.24 | 0.23..0.28 | 11.0% | 22.1% | 4.6% | moderate |
| Select → JSON Bytes / Large payload (~650KB) / resqlite selectBytes... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.06 | 240.0% | 480.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.04 | 0.04..0.15 | 152.7% | 305.4% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 30.0% | 60.0% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.30 | 0.29..0.35 | 10.6% | 21.1% | 1.7% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.05 | 0.05..0.06 | 4.8% | 9.6% | 1.9% | stable |
| Select → Maps / 10000 rows / resqlite select() | 3.21 | 3.13..3.32 | 3.1% | 6.1% | 1.8% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.51 | 0.50..0.53 | 3.1% | 6.3% | 1.0% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.17 | 0.16..0.20 | 11.7% | 23.5% | 1.8% | stable |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.17 | 0.16..0.20 | 11.7% | 23.5% | 1.8% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.47 | 0.46..0.48 | 2.2% | 4.5% | 0.9% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.47 | 0.46..0.48 | 2.2% | 4.5% | 0.9% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03..0.07 | 74.1% | 148.1% | 7.4% | moderate |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03..0.07 | 74.1% | 148.1% | 7.4% | moderate |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.04..0.07 | 29.8% | 59.6% | 2.1% | stable |
| Streaming / Invalidation Latency / resqlite [main] | 0.05 | 0.04..0.07 | 29.8% | 59.6% | 2.1% | stable |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows x 32K... | 2.68 | 2.53..3.02 | 9.1% | 18.2% | 3.3% | moderate |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows x 32K... | 2.68 | 2.53..3.02 | 9.1% | 18.2% | 3.3% | moderate |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged streams, 6... | 2.54 | 2.46..2.80 | 6.6% | 13.3% | 3.0% | moderate |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged streams, 6... | 2.54 | 2.46..2.80 | 6.6% | 13.3% | 3.0% | moderate |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 1.69 | 1.46..2.15 | 20.4% | 40.9% | 12.4% | noisy |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 1.69 | 1.46..2.15 | 20.4% | 40.9% | 12.4% | noisy |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.17 | 3.07..3.43 | 5.7% | 11.4% | 2.7% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.17 | 3.07..3.43 | 5.7% | 11.4% | 2.7% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.75 | 1.32..2.91 | 45.3% | 90.6% | 22.8% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.75 | 1.32..2.91 | 45.3% | 90.6% | 22.8% | noisy |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 5.85 | 5.79..6.69 | 7.7% | 15.3% | 1.1% | stable |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 5.85 | 5.79..6.69 | 7.7% | 15.3% | 1.1% | stable |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.19 | 0.19..0.22 | 7.6% | 15.2% | 1.0% | stable |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.19 | 0.19..0.22 | 7.6% | 15.2% | 1.0% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.05 | 0.05..0.05 | 2.9% | 5.9% | 2.0% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.05 | 0.05..0.05 | 2.9% | 5.9% | 2.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.40 | 0.39..0.42 | 3.5% | 7.1% | 0.8% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.40 | 0.39..0.42 | 3.5% | 7.1% | 0.8% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.70 | 3.63..3.95 | 4.3% | 8.7% | 0.2% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.70 | 3.63..3.95 | 4.3% | 8.7% | 0.2% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.51 | 0.40..0.56 | 15.0% | 30.0% | 8.0% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.51 | 0.40..0.56 | 15.0% | 30.0% | 8.0% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.06..0.07 | 8.5% | 16.9% | 1.5% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.06..0.07 | 8.5% | 16.9% | 1.5% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 4.80 | 4.75..4.97 | 2.2% | 4.4% | 0.9% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 4.80 | 4.75..4.97 | 2.2% | 4.4% | 0.9% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.40 | 0.40..0.42 | 3.0% | 6.0% | 1.5% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.40 | 0.40..0.42 | 3.0% | 6.0% | 1.5% | stable |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 0.83 | 0.80..0.85 | 2.8% | 5.6% | 1.4% | stable |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 0.83 | 0.80..0.85 | 2.8% | 5.6% | 1.4% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.04..0.05 | 8.7% | 17.4% | 6.5% | moderate |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.04..0.05 | 8.7% | 17.4% | 6.5% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.07 | 0.06..0.10 | 29.2% | 58.3% | 18.1% | noisy |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.07 | 0.06..0.10 | 29.2% | 58.3% | 18.1% | noisy |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.82 | 0.69..0.94 | 15.2% | 30.3% | 1.7% | stable |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.82 | 0.69..0.94 | 15.2% | 30.3% | 1.7% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.50 | 1.46..1.58 | 4.1% | 8.2% | 3.1% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.50 | 1.46..1.58 | 4.1% | 8.2% | 3.1% | moderate |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.17 | 0.16..0.18 | 5.7% | 11.3% | 1.8% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.17 | 0.16..0.18 | 5.7% | 11.3% | 1.8% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.10 | 0.09..0.10 | 5.2% | 10.4% | 4.2% | moderate |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.10 | 0.09..0.10 | 5.2% | 10.4% | 4.2% | moderate |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 13.08 | 12.39..13.83 | 5.5% | 11.0% | 2.3% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 13.08 | 12.39..13.83 | 5.5% | 11.0% | 2.3% | stable |


## Comparison

Automatic comparison skipped because `2026-08-12T10-15-00Z-exp269-opaque-work.md` was not captured in a compatible environment:
- baseline sidecar is missing environment metadata

Use `--compare-to=benchmark/results/2026-08-12T10-15-00Z-exp269-opaque-work.md` to run an explicit reference comparison anyway.


