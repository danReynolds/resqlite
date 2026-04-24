# resqlite Benchmark Results

Generated: 2026-04-23T19:08:51.021782

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp094-dirty-read-string-reuse`
- Repeats: `3`
- Runtime: `dart-vm / Dart 3.11.0`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `codex/benchmark-contract-goldens @ 02da8b80915d (dirty)`
- Comparison baseline: `2026-04-23T18-44-25-internal-perf-review.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.012 | 0.018 | 0.001 | 0.001 |
| sqlite3 select() | 0.016 | 0.016 | 0.016 | 0.016 |
| sqlite_async select() | 0.033 | 0.037 | 0.001 | 0.002 |
| drift select() | 0.059 | 0.088 | 0.002 | 0.003 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.048 | 0.060 | 0.009 | 0.010 |
| sqlite3 select() | 0.120 | 0.152 | 0.120 | 0.152 |
| sqlite_async select() | 0.124 | 0.141 | 0.010 | 0.012 |
| drift select() | 0.186 | 0.221 | 0.010 | 0.011 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.381 | 0.434 | 0.088 | 0.100 |
| sqlite3 select() | 1.123 | 1.230 | 1.123 | 1.230 |
| sqlite_async select() | 1.042 | 1.218 | 0.096 | 0.102 |
| drift select() | 1.681 | 2.061 | 0.096 | 0.100 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.534 | 12.054 | 0.874 | 1.402 |
| sqlite3 select() | 15.166 | 18.696 | 15.166 | 18.696 |
| sqlite_async select() | 13.882 | 20.585 | 0.991 | 1.649 |
| drift select() | 25.072 | 30.688 | 1.003 | 4.596 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.032 | 0.041 | 0.016 | 0.019 |
| sqlite3 + jsonEncode | 0.031 | 0.032 | 0.031 | 0.032 |
| sqlite_async + jsonEncode | 0.050 | 0.051 | 0.016 | 0.017 |
| drift + jsonEncode | 0.078 | 0.098 | 0.018 | 0.023 |
| resqlite selectBytes() | 0.019 | 0.023 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.208 | 0.255 | 0.160 | 0.176 |
| sqlite3 + jsonEncode | 0.306 | 0.885 | 0.306 | 0.885 |
| sqlite_async + jsonEncode | 0.282 | 0.333 | 0.160 | 0.177 |
| drift + jsonEncode | 0.330 | 0.398 | 0.154 | 0.164 |
| resqlite selectBytes() | 0.046 | 0.048 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.922 | 4.133 | 1.553 | 3.572 |
| sqlite3 + jsonEncode | 2.532 | 4.212 | 2.532 | 4.212 |
| sqlite_async + jsonEncode | 2.601 | 5.164 | 1.516 | 2.307 |
| drift + jsonEncode | 3.225 | 5.697 | 1.557 | 2.532 |
| resqlite selectBytes() | 0.356 | 0.417 | 0.000 | 0.001 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 21.725 | 28.207 | 16.060 | 18.726 |
| sqlite3 + jsonEncode | 33.780 | 38.548 | 33.780 | 38.548 |
| sqlite_async + jsonEncode | 31.403 | 46.060 | 16.130 | 18.114 |
| drift + jsonEncode | 42.527 | 48.940 | 15.619 | 19.471 |
| resqlite selectBytes() | 4.898 | 9.638 | 0.005 | 0.014 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.104 | 0.118 | 0.036 | 0.038 |
| sqlite3 | 0.332 | 0.339 | 0.332 | 0.339 |
| sqlite_async | 0.371 | 0.495 | 0.043 | 0.050 |
| drift | 0.639 | 0.768 | 0.044 | 0.052 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.907 | 1.036 | 0.270 | 0.292 |
| sqlite3 | 3.331 | 3.905 | 3.331 | 3.905 |
| sqlite_async | 3.024 | 3.599 | 0.336 | 0.349 |
| drift | 5.135 | 6.804 | 0.356 | 0.393 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.582 | 0.646 | 0.106 | 0.112 |
| sqlite3 | 1.557 | 2.343 | 1.557 | 2.343 |
| sqlite_async | 1.386 | 1.684 | 0.117 | 0.126 |
| drift | 2.229 | 2.916 | 0.128 | 0.138 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.295 | 0.299 | 0.098 | 0.102 |
| sqlite3 | 1.036 | 1.198 | 1.036 | 1.198 |
| sqlite_async | 0.957 | 1.122 | 0.117 | 0.146 |
| drift | 1.553 | 1.891 | 0.117 | 0.126 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.291 | 0.313 | 0.096 | 0.101 |
| sqlite3 | 0.974 | 1.029 | 0.974 | 1.029 |
| sqlite_async | 0.906 | 1.141 | 0.114 | 0.133 |
| drift | 1.457 | 1.656 | 0.114 | 0.124 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.012 | 0.014 | 0.001 | 0.001 |
| sqlite3 | 0.015 | 0.016 | 0.015 | 0.016 |
| sqlite_async | 0.032 | 0.051 | 0.001 | 0.002 |
| drift | 0.044 | 0.062 | 0.001 | 0.002 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.028 | 0.033 | 0.004 | 0.005 |
| sqlite3 | 0.062 | 0.063 | 0.062 | 0.063 |
| sqlite_async | 0.072 | 0.089 | 0.005 | 0.006 |
| drift | 0.104 | 0.129 | 0.005 | 0.005 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.047 | 0.050 | 0.009 | 0.009 |
| sqlite3 | 0.118 | 0.129 | 0.118 | 0.129 |
| sqlite_async | 0.124 | 0.130 | 0.010 | 0.010 |
| drift | 0.180 | 0.216 | 0.010 | 0.011 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.187 | 0.192 | 0.042 | 0.042 |
| sqlite3 | 0.554 | 0.615 | 0.554 | 0.615 |
| sqlite_async | 0.538 | 0.580 | 0.048 | 0.052 |
| drift | 0.816 | 1.048 | 0.046 | 0.067 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.386 | 0.437 | 0.088 | 0.092 |
| sqlite3 | 1.115 | 1.243 | 1.115 | 1.243 |
| sqlite_async | 1.046 | 1.251 | 0.094 | 0.101 |
| drift | 1.629 | 2.069 | 0.094 | 0.107 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.820 | 0.900 | 0.176 | 0.187 |
| sqlite3 | 2.213 | 2.785 | 2.213 | 2.785 |
| sqlite_async | 2.150 | 2.661 | 0.191 | 0.223 |
| drift | 3.400 | 4.035 | 0.192 | 0.221 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.254 | 6.319 | 0.441 | 0.535 |
| sqlite3 | 6.154 | 8.887 | 6.154 | 8.887 |
| sqlite_async | 5.893 | 7.474 | 0.480 | 0.516 |
| drift | 9.137 | 10.268 | 0.481 | 0.505 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.714 | 13.065 | 0.887 | 1.427 |
| sqlite3 | 15.374 | 17.783 | 15.374 | 17.783 |
| sqlite_async | 13.990 | 17.187 | 0.960 | 2.092 |
| drift | 23.863 | 33.779 | 0.990 | 4.379 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 9.151 | 20.512 | 1.723 | 1.834 |
| sqlite3 | 36.232 | 42.883 | 36.232 | 42.883 |
| sqlite_async | 39.099 | 50.033 | 1.914 | 3.241 |
| drift | 53.053 | 73.416 | 1.915 | 7.785 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.027 | 0.030 | 0.027 | 0.030 |
| sqlite3 + jsonEncode | 0.031 | 0.033 | 0.031 | 0.033 |
| sqlite_async + jsonEncode | 0.048 | 0.068 | 0.048 | 0.068 |
| drift + jsonEncode | 0.057 | 0.094 | 0.057 | 0.094 |
| resqlite selectBytes() | 0.012 | 0.033 | 0.012 | 0.033 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.105 | 0.160 | 0.105 | 0.160 |
| sqlite3 + jsonEncode | 0.154 | 0.482 | 0.154 | 0.482 |
| sqlite_async + jsonEncode | 0.153 | 0.192 | 0.153 | 0.192 |
| drift + jsonEncode | 0.178 | 0.207 | 0.178 | 0.207 |
| resqlite selectBytes() | 0.027 | 0.037 | 0.027 | 0.037 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.190 | 0.202 | 0.190 | 0.202 |
| sqlite3 + jsonEncode | 0.258 | 0.279 | 0.258 | 0.279 |
| sqlite_async + jsonEncode | 0.273 | 0.312 | 0.273 | 0.312 |
| drift + jsonEncode | 0.334 | 0.373 | 0.334 | 0.373 |
| resqlite selectBytes() | 0.047 | 0.056 | 0.047 | 0.056 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.919 | 1.546 | 0.919 | 1.546 |
| sqlite3 + jsonEncode | 1.305 | 3.840 | 1.305 | 3.840 |
| sqlite_async + jsonEncode | 1.276 | 2.228 | 1.276 | 2.228 |
| drift + jsonEncode | 1.602 | 2.062 | 1.602 | 2.062 |
| resqlite selectBytes() | 0.194 | 0.246 | 0.194 | 0.246 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 2.034 | 6.837 | 2.034 | 6.837 |
| sqlite3 + jsonEncode | 2.701 | 5.572 | 2.701 | 5.572 |
| sqlite_async + jsonEncode | 2.542 | 4.303 | 2.542 | 4.303 |
| drift + jsonEncode | 3.217 | 5.162 | 3.217 | 5.162 |
| resqlite selectBytes() | 0.352 | 0.393 | 0.352 | 0.393 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.977 | 9.021 | 3.977 | 9.021 |
| sqlite3 + jsonEncode | 5.776 | 12.072 | 5.776 | 12.072 |
| sqlite_async + jsonEncode | 5.679 | 11.434 | 5.679 | 11.434 |
| drift + jsonEncode | 6.876 | 13.742 | 6.876 | 13.742 |
| resqlite selectBytes() | 0.824 | 1.366 | 0.824 | 1.366 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 10.032 | 15.222 | 10.032 | 15.222 |
| sqlite3 + jsonEncode | 16.533 | 31.089 | 16.533 | 31.089 |
| sqlite_async + jsonEncode | 15.609 | 23.022 | 15.609 | 23.022 |
| drift + jsonEncode | 17.400 | 24.583 | 17.400 | 24.583 |
| resqlite selectBytes() | 2.007 | 4.528 | 2.007 | 4.528 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 24.413 | 33.371 | 24.413 | 33.371 |
| sqlite3 + jsonEncode | 31.824 | 37.800 | 31.824 | 37.800 |
| sqlite_async + jsonEncode | 33.352 | 41.105 | 33.352 | 41.105 |
| drift + jsonEncode | 42.370 | 47.910 | 42.370 | 47.910 |
| resqlite selectBytes() | 3.944 | 7.467 | 3.944 | 7.467 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 46.961 | 55.846 | 46.961 | 55.846 |
| sqlite3 + jsonEncode | 69.130 | 97.820 | 69.130 | 97.820 |
| sqlite_async + jsonEncode | 75.466 | 108.027 | 75.466 | 108.027 |
| drift + jsonEncode | 87.573 | 111.061 | 87.573 | 111.061 |
| resqlite selectBytes() | 8.287 | 14.635 | 8.287 | 14.635 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.36 | 0.30 |
| sqlite_async | 1.01 | 1.36 | 1.01 |
| drift | 1.55 | 1.68 | 1.55 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.32 | 0.36 | 0.16 |
| sqlite_async | 1.39 | 1.64 | 0.69 |
| drift | 2.90 | 5.20 | 1.45 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.37 | 0.91 | 0.09 |
| sqlite_async | 2.17 | 2.87 | 0.54 |
| drift | 5.43 | 5.96 | 1.36 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.68 | 1.12 | 0.08 |
| sqlite_async | 5.00 | 5.56 | 0.63 |
| drift | 10.98 | 11.81 | 1.37 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 117778 |
| resqlite per query | 0.008 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 117778 | 114646..120614 | 2.5 | 7.8 |
| sqlite3 | 186156 | 169775..186935 | 4.6 | 3.6 |
| sqlite_async | 44743 | 39457..46349 | 7.7 | 13.6 |
| drift | 41577 | 35841..41851 | 7.2 | 6.8 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.964 | 17.090 | 14.964 | 17.090 |
| sqlite_async | 36.959 | 38.312 | 36.959 | 38.312 |
| drift | 55.285 | 63.394 | 55.285 | 63.394 |
| sqlite3 (no cache) | 25.203 | 26.596 | 25.203 | 26.596 |
| sqlite3 (cached stmt) | 24.758 | 28.263 | 24.758 | 28.263 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.877 | 3.098 | 1.877 | 3.098 |
| sqlite3 execute() | 1.245 | 3.073 | 1.245 | 3.073 |
| sqlite_async execute() | 3.208 | 3.896 | 3.208 | 3.896 |
| drift execute() | 3.205 | 3.846 | 3.205 | 3.846 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.057 | 0.069 | 0.057 | 0.069 |
| sqlite3 executeBatch() | 0.050 | 0.065 | 0.050 | 0.065 |
| sqlite_async executeBatch() | 0.100 | 0.118 | 0.100 | 0.118 |
| drift executeBatch() | 0.122 | 0.167 | 0.122 | 0.167 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.429 | 0.637 | 0.429 | 0.637 |
| sqlite3 executeBatch() | 0.436 | 0.472 | 0.436 | 0.472 |
| sqlite_async executeBatch() | 0.534 | 0.616 | 0.534 | 0.616 |
| drift executeBatch() | 0.698 | 0.820 | 0.698 | 0.820 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.816 | 5.667 | 4.816 | 5.667 |
| sqlite3 executeBatch() | 4.497 | 4.690 | 4.497 | 4.690 |
| sqlite_async executeBatch() | 5.245 | 5.626 | 5.245 | 5.626 |
| drift executeBatch() | 6.938 | 9.328 | 6.938 | 9.328 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.059 | 0.123 | 0.059 | 0.123 |
| sqlite_async writeTransaction() | 0.113 | 0.226 | 0.113 | 0.226 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.079 | 0.152 | 0.079 | 0.152 |
| resqlite tx.execute() loop | 0.746 | 0.991 | 0.746 | 0.991 |
| sqlite_async tx.execute() loop | 1.160 | 1.474 | 1.160 | 1.474 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.490 | 0.714 | 0.490 | 0.714 |
| resqlite tx.execute() loop | 6.964 | 9.429 | 6.964 | 9.429 |
| sqlite_async tx.execute() loop | 10.644 | 12.887 | 10.644 | 12.887 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.105 | 0.110 | 0.105 | 0.110 |
| sqlite_async tx.getAll() | 0.208 | 0.241 | 0.208 | 0.241 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.187 | 0.221 | 0.187 | 0.221 |
| sqlite_async tx.getAll() | 0.376 | 0.420 | 0.376 | 0.420 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.035 | 0.045 | 0.035 | 0.045 |
| sqlite_async watch() | 0.114 | 0.123 | 0.114 | 0.123 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.045 | 0.057 | 0.045 | 0.057 |
| sqlite_async | 0.055 | 0.105 | 0.055 | 0.105 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.199 | 0.243 | 0.199 | 0.243 |
| sqlite_async | 0.553 | 2.203 | 0.553 | 2.203 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.239 | 0.329 | 0.239 | 0.329 |
| sqlite_async | 0.273 | 0.348 | 0.273 | 0.348 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.776 | 1.776 | 1.776 | 1.776 |
| sqlite_async | 9.622 | 9.622 | 9.622 | 9.622 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.732 | 4.251 | 3.732 | 4.251 |
| sqlite_async | 6.356 | 10.264 | 6.356 | 10.264 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.598 | 0.748 | 0.598 | 0.748 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 7.516 | 8.669 | 7.516 | 8.669 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. On resqlite's main branch this ratio is driven toward 0 by experiment 075 (C-side result-hash short-circuit), not by writer-side column-tracking (exp 052 is not implemented). The two mechanisms are indistinguishable on this read-side benchmark.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 77.3 | 0.000 |
| sqlite_async | 3251 | 978.3 | 0.929 |
| drift | 5000 | 1186.6 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 78.1 | 0.000 |
| sqlite_async | 3500 | 927.5 | 0.929 |
| drift | 5000 | 1097.2 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 218.12 | 223.61 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 435.84 | 438.12 | 0.00 | 0.00 | 1202 | 3 |
| drift stream() | 593.70 | 632.82 | 0.15 | 0.34 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.025 | 0.042 | 0.000 | 0.000 |
| sqlite3 | 0.022 | 0.049 | 0.022 | 0.049 |
| sqlite_async | 0.045 | 0.069 | 0.000 | 0.000 |
| drift | 0.045 | 0.066 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.018 | 0.029 | 0.000 | 0.000 |
| sqlite3 | 0.014 | 0.027 | 0.014 | 0.027 |
| sqlite_async | 0.037 | 0.053 | 0.000 | 0.000 |
| drift | 0.036 | 0.052 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.027 | 0.040 | 0.000 | 0.000 |
| sqlite3 | 0.032 | 0.037 | 0.032 | 0.037 |
| sqlite_async | 0.060 | 0.076 | 0.000 | 0.000 |
| drift | 0.056 | 0.068 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.009 | 0.018 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.007 | 0.005 | 0.007 |
| sqlite_async | 0.022 | 0.028 | 0.000 | 0.000 |
| drift | 0.022 | 0.030 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.041 | 0.046 | 0.001 | 0.001 |
| sqlite3 | 0.063 | 0.066 | 0.063 | 0.066 |
| sqlite_async | 0.081 | 0.111 | 0.001 | 0.001 |
| drift | 0.103 | 0.128 | 0.001 | 0.002 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 109.273 | 110.000 | 0.000 | 0.000 | 0 |
| sqlite_async | 211.842 | 212.342 | 0.000 | 0.000 | 47 |
| drift | 221.441 | 241.810 | 0.000 | 0.001 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 230.45 | 230.45 | 0.00 | 0.00 | 12.45 | 218.22 | 0 |
| sqlite_async | 489.43 | 489.43 | 0.01 | 0.01 | 22.98 | 467.07 | 1194 |
| drift | 1821.26 | 1821.26 | 0.87 | 0.87 | 16.56 | 1804.69 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 1.27 | 13.81 | 0.00..9.70 | ±4.85 |
| sqlite3 select() | 2.13 | 8.56 | 0.00..7.19 | ±3.59 |
| sqlite_async select() | 1.00 | 3.50 | 0.50..1.50 | ±0.50 |
| drift select() | 3.02 | 49.33 | 0.00..22.03 | ±11.02 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 9.05 | 0.00..8.02 | ±4.01 |
| resqlite + jsonEncode | 0.00 | 111.20 | 0.00..20.48 | ±10.24 |
| sqlite3 + jsonEncode | 0.00 | 33.14 | 0.00..9.36 | ±4.68 |
| sqlite_async + jsonEncode | 0.00 | 6.14 | 0.00..0.00 | ±0.00 |
| drift + jsonEncode | 0.30 | 87.53 | 0.00..7.00 | ±3.50 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.00 | 33.78 | 0.00..25.84 | ±12.92 |
| sqlite3 executeBatch() | 0.00 | 0.08 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 0.08 | 0.00..0.02 | ±0.01 |
| drift batch() | 0.00 | 2.00 | 0.00..0.05 | ±0.02 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.06 | 0.00..0.06 | ±0.03 |
| sqlite_async watch() | 0.00 | 0.56 | 0.00..0.05 | ±0.02 |

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

## Repeat Stability

These rows summarize resqlite wall medians across repeated full-suite runs.
Use this section to judge whether small deltas are real or just noise.

| Benchmark | Median (ms) | 95% CI (ms) | MDE_ci | Range | MAD | Stability |
|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.03 | 0.03..0.03 | 6.9% | 6.9% | 0.0% | stable |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 10.0% | 10.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.03 | 0.03..0.03 | 14.3% | 14.3% | 3.6% | moderate |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02..0.02 | 15.0% | 15.0% | 5.0% | moderate |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.30 | 0.28..0.31 | 10.0% | 10.0% | 3.3% | moderate |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.30 | 0.28..0.31 | 10.0% | 10.0% | 3.3% | moderate |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.33 | 0.32..0.55 | 69.7% | 69.7% | 3.0% | moderate |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.17 | 0.16..0.27 | 64.7% | 64.7% | 5.9% | moderate |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.38 | 0.37..0.66 | 76.3% | 76.3% | 2.6% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.09 | 0.09..0.16 | 77.8% | 77.8% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.74 | 0.68..1.71 | 139.2% | 139.2% | 8.1% | noisy |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.09 | 0.08..0.21 | 144.4% | 144.4% | 11.1% | noisy |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.04 | 7.3% | 7.3% | 2.4% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 300.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 109.10 | 105.28..109.27 | 3.7% | 3.7% | 0.2% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 230.45 | 230.40..250.73 | 8.8% | 8.8% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 218.12 | 217.18..221.19 | 1.8% | 1.8% | 0.4% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 14.77 | 14.72..14.96 | 1.7% | 1.7% | 0.4% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 14.77 | 14.72..14.96 | 1.7% | 1.7% | 0.4% | stable |
| Point Query Throughput / resqlite qps | 103752.00 | 95420.00..117778.00 | 21.5% | 21.5% | 8.0% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.02 | 30.8% | 30.8% | 7.7% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.04 | 55.2% | 55.2% | 6.9% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.04 | 55.2% | 55.2% | 6.9% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 100.0% | 100.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 91.7% | 91.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.02 | 91.7% | 91.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.04..0.05 | 14.9% | 14.9% | 4.3% | moderate |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.20 | 0.19..0.21 | 11.1% | 11.1% | 4.5% | moderate |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.20 | 0.19..0.21 | 11.1% | 11.1% | 4.5% | moderate |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.05 | 0.05..0.05 | 12.8% | 12.8% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.05 | 0.05..0.05 | 12.8% | 12.8% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.38 | 0.37..0.39 | 4.7% | 4.7% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.91 | 1.83..2.03 | 10.8% | 10.8% | 4.5% | moderate |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.91 | 1.83..2.03 | 10.8% | 10.8% | 4.5% | moderate |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.08..0.09 | 4.6% | 4.6% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.37 | 0.35..0.38 | 7.1% | 7.1% | 3.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.37 | 0.35..0.38 | 7.1% | 7.1% | 3.0% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.71 | 4.55..5.12 | 12.0% | 12.0% | 3.5% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 22.70 | 21.19..24.41 | 14.2% | 14.2% | 6.6% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 22.70 | 21.19..24.41 | 14.2% | 14.2% | 6.6% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.88 | 0.85..0.89 | 3.6% | 3.6% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 4.03 | 3.94..4.30 | 8.8% | 8.8% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 4.03 | 3.94..4.30 | 8.8% | 8.8% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.82 | 0.82..0.87 | 6.3% | 6.3% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.98 | 3.90..3.98 | 2.0% | 2.0% | 0.1% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.98 | 3.90..3.98 | 2.0% | 2.0% | 0.1% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.18 | 0.18..0.18 | 1.1% | 1.1% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.89 | 0.82..0.90 | 8.1% | 8.1% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.89 | 0.82..0.90 | 8.1% | 8.1% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 11.28 | 9.15..16.82 | 68.0% | 68.0% | 18.9% | noisy |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 47.94 | 46.96..48.42 | 3.0% | 3.0% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 47.94 | 46.96..48.42 | 3.0% | 3.0% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.75 | 1.72..1.81 | 5.1% | 5.1% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 7.95 | 7.80..8.29 | 6.1% | 6.1% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 7.95 | 7.80..8.29 | 6.1% | 6.1% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03..0.04 | 24.2% | 24.2% | 9.1% | noisy |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10..0.13 | 21.9% | 21.9% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.10 | 0.10..0.13 | 21.9% | 21.9% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.01 | 25.0% | 25.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.03..0.04 | 31.0% | 31.0% | 6.9% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.03..0.04 | 31.0% | 31.0% | 6.9% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.20 | 0.19..0.20 | 7.6% | 7.6% | 2.5% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.92 | 0.90..0.93 | 2.8% | 2.8% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.92 | 0.90..0.93 | 2.8% | 2.8% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04..0.04 | 6.7% | 6.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.19 | 0.19..0.20 | 4.1% | 4.1% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.19 | 0.19..0.20 | 4.1% | 4.1% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.28 | 2.25..2.48 | 9.8% | 9.8% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 10.12 | 10.03..10.29 | 2.5% | 2.5% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 10.12 | 10.03..10.29 | 2.5% | 2.5% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.45 | 0.44..0.45 | 2.2% | 2.2% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 2.01 | 1.97..2.04 | 3.7% | 3.7% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 2.01 | 1.97..2.04 | 3.7% | 3.7% | 1.7% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.10 | 0.10..0.14 | 35.6% | 35.6% | 2.9% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.04 | 0.03..0.04 | 11.1% | 11.1% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.30 | 0.29..0.30 | 4.3% | 4.3% | 0.3% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.10 | 0.10..0.10 | 5.0% | 5.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.29 | 0.28..0.29 | 5.4% | 5.4% | 0.3% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.10 | 0.09..0.10 | 5.2% | 5.2% | 1.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.58 | 0.58..0.58 | 0.9% | 0.9% | 0.3% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.11 | 0.10..0.11 | 1.9% | 1.9% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.91 | 0.91..1.22 | 34.4% | 34.4% | 0.1% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.27 | 0.27..0.30 | 12.2% | 12.2% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.13 | 318.8% | 318.8% | 18.8% | noisy |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.01..0.10 | 525.0% | 525.0% | 6.3% | moderate |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.02 | 0.01..0.02 | 68.4% | 68.4% | 26.3% | noisy |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.21 | 0.20..0.23 | 14.9% | 14.9% | 2.9% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.16 | 0.16..0.18 | 11.2% | 11.2% | 0.6% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.04..0.06 | 30.4% | 30.4% | 4.3% | moderate |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.92 | 1.88..2.09 | 10.8% | 10.8% | 2.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.55 | 1.53..1.65 | 7.3% | 7.3% | 1.3% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.37 | 0.36..0.37 | 4.6% | 4.6% | 1.1% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 21.95 | 21.73..22.62 | 4.1% | 4.1% | 1.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 15.80 | 15.69..16.06 | 2.4% | 2.4% | 0.7% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 4.25 | 4.04..4.90 | 20.2% | 20.2% | 5.0% | moderate |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.01 | 40.0% | 40.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.09 | 571.4% | 571.4% | 14.3% | noisy |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 1150.0% | 1150.0% | 50.0% | noisy |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.05..0.07 | 37.5% | 37.5% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 11.1% | 11.1% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.38 | 0.36..0.42 | 15.5% | 15.5% | 4.2% | moderate |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.08 | 0.07..0.09 | 16.7% | 16.7% | 4.8% | moderate |
| Select → Maps / 10000 rows / resqlite select() | 4.61 | 4.53..4.83 | 6.4% | 6.4% | 1.6% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.87 | 0.70..0.90 | 22.8% | 22.8% | 2.6% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.24 | 0.23..0.30 | 29.3% | 29.3% | 2.1% | stable |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.24 | 0.23..0.30 | 29.3% | 29.3% | 2.1% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.55 | 0.53..0.60 | 12.8% | 12.8% | 3.1% | moderate |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.55 | 0.53..0.60 | 12.8% | 12.8% | 3.1% | moderate |
| Streaming / Initial Emission / resqlite stream() | 0.04 | 0.03..0.04 | 22.9% | 22.9% | 8.6% | noisy |
| Streaming / Initial Emission / resqlite stream() [main] | 0.04 | 0.03..0.04 | 22.9% | 22.9% | 8.6% | noisy |
| Streaming / Invalidation Latency / resqlite | 0.06 | 0.04..0.07 | 33.9% | 33.9% | 10.2% | noisy |
| Streaming / Invalidation Latency / resqlite [main] | 0.06 | 0.04..0.07 | 33.9% | 33.9% | 10.2% | noisy |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.83 | 3.73..3.87 | 3.7% | 3.7% | 1.1% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.83 | 3.73..3.87 | 3.7% | 3.7% | 1.1% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.89 | 1.78..3.32 | 81.9% | 81.9% | 5.9% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.89 | 1.78..3.32 | 81.9% | 81.9% | 5.9% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 7.52 | 7.16..7.81 | 8.7% | 8.7% | 3.9% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 7.52 | 7.16..7.81 | 8.7% | 8.7% | 3.9% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.23 | 0.20..0.29 | 42.3% | 42.3% | 12.3% | noisy |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.23 | 0.20..0.29 | 42.3% | 42.3% | 12.3% | noisy |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.06..0.07 | 15.5% | 15.5% | 1.7% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.06 | 0.06..0.07 | 15.5% | 15.5% | 1.7% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.45 | 0.43..0.64 | 48.3% | 48.3% | 3.6% | moderate |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.45 | 0.43..0.64 | 48.3% | 48.3% | 3.6% | moderate |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.87 | 4.82..5.22 | 8.4% | 8.4% | 1.0% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.87 | 4.82..5.22 | 8.4% | 8.4% | 1.0% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.75 | 0.68..0.82 | 19.6% | 19.6% | 9.0% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.75 | 0.68..0.82 | 19.6% | 19.6% | 9.0% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.08 | 0.07..0.08 | 5.1% | 5.1% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.08 | 0.07..0.08 | 5.1% | 5.1% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 6.96 | 6.37..7.92 | 22.2% | 22.2% | 8.6% | noisy |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 6.96 | 6.37..7.92 | 22.2% | 22.2% | 8.6% | noisy |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.49 | 0.49..0.54 | 9.1% | 9.1% | 0.4% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.49 | 0.49..0.54 | 9.1% | 9.1% | 0.4% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.06 | 0.05..0.06 | 15.3% | 15.3% | 5.1% | moderate |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.06 | 0.05..0.06 | 15.3% | 15.3% | 5.1% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 2.00 | 1.88..2.13 | 12.8% | 12.8% | 6.0% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 2.00 | 1.88..2.13 | 12.8% | 12.8% | 6.0% | moderate |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.18..0.22 | 17.1% | 17.1% | 1.1% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.18..0.22 | 17.1% | 17.1% | 1.1% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.11 | 0.10..0.12 | 17.1% | 17.1% | 5.4% | moderate |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.11 | 0.10..0.12 | 17.1% | 17.1% | 5.4% | moderate |


## Comparison vs Previous Run

Previous: `2026-04-23T18-44-25-internal-perf-review.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 6.9% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | 10.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.03 | 0.03 | -0.00 | ±14% / ±0.02 ms | 14.3% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02 | -0.00 | ±15% / ±0.02 ms | 15.0% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.30 | +0.00 | ±10% / ±0.03 ms | 10.0% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.30 | +0.00 | ±10% / ±0.03 ms | 10.0% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.30 | 0.33 | +0.03 | ±70% / ±0.23 ms | 69.7% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.15 | 0.17 | +0.02 | ±65% / ±0.11 ms | 64.7% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.36 | 0.38 | +0.02 | ±76% / ±0.29 ms | 76.3% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.09 | 0.09 | +0.00 | ±78% / ±0.07 ms | 77.8% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.66 | 0.74 | +0.08 | ±139% / ±1.03 ms | 139.2% | noisy | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.08 | 0.09 | +0.01 | ±144% / ±0.13 ms | 144.4% | noisy | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 7.3% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±300% / ±0.02 ms | 300.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 110.22 | 109.10 | -1.12 | ±10% / ±11.02 ms | 3.7% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 238.40 | 230.45 | -7.95 | ±10% / ±23.84 ms | 8.8% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 220.53 | 218.12 | -2.41 | ±10% / ±22.05 ms | 1.8% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.11 | 14.77 | +0.66 | ±10% / ±1.48 ms | 1.7% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.11 | 14.77 | +0.66 | ±10% / ±1.48 ms | 1.7% | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 143726.00 | 103752.00 | -39974.00 | ±24% / ±34626.56 ms | 21.5% | noisy | 🔴 Regression (-28%) |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01 | +0.00 | ±31% / ±0.02 ms | 30.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±55% / ±0.02 ms | 55.2% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.03 | +0.00 | ±55% / ±0.02 ms | 55.2% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±100% / ±0.02 ms | 100.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±92% / ±0.02 ms | 91.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±92% / ±0.02 ms | 91.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05 | +0.00 | ±15% / ±0.02 ms | 14.9% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.20 | +0.01 | ±14% / ±0.03 ms | 11.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.20 | +0.01 | ±14% / ±0.03 ms | 11.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.05 | +0.00 | ±13% / ±0.02 ms | 12.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.05 | +0.00 | ±13% / ±0.02 ms | 12.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.37 | 0.38 | +0.01 | ±10% / ±0.04 ms | 4.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.88 | 1.91 | +0.04 | ±13% / ±0.26 ms | 10.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.88 | 1.91 | +0.04 | ±13% / ±0.26 ms | 10.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 4.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.37 | +0.01 | ±10% / ±0.04 ms | 7.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.37 | +0.01 | ±10% / ±0.04 ms | 7.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.31 | 4.71 | +0.41 | ±12% / ±0.57 ms | 12.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 20.73 | 22.70 | +1.96 | ±20% / ±4.51 ms | 14.2% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 20.73 | 22.70 | +1.96 | ±20% / ±4.51 ms | 14.2% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.85 | 0.88 | +0.03 | ±10% / ±0.09 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.58 | 4.03 | +0.44 | ±10% / ±0.40 ms | 8.8% | stable | 🔴 Regression (+12%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.58 | 4.03 | +0.44 | ±10% / ±0.40 ms | 8.8% | stable | 🔴 Regression (+12%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.76 | 0.82 | +0.06 | ±10% / ±0.08 ms | 6.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.85 | 3.98 | +0.13 | ±10% / ±0.40 ms | 2.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.85 | 3.98 | +0.13 | ±10% / ±0.40 ms | 2.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.17 | 0.18 | +0.01 | ±10% / ±0.02 ms | 1.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.74 | 0.89 | +0.15 | ±10% / ±0.09 ms | 8.1% | stable | 🔴 Regression (+20%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.74 | 0.89 | +0.15 | ±10% / ±0.09 ms | 8.1% | stable | 🔴 Regression (+20%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.43 | 11.28 | +0.85 | ±68% / ±7.67 ms | 68.0% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 43.46 | 47.94 | +4.48 | ±10% / ±4.79 ms | 3.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 43.46 | 47.94 | +4.48 | ±10% / ±4.79 ms | 3.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.71 | 1.75 | +0.05 | ±10% / ±0.18 ms | 5.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.34 | 7.95 | -0.39 | ±10% / ±0.83 ms | 6.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.34 | 7.95 | -0.39 | ±10% / ±0.83 ms | 6.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03 | +0.00 | ±27% / ±0.02 ms | 24.2% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10 | +0.00 | ±22% / ±0.02 ms | 21.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.10 | 0.10 | +0.00 | ±22% / ±0.02 ms | 21.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±25% / ±0.02 ms | 25.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.03 | +0.01 | ±31% / ±0.02 ms | 31.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.03 | +0.01 | ±31% / ±0.02 ms | 31.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.19 | 0.20 | +0.01 | ±10% / ±0.02 ms | 7.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.89 | 0.92 | +0.03 | ±10% / ±0.09 ms | 2.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.89 | 0.92 | +0.03 | ±10% / ±0.09 ms | 2.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 6.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.19 | 0.19 | +0.00 | ±10% / ±0.02 ms | 4.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.19 | 0.19 | +0.00 | ±10% / ±0.02 ms | 4.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.26 | 2.28 | +0.02 | ±10% / ±0.23 ms | 9.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 9.77 | 10.12 | +0.35 | ±10% / ±1.01 ms | 2.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 9.77 | 10.12 | +0.35 | ±10% / ±1.01 ms | 2.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.45 | 0.45 | +0.00 | ±10% / ±0.04 ms | 2.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.83 | 2.01 | +0.18 | ±10% / ±0.20 ms | 3.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.83 | 2.01 | +0.18 | ±10% / ±0.20 ms | 3.7% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.10 | 0.10 | +0.00 | ±36% / ±0.04 ms | 35.6% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.04 | 0.04 | +0.00 | ±11% / ±0.02 ms | 11.1% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.31 | 0.30 | -0.01 | ±10% / ±0.03 ms | 4.3% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 5.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.30 | 0.29 | -0.00 | ±10% / ±0.03 ms | 5.4% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 5.2% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.52 | 0.58 | +0.06 | ±10% / ±0.06 ms | 0.9% | stable | 🔴 Regression (+12%) |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.10 | 0.11 | +0.01 | ±10% / ±0.02 ms | 1.9% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.89 | 0.91 | +0.01 | ±34% / ±0.31 ms | 34.4% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.27 | 0.27 | +0.00 | ±12% / ±0.03 ms | 12.2% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±319% / ±0.10 ms | 318.8% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02 | +0.00 | ±525% / ±0.08 ms | 525.0% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.02 | +0.01 | ±79% / ±0.02 ms | 68.4% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.19 | 0.21 | +0.01 | ±15% / ±0.03 ms | 14.9% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.15 | 0.16 | +0.01 | ±11% / ±0.02 ms | 11.2% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.05 | -0.00 | ±30% / ±0.02 ms | 30.4% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.80 | 1.92 | +0.12 | ±11% / ±0.21 ms | 10.8% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.49 | 1.55 | +0.06 | ±10% / ±0.16 ms | 7.3% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.37 | 0.37 | +0.00 | ±10% / ±0.04 ms | 4.6% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.82 | 21.95 | +1.13 | ±10% / ±2.19 ms | 4.1% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 15.01 | 15.80 | +0.79 | ±10% / ±1.58 ms | 2.4% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.77 | 4.25 | +0.48 | ±20% / ±0.86 ms | 20.2% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.01 | +0.00 | ±40% / ±0.02 ms | 40.0% | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | +0.00 | ±571% / ±0.08 ms | 571.4% | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±1150% / ±0.02 ms | 1150.0% | noisy | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.04 | 0.05 | +0.00 | ±38% / ±0.02 ms | 37.5% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±11% / ±0.02 ms | 11.1% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.37 | 0.38 | +0.01 | ±15% / ±0.06 ms | 15.5% | moderate | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.08 | -0.00 | ±17% / ±0.02 ms | 16.7% | moderate | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 4.43 | 4.61 | +0.18 | ±10% / ±0.46 ms | 6.4% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.86 | 0.87 | +0.02 | ±23% / ±0.20 ms | 22.8% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.24 | 0.24 | -0.01 | ±29% / ±0.07 ms | 29.3% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.24 | 0.24 | -0.01 | ±29% / ±0.07 ms | 29.3% | stable | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.57 | 0.55 | -0.02 | ±13% / ±0.07 ms | 12.8% | moderate | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.57 | 0.55 | -0.02 | ±13% / ±0.07 ms | 12.8% | moderate | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.04 | +0.00 | ±26% / ±0.02 ms | 22.9% | noisy | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.04 | +0.00 | ±26% / ±0.02 ms | 22.9% | noisy | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.06 | +0.01 | ±34% / ±0.02 ms | 33.9% | noisy | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.06 | +0.01 | ±34% / ±0.02 ms | 33.9% | noisy | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.36 | 3.83 | +0.47 | ±10% / ±0.38 ms | 3.7% | stable | 🔴 Regression (+14%) |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.36 | 3.83 | +0.47 | ±10% / ±0.38 ms | 3.7% | stable | 🔴 Regression (+14%) |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.06 | 1.89 | -0.17 | ±82% / ±1.68 ms | 81.9% | moderate | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.06 | 1.89 | -0.17 | ±82% / ±1.68 ms | 81.9% | moderate | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 7.22 | 7.52 | +0.30 | ±12% / ±0.88 ms | 8.7% | moderate | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 7.22 | 7.52 | +0.30 | ±12% / ±0.88 ms | 8.7% | moderate | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.18 | 0.23 | +0.05 | ±42% / ±0.10 ms | 42.3% | noisy | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.18 | 0.23 | +0.05 | ±42% / ±0.10 ms | 42.3% | noisy | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.07 | 0.06 | -0.01 | ±16% / ±0.02 ms | 15.5% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.07 | 0.06 | -0.01 | ±16% / ±0.02 ms | 15.5% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.47 | 0.45 | -0.02 | ±48% / ±0.23 ms | 48.3% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.47 | 0.45 | -0.02 | ±48% / ±0.23 ms | 48.3% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.14 | 4.87 | +0.73 | ±10% / ±0.49 ms | 8.4% | stable | 🔴 Regression (+18%) |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.14 | 4.87 | +0.73 | ±10% / ±0.49 ms | 8.4% | stable | 🔴 Regression (+18%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.56 | 0.75 | +0.18 | ±27% / ±0.20 ms | 19.6% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.56 | 0.75 | +0.18 | ±27% / ±0.20 ms | 19.6% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.08 | +0.01 | ±10% / ±0.02 ms | 5.1% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.08 | +0.01 | ±10% / ±0.02 ms | 5.1% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 6.59 | 6.96 | +0.38 | ±26% / ±1.79 ms | 22.2% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 6.59 | 6.96 | +0.38 | ±26% / ±1.79 ms | 22.2% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.43 | 0.49 | +0.06 | ±10% / ±0.05 ms | 9.1% | stable | 🔴 Regression (+14%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.43 | 0.49 | +0.06 | ±10% / ±0.05 ms | 9.1% | stable | 🔴 Regression (+14%) |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.06 | +0.01 | ±15% / ±0.02 ms | 15.3% | moderate | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.06 | +0.01 | ±15% / ±0.02 ms | 15.3% | moderate | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.53 | 2.00 | +0.47 | ±18% / ±0.36 ms | 12.8% | moderate | 🔴 Regression (+31%) |
| Write Performance / Single Inserts (100 sequential) / res... | 1.53 | 2.00 | +0.47 | ±18% / ±0.36 ms | 12.8% | moderate | 🔴 Regression (+31%) |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.19 | -0.00 | ±17% / ±0.03 ms | 17.1% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.19 | -0.00 | ±17% / ±0.03 ms | 17.1% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.11 | +0.01 | ±17% / ±0.02 ms | 17.1% | moderate | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.11 | +0.01 | ±17% / ±0.02 ms | 17.1% | moderate | ⚪ Within noise |

**Summary:** 0 wins, 14 regressions, 139 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.02 | 0.00 | -0.02 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 0.00 | 0.00 | +0.00 MB | ±12.92 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 0.00 | 0.30 | +0.30 MB | ±3.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 2.00 | 0.00 | -2.00 MB | ±10.24 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 0.00 | +0.00 MB | ±4.01 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 1.34 | 0.00 | -1.34 MB | ±4.68 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 11.36 | 3.02 | -8.34 MB | ±11.02 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / resqlite select() | 5.45 | 1.27 | -4.18 MB | ±4.85 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite3 select() | 2.66 | 2.13 | -0.53 MB | ±3.59 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 1.00 | 1.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.06 | 0.06 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 0 wins, 0 regressions, 15 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 3969 | 3251 | -718 | ±100 | 🟢 Fewer re-emits (-718) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 3879 | 3500 | -379 | ±100 | 🔴 Invalidation elided (-379) — writes not firing |

**Granularity summary:** 1 fewer-re-emit, 1 more-re-emit, 4 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.
