# resqlite Benchmark Results

Generated: 2026-06-10T11:25:55.763350

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp160-stream-delta-ivm`
- Repeats: `5`
- Runtime: `dart-runtime / Dart 3.12.1`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `exp-160-stream-delta-ivm @ b32177adfadd (dirty)`
- Comparison baseline: `2026-06-09T11-20-00-exp150-nullable-batch-packing.md`
- Comparison mode: `automatic`
- Comparison baseline compatibility: `incompatible (automatic comparison skipped)`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.021 | 0.049 | 0.001 | 0.002 |
| sqlite3 select() | 0.030 | 0.033 | 0.030 | 0.033 |
| sqlite_async select() | 0.055 | 0.074 | 0.003 | 0.005 |
| drift select() | 0.063 | 0.066 | 0.002 | 0.003 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.066 | 0.069 | 0.007 | 0.007 |
| sqlite3 select() | 0.204 | 0.211 | 0.204 | 0.211 |
| sqlite_async select() | 0.199 | 0.205 | 0.018 | 0.020 |
| drift select() | 0.299 | 0.323 | 0.017 | 0.020 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.512 | 0.553 | 0.064 | 0.066 |
| sqlite3 select() | 1.930 | 1.992 | 1.930 | 1.992 |
| sqlite_async select() | 1.659 | 1.921 | 0.172 | 0.180 |
| drift select() | 2.650 | 3.132 | 0.166 | 0.170 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 8.708 | 20.188 | 0.717 | 1.299 |
| sqlite3 select() | 24.015 | 28.868 | 24.015 | 28.868 |
| sqlite_async select() | 19.142 | 24.053 | 1.681 | 2.684 |
| drift select() | 41.652 | 51.899 | 2.494 | 4.098 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.039 | 0.047 | 0.020 | 0.021 |
| sqlite3 + jsonEncode | 0.047 | 0.051 | 0.047 | 0.051 |
| sqlite_async + jsonEncode | 0.076 | 0.088 | 0.021 | 0.025 |
| drift + jsonEncode | 0.089 | 0.103 | 0.022 | 0.026 |
| resqlite selectBytes() | 0.022 | 0.025 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.258 | 0.262 | 0.191 | 0.194 |
| sqlite3 + jsonEncode | 0.379 | 0.403 | 0.379 | 0.403 |
| sqlite_async + jsonEncode | 0.382 | 0.396 | 0.189 | 0.194 |
| drift + jsonEncode | 0.477 | 0.495 | 0.187 | 0.197 |
| resqlite selectBytes() | 0.086 | 0.096 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 2.372 | 5.598 | 1.888 | 3.517 |
| sqlite3 + jsonEncode | 3.693 | 9.090 | 3.693 | 9.090 |
| sqlite_async + jsonEncode | 3.373 | 11.882 | 1.888 | 4.689 |
| drift + jsonEncode | 4.468 | 13.947 | 1.886 | 3.518 |
| resqlite selectBytes() | 0.700 | 0.755 | 0.000 | 0.004 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 32.654 | 42.762 | 20.903 | 24.667 |
| sqlite3 + jsonEncode | 43.098 | 57.609 | 43.098 | 57.609 |
| sqlite_async + jsonEncode | 55.225 | 64.016 | 21.279 | 24.435 |
| drift + jsonEncode | 69.361 | 83.358 | 21.346 | 28.551 |
| resqlite selectBytes() | 7.114 | 12.536 | 0.006 | 0.364 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.123 | 0.138 | 0.028 | 0.030 |
| sqlite3 | 0.612 | 0.654 | 0.612 | 0.654 |
| sqlite_async | 0.593 | 0.714 | 0.066 | 0.074 |
| drift | 0.985 | 1.009 | 0.065 | 0.068 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.237 | 1.345 | 0.269 | 0.281 |
| sqlite3 | 5.731 | 6.488 | 5.731 | 6.488 |
| sqlite_async | 4.682 | 5.302 | 0.464 | 0.493 |
| drift | 8.084 | 13.013 | 0.482 | 0.534 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.947 | 1.017 | 0.072 | 0.076 |
| sqlite3 | 2.349 | 3.939 | 2.349 | 3.939 |
| sqlite_async | 1.931 | 2.052 | 0.169 | 0.176 |
| drift | 3.038 | 3.872 | 0.167 | 0.172 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.353 | 0.367 | 0.071 | 0.073 |
| sqlite3 | 1.740 | 1.888 | 1.740 | 1.888 |
| sqlite_async | 1.452 | 1.756 | 0.181 | 0.200 |
| drift | 2.489 | 2.689 | 0.178 | 0.184 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.347 | 0.382 | 0.069 | 0.074 |
| sqlite3 | 1.574 | 1.755 | 1.574 | 1.755 |
| sqlite_async | 1.388 | 1.491 | 0.166 | 0.180 |
| drift | 2.349 | 2.457 | 0.165 | 0.174 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.021 | 0.027 | 0.001 | 0.001 |
| sqlite3 | 0.028 | 0.031 | 0.028 | 0.031 |
| sqlite_async | 0.052 | 0.072 | 0.002 | 0.003 |
| drift | 0.062 | 0.067 | 0.002 | 0.002 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.042 | 0.046 | 0.004 | 0.004 |
| sqlite3 | 0.106 | 0.112 | 0.106 | 0.112 |
| sqlite_async | 0.117 | 0.124 | 0.009 | 0.009 |
| drift | 0.169 | 0.178 | 0.009 | 0.009 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.065 | 0.067 | 0.007 | 0.007 |
| sqlite3 | 0.197 | 0.202 | 0.197 | 0.202 |
| sqlite_async | 0.191 | 0.205 | 0.017 | 0.018 |
| drift | 0.304 | 0.319 | 0.016 | 0.018 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.276 | 0.285 | 0.036 | 0.037 |
| sqlite3 | 0.951 | 1.082 | 0.951 | 1.082 |
| sqlite_async | 0.848 | 0.913 | 0.085 | 0.101 |
| drift | 1.341 | 1.462 | 0.082 | 0.089 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.529 | 0.607 | 0.071 | 0.076 |
| sqlite3 | 1.941 | 2.011 | 1.941 | 2.011 |
| sqlite_async | 1.609 | 1.703 | 0.165 | 0.182 |
| drift | 2.638 | 3.085 | 0.165 | 0.168 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.099 | 1.290 | 0.140 | 0.144 |
| sqlite3 | 3.858 | 4.871 | 3.858 | 4.871 |
| sqlite_async | 3.263 | 5.224 | 0.331 | 0.415 |
| drift | 5.324 | 5.912 | 0.323 | 0.921 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.361 | 10.958 | 0.360 | 2.112 |
| sqlite3 | 9.805 | 12.605 | 9.805 | 12.605 |
| sqlite_async | 8.480 | 9.558 | 0.813 | 0.915 |
| drift | 14.177 | 14.529 | 0.817 | 0.889 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 8.588 | 16.947 | 0.737 | 1.592 |
| sqlite3 | 23.166 | 30.116 | 23.166 | 30.116 |
| sqlite_async | 16.345 | 17.844 | 1.540 | 1.586 |
| drift | 31.663 | 45.264 | 1.847 | 3.859 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 19.172 | 28.498 | 1.625 | 8.176 |
| sqlite3 | 54.991 | 58.473 | 54.991 | 58.473 |
| sqlite_async | 63.204 | 85.638 | 4.681 | 5.123 |
| drift | 85.513 | 99.975 | 4.180 | 4.897 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.040 | 0.084 | 0.040 | 0.084 |
| sqlite3 + jsonEncode | 0.044 | 0.056 | 0.044 | 0.056 |
| sqlite_async + jsonEncode | 0.068 | 0.077 | 0.068 | 0.077 |
| drift + jsonEncode | 0.080 | 0.082 | 0.080 | 0.082 |
| resqlite selectBytes() | 0.021 | 0.024 | 0.021 | 0.024 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.131 | 0.141 | 0.131 | 0.141 |
| sqlite3 + jsonEncode | 0.182 | 0.188 | 0.182 | 0.188 |
| sqlite_async + jsonEncode | 0.193 | 0.197 | 0.193 | 0.197 |
| drift + jsonEncode | 0.255 | 0.272 | 0.255 | 0.272 |
| resqlite selectBytes() | 0.048 | 0.049 | 0.048 | 0.049 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.240 | 0.256 | 0.240 | 0.256 |
| sqlite3 + jsonEncode | 0.359 | 0.395 | 0.359 | 0.395 |
| sqlite_async + jsonEncode | 0.350 | 0.430 | 0.350 | 0.430 |
| drift + jsonEncode | 0.444 | 0.454 | 0.444 | 0.454 |
| resqlite selectBytes() | 0.082 | 0.085 | 0.082 | 0.085 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.125 | 1.139 | 1.125 | 1.139 |
| sqlite3 + jsonEncode | 1.754 | 1.909 | 1.754 | 1.909 |
| sqlite_async + jsonEncode | 1.592 | 1.681 | 1.592 | 1.681 |
| drift + jsonEncode | 2.078 | 2.113 | 2.078 | 2.113 |
| resqlite selectBytes() | 0.342 | 0.347 | 0.342 | 0.347 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 2.203 | 2.267 | 2.203 | 2.267 |
| sqlite3 + jsonEncode | 3.762 | 7.176 | 3.762 | 7.176 |
| sqlite_async + jsonEncode | 3.178 | 11.331 | 3.178 | 11.331 |
| drift + jsonEncode | 4.165 | 12.146 | 4.165 | 12.146 |
| resqlite selectBytes() | 0.657 | 0.666 | 0.657 | 0.666 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 5.783 | 12.954 | 5.783 | 12.954 |
| sqlite3 + jsonEncode | 8.297 | 16.767 | 8.297 | 16.767 |
| sqlite_async + jsonEncode | 7.246 | 14.480 | 7.246 | 14.480 |
| drift + jsonEncode | 9.698 | 20.192 | 9.698 | 20.192 |
| resqlite selectBytes() | 1.704 | 4.706 | 1.704 | 4.706 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 19.581 | 25.753 | 19.581 | 25.753 |
| sqlite3 + jsonEncode | 22.179 | 34.178 | 22.179 | 34.178 |
| sqlite_async + jsonEncode | 23.133 | 34.563 | 23.133 | 34.563 |
| drift + jsonEncode | 28.103 | 42.442 | 28.103 | 42.442 |
| resqlite selectBytes() | 4.220 | 9.309 | 4.220 | 9.309 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 32.354 | 43.597 | 32.354 | 43.597 |
| sqlite3 + jsonEncode | 49.143 | 66.132 | 49.143 | 66.132 |
| sqlite_async + jsonEncode | 60.308 | 71.855 | 60.308 | 71.855 |
| drift + jsonEncode | 70.884 | 86.577 | 70.884 | 86.577 |
| resqlite selectBytes() | 8.079 | 13.317 | 8.079 | 13.317 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 65.593 | 75.579 | 65.593 | 75.579 |
| sqlite3 + jsonEncode | 98.680 | 108.502 | 98.680 | 108.502 |
| sqlite_async + jsonEncode | 98.032 | 115.728 | 98.032 | 115.728 |
| drift + jsonEncode | 132.373 | 147.909 | 132.373 | 147.909 |
| resqlite selectBytes() | 16.827 | 18.788 | 16.827 | 18.788 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.43 | 0.48 | 0.43 |
| sqlite_async | 1.37 | 1.50 | 1.37 |
| drift | 2.51 | 2.96 | 2.51 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.48 | 0.53 | 0.24 |
| sqlite_async | 2.15 | 2.70 | 1.08 |
| drift | 4.58 | 5.10 | 2.29 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.52 | 1.09 | 0.13 |
| sqlite_async | 3.52 | 4.47 | 0.88 |
| drift | 8.65 | 9.24 | 2.16 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.98 | 1.78 | 0.12 |
| sqlite_async | 6.92 | 7.79 | 0.86 |
| drift | 17.98 | 18.42 | 2.25 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 70059 |
| resqlite per query | 0.014 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 70059 | 66213..70397 | 3.0 | 9.1 |
| sqlite3 | 96271 | 90377..98171 | 4.0 | 8.2 |
| sqlite_async | 24757 | 22177..26616 | 9.0 | 22.5 |
| drift | 17604 | 15271..19735 | 12.7 | 39.6 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 21.398 | 26.672 | 21.398 | 26.672 |
| sqlite_async | 57.318 | 65.288 | 57.318 | 65.288 |
| drift | 100.867 | 151.538 | 100.867 | 151.538 |
| sqlite3 (no cache) | 50.808 | 79.109 | 50.808 | 79.109 |
| sqlite3 (cached stmt) | 44.103 | 50.156 | 44.103 | 50.156 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 2.635 | 3.252 | 2.635 | 3.252 |
| sqlite3 execute() | 1.702 | 4.769 | 1.702 | 4.769 |
| sqlite_async execute() | 5.816 | 7.161 | 5.816 | 7.161 |
| drift execute() | 4.995 | 5.987 | 4.995 | 5.987 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.098 | 0.106 | 0.098 | 0.106 |
| sqlite3 executeBatch() | 0.088 | 0.097 | 0.088 | 0.097 |
| sqlite_async executeBatch() | 0.184 | 0.313 | 0.184 | 0.313 |
| drift executeBatch() | 0.250 | 0.336 | 0.250 | 0.336 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.610 | 0.910 | 0.610 | 0.910 |
| sqlite3 executeBatch() | 0.802 | 0.979 | 0.802 | 0.979 |
| sqlite_async executeBatch() | 0.921 | 4.477 | 0.921 | 4.477 |
| drift executeBatch() | 1.264 | 1.893 | 1.264 | 1.893 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 5.746 | 6.686 | 5.746 | 6.686 |
| sqlite3 executeBatch() | 7.705 | 8.272 | 7.705 | 8.272 |
| sqlite_async executeBatch() | 7.885 | 8.676 | 7.885 | 8.676 |
| drift executeBatch() | 10.689 | 13.943 | 10.689 | 13.943 |

### Wide Batch Insert (10000 rows x 20 params)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 19.178 | 44.984 | 19.178 | 44.984 |
| sqlite3 executeBatch() | 39.718 | 42.194 | 39.718 | 42.194 |
| sqlite_async executeBatch() | 43.805 | 63.616 | 43.805 | 63.616 |
| drift executeBatch() | 48.958 | 62.041 | 48.958 | 62.041 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.086 | 0.178 | 0.086 | 0.178 |
| sqlite_async writeTransaction() | 0.143 | 0.195 | 0.143 | 0.195 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.150 | 0.175 | 0.150 | 0.175 |
| resqlite tx.execute() loop | 1.401 | 1.901 | 1.401 | 1.901 |
| sqlite_async tx.execute() loop | 2.615 | 3.394 | 2.615 | 3.394 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.621 | 0.710 | 0.621 | 0.710 |
| resqlite tx.execute() loop | 13.556 | 17.375 | 13.556 | 17.375 |
| sqlite_async tx.execute() loop | 23.020 | 25.111 | 23.020 | 25.111 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.159 | 0.167 | 0.159 | 0.167 |
| sqlite_async tx.getAll() | 0.352 | 0.376 | 0.352 | 0.376 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.273 | 0.338 | 0.273 | 0.338 |
| sqlite_async tx.getAll() | 0.569 | 0.699 | 0.569 | 0.699 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 2.941 | 3.509 | 2.941 | 3.509 |
| resqlite nested transaction() depth=5 | 0.188 | 0.218 | 0.188 | 0.218 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.054 | 0.091 | 0.054 | 0.091 |
| sqlite_async watch() | 0.200 | 0.326 | 0.200 | 0.326 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.127 | 0.259 | 0.127 | 0.259 |
| sqlite_async | 0.142 | 0.713 | 0.142 | 0.713 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.325 | 0.389 | 0.325 | 0.389 |
| sqlite_async | 0.767 | 2.168 | 0.767 | 2.168 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.135 | 0.206 | 0.135 | 0.206 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.310 | 0.406 | 0.310 | 0.406 |
| sqlite_async | 0.360 | 0.478 | 0.360 | 0.478 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.433 | 3.433 | 3.433 | 3.433 |
| sqlite_async | 16.332 | 16.332 | 16.332 | 16.332 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 5.976 | 6.640 | 5.976 | 6.640 |
| sqlite_async | 10.428 | 11.678 | 10.428 | 11.678 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.173 | 0.193 | 0.173 | 0.193 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.421 | 16.022 | 14.421 | 16.022 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. For resqlite, this emission metric can reflect writer-side column-level invalidation, experiment 075's native result-hash short-circuit, or both. Use A11c (Many-Streams Writer Throughput) when the question is specifically writer-side dispatch elision.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 79.5 | 0.000 |
| sqlite_async | 3825 | 1560.8 | 0.951 |
| drift | 5000 | 1594.0 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 5000 | 88.4 | 0.000 |
| sqlite_async | 4021 | 1556.4 | 0.951 |
| drift | 5000 | 1566.8 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 212.08 | 212.10 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 445.65 | 446.84 | 0.00 | 0.01 | 1195 | 3 |
| drift stream() | 659.43 | 664.34 | 0.06 | 0.08 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.049 | 0.093 | 0.000 | 0.000 |
| sqlite3 | 0.026 | 0.048 | 0.026 | 0.048 |
| sqlite_async | 0.088 | 0.145 | 0.000 | 0.000 |
| drift | 0.079 | 0.131 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.039 | 0.080 | 0.000 | 0.000 |
| sqlite3 | 0.018 | 0.027 | 0.018 | 0.027 |
| sqlite_async | 0.073 | 0.125 | 0.000 | 0.000 |
| drift | 0.067 | 0.117 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.050 | 0.085 | 0.000 | 0.000 |
| sqlite3 | 0.051 | 0.057 | 0.051 | 0.057 |
| sqlite_async | 0.102 | 0.158 | 0.001 | 0.001 |
| drift | 0.097 | 0.127 | 0.001 | 0.001 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.019 | 0.049 | 0.000 | 0.000 |
| sqlite3 | 0.010 | 0.012 | 0.010 | 0.012 |
| sqlite_async | 0.043 | 0.075 | 0.000 | 0.000 |
| drift | 0.042 | 0.064 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.071 | 0.094 | 0.001 | 0.002 |
| sqlite3 | 0.112 | 0.116 | 0.112 | 0.116 |
| sqlite_async | 0.132 | 0.148 | 0.002 | 0.002 |
| drift | 0.194 | 0.253 | 0.002 | 0.003 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 106.908 | 107.198 | 0.000 | 0.000 | 0 |
| sqlite_async | 212.821 | 213.096 | 0.000 | 0.000 | 40 |
| drift | 225.667 | 226.407 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 230.33 | 230.33 | 0.00 | 0.00 | 12.38 | 218.00 | 2 |
| sqlite_async | 500.46 | 500.46 | 0.00 | 0.00 | 23.76 | 476.70 | 1183 |
| drift | 3077.56 | 3077.56 | 2.53 | 2.53 | 17.91 | 3059.56 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 6.14 | 24.32 | 3.03..9.67 | ±3.32 |
| sqlite3 select() | 1.98 | 9.56 | 0.00..4.53 | ±2.27 |
| sqlite_async select() | 1.00 | 1.66 | 0.96..1.00 | ±0.02 |
| drift select() | 5.25 | 19.36 | 0.59..12.28 | ±5.85 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.24 | 8.97 | 0.00..1.16 | ±0.58 |
| resqlite + jsonEncode | 7.83 | 67.64 | 0.00..47.54 | ±23.77 |
| sqlite3 + jsonEncode | 7.68 | 58.14 | 0.00..14.66 | ±7.33 |
| sqlite_async + jsonEncode | 2.38 | 26.09 | 0.00..10.20 | ±5.10 |
| drift + jsonEncode | 0.00 | 31.68 | 0.00..1.94 | ±0.97 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 6.73 | 12.64 | 0.00..9.56 | ±4.78 |
| sqlite3 executeBatch() | 0.00 | 0.62 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.29 | 4.98 | 0.00..0.54 | ±0.27 |
| drift batch() | 0.01 | 2.00 | 0.00..0.11 | ±0.06 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.00 | 0.13 | 0.00..0.12 | ±0.06 |
| sqlite_async watch() | 0.00 | 0.91 | 0.00..0.03 | ±0.02 |

## SQLite Diagnostics

resqlite-only internal SQLite counters captured via `Database.diagnostics()` after representative workloads. Values reflect the writer plus idle readers in this connection pool; they are not process-global SQLite totals.

### Warm read working set (20000 rows + 2000 point lookups)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | Readers busy |
|---|---|---|---|---|---|---|
| resqlite | 3210.4 | 3189.5 | 5.3 | 15.6 | 2048.0 | 0 |

### Statement cache footprint (48 distinct SELECT texts)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | Readers busy |
|---|---|---|---|---|---|---|
| resqlite | 3299.6 | 3189.5 | 5.3 | 104.8 | 2048.0 | 0 |

### WAL after write burst (1000 inserted rows)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | Readers busy |
|---|---|---|---|---|---|---|
| resqlite | 260.9 | 240.0 | 5.3 | 15.6 | 161.0 | 0 |

## Repeat Stability

These rows summarize resqlite wall medians across repeated full-suite runs.
Use this section to judge whether small deltas are real or just noise.

| Benchmark | Median (ms) | 95% CI (ms) | MDE_ci | Range | MAD | Stability |
|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.05 | 0.04..0.05 | 8.7% | 17.4% | 2.2% | stable |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.02 | 0.02..0.02 | 11.1% | 22.2% | 5.6% | moderate |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.04 | 0.04..0.06 | 20.5% | 40.9% | 9.1% | noisy |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.04 | 0.03..0.05 | 16.7% | 33.3% | 5.6% | moderate |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.47 | 0.43..0.50 | 7.4% | 14.9% | 6.4% | moderate |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.47 | 0.43..0.50 | 7.4% | 14.9% | 6.4% | moderate |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.50 | 0.48..0.61 | 13.0% | 26.0% | 2.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.25 | 0.24..0.30 | 12.0% | 24.0% | 4.0% | moderate |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.54 | 0.52..0.58 | 5.6% | 11.1% | 3.7% | moderate |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.13 | 0.13..0.14 | 3.8% | 7.7% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 1.11 | 0.98..1.64 | 29.7% | 59.5% | 7.2% | moderate |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.14 | 0.12..0.20 | 28.6% | 57.1% | 7.1% | moderate |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.07 | 0.07..0.08 | 5.6% | 11.1% | 1.4% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.01 | 100.0% | 200.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 106.63 | 106.30..110.16 | 1.8% | 3.6% | 0.3% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 229.17 | 228.00..237.51 | 2.1% | 4.1% | 0.5% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 211.92 | 210.21..214.34 | 1.0% | 1.9% | 0.6% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 20.98 | 20.69..21.40 | 1.7% | 3.4% | 1.4% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 20.98 | 20.69..21.40 | 1.7% | 3.4% | 1.4% | stable |
| Point Query Throughput / resqlite qps | 64561.00 | 58030.00..70059.00 | 9.3% | 18.6% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.02 | 0.02..0.03 | 16.7% | 33.3% | 12.5% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.04 | 0.04..0.05 | 13.6% | 27.3% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.04 | 0.04..0.05 | 13.6% | 27.3% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 50.0% | 100.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.03 | 0.02..0.04 | 26.8% | 53.6% | 7.1% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.03 | 0.02..0.04 | 26.8% | 53.6% | 7.1% | moderate |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.07 | 0.07..0.08 | 8.1% | 16.2% | 4.1% | moderate |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.26 | 0.24..0.27 | 4.9% | 9.8% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.26 | 0.24..0.27 | 4.9% | 9.8% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 7.1% | 14.3% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.09 | 0.08..0.10 | 8.8% | 17.6% | 3.5% | moderate |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.09 | 0.08..0.10 | 8.8% | 17.6% | 3.5% | moderate |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.53 | 0.51..0.55 | 4.2% | 8.3% | 3.2% | moderate |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 2.52 | 2.20..2.55 | 6.9% | 13.9% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 2.52 | 2.20..2.55 | 6.9% | 13.9% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.07 | 0.07..0.07 | 2.1% | 4.2% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.70 | 0.66..0.78 | 8.5% | 17.0% | 2.4% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.70 | 0.66..0.78 | 8.5% | 17.0% | 2.4% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 9.21 | 7.62..10.66 | 16.5% | 33.0% | 11.1% | noisy |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 32.35 | 29.65..50.48 | 32.2% | 64.4% | 8.3% | noisy |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 32.35 | 29.65..50.48 | 32.2% | 64.4% | 8.3% | noisy |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.81 | 0.73..1.00 | 16.6% | 33.2% | 8.7% | noisy |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 7.36 | 6.94..8.08 | 7.7% | 15.5% | 5.6% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 7.36 | 6.94..8.08 | 7.7% | 15.5% | 5.6% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 1.18 | 1.10..1.29 | 8.0% | 16.0% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 6.50 | 5.78..10.81 | 38.7% | 77.4% | 4.9% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 6.50 | 5.78..10.81 | 38.7% | 77.4% | 4.9% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.14 | 0.14..0.15 | 4.5% | 9.1% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 1.68 | 1.60..1.76 | 4.8% | 9.6% | 2.7% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 1.68 | 1.60..1.76 | 4.8% | 9.6% | 2.7% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 20.90 | 19.17..25.45 | 15.0% | 30.0% | 4.0% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 68.09 | 65.59..72.92 | 5.4% | 10.8% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 68.09 | 65.59..72.92 | 5.4% | 10.8% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.77 | 1.63..2.00 | 10.5% | 21.1% | 4.5% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 16.83 | 13.88..18.25 | 13.0% | 25.9% | 8.4% | noisy |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 16.83 | 13.88..18.25 | 13.0% | 25.9% | 8.4% | noisy |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.04 | 0.04..0.05 | 8.9% | 17.8% | 6.7% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.14 | 0.13..0.14 | 4.2% | 8.5% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.14 | 0.13..0.14 | 4.2% | 8.5% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.05 | 0.05..0.07 | 18.5% | 37.0% | 11.1% | noisy |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.05 | 0.05..0.07 | 18.5% | 37.0% | 11.1% | noisy |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.28 | 0.27..0.28 | 2.5% | 5.1% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 1.19 | 1.13..1.30 | 7.2% | 14.4% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 1.19 | 1.13..1.30 | 7.2% | 14.4% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04..0.04 | 1.4% | 2.8% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.35 | 0.34..0.38 | 5.3% | 10.5% | 2.6% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.35 | 0.34..0.38 | 5.3% | 10.5% | 2.6% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 3.41 | 3.36..3.59 | 3.3% | 6.7% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 20.34 | 19.58..23.48 | 9.6% | 19.2% | 3.7% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 20.34 | 19.58..23.48 | 9.6% | 19.2% | 3.7% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.37 | 0.36..0.39 | 3.5% | 7.1% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 4.22 | 3.78..5.03 | 14.8% | 29.5% | 9.4% | noisy |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 4.22 | 3.78..5.03 | 14.8% | 29.5% | 9.4% | noisy |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.13 | 0.12..0.19 | 28.3% | 56.7% | 5.5% | moderate |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.03 | 0.03..0.09 | 112.5% | 225.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.36 | 0.35..0.39 | 5.7% | 11.4% | 1.9% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.07 | 0.07..0.07 | 2.2% | 4.3% | 1.4% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.36 | 0.35..0.36 | 2.5% | 5.1% | 2.2% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.07 | 0.07..0.07 | 3.5% | 7.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.98 | 0.95..1.01 | 3.1% | 6.2% | 2.7% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.07 | 0.07..0.08 | 3.4% | 6.8% | 2.7% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 1.24 | 1.20..1.35 | 6.0% | 12.0% | 2.5% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.27 | 0.26..0.27 | 1.3% | 2.6% | 0.7% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.04 | 0.04..0.09 | 65.5% | 131.0% | 7.1% | moderate |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02..0.05 | 80.0% | 160.0% | 5.0% | moderate |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.03 | 0.02..0.04 | 30.0% | 60.0% | 4.0% | moderate |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.26 | 0.25..0.34 | 15.8% | 31.6% | 0.8% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.19 | 0.19..0.24 | 14.7% | 29.5% | 1.1% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.09 | 0.08..0.10 | 8.7% | 17.4% | 1.2% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 2.56 | 2.37..3.37 | 19.4% | 38.8% | 1.4% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.95 | 1.89..2.52 | 16.1% | 32.2% | 2.3% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.70 | 0.68..0.73 | 3.4% | 6.7% | 2.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 29.67 | 29.55..40.17 | 17.9% | 35.8% | 0.4% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 20.78 | 20.65..21.84 | 2.9% | 5.7% | 0.6% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 7.25 | 6.96..7.76 | 5.5% | 11.0% | 2.7% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.01 | 25.0% | 50.0% | 12.5% | noisy |
| Select → Maps / 10 rows / resqlite select() | 0.03 | 0.02..0.14 | 232.0% | 464.0% | 8.0% | noisy |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.03 | 1200.0% | 2400.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.07 | 0.07..0.20 | 100.7% | 201.5% | 1.5% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 42.9% | 85.7% | 14.3% | noisy |
| Select → Maps / 1000 rows / resqlite select() | 0.52 | 0.50..0.58 | 8.1% | 16.2% | 1.5% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.06 | 0.06..0.08 | 16.4% | 32.8% | 1.6% | stable |
| Select → Maps / 10000 rows / resqlite select() | 8.31 | 7.57..8.96 | 8.4% | 16.8% | 4.8% | moderate |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.68 | 0.65..1.01 | 26.8% | 53.6% | 5.0% | moderate |
| Streaming / Fan-out (10 streams) / resqlite | 0.34 | 0.31..0.43 | 18.4% | 36.8% | 8.8% | noisy |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.34 | 0.31..0.43 | 18.4% | 36.8% | 8.8% | noisy |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.19 | 0.17..0.39 | 57.9% | 115.7% | 2.6% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.19 | 0.17..0.39 | 57.9% | 115.7% | 2.6% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.06 | 0.05..0.11 | 51.8% | 103.5% | 14.0% | noisy |
| Streaming / Initial Emission / resqlite stream() [main] | 0.06 | 0.05..0.11 | 51.8% | 103.5% | 14.0% | noisy |
| Streaming / Invalidation Latency / resqlite | 0.11 | 0.08..0.14 | 24.8% | 49.5% | 18.7% | noisy |
| Streaming / Invalidation Latency / resqlite [main] | 0.11 | 0.08..0.14 | 24.8% | 49.5% | 18.7% | noisy |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 0.16 | 0.13..0.16 | 11.5% | 22.9% | 3.8% | moderate |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 0.16 | 0.13..0.16 | 11.5% | 22.9% | 3.8% | moderate |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 6.32 | 5.98..8.70 | 21.5% | 43.1% | 3.3% | moderate |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 6.32 | 5.98..8.70 | 21.5% | 43.1% | 3.3% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite | 4.01 | 3.24..6.48 | 40.5% | 80.9% | 14.6% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 4.01 | 3.24..6.48 | 40.5% | 80.9% | 14.6% | noisy |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 15.47 | 14.17..19.20 | 16.2% | 32.5% | 6.8% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 15.47 | 14.17..19.20 | 16.2% | 32.5% | 6.8% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.33 | 0.31..0.72 | 63.2% | 126.5% | 4.3% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.33 | 0.31..0.72 | 63.2% | 126.5% | 4.3% | moderate |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.10 | 0.10..0.10 | 2.5% | 5.1% | 1.0% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.10 | 0.10..0.10 | 2.5% | 5.1% | 1.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.60 | 0.58..1.07 | 40.0% | 79.9% | 1.2% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.60 | 0.58..1.07 | 40.0% | 79.9% | 1.2% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 5.79 | 5.45..7.31 | 16.1% | 32.1% | 5.8% | moderate |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 5.79 | 5.45..7.31 | 16.1% | 32.1% | 5.8% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 1.43 | 1.24..2.25 | 35.4% | 70.7% | 13.4% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 1.43 | 1.24..2.25 | 35.4% | 70.7% | 13.4% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.14 | 0.13..0.18 | 18.0% | 36.0% | 7.9% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.14 | 0.13..0.18 | 18.0% | 36.0% | 7.9% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 13.56 | 12.46..16.98 | 16.7% | 33.3% | 8.1% | noisy |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 13.56 | 12.46..16.98 | 16.7% | 33.3% | 8.1% | noisy |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.65 | 0.62..0.83 | 16.3% | 32.6% | 4.5% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.65 | 0.62..0.83 | 16.3% | 32.6% | 4.5% | moderate |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.10 | 0.09..0.11 | 11.9% | 23.8% | 8.9% | noisy |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.10 | 0.09..0.11 | 11.9% | 23.8% | 8.9% | noisy |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.23 | 0.19..0.27 | 17.0% | 33.9% | 13.7% | noisy |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.23 | 0.19..0.27 | 17.0% | 33.9% | 13.7% | noisy |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 2.77 | 2.25..2.94 | 12.4% | 24.8% | 6.1% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 2.77 | 2.25..2.94 | 12.4% | 24.8% | 6.1% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 3.12 | 2.63..3.64 | 16.1% | 32.2% | 8.7% | noisy |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 3.12 | 2.63..3.64 | 16.1% | 32.2% | 8.7% | noisy |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.28 | 0.27..0.37 | 18.2% | 36.3% | 2.5% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.28 | 0.27..0.37 | 18.2% | 36.3% | 2.5% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.16 | 0.15..0.18 | 7.9% | 15.9% | 3.0% | moderate |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.16 | 0.15..0.18 | 7.9% | 15.9% | 3.0% | moderate |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 19.52 | 19.18..25.12 | 15.2% | 30.5% | 1.4% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 19.52 | 19.18..25.12 | 15.2% | 30.5% | 1.4% | stable |


## Comparison

Automatic comparison skipped because `2026-06-09T11-20-00-exp150-nullable-batch-packing.md` was not captured in a compatible environment:
- baseline sidecar is missing environment metadata

Use `--compare-to=benchmark/results/2026-06-09T11-20-00-exp150-nullable-batch-packing.md` to run an explicit reference comparison anyway.


