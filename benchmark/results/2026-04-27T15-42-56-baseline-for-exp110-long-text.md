# resqlite Benchmark Results

Generated: 2026-04-27T15:42:56.903786

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `baseline-for-exp110-long-text`
- Repeats: `1`
- Runtime: `dart-vm / Dart 3.11.0`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `codex/dogfood-experiment-110 @ d559b6c9bd4f (dirty)`
- Comparison baseline: `2026-04-27T07-40-26-exp109-inline-param-buffer.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.090 | 0.134 | 0.022 | 0.026 |
| sqlite3 select() | 0.143 | 0.313 | 0.143 | 0.313 |
| sqlite_async select() | 0.204 | 0.434 | 0.023 | 0.028 |
| drift select() | 0.153 | 0.317 | 0.008 | 0.028 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.071 | 0.109 | 0.009 | 0.011 |
| sqlite3 select() | 0.213 | 0.259 | 0.213 | 0.259 |
| sqlite_async select() | 0.243 | 0.301 | 0.013 | 0.016 |
| drift select() | 0.327 | 0.465 | 0.014 | 0.021 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.455 | 0.561 | 0.078 | 0.085 |
| sqlite3 select() | 1.090 | 1.269 | 1.090 | 1.269 |
| sqlite_async select() | 1.305 | 1.548 | 0.091 | 0.126 |
| drift select() | 1.795 | 2.108 | 0.091 | 0.108 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.586 | 13.371 | 0.688 | 0.764 |
| sqlite3 select() | 16.987 | 25.596 | 16.987 | 25.596 |
| sqlite_async select() | 13.745 | 18.502 | 0.802 | 2.512 |
| drift select() | 21.832 | 31.031 | 0.800 | 1.672 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.063 | 0.111 | 0.041 | 0.075 |
| sqlite3 + jsonEncode | 0.051 | 0.074 | 0.051 | 0.074 |
| sqlite_async + jsonEncode | 0.136 | 0.253 | 0.030 | 0.049 |
| drift + jsonEncode | 0.107 | 0.229 | 0.030 | 0.047 |
| resqlite selectBytes() | 0.027 | 0.078 | 0.001 | 0.005 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.243 | 0.342 | 0.186 | 0.236 |
| sqlite3 + jsonEncode | 0.271 | 0.293 | 0.271 | 0.293 |
| sqlite_async + jsonEncode | 0.399 | 0.616 | 0.177 | 0.222 |
| drift + jsonEncode | 0.356 | 0.430 | 0.159 | 0.172 |
| resqlite selectBytes() | 0.053 | 0.057 | 0.000 | 0.001 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.979 | 3.942 | 1.567 | 2.854 |
| sqlite3 + jsonEncode | 2.806 | 5.939 | 2.806 | 5.939 |
| sqlite_async + jsonEncode | 2.990 | 5.241 | 1.620 | 3.010 |
| drift + jsonEncode | 3.801 | 7.584 | 1.711 | 3.515 |
| resqlite selectBytes() | 0.390 | 0.605 | 0.001 | 0.008 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 23.359 | 30.707 | 16.216 | 21.193 |
| sqlite3 + jsonEncode | 30.889 | 40.437 | 30.889 | 40.437 |
| sqlite_async + jsonEncode | 33.067 | 40.515 | 16.163 | 19.488 |
| drift + jsonEncode | 40.819 | 65.381 | 16.318 | 24.439 |
| resqlite selectBytes() | 3.929 | 5.859 | 0.005 | 0.011 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.138 | 0.309 | 0.027 | 0.234 |
| sqlite3 | 0.372 | 0.580 | 0.372 | 0.580 |
| sqlite_async | 0.425 | 0.672 | 0.047 | 0.067 |
| drift | 0.789 | 1.191 | 0.056 | 0.113 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.990 | 1.112 | 0.302 | 0.314 |
| sqlite3 | 3.404 | 4.140 | 3.404 | 4.140 |
| sqlite_async | 3.057 | 3.622 | 0.335 | 0.369 |
| drift | 5.017 | 7.400 | 0.359 | 0.400 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.579 | 0.641 | 0.103 | 0.116 |
| sqlite3 | 1.480 | 2.363 | 1.480 | 2.363 |
| sqlite_async | 1.498 | 1.728 | 0.126 | 0.148 |
| drift | 2.079 | 2.567 | 0.133 | 0.145 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.302 | 0.356 | 0.100 | 0.107 |
| sqlite3 | 1.023 | 1.245 | 1.023 | 1.245 |
| sqlite_async | 1.084 | 1.363 | 0.131 | 0.147 |
| drift | 1.741 | 2.019 | 0.141 | 0.209 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.307 | 0.505 | 0.101 | 0.121 |
| sqlite3 | 0.935 | 1.044 | 0.935 | 1.044 |
| sqlite_async | 1.054 | 1.212 | 0.125 | 0.152 |
| drift | 1.589 | 1.812 | 0.129 | 0.148 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.016 | 0.018 | 0.002 | 0.002 |
| sqlite3 | 0.022 | 0.026 | 0.022 | 0.026 |
| sqlite_async | 0.093 | 0.236 | 0.007 | 0.013 |
| drift | 0.060 | 0.086 | 0.004 | 0.005 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.035 | 0.063 | 0.005 | 0.006 |
| sqlite3 | 0.064 | 0.071 | 0.064 | 0.071 |
| sqlite_async | 0.134 | 0.196 | 0.008 | 0.021 |
| drift | 0.128 | 0.150 | 0.007 | 0.009 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.051 | 0.060 | 0.009 | 0.010 |
| sqlite3 | 0.117 | 0.154 | 0.117 | 0.154 |
| sqlite_async | 0.165 | 0.190 | 0.012 | 0.014 |
| drift | 0.202 | 0.266 | 0.012 | 0.017 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.292 | 3.290 | 0.051 | 0.255 |
| sqlite3 | 0.746 | 5.087 | 0.746 | 5.087 |
| sqlite_async | 0.581 | 1.135 | 0.052 | 0.083 |
| drift | 0.892 | 2.701 | 0.053 | 0.094 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.400 | 0.800 | 0.089 | 0.103 |
| sqlite3 | 1.229 | 2.471 | 1.229 | 2.471 |
| sqlite_async | 1.118 | 1.392 | 0.102 | 0.119 |
| drift | 1.619 | 1.930 | 0.096 | 0.114 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.977 | 1.923 | 0.182 | 0.250 |
| sqlite3 | 2.478 | 4.657 | 2.478 | 4.657 |
| sqlite_async | 2.298 | 2.634 | 0.201 | 0.215 |
| drift | 3.367 | 4.118 | 0.205 | 0.218 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.435 | 5.354 | 0.450 | 0.611 |
| sqlite3 | 6.836 | 10.157 | 6.836 | 10.157 |
| sqlite_async | 5.946 | 6.811 | 0.495 | 0.532 |
| drift | 9.086 | 9.522 | 0.487 | 0.525 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.787 | 9.673 | 0.886 | 1.348 |
| sqlite3 | 16.879 | 29.678 | 16.879 | 29.678 |
| sqlite_async | 14.297 | 20.636 | 1.007 | 2.022 |
| drift | 22.001 | 29.950 | 1.015 | 1.476 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.235 | 22.302 | 1.805 | 4.047 |
| sqlite3 | 35.940 | 42.355 | 35.940 | 42.355 |
| sqlite_async | 37.017 | 68.269 | 1.930 | 7.228 |
| drift | 54.076 | 91.135 | 1.978 | 7.292 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.040 | 0.047 | 0.040 | 0.047 |
| sqlite3 + jsonEncode | 0.041 | 0.077 | 0.041 | 0.077 |
| sqlite_async + jsonEncode | 0.080 | 0.245 | 0.080 | 0.245 |
| drift + jsonEncode | 0.076 | 0.109 | 0.076 | 0.109 |
| resqlite selectBytes() | 0.019 | 0.026 | 0.019 | 0.026 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.113 | 0.145 | 0.113 | 0.145 |
| sqlite3 + jsonEncode | 0.146 | 0.249 | 0.146 | 0.249 |
| sqlite_async + jsonEncode | 0.164 | 0.168 | 0.164 | 0.168 |
| drift + jsonEncode | 0.200 | 0.277 | 0.200 | 0.277 |
| resqlite selectBytes() | 0.033 | 0.043 | 0.033 | 0.043 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.205 | 0.229 | 0.205 | 0.229 |
| sqlite3 + jsonEncode | 0.260 | 0.323 | 0.260 | 0.323 |
| sqlite_async + jsonEncode | 0.295 | 0.511 | 0.295 | 0.511 |
| drift + jsonEncode | 0.351 | 0.436 | 0.351 | 0.436 |
| resqlite selectBytes() | 0.053 | 0.054 | 0.053 | 0.054 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.947 | 1.028 | 0.947 | 1.028 |
| sqlite3 + jsonEncode | 1.334 | 2.831 | 1.334 | 2.831 |
| sqlite_async + jsonEncode | 1.428 | 2.847 | 1.428 | 2.847 |
| drift + jsonEncode | 1.736 | 3.680 | 1.736 | 3.680 |
| resqlite selectBytes() | 0.188 | 0.241 | 0.188 | 0.241 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.911 | 3.943 | 1.911 | 3.943 |
| sqlite3 + jsonEncode | 2.675 | 5.178 | 2.675 | 5.178 |
| sqlite_async + jsonEncode | 2.821 | 5.710 | 2.821 | 5.710 |
| drift + jsonEncode | 3.317 | 5.760 | 3.317 | 5.760 |
| resqlite selectBytes() | 0.372 | 0.420 | 0.372 | 0.420 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 4.245 | 7.025 | 4.245 | 7.025 |
| sqlite3 + jsonEncode | 5.533 | 9.525 | 5.533 | 9.525 |
| sqlite_async + jsonEncode | 5.971 | 10.172 | 5.971 | 10.172 |
| drift + jsonEncode | 8.290 | 21.297 | 8.290 | 21.297 |
| resqlite selectBytes() | 0.871 | 2.175 | 0.871 | 2.175 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 12.082 | 14.375 | 12.082 | 14.375 |
| sqlite3 + jsonEncode | 15.400 | 20.174 | 15.400 | 20.174 |
| sqlite_async + jsonEncode | 15.321 | 19.757 | 15.321 | 19.757 |
| drift + jsonEncode | 19.838 | 41.849 | 19.838 | 41.849 |
| resqlite selectBytes() | 2.051 | 3.811 | 2.051 | 3.811 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 23.768 | 25.399 | 23.768 | 25.399 |
| sqlite3 + jsonEncode | 33.410 | 44.765 | 33.410 | 44.765 |
| sqlite_async + jsonEncode | 32.331 | 34.360 | 32.331 | 34.360 |
| drift + jsonEncode | 42.293 | 66.782 | 42.293 | 66.782 |
| resqlite selectBytes() | 3.895 | 4.932 | 3.895 | 4.932 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 45.381 | 63.426 | 45.381 | 63.426 |
| sqlite3 + jsonEncode | 67.995 | 92.246 | 67.995 | 92.246 |
| sqlite_async + jsonEncode | 73.724 | 89.233 | 73.724 | 89.233 |
| drift + jsonEncode | 86.965 | 112.377 | 86.965 | 112.377 |
| resqlite selectBytes() | 7.794 | 8.463 | 7.794 | 8.463 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.36 | 0.30 |
| sqlite_async | 0.95 | 1.19 | 0.95 |
| drift | 1.56 | 1.76 | 1.56 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.34 | 0.48 | 0.17 |
| sqlite_async | 1.42 | 1.94 | 0.71 |
| drift | 2.88 | 3.44 | 1.44 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.44 | 1.14 | 0.11 |
| sqlite_async | 4.26 | 8.22 | 1.06 |
| drift | 6.06 | 7.13 | 1.51 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 1.42 | 4.09 | 0.18 |
| sqlite_async | 5.13 | 5.77 | 0.64 |
| drift | 11.13 | 12.12 | 1.39 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 118654 |
| resqlite per query | 0.008 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 118654 | 115404..121826 | 2.7 | 8.2 |
| sqlite3 | 189466 | 178317..191618 | 3.5 | 3.4 |
| sqlite_async | 40931 | 38715..42729 | 4.9 | 16.2 |
| drift | 40733 | 36139..40937 | 5.9 | 3.6 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 15.300 | 16.938 | 15.300 | 16.938 |
| sqlite_async | 38.048 | 45.137 | 38.048 | 45.137 |
| drift | 57.249 | 79.822 | 57.249 | 79.822 |
| sqlite3 (no cache) | 24.076 | 25.723 | 24.076 | 25.723 |
| sqlite3 (cached stmt) | 23.563 | 24.898 | 23.563 | 24.898 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.912 | 2.611 | 1.912 | 2.611 |
| sqlite3 execute() | 0.966 | 1.848 | 0.966 | 1.848 |
| sqlite_async execute() | 3.432 | 3.990 | 3.432 | 3.990 |
| drift execute() | 5.058 | 9.712 | 5.058 | 9.712 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.145 | 0.451 | 0.145 | 0.451 |
| sqlite3 executeBatch() | 0.056 | 0.335 | 0.056 | 0.335 |
| sqlite_async executeBatch() | 0.093 | 0.102 | 0.093 | 0.102 |
| drift executeBatch() | 0.221 | 0.848 | 0.221 | 0.848 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.423 | 0.506 | 0.423 | 0.506 |
| sqlite3 executeBatch() | 0.484 | 1.203 | 0.484 | 1.203 |
| sqlite_async executeBatch() | 0.567 | 1.118 | 0.567 | 1.118 |
| drift executeBatch() | 0.788 | 1.340 | 0.788 | 1.340 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.581 | 9.166 | 4.581 | 9.166 |
| sqlite3 executeBatch() | 5.012 | 14.735 | 5.012 | 14.735 |
| sqlite_async executeBatch() | 5.616 | 6.159 | 5.616 | 6.159 |
| drift executeBatch() | 7.398 | 8.740 | 7.398 | 8.740 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.058 | 0.066 | 0.058 | 0.066 |
| sqlite_async writeTransaction() | 0.097 | 0.170 | 0.097 | 0.170 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.066 | 0.103 | 0.066 | 0.103 |
| resqlite tx.execute() loop | 0.637 | 0.929 | 0.637 | 0.929 |
| sqlite_async tx.execute() loop | 1.279 | 1.597 | 1.279 | 1.597 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.459 | 0.690 | 0.459 | 0.690 |
| resqlite tx.execute() loop | 7.564 | 8.455 | 7.564 | 8.455 |
| sqlite_async tx.execute() loop | 12.565 | 14.330 | 12.565 | 14.330 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.127 | 0.238 | 0.127 | 0.238 |
| sqlite_async tx.getAll() | 0.224 | 0.306 | 0.224 | 0.306 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.193 | 0.258 | 0.193 | 0.258 |
| sqlite_async tx.getAll() | 0.372 | 0.501 | 0.372 | 0.501 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.057 | 0.072 | 0.057 | 0.072 |
| sqlite_async watch() | 0.139 | 0.279 | 0.139 | 0.279 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.066 | 0.141 | 0.066 | 0.141 |
| sqlite_async | 0.100 | 0.266 | 0.100 | 0.266 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.341 | 0.626 | 0.341 | 0.626 |
| sqlite_async | 2.553 | 4.282 | 2.553 | 4.282 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 10.328 | 15.035 | 10.328 | 15.035 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.262 | 0.340 | 0.262 | 0.340 |
| sqlite_async | 0.342 | 0.472 | 0.342 | 0.472 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.068 | 3.068 | 3.068 | 3.068 |
| sqlite_async | 13.075 | 13.075 | 13.075 | 13.075 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 5.489 | 10.602 | 5.489 | 10.602 |
| sqlite_async | 6.607 | 7.711 | 6.607 | 7.711 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.529 | 0.731 | 0.529 | 0.731 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 7.975 | 9.365 | 7.975 | 9.365 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. On resqlite's main branch this ratio is driven toward 0 by experiment 075 (C-side result-hash short-circuit), not by writer-side column-tracking (exp 052 is not implemented). The two mechanisms are indistinguishable on this read-side benchmark.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 77.8 | 0.000 |
| sqlite_async | 3623 | 1112.4 | 1.026 |
| drift | 5000 | 1230.0 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 84.2 | 0.000 |
| sqlite_async | 3530 | 1044.8 | 1.026 |
| drift | 5000 | 1135.8 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 221.72 | 225.19 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 442.65 | 479.75 | 0.00 | 0.00 | 1115 | 3 |
| drift stream() | 582.58 | 678.98 | 0.02 | 0.12 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.026 | 0.048 | 0.000 | 0.000 |
| sqlite3 | 0.023 | 0.049 | 0.023 | 0.049 |
| sqlite_async | 0.046 | 0.077 | 0.000 | 0.000 |
| drift | 0.054 | 0.091 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.019 | 0.033 | 0.000 | 0.000 |
| sqlite3 | 0.015 | 0.026 | 0.015 | 0.026 |
| sqlite_async | 0.037 | 0.058 | 0.000 | 0.000 |
| drift | 0.045 | 0.076 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.027 | 0.041 | 0.000 | 0.000 |
| sqlite3 | 0.032 | 0.037 | 0.032 | 0.037 |
| sqlite_async | 0.063 | 0.083 | 0.000 | 0.000 |
| drift | 0.059 | 0.076 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.009 | 0.019 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.007 | 0.005 | 0.007 |
| sqlite_async | 0.024 | 0.035 | 0.000 | 0.000 |
| drift | 0.024 | 0.037 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.042 | 0.077 | 0.004 | 0.004 |
| sqlite3 | 0.064 | 0.076 | 0.064 | 0.076 |
| sqlite_async | 0.084 | 0.157 | 0.001 | 0.002 |
| drift | 0.114 | 0.274 | 0.001 | 0.002 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 108.399 | 109.407 | 0.000 | 0.000 | 0 |
| sqlite_async | 212.862 | 221.777 | 0.000 | 0.000 | 41 |
| drift | 227.206 | 228.789 | 0.000 | 0.001 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 241.23 | 241.23 | 0.00 | 0.00 | 12.63 | 228.78 | 0 |
| sqlite_async | 488.92 | 488.92 | 0.00 | 0.00 | 24.92 | 464.00 | 1176 |
| drift | 1889.58 | 1889.58 | 0.19 | 0.19 | 13.35 | 1877.13 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 7.63 | 13.17 | 0.00..11.92 | ±5.96 |
| sqlite3 select() | 4.91 | 9.83 | 0.00..6.94 | ±3.47 |
| sqlite_async select() | 1.00 | 1.00 | 0.86..1.00 | ±0.07 |
| drift select() | 9.58 | 57.53 | 0.92..12.13 | ±5.60 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 20.00 | 0.00..8.00 | ±4.00 |
| resqlite + jsonEncode | 0.00 | 71.27 | 0.00..24.97 | ±12.48 |
| sqlite3 + jsonEncode | 0.00 | 75.64 | 0.00..9.48 | ±4.74 |
| sqlite_async + jsonEncode | 0.00 | 45.84 | 0.00..3.03 | ±1.52 |
| drift + jsonEncode | 2.47 | 80.83 | 0.00..13.56 | ±6.78 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 1.56 | 2.42 | 0.61..2.09 | ±0.74 |
| sqlite3 executeBatch() | 0.00 | 0.50 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 2.38 | 0.00..0.05 | ±0.02 |
| drift batch() | 0.00 | 2.00 | 0.00..0.00 | ±0.00 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.30 | 0.00..0.06 | ±0.03 |
| sqlite_async watch() | 0.00 | 0.50 | 0.00..0.13 | ±0.06 |

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

Previous: `2026-04-27T07-40-26-exp109-inline-param-buffer.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.03 | 0.03 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Insert message / resqlite | 0.03 | 0.03 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.30 | +0.00 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.30 | +0.00 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.30 | 0.34 | +0.04 | ±10% / ±0.03 ms | 0.0% | single run | 🔴 Regression (+13%) |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.15 | 0.17 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+13%) |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.36 | 0.44 | +0.08 | ±10% / ±0.04 ms | 0.0% | single run | 🔴 Regression (+22%) |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.09 | 0.11 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+22%) |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.79 | 1.42 | +0.63 | ±10% / ±0.14 ms | 0.0% | single run | 🔴 Regression (+80%) |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.10 | 0.18 | +0.08 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+80%) |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 110.28 | 108.40 | -1.88 | ±10% / ±11.03 ms | 0.0% | single run | ⚪ Neutral |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 241.00 | 241.23 | +0.23 | ±10% / ±24.12 ms | 0.0% | single run | ⚪ Neutral |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 227.00 | 221.72 | -5.28 | ±10% / ±22.70 ms | 0.0% | single run | ⚪ Neutral |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.84 | 15.30 | +0.46 | ±10% / ±1.53 ms | 0.0% | single run | ⚪ Neutral |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.84 | 15.30 | +0.46 | ±10% / ±1.53 ms | 0.0% | single run | ⚪ Neutral |
| Point Query Throughput / resqlite qps | 146189.00 | 118654.00 | -27535.00 | ±10% / ±14618.90 ms | 0.0% | single run | 🔴 Regression (-19%) |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.02 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.04 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.04 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.02 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.02 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.20 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.20 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.05 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.05 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.39 | 0.40 | +0.01 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.87 | 1.91 | +0.04 | ±10% / ±0.19 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.87 | 1.91 | +0.04 | ±10% / ±0.19 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.37 | +0.02 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.37 | +0.02 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.32 | 4.79 | +0.47 | ±10% / ±0.48 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 20.48 | 23.77 | +3.29 | ±10% / ±2.38 ms | 0.0% | single run | 🔴 Regression (+16%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 20.48 | 23.77 | +3.29 | ±10% / ±2.38 ms | 0.0% | single run | 🔴 Regression (+16%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.84 | 0.89 | +0.04 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.70 | 3.90 | +0.19 | ±10% / ±0.39 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.70 | 3.90 | +0.19 | ±10% / ±0.39 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.82 | 0.98 | +0.16 | ±10% / ±0.10 ms | 0.0% | single run | 🔴 Regression (+19%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.87 | 4.25 | +0.38 | ±10% / ±0.42 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.87 | 4.25 | +0.38 | ±10% / ±0.42 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.18 | 0.18 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.82 | 0.87 | +0.05 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.82 | 0.87 | +0.05 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.88 | 14.23 | +3.35 | ±10% / ±1.42 ms | 0.0% | single run | 🔴 Regression (+31%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 44.49 | 45.38 | +0.89 | ±10% / ±4.54 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 44.49 | 45.38 | +0.89 | ±10% / ±4.54 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.71 | 1.80 | +0.10 | ±10% / ±0.18 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.84 | 7.79 | -1.05 | ±10% / ±0.88 ms | 0.0% | single run | 🟢 Win (-12%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.84 | 7.79 | -1.05 | ±10% / ±0.88 ms | 0.0% | single run | 🟢 Win (-12%) |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.04 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.11 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.10 | 0.11 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.20 | 0.29 | +0.09 | ±10% / ±0.03 ms | 0.0% | single run | 🔴 Regression (+45%) |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.90 | 0.95 | +0.05 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.90 | 0.95 | +0.05 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.05 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.19 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.19 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.06 | 2.44 | +0.38 | ±10% / ±0.24 ms | 0.0% | single run | 🔴 Regression (+18%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.31 | 12.08 | +1.77 | ±10% / ±1.21 ms | 0.0% | single run | 🔴 Regression (+17%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.31 | 12.08 | +1.77 | ±10% / ±1.21 ms | 0.0% | single run | 🔴 Regression (+17%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.42 | 0.45 | +0.03 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.90 | 2.05 | +0.15 | ±10% / ±0.21 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.90 | 2.05 | +0.15 | ±10% / ±0.21 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.11 | 0.14 | +0.03 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+30%) |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.04 | 0.03 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.29 | 0.31 | +0.01 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.29 | 0.30 | +0.01 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.10 | 0.10 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.52 | 0.58 | +0.05 | ±10% / ±0.06 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.91 | 0.99 | +0.08 | ±10% / ±0.10 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.27 | 0.30 | +0.03 | ±10% / ±0.03 ms | 0.0% | single run | 🔴 Regression (+13%) |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.06 | +0.04 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+152%) |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.04 | +0.03 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+156%) |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.03 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.22 | 0.24 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.17 | 0.19 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.05 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.84 | 1.98 | +0.14 | ±10% / ±0.20 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.52 | 1.57 | +0.05 | ±10% / ±0.16 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.35 | 0.39 | +0.04 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 22.29 | 23.36 | +1.07 | ±10% / ±2.34 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 15.22 | 16.22 | +1.00 | ±10% / ±1.62 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.94 | 3.93 | -0.01 | ±10% / ±0.39 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.09 | +0.08 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+592%) |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.02 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+2100%) |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.07 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+51%) |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 1000 rows / resqlite select() | 0.41 | 0.46 | +0.05 | ±10% / ±0.05 ms | 0.0% | single run | 🔴 Regression (+12%) |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.08 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 10000 rows / resqlite select() | 4.58 | 4.59 | +0.01 | ±10% / ±0.46 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.85 | 0.69 | -0.16 | ±10% / ±0.09 ms | 0.0% | single run | 🟢 Win (-19%) |
| Streaming / Fan-out (10 streams) / resqlite | 0.40 | 0.26 | -0.13 | ±10% / ±0.04 ms | 0.0% | single run | 🟢 Win (-34%) |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.40 | 0.26 | -0.13 | ±10% / ±0.04 ms | 0.0% | single run | 🟢 Win (-34%) |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.52 | 0.53 | +0.01 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.52 | 0.53 | +0.01 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.06 | +0.03 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+111%) |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.06 | +0.03 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+111%) |
| Streaming / Invalidation Latency / resqlite | 0.06 | 0.07 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Invalidation Latency / resqlite [main] | 0.06 | 0.07 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.46 | 5.49 | +2.03 | ±10% / ±0.55 ms | 0.0% | single run | 🔴 Regression (+59%) |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.46 | 5.49 | +2.03 | ±10% / ±0.55 ms | 0.0% | single run | 🔴 Regression (+59%) |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.92 | 3.07 | +1.15 | ±10% / ±0.31 ms | 0.0% | single run | 🔴 Regression (+60%) |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.92 | 3.07 | +1.15 | ±10% / ±0.31 ms | 0.0% | single run | 🔴 Regression (+60%) |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 5.50 | 7.97 | +2.47 | ±10% / ±0.80 ms | 0.0% | single run | 🔴 Regression (+45%) |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 5.50 | 7.97 | +2.47 | ±10% / ±0.80 ms | 0.0% | single run | 🔴 Regression (+45%) |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.21 | 0.34 | +0.13 | ±10% / ±0.03 ms | 0.0% | single run | 🔴 Regression (+62%) |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.21 | 0.34 | +0.13 | ±10% / ±0.03 ms | 0.0% | single run | 🔴 Regression (+62%) |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.14 | +0.09 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+184%) |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.14 | +0.09 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+184%) |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.39 | 0.42 | +0.04 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.39 | 0.42 | +0.04 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.66 | 4.58 | +0.92 | ±10% / ±0.46 ms | 0.0% | single run | 🔴 Regression (+25%) |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.66 | 4.58 | +0.92 | ±10% / ±0.46 ms | 0.0% | single run | 🔴 Regression (+25%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.59 | 0.64 | +0.05 | ±10% / ±0.06 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.59 | 0.64 | +0.05 | ±10% / ±0.06 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.06 | 0.07 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.06 | 0.07 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 5.17 | 7.56 | +2.40 | ±10% / ±0.76 ms | 0.0% | single run | 🔴 Regression (+46%) |
| Write Performance / Batched Write Inside Transaction (100... | 5.17 | 7.56 | +2.40 | ±10% / ±0.76 ms | 0.0% | single run | 🔴 Regression (+46%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.38 | 0.46 | +0.08 | ±10% / ±0.05 ms | 0.0% | single run | 🔴 Regression (+20%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.38 | 0.46 | +0.08 | ±10% / ±0.05 ms | 0.0% | single run | 🔴 Regression (+20%) |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.06 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.06 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Single Inserts (100 sequential) / res... | 1.61 | 1.91 | +0.30 | ±10% / ±0.19 ms | 0.0% | single run | 🔴 Regression (+19%) |
| Write Performance / Single Inserts (100 sequential) / res... | 1.61 | 1.91 | +0.30 | ±10% / ±0.19 ms | 0.0% | single run | 🔴 Regression (+19%) |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.19 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.19 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.11 | 0.13 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+19%) |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.11 | 0.13 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+19%) |

**Summary:** 5 wins, 45 regressions, 103 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.02 | 0.00 | -0.02 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 1.00 | 1.56 | +0.56 MB | ±0.74 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.02 | 0.00 | -0.02 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 0.00 | 2.47 | +2.47 MB | ±6.78 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 0.00 | 0.00 | +0.00 MB | ±12.48 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 0.00 | +0.00 MB | ±4.00 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 1.19 | 0.00 | -1.19 MB | ±4.74 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±1.52 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 5.16 | 9.58 | +4.42 MB | ±5.60 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / resqlite select() | 1.36 | 7.63 | +6.27 MB | ±5.96 MB | 🔴 Regression (+6.27 MB) |
| Memory / Select 10k rows → Maps / sqlite3 select() | 4.73 | 4.91 | +0.18 MB | ±3.47 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 1.00 | 1.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.06 | 0.06 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 0 wins, 1 regressions, 14 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 4244 | 3623 | -621 | ±100 | 🟢 Fewer re-emits (-621) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 3484 | 3530 | +46 | ±100 | ⚪ Within noise |

**Granularity summary:** 1 fewer-re-emit, 0 more-re-emit, 5 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


