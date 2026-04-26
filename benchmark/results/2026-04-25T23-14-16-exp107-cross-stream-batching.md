# resqlite Benchmark Results

Generated: 2026-04-25T23:14:15.741952

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp107-cross-stream-batching`
- Repeats: `5`
- Runtime: `dart-vm / Dart 3.11.0`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `exp-107-cross-stream-batching @ 3875709c5289 (dirty)`
- Comparison baseline: `2026-04-25T19-43-21-baseline-for-exp105.md` (cap=4 baseline) and `2026-04-25T22-10-11-exp106-column-level-deps.md` (post-exp-106 anchor)

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.013 | 0.014 | 0.001 | 0.001 |
| sqlite3 select() | 0.016 | 0.018 | 0.016 | 0.018 |
| sqlite_async select() | 0.033 | 0.036 | 0.001 | 0.001 |
| drift select() | 0.038 | 0.040 | 0.001 | 0.001 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.048 | 0.049 | 0.009 | 0.009 |
| sqlite3 select() | 0.118 | 0.137 | 0.118 | 0.137 |
| sqlite_async select() | 0.120 | 0.124 | 0.010 | 0.010 |
| drift select() | 0.175 | 0.180 | 0.010 | 0.010 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.399 | 0.613 | 0.092 | 0.115 |
| sqlite3 select() | 1.136 | 1.179 | 1.136 | 1.179 |
| sqlite_async select() | 1.008 | 1.078 | 0.092 | 0.098 |
| drift select() | 1.554 | 1.907 | 0.091 | 0.094 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.486 | 9.450 | 0.875 | 1.360 |
| sqlite3 select() | 13.807 | 16.754 | 13.807 | 16.754 |
| sqlite_async select() | 13.790 | 25.712 | 0.983 | 2.480 |
| drift select() | 22.172 | 24.649 | 0.931 | 2.539 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.027 | 0.030 | 0.015 | 0.017 |
| sqlite3 + jsonEncode | 0.029 | 0.031 | 0.029 | 0.031 |
| sqlite_async + jsonEncode | 0.045 | 0.048 | 0.016 | 0.016 |
| drift + jsonEncode | 0.052 | 0.057 | 0.016 | 0.017 |
| resqlite selectBytes() | 0.010 | 0.011 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.194 | 0.215 | 0.156 | 0.168 |
| sqlite3 + jsonEncode | 0.275 | 0.531 | 0.275 | 0.531 |
| sqlite_async + jsonEncode | 0.263 | 0.266 | 0.151 | 0.154 |
| drift + jsonEncode | 0.318 | 0.326 | 0.153 | 0.154 |
| resqlite selectBytes() | 0.043 | 0.044 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.734 | 3.355 | 1.444 | 2.205 |
| sqlite3 + jsonEncode | 2.421 | 3.286 | 2.421 | 3.286 |
| sqlite_async + jsonEncode | 2.330 | 3.837 | 1.441 | 1.961 |
| drift + jsonEncode | 2.922 | 4.053 | 1.439 | 1.742 |
| resqlite selectBytes() | 0.351 | 0.361 | 0.000 | 0.000 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 21.207 | 40.290 | 15.666 | 19.834 |
| sqlite3 + jsonEncode | 28.204 | 33.365 | 28.204 | 33.365 |
| sqlite_async + jsonEncode | 29.555 | 49.137 | 15.870 | 18.302 |
| drift + jsonEncode | 37.337 | 43.847 | 14.803 | 18.138 |
| resqlite selectBytes() | 3.721 | 6.515 | 0.002 | 0.008 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.103 | 0.107 | 0.036 | 0.038 |
| sqlite3 | 0.335 | 0.355 | 0.335 | 0.355 |
| sqlite_async | 0.373 | 0.398 | 0.043 | 0.045 |
| drift | 0.622 | 1.878 | 0.044 | 0.141 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.992 | 2.191 | 0.309 | 0.320 |
| sqlite3 | 3.442 | 4.735 | 3.442 | 4.735 |
| sqlite_async | 3.110 | 4.195 | 0.360 | 0.397 |
| drift | 5.026 | 7.072 | 0.348 | 0.389 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.532 | 0.576 | 0.108 | 0.112 |
| sqlite3 | 1.432 | 1.465 | 1.432 | 1.465 |
| sqlite_async | 1.336 | 1.411 | 0.117 | 0.122 |
| drift | 1.936 | 2.270 | 0.116 | 0.118 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.297 | 0.302 | 0.103 | 0.105 |
| sqlite3 | 0.972 | 1.032 | 0.972 | 1.032 |
| sqlite_async | 0.903 | 0.927 | 0.114 | 0.118 |
| drift | 1.453 | 1.539 | 0.113 | 0.118 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.298 | 0.306 | 0.100 | 0.102 |
| sqlite3 | 0.934 | 0.968 | 0.934 | 0.968 |
| sqlite_async | 0.903 | 0.915 | 0.115 | 0.116 |
| drift | 1.411 | 1.464 | 0.111 | 0.115 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.012 | 0.013 | 0.001 | 0.001 |
| sqlite3 | 0.015 | 0.016 | 0.015 | 0.016 |
| sqlite_async | 0.031 | 0.033 | 0.001 | 0.001 |
| drift | 0.037 | 0.042 | 0.001 | 0.001 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.027 | 0.029 | 0.004 | 0.004 |
| sqlite3 | 0.058 | 0.059 | 0.058 | 0.059 |
| sqlite_async | 0.070 | 0.072 | 0.005 | 0.005 |
| drift | 0.109 | 0.143 | 0.005 | 0.006 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.046 | 0.048 | 0.009 | 0.009 |
| sqlite3 | 0.112 | 0.118 | 0.112 | 0.118 |
| sqlite_async | 0.121 | 0.133 | 0.009 | 0.010 |
| drift | 0.181 | 0.187 | 0.010 | 0.010 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.194 | 0.200 | 0.044 | 0.046 |
| sqlite3 | 0.544 | 0.553 | 0.544 | 0.553 |
| sqlite_async | 0.500 | 0.512 | 0.045 | 0.046 |
| drift | 0.771 | 0.835 | 0.044 | 0.046 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.377 | 0.388 | 0.087 | 0.090 |
| sqlite3 | 1.064 | 1.091 | 1.064 | 1.091 |
| sqlite_async | 1.016 | 1.082 | 0.092 | 0.097 |
| drift | 1.532 | 1.595 | 0.088 | 0.092 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.786 | 1.217 | 0.179 | 0.202 |
| sqlite3 | 2.149 | 2.593 | 2.149 | 2.593 |
| sqlite_async | 1.969 | 2.313 | 0.179 | 0.181 |
| drift | 3.110 | 3.689 | 0.178 | 0.187 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.161 | 6.096 | 0.443 | 0.476 |
| sqlite3 | 5.516 | 6.909 | 5.516 | 6.909 |
| sqlite_async | 5.566 | 7.712 | 0.478 | 1.139 |
| drift | 8.988 | 10.487 | 0.480 | 0.500 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.359 | 12.290 | 0.884 | 1.225 |
| sqlite3 | 13.740 | 16.251 | 13.740 | 16.251 |
| sqlite_async | 10.610 | 11.558 | 0.884 | 0.916 |
| drift | 21.159 | 35.293 | 0.964 | 2.454 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 11.149 | 17.251 | 1.746 | 2.547 |
| sqlite3 | 32.392 | 36.096 | 32.392 | 36.096 |
| sqlite_async | 36.868 | 61.485 | 1.844 | 2.079 |
| drift | 52.290 | 88.393 | 1.859 | 6.517 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.030 | 0.036 | 0.030 | 0.036 |
| sqlite3 + jsonEncode | 0.029 | 0.030 | 0.029 | 0.030 |
| sqlite_async + jsonEncode | 0.045 | 0.047 | 0.045 | 0.047 |
| drift + jsonEncode | 0.052 | 0.055 | 0.052 | 0.055 |
| resqlite selectBytes() | 0.011 | 0.012 | 0.011 | 0.012 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.102 | 0.111 | 0.102 | 0.111 |
| sqlite3 + jsonEncode | 0.128 | 0.135 | 0.128 | 0.135 |
| sqlite_async + jsonEncode | 0.143 | 0.147 | 0.143 | 0.147 |
| drift + jsonEncode | 0.171 | 0.183 | 0.171 | 0.183 |
| resqlite selectBytes() | 0.026 | 0.029 | 0.026 | 0.029 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.190 | 0.200 | 0.190 | 0.200 |
| sqlite3 + jsonEncode | 0.256 | 0.267 | 0.256 | 0.267 |
| sqlite_async + jsonEncode | 0.263 | 0.275 | 0.263 | 0.275 |
| drift + jsonEncode | 0.318 | 0.323 | 0.318 | 0.323 |
| resqlite selectBytes() | 0.042 | 0.045 | 0.042 | 0.045 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.891 | 0.943 | 0.891 | 0.943 |
| sqlite3 + jsonEncode | 1.233 | 1.248 | 1.233 | 1.248 |
| sqlite_async + jsonEncode | 1.198 | 1.244 | 1.198 | 1.244 |
| drift + jsonEncode | 1.458 | 1.533 | 1.458 | 1.533 |
| resqlite selectBytes() | 0.179 | 0.185 | 0.179 | 0.185 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.763 | 1.916 | 1.763 | 1.916 |
| sqlite3 + jsonEncode | 2.604 | 4.103 | 2.604 | 4.103 |
| sqlite_async + jsonEncode | 2.463 | 3.899 | 2.463 | 3.899 |
| drift + jsonEncode | 2.910 | 3.338 | 2.910 | 3.338 |
| resqlite selectBytes() | 0.349 | 0.356 | 0.349 | 0.356 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.901 | 7.834 | 3.901 | 7.834 |
| sqlite3 + jsonEncode | 5.267 | 9.212 | 5.267 | 9.212 |
| sqlite_async + jsonEncode | 5.167 | 10.021 | 5.167 | 10.021 |
| drift + jsonEncode | 7.196 | 14.983 | 7.196 | 14.983 |
| resqlite selectBytes() | 0.885 | 1.698 | 0.885 | 1.698 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 9.630 | 12.686 | 9.630 | 12.686 |
| sqlite3 + jsonEncode | 14.316 | 18.828 | 14.316 | 18.828 |
| sqlite_async + jsonEncode | 14.621 | 20.637 | 14.621 | 20.637 |
| drift + jsonEncode | 17.269 | 33.025 | 17.269 | 33.025 |
| resqlite selectBytes() | 1.911 | 3.361 | 1.911 | 3.361 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 22.734 | 25.136 | 22.734 | 25.136 |
| sqlite3 + jsonEncode | 30.494 | 52.514 | 30.494 | 52.514 |
| sqlite_async + jsonEncode | 31.171 | 33.069 | 31.171 | 33.069 |
| drift + jsonEncode | 38.772 | 48.288 | 38.772 | 48.288 |
| resqlite selectBytes() | 3.519 | 3.551 | 3.519 | 3.551 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 44.578 | 55.755 | 44.578 | 55.755 |
| sqlite3 + jsonEncode | 63.098 | 84.876 | 63.098 | 84.876 |
| sqlite_async + jsonEncode | 64.285 | 79.603 | 64.285 | 79.603 |
| drift + jsonEncode | 85.691 | 105.899 | 85.691 | 105.899 |
| resqlite selectBytes() | 9.047 | 10.791 | 9.047 | 10.791 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.32 | 0.30 |
| sqlite_async | 0.90 | 0.99 | 0.90 |
| drift | 1.46 | 1.82 | 1.46 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.32 | 0.15 |
| sqlite_async | 1.29 | 1.59 | 0.64 |
| drift | 2.65 | 3.12 | 1.33 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.36 | 0.45 | 0.09 |
| sqlite_async | 2.13 | 2.67 | 0.53 |
| drift | 5.17 | 5.63 | 1.29 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.83 | 1.31 | 0.10 |
| sqlite_async | 4.90 | 10.09 | 0.61 |
| drift | 10.32 | 10.80 | 1.29 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 147201 |
| resqlite per query | 0.007 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 147201 | 144536..147480 | 1.0 | 2.5 |
| sqlite3 | 184954 | 182346..194770 | 3.4 | 9.9 |
| sqlite_async | 48495 | 41083..51544 | 10.8 | 20.7 |
| drift | 47348 | 44685..47643 | 3.1 | 2.4 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.676 | 15.432 | 14.676 | 15.432 |
| sqlite_async | 35.000 | 38.074 | 35.000 | 38.074 |
| drift | 52.726 | 62.688 | 52.726 | 62.688 |
| sqlite3 (no cache) | 24.112 | 24.430 | 24.112 | 24.430 |
| sqlite3 (cached stmt) | 25.080 | 26.360 | 25.080 | 26.360 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.654 | 2.224 | 1.654 | 2.224 |
| sqlite3 execute() | 1.000 | 1.541 | 1.000 | 1.541 |
| sqlite_async execute() | 2.896 | 3.435 | 2.896 | 3.435 |
| drift execute() | 3.014 | 7.152 | 3.014 | 7.152 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.058 | 0.060 | 0.058 | 0.060 |
| sqlite3 executeBatch() | 0.050 | 0.051 | 0.050 | 0.051 |
| sqlite_async executeBatch() | 0.095 | 0.099 | 0.095 | 0.099 |
| drift executeBatch() | 0.111 | 0.114 | 0.111 | 0.114 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.459 | 0.497 | 0.459 | 0.497 |
| sqlite3 executeBatch() | 0.451 | 0.468 | 0.451 | 0.468 |
| sqlite_async executeBatch() | 0.527 | 0.561 | 0.527 | 0.561 |
| drift executeBatch() | 0.668 | 0.700 | 0.668 | 0.700 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.385 | 7.043 | 4.385 | 7.043 |
| sqlite3 executeBatch() | 4.456 | 5.199 | 4.456 | 5.199 |
| sqlite_async executeBatch() | 4.799 | 5.414 | 4.799 | 5.414 |
| drift executeBatch() | 6.014 | 6.729 | 6.014 | 6.729 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.054 | 0.075 | 0.054 | 0.075 |
| sqlite_async writeTransaction() | 0.080 | 0.100 | 0.080 | 0.100 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.074 | 0.077 | 0.074 | 0.077 |
| resqlite tx.execute() loop | 0.583 | 0.766 | 0.583 | 0.766 |
| sqlite_async tx.execute() loop | 1.050 | 1.432 | 1.050 | 1.432 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.487 | 0.583 | 0.487 | 0.583 |
| resqlite tx.execute() loop | 6.593 | 7.522 | 6.593 | 7.522 |
| sqlite_async tx.execute() loop | 12.540 | 16.883 | 12.540 | 16.883 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.103 | 0.107 | 0.103 | 0.107 |
| sqlite_async tx.getAll() | 0.201 | 0.213 | 0.201 | 0.213 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.181 | 0.188 | 0.181 | 0.188 |
| sqlite_async tx.getAll() | 0.345 | 0.353 | 0.345 | 0.353 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.027 | 0.029 | 0.027 | 0.029 |
| sqlite_async watch() | 0.102 | 0.116 | 0.102 | 0.116 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.043 | 0.059 | 0.043 | 0.059 |
| sqlite_async | 0.063 | 0.071 | 0.063 | 0.071 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.200 | 0.262 | 0.200 | 0.262 |
| sqlite_async | 0.514 | 2.307 | 0.514 | 2.307 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.227 | 0.287 | 0.227 | 0.287 |
| sqlite_async | 0.245 | 0.305 | 0.245 | 0.305 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.785 | 1.785 | 1.785 | 1.785 |
| sqlite_async | 9.593 | 9.593 | 9.593 | 9.593 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.449 | 4.327 | 3.449 | 4.327 |
| sqlite_async | 5.470 | 12.214 | 5.470 | 12.214 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.545 | 0.689 | 0.545 | 0.689 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 6.195 | 6.493 | 6.195 | 6.493 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. On resqlite's main branch this ratio is driven toward 0 by experiment 075 (C-side result-hash short-circuit), not by writer-side column-tracking (exp 052 is not implemented). The two mechanisms are indistinguishable on this read-side benchmark.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 67.8 | 0.000 |
| sqlite_async | 3927 | 1002.1 | 1.059 |
| drift | 5000 | 1026.6 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 72.4 | 0.000 |
| sqlite_async | 3708 | 1022.1 | 1.059 |
| drift | 5000 | 1062.0 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 215.42 | 219.43 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 443.47 | 444.06 | 0.00 | 0.00 | 1105 | 3 |
| drift stream() | 550.13 | 575.10 | 0.01 | 0.01 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.031 | 0.059 | 0.000 | 0.000 |
| sqlite3 | 0.022 | 0.039 | 0.022 | 0.039 |
| sqlite_async | 0.036 | 0.044 | 0.000 | 0.000 |
| drift | 0.037 | 0.052 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.024 | 0.049 | 0.000 | 0.000 |
| sqlite3 | 0.014 | 0.022 | 0.014 | 0.022 |
| sqlite_async | 0.029 | 0.034 | 0.000 | 0.000 |
| drift | 0.029 | 0.038 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.030 | 0.045 | 0.000 | 0.000 |
| sqlite3 | 0.031 | 0.035 | 0.031 | 0.035 |
| sqlite_async | 0.054 | 0.063 | 0.000 | 0.000 |
| drift | 0.053 | 0.058 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.011 | 0.024 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.020 | 0.024 | 0.000 | 0.000 |
| drift | 0.019 | 0.023 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.039 | 0.040 | 0.001 | 0.001 |
| sqlite3 | 0.067 | 0.069 | 0.067 | 0.069 |
| sqlite_async | 0.084 | 0.088 | 0.001 | 0.001 |
| drift | 0.098 | 0.128 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 112.145 | 116.141 | 0.000 | 0.000 | 0 |
| sqlite_async | 219.308 | 220.527 | 0.000 | 0.000 | 43 |
| drift | 230.509 | 231.686 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 229.09 | 229.09 | 0.00 | 0.00 | 13.71 | 215.38 | 0 |
| sqlite_async | 482.08 | 482.08 | 0.00 | 0.00 | 23.88 | 458.20 | 1183 |
| drift | 1811.33 | 1811.33 | 0.66 | 0.66 | 14.13 | 1798.56 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 6.31 | 23.56 | 1.34..7.09 | ±2.88 |
| sqlite3 select() | 5.03 | 9.22 | 0.00..7.70 | ±3.85 |
| sqlite_async select() | 1.00 | 1.00 | 1.00..1.00 | ±0.00 |
| drift select() | 0.98 | 40.75 | 0.00..11.33 | ±5.66 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 8.00 | 0.00..6.00 | ±3.00 |
| resqlite + jsonEncode | 1.03 | 80.45 | 0.00..40.11 | ±20.05 |
| sqlite3 + jsonEncode | 0.00 | 58.81 | 0.00..7.08 | ±3.54 |
| sqlite_async + jsonEncode | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| drift + jsonEncode | 0.00 | 32.56 | 0.00..1.84 | ±0.92 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 3.50 | 6.30 | 0.00..3.83 | ±1.91 |
| sqlite3 executeBatch() | 0.00 | 0.50 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 0.50 | 0.00..0.00 | ±0.00 |
| drift batch() | 0.05 | 4.50 | 0.02..2.52 | ±1.25 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.05 | 0.13 | 0.00..0.06 | ±0.03 |
| sqlite_async watch() | 0.00 | 0.11 | 0.00..0.02 | ±0.01 |

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

## Sync Burst (v1)

50K bulk insert via executeBatch in 500-row chunks, then 10 × 100-row INSERT OR REPLACE merges. A COUNT(*) stream stays active throughout on reactive peers. Models offline-first sync: a client pulling from a server, applying batched changes, while the local UI shows live counts. Opt-in via --include-slow.

### Bulk insert: 50000 rows × 500-row chunks

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 69.85 | 69.85 | 0.00 | 0.00 |
| sqlite3 | 49.07 | 49.07 | 49.07 | 49.07 |
| sqlite_async | 68.15 | 68.15 | 0.00 | 0.00 |
| drift | 78.89 | 78.89 | 0.00 | 0.00 |

### Merge rounds: 10 × 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.12 | 3.12 | 0.00 | 0.00 |
| sqlite3 | 1.06 | 1.06 | 1.06 | 1.06 |
| sqlite_async | 2.25 | 2.25 | 0.00 | 0.00 |
| drift | 2.77 | 2.77 | 0.00 | 0.00 |

### Stream emissions during burst (COUNT(*))

| Library | Emissions |
|---|---|
| resqlite | 102 |
| sqlite_async | 109 |
| drift | 1 |

Every batch commit invalidates the COUNT(*) stream. Fewer emissions under the same write load signals better coalescing; more emissions may indicate per-commit re-emit without the suppression logic resqlite's engine applies (exp 031/033/075 + PR #17's per-stream re-query coalescing).

## Large Working Set (v1)

Random-point and range-scan latency on a ~1 GB database. Measures behavior at scale, where mmap and page cache matter. Cold-cache and warm-cache variants reported separately. Seed is cached across runs. Opt-in via --include-slow.

### Warm cache (5 rounds)

Random-point (1000/round) and range-scan (10/round, LIMIT 500) against a 5000K-row table.

| Library | Point p50 (ms) | Point p90 (ms) | Range p50 (ms) | Range p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.114 | 0.190 | 0.738 | 1.125 |
| sqlite3 | 0.095 | 0.180 | 0.803 | 1.088 |
| sqlite_async | 0.115 | 0.190 | 0.852 | 1.264 |
| drift | 0.120 | 0.200 | 1.016 | 1.306 |

### Cold cache (3 rounds with shrink_memory)

Random-point (1000/round) and range-scan (10/round, LIMIT 500) against a 5000K-row table.

| Library | Point p50 (ms) | Point p90 (ms) | Range p50 (ms) | Range p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.111 | 0.197 | 0.661 | 0.841 |
| sqlite3 | 0.094 | 0.179 | 0.819 | 1.298 |
| sqlite_async | 0.124 | 0.217 | 0.870 | 1.171 |
| drift | 0.113 | 0.199 | 0.910 | 1.246 |

## Many-Streams Writer Throughput (v1)

Writer throughput (writes/sec) under stream fan-out. A wide 20-column table is watched by N streams, each projecting a subset of columns over a partition of the row space. The writer issues 500 single-row updates first against a column NOT in any stream's projection (disjoint) and then against a column IN every stream's projection (overlapping). The disjoint-vs-overlapping spread reveals whether a library elides per-stream dispatch on column-disjoint writes — the writer-side counterpart to disjoint_columns.dart's stream-side ratio. A no-streams baseline run is reported as a writer-only reference.

### 50 streams × 500 writes per scenario

### No-streams baseline (500 writes, no subscribers)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Writes/sec |
|---|---|---|---|---|---|
| resqlite | 8.00 | 11.07 | 0.00 | 0.00 | 62484 |
| sqlite_async | 14.80 | 15.37 | 0.00 | 0.00 | 33775 |
| drift | 13.11 | 18.89 | 0.00 | 0.00 | 38153 |

### Disjoint column writes (SET c = ?, projection = id, a, b)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Writes/sec | Emissions |
|---|---|---|---|---|---|---|
| resqlite | 68.46 | 71.22 | 0.00 | 0.00 | 7304 | 0 |
| sqlite_async | 246.39 | 285.41 | 0.01 | 0.01 | 2029 | 4290 |
| drift | 2209.50 | 2265.64 | 0.07 | 2.13 | 226 | 25000 |

### Overlapping column writes (SET a = ?, projection = id, a, b)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Writes/sec | Emissions |
|---|---|---|---|---|---|---|
| resqlite | 74.04 | 77.70 | 0.00 | 0.00 | 6753 | 0 |
| sqlite_async | 221.27 | 230.55 | 0.01 | 0.03 | 2260 | 4239 |
| drift | 2243.07 | 2276.30 | 0.77 | 1.11 | 223 | 25000 |

### Overlap-vs-disjoint writer-throughput ratio

| Library | Disjoint w/s | Overlap w/s | Overlap/disjoint |
|---|---|---|---|
| resqlite | 7304 | 6753 | 0.925 |
| sqlite_async | 2029 | 2260 | 1.114 |
| drift | 226 | 223 | 0.985 |

**Writes/sec** is `writeCount / wall_time_seconds`. Higher is better. **Baseline** is the same write loop with no streams subscribed — the writer's ceiling on this hardware.

**Emissions** are post-baseline emissions summed across all 50 streams during the timed write loop. A library with hash-based result suppression (resqlite exp 075) reports low emission counts on the disjoint scenario even when its writer throughput is unchanged — that signal lives in `disjoint_columns.dart`, not here. This suite is about the writer-side cost of the dispatch itself.

**Overlap/disjoint ratio**: writes/sec under overlap divided by writes/sec under disjoint. A ratio close to 1.0 means the library performs similar writer-side work in both scenarios; a ratio ≪ 1.0 means it is actually eliding per-stream dispatch on disjoint writes. resqlite today is expected near 1.0; this benchmark exists to make a future column-tracking optimization (exp 052) visible by driving that ratio down.

## Repeat Stability

These rows summarize resqlite wall medians across repeated full-suite runs.
Use this section to judge whether small deltas are real or just noise.

| Benchmark | Median (ms) | 95% CI (ms) | MDE_ci | Range | MAD | Stability |
|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.03 | 0.02..0.03 | 14.0% | 28.0% | 4.0% | moderate |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 16.7% | 33.3% | 11.1% | noisy |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02..0.03 | 27.3% | 54.5% | 13.6% | noisy |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.01..0.02 | 26.5% | 52.9% | 11.8% | noisy |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.30 | 0.29..0.30 | 1.7% | 3.3% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.30 | 0.29..0.30 | 1.7% | 3.3% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.31 | 0.30..0.35 | 8.1% | 16.1% | 3.2% | moderate |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.15 | 0.15..0.17 | 6.7% | 13.3% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.37 | 0.36..1.35 | 133.8% | 267.6% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.09 | 0.09..0.34 | 138.9% | 277.8% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.73 | 0.68..1.55 | 59.6% | 119.2% | 6.8% | moderate |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.09 | 0.08..0.19 | 61.1% | 122.2% | 11.1% | noisy |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.04 | 7.7% | 15.4% | 2.6% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 150.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 108.96 | 108.20..112.14 | 1.8% | 3.6% | 0.7% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 226.49 | 224.62..229.09 | 1.0% | 2.0% | 0.8% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 214.16 | 213.08..216.59 | 0.8% | 1.6% | 0.5% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Large Working Set (v1) / Cold cache (3 rounds with shrink_memory) /... | 0.11 | 0.10..0.15 | 23.0% | 45.9% | 8.1% | noisy |
| Large Working Set (v1) / Cold cache (3 rounds with shrink_memory) /... | 0.66 | 0.15..0.92 | 58.2% | 116.5% | 38.7% | noisy |
| Large Working Set (v1) / Warm cache (5 rounds) / resqlite | 0.11 | 0.10..0.12 | 6.6% | 13.2% | 0.9% | stable |
| Large Working Set (v1) / Warm cache (5 rounds) / resqlite [main] | 0.74 | 0.71..0.80 | 5.8% | 11.7% | 3.5% | moderate |
| Many-Streams Writer Throughput (v1) / Disjoint column writes (SET c... | 68.66 | 66.63..70.63 | 2.9% | 5.8% | 0.4% | stable |
| Many-Streams Writer Throughput (v1) / Disjoint column writes (SET c... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Many-Streams Writer Throughput (v1) / No-streams baseline (500 writ... | 8.68 | 8.00..11.98 | 22.9% | 45.9% | 6.6% | moderate |
| Many-Streams Writer Throughput (v1) / No-streams baseline (500 writ... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Many-Streams Writer Throughput (v1) / Overlap-vs-disjoint writer-th... | 7282.00 | 7079.00..7504.00 | 2.9% | 5.8% | 0.4% | stable |
| Many-Streams Writer Throughput (v1) / Overlap-vs-disjoint writer-th... | 0.95 | 0.89..0.98 | 4.3% | 8.6% | 2.2% | stable |
| Many-Streams Writer Throughput (v1) / Overlapping column writes (SE... | 72.34 | 71.65..74.56 | 2.0% | 4.0% | 1.0% | stable |
| Many-Streams Writer Throughput (v1) / Overlapping column writes (SE... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 14.68 | 14.26..15.10 | 2.9% | 5.7% | 1.7% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 14.68 | 14.26..15.10 | 2.9% | 5.7% | 1.7% | stable |
| Point Query Throughput / resqlite qps | 146675.00 | 135010.00..149487.00 | 4.9% | 9.9% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.02 | 37.5% | 75.0% | 8.3% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.04 | 16.7% | 33.3% | 3.7% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.04 | 16.7% | 33.3% | 3.7% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 50.0% | 100.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 27.3% | 54.5% | 9.1% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.02 | 27.3% | 54.5% | 9.1% | noisy |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05..0.05 | 4.3% | 8.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.19 | 0.19..0.21 | 5.5% | 11.0% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.19 | 0.19..0.21 | 5.5% | 11.0% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.05 | 6.8% | 13.6% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.04 | 0.04..0.05 | 6.8% | 13.6% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.39 | 0.38..0.39 | 2.2% | 4.4% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.76 | 1.73..1.88 | 4.3% | 8.6% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.76 | 1.73..1.88 | 4.3% | 8.6% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09..0.09 | 3.9% | 7.9% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.36 | 0.35..0.39 | 5.0% | 9.9% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.36 | 0.35..0.39 | 5.0% | 9.9% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.42 | 4.36..5.56 | 13.6% | 27.1% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 22.64 | 20.29..22.96 | 5.9% | 11.8% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 22.64 | 20.29..22.96 | 5.9% | 11.8% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.88 | 0.86..0.89 | 1.6% | 3.2% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 3.70 | 3.52..3.71 | 2.6% | 5.1% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 3.70 | 3.52..3.71 | 2.6% | 5.1% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.79 | 0.78..0.80 | 1.3% | 2.7% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.90 | 3.67..4.46 | 10.1% | 20.2% | 4.5% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.90 | 3.67..4.46 | 10.1% | 20.2% | 4.5% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.18 | 0.17..0.18 | 2.0% | 4.0% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.78 | 0.75..0.95 | 13.1% | 26.1% | 3.8% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.78 | 0.75..0.95 | 13.1% | 26.1% | 3.8% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 11.04 | 10.69..13.15 | 11.1% | 22.3% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 44.35 | 42.48..45.02 | 2.9% | 5.7% | 1.3% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 44.35 | 42.48..45.02 | 2.9% | 5.7% | 1.3% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.73 | 1.71..1.82 | 3.0% | 6.1% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 8.08 | 7.74..9.05 | 8.1% | 16.2% | 4.2% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 8.08 | 7.74..9.05 | 8.1% | 16.2% | 4.2% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03..0.03 | 11.1% | 22.2% | 3.7% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10..0.11 | 3.5% | 6.9% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.10 | 0.10..0.11 | 3.5% | 6.9% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.01 | 12.5% | 25.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.02..0.03 | 14.0% | 28.0% | 4.0% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.02..0.03 | 14.0% | 28.0% | 4.0% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.19 | 0.19..0.20 | 0.5% | 1.0% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.89 | 0.88..0.89 | 0.6% | 1.2% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.89 | 0.88..0.89 | 0.6% | 1.2% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04..0.04 | 1.1% | 2.3% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.18 | 0.18..0.18 | 2.2% | 4.4% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.18 | 0.18..0.18 | 2.2% | 4.4% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.21 | 2.11..2.83 | 16.4% | 32.8% | 4.8% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 9.65 | 9.58..11.12 | 8.0% | 15.9% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 9.65 | 9.58..11.12 | 8.0% | 15.9% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.44 | 0.42..0.47 | 5.4% | 10.8% | 4.3% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 1.91 | 1.78..2.10 | 8.3% | 16.6% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 1.91 | 1.78..2.10 | 8.3% | 16.6% | 0.5% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.10 | 0.10..0.16 | 32.0% | 64.1% | 3.9% | moderate |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.04 | 0.02..0.09 | 97.2% | 194.4% | 2.8% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.30 | 0.29..0.30 | 1.5% | 3.0% | 0.7% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.10 | 0.09..0.10 | 4.0% | 7.9% | 1.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.30 | 0.30..0.31 | 2.3% | 4.7% | 1.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.10 | 0.10..0.11 | 2.9% | 5.8% | 1.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.54 | 0.53..0.56 | 3.1% | 6.1% | 1.7% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.11 | 0.10..0.11 | 4.2% | 8.3% | 0.9% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.99 | 0.94..1.01 | 3.9% | 7.9% | 1.9% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.30 | 0.29..0.31 | 3.5% | 7.0% | 2.7% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.10 | 137.0% | 274.1% | 3.7% | moderate |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.01 | 0.01..0.07 | 196.7% | 393.3% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 59.1% | 118.2% | 9.1% | noisy |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.19..0.24 | 12.3% | 24.6% | 4.9% | moderate |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.16 | 0.15..0.18 | 10.1% | 20.1% | 3.8% | moderate |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.06 | 14.4% | 28.9% | 2.2% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.80 | 1.73..1.91 | 4.9% | 9.8% | 3.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.46 | 1.44..1.56 | 4.1% | 8.2% | 0.8% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.36 | 0.35..0.38 | 4.6% | 9.2% | 1.7% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 21.21 | 20.08..22.36 | 5.4% | 10.8% | 3.5% | moderate |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 15.33 | 14.65..15.67 | 3.3% | 6.6% | 2.2% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.72 | 3.63..3.89 | 3.4% | 6.8% | 2.3% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 75.0% | 150.0% | 50.0% | noisy |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.09 | 280.8% | 561.5% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 1050.0% | 2100.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.05..0.07 | 25.0% | 50.0% | 2.1% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 5.6% | 11.1% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.38 | 0.37..0.43 | 7.4% | 14.9% | 2.6% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.07..0.09 | 10.3% | 20.7% | 1.1% | stable |
| Select → Maps / 10000 rows / resqlite select() | 4.45 | 4.30..4.70 | 4.5% | 9.0% | 1.7% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.87 | 0.67..0.92 | 14.4% | 28.9% | 1.0% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.23 | 0.20..0.76 | 121.3% | 242.6% | 1.3% | stable |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.23 | 0.20..0.76 | 121.3% | 242.6% | 1.3% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.55 | 0.52..0.61 | 8.1% | 16.1% | 3.9% | moderate |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.55 | 0.52..0.61 | 8.1% | 16.1% | 3.9% | moderate |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03..0.06 | 66.1% | 132.1% | 3.6% | moderate |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03..0.06 | 66.1% | 132.1% | 3.6% | moderate |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.04..0.06 | 13.5% | 27.1% | 10.4% | noisy |
| Streaming / Invalidation Latency / resqlite [main] | 0.05 | 0.04..0.06 | 13.5% | 27.1% | 10.4% | noisy |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.70 | 3.45..4.19 | 10.0% | 20.0% | 6.7% | moderate |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.70 | 3.45..4.19 | 10.0% | 20.0% | 6.7% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.81 | 1.66..4.41 | 76.1% | 152.1% | 5.4% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.81 | 1.66..4.41 | 76.1% | 152.1% | 5.4% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.55 | 6.20..7.50 | 9.9% | 19.9% | 4.3% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.55 | 6.20..7.50 | 9.9% | 19.9% | 4.3% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.20 | 0.19..0.32 | 30.7% | 61.4% | 4.5% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.20 | 0.19..0.32 | 30.7% | 61.4% | 4.5% | moderate |
| Sync Burst (v1) / Bulk insert: 50000 rows × 500-row chunks / resqlite | 65.60 | 45.73..69.85 | 18.4% | 36.8% | 6.5% | moderate |
| Sync Burst (v1) / Bulk insert: 50000 rows × 500-row chunks / resqli... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Sync Burst (v1) / Merge rounds: 10 × 100 rows / resqlite | 2.54 | 2.45..3.80 | 26.6% | 53.1% | 3.5% | moderate |
| Sync Burst (v1) / Merge rounds: 10 × 100 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Sync Burst (v1) / Stream emissions during burst (COUNT(*)) / resqlite | 104.00 | 102.00..104.00 | 1.0% | 1.9% | 0.0% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.06..0.07 | 8.3% | 16.7% | 3.3% | moderate |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.06 | 0.06..0.07 | 8.3% | 16.7% | 3.3% | moderate |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.46 | 0.45..0.49 | 4.2% | 8.5% | 1.1% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.46 | 0.45..0.49 | 4.2% | 8.5% | 1.1% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.50 | 4.38..4.83 | 4.9% | 9.8% | 1.7% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.50 | 4.38..4.83 | 4.9% | 9.8% | 1.7% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.57 | 0.48..0.59 | 9.1% | 18.2% | 3.0% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.57 | 0.48..0.59 | 9.1% | 18.2% | 3.0% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07..0.08 | 3.4% | 6.8% | 1.4% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07..0.08 | 3.4% | 6.8% | 1.4% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.48 | 5.17..6.71 | 14.1% | 28.3% | 5.7% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.48 | 5.17..6.71 | 14.1% | 28.3% | 5.7% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.47 | 0.46..0.49 | 3.2% | 6.5% | 1.7% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.47 | 0.46..0.49 | 3.2% | 6.5% | 1.7% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05..0.05 | 4.9% | 9.8% | 2.0% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05..0.05 | 4.9% | 9.8% | 2.0% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.92 | 1.65..2.38 | 18.9% | 37.9% | 12.6% | noisy |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.92 | 1.65..2.38 | 18.9% | 37.9% | 12.6% | noisy |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.18..0.19 | 2.7% | 5.5% | 1.1% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.18..0.19 | 2.7% | 5.5% | 1.1% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.10 | 0.10..0.11 | 2.9% | 5.7% | 0.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.10 | 0.10..0.11 | 2.9% | 5.7% | 0.0% | stable |


## Comparison vs Previous Run

Previous: `2026-04-25T22-55-48-exp107-cross-stream-batching.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.02 | 0.03 | +0.00 | ±14% / ±0.02 ms | 14.0% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | +0.00 | ±33% / ±0.02 ms | 16.7% | noisy | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02 | +0.00 | ±41% / ±0.02 ms | 27.3% | noisy | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.02 | +0.00 | ±35% / ±0.02 ms | 26.5% | noisy | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.29 | 0.30 | +0.01 | ±10% / ±0.03 ms | 1.7% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.29 | 0.30 | +0.01 | ±10% / ±0.03 ms | 1.7% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.66 | 0.31 | -0.35 | ±10% / ±0.07 ms | 8.1% | moderate | 🟢 Win (-53%) |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.33 | 0.15 | -0.18 | ±10% / ±0.03 ms | 6.7% | stable | 🟢 Win (-55%) |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.37 | 0.37 | +0.00 | ±134% / ±0.50 ms | 133.8% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.09 | 0.09 | +0.00 | ±139% / ±0.12 ms | 138.9% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 1.20 | 0.73 | -0.47 | ±60% / ±0.72 ms | 59.6% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.15 | 0.09 | -0.06 | ±61% / ±0.09 ms | 61.1% | noisy | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 7.7% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±150% / ±0.02 ms | 150.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 113.02 | 108.96 | -4.06 | ±10% / ±11.30 ms | 1.8% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 232.63 | 226.49 | -6.14 | ±10% / ±23.26 ms | 1.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 213.07 | 214.16 | +1.09 | ±10% / ±21.42 ms | 0.8% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Large Working Set (v1) / Cold cache (3 rounds with shrink... | 0.11 | 0.11 | +0.00 | ±24% / ±0.03 ms | 23.0% | noisy | ⚪ Within noise |
| Large Working Set (v1) / Cold cache (3 rounds with shrink... | 0.68 | 0.66 | -0.02 | ±116% / ±0.79 ms | 58.2% | noisy | ⚪ Within noise |
| Large Working Set (v1) / Warm cache (5 rounds) / resqlite | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | 6.6% | stable | ⚪ Within noise |
| Large Working Set (v1) / Warm cache (5 rounds) / resqlite... | 0.68 | 0.74 | +0.06 | ±11% / ±0.08 ms | 5.8% | moderate | ⚪ Within noise |
| Many-Streams Writer Throughput (v1) / Disjoint column wri... | 66.80 | 68.66 | +1.86 | ±10% / ±6.87 ms | 2.9% | stable | ⚪ Within noise |
| Many-Streams Writer Throughput (v1) / Disjoint column wri... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Many-Streams Writer Throughput (v1) / No-streams baseline... | 8.27 | 8.68 | +0.41 | ±23% / ±1.99 ms | 22.9% | moderate | ⚪ Within noise |
| Many-Streams Writer Throughput (v1) / No-streams baseline... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Many-Streams Writer Throughput (v1) / Overlap-vs-disjoint... | 7485.00 | 7282.00 | -203.00 | ±10% / ±748.50 ms | 2.9% | stable | ⚪ Within noise |
| Many-Streams Writer Throughput (v1) / Overlap-vs-disjoint... | 0.91 | 0.95 | +0.05 | ±10% / ±0.10 ms | 4.3% | stable | ⚪ Within noise |
| Many-Streams Writer Throughput (v1) / Overlapping column ... | 73.58 | 72.34 | -1.24 | ±10% / ±7.36 ms | 2.0% | stable | ⚪ Within noise |
| Many-Streams Writer Throughput (v1) / Overlapping column ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 15.02 | 14.68 | -0.34 | ±10% / ±1.50 ms | 2.9% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 15.02 | 14.68 | -0.34 | ±10% / ±1.50 ms | 2.9% | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 137191.00 | 146675.00 | +9484.00 | ±10% / ±14667.50 ms | 4.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01 | -0.00 | ±38% / ±0.02 ms | 37.5% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | -0.00 | ±17% / ±0.02 ms | 16.7% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.03 | -0.00 | ±17% / ±0.02 ms | 16.7% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±50% / ±0.02 ms | 50.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±27% / ±0.02 ms | 27.3% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±27% / ±0.02 ms | 27.3% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05 | -0.00 | ±10% / ±0.02 ms | 4.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.21 | 0.19 | -0.01 | ±10% / ±0.02 ms | 5.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.21 | 0.19 | -0.01 | ±10% / ±0.02 ms | 5.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 6.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 6.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.37 | 0.39 | +0.01 | ±10% / ±0.04 ms | 2.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.87 | 1.76 | -0.10 | ±10% / ±0.19 ms | 4.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.87 | 1.76 | -0.10 | ±10% / ±0.19 ms | 4.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 3.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.36 | +0.01 | ±10% / ±0.04 ms | 5.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.36 | +0.01 | ±10% / ±0.04 ms | 5.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.61 | 4.42 | -0.19 | ±14% / ±0.63 ms | 13.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 23.40 | 22.64 | -0.75 | ±10% / ±2.34 ms | 5.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 23.40 | 22.64 | -0.75 | ±10% / ±2.34 ms | 5.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.90 | 0.88 | -0.01 | ±10% / ±0.09 ms | 1.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 4.01 | 3.70 | -0.31 | ±10% / ±0.40 ms | 2.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 4.01 | 3.70 | -0.31 | ±10% / ±0.40 ms | 2.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.77 | 0.79 | +0.02 | ±10% / ±0.08 ms | 1.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.74 | 3.90 | +0.16 | ±14% / ±0.53 ms | 10.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.74 | 3.90 | +0.16 | ±14% / ±0.53 ms | 10.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.17 | 0.18 | +0.01 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.75 | 0.78 | +0.03 | ±13% / ±0.10 ms | 13.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.75 | 0.78 | +0.03 | ±13% / ±0.10 ms | 13.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 12.08 | 11.04 | -1.04 | ±11% / ±1.35 ms | 11.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 44.09 | 44.35 | +0.26 | ±10% / ±4.43 ms | 2.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 44.09 | 44.35 | +0.26 | ±10% / ±4.43 ms | 2.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.75 | 1.73 | -0.02 | ±10% / ±0.18 ms | 3.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.33 | 8.08 | -0.25 | ±13% / ±1.06 ms | 8.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.33 | 8.08 | -0.25 | ±13% / ±1.06 ms | 8.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03 | -0.00 | ±11% / ±0.02 ms | 11.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.10 | -0.01 | ±10% / ±0.02 ms | 3.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.11 | 0.10 | -0.01 | ±10% / ±0.02 ms | 3.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.01 | 0.00 | -0.00 | ±13% / ±0.02 ms | 12.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | -0.00 | ±14% / ±0.02 ms | 14.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | -0.00 | ±14% / ±0.02 ms | 14.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.19 | 0.19 | +0.00 | ±10% / ±0.02 ms | 0.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.94 | 0.89 | -0.05 | ±10% / ±0.09 ms | 0.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.94 | 0.89 | -0.05 | ±10% / ±0.09 ms | 0.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 1.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.19 | 0.18 | -0.01 | ±10% / ±0.02 ms | 2.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.19 | 0.18 | -0.01 | ±10% / ±0.02 ms | 2.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.13 | 2.21 | +0.08 | ±16% / ±0.36 ms | 16.4% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.61 | 9.65 | -0.96 | ±10% / ±1.06 ms | 8.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.61 | 9.65 | -0.96 | ±10% / ±1.06 ms | 8.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.43 | 0.44 | +0.02 | ±13% / ±0.06 ms | 5.4% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.76 | 1.91 | +0.15 | ±10% / ±0.19 ms | 8.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.76 | 1.91 | +0.15 | ±10% / ±0.19 ms | 8.3% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.10 | 0.10 | +0.00 | ±32% / ±0.03 ms | 32.0% | moderate | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.04 | 0.04 | +0.00 | ±97% / ±0.04 ms | 97.2% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.32 | 0.30 | -0.02 | ±10% / ±0.03 ms | 1.5% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 4.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.31 | 0.30 | -0.01 | ±10% / ±0.03 ms | 2.3% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 2.9% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.56 | 0.54 | -0.02 | ±10% / ±0.06 ms | 3.1% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | 4.2% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.95 | 0.99 | +0.04 | ±10% / ±0.10 ms | 3.9% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.29 | 0.30 | +0.01 | ±10% / ±0.03 ms | 3.5% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±137% / ±0.04 ms | 137.0% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.01 | 0.01 | +0.00 | ±197% / ±0.03 ms | 196.7% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | +0.00 | ±59% / ±0.02 ms | 59.1% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.20 | +0.01 | ±15% / ±0.03 ms | 12.3% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.16 | 0.16 | +0.00 | ±11% / ±0.02 ms | 10.1% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04 | +0.00 | ±14% / ±0.02 ms | 14.4% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.83 | 1.80 | -0.03 | ±10% / ±0.18 ms | 4.9% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.52 | 1.46 | -0.06 | ±10% / ±0.15 ms | 4.1% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.35 | 0.36 | +0.01 | ±10% / ±0.04 ms | 4.6% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 22.57 | 21.21 | -1.37 | ±10% / ±2.36 ms | 5.4% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 15.74 | 15.33 | -0.41 | ±10% / ±1.57 ms | 3.3% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.67 | 3.72 | +0.05 | ±10% / ±0.37 ms | 3.4% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±150% / ±0.02 ms | 75.0% | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | +0.00 | ±281% / ±0.04 ms | 280.8% | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±1050% / ±0.02 ms | 1050.0% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.05 | +0.00 | ±25% / ±0.02 ms | 25.0% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 5.6% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.39 | 0.38 | -0.01 | ±10% / ±0.04 ms | 7.4% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.09 | -0.00 | ±10% / ±0.02 ms | 10.3% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 4.42 | 4.45 | +0.03 | ±10% / ±0.44 ms | 4.5% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.85 | 0.87 | +0.02 | ±14% / ±0.12 ms | 14.4% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.26 | 0.23 | -0.03 | ±121% / ±0.31 ms | 121.3% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.26 | 0.23 | -0.03 | ±121% / ±0.31 ms | 121.3% | stable | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.59 | 0.55 | -0.05 | ±12% / ±0.07 ms | 8.1% | moderate | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.59 | 0.55 | -0.05 | ±12% / ±0.07 ms | 8.1% | moderate | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | -0.01 | ±66% / ±0.02 ms | 66.1% | moderate | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03 | -0.01 | ±66% / ±0.02 ms | 66.1% | moderate | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.06 | 0.05 | -0.02 | ±31% / ±0.02 ms | 13.5% | noisy | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.06 | 0.05 | -0.02 | ±31% / ±0.02 ms | 13.5% | noisy | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.74 | 3.70 | -0.04 | ±20% / ±0.75 ms | 10.0% | moderate | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.74 | 3.70 | -0.04 | ±20% / ±0.75 ms | 10.0% | moderate | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.84 | 1.81 | -0.03 | ±76% / ±1.40 ms | 76.1% | moderate | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.84 | 1.81 | -0.03 | ±76% / ±1.40 ms | 76.1% | moderate | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.43 | 6.55 | +0.13 | ±13% / ±0.85 ms | 9.9% | moderate | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.43 | 6.55 | +0.13 | ±13% / ±0.85 ms | 9.9% | moderate | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.92 | 0.20 | -0.71 | ±31% / ±0.28 ms | 30.7% | moderate | 🟢 Win (-78%) |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.92 | 0.20 | -0.71 | ±31% / ±0.28 ms | 30.7% | moderate | 🟢 Win (-78%) |
| Sync Burst (v1) / Bulk insert: 50000 rows × 500-row chunk... | 65.74 | 65.60 | -0.14 | ±19% / ±12.78 ms | 18.4% | moderate | ⚪ Within noise |
| Sync Burst (v1) / Bulk insert: 50000 rows × 500-row chunk... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Sync Burst (v1) / Merge rounds: 10 × 100 rows / resqlite | 2.36 | 2.54 | +0.18 | ±27% / ±0.67 ms | 26.6% | moderate | ⚪ Within noise |
| Sync Burst (v1) / Merge rounds: 10 × 100 rows / resqlite ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Sync Burst (v1) / Stream emissions during burst (COUNT(*)... | 104.00 | 104.00 | +0.00 | ±10% / ±10.40 ms | 1.0% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.07 | 0.06 | -0.01 | ±10% / ±0.02 ms | 8.3% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.07 | 0.06 | -0.01 | ±10% / ±0.02 ms | 8.3% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.50 | 0.46 | -0.04 | ±10% / ±0.05 ms | 4.2% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.50 | 0.46 | -0.04 | ±10% / ±0.05 ms | 4.2% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.41 | 4.50 | +0.09 | ±10% / ±0.45 ms | 4.9% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.41 | 4.50 | +0.09 | ±10% / ±0.45 ms | 4.9% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.59 | 0.57 | -0.02 | ±10% / ±0.06 ms | 9.1% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.59 | 0.57 | -0.02 | ±10% / ±0.06 ms | 9.1% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.08 | 0.07 | -0.01 | ±10% / ±0.02 ms | 3.4% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.08 | 0.07 | -0.01 | ±10% / ±0.02 ms | 3.4% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 5.55 | 5.48 | -0.07 | ±17% / ±0.95 ms | 14.1% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 5.55 | 5.48 | -0.07 | ±17% / ±0.95 ms | 14.1% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.46 | 0.47 | +0.01 | ±10% / ±0.05 ms | 3.2% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.46 | 0.47 | +0.01 | ±10% / ±0.05 ms | 3.2% | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.07 | 0.05 | -0.02 | ±10% / ±0.02 ms | 4.9% | stable | 🟢 Win (-29%) |
| Write Performance / Interactive Transaction (insert + sel... | 0.07 | 0.05 | -0.02 | ±10% / ±0.02 ms | 4.9% | stable | 🟢 Win (-29%) |
| Write Performance / Single Inserts (100 sequential) / res... | 1.88 | 1.92 | +0.04 | ±38% / ±0.73 ms | 18.9% | noisy | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.88 | 1.92 | +0.04 | ±38% / ±0.73 ms | 18.9% | noisy | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.18 | -0.01 | ±10% / ±0.02 ms | 2.7% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.18 | -0.01 | ±10% / ±0.02 ms | 2.7% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.12 | 0.10 | -0.01 | ±10% / ±0.02 ms | 2.9% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.12 | 0.10 | -0.01 | ±10% / ±0.02 ms | 2.9% | stable | ⚪ Within noise |

**Summary:** 6 wins, 0 regressions, 164 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

✅ **No regressions beyond noise.** 6 benchmarks improved.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.02 | 0.05 | +0.03 MB | ±1.25 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 0.00 | 3.50 | +3.50 MB | ±1.91 MB | 🔴 Regression (+3.50 MB) |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 0.00 | 0.00 | +0.00 MB | ±0.92 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 0.75 | 1.03 | +0.28 MB | ±20.05 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 2.00 | 0.00 | -2.00 MB | ±3.00 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 5.14 | 0.00 | -5.14 MB | ±3.54 MB | 🟢 Win (-5.14 MB) |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 8.23 | 0.98 | -7.25 MB | ±5.66 MB | 🟢 Win (-7.25 MB) |
| Memory / Select 10k rows → Maps / resqlite select() | 1.84 | 6.31 | +4.47 MB | ±2.88 MB | 🔴 Regression (+4.47 MB) |
| Memory / Select 10k rows → Maps / sqlite3 select() | 6.58 | 5.03 | -1.55 MB | ±3.85 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 1.00 | 1.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.05 | 0.05 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 2 wins, 2 regressions, 11 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 3685 | 3927 | +242 | ±100 | 🔴 More re-emits (+242) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 3341 | 3708 | +367 | ±100 | 🔴 More re-emits (+367) |

**Granularity summary:** 0 fewer-re-emit, 2 more-re-emit, 4 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


