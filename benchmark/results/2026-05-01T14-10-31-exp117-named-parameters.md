# resqlite Benchmark Results

Generated: 2026-05-01T14:10:31.211108

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp117-named-parameters`
- Repeats: `2`
- Runtime: `dart-vm / Dart 3.11.0`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `exp-117-named-parameters @ a6dd8cfe8ff4 (dirty)`
- Comparison baseline: `2026-05-01T13-17-43-baseline-for-exp117.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.014 | 0.020 | 0.002 | 0.003 |
| sqlite3 select() | 0.017 | 0.021 | 0.017 | 0.021 |
| sqlite_async select() | 0.038 | 0.043 | 0.002 | 0.003 |
| drift select() | 0.062 | 0.099 | 0.004 | 0.008 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.049 | 0.051 | 0.008 | 0.009 |
| sqlite3 select() | 0.118 | 0.147 | 0.118 | 0.147 |
| sqlite_async select() | 0.127 | 0.148 | 0.010 | 0.011 |
| drift select() | 0.184 | 0.208 | 0.010 | 0.011 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.390 | 0.428 | 0.087 | 0.099 |
| sqlite3 select() | 1.133 | 1.250 | 1.133 | 1.250 |
| sqlite_async select() | 1.064 | 1.240 | 0.097 | 0.113 |
| drift select() | 1.677 | 2.007 | 0.099 | 0.104 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.805 | 10.541 | 0.876 | 1.976 |
| sqlite3 select() | 14.513 | 17.639 | 14.513 | 17.639 |
| sqlite_async select() | 13.290 | 17.442 | 0.957 | 2.331 |
| drift select() | 21.949 | 29.141 | 0.961 | 1.090 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.027 | 0.036 | 0.016 | 0.019 |
| sqlite3 + jsonEncode | 0.030 | 0.032 | 0.030 | 0.032 |
| sqlite_async + jsonEncode | 0.047 | 0.048 | 0.016 | 0.017 |
| drift + jsonEncode | 0.058 | 0.085 | 0.018 | 0.024 |
| resqlite selectBytes() | 0.012 | 0.015 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.198 | 0.221 | 0.158 | 0.173 |
| sqlite3 + jsonEncode | 0.262 | 0.290 | 0.262 | 0.290 |
| sqlite_async + jsonEncode | 0.276 | 0.363 | 0.154 | 0.197 |
| drift + jsonEncode | 0.327 | 0.365 | 0.154 | 0.162 |
| resqlite selectBytes() | 0.045 | 0.049 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.818 | 2.023 | 1.484 | 1.702 |
| sqlite3 + jsonEncode | 2.677 | 5.136 | 2.677 | 5.136 |
| sqlite_async + jsonEncode | 2.642 | 4.953 | 1.572 | 1.884 |
| drift + jsonEncode | 3.167 | 4.852 | 1.535 | 2.010 |
| resqlite selectBytes() | 0.364 | 0.392 | 0.000 | 0.001 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 23.832 | 26.100 | 15.348 | 16.064 |
| sqlite3 + jsonEncode | 29.620 | 34.718 | 29.620 | 34.718 |
| sqlite_async + jsonEncode | 29.353 | 37.234 | 15.849 | 19.382 |
| drift + jsonEncode | 41.349 | 49.227 | 15.611 | 19.049 |
| resqlite selectBytes() | 4.041 | 6.178 | 0.004 | 0.012 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.107 | 0.113 | 0.036 | 0.040 |
| sqlite3 | 0.332 | 0.365 | 0.332 | 0.365 |
| sqlite_async | 0.376 | 0.444 | 0.044 | 0.046 |
| drift | 0.600 | 0.693 | 0.043 | 0.047 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.946 | 0.982 | 0.282 | 0.294 |
| sqlite3 | 3.250 | 3.979 | 3.250 | 3.979 |
| sqlite_async | 2.953 | 3.478 | 0.331 | 0.358 |
| drift | 4.867 | 6.622 | 0.331 | 0.358 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.541 | 0.572 | 0.104 | 0.107 |
| sqlite3 | 1.432 | 2.534 | 1.432 | 2.534 |
| sqlite_async | 1.383 | 1.643 | 0.118 | 0.125 |
| drift | 2.064 | 2.551 | 0.121 | 0.167 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.305 | 0.323 | 0.100 | 0.105 |
| sqlite3 | 1.050 | 1.158 | 1.050 | 1.158 |
| sqlite_async | 0.922 | 1.122 | 0.118 | 0.138 |
| drift | 1.643 | 1.804 | 0.128 | 0.144 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.329 | 0.413 | 0.104 | 0.113 |
| sqlite3 | 1.001 | 1.135 | 1.001 | 1.135 |
| sqlite_async | 0.964 | 1.102 | 0.121 | 0.131 |
| drift | 1.709 | 2.061 | 0.127 | 0.142 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.012 | 0.013 | 0.001 | 0.001 |
| sqlite3 | 0.016 | 0.016 | 0.016 | 0.016 |
| sqlite_async | 0.035 | 0.037 | 0.001 | 0.001 |
| drift | 0.053 | 0.073 | 0.002 | 0.004 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.032 | 0.035 | 0.004 | 0.005 |
| sqlite3 | 0.059 | 0.061 | 0.059 | 0.061 |
| sqlite_async | 0.075 | 0.078 | 0.005 | 0.005 |
| drift | 0.107 | 0.131 | 0.005 | 0.007 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.051 | 0.052 | 0.009 | 0.009 |
| sqlite3 | 0.117 | 0.122 | 0.117 | 0.122 |
| sqlite_async | 0.126 | 0.134 | 0.010 | 0.010 |
| drift | 0.178 | 0.192 | 0.009 | 0.012 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.199 | 0.233 | 0.044 | 0.047 |
| sqlite3 | 0.541 | 0.616 | 0.541 | 0.616 |
| sqlite_async | 0.519 | 0.633 | 0.047 | 0.056 |
| drift | 0.795 | 0.866 | 0.046 | 0.048 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.393 | 0.428 | 0.087 | 0.090 |
| sqlite3 | 1.105 | 1.221 | 1.105 | 1.221 |
| sqlite_async | 1.067 | 1.232 | 0.099 | 0.112 |
| drift | 1.619 | 2.104 | 0.095 | 0.101 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.838 | 2.064 | 0.175 | 0.228 |
| sqlite3 | 2.174 | 2.670 | 2.174 | 2.670 |
| sqlite_async | 2.069 | 3.271 | 0.184 | 0.193 |
| drift | 3.270 | 4.563 | 0.192 | 0.212 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.296 | 5.602 | 0.451 | 0.550 |
| sqlite3 | 5.625 | 7.635 | 5.625 | 7.635 |
| sqlite_async | 5.704 | 8.046 | 0.478 | 0.503 |
| drift | 8.807 | 9.855 | 0.481 | 0.503 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.676 | 12.202 | 0.873 | 1.303 |
| sqlite3 | 14.938 | 18.016 | 14.938 | 18.016 |
| sqlite_async | 13.160 | 16.270 | 0.950 | 1.435 |
| drift | 22.555 | 38.125 | 0.989 | 2.343 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 11.715 | 20.491 | 1.718 | 1.851 |
| sqlite3 | 34.805 | 40.076 | 34.805 | 40.076 |
| sqlite_async | 36.447 | 46.738 | 1.924 | 4.234 |
| drift | 52.132 | 67.851 | 1.896 | 8.207 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.078 | 0.259 | 0.078 | 0.259 |
| sqlite3 + jsonEncode | 0.032 | 0.040 | 0.032 | 0.040 |
| sqlite_async + jsonEncode | 0.045 | 0.055 | 0.045 | 0.055 |
| drift + jsonEncode | 0.067 | 0.136 | 0.067 | 0.136 |
| resqlite selectBytes() | 0.013 | 0.018 | 0.013 | 0.018 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.105 | 0.120 | 0.105 | 0.120 |
| sqlite3 + jsonEncode | 0.136 | 0.147 | 0.136 | 0.147 |
| sqlite_async + jsonEncode | 0.148 | 0.152 | 0.148 | 0.152 |
| drift + jsonEncode | 0.182 | 0.203 | 0.182 | 0.203 |
| resqlite selectBytes() | 0.025 | 0.026 | 0.025 | 0.026 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.199 | 0.210 | 0.199 | 0.210 |
| sqlite3 + jsonEncode | 0.255 | 0.298 | 0.255 | 0.298 |
| sqlite_async + jsonEncode | 0.264 | 0.277 | 0.264 | 0.277 |
| drift + jsonEncode | 0.320 | 0.347 | 0.320 | 0.347 |
| resqlite selectBytes() | 0.046 | 0.061 | 0.046 | 0.061 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.940 | 1.655 | 0.940 | 1.655 |
| sqlite3 + jsonEncode | 1.332 | 2.487 | 1.332 | 2.487 |
| sqlite_async + jsonEncode | 1.341 | 3.511 | 1.341 | 3.511 |
| drift + jsonEncode | 1.638 | 2.005 | 1.638 | 2.005 |
| resqlite selectBytes() | 0.185 | 0.188 | 0.185 | 0.188 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.900 | 4.025 | 1.900 | 4.025 |
| sqlite3 + jsonEncode | 2.608 | 4.041 | 2.608 | 4.041 |
| sqlite_async + jsonEncode | 2.545 | 4.014 | 2.545 | 4.014 |
| drift + jsonEncode | 3.126 | 4.780 | 3.126 | 4.780 |
| resqlite selectBytes() | 0.352 | 0.403 | 0.352 | 0.403 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.880 | 7.169 | 3.880 | 7.169 |
| sqlite3 + jsonEncode | 5.382 | 10.256 | 5.382 | 10.256 |
| sqlite_async + jsonEncode | 5.264 | 8.757 | 5.264 | 8.757 |
| drift + jsonEncode | 6.490 | 11.265 | 6.490 | 11.265 |
| resqlite selectBytes() | 0.799 | 1.127 | 0.799 | 1.127 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 10.297 | 14.535 | 10.297 | 14.535 |
| sqlite3 + jsonEncode | 14.157 | 20.338 | 14.157 | 20.338 |
| sqlite_async + jsonEncode | 13.993 | 21.216 | 13.993 | 21.216 |
| drift + jsonEncode | 19.498 | 22.285 | 19.498 | 22.285 |
| resqlite selectBytes() | 1.938 | 4.283 | 1.938 | 4.283 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 23.896 | 25.584 | 23.896 | 25.584 |
| sqlite3 + jsonEncode | 29.705 | 36.454 | 29.705 | 36.454 |
| sqlite_async + jsonEncode | 29.899 | 34.240 | 29.899 | 34.240 |
| drift + jsonEncode | 41.171 | 52.342 | 41.171 | 52.342 |
| resqlite selectBytes() | 3.844 | 6.634 | 3.844 | 6.634 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 45.297 | 49.195 | 45.297 | 49.195 |
| sqlite3 + jsonEncode | 67.091 | 73.126 | 67.091 | 73.126 |
| sqlite_async + jsonEncode | 70.093 | 78.410 | 70.093 | 78.410 |
| drift + jsonEncode | 82.438 | 95.221 | 82.438 | 95.221 |
| resqlite selectBytes() | 7.897 | 11.860 | 7.897 | 11.860 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.31 | 0.34 | 0.31 |
| sqlite_async | 0.93 | 1.16 | 0.93 |
| drift | 1.52 | 1.67 | 1.52 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.32 | 0.34 | 0.16 |
| sqlite_async | 1.35 | 1.58 | 0.68 |
| drift | 2.81 | 3.25 | 1.40 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.37 | 0.42 | 0.09 |
| sqlite_async | 2.17 | 2.87 | 0.54 |
| drift | 5.19 | 5.59 | 1.30 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.68 | 1.10 | 0.09 |
| sqlite_async | 4.64 | 5.88 | 0.58 |
| drift | 10.60 | 11.40 | 1.32 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 140282 |
| resqlite per query | 0.007 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 140282 | 131844..144001 | 4.3 | 10.0 |
| sqlite3 | 190747 | 183217..192361 | 2.4 | 3.5 |
| sqlite_async | 45314 | 43694..47474 | 4.2 | 13.4 |
| drift | 45345 | 44798..45809 | 1.1 | 3.6 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 15.053 | 15.675 | 15.053 | 15.675 |
| sqlite_async | 36.429 | 37.379 | 36.429 | 37.379 |
| drift | 53.879 | 54.839 | 53.879 | 54.839 |
| sqlite3 (no cache) | 25.109 | 27.102 | 25.109 | 27.102 |
| sqlite3 (cached stmt) | 24.632 | 24.886 | 24.632 | 24.886 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 2.059 | 2.584 | 2.059 | 2.584 |
| sqlite3 execute() | 0.988 | 1.824 | 0.988 | 1.824 |
| sqlite_async execute() | 3.121 | 3.982 | 3.121 | 3.982 |
| drift execute() | 3.320 | 4.022 | 3.320 | 4.022 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.054 | 0.059 | 0.054 | 0.059 |
| sqlite3 executeBatch() | 0.047 | 0.050 | 0.047 | 0.050 |
| sqlite_async executeBatch() | 0.094 | 0.115 | 0.094 | 0.115 |
| drift executeBatch() | 0.112 | 0.126 | 0.112 | 0.126 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.422 | 0.491 | 0.422 | 0.491 |
| sqlite3 executeBatch() | 0.449 | 0.491 | 0.449 | 0.491 |
| sqlite_async executeBatch() | 0.519 | 0.567 | 0.519 | 0.567 |
| drift executeBatch() | 0.660 | 0.719 | 0.660 | 0.719 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 3.988 | 4.581 | 3.988 | 4.581 |
| sqlite3 executeBatch() | 4.084 | 4.513 | 4.084 | 4.513 |
| sqlite_async executeBatch() | 5.107 | 6.051 | 5.107 | 6.051 |
| drift executeBatch() | 6.387 | 7.238 | 6.387 | 7.238 |

### Wide Batch Insert (10000 rows x 20 params)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 20.869 | 28.186 | 20.869 | 28.186 |
| sqlite3 executeBatch() | 20.361 | 22.392 | 20.361 | 22.392 |
| sqlite_async executeBatch() | 25.184 | 29.606 | 25.184 | 29.606 |
| drift executeBatch() | 27.196 | 32.447 | 27.196 | 32.447 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.056 | 0.087 | 0.056 | 0.087 |
| sqlite_async writeTransaction() | 0.110 | 1.116 | 0.110 | 1.116 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.066 | 0.101 | 0.066 | 0.101 |
| resqlite tx.execute() loop | 0.569 | 0.732 | 0.569 | 0.732 |
| sqlite_async tx.execute() loop | 1.217 | 1.372 | 1.217 | 1.372 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.450 | 0.588 | 0.450 | 0.588 |
| resqlite tx.execute() loop | 6.672 | 8.100 | 6.672 | 8.100 |
| sqlite_async tx.execute() loop | 10.144 | 11.514 | 10.144 | 11.514 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.109 | 0.116 | 0.109 | 0.116 |
| sqlite_async tx.getAll() | 0.201 | 0.242 | 0.201 | 0.242 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.185 | 0.199 | 0.185 | 0.199 |
| sqlite_async tx.getAll() | 0.365 | 0.404 | 0.365 | 0.404 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 0.955 | 1.172 | 0.955 | 1.172 |
| resqlite nested transaction() depth=5 | 0.086 | 0.112 | 0.086 | 0.112 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.026 | 0.030 | 0.026 | 0.030 |
| sqlite_async watch() | 0.129 | 0.248 | 0.129 | 0.248 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.063 | 0.160 | 0.063 | 0.160 |
| sqlite_async | 0.071 | 0.110 | 0.071 | 0.110 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.188 | 0.259 | 0.188 | 0.259 |
| sqlite_async | 0.566 | 2.632 | 0.566 | 2.632 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.036 | 4.057 | 2.036 | 4.057 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.205 | 0.250 | 0.205 | 0.250 |
| sqlite_async | 0.266 | 0.314 | 0.266 | 0.314 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.931 | 1.931 | 1.931 | 1.931 |
| sqlite_async | 11.034 | 11.034 | 11.034 | 11.034 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.170 | 5.133 | 4.170 | 5.133 |
| sqlite_async | 6.056 | 7.066 | 6.056 | 7.066 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.517 | 0.721 | 0.517 | 0.721 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 5.945 | 7.082 | 5.945 | 7.082 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. For resqlite, this emission metric can reflect writer-side column-level invalidation, experiment 075's native result-hash short-circuit, or both. Use A11c (Many-Streams Writer Throughput) when the question is specifically writer-side dispatch elision.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 71.6 | 0.000 |
| sqlite_async | 3936 | 950.2 | 1.007 |
| drift | 5000 | 1058.0 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 72.6 | 0.000 |
| sqlite_async | 3910 | 957.1 | 1.007 |
| drift | 5000 | 1090.6 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 218.88 | 219.23 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 436.74 | 438.90 | 0.00 | 0.01 | 1114 | 3 |
| drift stream() | 550.93 | 567.32 | 0.02 | 0.04 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.031 | 0.056 | 0.000 | 0.000 |
| sqlite3 | 0.024 | 0.054 | 0.024 | 0.054 |
| sqlite_async | 0.054 | 0.093 | 0.000 | 0.000 |
| drift | 0.070 | 0.155 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.023 | 0.045 | 0.000 | 0.000 |
| sqlite3 | 0.016 | 0.027 | 0.016 | 0.027 |
| sqlite_async | 0.043 | 0.077 | 0.000 | 0.000 |
| drift | 0.055 | 0.119 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.031 | 0.047 | 0.000 | 0.000 |
| sqlite3 | 0.033 | 0.037 | 0.033 | 0.037 |
| sqlite_async | 0.067 | 0.101 | 0.000 | 0.000 |
| drift | 0.067 | 0.100 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.011 | 0.024 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.007 | 0.005 | 0.007 |
| sqlite_async | 0.027 | 0.038 | 0.000 | 0.000 |
| drift | 0.027 | 0.050 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.046 | 0.095 | 0.001 | 0.002 |
| sqlite3 | 0.068 | 0.073 | 0.068 | 0.073 |
| sqlite_async | 0.082 | 0.087 | 0.001 | 0.001 |
| drift | 0.096 | 0.105 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 107.851 | 111.622 | 0.000 | 0.000 | 0 |
| sqlite_async | 215.783 | 219.266 | 0.000 | 0.001 | 44 |
| drift | 219.654 | 222.946 | 0.000 | 0.001 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 235.04 | 235.04 | 0.00 | 0.00 | 14.51 | 220.53 | 0 |
| sqlite_async | 474.20 | 474.20 | 0.01 | 0.01 | 22.75 | 451.45 | 1174 |
| drift | 1826.27 | 1826.27 | 0.11 | 0.11 | 12.40 | 1813.86 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 3.59 | 12.83 | 0.00..5.81 | ±2.91 |
| sqlite3 select() | 4.00 | 9.50 | 1.31..8.67 | ±3.68 |
| sqlite_async select() | 1.00 | 1.00 | 1.00..1.00 | ±0.00 |
| drift select() | 7.00 | 54.64 | 0.00..11.52 | ±5.76 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 8.00 | 0.00..4.00 | ±2.00 |
| resqlite + jsonEncode | 0.00 | 20.63 | 0.00..11.03 | ±5.52 |
| sqlite3 + jsonEncode | 0.00 | 52.09 | 0.00..10.52 | ±5.26 |
| sqlite_async + jsonEncode | 0.00 | 19.16 | 0.00..1.55 | ±0.77 |
| drift + jsonEncode | 3.41 | 14.06 | 0.00..5.97 | ±2.98 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.00 | 6.52 | 0.00..6.02 | ±3.01 |
| sqlite3 executeBatch() | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 0.08 | 0.00..0.03 | ±0.02 |
| drift batch() | 0.00 | 2.00 | 0.00..0.00 | ±0.00 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.13 | 0.00..0.06 | ±0.03 |
| sqlite_async watch() | 0.00 | 0.50 | 0.00..0.50 | ±0.25 |

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
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.03 | 0.03..0.03 | 13.8% | 13.8% | 6.9% | moderate |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 20.0% | 20.0% | 10.0% | noisy |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.03 | 0.02..0.03 | 25.5% | 25.5% | 12.7% | noisy |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02..0.02 | 19.0% | 19.0% | 9.5% | noisy |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.32 | 0.31..0.33 | 6.3% | 6.3% | 3.1% | moderate |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.32 | 0.31..0.33 | 6.3% | 6.3% | 3.1% | moderate |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.34 | 0.32..0.37 | 14.5% | 14.5% | 7.2% | moderate |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.17 | 0.16..0.19 | 17.1% | 17.1% | 8.6% | noisy |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.60 | 0.37..0.83 | 76.7% | 76.7% | 38.3% | noisy |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.15 | 0.09..0.21 | 80.0% | 80.0% | 40.0% | noisy |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.81 | 0.68..0.94 | 32.1% | 32.1% | 16.0% | noisy |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.10 | 0.09..0.12 | 28.6% | 28.6% | 14.3% | noisy |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.05 | 9.1% | 9.1% | 4.5% | moderate |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 120.0% | 120.0% | 60.0% | noisy |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 110.83 | 107.85..113.80 | 5.4% | 5.4% | 2.7% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 235.49 | 235.04..235.94 | 0.4% | 0.4% | 0.2% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 221.47 | 218.88..224.06 | 2.3% | 2.3% | 1.2% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 14.98 | 14.90..15.05 | 1.0% | 1.0% | 0.5% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 14.98 | 14.90..15.05 | 1.0% | 1.0% | 0.5% | stable |
| Point Query Throughput / resqlite qps | 120654.00 | 101026.00..140282.00 | 32.5% | 32.5% | 16.3% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.02 | 34.5% | 34.5% | 17.2% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.06 | 0.04..0.08 | 76.1% | 76.1% | 38.1% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.06 | 0.04..0.08 | 76.1% | 76.1% | 38.1% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 66.7% | 66.7% | 33.3% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 26.7% | 26.7% | 13.3% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.02 | 26.7% | 26.7% | 13.3% | noisy |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05..0.06 | 9.3% | 9.3% | 4.7% | moderate |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.20 | 0.20..0.21 | 4.4% | 4.4% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.20 | 0.20..0.21 | 4.4% | 4.4% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.05 | 0.05..0.05 | 16.0% | 16.0% | 8.0% | moderate |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.05 | 0.05..0.05 | 16.0% | 16.0% | 8.0% | moderate |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.39 | 0.39..0.40 | 0.8% | 0.8% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.94 | 1.90..1.97 | 3.6% | 3.6% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.94 | 1.90..1.97 | 3.6% | 3.6% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09..0.09 | 1.1% | 1.1% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.36 | 0.35..0.38 | 6.3% | 6.3% | 3.2% | moderate |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.36 | 0.35..0.38 | 6.3% | 6.3% | 3.2% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.80 | 4.68..4.92 | 5.0% | 5.0% | 2.5% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 22.63 | 21.37..23.90 | 11.1% | 11.1% | 5.6% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 22.63 | 21.37..23.90 | 11.1% | 11.1% | 5.6% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.88 | 0.87..0.89 | 2.3% | 2.3% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 3.95 | 3.84..4.07 | 5.6% | 5.6% | 2.8% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 3.95 | 3.84..4.07 | 5.6% | 5.6% | 2.8% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.84 | 0.84..0.85 | 1.2% | 1.2% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 4.00 | 3.88..4.13 | 6.2% | 6.2% | 3.1% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 4.00 | 3.88..4.13 | 6.2% | 6.2% | 3.1% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.18 | 0.17..0.18 | 1.1% | 1.1% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.79 | 0.78..0.80 | 2.3% | 2.3% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.79 | 0.78..0.80 | 2.3% | 2.3% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 11.55 | 11.39..11.71 | 2.8% | 2.8% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 45.37 | 45.30..45.45 | 0.3% | 0.3% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 45.37 | 45.30..45.45 | 0.3% | 0.3% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.75 | 1.72..1.78 | 3.4% | 3.4% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 8.45 | 7.90..9.00 | 13.1% | 13.1% | 6.5% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 8.45 | 7.90..9.00 | 13.1% | 13.1% | 6.5% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.04 | 0.03..0.04 | 19.7% | 19.7% | 9.9% | noisy |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.10..0.11 | 8.2% | 8.2% | 4.1% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.11 | 0.10..0.11 | 8.2% | 8.2% | 4.1% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.01 | 22.2% | 22.2% | 11.1% | noisy |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.03..0.03 | 24.6% | 24.6% | 12.3% | noisy |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.03..0.03 | 24.6% | 24.6% | 12.3% | noisy |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.20 | 0.20..0.20 | 2.5% | 2.5% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.96 | 0.94..0.99 | 5.1% | 5.1% | 2.5% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.96 | 0.94..0.99 | 5.1% | 5.1% | 2.5% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04..0.04 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.19 | 0.18..0.20 | 5.3% | 5.3% | 2.6% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.19 | 0.18..0.20 | 5.3% | 5.3% | 2.6% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.33 | 2.30..2.36 | 2.6% | 2.6% | 1.3% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 10.88 | 10.30..11.46 | 10.7% | 10.7% | 5.3% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 10.88 | 10.30..11.46 | 10.7% | 10.7% | 5.3% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.45 | 0.44..0.45 | 1.8% | 1.8% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 1.97 | 1.94..2.00 | 2.9% | 2.9% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 1.97 | 1.94..2.00 | 2.9% | 2.9% | 1.4% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.10 | 0.10..0.11 | 4.8% | 4.8% | 2.4% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.03 | 0.03..0.04 | 11.8% | 11.8% | 5.9% | moderate |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.32 | 0.31..0.33 | 5.9% | 5.9% | 3.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.10 | 0.10..0.10 | 4.9% | 4.9% | 2.5% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.31 | 0.30..0.32 | 5.4% | 5.4% | 2.7% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.10 | 0.10..0.10 | 3.0% | 3.0% | 1.5% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.55 | 0.54..0.56 | 3.6% | 3.6% | 1.8% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.10 | 0.10..0.10 | 1.9% | 1.9% | 1.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.95 | 0.95..0.96 | 1.9% | 1.9% | 0.9% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.28 | 0.27..0.28 | 2.9% | 2.9% | 1.4% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.06 | 0.03..0.10 | 115.6% | 115.6% | 57.8% | noisy |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.05 | 0.02..0.08 | 131.2% | 131.2% | 65.6% | noisy |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.02 | 0.01..0.02 | 50.0% | 50.0% | 25.0% | noisy |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.22 | 0.20..0.24 | 20.0% | 20.0% | 10.0% | noisy |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.17 | 0.16..0.19 | 17.3% | 17.3% | 8.7% | noisy |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.04..0.06 | 23.5% | 23.5% | 11.8% | noisy |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 200.0% | 200.0% | 100.0% | noisy |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.89 | 1.82..1.97 | 8.0% | 8.0% | 4.0% | moderate |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.53 | 1.48..1.58 | 6.5% | 6.5% | 3.2% | moderate |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.37 | 0.36..0.38 | 4.3% | 4.3% | 2.2% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 23.87 | 23.83..23.90 | 0.3% | 0.3% | 0.1% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 16.10 | 15.35..16.84 | 9.3% | 9.3% | 4.7% | moderate |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.98 | 3.92..4.04 | 2.9% | 2.9% | 1.5% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.01 | 22.2% | 22.2% | 11.1% | noisy |
| Select → Maps / 10 rows / resqlite select() | 0.05 | 0.01..0.08 | 138.5% | 138.5% | 69.2% | noisy |
| Select → Maps / 10 rows / resqlite select() [main] | 0.01 | 0.00..0.02 | 166.7% | 166.7% | 83.3% | noisy |
| Select → Maps / 100 rows / resqlite select() | 0.11 | 0.05..0.16 | 106.7% | 106.7% | 53.3% | noisy |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 31.6% | 31.6% | 15.8% | noisy |
| Select → Maps / 1000 rows / resqlite select() | 0.42 | 0.39..0.45 | 13.2% | 13.2% | 6.6% | moderate |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.08 | 0.08..0.09 | 10.9% | 10.9% | 5.5% | moderate |
| Select → Maps / 10000 rows / resqlite select() | 5.20 | 4.80..5.59 | 15.0% | 15.0% | 7.5% | moderate |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.80 | 0.73..0.88 | 18.5% | 18.5% | 9.2% | noisy |
| Streaming / Fan-out (10 streams) / resqlite | 0.27 | 0.20..0.33 | 45.6% | 45.6% | 22.8% | noisy |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.27 | 0.20..0.33 | 45.6% | 45.6% | 22.8% | noisy |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.54 | 0.52..0.57 | 9.8% | 9.8% | 4.9% | moderate |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.54 | 0.52..0.57 | 9.8% | 9.8% | 4.9% | moderate |
| Streaming / Initial Emission / resqlite stream() | 0.04 | 0.03..0.06 | 77.6% | 77.6% | 38.8% | noisy |
| Streaming / Initial Emission / resqlite stream() [main] | 0.04 | 0.03..0.06 | 77.6% | 77.6% | 38.8% | noisy |
| Streaming / Invalidation Latency / resqlite | 0.06 | 0.06..0.06 | 3.2% | 3.2% | 1.6% | stable |
| Streaming / Invalidation Latency / resqlite [main] | 0.06 | 0.06..0.06 | 3.2% | 3.2% | 1.6% | stable |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 2.52 | 2.04..3.01 | 38.5% | 38.5% | 19.3% | noisy |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 2.52 | 2.04..3.01 | 38.5% | 38.5% | 19.3% | noisy |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 4.33 | 4.17..4.50 | 7.6% | 7.6% | 3.8% | moderate |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 4.33 | 4.17..4.50 | 7.6% | 7.6% | 3.8% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.44 | 1.93..2.94 | 41.4% | 41.4% | 20.7% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.44 | 1.93..2.94 | 41.4% | 41.4% | 20.7% | noisy |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.34 | 5.95..6.73 | 12.4% | 12.4% | 6.2% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.34 | 5.95..6.73 | 12.4% | 12.4% | 6.2% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.23 | 0.19..0.27 | 35.8% | 35.8% | 17.9% | noisy |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.23 | 0.19..0.27 | 35.8% | 35.8% | 17.9% | noisy |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.05 | 0.05..0.05 | 1.9% | 1.9% | 0.9% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.05 | 0.05..0.05 | 1.9% | 1.9% | 0.9% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.42 | 0.42..0.42 | 0.7% | 0.7% | 0.4% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.42 | 0.42..0.42 | 0.7% | 0.7% | 0.4% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.14 | 3.99..4.29 | 7.2% | 7.2% | 3.6% | moderate |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.14 | 3.99..4.29 | 7.2% | 7.2% | 3.6% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.75 | 0.57..0.93 | 47.8% | 47.8% | 23.9% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.75 | 0.57..0.93 | 47.8% | 47.8% | 23.9% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.09 | 0.07..0.12 | 57.3% | 57.3% | 28.6% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.09 | 0.07..0.12 | 57.3% | 57.3% | 28.6% | noisy |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 7.73 | 6.67..8.78 | 27.3% | 27.3% | 13.6% | noisy |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 7.73 | 6.67..8.78 | 27.3% | 27.3% | 13.6% | noisy |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.48 | 0.45..0.50 | 11.1% | 11.1% | 5.6% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.48 | 0.45..0.50 | 11.1% | 11.1% | 5.6% | moderate |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.06 | 0.06..0.07 | 22.2% | 22.2% | 11.1% | noisy |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.06 | 0.06..0.07 | 22.2% | 22.2% | 11.1% | noisy |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.10 | 0.09..0.11 | 27.1% | 27.1% | 13.6% | noisy |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.10 | 0.09..0.11 | 27.1% | 27.1% | 13.6% | noisy |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 1.26 | 0.95..1.57 | 49.0% | 49.0% | 24.5% | noisy |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 1.26 | 0.95..1.57 | 49.0% | 49.0% | 24.5% | noisy |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 2.12 | 2.06..2.19 | 6.1% | 6.1% | 3.0% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 2.12 | 2.06..2.19 | 6.1% | 6.1% | 3.0% | moderate |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.20 | 0.18..0.21 | 13.1% | 13.1% | 6.6% | moderate |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.20 | 0.18..0.21 | 13.1% | 13.1% | 6.6% | moderate |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.12 | 0.11..0.13 | 15.3% | 15.3% | 7.6% | moderate |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.12 | 0.11..0.13 | 15.3% | 15.3% | 7.6% | moderate |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 20.76 | 20.66..20.87 | 1.0% | 1.0% | 0.5% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 20.76 | 20.66..20.87 | 1.0% | 1.0% | 0.5% | stable |


## Comparison vs Previous Run

Previous: `2026-05-01T13-17-43-baseline-for-exp117.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.03 | 0.03 | -0.01 | ±21% / ±0.02 ms | 13.8% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | -0.00 | ±30% / ±0.02 ms | 20.0% | noisy | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.04 | 0.03 | -0.01 | ±38% / ±0.02 ms | 25.5% | noisy | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.03 | 0.02 | -0.01 | ±29% / ±0.02 ms | 19.0% | noisy | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.32 | 0.32 | +0.00 | ±10% / ±0.03 ms | 6.3% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.32 | 0.32 | +0.00 | ±10% / ±0.03 ms | 6.3% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.34 | 0.34 | +0.00 | ±22% / ±0.07 ms | 14.5% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.17 | 0.17 | +0.00 | ±26% / ±0.05 ms | 17.1% | noisy | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.39 | 0.60 | +0.21 | ±115% / ±0.69 ms | 76.7% | noisy | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.10 | 0.15 | +0.05 | ±120% / ±0.18 ms | 80.0% | noisy | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.78 | 0.81 | +0.03 | ±48% / ±0.39 ms | 32.1% | noisy | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.10 | 0.10 | +0.00 | ±43% / ±0.04 ms | 28.6% | noisy | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | +0.00 | ±14% / ±0.02 ms | 9.1% | moderate | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±180% / ±0.02 ms | 120.0% | noisy | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 105.88 | 110.83 | +4.95 | ±10% / ±11.08 ms | 5.4% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 248.33 | 235.49 | -12.84 | ±10% / ±24.83 ms | 0.4% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 220.08 | 221.47 | +1.39 | ±10% / ±22.15 ms | 2.3% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 18.30 | 14.98 | -3.32 | ±10% / ±1.83 ms | 1.0% | stable | 🟢 Win (-18%) |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 18.30 | 14.98 | -3.32 | ±10% / ±1.83 ms | 1.0% | stable | 🟢 Win (-18%) |
| Point Query Throughput / resqlite qps | 92631.00 | 120654.00 | +28023.00 | ±49% / ±58884.00 ms | 32.5% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01 | -0.00 | ±52% / ±0.02 ms | 34.5% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.06 | +0.03 | ±114% / ±0.06 ms | 76.1% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.06 | +0.03 | ±114% / ±0.06 ms | 76.1% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±100% / ±0.02 ms | 66.7% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±40% / ±0.02 ms | 26.7% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±40% / ±0.02 ms | 26.7% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05 | +0.00 | ±14% / ±0.02 ms | 9.3% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.20 | +0.01 | ±10% / ±0.02 ms | 4.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.20 | +0.01 | ±10% / ±0.02 ms | 4.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.05 | 0.05 | +0.00 | ±24% / ±0.02 ms | 16.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.05 | 0.05 | +0.00 | ±24% / ±0.02 ms | 16.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.41 | 0.39 | -0.01 | ±10% / ±0.04 ms | 0.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.86 | 1.94 | +0.08 | ±10% / ±0.19 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.86 | 1.94 | +0.08 | ±10% / ±0.19 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.10 | 0.09 | -0.02 | ±10% / ±0.02 ms | 1.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.37 | 0.36 | -0.01 | ±10% / ±0.04 ms | 6.3% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.37 | 0.36 | -0.01 | ±10% / ±0.04 ms | 6.3% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.97 | 4.80 | -0.17 | ±10% / ±0.50 ms | 5.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 25.69 | 22.63 | -3.05 | ±17% / ±4.29 ms | 11.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 25.69 | 22.63 | -3.05 | ±17% / ±4.29 ms | 11.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 1.04 | 0.88 | -0.15 | ±10% / ±0.10 ms | 2.3% | stable | 🟢 Win (-15%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 5.49 | 3.95 | -1.54 | ±10% / ±0.55 ms | 5.6% | stable | 🟢 Win (-28%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 5.49 | 3.95 | -1.54 | ±10% / ±0.55 ms | 5.6% | stable | 🟢 Win (-28%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.86 | 0.84 | -0.02 | ±10% / ±0.09 ms | 1.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.94 | 4.00 | +0.07 | ±10% / ±0.40 ms | 6.2% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.94 | 4.00 | +0.07 | ±10% / ±0.40 ms | 6.2% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.21 | 0.18 | -0.03 | ±10% / ±0.02 ms | 1.1% | stable | 🟢 Win (-15%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.84 | 0.79 | -0.05 | ±10% / ±0.08 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.84 | 0.79 | -0.05 | ±10% / ±0.08 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 11.78 | 11.55 | -0.22 | ±10% / ±1.18 ms | 2.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 52.53 | 45.37 | -7.15 | ±10% / ±5.25 ms | 0.3% | stable | 🟢 Win (-14%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 52.53 | 45.37 | -7.15 | ±10% / ±5.25 ms | 0.3% | stable | 🟢 Win (-14%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 2.05 | 1.75 | -0.30 | ±10% / ±0.20 ms | 3.4% | stable | 🟢 Win (-15%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.41 | 8.45 | +0.03 | ±20% / ±1.66 ms | 13.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.41 | 8.45 | +0.03 | ±20% / ±1.66 ms | 13.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.04 | +0.01 | ±30% / ±0.02 ms | 19.7% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.11 | +0.01 | ±12% / ±0.02 ms | 8.2% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.10 | 0.11 | +0.01 | ±12% / ±0.02 ms | 8.2% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.01 | 0.00 | -0.00 | ±33% / ±0.02 ms | 22.2% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | +0.00 | ±37% / ±0.02 ms | 24.6% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | +0.00 | ±37% / ±0.02 ms | 24.6% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.21 | 0.20 | -0.01 | ±10% / ±0.02 ms | 2.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.94 | 0.96 | +0.02 | ±10% / ±0.10 ms | 5.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.94 | 0.96 | +0.02 | ±10% / ±0.10 ms | 5.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.05 | 0.04 | -0.01 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.19 | 0.19 | +0.00 | ±10% / ±0.02 ms | 5.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.19 | 0.19 | +0.00 | ±10% / ±0.02 ms | 5.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.31 | 2.33 | +0.01 | ±10% / ±0.23 ms | 2.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.54 | 10.88 | +0.34 | ±16% / ±1.74 ms | 10.7% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.54 | 10.88 | +0.34 | ±16% / ±1.74 ms | 10.7% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.52 | 0.45 | -0.07 | ±10% / ±0.05 ms | 1.8% | stable | 🟢 Win (-13%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 2.83 | 1.97 | -0.86 | ±10% / ±0.28 ms | 2.9% | stable | 🟢 Win (-30%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 2.83 | 1.97 | -0.86 | ±10% / ±0.28 ms | 2.9% | stable | 🟢 Win (-30%) |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.11 | 0.10 | -0.01 | ±10% / ±0.02 ms | 4.8% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.04 | 0.03 | -0.01 | ±18% / ±0.02 ms | 11.8% | moderate | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.33 | 0.32 | -0.01 | ±10% / ±0.03 ms | 5.9% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.13 | 0.10 | -0.02 | ±10% / ±0.02 ms | 4.9% | stable | 🟢 Win (-19%) |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.33 | 0.31 | -0.02 | ±10% / ±0.03 ms | 5.4% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.13 | 0.10 | -0.03 | ±10% / ±0.02 ms | 3.0% | stable | 🟢 Win (-24%) |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.60 | 0.55 | -0.05 | ±10% / ±0.06 ms | 3.6% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.13 | 0.10 | -0.03 | ±10% / ±0.02 ms | 1.9% | stable | 🟢 Win (-20%) |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 1.04 | 0.95 | -0.09 | ±10% / ±0.10 ms | 1.9% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.36 | 0.28 | -0.09 | ±10% / ±0.04 ms | 2.9% | stable | 🟢 Win (-24%) |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.06 | +0.04 | ±173% / ±0.11 ms | 115.6% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.05 | +0.03 | ±197% / ±0.09 ms | 131.2% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.02 | +0.01 | ±75% / ±0.02 ms | 50.0% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.22 | +0.02 | ±30% / ±0.07 ms | 20.0% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.15 | 0.17 | +0.02 | ±26% / ±0.05 ms | 17.3% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.05 | +0.01 | ±35% / ±0.02 ms | 23.5% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±300% / ±0.02 ms | 200.0% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.86 | 1.89 | +0.03 | ±12% / ±0.23 ms | 8.0% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.49 | 1.53 | +0.04 | ±10% / ±0.15 ms | 6.5% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.36 | 0.37 | +0.02 | ±10% / ±0.04 ms | 4.3% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 24.29 | 23.87 | -0.43 | ±10% / ±2.43 ms | 0.3% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 15.37 | 16.10 | +0.73 | ±14% / ±2.25 ms | 9.3% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.98 | 3.98 | -0.00 | ±10% / ±0.40 ms | 2.9% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±33% / ±0.02 ms | 22.2% | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.05 | +0.03 | ±208% / ±0.09 ms | 138.5% | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.01 | +0.01 | ±250% / ±0.03 ms | 166.7% | noisy | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.11 | +0.06 | ±160% / ±0.17 ms | 106.7% | noisy | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±47% / ±0.02 ms | 31.6% | noisy | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.38 | 0.42 | +0.04 | ±20% / ±0.08 ms | 13.2% | moderate | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.08 | -0.00 | ±16% / ±0.02 ms | 10.9% | moderate | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 4.55 | 5.20 | +0.64 | ±23% / ±1.17 ms | 15.0% | moderate | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.88 | 0.80 | -0.08 | ±28% / ±0.24 ms | 18.5% | noisy | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.24 | 0.27 | +0.02 | ±68% / ±0.18 ms | 45.6% | noisy | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.24 | 0.27 | +0.02 | ±68% / ±0.18 ms | 45.6% | noisy | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.52 | 0.54 | +0.02 | ±15% / ±0.08 ms | 9.8% | moderate | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.52 | 0.54 | +0.02 | ±15% / ±0.08 ms | 9.8% | moderate | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.04 | +0.01 | ±116% / ±0.05 ms | 77.6% | noisy | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.04 | +0.01 | ±116% / ±0.05 ms | 77.6% | noisy | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 3.2% | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 3.2% | stable | ⚪ Within noise |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 2.75 | 2.52 | -0.23 | ±58% / ±1.59 ms | 38.5% | noisy | ⚪ Within noise |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 2.75 | 2.52 | -0.23 | ±58% / ±1.59 ms | 38.5% | noisy | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.97 | 4.33 | +0.37 | ±11% / ±0.49 ms | 7.6% | moderate | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.97 | 4.33 | +0.37 | ±11% / ±0.49 ms | 7.6% | moderate | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.71 | 2.44 | +0.72 | ±62% / ±1.51 ms | 41.4% | noisy | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.71 | 2.44 | +0.72 | ±62% / ±1.51 ms | 41.4% | noisy | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 7.47 | 6.34 | -1.13 | ±19% / ±1.39 ms | 12.4% | moderate | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 7.47 | 6.34 | -1.13 | ±19% / ±1.39 ms | 12.4% | moderate | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.25 | 0.23 | -0.02 | ±54% / ±0.13 ms | 35.8% | noisy | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.25 | 0.23 | -0.02 | ±54% / ±0.13 ms | 35.8% | noisy | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 1.9% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 1.9% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.40 | 0.42 | +0.02 | ±10% / ±0.04 ms | 0.7% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.40 | 0.42 | +0.02 | ±10% / ±0.04 ms | 0.7% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.96 | 4.14 | +0.17 | ±11% / ±0.45 ms | 7.2% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.96 | 4.14 | +0.17 | ±11% / ±0.45 ms | 7.2% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.66 | 0.75 | +0.09 | ±72% / ±0.54 ms | 47.8% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.66 | 0.75 | +0.09 | ±72% / ±0.54 ms | 47.8% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.08 | 0.09 | +0.01 | ±86% / ±0.08 ms | 57.3% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.08 | 0.09 | +0.01 | ±86% / ±0.08 ms | 57.3% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 7.66 | 7.73 | +0.07 | ±41% / ±3.16 ms | 27.3% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 7.66 | 7.73 | +0.07 | ±41% / ±3.16 ms | 27.3% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.44 | 0.48 | +0.04 | ±17% / ±0.08 ms | 11.1% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.44 | 0.48 | +0.04 | ±17% / ±0.08 ms | 11.1% | moderate | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.07 | 0.06 | -0.01 | ±33% / ±0.03 ms | 22.2% | noisy | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.07 | 0.06 | -0.01 | ±33% / ±0.03 ms | 22.2% | noisy | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.09 | 0.10 | +0.01 | ±41% / ±0.04 ms | 27.1% | noisy | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.09 | 0.10 | +0.01 | ±41% / ±0.04 ms | 27.1% | noisy | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 1.05 | 1.26 | +0.22 | ±73% / ±0.93 ms | 49.0% | noisy | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 1.05 | 1.26 | +0.22 | ±73% / ±0.93 ms | 49.0% | noisy | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 2.18 | 2.12 | -0.05 | ±10% / ±0.22 ms | 6.1% | moderate | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 2.18 | 2.12 | -0.05 | ±10% / ±0.22 ms | 6.1% | moderate | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.20 | 0.20 | -0.01 | ±20% / ±0.04 ms | 13.1% | moderate | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.20 | 0.20 | -0.01 | ±20% / ±0.04 ms | 13.1% | moderate | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.12 | 0.12 | +0.00 | ±23% / ±0.03 ms | 15.3% | moderate | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.12 | 0.12 | +0.00 | ±23% / ±0.03 ms | 15.3% | moderate | ⚪ Within noise |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 16.26 | 20.76 | +4.51 | ±10% / ±2.08 ms | 1.0% | stable | 🔴 Regression (+28%) |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 16.26 | 20.76 | +4.51 | ±10% / ±2.08 ms | 1.0% | stable | 🔴 Regression (+28%) |

**Summary:** 16 wins, 2 regressions, 143 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.08 | 0.00 | -0.08 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 0.00 | 0.00 | +0.00 MB | ±3.01 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 0.00 | 3.41 | +3.41 MB | ±2.98 MB | 🔴 Regression (+3.41 MB) |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 0.00 | 0.00 | +0.00 MB | ±5.52 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 0.00 | +0.00 MB | ±2.00 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 4.98 | 0.00 | -4.98 MB | ±5.26 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±0.77 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 5.92 | 7.00 | +1.08 MB | ±5.76 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / resqlite select() | 1.91 | 3.59 | +1.68 MB | ±2.91 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite3 select() | 3.03 | 4.00 | +0.97 MB | ±3.68 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 1.00 | 1.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.06 | 0.06 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.02 | 0.00 | -0.02 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 0 wins, 1 regressions, 14 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 3506 | 3936 | +430 | ±100 | 🔴 More re-emits (+430) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 3414 | 3910 | +496 | ±100 | 🔴 More re-emits (+496) |

**Granularity summary:** 0 fewer-re-emit, 2 more-re-emit, 4 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


