# resqlite Benchmark Results

Generated: 2026-09-11T08:38:37.621014

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp289-warm-connection-reruns`
- Repeats: `5`
- Runtime: `dart-vm / Dart 3.12.2`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `exp-289-reader-snapshot-tax @ 9583bb6affdd`
- Comparison baseline: `2026-08-09T20-36-47-exp266-headline-refresh.md`
- Comparison mode: `explicit`
- Comparison baseline compatibility: `incompatible (explicit comparison)`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.010 | 0.011 | 0.000 | 0.000 |
| sqlite3 select() | 0.016 | 0.017 | 0.016 | 0.017 |
| sqlite_async select() | 0.031 | 0.033 | 0.001 | 0.002 |
| drift select() | 0.037 | 0.039 | 0.001 | 0.001 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.038 | 0.039 | 0.005 | 0.005 |
| sqlite3 select() | 0.123 | 0.125 | 0.123 | 0.125 |
| sqlite_async select() | 0.131 | 0.138 | 0.010 | 0.011 |
| drift select() | 0.182 | 0.186 | 0.010 | 0.010 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.302 | 0.308 | 0.052 | 0.053 |
| sqlite3 select() | 1.177 | 1.213 | 1.177 | 1.213 |
| sqlite_async select() | 1.077 | 1.116 | 0.094 | 0.095 |
| drift select() | 1.583 | 1.598 | 0.093 | 0.093 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 3.241 | 8.732 | 0.517 | 0.750 |
| sqlite3 select() | 14.444 | 16.811 | 14.444 | 16.811 |
| sqlite_async select() | 12.484 | 15.261 | 0.950 | 2.184 |
| drift select() | 21.346 | 27.343 | 0.942 | 1.294 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row. The large-payload row isolates resqlite selectBytes because it guards the native bytes transfer policy without multiplying large JSON encoding work across every peer.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.027 | 0.027 | 0.017 | 0.017 |
| sqlite3 + jsonEncode | 0.033 | 0.035 | 0.033 | 0.035 |
| sqlite_async + jsonEncode | 0.048 | 0.055 | 0.017 | 0.018 |
| drift + jsonEncode | 0.053 | 0.054 | 0.017 | 0.017 |
| resqlite selectBytes() | 0.011 | 0.011 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.200 | 0.202 | 0.167 | 0.168 |
| sqlite3 + jsonEncode | 0.275 | 0.288 | 0.275 | 0.288 |
| sqlite_async + jsonEncode | 0.285 | 0.289 | 0.163 | 0.166 |
| drift + jsonEncode | 0.332 | 0.343 | 0.162 | 0.167 |
| resqlite selectBytes() | 0.035 | 0.037 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.836 | 3.711 | 1.583 | 2.921 |
| sqlite3 + jsonEncode | 2.679 | 3.403 | 2.679 | 3.403 |
| sqlite_async + jsonEncode | 2.570 | 3.388 | 1.579 | 1.680 |
| drift + jsonEncode | 3.078 | 3.710 | 1.575 | 2.218 |
| resqlite selectBytes() | 0.264 | 0.267 | 0.000 | 0.000 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.728 | 25.086 | 15.930 | 17.688 |
| sqlite3 + jsonEncode | 30.232 | 35.799 | 30.232 | 35.799 |
| sqlite_async + jsonEncode | 29.495 | 35.215 | 16.292 | 17.632 |
| drift + jsonEncode | 40.659 | 42.840 | 16.290 | 21.452 |
| resqlite selectBytes() | 2.638 | 2.708 | 0.000 | 0.000 |

### Large payload (~650KB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.270 | 0.277 | 0.000 | 0.000 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.086 | 0.088 | 0.023 | 0.026 |
| sqlite3 | 0.338 | 0.347 | 0.338 | 0.347 |
| sqlite_async | 0.375 | 0.382 | 0.033 | 0.036 |
| drift | 0.575 | 0.599 | 0.032 | 0.033 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.782 | 0.796 | 0.223 | 0.229 |
| sqlite3 | 3.351 | 3.892 | 3.351 | 3.892 |
| sqlite_async | 2.966 | 3.395 | 0.236 | 0.246 |
| drift | 4.811 | 6.009 | 0.245 | 0.255 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.370 | 0.377 | 0.061 | 0.064 |
| sqlite3 | 1.486 | 1.573 | 1.486 | 1.573 |
| sqlite_async | 1.394 | 1.714 | 0.086 | 0.089 |
| drift | 1.960 | 2.225 | 0.085 | 0.087 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.242 | 0.247 | 0.061 | 0.064 |
| sqlite3 | 1.024 | 1.048 | 1.024 | 1.048 |
| sqlite_async | 0.953 | 0.974 | 0.084 | 0.086 |
| drift | 1.445 | 1.463 | 0.083 | 0.084 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.249 | 0.251 | 0.062 | 0.063 |
| sqlite3 | 0.994 | 1.045 | 0.994 | 1.045 |
| sqlite_async | 0.957 | 0.966 | 0.084 | 0.085 |
| drift | 1.428 | 1.713 | 0.083 | 0.087 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.010 | 0.010 | 0.000 | 0.000 |
| sqlite3 | 0.016 | 0.016 | 0.016 | 0.016 |
| sqlite_async | 0.031 | 0.031 | 0.001 | 0.001 |
| drift | 0.036 | 0.037 | 0.001 | 0.001 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.022 | 0.023 | 0.003 | 0.003 |
| sqlite3 | 0.063 | 0.064 | 0.063 | 0.064 |
| sqlite_async | 0.074 | 0.077 | 0.004 | 0.004 |
| drift | 0.100 | 0.102 | 0.004 | 0.004 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.038 | 0.039 | 0.005 | 0.006 |
| sqlite3 | 0.121 | 0.125 | 0.121 | 0.125 |
| sqlite_async | 0.128 | 0.131 | 0.008 | 0.008 |
| drift | 0.178 | 0.182 | 0.007 | 0.008 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.160 | 0.165 | 0.027 | 0.029 |
| sqlite3 | 0.581 | 0.603 | 0.581 | 0.603 |
| sqlite_async | 0.540 | 0.544 | 0.036 | 0.037 |
| drift | 0.797 | 0.840 | 0.035 | 0.039 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.305 | 0.310 | 0.053 | 0.054 |
| sqlite3 | 1.156 | 1.171 | 1.156 | 1.171 |
| sqlite_async | 1.057 | 1.070 | 0.072 | 0.073 |
| drift | 1.555 | 1.574 | 0.071 | 0.072 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.592 | 0.603 | 0.106 | 0.108 |
| sqlite3 | 2.305 | 2.754 | 2.305 | 2.754 |
| sqlite_async | 2.099 | 2.410 | 0.143 | 0.146 |
| drift | 3.115 | 3.576 | 0.142 | 0.143 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.728 | 3.856 | 0.264 | 0.425 |
| sqlite3 | 5.785 | 7.043 | 5.785 | 7.043 |
| sqlite_async | 5.358 | 6.185 | 0.360 | 0.367 |
| drift | 8.354 | 8.552 | 0.356 | 0.360 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.247 | 9.052 | 0.526 | 0.829 |
| sqlite3 | 14.284 | 17.634 | 14.284 | 17.634 |
| sqlite_async | 11.418 | 12.136 | 0.721 | 0.755 |
| drift | 18.309 | 24.955 | 0.734 | 2.081 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 7.392 | 14.095 | 1.062 | 1.917 |
| sqlite3 | 33.397 | 38.185 | 33.397 | 38.185 |
| sqlite_async | 35.283 | 39.106 | 1.480 | 6.241 |
| drift | 49.683 | 61.163 | 1.467 | 2.811 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.030 | 0.036 | 0.030 | 0.036 |
| sqlite3 + jsonEncode | 0.032 | 0.033 | 0.032 | 0.033 |
| sqlite_async + jsonEncode | 0.048 | 0.049 | 0.048 | 0.049 |
| drift + jsonEncode | 0.053 | 0.055 | 0.053 | 0.055 |
| resqlite selectBytes() | 0.011 | 0.012 | 0.011 | 0.012 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.107 | 0.126 | 0.107 | 0.126 |
| sqlite3 + jsonEncode | 0.140 | 0.143 | 0.140 | 0.143 |
| sqlite_async + jsonEncode | 0.155 | 0.159 | 0.155 | 0.159 |
| drift + jsonEncode | 0.180 | 0.197 | 0.180 | 0.197 |
| resqlite selectBytes() | 0.022 | 0.025 | 0.022 | 0.025 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.199 | 0.201 | 0.199 | 0.201 |
| sqlite3 + jsonEncode | 0.277 | 0.280 | 0.277 | 0.280 |
| sqlite_async + jsonEncode | 0.286 | 0.299 | 0.286 | 0.299 |
| drift + jsonEncode | 0.332 | 0.335 | 0.332 | 0.335 |
| resqlite selectBytes() | 0.035 | 0.037 | 0.035 | 0.037 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.932 | 0.965 | 0.932 | 0.965 |
| sqlite3 + jsonEncode | 1.350 | 1.363 | 1.350 | 1.363 |
| sqlite_async + jsonEncode | 1.304 | 1.327 | 1.304 | 1.327 |
| drift + jsonEncode | 1.557 | 1.615 | 1.557 | 1.615 |
| resqlite selectBytes() | 0.134 | 0.137 | 0.134 | 0.137 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.822 | 2.150 | 1.822 | 2.150 |
| sqlite3 + jsonEncode | 2.777 | 3.478 | 2.777 | 3.478 |
| sqlite_async + jsonEncode | 2.615 | 3.396 | 2.615 | 3.396 |
| drift + jsonEncode | 3.091 | 3.551 | 3.091 | 3.551 |
| resqlite selectBytes() | 0.259 | 0.263 | 0.259 | 0.263 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.762 | 6.583 | 3.762 | 6.583 |
| sqlite3 + jsonEncode | 5.702 | 8.618 | 5.702 | 8.618 |
| sqlite_async + jsonEncode | 5.480 | 9.139 | 5.480 | 9.139 |
| drift + jsonEncode | 6.502 | 11.079 | 6.502 | 11.079 |
| resqlite selectBytes() | 0.511 | 0.521 | 0.511 | 0.521 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 10.043 | 13.371 | 10.043 | 13.371 |
| sqlite3 + jsonEncode | 15.565 | 18.734 | 15.565 | 18.734 |
| sqlite_async + jsonEncode | 14.053 | 19.390 | 14.053 | 19.390 |
| drift + jsonEncode | 17.450 | 23.330 | 17.450 | 23.330 |
| resqlite selectBytes() | 1.262 | 1.283 | 1.262 | 1.283 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 23.430 | 24.702 | 23.430 | 24.702 |
| sqlite3 + jsonEncode | 31.854 | 35.876 | 31.854 | 35.876 |
| sqlite_async + jsonEncode | 32.166 | 36.628 | 32.166 | 36.628 |
| drift + jsonEncode | 37.636 | 43.452 | 37.636 | 43.452 |
| resqlite selectBytes() | 2.567 | 2.675 | 2.567 | 2.675 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 44.951 | 46.696 | 44.951 | 46.696 |
| sqlite3 + jsonEncode | 65.700 | 69.812 | 65.700 | 69.812 |
| sqlite_async + jsonEncode | 69.011 | 73.854 | 69.011 | 73.854 |
| drift + jsonEncode | 84.263 | 96.905 | 84.263 | 96.905 |
| resqlite selectBytes() | 5.376 | 5.493 | 5.376 | 5.493 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.26 | 0.26 | 0.26 |
| sqlite_async | 0.99 | 1.00 | 0.99 |
| drift | 1.49 | 1.55 | 1.49 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.28 | 0.29 | 0.14 |
| sqlite_async | 1.47 | 1.76 | 0.73 |
| drift | 2.73 | 3.06 | 1.36 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.35 | 0.64 | 0.09 |
| sqlite_async | 2.46 | 3.07 | 0.62 |
| drift | 5.22 | 5.66 | 1.30 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.72 | 1.01 | 0.09 |
| sqlite_async | 5.04 | 5.44 | 0.63 |
| drift | 10.56 | 11.07 | 1.32 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 165123 |
| resqlite per query | 0.006 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 165123 | 163605..166268 | 0.8 | 2.1 |
| sqlite3 | 186189 | 185747..186406 | 0.2 | 0.7 |
| sqlite_async | 50117 | 49650..50224 | 0.6 | 1.2 |
| drift | 48861 | 48727..49238 | 0.5 | 2.1 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 13.597 | 13.802 | 13.597 | 13.802 |
| sqlite_async | 36.806 | 37.294 | 36.806 | 37.294 |
| drift | 52.761 | 53.850 | 52.761 | 53.850 |
| sqlite3 (no cache) | 24.267 | 24.413 | 24.267 | 24.413 |
| sqlite3 (cached stmt) | 23.937 | 23.993 | 23.937 | 23.993 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.555 | 2.767 | 1.555 | 2.767 |
| sqlite3 execute() | 0.924 | 1.559 | 0.924 | 1.559 |
| sqlite_async execute() | 2.653 | 3.420 | 2.653 | 3.420 |
| drift execute() | 2.622 | 3.325 | 2.622 | 3.325 |

### Concurrent Single Inserts (100 concurrent)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite concurrent execute() | 0.840 | 1.220 | 0.840 | 1.220 |
| sqlite3 concurrent execute() | 0.887 | 1.547 | 0.887 | 1.547 |
| sqlite_async concurrent execute() | 2.659 | 3.333 | 2.659 | 3.333 |
| drift concurrent execute() | 1.667 | 2.423 | 1.667 | 2.423 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.051 | 0.052 | 0.051 | 0.052 |
| sqlite3 executeBatch() | 0.048 | 0.049 | 0.048 | 0.049 |
| sqlite_async executeBatch() | 0.096 | 0.100 | 0.096 | 0.100 |
| drift executeBatch() | 0.112 | 0.116 | 0.112 | 0.116 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.415 | 0.424 | 0.415 | 0.424 |
| sqlite3 executeBatch() | 0.436 | 0.440 | 0.436 | 0.440 |
| sqlite_async executeBatch() | 0.516 | 0.522 | 0.516 | 0.522 |
| drift executeBatch() | 0.652 | 0.664 | 0.652 | 0.664 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 3.792 | 4.607 | 3.792 | 4.607 |
| sqlite3 executeBatch() | 4.041 | 4.282 | 4.041 | 4.282 |
| sqlite_async executeBatch() | 4.681 | 5.215 | 4.681 | 5.215 |
| drift executeBatch() | 6.111 | 7.169 | 6.111 | 7.169 |

### Wide Batch Insert (10000 rows x 20 params)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 12.589 | 17.958 | 12.589 | 17.958 |
| sqlite3 executeBatch() | 19.196 | 21.386 | 19.196 | 21.386 |
| sqlite_async executeBatch() | 21.555 | 23.884 | 21.555 | 23.884 |
| drift executeBatch() | 25.294 | 30.813 | 25.294 | 30.813 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.044 | 0.048 | 0.044 | 0.048 |
| sqlite_async writeTransaction() | 0.082 | 0.094 | 0.082 | 0.094 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.064 | 0.066 | 0.064 | 0.066 |
| resqlite tx.execute() loop | 0.557 | 0.568 | 0.557 | 0.568 |
| sqlite_async tx.execute() loop | 1.027 | 1.255 | 1.027 | 1.255 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.407 | 0.440 | 0.407 | 0.440 |
| resqlite tx.execute() loop | 4.988 | 5.380 | 4.988 | 5.380 |
| sqlite_async tx.execute() loop | 9.705 | 10.414 | 9.705 | 10.414 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.094 | 0.097 | 0.094 | 0.097 |
| sqlite_async tx.getAll() | 0.203 | 0.211 | 0.203 | 0.211 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.170 | 0.178 | 0.170 | 0.178 |
| sqlite_async tx.getAll() | 0.382 | 0.392 | 0.382 | 0.392 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 0.840 | 1.024 | 0.840 | 1.024 |
| resqlite nested transaction() depth=5 | 0.069 | 0.083 | 0.069 | 0.083 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.026 | 0.027 | 0.026 | 0.027 |
| sqlite_async watch() | 0.104 | 0.121 | 0.104 | 0.121 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.040 | 0.047 | 0.040 | 0.047 |
| sqlite_async | 0.065 | 0.076 | 0.065 | 0.076 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.097 | 0.151 | 0.097 | 0.151 |
| sqlite_async | 0.525 | 1.199 | 0.525 | 1.199 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.757 | 2.223 | 1.757 | 2.223 |

### Long-Payload Unchanged Fanout (8 streams, 64 rows x 32KB TEXT + 32KB BLOB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.293 | 3.181 | 0.293 | 3.181 |

### Long-Text 32KB Unchanged Fanout (8 unchanged streams, 64 rows x 32KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.724 | 3.678 | 2.724 | 3.678 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.184 | 0.215 | 0.184 | 0.215 |
| sqlite_async | 0.285 | 0.333 | 0.285 | 0.333 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.354 | 1.354 | 1.354 | 1.354 |
| sqlite_async | 7.888 | 7.888 | 7.888 | 7.888 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.033 | 3.520 | 3.033 | 3.520 |
| sqlite_async | 5.497 | 6.590 | 5.497 | 6.590 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.477 | 0.661 | 0.477 | 0.661 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 6.107 | 6.777 | 6.107 | 6.777 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. For resqlite, this emission metric can reflect writer-side column-level invalidation, experiment 075's native result-hash short-circuit, or both. Use A11c (Many-Streams Writer Throughput) when the question is specifically writer-side dispatch elision.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 65.8 | 0.000 |
| sqlite_async | 4021 | 1105.7 | 1.089 |
| drift | 5000 | 1004.7 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 71.7 | 0.000 |
| sqlite_async | 3694 | 1007.6 | 1.089 |
| drift | 5000 | 1004.5 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 217.12 | 217.84 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 433.75 | 434.83 | 0.00 | 0.00 | 1127 | 3 |
| drift stream() | 532.08 | 535.31 | 0.00 | 0.01 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.018 | 0.026 | 0.000 | 0.000 |
| sqlite3 | 0.019 | 0.022 | 0.019 | 0.022 |
| sqlite_async | 0.036 | 0.042 | 0.000 | 0.000 |
| drift | 0.037 | 0.043 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.014 | 0.018 | 0.000 | 0.000 |
| sqlite3 | 0.012 | 0.014 | 0.012 | 0.014 |
| sqlite_async | 0.029 | 0.033 | 0.000 | 0.000 |
| drift | 0.030 | 0.034 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.018 | 0.027 | 0.000 | 0.000 |
| sqlite3 | 0.031 | 0.033 | 0.031 | 0.033 |
| sqlite_async | 0.056 | 0.064 | 0.000 | 0.000 |
| drift | 0.053 | 0.057 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.006 | 0.011 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.020 | 0.024 | 0.000 | 0.000 |
| drift | 0.020 | 0.023 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.039 | 0.040 | 0.001 | 0.001 |
| sqlite3 | 0.067 | 0.068 | 0.067 | 0.068 |
| sqlite_async | 0.083 | 0.085 | 0.001 | 0.001 |
| drift | 0.090 | 0.096 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 108.694 | 109.015 | 0.000 | 0.000 | 0 |
| sqlite_async | 213.000 | 213.377 | 0.000 | 0.000 | 35 |
| drift | 223.283 | 223.516 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 435.06 | 435.06 | 0.00 | 0.00 | 12.83 | 422.23 | 2 |
| sqlite_async | 476.15 | 476.15 | 0.00 | 0.00 | 24.57 | 451.57 | 1172 |
| drift | 1664.72 | 1664.72 | 0.04 | 0.04 | 14.25 | 1650.46 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 1.28 | 13.08 | 0.00..12.08 | ±6.04 |
| sqlite3 select() | 4.53 | 14.83 | 1.75..8.84 | ±3.55 |
| sqlite_async select() | 1.00 | 1.00 | 1.00..1.00 | ±0.00 |
| drift select() | 11.05 | 74.05 | 6.67..71.61 | ±32.47 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| resqlite + jsonEncode | 0.00 | 3.61 | 0.00..0.50 | ±0.25 |
| sqlite3 + jsonEncode | 0.00 | 12.20 | 0.00..7.97 | ±3.98 |
| sqlite_async + jsonEncode | 0.00 | 3.03 | 0.00..0.00 | ±0.00 |
| drift + jsonEncode | 0.00 | 15.13 | 0.00..12.06 | ±6.03 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 7.14 | 7.70 | 6.72..7.25 | ±0.27 |
| sqlite3 executeBatch() | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| drift batch() | 0.00 | 5.00 | 0.00..2.52 | ±1.26 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.09 | 0.28 | 0.08..0.11 | ±0.02 |
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
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.02 | 0.02..0.02 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 7.1% | 14.3% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02..0.02 | 5.3% | 10.5% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.01..0.01 | 3.3% | 6.7% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.25 | 0.24..0.26 | 4.0% | 8.0% | 4.0% | moderate |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.25 | 0.24..0.26 | 4.0% | 8.0% | 4.0% | moderate |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.28 | 0.28..0.28 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.14 | 0.14..0.14 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.32 | 0.31..0.35 | 6.2% | 12.5% | 3.1% | moderate |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.08 | 0.08..0.09 | 6.2% | 12.5% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.72 | 0.58..0.72 | 9.7% | 19.4% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.09 | 0.07..0.09 | 11.1% | 22.2% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.04 | 3.8% | 7.7% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 150.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 108.69 | 108.18..109.16 | 0.5% | 0.9% | 0.3% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 234.99 | 232.35..435.06 | 43.1% | 86.3% | 0.8% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 217.12 | 215.87..218.59 | 0.6% | 1.3% | 0.6% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 13.60 | 13.52..13.62 | 0.4% | 0.7% | 0.2% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 13.60 | 13.52..13.62 | 0.4% | 0.7% | 0.2% | stable |
| Point Query Throughput / resqlite qps | 166661.00 | 165014.00..169071.00 | 1.2% | 2.4% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.01 | 20.0% | 40.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.04 | 16.7% | 33.3% | 10.0% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.04 | 16.7% | 33.3% | 10.0% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.01 | 9.1% | 18.2% | 9.1% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.01 | 9.1% | 18.2% | 9.1% | noisy |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.04..0.04 | 3.9% | 7.9% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.20 | 0.20..0.20 | 1.2% | 2.5% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.20 | 0.20..0.20 | 1.2% | 2.5% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.04 | 4.3% | 8.6% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.04 | 0.04..0.04 | 4.3% | 8.6% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.31 | 0.30..0.31 | 0.5% | 1.0% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.82 | 1.82..1.89 | 1.9% | 3.9% | 0.1% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.82 | 1.82..1.89 | 1.9% | 3.9% | 0.1% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.05 | 0.05..0.05 | 0.9% | 1.9% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.26 | 0.26..0.27 | 2.7% | 5.3% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.26 | 0.26..0.27 | 2.7% | 5.3% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 3.28 | 3.24..3.37 | 2.0% | 4.0% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 21.91 | 20.30..23.43 | 7.2% | 14.3% | 5.0% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 21.91 | 20.30..23.43 | 7.2% | 14.3% | 5.0% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.53 | 0.53..0.54 | 1.0% | 2.1% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 2.63 | 2.57..2.64 | 1.4% | 2.7% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 2.63 | 2.57..2.64 | 1.4% | 2.7% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.59 | 0.58..0.60 | 1.6% | 3.2% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.77 | 3.75..3.80 | 0.7% | 1.4% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.77 | 3.75..3.80 | 0.7% | 1.4% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.11 | 0.11..0.11 | 0.5% | 0.9% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.52 | 0.51..0.54 | 2.8% | 5.6% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.52 | 0.51..0.54 | 2.8% | 5.6% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 8.37 | 7.39..8.66 | 7.6% | 15.1% | 3.4% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 44.72 | 43.93..45.24 | 1.5% | 2.9% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 44.72 | 43.93..45.24 | 1.5% | 2.9% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.06 | 1.05..1.06 | 0.4% | 0.8% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 5.38 | 5.36..5.55 | 1.8% | 3.6% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 5.38 | 5.36..5.55 | 1.8% | 3.6% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.02 | 0.02..0.03 | 11.4% | 22.7% | 4.5% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.10..0.11 | 2.4% | 4.7% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.11 | 0.10..0.11 | 2.4% | 4.7% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.00 | 16.7% | 33.3% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.02 | 0.02..0.02 | 6.8% | 13.6% | 4.5% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.02 | 0.02..0.02 | 6.8% | 13.6% | 4.5% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.16 | 0.16..0.16 | 0.9% | 1.9% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.94 | 0.93..0.96 | 1.3% | 2.7% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.94 | 0.93..0.96 | 1.3% | 2.7% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.03 | 0.03..0.03 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.14 | 0.13..0.14 | 1.5% | 2.9% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.14 | 0.13..0.14 | 1.5% | 2.9% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 1.72 | 1.69..1.73 | 1.1% | 2.3% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 10.04 | 9.42..12.21 | 13.9% | 27.7% | 6.2% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 10.04 | 9.42..12.21 | 13.9% | 27.7% | 6.2% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.27 | 0.26..0.27 | 0.8% | 1.5% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 1.28 | 1.26..1.35 | 3.3% | 6.6% | 1.3% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 1.28 | 1.26..1.35 | 3.3% | 6.6% | 1.3% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.09 | 0.09..0.16 | 43.1% | 86.2% | 1.1% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.02 | 0.02..0.03 | 19.6% | 39.1% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.25 | 0.25..0.25 | 0.4% | 0.8% | 0.4% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.06 | 0.06..0.06 | 0.8% | 1.6% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.24 | 0.24..0.24 | 1.0% | 2.1% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.06 | 0.06..0.06 | 0.8% | 1.6% | 0.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.37 | 0.37..0.37 | 0.8% | 1.6% | 0.5% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.06 | 0.06..0.06 | 0.8% | 1.6% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.78 | 0.78..0.78 | 0.3% | 0.6% | 0.3% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.22 | 0.22..0.23 | 0.7% | 1.3% | 0.4% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.06 | 63.0% | 125.9% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02..0.04 | 64.7% | 129.4% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 27.3% | 54.5% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.20..0.22 | 4.0% | 7.9% | 0.5% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.17 | 0.17..0.18 | 2.7% | 5.4% | 0.6% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.04 | 8.3% | 16.7% | 2.8% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.84 | 1.82..1.84 | 0.5% | 1.1% | 0.4% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.58 | 1.57..1.58 | 0.3% | 0.7% | 0.3% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.26 | 0.26..0.28 | 4.0% | 8.0% | 1.5% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.42 | 19.75..23.31 | 8.7% | 17.4% | 1.8% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 15.99 | 15.82..16.00 | 0.6% | 1.2% | 0.1% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 2.66 | 2.63..2.67 | 0.8% | 1.7% | 0.5% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / Large payload (~650KB) / resqlite selectBytes() | 0.27 | 0.23..0.28 | 8.3% | 16.7% | 3.7% | moderate |
| Select → JSON Bytes / Large payload (~650KB) / resqlite selectBytes... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.06 | 260.0% | 520.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.04 | 0.04..0.15 | 147.4% | 294.7% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 20.0% | 40.0% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.30 | 0.30..0.37 | 11.1% | 22.1% | 0.7% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.05 | 0.05..0.06 | 6.6% | 13.2% | 0.0% | stable |
| Select → Maps / 10000 rows / resqlite select() | 3.24 | 3.24..3.38 | 2.3% | 4.5% | 0.1% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.52 | 0.51..0.53 | 1.8% | 3.7% | 1.0% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.18 | 0.17..0.22 | 11.7% | 23.4% | 2.2% | stable |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.18 | 0.17..0.22 | 11.7% | 23.4% | 2.2% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.47 | 0.46..0.50 | 3.5% | 7.0% | 1.3% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.47 | 0.46..0.50 | 3.5% | 7.0% | 1.3% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03..0.07 | 76.9% | 153.8% | 0.0% | stable |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03..0.07 | 76.9% | 153.8% | 0.0% | stable |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.04..0.04 | 5.0% | 10.0% | 0.0% | stable |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.04..0.04 | 5.0% | 10.0% | 0.0% | stable |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows x 32K... | 0.31 | 0.29..0.35 | 9.5% | 18.9% | 6.1% | moderate |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows x 32K... | 0.31 | 0.29..0.35 | 9.5% | 18.9% | 6.1% | moderate |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged streams, 6... | 2.44 | 2.36..2.72 | 7.5% | 15.0% | 2.0% | stable |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged streams, 6... | 2.44 | 2.36..2.72 | 7.5% | 15.0% | 2.0% | stable |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 1.69 | 1.44..1.76 | 9.5% | 19.0% | 4.0% | moderate |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 1.69 | 1.44..1.76 | 9.5% | 19.0% | 4.0% | moderate |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.24 | 3.03..3.27 | 3.7% | 7.3% | 0.8% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.24 | 3.03..3.27 | 3.7% | 7.3% | 0.8% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.40 | 1.27..2.52 | 44.9% | 89.7% | 3.9% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.40 | 1.27..2.52 | 44.9% | 89.7% | 3.9% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.11 | 6.04..6.54 | 4.1% | 8.2% | 1.1% | stable |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.11 | 6.04..6.54 | 4.1% | 8.2% | 1.1% | stable |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.10 | 0.10..0.12 | 12.4% | 24.8% | 4.0% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.10 | 0.10..0.12 | 12.4% | 24.8% | 4.0% | moderate |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.05 | 0.05..0.05 | 1.9% | 3.8% | 1.9% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.05 | 0.05..0.05 | 1.9% | 3.8% | 1.9% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.41 | 0.41..0.42 | 1.5% | 2.9% | 1.2% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.41 | 0.41..0.42 | 1.5% | 2.9% | 1.2% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.79 | 3.75..3.93 | 2.4% | 4.8% | 0.6% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.79 | 3.75..3.93 | 2.4% | 4.8% | 0.6% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.55 | 0.38..0.56 | 16.0% | 31.9% | 0.7% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.55 | 0.38..0.56 | 16.0% | 31.9% | 0.7% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.06 | 0.06..0.07 | 3.1% | 6.3% | 1.6% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.06 | 0.06..0.07 | 3.1% | 6.3% | 1.6% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 4.88 | 4.50..4.99 | 5.0% | 9.9% | 2.3% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 4.88 | 4.50..4.99 | 5.0% | 9.9% | 2.3% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.41 | 0.41..0.42 | 1.6% | 3.2% | 0.5% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.41 | 0.41..0.42 | 1.6% | 3.2% | 0.5% | stable |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 0.84 | 0.84..0.88 | 2.4% | 4.9% | 0.1% | stable |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 0.84 | 0.84..0.88 | 2.4% | 4.9% | 0.1% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.04 | 0.04..0.05 | 4.5% | 9.1% | 2.3% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.04 | 0.04..0.05 | 4.5% | 9.1% | 2.3% | stable |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.07 | 0.07..0.08 | 8.0% | 16.0% | 5.3% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.07 | 0.07..0.08 | 8.0% | 16.0% | 5.3% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.84 | 0.62..0.88 | 16.0% | 31.9% | 5.2% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.84 | 0.62..0.88 | 16.0% | 31.9% | 5.2% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.56 | 1.55..1.71 | 5.1% | 10.1% | 0.4% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.56 | 1.55..1.71 | 5.1% | 10.1% | 0.4% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.17 | 0.16..0.17 | 2.1% | 4.1% | 0.6% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.17 | 0.16..0.17 | 2.1% | 4.1% | 0.6% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.10 | 0.09..0.10 | 2.5% | 5.1% | 0.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.10 | 0.09..0.10 | 2.5% | 5.1% | 0.0% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 12.60 | 12.58..12.86 | 1.1% | 2.2% | 0.1% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 12.60 | 12.58..12.86 | 1.1% | 2.2% | 0.1% | stable |


## Baseline Compatibility

This is an explicit comparison against `2026-08-09T20-36-47-exp266-headline-refresh.md`, but the baseline environment differs from the current run:
- hostname differs: current `macbookpro.lan` vs baseline `enterprise.local`

Treat the comparison as a reference check, not a gate.


## Comparison vs Previous Run

Previous: `2026-08-09T20-36-47-exp266-headline-refresh.md` (cross-repeat aggregate medians)

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 7.1% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 5.3% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 3.3% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.26 | 0.25 | -0.01 | ±12% / ±0.03 ms | 4.0% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.26 | 0.25 | -0.01 | ±12% / ±0.03 ms | 4.0% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.29 | 0.28 | -0.01 | ±10% / ±0.03 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.14 | 0.14 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.33 | 0.32 | -0.01 | ±10% / ±0.03 ms | 6.2% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.08 | 0.08 | +0.00 | ±10% / ±0.02 ms | 6.2% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.61 | 0.72 | +0.11 | ±10% / ±0.07 ms | 9.7% | stable | 🔴 Regression (+18%) |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.08 | 0.09 | +0.01 | ±11% / ±0.02 ms | 11.1% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 3.8% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±150% / ±0.02 ms | 150.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 109.26 | 108.69 | -0.56 | ±10% / ±10.93 ms | 0.5% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 237.79 | 234.99 | -2.80 | ±43% / ±102.56 ms | 43.1% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 217.93 | 217.12 | -0.81 | ±10% / ±21.79 ms | 0.6% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.08 | 13.60 | -0.49 | ±10% / ±1.41 ms | 0.4% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.08 | 13.60 | -0.49 | ±10% / ±1.41 ms | 0.4% | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 164941.00 | 166661.00 | +1720.00 | ±10% / ±16666.10 ms | 1.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01 | +0.00 | ±20% / ±0.02 ms | 20.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±30% / ±0.02 ms | 16.7% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.03 | +0.00 | ±30% / ±0.02 ms | 16.7% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | -0.00 | ±27% / ±0.02 ms | 9.1% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | -0.00 | ±27% / ±0.02 ms | 9.1% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 3.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.20 | 0.20 | -0.00 | ±10% / ±0.02 ms | 1.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.20 | 0.20 | -0.00 | ±10% / ±0.02 ms | 1.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 4.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 4.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.32 | 0.31 | -0.01 | ±10% / ±0.03 ms | 0.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.89 | 1.82 | -0.07 | ±10% / ±0.19 ms | 1.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.89 | 1.82 | -0.07 | ±10% / ±0.19 ms | 1.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 0.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.27 | 0.26 | -0.00 | ±10% / ±0.03 ms | 2.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.27 | 0.26 | -0.00 | ±10% / ±0.03 ms | 2.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 3.44 | 3.28 | -0.16 | ±10% / ±0.34 ms | 2.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 23.34 | 21.91 | -1.43 | ±15% / ±3.47 ms | 7.2% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 23.34 | 21.91 | -1.43 | ±15% / ±3.47 ms | 7.2% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.53 | 0.53 | -0.00 | ±10% / ±0.05 ms | 1.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 2.60 | 2.63 | +0.03 | ±10% / ±0.26 ms | 1.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 2.60 | 2.63 | +0.03 | ±10% / ±0.26 ms | 1.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.63 | 0.59 | -0.04 | ±10% / ±0.06 ms | 1.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.84 | 3.77 | -0.07 | ±10% / ±0.38 ms | 0.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.84 | 3.77 | -0.07 | ±10% / ±0.38 ms | 0.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.11 | 0.11 | -0.00 | ±10% / ±0.02 ms | 0.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.52 | 0.52 | -0.00 | ±10% / ±0.05 ms | 2.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.52 | 0.52 | -0.00 | ±10% / ±0.05 ms | 2.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 8.76 | 8.37 | -0.39 | ±10% / ±0.88 ms | 7.6% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 44.32 | 44.72 | +0.40 | ±10% / ±4.47 ms | 1.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 44.32 | 44.72 | +0.40 | ±10% / ±4.47 ms | 1.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.07 | 1.06 | -0.01 | ±10% / ±0.11 ms | 0.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 5.49 | 5.38 | -0.11 | ±10% / ±0.55 ms | 1.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 5.49 | 5.38 | -0.11 | ±10% / ±0.55 ms | 1.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.02 | 0.02 | -0.00 | ±14% / ±0.02 ms | 11.4% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | 2.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | 2.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±17% / ±0.02 ms | 16.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.02 | -0.00 | ±14% / ±0.02 ms | 6.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.02 | -0.00 | ±14% / ±0.02 ms | 6.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.16 | 0.16 | -0.00 | ±10% / ±0.02 ms | 0.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.98 | 0.94 | -0.04 | ±10% / ±0.10 ms | 1.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.98 | 0.94 | -0.04 | ±10% / ±0.10 ms | 1.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.14 | 0.14 | +0.00 | ±10% / ±0.02 ms | 1.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.14 | 0.14 | +0.00 | ±10% / ±0.02 ms | 1.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 1.78 | 1.72 | -0.06 | ±10% / ±0.18 ms | 1.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.55 | 10.04 | -0.51 | ±18% / ±1.95 ms | 13.9% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.55 | 10.04 | -0.51 | ±18% / ±1.95 ms | 13.9% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.27 | 0.27 | -0.00 | ±10% / ±0.03 ms | 0.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.33 | 1.28 | -0.05 | ±10% / ±0.13 ms | 3.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.33 | 1.28 | -0.05 | ±10% / ±0.13 ms | 3.3% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.09 | 0.09 | +0.00 | ±43% / ±0.04 ms | 43.1% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.02 | 0.02 | +0.00 | ±20% / ±0.02 ms | 19.6% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.25 | 0.25 | -0.01 | ±10% / ±0.03 ms | 0.4% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 0.8% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.24 | 0.24 | +0.00 | ±10% / ±0.02 ms | 1.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 0.8% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.38 | 0.37 | -0.01 | ±10% / ±0.04 ms | 0.8% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 0.8% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.81 | 0.78 | -0.03 | ±10% / ±0.08 ms | 0.3% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.23 | 0.22 | -0.01 | ±10% / ±0.02 ms | 0.7% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | -0.00 | ±63% / ±0.02 ms | 63.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02 | +0.00 | ±65% / ±0.02 ms | 64.7% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | +0.00 | ±27% / ±0.02 ms | 27.3% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.20 | +0.00 | ±10% / ±0.02 ms | 4.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.17 | 0.17 | +0.00 | ±10% / ±0.02 ms | 2.7% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 8.3% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.88 | 1.84 | -0.05 | ±10% / ±0.19 ms | 0.5% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.60 | 1.58 | -0.03 | ±10% / ±0.16 ms | 0.3% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.26 | 0.26 | +0.00 | ±10% / ±0.03 ms | 4.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.41 | 20.42 | +0.01 | ±10% / ±2.04 ms | 8.7% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 15.79 | 15.99 | +0.20 | ±10% / ±1.60 ms | 0.6% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 2.68 | 2.66 | -0.02 | ±10% / ±0.27 ms | 0.8% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / Large payload (~650KB) / resqlite s... | 0.24 | 0.27 | +0.03 | ±11% / ±0.03 ms | 8.3% | moderate | ⚪ Within noise |
| Select → JSON Bytes / Large payload (~650KB) / resqlite s... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | -0.00 | ±260% / ±0.03 ms | 260.0% | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.04 | 0.04 | +0.00 | ±147% / ±0.06 ms | 147.4% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±20% / ±0.02 ms | 20.0% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.31 | 0.30 | -0.01 | ±11% / ±0.03 ms | 11.1% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 6.6% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 3.44 | 3.24 | -0.20 | ±10% / ±0.34 ms | 2.3% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.51 | 0.52 | +0.01 | ±10% / ±0.05 ms | 1.8% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.19 | 0.18 | -0.01 | ±12% / ±0.02 ms | 11.7% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.19 | 0.18 | -0.01 | ±12% / ±0.02 ms | 11.7% | stable | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.48 | 0.47 | -0.01 | ±10% / ±0.05 ms | 3.5% | stable | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.48 | 0.47 | -0.01 | ±10% / ±0.05 ms | 3.5% | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | -0.00 | ±77% / ±0.02 ms | 76.9% | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03 | -0.00 | ±77% / ±0.02 ms | 76.9% | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.04 | -0.01 | ±10% / ±0.02 ms | 5.0% | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.05 | 0.04 | -0.01 | ±10% / ±0.02 ms | 5.0% | stable | ⚪ Within noise |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 ... | 2.65 | 0.31 | -2.33 | ±18% / ±0.48 ms | 9.5% | moderate | 🟢 Win (-88%) |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 ... | 2.65 | 0.31 | -2.33 | ±18% / ±0.48 ms | 9.5% | moderate | 🟢 Win (-88%) |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged ... | 2.76 | 2.44 | -0.31 | ±10% / ±0.28 ms | 7.5% | stable | 🟢 Win (-11%) |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged ... | 2.76 | 2.44 | -0.31 | ±10% / ±0.28 ms | 7.5% | stable | 🟢 Win (-11%) |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 1.55 | 1.69 | +0.14 | ±12% / ±0.20 ms | 9.5% | moderate | ⚪ Within noise |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 1.55 | 1.69 | +0.14 | ±12% / ±0.20 ms | 9.5% | moderate | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.18 | 3.24 | +0.07 | ±10% / ±0.32 ms | 3.7% | stable | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.18 | 3.24 | +0.07 | ±10% / ±0.32 ms | 3.7% | stable | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.58 | 1.40 | -0.18 | ±45% / ±0.71 ms | 44.9% | moderate | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.58 | 1.40 | -0.18 | ±45% / ±0.71 ms | 44.9% | moderate | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.27 | 6.11 | -0.16 | ±10% / ±0.63 ms | 4.1% | stable | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.27 | 6.11 | -0.16 | ±10% / ±0.63 ms | 4.1% | stable | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.19 | 0.10 | -0.09 | ±12% / ±0.02 ms | 12.4% | moderate | 🟢 Win (-46%) |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.19 | 0.10 | -0.09 | ±12% / ±0.02 ms | 12.4% | moderate | 🟢 Win (-46%) |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 1.9% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 1.9% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.41 | 0.41 | +0.00 | ±10% / ±0.04 ms | 1.5% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.41 | 0.41 | +0.00 | ±10% / ±0.04 ms | 1.5% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.93 | 3.79 | -0.13 | ±10% / ±0.39 ms | 2.4% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.93 | 3.79 | -0.13 | ±10% / ±0.39 ms | 2.4% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.52 | 0.55 | +0.03 | ±16% / ±0.09 ms | 16.0% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.52 | 0.55 | +0.03 | ±16% / ±0.09 ms | 16.0% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.06 | -0.00 | ±10% / ±0.02 ms | 3.1% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.06 | -0.00 | ±10% / ±0.02 ms | 3.1% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 5.01 | 4.88 | -0.13 | ±10% / ±0.50 ms | 5.0% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 5.01 | 4.88 | -0.13 | ±10% / ±0.50 ms | 5.0% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.40 | 0.41 | +0.01 | ±10% / ±0.04 ms | 1.6% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.40 | 0.41 | +0.01 | ±10% / ±0.04 ms | 1.6% | stable | ⚪ Within noise |
| Write Performance / Concurrent Single Inserts (100 concur... | 0.83 | 0.84 | +0.01 | ±10% / ±0.08 ms | 2.4% | stable | ⚪ Within noise |
| Write Performance / Concurrent Single Inserts (100 concur... | 0.83 | 0.84 | +0.01 | ±10% / ±0.08 ms | 2.4% | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.04 | -0.00 | ±10% / ±0.02 ms | 4.5% | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.04 | -0.00 | ±10% / ±0.02 ms | 4.5% | stable | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.07 | 0.07 | +0.01 | ±16% / ±0.02 ms | 8.0% | moderate | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.07 | 0.07 | +0.01 | ±16% / ±0.02 ms | 8.0% | moderate | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.88 | 0.84 | -0.04 | ±16% / ±0.14 ms | 16.0% | moderate | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.88 | 0.84 | -0.04 | ±16% / ±0.14 ms | 16.0% | moderate | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.54 | 1.56 | +0.02 | ±10% / ±0.16 ms | 5.1% | stable | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.54 | 1.56 | +0.02 | ±10% / ±0.16 ms | 5.1% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.17 | -0.01 | ±10% / ±0.02 ms | 2.1% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.17 | -0.01 | ±10% / ±0.02 ms | 2.1% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 2.5% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 2.5% | stable | ⚪ Within noise |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 13.18 | 12.60 | -0.58 | ±10% / ±1.32 ms | 1.1% | stable | ⚪ Within noise |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 13.18 | 12.60 | -0.58 | ±10% / ±1.32 ms | 1.1% | stable | ⚪ Within noise |

**Summary:** 6 wins, 1 regressions, 162 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


## Memory Comparison vs Previous Run

Previous run has no `## Memory` section — baseline unavailable. Current values recorded for next-run comparison.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 4193 | 4021 | -172 | ±100 | 🟢 Fewer re-emits (-172) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 3595 | 3694 | +99 | ±100 | ⚪ Within noise |

**Granularity summary:** 1 fewer-re-emit, 0 more-re-emit, 5 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


