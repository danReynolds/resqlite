# resqlite Benchmark Results

Generated: 2026-06-11T10:19:38.500874

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp162-concurrent-reads-pool-scaling`
- Repeats: `5`
- Runtime: `dart-runtime / Dart 3.12.2`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `exp-162-concurrent-reads-pool-scaling @ 2805504a903d (dirty)`
- Comparison baseline: `2026-06-09T22-41-01-exp159-writer-pipelining.md`
- Comparison mode: `automatic`
- Comparison baseline compatibility: `incompatible (automatic comparison skipped)`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.011 | 0.012 | 0.000 | 0.000 |
| sqlite3 select() | 0.016 | 0.017 | 0.016 | 0.017 |
| sqlite_async select() | 0.034 | 0.060 | 0.002 | 0.003 |
| drift select() | 0.039 | 0.049 | 0.001 | 0.002 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.042 | 0.044 | 0.005 | 0.006 |
| sqlite3 select() | 0.122 | 0.137 | 0.122 | 0.137 |
| sqlite_async select() | 0.132 | 0.140 | 0.010 | 0.011 |
| drift select() | 0.182 | 0.219 | 0.010 | 0.012 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.347 | 0.393 | 0.052 | 0.058 |
| sqlite3 select() | 1.196 | 1.276 | 1.196 | 1.276 |
| sqlite_async select() | 1.071 | 1.263 | 0.094 | 0.102 |
| drift select() | 1.719 | 2.088 | 0.101 | 0.107 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.325 | 11.382 | 0.534 | 0.892 |
| sqlite3 select() | 15.526 | 18.781 | 15.526 | 18.781 |
| sqlite_async select() | 13.810 | 18.127 | 0.969 | 1.760 |
| drift select() | 23.967 | 32.211 | 1.080 | 2.853 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.032 | 0.036 | 0.016 | 0.019 |
| sqlite3 + jsonEncode | 0.031 | 0.033 | 0.031 | 0.033 |
| sqlite_async + jsonEncode | 0.050 | 0.054 | 0.016 | 0.017 |
| drift + jsonEncode | 0.076 | 0.100 | 0.018 | 0.023 |
| resqlite selectBytes() | 0.013 | 0.020 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.202 | 0.227 | 0.157 | 0.171 |
| sqlite3 + jsonEncode | 0.265 | 0.304 | 0.265 | 0.304 |
| sqlite_async + jsonEncode | 0.285 | 0.323 | 0.156 | 0.175 |
| drift + jsonEncode | 0.333 | 0.354 | 0.154 | 0.163 |
| resqlite selectBytes() | 0.049 | 0.076 | 0.000 | 0.001 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.764 | 1.950 | 1.457 | 1.588 |
| sqlite3 + jsonEncode | 2.732 | 5.777 | 2.732 | 5.777 |
| sqlite_async + jsonEncode | 2.579 | 5.588 | 1.531 | 2.420 |
| drift + jsonEncode | 3.182 | 5.808 | 1.530 | 2.198 |
| resqlite selectBytes() | 0.359 | 0.431 | 0.000 | 0.002 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 22.211 | 27.841 | 16.179 | 18.717 |
| sqlite3 + jsonEncode | 34.141 | 39.140 | 34.141 | 39.140 |
| sqlite_async + jsonEncode | 30.490 | 37.744 | 15.843 | 18.973 |
| drift + jsonEncode | 43.399 | 46.205 | 15.781 | 23.261 |
| resqlite selectBytes() | 4.162 | 4.869 | 0.005 | 0.008 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.093 | 0.101 | 0.023 | 0.026 |
| sqlite3 | 0.353 | 0.389 | 0.353 | 0.389 |
| sqlite_async | 0.634 | 3.538 | 0.040 | 0.489 |
| drift | 0.618 | 1.446 | 0.036 | 0.061 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.874 | 1.005 | 0.224 | 0.253 |
| sqlite3 | 3.485 | 4.302 | 3.485 | 4.302 |
| sqlite_async | 3.099 | 3.757 | 0.248 | 0.271 |
| drift | 4.932 | 6.560 | 0.251 | 0.285 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.496 | 0.539 | 0.062 | 0.068 |
| sqlite3 | 1.608 | 1.961 | 1.608 | 1.961 |
| sqlite_async | 1.416 | 1.746 | 0.086 | 0.099 |
| drift | 2.030 | 2.559 | 0.086 | 0.098 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.258 | 0.264 | 0.060 | 0.062 |
| sqlite3 | 1.068 | 1.118 | 1.068 | 1.118 |
| sqlite_async | 1.003 | 1.054 | 0.088 | 0.092 |
| drift | 1.514 | 1.803 | 0.086 | 0.094 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.260 | 0.286 | 0.061 | 0.063 |
| sqlite3 | 0.998 | 1.093 | 0.998 | 1.093 |
| sqlite_async | 0.980 | 1.167 | 0.084 | 0.094 |
| drift | 1.544 | 1.714 | 0.090 | 0.099 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.011 | 0.014 | 0.000 | 0.001 |
| sqlite3 | 0.016 | 0.016 | 0.016 | 0.016 |
| sqlite_async | 0.030 | 0.032 | 0.001 | 0.001 |
| drift | 0.038 | 0.043 | 0.001 | 0.001 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.026 | 0.028 | 0.003 | 0.003 |
| sqlite3 | 0.063 | 0.068 | 0.063 | 0.068 |
| sqlite_async | 0.074 | 0.076 | 0.004 | 0.004 |
| drift | 0.104 | 0.137 | 0.004 | 0.005 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.046 | 0.050 | 0.005 | 0.006 |
| sqlite3 | 0.119 | 0.123 | 0.119 | 0.123 |
| sqlite_async | 0.126 | 0.149 | 0.007 | 0.009 |
| drift | 0.192 | 0.234 | 0.008 | 0.010 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.177 | 0.186 | 0.026 | 0.027 |
| sqlite3 | 0.585 | 0.698 | 0.585 | 0.698 |
| sqlite_async | 0.547 | 0.635 | 0.036 | 0.044 |
| drift | 0.806 | 1.123 | 0.036 | 0.047 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.352 | 0.404 | 0.053 | 0.065 |
| sqlite3 | 1.211 | 1.414 | 1.211 | 1.414 |
| sqlite_async | 1.119 | 1.245 | 0.077 | 0.093 |
| drift | 1.620 | 1.985 | 0.074 | 0.090 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.782 | 0.856 | 0.107 | 0.117 |
| sqlite3 | 2.431 | 3.427 | 2.431 | 3.427 |
| sqlite_async | 2.208 | 2.623 | 0.147 | 0.164 |
| drift | 3.382 | 3.999 | 0.149 | 0.166 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.062 | 4.950 | 0.266 | 0.283 |
| sqlite3 | 6.166 | 8.538 | 6.166 | 8.538 |
| sqlite_async | 5.906 | 6.615 | 0.373 | 0.420 |
| drift | 8.698 | 9.308 | 0.369 | 0.387 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.354 | 11.466 | 0.537 | 1.174 |
| sqlite3 | 15.377 | 20.082 | 15.377 | 20.082 |
| sqlite_async | 12.683 | 14.378 | 0.750 | 0.778 |
| drift | 18.629 | 25.752 | 0.742 | 0.823 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 10.710 | 18.479 | 1.087 | 2.735 |
| sqlite3 | 37.497 | 43.148 | 37.497 | 43.148 |
| sqlite_async | 43.297 | 47.001 | 1.559 | 1.696 |
| drift | 54.660 | 69.824 | 1.481 | 2.195 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.031 | 0.034 | 0.031 | 0.034 |
| sqlite3 + jsonEncode | 0.031 | 0.033 | 0.031 | 0.033 |
| sqlite_async + jsonEncode | 0.048 | 0.050 | 0.048 | 0.050 |
| drift + jsonEncode | 0.075 | 0.123 | 0.075 | 0.123 |
| resqlite selectBytes() | 0.011 | 0.015 | 0.011 | 0.015 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.103 | 0.108 | 0.103 | 0.108 |
| sqlite3 + jsonEncode | 0.138 | 0.149 | 0.138 | 0.149 |
| sqlite_async + jsonEncode | 0.151 | 0.166 | 0.151 | 0.166 |
| drift + jsonEncode | 0.180 | 0.241 | 0.180 | 0.241 |
| resqlite selectBytes() | 0.027 | 0.040 | 0.027 | 0.040 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.197 | 0.217 | 0.197 | 0.217 |
| sqlite3 + jsonEncode | 0.272 | 0.302 | 0.272 | 0.302 |
| sqlite_async + jsonEncode | 0.277 | 0.320 | 0.277 | 0.320 |
| drift + jsonEncode | 0.353 | 0.397 | 0.353 | 0.397 |
| resqlite selectBytes() | 0.046 | 0.059 | 0.046 | 0.059 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.251 | 2.462 | 1.251 | 2.462 |
| sqlite3 + jsonEncode | 1.424 | 2.707 | 1.424 | 2.707 |
| sqlite_async + jsonEncode | 1.315 | 2.578 | 1.315 | 2.578 |
| drift + jsonEncode | 1.576 | 2.136 | 1.576 | 2.136 |
| resqlite selectBytes() | 0.189 | 0.212 | 0.189 | 0.212 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.945 | 3.475 | 1.945 | 3.475 |
| sqlite3 + jsonEncode | 2.732 | 5.068 | 2.732 | 5.068 |
| sqlite_async + jsonEncode | 2.741 | 5.639 | 2.741 | 5.639 |
| drift + jsonEncode | 3.257 | 5.771 | 3.257 | 5.771 |
| resqlite selectBytes() | 0.351 | 0.397 | 0.351 | 0.397 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.937 | 8.503 | 3.937 | 8.503 |
| sqlite3 + jsonEncode | 5.588 | 10.846 | 5.588 | 10.846 |
| sqlite_async + jsonEncode | 5.610 | 11.008 | 5.610 | 11.008 |
| drift + jsonEncode | 6.971 | 14.314 | 6.971 | 14.314 |
| resqlite selectBytes() | 1.367 | 4.350 | 1.367 | 4.350 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 11.389 | 17.583 | 11.389 | 17.583 |
| sqlite3 + jsonEncode | 15.343 | 21.734 | 15.343 | 21.734 |
| sqlite_async + jsonEncode | 14.668 | 22.069 | 14.668 | 22.069 |
| drift + jsonEncode | 17.147 | 26.917 | 17.147 | 26.917 |
| resqlite selectBytes() | 1.946 | 2.125 | 1.946 | 2.125 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 24.199 | 26.302 | 24.199 | 26.302 |
| sqlite3 + jsonEncode | 32.080 | 40.545 | 32.080 | 40.545 |
| sqlite_async + jsonEncode | 38.350 | 47.096 | 38.350 | 47.096 |
| drift + jsonEncode | 40.067 | 47.612 | 40.067 | 47.612 |
| resqlite selectBytes() | 3.920 | 6.932 | 3.920 | 6.932 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 47.435 | 50.558 | 47.435 | 50.558 |
| sqlite3 + jsonEncode | 70.048 | 78.378 | 70.048 | 78.378 |
| sqlite_async + jsonEncode | 70.443 | 81.793 | 70.443 | 81.793 |
| drift + jsonEncode | 91.454 | 106.707 | 91.454 | 106.707 |
| resqlite selectBytes() | 8.688 | 9.984 | 8.688 | 9.984 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.31 | 0.38 | 0.31 |
| sqlite_async | 1.03 | 1.27 | 1.03 |
| drift | 1.56 | 1.92 | 1.56 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.34 | 0.40 | 0.17 |
| sqlite_async | 1.52 | 1.93 | 0.76 |
| drift | 2.94 | 3.43 | 1.47 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.40 | 0.53 | 0.10 |
| sqlite_async | 2.58 | 3.54 | 0.65 |
| drift | 5.61 | 6.16 | 1.40 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.73 | 1.25 | 0.09 |
| sqlite_async | 5.38 | 6.23 | 0.67 |
| drift | 11.10 | 12.08 | 1.39 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 117548 |
| resqlite per query | 0.009 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 117548 | 114977..119370 | 1.9 | 4.7 |
| sqlite3 | 187874 | 187143..188708 | 0.4 | 1.3 |
| sqlite_async | 44619 | 43533..45351 | 2.0 | 6.1 |
| drift | 39456 | 39017..41155 | 2.7 | 10.5 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 15.721 | 18.299 | 15.721 | 18.299 |
| sqlite_async | 40.685 | 47.547 | 40.685 | 47.547 |
| drift | 58.570 | 80.796 | 58.570 | 80.796 |
| sqlite3 (no cache) | 25.707 | 27.580 | 25.707 | 27.580 |
| sqlite3 (cached stmt) | 25.273 | 46.766 | 25.273 | 46.766 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 2.629 | 9.876 | 2.629 | 9.876 |
| sqlite3 execute() | 1.476 | 3.477 | 1.476 | 3.477 |
| sqlite_async execute() | 5.665 | 17.334 | 5.665 | 17.334 |
| drift execute() | 4.924 | 12.096 | 4.924 | 12.096 |

### Concurrent Single Inserts (100 concurrent)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite concurrent execute() | 1.604 | 6.441 | 1.604 | 6.441 |
| sqlite3 concurrent execute() | 1.227 | 2.023 | 1.227 | 2.023 |
| sqlite_async concurrent execute() | 3.397 | 4.238 | 3.397 | 4.238 |
| drift concurrent execute() | 2.182 | 3.148 | 2.182 | 3.148 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.054 | 0.067 | 0.054 | 0.067 |
| sqlite3 executeBatch() | 0.051 | 0.061 | 0.051 | 0.061 |
| sqlite_async executeBatch() | 0.096 | 0.138 | 0.096 | 0.138 |
| drift executeBatch() | 0.115 | 0.156 | 0.115 | 0.156 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.406 | 0.519 | 0.406 | 0.519 |
| sqlite3 executeBatch() | 0.465 | 0.560 | 0.465 | 0.560 |
| sqlite_async executeBatch() | 0.567 | 0.643 | 0.567 | 0.643 |
| drift executeBatch() | 0.685 | 0.828 | 0.685 | 0.828 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.098 | 4.798 | 4.098 | 4.798 |
| sqlite3 executeBatch() | 4.293 | 4.721 | 4.293 | 4.721 |
| sqlite_async executeBatch() | 5.005 | 5.394 | 5.005 | 5.394 |
| drift executeBatch() | 6.421 | 7.327 | 6.421 | 7.327 |

### Wide Batch Insert (10000 rows x 20 params)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 13.578 | 26.197 | 13.578 | 26.197 |
| sqlite3 executeBatch() | 20.469 | 22.529 | 20.469 | 22.529 |
| sqlite_async executeBatch() | 24.041 | 29.406 | 24.041 | 29.406 |
| drift executeBatch() | 26.631 | 30.915 | 26.631 | 30.915 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.059 | 0.102 | 0.059 | 0.102 |
| sqlite_async writeTransaction() | 0.085 | 0.160 | 0.085 | 0.160 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.063 | 0.081 | 0.063 | 0.081 |
| resqlite tx.execute() loop | 0.523 | 0.584 | 0.523 | 0.584 |
| sqlite_async tx.execute() loop | 1.102 | 1.260 | 1.102 | 1.260 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.416 | 0.487 | 0.416 | 0.487 |
| resqlite tx.execute() loop | 5.266 | 5.649 | 5.266 | 5.649 |
| sqlite_async tx.execute() loop | 10.208 | 10.538 | 10.208 | 10.538 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.104 | 0.121 | 0.104 | 0.121 |
| sqlite_async tx.getAll() | 0.205 | 0.237 | 0.205 | 0.237 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.189 | 0.214 | 0.189 | 0.214 |
| sqlite_async tx.getAll() | 0.366 | 0.419 | 0.366 | 0.419 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 0.875 | 1.018 | 0.875 | 1.018 |
| resqlite nested transaction() depth=5 | 0.078 | 0.088 | 0.078 | 0.088 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.027 | 0.040 | 0.027 | 0.040 |
| sqlite_async watch() | 0.101 | 0.121 | 0.101 | 0.121 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.047 | 0.092 | 0.047 | 0.092 |
| sqlite_async | 0.050 | 0.085 | 0.050 | 0.085 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.192 | 0.239 | 0.192 | 0.239 |
| sqlite_async | 0.553 | 2.444 | 0.553 | 2.444 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.478 | 5.625 | 2.478 | 5.625 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.228 | 0.264 | 0.228 | 0.264 |
| sqlite_async | 0.277 | 0.320 | 0.277 | 0.320 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.760 | 1.760 | 1.760 | 1.760 |
| sqlite_async | 8.721 | 8.721 | 8.721 | 8.721 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.393 | 3.849 | 3.393 | 3.849 |
| sqlite_async | 5.805 | 7.522 | 5.805 | 7.522 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.564 | 0.795 | 0.564 | 0.795 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 7.239 | 8.372 | 7.239 | 8.372 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. For resqlite, this emission metric can reflect writer-side column-level invalidation, experiment 075's native result-hash short-circuit, or both. Use A11c (Many-Streams Writer Throughput) when the question is specifically writer-side dispatch elision.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 67.8 | 0.000 |
| sqlite_async | 4216 | 1255.2 | 1.049 |
| drift | 5000 | 1104.7 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 75.0 | 0.000 |
| sqlite_async | 4018 | 1198.0 | 1.049 |
| drift | 5000 | 1105.2 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 216.86 | 216.93 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 433.89 | 434.77 | 0.00 | 0.00 | 1194 | 3 |
| drift stream() | 555.01 | 559.58 | 0.02 | 0.03 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.021 | 0.042 | 0.000 | 0.000 |
| sqlite3 | 0.020 | 0.037 | 0.020 | 0.037 |
| sqlite_async | 0.044 | 0.069 | 0.000 | 0.000 |
| drift | 0.047 | 0.075 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.016 | 0.029 | 0.000 | 0.000 |
| sqlite3 | 0.013 | 0.020 | 0.013 | 0.020 |
| sqlite_async | 0.035 | 0.055 | 0.000 | 0.000 |
| drift | 0.039 | 0.059 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.027 | 0.040 | 0.000 | 0.000 |
| sqlite3 | 0.033 | 0.037 | 0.033 | 0.037 |
| sqlite_async | 0.061 | 0.077 | 0.000 | 0.000 |
| drift | 0.058 | 0.076 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.009 | 0.017 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.021 | 0.029 | 0.000 | 0.000 |
| drift | 0.023 | 0.036 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.047 | 0.089 | 0.001 | 0.001 |
| sqlite3 | 0.067 | 0.068 | 0.067 | 0.068 |
| sqlite_async | 0.085 | 0.108 | 0.001 | 0.001 |
| drift | 0.093 | 0.107 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 103.894 | 105.444 | 0.000 | 0.000 | 0 |
| sqlite_async | 213.008 | 213.825 | 0.000 | 0.000 | 40 |
| drift | 218.052 | 219.575 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 230.35 | 230.35 | 0.00 | 0.00 | 12.28 | 218.07 | 0 |
| sqlite_async | 472.60 | 472.60 | 0.00 | 0.00 | 12.37 | 460.27 | 1182 |
| drift | 1801.25 | 1801.25 | 0.05 | 0.05 | 12.78 | 1788.76 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 7.28 | 13.81 | 0.00..12.83 | ±6.41 |
| sqlite3 select() | 5.72 | 9.84 | 1.19..9.03 | ±3.92 |
| sqlite_async select() | 1.00 | 1.00 | 0.98..1.00 | ±0.01 |
| drift select() | 12.08 | 74.14 | 0.00..59.00 | ±29.50 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 19.98 | 0.00..8.02 | ±4.01 |
| resqlite + jsonEncode | 0.00 | 57.14 | 0.00..15.53 | ±7.77 |
| sqlite3 + jsonEncode | 8.83 | 64.91 | 0.00..36.53 | ±18.27 |
| sqlite_async + jsonEncode | 0.00 | 23.19 | 0.00..3.00 | ±1.50 |
| drift + jsonEncode | 0.00 | 35.20 | 0.00..4.67 | ±2.34 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.06 | 6.30 | 0.00..4.11 | ±2.05 |
| sqlite3 executeBatch() | 0.00 | 0.05 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 0.17 | 0.00..0.05 | ±0.02 |
| drift batch() | 0.02 | 2.05 | 0.00..1.00 | ±0.50 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.20 | 0.06..0.13 | ±0.03 |
| sqlite_async watch() | 0.00 | 0.03 | 0.00..0.00 | ±0.00 |

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
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.03 | 0.03..0.03 | 3.7% | 7.4% | 3.7% | moderate |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 5.6% | 11.1% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02..0.03 | 10.9% | 21.7% | 4.3% | moderate |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02..0.02 | 8.8% | 17.6% | 5.9% | moderate |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.30 | 0.30..0.31 | 1.7% | 3.3% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.30 | 0.30..0.31 | 1.7% | 3.3% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.33 | 0.32..0.34 | 3.0% | 6.1% | 3.0% | moderate |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.16 | 0.16..0.17 | 3.1% | 6.3% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.37 | 0.36..0.40 | 5.4% | 10.8% | 2.7% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.09 | 0.09..0.10 | 5.6% | 11.1% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.73 | 0.69..0.78 | 6.2% | 12.3% | 5.5% | moderate |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.09 | 0.09..0.10 | 5.6% | 11.1% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.05 | 5.7% | 11.4% | 4.5% | moderate |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 150.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 104.96 | 103.89..110.83 | 3.3% | 6.6% | 1.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 231.14 | 228.59..433.23 | 44.3% | 88.5% | 1.1% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 215.60 | 214.90..216.86 | 0.5% | 0.9% | 0.2% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 15.04 | 14.54..15.72 | 3.9% | 7.9% | 2.3% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 15.04 | 14.54..15.72 | 3.9% | 7.9% | 2.3% | stable |
| Point Query Throughput / resqlite qps | 113682.00 | 78875.00..126319.00 | 20.9% | 41.7% | 11.1% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.01 | 14.3% | 28.6% | 7.1% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.04 | 12.9% | 25.8% | 6.5% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.04 | 12.9% | 25.8% | 6.5% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 20.8% | 41.7% | 8.3% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.02 | 20.8% | 41.7% | 8.3% | noisy |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.04..0.05 | 3.3% | 6.5% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.20 | 0.19..0.20 | 2.0% | 4.1% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.20 | 0.19..0.20 | 2.0% | 4.1% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 10.0% | 20.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.05 | 0.04..0.05 | 1.1% | 2.2% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.05 | 0.04..0.05 | 1.1% | 2.2% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.35 | 0.35..0.36 | 1.7% | 3.4% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.86 | 1.79..1.95 | 4.1% | 8.2% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.86 | 1.79..1.95 | 4.1% | 8.2% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.05 | 0.05..0.05 | 0.9% | 1.9% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.37 | 0.35..0.69 | 46.2% | 92.4% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.37 | 0.35..0.69 | 46.2% | 92.4% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.37 | 4.35..4.56 | 2.4% | 4.8% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 24.20 | 20.52..26.10 | 11.5% | 23.1% | 4.8% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 24.20 | 20.52..26.10 | 11.5% | 23.1% | 4.8% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.55 | 0.54..0.56 | 2.2% | 4.4% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 3.92 | 3.89..4.00 | 1.4% | 2.8% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 3.92 | 3.89..4.00 | 1.4% | 2.8% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.78 | 0.74..0.96 | 14.2% | 28.4% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.98 | 3.94..4.02 | 1.1% | 2.2% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.98 | 3.94..4.02 | 1.1% | 2.2% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.11 | 0.11..0.12 | 5.9% | 11.7% | 3.6% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.82 | 0.77..1.37 | 36.1% | 72.1% | 6.4% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.82 | 0.77..1.37 | 36.1% | 72.1% | 6.4% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 11.41 | 10.21..12.36 | 9.4% | 18.8% | 6.2% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 47.60 | 43.31..48.79 | 5.8% | 11.5% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 47.60 | 43.31..48.79 | 5.8% | 11.5% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.09 | 1.05..1.14 | 4.4% | 8.8% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 8.24 | 7.88..8.69 | 4.9% | 9.8% | 3.9% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 8.24 | 7.88..8.69 | 4.9% | 9.8% | 3.9% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03..0.03 | 6.9% | 13.8% | 3.4% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.10..0.11 | 5.1% | 10.2% | 4.6% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.11 | 0.10..0.11 | 5.1% | 10.2% | 4.6% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.03..0.03 | 3.8% | 7.7% | 3.8% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.03..0.03 | 3.8% | 7.7% | 3.8% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.18 | 0.18..0.19 | 2.8% | 5.6% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.96 | 0.92..1.25 | 17.4% | 34.8% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.96 | 0.92..1.25 | 17.4% | 34.8% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.03 | 0.03..0.03 | 1.9% | 3.8% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.19 | 0.18..0.19 | 2.9% | 5.8% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.19 | 0.18..0.19 | 2.9% | 5.8% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.13 | 2.04..2.81 | 17.9% | 35.9% | 4.2% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 10.71 | 9.34..12.67 | 15.5% | 31.1% | 6.3% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 10.71 | 9.34..12.67 | 15.5% | 31.1% | 6.3% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.28 | 0.27..0.29 | 4.0% | 8.0% | 3.3% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 2.02 | 1.93..2.03 | 2.5% | 4.9% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 2.02 | 1.93..2.03 | 2.5% | 4.9% | 0.4% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.09 | 0.09..0.10 | 2.7% | 5.4% | 2.2% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.02 | 0.02..0.02 | 15.2% | 30.4% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.27 | 0.26..0.28 | 3.6% | 7.1% | 2.2% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.06 | 0.06..0.07 | 3.2% | 6.5% | 1.6% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.26 | 0.26..0.27 | 2.5% | 5.0% | 1.2% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.06 | 0.06..0.06 | 2.5% | 5.0% | 1.7% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.53 | 0.50..0.56 | 5.9% | 11.8% | 4.9% | moderate |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.06 | 0.06..0.07 | 3.1% | 6.3% | 1.6% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.88 | 0.85..0.91 | 3.7% | 7.5% | 1.2% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.23 | 0.22..0.23 | 1.6% | 3.1% | 0.9% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.06 | 53.2% | 106.5% | 3.2% | moderate |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02..0.04 | 65.6% | 131.2% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 50.0% | 100.0% | 8.3% | noisy |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.19..0.23 | 10.3% | 20.6% | 1.5% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.16 | 0.15..0.18 | 9.2% | 18.5% | 3.2% | moderate |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.04..0.05 | 8.2% | 16.3% | 6.1% | moderate |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.81 | 1.76..1.87 | 2.9% | 5.8% | 0.8% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.49 | 1.46..1.53 | 2.6% | 5.1% | 0.4% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.36 | 0.36..0.37 | 1.5% | 3.0% | 1.4% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 21.55 | 20.82..25.71 | 11.3% | 22.7% | 3.1% | moderate |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 15.49 | 15.07..16.18 | 3.6% | 7.2% | 2.7% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.92 | 3.80..4.16 | 4.7% | 9.3% | 2.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.01 | 25.0% | 50.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.08 | 291.7% | 583.3% | 8.3% | noisy |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.04..0.13 | 94.7% | 189.4% | 8.5% | noisy |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 20.0% | 40.0% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.36 | 0.35..0.43 | 11.8% | 23.6% | 1.7% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.05 | 0.05..0.06 | 9.4% | 18.9% | 0.0% | stable |
| Select → Maps / 10000 rows / resqlite select() | 4.33 | 4.29..4.59 | 3.4% | 6.9% | 0.2% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.53 | 0.53..0.54 | 1.7% | 3.4% | 1.3% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.23 | 0.22..0.36 | 31.8% | 63.5% | 7.3% | moderate |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.23 | 0.22..0.36 | 31.8% | 63.5% | 7.3% | moderate |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.56 | 0.56..0.60 | 4.1% | 8.2% | 0.9% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.56 | 0.56..0.60 | 4.1% | 8.2% | 0.9% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03..0.08 | 86.2% | 172.4% | 10.3% | noisy |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03..0.08 | 86.2% | 172.4% | 10.3% | noisy |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.05..0.09 | 42.5% | 84.9% | 11.3% | noisy |
| Streaming / Invalidation Latency / resqlite [main] | 0.05 | 0.05..0.09 | 42.5% | 84.9% | 11.3% | noisy |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 2.63 | 2.48..2.84 | 6.8% | 13.6% | 4.5% | moderate |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 2.63 | 2.48..2.84 | 6.8% | 13.6% | 4.5% | moderate |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.45 | 3.28..3.85 | 8.2% | 16.5% | 4.7% | moderate |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.45 | 3.28..3.85 | 8.2% | 16.5% | 4.7% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.75 | 1.36..3.04 | 48.0% | 96.0% | 14.2% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.75 | 1.36..3.04 | 48.0% | 96.0% | 14.2% | noisy |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 8.02 | 7.24..8.53 | 8.0% | 16.1% | 6.3% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 8.02 | 7.24..8.53 | 8.0% | 16.1% | 6.3% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.26 | 0.19..0.45 | 48.5% | 97.0% | 27.3% | noisy |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.26 | 0.19..0.45 | 48.5% | 97.0% | 27.3% | noisy |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.05..0.06 | 5.4% | 10.7% | 3.6% | moderate |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.06 | 0.05..0.06 | 5.4% | 10.7% | 3.6% | moderate |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.41 | 0.40..0.44 | 5.8% | 11.7% | 2.2% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.41 | 0.40..0.44 | 5.8% | 11.7% | 2.2% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.04 | 3.88..4.10 | 2.7% | 5.4% | 1.3% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.04 | 3.88..4.10 | 2.7% | 5.4% | 1.3% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.52 | 0.47..0.68 | 19.7% | 39.4% | 6.0% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.52 | 0.47..0.68 | 19.7% | 39.4% | 6.0% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.06..0.07 | 6.3% | 12.7% | 1.4% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.06..0.07 | 6.3% | 12.7% | 1.4% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.53 | 5.11..6.82 | 15.5% | 31.0% | 6.2% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.53 | 5.11..6.82 | 15.5% | 31.0% | 6.2% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.42 | 0.40..0.52 | 13.8% | 27.6% | 3.8% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.42 | 0.40..0.52 | 13.8% | 27.6% | 3.8% | moderate |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 1.44 | 1.18..1.60 | 14.8% | 29.6% | 11.2% | noisy |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 1.44 | 1.18..1.60 | 14.8% | 29.6% | 11.2% | noisy |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.04..0.06 | 13.7% | 27.5% | 7.8% | moderate |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.04..0.06 | 13.7% | 27.5% | 7.8% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.08 | 0.06..0.10 | 25.3% | 50.6% | 11.1% | noisy |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.08 | 0.06..0.10 | 25.3% | 50.6% | 11.1% | noisy |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 1.01 | 0.88..1.19 | 15.7% | 31.4% | 13.5% | noisy |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 1.01 | 0.88..1.19 | 15.7% | 31.4% | 13.5% | noisy |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.89 | 1.60..2.63 | 27.2% | 54.4% | 15.4% | noisy |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.89 | 1.60..2.63 | 27.2% | 54.4% | 15.4% | noisy |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.19..0.22 | 8.1% | 16.2% | 2.1% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.19..0.22 | 8.1% | 16.2% | 2.1% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.11 | 0.10..0.12 | 7.0% | 14.0% | 0.9% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.11 | 0.10..0.12 | 7.0% | 14.0% | 0.9% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 13.51 | 13.19..13.87 | 2.5% | 5.1% | 0.5% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 13.51 | 13.19..13.87 | 2.5% | 5.1% | 0.5% | stable |


## Comparison

Automatic comparison skipped because `2026-06-09T22-41-01-exp159-writer-pipelining.md` was not captured in a compatible environment:
- hostname differs: current `enterprise.local` vs baseline `macbookpro.lan`

Use `--compare-to=benchmark/results/2026-06-09T22-41-01-exp159-writer-pipelining.md` to run an explicit reference comparison anyway.


