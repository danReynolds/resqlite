# resqlite Benchmark Results

Generated: 2026-04-23T19:38:10.959176

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp097-one-pass-initial-stream-hash`
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
| resqlite select() | 0.012 | 0.014 | 0.001 | 0.001 |
| sqlite3 select() | 0.015 | 0.017 | 0.015 | 0.017 |
| sqlite_async select() | 0.030 | 0.032 | 0.001 | 0.001 |
| drift select() | 0.036 | 0.039 | 0.001 | 0.001 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.046 | 0.049 | 0.009 | 0.009 |
| sqlite3 select() | 0.109 | 0.112 | 0.109 | 0.112 |
| sqlite_async select() | 0.121 | 0.123 | 0.010 | 0.010 |
| drift select() | 0.177 | 0.186 | 0.010 | 0.010 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.375 | 0.380 | 0.088 | 0.090 |
| sqlite3 select() | 1.043 | 1.055 | 1.043 | 1.055 |
| sqlite_async select() | 0.983 | 1.015 | 0.090 | 0.095 |
| drift select() | 1.473 | 1.707 | 0.088 | 0.091 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.680 | 12.366 | 0.884 | 1.227 |
| sqlite3 select() | 14.008 | 17.679 | 14.008 | 17.679 |
| sqlite_async select() | 11.643 | 17.465 | 0.907 | 2.463 |
| drift select() | 20.823 | 26.809 | 0.909 | 1.339 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.026 | 0.028 | 0.015 | 0.016 |
| sqlite3 + jsonEncode | 0.029 | 0.031 | 0.029 | 0.031 |
| sqlite_async + jsonEncode | 0.043 | 0.044 | 0.016 | 0.016 |
| drift + jsonEncode | 0.051 | 0.053 | 0.016 | 0.017 |
| resqlite selectBytes() | 0.011 | 0.014 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.189 | 0.194 | 0.152 | 0.155 |
| sqlite3 + jsonEncode | 0.248 | 0.262 | 0.248 | 0.262 |
| sqlite_async + jsonEncode | 0.255 | 0.262 | 0.149 | 0.152 |
| drift + jsonEncode | 0.316 | 0.373 | 0.151 | 0.154 |
| resqlite selectBytes() | 0.045 | 0.047 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.758 | 3.792 | 1.449 | 2.594 |
| sqlite3 + jsonEncode | 2.567 | 4.504 | 2.567 | 4.504 |
| sqlite_async + jsonEncode | 2.560 | 5.396 | 1.567 | 2.934 |
| drift + jsonEncode | 3.141 | 5.626 | 1.572 | 2.245 |
| resqlite selectBytes() | 0.369 | 0.398 | 0.000 | 0.001 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 21.885 | 24.785 | 15.069 | 17.135 |
| sqlite3 + jsonEncode | 28.913 | 32.033 | 28.913 | 32.033 |
| sqlite_async + jsonEncode | 29.677 | 34.388 | 15.595 | 17.832 |
| drift + jsonEncode | 36.810 | 42.584 | 15.140 | 16.576 |
| resqlite selectBytes() | 3.876 | 5.882 | 0.003 | 0.007 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.099 | 0.103 | 0.036 | 0.037 |
| sqlite3 | 0.332 | 0.616 | 0.332 | 0.616 |
| sqlite_async | 0.372 | 0.380 | 0.044 | 0.045 |
| drift | 0.652 | 1.920 | 0.047 | 0.062 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.918 | 0.985 | 0.279 | 0.301 |
| sqlite3 | 3.030 | 3.483 | 3.030 | 3.483 |
| sqlite_async | 2.718 | 3.115 | 0.312 | 0.326 |
| drift | 4.813 | 5.628 | 0.323 | 0.361 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.514 | 1.067 | 0.101 | 0.107 |
| sqlite3 | 1.347 | 1.422 | 1.347 | 1.422 |
| sqlite_async | 1.285 | 1.366 | 0.113 | 0.118 |
| drift | 1.836 | 2.120 | 0.111 | 0.113 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.279 | 0.285 | 0.095 | 0.100 |
| sqlite3 | 0.915 | 0.936 | 0.915 | 0.936 |
| sqlite_async | 0.870 | 0.900 | 0.111 | 0.113 |
| drift | 1.383 | 1.412 | 0.110 | 0.111 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.287 | 0.294 | 0.097 | 0.101 |
| sqlite3 | 0.880 | 0.898 | 0.880 | 0.898 |
| sqlite_async | 0.870 | 0.884 | 0.111 | 0.113 |
| drift | 1.381 | 1.396 | 0.110 | 0.112 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.011 | 0.012 | 0.001 | 0.001 |
| sqlite3 | 0.015 | 0.017 | 0.015 | 0.017 |
| sqlite_async | 0.028 | 0.032 | 0.001 | 0.001 |
| drift | 0.035 | 0.037 | 0.001 | 0.001 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.026 | 0.027 | 0.004 | 0.004 |
| sqlite3 | 0.055 | 0.056 | 0.055 | 0.056 |
| sqlite_async | 0.069 | 0.074 | 0.005 | 0.005 |
| drift | 0.098 | 0.102 | 0.005 | 0.005 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.045 | 0.049 | 0.008 | 0.009 |
| sqlite3 | 0.106 | 0.109 | 0.106 | 0.109 |
| sqlite_async | 0.118 | 0.121 | 0.010 | 0.010 |
| drift | 0.174 | 0.178 | 0.010 | 0.010 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.184 | 0.188 | 0.042 | 0.044 |
| sqlite3 | 0.509 | 0.524 | 0.509 | 0.524 |
| sqlite_async | 0.488 | 0.495 | 0.045 | 0.045 |
| drift | 0.739 | 0.762 | 0.044 | 0.045 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.366 | 0.377 | 0.085 | 0.088 |
| sqlite3 | 1.008 | 1.026 | 1.008 | 1.026 |
| sqlite_async | 0.955 | 0.971 | 0.089 | 0.091 |
| drift | 1.474 | 1.699 | 0.088 | 0.090 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.746 | 0.766 | 0.168 | 0.177 |
| sqlite3 | 2.022 | 2.491 | 2.022 | 2.491 |
| sqlite_async | 1.908 | 2.316 | 0.177 | 0.181 |
| drift | 3.181 | 4.740 | 0.188 | 0.216 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.213 | 5.184 | 0.441 | 0.563 |
| sqlite3 | 5.465 | 7.269 | 5.465 | 7.269 |
| sqlite_async | 5.582 | 6.389 | 0.478 | 0.498 |
| drift | 8.156 | 9.209 | 0.448 | 0.481 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.188 | 10.862 | 0.835 | 1.064 |
| sqlite3 | 13.066 | 15.569 | 13.066 | 15.569 |
| sqlite_async | 11.515 | 14.660 | 0.901 | 1.556 |
| drift | 24.494 | 32.323 | 0.977 | 2.637 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 10.439 | 16.213 | 1.653 | 1.997 |
| sqlite3 | 29.058 | 37.820 | 29.058 | 37.820 |
| sqlite_async | 32.497 | 41.899 | 1.818 | 5.487 |
| drift | 45.208 | 84.121 | 1.901 | 7.071 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.027 | 0.028 | 0.027 | 0.028 |
| sqlite3 + jsonEncode | 0.031 | 0.032 | 0.031 | 0.032 |
| sqlite_async + jsonEncode | 0.044 | 0.045 | 0.044 | 0.045 |
| drift + jsonEncode | 0.052 | 0.054 | 0.052 | 0.054 |
| resqlite selectBytes() | 0.011 | 0.012 | 0.011 | 0.012 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.104 | 0.107 | 0.104 | 0.107 |
| sqlite3 + jsonEncode | 0.133 | 0.146 | 0.133 | 0.146 |
| sqlite_async + jsonEncode | 0.147 | 0.150 | 0.147 | 0.150 |
| drift + jsonEncode | 0.172 | 0.180 | 0.172 | 0.180 |
| resqlite selectBytes() | 0.025 | 0.029 | 0.025 | 0.029 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.191 | 0.211 | 0.191 | 0.211 |
| sqlite3 + jsonEncode | 0.247 | 0.250 | 0.247 | 0.250 |
| sqlite_async + jsonEncode | 0.259 | 0.280 | 0.259 | 0.280 |
| drift + jsonEncode | 0.312 | 0.325 | 0.312 | 0.325 |
| resqlite selectBytes() | 0.043 | 0.044 | 0.043 | 0.044 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.881 | 1.246 | 0.881 | 1.246 |
| sqlite3 + jsonEncode | 1.216 | 2.622 | 1.216 | 2.622 |
| sqlite_async + jsonEncode | 1.189 | 1.632 | 1.189 | 1.632 |
| drift + jsonEncode | 1.434 | 2.962 | 1.434 | 2.962 |
| resqlite selectBytes() | 0.180 | 0.183 | 0.180 | 0.183 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.714 | 3.168 | 1.714 | 3.168 |
| sqlite3 + jsonEncode | 2.371 | 3.739 | 2.371 | 3.739 |
| sqlite_async + jsonEncode | 2.330 | 4.985 | 2.330 | 4.985 |
| drift + jsonEncode | 2.830 | 5.245 | 2.830 | 5.245 |
| resqlite selectBytes() | 0.348 | 0.358 | 0.348 | 0.358 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.621 | 6.853 | 3.621 | 6.853 |
| sqlite3 + jsonEncode | 5.243 | 9.069 | 5.243 | 9.069 |
| sqlite_async + jsonEncode | 5.853 | 18.693 | 5.853 | 18.693 |
| drift + jsonEncode | 6.476 | 12.379 | 6.476 | 12.379 |
| resqlite selectBytes() | 0.861 | 1.647 | 0.861 | 1.647 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 9.741 | 13.428 | 9.741 | 13.428 |
| sqlite3 + jsonEncode | 13.626 | 15.749 | 13.626 | 15.749 |
| sqlite_async + jsonEncode | 13.214 | 18.803 | 13.214 | 18.803 |
| drift + jsonEncode | 17.567 | 33.128 | 17.567 | 33.128 |
| resqlite selectBytes() | 1.994 | 3.940 | 1.994 | 3.940 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 21.965 | 23.562 | 21.965 | 23.562 |
| sqlite3 + jsonEncode | 29.983 | 52.611 | 29.983 | 52.611 |
| sqlite_async + jsonEncode | 28.330 | 31.850 | 28.330 | 31.850 |
| drift + jsonEncode | 37.999 | 54.117 | 37.999 | 54.117 |
| resqlite selectBytes() | 3.684 | 5.660 | 3.684 | 5.660 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 44.758 | 51.990 | 44.758 | 51.990 |
| sqlite3 + jsonEncode | 60.125 | 73.881 | 60.125 | 73.881 |
| sqlite_async + jsonEncode | 66.714 | 79.311 | 66.714 | 79.311 |
| drift + jsonEncode | 78.219 | 96.706 | 78.219 | 96.706 |
| resqlite selectBytes() | 8.076 | 11.539 | 8.076 | 11.539 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.29 | 0.30 | 0.29 |
| sqlite_async | 0.95 | 1.09 | 0.95 |
| drift | 1.48 | 1.80 | 1.48 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.31 | 0.33 | 0.16 |
| sqlite_async | 1.36 | 1.58 | 0.68 |
| drift | 2.80 | 3.32 | 1.40 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.81 | 0.98 | 0.20 |
| sqlite_async | 2.25 | 3.09 | 0.56 |
| drift | 5.22 | 5.88 | 1.31 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.65 | 1.05 | 0.08 |
| sqlite_async | 4.43 | 4.61 | 0.55 |
| drift | 9.70 | 10.28 | 1.21 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 129410 |
| resqlite per query | 0.008 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 129410 | 110461..145106 | 13.4 | 37.8 |
| sqlite3 | 190988 | 185557..202959 | 4.6 | 10.7 |
| sqlite_async | 52903 | 51995..53420 | 1.3 | 5.3 |
| drift | 48048 | 48010..48186 | 0.2 | 0.9 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.189 | 15.547 | 14.189 | 15.547 |
| sqlite_async | 34.943 | 37.205 | 34.943 | 37.205 |
| drift | 52.745 | 54.552 | 52.745 | 54.552 |
| sqlite3 (no cache) | 22.532 | 24.273 | 22.532 | 24.273 |
| sqlite3 (cached stmt) | 22.242 | 23.872 | 22.242 | 23.872 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.837 | 2.618 | 1.837 | 2.618 |
| sqlite3 execute() | 1.072 | 4.250 | 1.072 | 4.250 |
| sqlite_async execute() | 2.729 | 3.564 | 2.729 | 3.564 |
| drift execute() | 3.064 | 4.007 | 3.064 | 4.007 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.056 | 0.057 | 0.056 | 0.057 |
| sqlite3 executeBatch() | 0.050 | 0.053 | 0.050 | 0.053 |
| sqlite_async executeBatch() | 0.094 | 0.104 | 0.094 | 0.104 |
| drift executeBatch() | 0.112 | 0.117 | 0.112 | 0.117 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.456 | 0.536 | 0.456 | 0.536 |
| sqlite3 executeBatch() | 0.457 | 0.498 | 0.457 | 0.498 |
| sqlite_async executeBatch() | 0.561 | 0.669 | 0.561 | 0.669 |
| drift executeBatch() | 0.701 | 0.788 | 0.701 | 0.788 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.666 | 5.435 | 4.666 | 5.435 |
| sqlite3 executeBatch() | 4.284 | 4.557 | 4.284 | 4.557 |
| sqlite_async executeBatch() | 4.664 | 4.873 | 4.664 | 4.873 |
| drift executeBatch() | 5.877 | 8.239 | 5.877 | 8.239 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.085 | 0.119 | 0.085 | 0.119 |
| sqlite_async writeTransaction() | 0.094 | 0.207 | 0.094 | 0.207 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.069 | 0.072 | 0.069 | 0.072 |
| resqlite tx.execute() loop | 0.614 | 0.729 | 0.614 | 0.729 |
| sqlite_async tx.execute() loop | 0.888 | 0.959 | 0.888 | 0.959 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.427 | 0.465 | 0.427 | 0.465 |
| resqlite tx.execute() loop | 5.303 | 6.159 | 5.303 | 6.159 |
| sqlite_async tx.execute() loop | 8.603 | 13.548 | 8.603 | 13.548 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.101 | 0.112 | 0.101 | 0.112 |
| sqlite_async tx.getAll() | 0.196 | 0.208 | 0.196 | 0.208 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.180 | 0.186 | 0.180 | 0.186 |
| sqlite_async tx.getAll() | 0.347 | 0.360 | 0.347 | 0.360 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.025 | 0.029 | 0.025 | 0.029 |
| sqlite_async watch() | 0.106 | 0.130 | 0.106 | 0.130 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.045 | 0.062 | 0.045 | 0.062 |
| sqlite_async | 0.051 | 0.064 | 0.051 | 0.064 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.187 | 0.222 | 0.187 | 0.222 |
| sqlite_async | 0.465 | 1.960 | 0.465 | 1.960 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.203 | 0.260 | 0.203 | 0.260 |
| sqlite_async | 0.238 | 0.269 | 0.238 | 0.269 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.500 | 1.500 | 1.500 | 1.500 |
| sqlite_async | 9.073 | 9.073 | 9.073 | 9.073 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.326 | 3.933 | 3.326 | 3.933 |
| sqlite_async | 5.872 | 7.077 | 5.872 | 7.077 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.534 | 0.772 | 0.534 | 0.772 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 6.085 | 6.586 | 6.085 | 6.586 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. On resqlite's main branch this ratio is driven toward 0 by experiment 075 (C-side result-hash short-circuit), not by writer-side column-tracking (exp 052 is not implemented). The two mechanisms are indistinguishable on this read-side benchmark.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 76.1 | 0.000 |
| sqlite_async | 3877 | 931.7 | 0.971 |
| drift | 5000 | 1035.5 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 20 | 82.5 | 0.000 |
| sqlite_async | 3992 | 956.8 | 0.971 |
| drift | 5000 | 1004.9 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 225.54 | 226.91 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 439.27 | 444.23 | 0.00 | 0.00 | 1186 | 3 |
| drift stream() | 550.91 | 574.50 | 0.00 | 0.00 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.018 | 0.029 | 0.000 | 0.000 |
| sqlite3 | 0.018 | 0.040 | 0.018 | 0.040 |
| sqlite_async | 0.036 | 0.046 | 0.000 | 0.000 |
| drift | 0.039 | 0.064 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.014 | 0.019 | 0.000 | 0.000 |
| sqlite3 | 0.012 | 0.022 | 0.012 | 0.022 |
| sqlite_async | 0.028 | 0.033 | 0.000 | 0.000 |
| drift | 0.031 | 0.050 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.023 | 0.032 | 0.000 | 0.000 |
| sqlite3 | 0.030 | 0.034 | 0.030 | 0.034 |
| sqlite_async | 0.053 | 0.062 | 0.000 | 0.000 |
| drift | 0.053 | 0.070 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.008 | 0.015 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.020 | 0.023 | 0.000 | 0.000 |
| drift | 0.020 | 0.035 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.041 | 0.045 | 0.001 | 0.001 |
| sqlite3 | 0.062 | 0.068 | 0.062 | 0.068 |
| sqlite_async | 0.076 | 0.079 | 0.001 | 0.001 |
| drift | 0.092 | 0.117 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 108.938 | 111.106 | 0.000 | 0.000 | 0 |
| sqlite_async | 217.093 | 219.851 | 0.000 | 0.002 | 37 |
| drift | 232.467 | 232.724 | 0.002 | 0.002 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 240.69 | 240.69 | 0.00 | 0.00 | 13.58 | 227.88 | 0 |
| sqlite_async | 479.88 | 479.88 | 0.00 | 0.00 | 24.73 | 455.15 | 1190 |
| drift | 1823.32 | 1823.32 | 0.84 | 0.84 | 19.58 | 1803.73 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 4.52 | 13.63 | 1.09..11.92 | ±5.41 |
| sqlite3 select() | 3.39 | 10.22 | 1.78..9.06 | ±3.64 |
| sqlite_async select() | 1.00 | 1.50 | 1.00..1.00 | ±0.00 |
| drift select() | 14.34 | 69.97 | 0.00..51.11 | ±25.55 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 8.02 | 0.00..4.00 | ±2.00 |
| resqlite + jsonEncode | 3.69 | 69.05 | 0.00..11.09 | ±5.55 |
| sqlite3 + jsonEncode | 0.03 | 39.02 | 0.00..7.00 | ±3.50 |
| sqlite_async + jsonEncode | 0.00 | 42.84 | 0.00..3.03 | ±1.52 |
| drift + jsonEncode | 2.97 | 31.95 | 0.00..13.64 | ±6.82 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.00 | 11.66 | 0.00..0.31 | ±0.16 |
| sqlite3 executeBatch() | 0.00 | 0.02 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 0.50 | 0.00..0.13 | ±0.06 |
| drift batch() | 0.02 | 2.00 | 0.00..0.50 | ±0.25 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.08 | 0.00..0.06 | ±0.03 |
| sqlite_async watch() | 0.00 | 0.52 | 0.00..0.02 | ±0.01 |

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
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.02 | 0.02..0.03 | 20.8% | 20.8% | 4.2% | moderate |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 25.0% | 25.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02..0.03 | 52.6% | 52.6% | 5.3% | moderate |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.01..0.02 | 40.0% | 40.0% | 6.7% | moderate |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.29 | 0.29..0.29 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.29 | 0.29..0.29 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.31 | 0.30..0.32 | 6.5% | 6.5% | 3.2% | moderate |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.16 | 0.15..0.16 | 6.3% | 6.3% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.36 | 0.31..0.81 | 138.9% | 138.9% | 13.9% | noisy |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.09 | 0.08..0.20 | 133.3% | 133.3% | 11.1% | noisy |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.65 | 0.64..0.76 | 18.5% | 18.5% | 1.5% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.08 | 0.08..0.10 | 25.0% | 25.0% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.04 | 7.5% | 7.5% | 2.5% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 300.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 109.17 | 108.94..109.97 | 0.9% | 0.9% | 0.2% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 242.24 | 240.69..242.33 | 0.7% | 0.7% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 224.23 | 220.29..225.54 | 2.3% | 2.3% | 0.6% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 14.19 | 14.03..14.53 | 3.5% | 3.5% | 1.1% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 14.19 | 14.03..14.53 | 3.5% | 3.5% | 1.1% | stable |
| Point Query Throughput / resqlite qps | 148505.00 | 129410.00..149560.00 | 13.6% | 13.6% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.02 | 0.01..0.02 | 31.3% | 31.3% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.04 | 32.1% | 32.1% | 3.6% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.04 | 32.1% | 32.1% | 3.6% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 100.0% | 100.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 38.5% | 38.5% | 15.4% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.02 | 38.5% | 38.5% | 15.4% | noisy |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.04..0.05 | 11.8% | 11.8% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.19 | 0.19..0.20 | 3.6% | 3.6% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.19 | 0.19..0.20 | 3.6% | 3.6% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 11.1% | 11.1% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.05 | 11.1% | 11.1% | 4.4% | moderate |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.04 | 0.04..0.05 | 11.1% | 11.1% | 4.4% | moderate |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.37 | 0.37..0.38 | 3.6% | 3.6% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.85 | 1.71..1.86 | 8.0% | 8.0% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.85 | 1.71..1.86 | 8.0% | 8.0% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09..0.09 | 3.5% | 3.5% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.36 | 0.35..0.36 | 3.6% | 3.6% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.36 | 0.35..0.36 | 3.6% | 3.6% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.48 | 4.19..4.81 | 14.0% | 14.0% | 6.5% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 21.43 | 21.20..21.96 | 3.6% | 3.6% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 21.43 | 21.20..21.96 | 3.6% | 3.6% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.86 | 0.83..0.87 | 4.2% | 4.2% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 3.68 | 3.62..4.41 | 21.6% | 21.6% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 3.68 | 3.62..4.41 | 21.6% | 21.6% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.75 | 0.74..0.85 | 14.6% | 14.6% | 0.1% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.65 | 3.62..3.65 | 0.9% | 0.9% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.65 | 3.62..3.65 | 0.9% | 0.9% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.17 | 0.17..0.18 | 7.1% | 7.1% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.79 | 0.75..0.86 | 13.9% | 13.9% | 5.1% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.79 | 0.75..0.86 | 13.9% | 13.9% | 5.1% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 11.41 | 10.44..13.50 | 26.8% | 26.8% | 8.5% | noisy |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 43.47 | 43.16..44.76 | 3.7% | 3.7% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 43.47 | 43.16..44.76 | 3.7% | 3.7% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.76 | 1.65..1.78 | 7.0% | 7.0% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 7.84 | 7.74..8.08 | 4.2% | 4.2% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 7.84 | 7.74..8.08 | 4.2% | 4.2% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03..0.03 | 20.0% | 20.0% | 6.7% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.10..0.11 | 4.6% | 4.6% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.11 | 0.10..0.11 | 4.6% | 4.6% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.03..0.03 | 15.4% | 15.4% | 3.8% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.03..0.03 | 15.4% | 15.4% | 3.8% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.19 | 0.18..0.20 | 7.2% | 7.2% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.89 | 0.88..0.89 | 0.8% | 0.8% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.89 | 0.88..0.89 | 0.8% | 0.8% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04..0.04 | 4.5% | 4.5% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.19 | 0.18..0.20 | 8.4% | 8.4% | 3.2% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.19 | 0.18..0.20 | 8.4% | 8.4% | 3.2% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.07 | 2.04..2.21 | 8.3% | 8.3% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 9.74 | 9.62..10.60 | 10.0% | 10.0% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 9.74 | 9.62..10.60 | 10.0% | 10.0% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.42 | 0.42..0.44 | 5.7% | 5.7% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 1.92 | 1.78..1.99 | 11.0% | 11.0% | 3.9% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 1.92 | 1.78..1.99 | 11.0% | 11.0% | 3.9% | moderate |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.10 | 0.10..0.10 | 6.1% | 6.1% | 2.0% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.04 | 0.03..0.04 | 22.9% | 22.9% | 2.9% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.29 | 0.29..0.31 | 7.2% | 7.2% | 2.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.10 | 0.10..0.10 | 6.1% | 6.1% | 2.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.28 | 0.28..0.29 | 5.3% | 5.3% | 1.8% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.10 | 0.10..0.10 | 6.3% | 6.3% | 0.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.53 | 0.51..0.57 | 10.1% | 10.1% | 3.6% | moderate |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.10 | 0.10..0.10 | 2.9% | 2.9% | 1.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.87 | 0.86..0.92 | 6.3% | 6.3% | 0.6% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.27 | 0.26..0.28 | 6.0% | 6.0% | 1.1% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.13 | 407.7% | 407.7% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.01 | 0.01..0.10 | 600.0% | 600.0% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 118.2% | 118.2% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.19 | 0.19..0.25 | 34.0% | 34.0% | 1.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.15 | 0.15..0.19 | 24.7% | 24.7% | 1.3% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.06 | 28.9% | 28.9% | 4.4% | moderate |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.76 | 1.72..1.87 | 8.8% | 8.8% | 2.4% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.45 | 1.43..1.54 | 7.2% | 7.2% | 1.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.35 | 0.35..0.37 | 4.5% | 4.5% | 0.3% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 21.89 | 20.55..23.14 | 11.8% | 11.8% | 5.7% | moderate |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 15.05 | 14.78..15.07 | 1.9% | 1.9% | 0.1% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.88 | 3.64..3.94 | 7.8% | 7.8% | 1.7% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.08 | 538.5% | 538.5% | 7.7% | moderate |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 1000.0% | 1000.0% | 50.0% | noisy |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.04..0.07 | 50.0% | 50.0% | 2.2% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 11.1% | 11.1% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.38 | 0.36..0.43 | 18.7% | 18.7% | 3.5% | moderate |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.08..0.09 | 12.9% | 12.9% | 3.5% | moderate |
| Select → Maps / 10000 rows / resqlite select() | 4.59 | 4.29..4.68 | 8.5% | 8.5% | 1.9% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.83 | 0.71..0.88 | 20.8% | 20.8% | 6.4% | moderate |
| Streaming / Fan-out (10 streams) / resqlite | 0.21 | 0.20..0.22 | 9.0% | 9.0% | 3.8% | moderate |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.21 | 0.20..0.22 | 9.0% | 9.0% | 3.8% | moderate |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.51 | 0.51..0.53 | 5.1% | 5.1% | 0.4% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.51 | 0.51..0.53 | 5.1% | 5.1% | 0.4% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03..0.08 | 212.0% | 212.0% | 0.0% | stable |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03..0.08 | 212.0% | 212.0% | 0.0% | stable |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.04..0.08 | 67.4% | 67.4% | 2.2% | stable |
| Streaming / Invalidation Latency / resqlite [main] | 0.05 | 0.04..0.08 | 67.4% | 67.4% | 2.2% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.40 | 3.33..3.73 | 11.7% | 11.7% | 2.3% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.40 | 3.33..3.73 | 11.7% | 11.7% | 2.3% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.53 | 1.50..2.31 | 52.7% | 52.7% | 2.3% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.53 | 1.50..2.31 | 52.7% | 52.7% | 2.3% | stable |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.06 | 5.68..6.08 | 6.6% | 6.6% | 0.4% | stable |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.06 | 5.68..6.08 | 6.6% | 6.6% | 0.4% | stable |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.20 | 0.19..0.41 | 108.8% | 108.8% | 8.8% | noisy |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.20 | 0.19..0.41 | 108.8% | 108.8% | 8.8% | noisy |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.05 | 0.05..0.06 | 5.6% | 5.6% | 1.9% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.05 | 0.05..0.06 | 5.6% | 5.6% | 1.9% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.43 | 0.42..0.46 | 7.7% | 7.7% | 1.6% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.43 | 0.42..0.46 | 7.7% | 7.7% | 1.6% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.23 | 4.20..4.67 | 11.0% | 11.0% | 0.8% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.23 | 4.20..4.67 | 11.0% | 11.0% | 0.8% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.60 | 0.57..0.61 | 7.9% | 7.9% | 1.7% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.60 | 0.57..0.61 | 7.9% | 7.9% | 1.7% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07..0.09 | 23.6% | 23.6% | 4.2% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07..0.09 | 23.6% | 23.6% | 4.2% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.37 | 5.30..5.46 | 2.9% | 2.9% | 1.2% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.37 | 5.30..5.46 | 2.9% | 2.9% | 1.2% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.50 | 0.43..0.51 | 17.1% | 17.1% | 2.0% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.50 | 0.43..0.51 | 17.1% | 17.1% | 2.0% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.07 | 0.05..0.09 | 45.3% | 45.3% | 13.3% | noisy |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.07 | 0.05..0.09 | 45.3% | 45.3% | 13.3% | noisy |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.84 | 1.59..1.96 | 20.4% | 20.4% | 6.8% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.84 | 1.59..1.96 | 20.4% | 20.4% | 6.8% | moderate |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.18..0.19 | 3.8% | 3.8% | 1.1% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.18..0.19 | 3.8% | 3.8% | 1.1% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.10 | 0.10..0.10 | 4.0% | 4.0% | 0.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.10 | 0.10..0.10 | 4.0% | 4.0% | 0.0% | stable |


## Comparison vs Previous Run

Previous: `2026-04-23T18-44-25-internal-perf-review.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.03 | 0.02 | -0.01 | ±21% / ±0.02 ms | 20.8% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | -0.00 | ±25% / ±0.02 ms | 25.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.03 | 0.02 | -0.01 | ±53% / ±0.02 ms | 52.6% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.01 | -0.01 | ±40% / ±0.02 ms | 40.0% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.29 | -0.01 | ±10% / ±0.03 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.29 | -0.01 | ±10% / ±0.03 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.30 | 0.31 | +0.01 | ±10% / ±0.03 ms | 6.5% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.15 | 0.16 | +0.01 | ±10% / ±0.02 ms | 6.3% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.36 | 0.36 | +0.00 | ±139% / ±0.50 ms | 138.9% | noisy | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.09 | 0.09 | +0.00 | ±133% / ±0.12 ms | 133.3% | noisy | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.66 | 0.65 | -0.01 | ±18% / ±0.12 ms | 18.5% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.08 | 0.08 | +0.00 | ±25% / ±0.02 ms | 25.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 7.5% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±300% / ±0.02 ms | 300.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 110.22 | 109.17 | -1.05 | ±10% / ±11.02 ms | 0.9% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 238.40 | 242.24 | +3.84 | ±10% / ±24.22 ms | 0.7% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 220.53 | 224.23 | +3.70 | ±10% / ±22.42 ms | 2.3% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.11 | 14.19 | +0.08 | ±10% / ±1.42 ms | 3.5% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.11 | 14.19 | +0.08 | ±10% / ±1.42 ms | 3.5% | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 143726.00 | 148505.00 | +4779.00 | ±14% / ±20150.00 ms | 13.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.02 | +0.01 | ±31% / ±0.02 ms | 31.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±32% / ±0.02 ms | 32.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.03 | +0.00 | ±32% / ±0.02 ms | 32.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±100% / ±0.02 ms | 100.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±46% / ±0.02 ms | 38.5% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±46% / ±0.02 ms | 38.5% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05 | +0.00 | ±12% / ±0.02 ms | 11.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.19 | +0.00 | ±10% / ±0.02 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.19 | +0.00 | ±10% / ±0.02 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±11% / ±0.02 ms | 11.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±13% / ±0.02 ms | 11.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±13% / ±0.02 ms | 11.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.37 | 0.37 | -0.01 | ±10% / ±0.04 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.88 | 1.85 | -0.03 | ±10% / ±0.19 ms | 8.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.88 | 1.85 | -0.03 | ±10% / ±0.19 ms | 8.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 3.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.36 | +0.01 | ±10% / ±0.04 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.36 | +0.01 | ±10% / ±0.04 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.31 | 4.48 | +0.17 | ±20% / ±0.88 ms | 14.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 20.73 | 21.43 | +0.69 | ±10% / ±2.14 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 20.73 | 21.43 | +0.69 | ±10% / ±2.14 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.85 | 0.86 | +0.01 | ±10% / ±0.09 ms | 4.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.58 | 3.68 | +0.10 | ±22% / ±0.80 ms | 21.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.58 | 3.68 | +0.10 | ±22% / ±0.80 ms | 21.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.76 | 0.75 | -0.01 | ±15% / ±0.11 ms | 14.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.85 | 3.65 | -0.19 | ±10% / ±0.38 ms | 0.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.85 | 3.65 | -0.19 | ±10% / ±0.38 ms | 0.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.17 | 0.17 | -0.00 | ±10% / ±0.02 ms | 7.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.74 | 0.79 | +0.05 | ±15% / ±0.12 ms | 13.9% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.74 | 0.79 | +0.05 | ±15% / ±0.12 ms | 13.9% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.43 | 11.41 | +0.98 | ±27% / ±3.06 ms | 26.8% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 43.46 | 43.47 | +0.01 | ±10% / ±4.35 ms | 3.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 43.46 | 43.47 | +0.01 | ±10% / ±4.35 ms | 3.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.71 | 1.76 | +0.05 | ±10% / ±0.18 ms | 7.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.34 | 7.84 | -0.50 | ±10% / ±0.83 ms | 4.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.34 | 7.84 | -0.50 | ±10% / ±0.83 ms | 4.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03 | +0.00 | ±20% / ±0.02 ms | 20.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.11 | +0.01 | ±10% / ±0.02 ms | 4.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.10 | 0.11 | +0.01 | ±10% / ±0.02 ms | 4.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.03 | +0.00 | ±15% / ±0.02 ms | 15.4% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.03 | +0.00 | ±15% / ±0.02 ms | 15.4% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.19 | 0.19 | +0.01 | ±10% / ±0.02 ms | 7.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.89 | 0.89 | +0.00 | ±10% / ±0.09 ms | 0.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.89 | 0.89 | +0.00 | ±10% / ±0.09 ms | 0.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 4.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.19 | 0.19 | -0.00 | ±10% / ±0.02 ms | 8.4% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.19 | 0.19 | -0.00 | ±10% / ±0.02 ms | 8.4% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.26 | 2.07 | -0.18 | ±10% / ±0.23 ms | 8.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 9.77 | 9.74 | -0.03 | ±10% / ±0.98 ms | 10.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 9.77 | 9.74 | -0.03 | ±10% / ±0.98 ms | 10.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.45 | 0.42 | -0.03 | ±10% / ±0.04 ms | 5.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.83 | 1.92 | +0.09 | ±12% / ±0.22 ms | 11.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.83 | 1.92 | +0.09 | ±12% / ±0.22 ms | 11.0% | moderate | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 6.1% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.04 | 0.04 | +0.00 | ±23% / ±0.02 ms | 22.9% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.31 | 0.29 | -0.02 | ±10% / ±0.03 ms | 7.2% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 6.1% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.30 | 0.28 | -0.01 | ±10% / ±0.03 ms | 5.3% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 6.3% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.52 | 0.53 | +0.01 | ±11% / ±0.06 ms | 10.1% | moderate | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 2.9% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.89 | 0.87 | -0.03 | ±10% / ±0.09 ms | 6.3% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.27 | 0.27 | -0.00 | ±10% / ±0.03 ms | 6.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | -0.00 | ±408% / ±0.11 ms | 407.7% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.01 | -0.00 | ±600% / ±0.10 ms | 600.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | +0.00 | ±118% / ±0.02 ms | 118.2% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.19 | 0.19 | -0.00 | ±34% / ±0.07 ms | 34.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.15 | 0.15 | +0.00 | ±25% / ±0.04 ms | 24.7% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.04 | -0.00 | ±29% / ±0.02 ms | 28.9% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.80 | 1.76 | -0.04 | ±10% / ±0.18 ms | 8.8% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.49 | 1.45 | -0.04 | ±10% / ±0.15 ms | 7.2% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.37 | 0.35 | -0.01 | ±10% / ±0.04 ms | 4.5% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.82 | 21.89 | +1.07 | ±17% / ±3.76 ms | 11.8% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 15.01 | 15.05 | +0.04 | ±10% / ±1.51 ms | 1.9% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.77 | 3.88 | +0.11 | ±10% / ±0.39 ms | 7.8% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | +0.00 | ±538% / ±0.07 ms | 538.5% | moderate | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±1000% / ±0.02 ms | 1000.0% | noisy | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.04 | 0.05 | +0.00 | ±50% / ±0.02 ms | 50.0% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±11% / ±0.02 ms | 11.1% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.37 | 0.38 | +0.01 | ±19% / ±0.07 ms | 18.7% | moderate | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.09 | +0.00 | ±13% / ±0.02 ms | 12.9% | moderate | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 4.43 | 4.59 | +0.17 | ±10% / ±0.46 ms | 8.5% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.86 | 0.83 | -0.03 | ±21% / ±0.18 ms | 20.8% | moderate | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.24 | 0.21 | -0.03 | ±11% / ±0.03 ms | 9.0% | moderate | 🟢 Win (-14%) |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.24 | 0.21 | -0.03 | ±11% / ±0.03 ms | 9.0% | moderate | 🟢 Win (-14%) |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.57 | 0.51 | -0.06 | ±10% / ±0.06 ms | 5.1% | stable | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.57 | 0.51 | -0.06 | ±10% / ±0.06 ms | 5.1% | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | -0.01 | ±212% / ±0.07 ms | 212.0% | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03 | -0.01 | ±212% / ±0.07 ms | 212.0% | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.05 | +0.00 | ±67% / ±0.03 ms | 67.4% | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.05 | +0.00 | ±67% / ±0.03 ms | 67.4% | stable | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.36 | 3.40 | +0.04 | ±12% / ±0.40 ms | 11.7% | stable | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.36 | 3.40 | +0.04 | ±12% / ±0.40 ms | 11.7% | stable | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.06 | 1.53 | -0.52 | ±53% / ±1.08 ms | 52.7% | stable | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.06 | 1.53 | -0.52 | ±53% / ±1.08 ms | 52.7% | stable | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 7.22 | 6.06 | -1.16 | ±10% / ±0.72 ms | 6.6% | stable | 🟢 Win (-16%) |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 7.22 | 6.06 | -1.16 | ±10% / ±0.72 ms | 6.6% | stable | 🟢 Win (-16%) |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.18 | 0.20 | +0.03 | ±109% / ±0.22 ms | 108.8% | noisy | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.18 | 0.20 | +0.03 | ±109% / ±0.22 ms | 108.8% | noisy | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.07 | 0.05 | -0.02 | ±10% / ±0.02 ms | 5.6% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.07 | 0.05 | -0.02 | ±10% / ±0.02 ms | 5.6% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.47 | 0.43 | -0.04 | ±10% / ±0.05 ms | 7.7% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.47 | 0.43 | -0.04 | ±10% / ±0.05 ms | 7.7% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.14 | 4.23 | +0.10 | ±11% / ±0.47 ms | 11.0% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.14 | 4.23 | +0.10 | ±11% / ±0.47 ms | 11.0% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.56 | 0.60 | +0.04 | ±10% / ±0.06 ms | 7.9% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.56 | 0.60 | +0.04 | ±10% / ±0.06 ms | 7.9% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.07 | +0.00 | ±24% / ±0.02 ms | 23.6% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.07 | +0.00 | ±24% / ±0.02 ms | 23.6% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 6.59 | 5.37 | -1.22 | ±10% / ±0.66 ms | 2.9% | stable | 🟢 Win (-19%) |
| Write Performance / Batched Write Inside Transaction (100... | 6.59 | 5.37 | -1.22 | ±10% / ±0.66 ms | 2.9% | stable | 🟢 Win (-19%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.43 | 0.50 | +0.07 | ±17% / ±0.09 ms | 17.1% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.43 | 0.50 | +0.07 | ±17% / ±0.09 ms | 17.1% | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.07 | +0.03 | ±45% / ±0.03 ms | 45.3% | noisy | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.07 | +0.03 | ±45% / ±0.03 ms | 45.3% | noisy | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.53 | 1.84 | +0.31 | ±20% / ±0.38 ms | 20.4% | moderate | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.53 | 1.84 | +0.31 | ±20% / ±0.38 ms | 20.4% | moderate | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.18 | -0.01 | ±10% / ±0.02 ms | 3.8% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.18 | -0.01 | ±10% / ±0.02 ms | 3.8% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 4.0% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 4.0% | stable | ⚪ Within noise |

**Summary:** 6 wins, 0 regressions, 147 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

✅ **No regressions beyond noise.** 6 benchmarks improved.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.02 | 0.02 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 0.00 | 2.97 | +2.97 MB | ±6.82 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 2.00 | 3.69 | +1.69 MB | ±5.55 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 0.00 | +0.00 MB | ±2.00 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 1.34 | 0.03 | -1.31 MB | ±3.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±1.52 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 11.36 | 14.34 | +2.98 MB | ±25.55 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / resqlite select() | 5.45 | 4.52 | -0.93 MB | ±5.41 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite3 select() | 2.66 | 3.39 | +0.73 MB | ±3.64 MB | ⚪ Within MDE |
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
| Streaming (Column Granularity) / Disjoint column writes (... | 3969 | 3877 | -92 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 20 | +10 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 3879 | 3992 | +113 | ±100 | 🔴 More re-emits (+113) |

**Granularity summary:** 0 fewer-re-emit, 1 more-re-emit, 5 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.
