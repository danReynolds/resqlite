# resqlite Benchmark Results

Generated: 2026-04-22T14:24:16.070173

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `state-check-verify`
- Repeats: `5`
- Comparison baseline: `2026-04-22T12-48-04-state-check-2026-04-22.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.011 | 0.014 | 0.001 | 0.001 |
| sqlite3 select() | 0.016 | 0.016 | 0.016 | 0.016 |
| sqlite_async select() | 0.033 | 0.045 | 0.001 | 0.002 |
| drift select() | 0.036 | 0.038 | 0.001 | 0.001 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.050 | 0.075 | 0.009 | 0.011 |
| sqlite3 select() | 0.114 | 0.115 | 0.114 | 0.115 |
| sqlite_async select() | 0.124 | 0.169 | 0.010 | 0.011 |
| drift select() | 0.192 | 0.225 | 0.010 | 0.011 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.368 | 0.386 | 0.084 | 0.085 |
| sqlite3 select() | 1.123 | 1.254 | 1.123 | 1.254 |
| sqlite_async select() | 0.989 | 1.211 | 0.091 | 0.095 |
| drift select() | 1.609 | 2.143 | 0.094 | 0.113 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.989 | 15.290 | 0.891 | 1.528 |
| sqlite3 select() | 15.820 | 21.865 | 15.820 | 21.865 |
| sqlite_async select() | 14.023 | 19.451 | 0.975 | 1.546 |
| drift select() | 26.940 | 40.308 | 1.003 | 1.261 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.032 | 0.033 | 0.016 | 0.016 |
| sqlite3 + jsonEncode | 0.031 | 0.037 | 0.031 | 0.037 |
| sqlite_async + jsonEncode | 0.046 | 0.057 | 0.017 | 0.019 |
| drift + jsonEncode | 0.069 | 0.092 | 0.018 | 0.021 |
| resqlite selectBytes() | 0.012 | 0.027 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.207 | 0.242 | 0.163 | 0.188 |
| sqlite3 + jsonEncode | 0.296 | 0.315 | 0.296 | 0.315 |
| sqlite_async + jsonEncode | 0.432 | 1.808 | 0.191 | 1.177 |
| drift + jsonEncode | 0.345 | 0.826 | 0.162 | 0.613 |
| resqlite selectBytes() | 0.045 | 0.142 | 0.000 | 0.001 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 2.245 | 3.443 | 1.803 | 2.856 |
| sqlite3 + jsonEncode | 3.120 | 6.333 | 3.120 | 6.333 |
| sqlite_async + jsonEncode | 2.864 | 4.111 | 1.668 | 2.023 |
| drift + jsonEncode | 4.081 | 8.077 | 1.678 | 4.103 |
| resqlite selectBytes() | 0.361 | 0.389 | 0.000 | 0.001 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 23.731 | 32.899 | 16.592 | 19.960 |
| sqlite3 + jsonEncode | 30.894 | 50.337 | 30.894 | 50.337 |
| sqlite_async + jsonEncode | 38.217 | 52.090 | 18.112 | 23.104 |
| drift + jsonEncode | 47.234 | 87.497 | 17.831 | 28.574 |
| resqlite selectBytes() | 3.947 | 8.343 | 0.004 | 0.010 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.104 | 0.117 | 0.036 | 0.042 |
| sqlite3 | 0.327 | 0.384 | 0.327 | 0.384 |
| sqlite_async | 0.358 | 0.385 | 0.043 | 0.045 |
| drift | 0.583 | 0.653 | 0.042 | 0.044 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.910 | 0.996 | 0.271 | 0.301 |
| sqlite3 | 3.373 | 4.162 | 3.373 | 4.162 |
| sqlite_async | 2.927 | 3.545 | 0.336 | 0.372 |
| drift | 4.894 | 6.428 | 0.337 | 0.360 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.690 | 5.583 | 0.107 | 0.509 |
| sqlite3 | 1.658 | 2.715 | 1.658 | 2.715 |
| sqlite_async | 1.482 | 2.075 | 0.126 | 0.184 |
| drift | 2.232 | 2.403 | 0.128 | 0.136 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.293 | 0.320 | 0.098 | 0.102 |
| sqlite3 | 0.991 | 1.072 | 0.991 | 1.072 |
| sqlite_async | 0.916 | 1.067 | 0.115 | 0.123 |
| drift | 1.526 | 1.707 | 0.115 | 0.122 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.297 | 0.344 | 0.099 | 0.104 |
| sqlite3 | 0.955 | 1.042 | 0.955 | 1.042 |
| sqlite_async | 0.914 | 1.087 | 0.116 | 0.132 |
| drift | 1.517 | 1.755 | 0.119 | 0.131 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.013 | 0.017 | 0.001 | 0.001 |
| sqlite3 | 0.016 | 0.019 | 0.016 | 0.019 |
| sqlite_async | 0.031 | 0.036 | 0.001 | 0.003 |
| drift | 0.037 | 0.040 | 0.001 | 0.001 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.031 | 0.041 | 0.004 | 0.005 |
| sqlite3 | 0.063 | 0.074 | 0.063 | 0.074 |
| sqlite_async | 0.072 | 0.078 | 0.005 | 0.005 |
| drift | 0.106 | 0.146 | 0.005 | 0.006 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.046 | 0.050 | 0.009 | 0.009 |
| sqlite3 | 0.114 | 0.131 | 0.114 | 0.131 |
| sqlite_async | 0.122 | 0.131 | 0.009 | 0.011 |
| drift | 0.185 | 0.230 | 0.010 | 0.011 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.190 | 0.194 | 0.042 | 0.044 |
| sqlite3 | 0.577 | 0.870 | 0.577 | 0.870 |
| sqlite_async | 0.546 | 0.700 | 0.049 | 0.052 |
| drift | 0.845 | 0.958 | 0.049 | 0.054 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.391 | 0.440 | 0.089 | 0.091 |
| sqlite3 | 1.248 | 2.298 | 1.248 | 2.298 |
| sqlite_async | 1.101 | 1.380 | 0.098 | 0.104 |
| drift | 1.721 | 3.328 | 0.097 | 0.118 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.876 | 1.227 | 0.182 | 0.220 |
| sqlite3 | 2.323 | 3.620 | 2.323 | 3.620 |
| sqlite_async | 2.150 | 2.558 | 0.189 | 0.202 |
| drift | 3.364 | 3.816 | 0.188 | 0.311 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.214 | 5.556 | 0.433 | 0.807 |
| sqlite3 | 5.961 | 8.032 | 5.961 | 8.032 |
| sqlite_async | 5.730 | 6.185 | 0.483 | 0.515 |
| drift | 8.936 | 9.934 | 0.469 | 0.484 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.873 | 13.686 | 0.887 | 1.268 |
| sqlite3 | 16.279 | 21.229 | 16.279 | 21.229 |
| sqlite_async | 12.431 | 13.982 | 0.943 | 0.992 |
| drift | 27.379 | 56.515 | 1.002 | 3.633 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 12.047 | 22.632 | 1.809 | 4.825 |
| sqlite3 | 36.635 | 42.737 | 36.635 | 42.737 |
| sqlite_async | 67.568 | 92.293 | 2.448 | 7.365 |
| drift | 67.596 | 108.699 | 1.946 | 3.966 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.029 | 0.030 | 0.029 | 0.030 |
| sqlite3 + jsonEncode | 0.031 | 0.033 | 0.031 | 0.033 |
| sqlite_async + jsonEncode | 0.051 | 0.052 | 0.051 | 0.052 |
| drift + jsonEncode | 0.076 | 0.097 | 0.076 | 0.097 |
| resqlite selectBytes() | 0.009 | 0.010 | 0.009 | 0.010 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.110 | 0.170 | 0.110 | 0.170 |
| sqlite3 + jsonEncode | 0.144 | 0.260 | 0.144 | 0.260 |
| sqlite_async + jsonEncode | 0.157 | 0.626 | 0.157 | 0.626 |
| drift + jsonEncode | 0.209 | 0.348 | 0.209 | 0.348 |
| resqlite selectBytes() | 0.031 | 0.069 | 0.031 | 0.069 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.205 | 0.259 | 0.205 | 0.259 |
| sqlite3 + jsonEncode | 0.273 | 0.323 | 0.273 | 0.323 |
| sqlite_async + jsonEncode | 0.280 | 0.354 | 0.280 | 0.354 |
| drift + jsonEncode | 0.360 | 0.404 | 0.360 | 0.404 |
| resqlite selectBytes() | 0.047 | 0.068 | 0.047 | 0.068 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.928 | 1.017 | 0.928 | 1.017 |
| sqlite3 + jsonEncode | 1.273 | 1.421 | 1.273 | 1.421 |
| sqlite_async + jsonEncode | 1.416 | 1.973 | 1.416 | 1.973 |
| drift + jsonEncode | 1.775 | 3.881 | 1.775 | 3.881 |
| resqlite selectBytes() | 0.191 | 0.663 | 0.191 | 0.663 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 2.135 | 5.367 | 2.135 | 5.367 |
| sqlite3 + jsonEncode | 3.198 | 8.772 | 3.198 | 8.772 |
| sqlite_async + jsonEncode | 2.818 | 13.087 | 2.818 | 13.087 |
| drift + jsonEncode | 4.374 | 14.835 | 4.374 | 14.835 |
| resqlite selectBytes() | 0.373 | 0.490 | 0.373 | 0.490 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 4.016 | 7.731 | 4.016 | 7.731 |
| sqlite3 + jsonEncode | 5.506 | 11.025 | 5.506 | 11.025 |
| sqlite_async + jsonEncode | 6.085 | 11.698 | 6.085 | 11.698 |
| drift + jsonEncode | 9.501 | 29.737 | 9.501 | 29.737 |
| resqlite selectBytes() | 0.789 | 1.260 | 0.789 | 1.260 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 13.698 | 21.812 | 13.698 | 21.812 |
| sqlite3 + jsonEncode | 16.423 | 25.764 | 16.423 | 25.764 |
| sqlite_async + jsonEncode | 15.627 | 23.584 | 15.627 | 23.584 |
| drift + jsonEncode | 24.907 | 65.808 | 24.907 | 65.808 |
| resqlite selectBytes() | 2.298 | 4.759 | 2.298 | 4.759 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 22.713 | 32.340 | 22.713 | 32.340 |
| sqlite3 + jsonEncode | 36.390 | 46.851 | 36.390 | 46.851 |
| sqlite_async + jsonEncode | 38.825 | 58.624 | 38.825 | 58.624 |
| drift + jsonEncode | 42.669 | 50.031 | 42.669 | 50.031 |
| resqlite selectBytes() | 4.129 | 4.682 | 4.129 | 4.682 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 50.838 | 77.576 | 50.838 | 77.576 |
| sqlite3 + jsonEncode | 69.983 | 102.798 | 69.983 | 102.798 |
| sqlite_async + jsonEncode | 75.013 | 86.667 | 75.013 | 86.667 |
| drift + jsonEncode | 97.555 | 187.348 | 97.555 | 187.348 |
| resqlite selectBytes() | 9.006 | 10.383 | 9.006 | 10.383 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.35 | 0.30 |
| sqlite_async | 0.98 | 1.30 | 0.98 |
| drift | 1.64 | 1.76 | 1.64 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.33 | 0.36 | 0.16 |
| sqlite_async | 1.37 | 1.65 | 0.69 |
| drift | 2.97 | 3.51 | 1.49 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.37 | 0.73 | 0.09 |
| sqlite_async | 2.28 | 4.40 | 0.57 |
| drift | 5.58 | 6.40 | 1.40 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.71 | 1.25 | 0.09 |
| sqlite_async | 5.14 | 5.88 | 0.64 |
| drift | 12.73 | 17.17 | 1.59 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each iteration runs 500 sequential queries over 100 iterations per library. 95% CI and MDE values derive from per-iteration QPS samples via percentile bootstrap (deterministic, seed=202440478).

| Metric | Value |
|---|---:|
| resqlite qps | 85070 |
| resqlite per query | 0.012 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 85070 | 74107..90220 | 9.5 | 68.0 |
| sqlite3 | 175408 | 170592..181265 | 3.0 | 19.7 |
| sqlite_async | 43365 | 42629..44071 | 1.7 | 14.0 |
| drift | 34756 | 32906..35957 | 4.4 | 31.0 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 15.946 | 17.982 | 15.946 | 17.982 |
| sqlite_async | 48.141 | 67.517 | 48.141 | 67.517 |
| drift | 62.147 | 86.981 | 62.147 | 86.981 |
| sqlite3 (no cache) | 27.036 | 64.640 | 27.036 | 64.640 |
| sqlite3 (cached stmt) | 37.289 | 65.136 | 37.289 | 65.136 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 3.712 | 39.587 | 3.712 | 39.587 |
| sqlite3 execute() | 9.392 | 118.393 | 9.392 | 118.393 |
| sqlite_async execute() | 14.212 | 35.196 | 14.212 | 35.196 |
| drift execute() | 7.517 | 12.024 | 7.517 | 12.024 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.066 | 0.361 | 0.066 | 0.361 |
| sqlite3 executeBatch() | 0.054 | 0.061 | 0.054 | 0.061 |
| sqlite_async executeBatch() | 0.127 | 0.560 | 0.127 | 0.560 |
| drift executeBatch() | 0.215 | 0.527 | 0.215 | 0.527 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.571 | 1.195 | 0.571 | 1.195 |
| sqlite3 executeBatch() | 0.549 | 1.531 | 0.549 | 1.531 |
| sqlite_async executeBatch() | 0.601 | 1.196 | 0.601 | 1.196 |
| drift executeBatch() | 1.608 | 4.060 | 1.608 | 4.060 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.836 | 7.245 | 4.836 | 7.245 |
| sqlite3 executeBatch() | 4.488 | 5.797 | 4.488 | 5.797 |
| sqlite_async executeBatch() | 6.381 | 8.306 | 6.381 | 8.306 |
| drift executeBatch() | 7.732 | 10.735 | 7.732 | 10.735 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.060 | 0.119 | 0.060 | 0.119 |
| sqlite_async writeTransaction() | 0.113 | 0.161 | 0.113 | 0.161 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.081 | 0.126 | 0.081 | 0.126 |
| resqlite tx.execute() loop | 0.969 | 1.157 | 0.969 | 1.157 |
| sqlite_async tx.execute() loop | 1.456 | 1.958 | 1.456 | 1.958 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.519 | 0.835 | 0.519 | 0.835 |
| resqlite tx.execute() loop | 9.449 | 16.622 | 9.449 | 16.622 |
| sqlite_async tx.execute() loop | 23.954 | 57.896 | 23.954 | 57.896 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.217 | 0.637 | 0.217 | 0.637 |
| sqlite_async tx.getAll() | 0.563 | 2.423 | 0.563 | 2.423 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.210 | 0.710 | 0.210 | 0.710 |
| sqlite_async tx.getAll() | 0.414 | 2.467 | 0.414 | 2.467 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.034 | 0.517 | 0.034 | 0.517 |
| sqlite_async watch() | 0.115 | 0.615 | 0.115 | 0.615 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.045 | 0.203 | 0.045 | 0.203 |
| sqlite_async | 0.084 | 1.096 | 0.084 | 1.096 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.651 | 4.506 | 0.651 | 4.506 |
| sqlite_async | 3.045 | 9.737 | 3.045 | 9.737 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.653 | 1.844 | 0.653 | 1.844 |
| sqlite_async | 0.819 | 1.382 | 0.819 | 1.382 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.071 | 2.071 | 2.071 | 2.071 |
| sqlite_async | 11.270 | 11.270 | 11.270 | 11.270 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.073 | 5.184 | 4.073 | 5.184 |
| sqlite_async | 7.990 | 12.852 | 7.990 | 12.852 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.517 | 0.726 | 0.517 | 0.726 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 8.798 | 19.427 | 8.798 | 19.427 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. On resqlite's main branch this ratio is driven toward 0 by experiment 075 (C-side result-hash short-circuit), not by writer-side column-tracking (exp 052 is not implemented). The two mechanisms are indistinguishable on this read-side benchmark.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 80.0 | 0.000 |
| sqlite_async | 3250 | 943.6 | 1.080 |
| drift | 5000 | 1175.4 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 20 | 88.2 | 0.000 |
| sqlite_async | 3009 | 1093.3 | 1.080 |
| drift | 5000 | 1381.6 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 219.84 | 221.50 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 452.07 | 456.11 | 0.03 | 0.04 | 1163 | 3 |
| drift stream() | 572.88 | 627.11 | 0.01 | 0.10 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.029 | 0.052 | 0.000 | 0.000 |
| sqlite3 | 0.021 | 0.032 | 0.021 | 0.032 |
| sqlite_async | 0.048 | 0.090 | 0.000 | 0.000 |
| drift | 0.041 | 0.069 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.021 | 0.040 | 0.000 | 0.000 |
| sqlite3 | 0.014 | 0.018 | 0.014 | 0.018 |
| sqlite_async | 0.038 | 0.070 | 0.000 | 0.000 |
| drift | 0.032 | 0.047 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.030 | 0.045 | 0.000 | 0.000 |
| sqlite3 | 0.032 | 0.035 | 0.032 | 0.035 |
| sqlite_async | 0.059 | 0.079 | 0.000 | 0.000 |
| drift | 0.055 | 0.067 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.011 | 0.023 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.022 | 0.031 | 0.000 | 0.000 |
| drift | 0.021 | 0.030 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.041 | 0.048 | 0.001 | 0.002 |
| sqlite3 | 0.066 | 0.070 | 0.066 | 0.070 |
| sqlite_async | 0.081 | 0.108 | 0.001 | 0.002 |
| drift | 0.093 | 0.122 | 0.001 | 0.002 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 108.724 | 110.689 | 0.000 | 0.000 | 0 |
| sqlite_async | 220.328 | 220.569 | 0.000 | 0.000 | 47 |
| drift | 231.700 | 232.256 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 239.34 | 239.34 | 0.00 | 0.00 | 12.08 | 227.51 | 0 |
| sqlite_async | 484.71 | 484.71 | 0.00 | 0.00 | 23.48 | 461.23 | 1191 |
| drift | 1889.24 | 1889.24 | 0.10 | 0.10 | 13.63 | 1876.58 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 0.86 | 9.84 | 0.00..4.52 | ±2.26 |
| sqlite3 select() | 3.86 | 9.73 | 2.84..8.98 | ±3.07 |
| sqlite_async select() | 1.00 | 1.53 | 0.97..1.02 | ±0.02 |
| drift select() | 11.77 | 74.53 | 0.00..19.02 | ±9.51 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 8.00 | 0.00..8.00 | ±4.00 |
| resqlite + jsonEncode | 0.00 | 57.83 | 0.00..36.88 | ±18.44 |
| sqlite3 + jsonEncode | 0.00 | 25.91 | 0.00..8.73 | ±4.37 |
| sqlite_async + jsonEncode | 0.00 | 33.05 | 0.00..12.09 | ±6.05 |
| drift + jsonEncode | 0.00 | 88.05 | 0.00..68.64 | ±34.32 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 1.72 | 12.50 | 0.00..3.33 | ±1.66 |
| sqlite3 executeBatch() | 0.00 | 0.02 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 0.25 | 0.00..0.00 | ±0.00 |
| drift batch() | 0.09 | 4.58 | 0.00..2.52 | ±1.26 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.11 | 0.17 | 0.00..0.14 | ±0.07 |
| sqlite_async watch() | 0.00 | 0.50 | 0.00..0.02 | ±0.01 |

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

| Benchmark | Median (ms) | Min | Max | Range | MAD | Stability |
|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.03 | 0.03 | 0.03 | 14.3% | 7.1% | moderate |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | 0.01 | 20.0% | 10.0% | noisy |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.03 | 0.02 | 0.03 | 23.1% | 7.7% | moderate |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02 | 0.02 | 26.3% | 10.5% | noisy |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.30 | 0.30 | 0.31 | 3.3% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.30 | 0.30 | 0.31 | 3.3% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.34 | 0.31 | 1.20 | 261.8% | 2.9% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.17 | 0.15 | 0.60 | 264.7% | 5.9% | moderate |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.40 | 0.37 | 1.56 | 297.5% | 7.5% | moderate |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.10 | 0.09 | 0.39 | 300.0% | 10.0% | noisy |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.72 | 0.71 | 0.75 | 5.6% | 1.4% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.09 | 0.09 | 0.09 | 0.0% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04 | 0.04 | 9.8% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00 | 0.00 | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 108.72 | 106.01 | 109.58 | 3.3% | 0.8% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 236.77 | 230.56 | 241.07 | 4.4% | 1.1% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 220.42 | 219.84 | 228.48 | 3.9% | 0.3% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 15.27 | 14.85 | 15.95 | 7.2% | 2.4% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 15.27 | 14.85 | 15.95 | 7.2% | 2.4% | stable |
| Point Query Throughput / resqlite qps | 112841.00 | 85070.00 | 117178.00 | 28.5% | 3.8% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01 | 0.02 | 53.8% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | 0.04 | 37.9% | 6.9% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03 | 0.04 | 37.9% | 6.9% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | 0.00 | 100.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | 0.01 | 41.7% | 8.3% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01 | 0.01 | 41.7% | 8.3% | noisy |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05 | 0.05 | 16.3% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.20 | 0.20 | 0.20 | 4.5% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.20 | 0.20 | 0.20 | 4.5% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | 0.01 | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.05 | 0.04 | 0.06 | 26.1% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.05 | 0.04 | 0.06 | 26.1% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.39 | 0.39 | 0.40 | 2.6% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 2.01 | 1.86 | 2.14 | 13.9% | 6.2% | moderate |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 2.01 | 1.86 | 2.14 | 13.9% | 6.2% | moderate |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09 | 0.09 | 1.1% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.37 | 0.36 | 0.58 | 58.7% | 1.3% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.37 | 0.36 | 0.58 | 58.7% | 1.3% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 5.44 | 4.69 | 9.57 | 89.6% | 13.7% | noisy |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 24.20 | 22.50 | 26.00 | 14.5% | 6.2% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 24.20 | 22.50 | 26.00 | 14.5% | 6.2% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.89 | 0.86 | 1.07 | 23.0% | 2.7% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 4.16 | 4.09 | 5.60 | 36.4% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 4.16 | 4.09 | 5.60 | 36.4% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.88 | 0.81 | 1.00 | 21.7% | 5.5% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 4.02 | 3.82 | 4.46 | 15.9% | 2.9% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 4.02 | 3.82 | 4.46 | 15.9% | 2.9% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.18 | 0.18 | 0.18 | 2.8% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.88 | 0.79 | 1.01 | 25.6% | 10.3% | noisy |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.88 | 0.79 | 1.01 | 25.6% | 10.3% | noisy |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 12.06 | 11.55 | 16.08 | 37.6% | 4.2% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 47.08 | 46.28 | 50.84 | 9.7% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 47.08 | 46.28 | 50.84 | 9.7% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.78 | 1.76 | 1.81 | 2.8% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 8.48 | 8.28 | 10.55 | 26.7% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 8.48 | 8.28 | 10.55 | 26.7% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03 | 0.03 | 16.1% | 3.2% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.11 | 0.11 | 7.5% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.11 | 0.11 | 0.11 | 7.5% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00 | 0.01 | 25.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.03 | 0.03 | 17.9% | 7.1% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.03 | 0.03 | 17.9% | 7.1% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.20 | 0.19 | 0.20 | 5.5% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.94 | 0.90 | 1.04 | 15.0% | 4.1% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.94 | 0.90 | 1.04 | 15.0% | 4.1% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04 | 0.04 | 4.5% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.19 | 0.18 | 0.24 | 32.6% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.19 | 0.18 | 0.24 | 32.6% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.24 | 2.19 | 2.67 | 21.2% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 13.70 | 10.69 | 30.95 | 147.9% | 19.8% | noisy |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 13.70 | 10.69 | 30.95 | 147.9% | 19.8% | noisy |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.43 | 0.43 | 0.46 | 6.7% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 2.30 | 1.94 | 5.18 | 140.9% | 13.4% | noisy |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 2.30 | 1.94 | 5.18 | 140.9% | 13.4% | noisy |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.10 | 0.10 | 0.23 | 122.1% | 1.0% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.04 | 0.04 | 0.09 | 161.1% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.31 | 0.30 | 0.33 | 9.4% | 2.9% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.10 | 0.10 | 0.10 | 4.0% | 2.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.31 | 0.29 | 0.41 | 37.5% | 5.2% | moderate |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.10 | 0.10 | 0.11 | 8.7% | 3.9% | moderate |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.57 | 0.54 | 0.69 | 26.4% | 5.9% | moderate |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.10 | 0.10 | 0.11 | 4.9% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.90 | 0.89 | 0.92 | 2.8% | 0.7% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.27 | 0.27 | 0.27 | 2.2% | 0.7% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | 0.14 | 357.6% | 3.0% | moderate |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02 | 0.10 | 556.3% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | 0.02 | 108.3% | 8.3% | noisy |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.21 | 0.20 | 0.24 | 15.5% | 1.4% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.16 | 0.16 | 0.18 | 14.7% | 1.8% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.04 | 0.06 | 21.3% | 4.3% | moderate |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 2.19 | 1.93 | 2.47 | 24.3% | 10.4% | noisy |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.59 | 1.57 | 1.93 | 22.2% | 1.2% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.37 | 0.36 | 0.50 | 37.5% | 1.9% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 23.73 | 21.21 | 32.82 | 48.9% | 10.6% | noisy |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 16.59 | 15.42 | 21.11 | 34.3% | 7.0% | moderate |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 4.06 | 3.92 | 5.16 | 30.6% | 2.9% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.01 | 75.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | 0.09 | 675.0% | 8.3% | noisy |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | 0.02 | 2100.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.05 | 0.21 | 346.8% | 2.1% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | 0.01 | 33.3% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.38 | 0.37 | 0.44 | 18.4% | 1.9% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.08 | 0.09 | 14.1% | 1.2% | stable |
| Select → Maps / 10000 rows / resqlite select() | 4.83 | 4.43 | 8.33 | 80.5% | 3.2% | moderate |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.89 | 0.70 | 1.03 | 37.5% | 0.9% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.29 | 0.23 | 0.65 | 146.5% | 18.2% | noisy |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.29 | 0.23 | 0.65 | 146.5% | 18.2% | noisy |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.58 | 0.52 | 0.60 | 14.9% | 2.9% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.58 | 0.52 | 0.60 | 14.9% | 2.9% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | 0.04 | 35.3% | 5.9% | moderate |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03 | 0.04 | 35.3% | 5.9% | moderate |
| Streaming / Invalidation Latency / resqlite | 0.06 | 0.04 | 0.06 | 28.3% | 1.7% | stable |
| Streaming / Invalidation Latency / resqlite [main] | 0.06 | 0.04 | 0.06 | 28.3% | 1.7% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 4.07 | 3.68 | 4.77 | 26.9% | 9.7% | noisy |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 4.07 | 3.68 | 4.77 | 26.9% | 9.7% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.82 | 1.42 | 3.22 | 98.6% | 13.6% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.82 | 1.42 | 3.22 | 98.6% | 13.6% | noisy |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 8.29 | 7.78 | 8.94 | 14.0% | 6.1% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 8.29 | 7.78 | 8.94 | 14.0% | 6.1% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.23 | 0.20 | 0.65 | 191.0% | 10.7% | noisy |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.23 | 0.20 | 0.65 | 191.0% | 10.7% | noisy |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.06 | 0.07 | 16.1% | 6.5% | moderate |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.06 | 0.06 | 0.07 | 16.1% | 6.5% | moderate |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.47 | 0.43 | 0.57 | 28.6% | 8.4% | noisy |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.47 | 0.43 | 0.57 | 28.6% | 8.4% | noisy |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.84 | 4.50 | 5.59 | 22.4% | 6.9% | moderate |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.84 | 4.50 | 5.59 | 22.4% | 6.9% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.92 | 0.62 | 1.07 | 48.4% | 4.9% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.92 | 0.62 | 1.07 | 48.4% | 4.9% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.09 | 0.08 | 0.09 | 11.5% | 1.1% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.09 | 0.08 | 0.09 | 11.5% | 1.1% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 8.14 | 7.64 | 11.52 | 47.7% | 6.2% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 8.14 | 7.64 | 11.52 | 47.7% | 6.2% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.52 | 0.49 | 1.08 | 114.8% | 5.2% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.52 | 0.49 | 1.08 | 114.8% | 5.2% | moderate |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.06 | 0.05 | 0.20 | 238.3% | 13.3% | noisy |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.06 | 0.05 | 0.20 | 238.3% | 13.3% | noisy |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 2.10 | 1.99 | 3.71 | 82.0% | 3.2% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 2.10 | 1.99 | 3.71 | 82.0% | 3.2% | moderate |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.20 | 0.19 | 0.21 | 11.3% | 3.4% | moderate |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.20 | 0.19 | 0.21 | 11.3% | 3.4% | moderate |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.12 | 0.10 | 0.22 | 96.6% | 3.4% | moderate |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.12 | 0.10 | 0.22 | 96.6% | 3.4% | moderate |


## Comparison vs Previous Run

Previous: `2026-04-22T12-48-04-state-check-2026-04-22.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Noise threshold | Stability | Status |
|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.03 | 0.03 | +0.00 | ±21% / ±0.02 ms | moderate | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | +0.00 | ±30% / ±0.02 ms | noisy | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.03 | +0.01 | ±23% / ±0.02 ms | moderate | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.02 | +0.00 | ±32% / ±0.02 ms | noisy | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.28 | 0.30 | +0.02 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.28 | 0.30 | +0.02 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.30 | 0.34 | +0.04 | ±10% / ±0.03 ms | stable | 🔴 Regression (+13%) |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.15 | 0.17 | +0.02 | ±18% / ±0.03 ms | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.37 | 0.40 | +0.03 | ±23% / ±0.09 ms | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.09 | 0.10 | +0.01 | ±30% / ±0.03 ms | noisy | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.92 | 0.72 | -0.20 | ±10% / ±0.09 ms | stable | 🟢 Win (-22%) |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.12 | 0.09 | -0.03 | ±10% / ±0.02 ms | stable | 🟢 Win (-25%) |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 108.04 | 108.72 | +0.69 | ±10% / ±10.87 ms | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 439.56 | 236.77 | -202.79 | ±10% / ±43.96 ms | stable | 🟢 Win (-46%) |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 225.78 | 220.42 | -5.36 | ±10% / ±22.58 ms | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 13.90 | 15.27 | +1.37 | ±10% / ±1.53 ms | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 13.90 | 15.27 | +1.37 | ±10% / ±1.53 ms | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 143493.00 | 112841.00 | -30652.00 | ±12% / ±16545.29 ms | moderate | 🔴 Regression (-21%) |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±21% / ±0.02 ms | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.03 | +0.00 | ±21% / ±0.02 ms | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±25% / ±0.02 ms | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±25% / ±0.02 ms | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.20 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.20 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.05 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.05 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.38 | 0.39 | +0.01 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.85 | 2.01 | +0.16 | ±19% / ±0.38 ms | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.85 | 2.01 | +0.16 | ±19% / ±0.38 ms | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09 | -0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.36 | 0.37 | +0.01 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.36 | 0.37 | +0.01 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.18 | 5.44 | +1.26 | ±41% / ±2.24 ms | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 21.32 | 24.20 | +2.88 | ±18% / ±4.47 ms | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 21.32 | 24.20 | +2.88 | ±18% / ±4.47 ms | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.84 | 0.89 | +0.05 | ±10% / ±0.09 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 4.41 | 4.16 | -0.25 | ±10% / ±0.44 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 4.41 | 4.16 | -0.25 | ±10% / ±0.44 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.85 | 0.88 | +0.02 | ±16% / ±0.14 ms | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.87 | 4.02 | +0.15 | ±10% / ±0.40 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.87 | 4.02 | +0.15 | ±10% / ±0.40 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.18 | 0.18 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.81 | 0.88 | +0.07 | ±31% / ±0.27 ms | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.81 | 0.88 | +0.07 | ±31% / ±0.27 ms | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.60 | 12.06 | +1.46 | ±13% / ±1.52 ms | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 42.34 | 47.08 | +4.74 | ±10% / ±4.71 ms | stable | 🔴 Regression (+11%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 42.34 | 47.08 | +4.74 | ±10% / ±4.71 ms | stable | 🔴 Regression (+11%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.69 | 1.78 | +0.09 | ±10% / ±0.18 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.60 | 8.48 | -0.12 | ±10% / ±0.86 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.60 | 8.48 | -0.12 | ±10% / ±0.86 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.11 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.10 | 0.11 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.03 | +0.00 | ±21% / ±0.02 ms | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.03 | +0.00 | ±21% / ±0.02 ms | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.20 | 0.20 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.94 | 0.94 | -0.00 | ±12% / ±0.11 ms | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.94 | 0.94 | -0.00 | ±12% / ±0.11 ms | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.19 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.19 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.03 | 2.24 | +0.21 | ±10% / ±0.22 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.60 | 13.70 | +3.10 | ±59% / ±8.12 ms | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.60 | 13.70 | +3.10 | ±59% / ±8.12 ms | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.42 | 0.43 | +0.02 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.94 | 2.30 | +0.36 | ±40% / ±0.92 ms | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.94 | 2.30 | +0.36 | ±40% / ±0.92 ms | noisy | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.10 | 0.10 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.29 | 0.31 | +0.02 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.28 | 0.31 | +0.03 | ±16% / ±0.05 ms | moderate | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.10 | 0.10 | +0.00 | ±12% / ±0.02 ms | moderate | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.51 | 0.57 | +0.06 | ±18% / ±0.10 ms | moderate | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.87 | 0.90 | +0.03 | ±10% / ±0.09 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.27 | 0.27 | +0.00 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | +0.00 | ±25% / ±0.02 ms | noisy | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.21 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.16 | 0.16 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.05 | +0.00 | ±13% / ±0.02 ms | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.91 | 2.19 | +0.28 | ±31% / ±0.69 ms | noisy | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.55 | 1.59 | +0.04 | ±10% / ±0.16 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.35 | 0.37 | +0.02 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 23.15 | 23.73 | +0.58 | ±32% / ±7.58 ms | noisy | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 14.88 | 16.59 | +1.72 | ±21% / ±3.50 ms | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.82 | 4.06 | +0.24 | ±10% / ±0.41 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | +0.00 | ±25% / ±0.02 ms | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.38 | 0.38 | +0.00 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.09 | -0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 4.49 | 4.83 | +0.34 | ±10% / ±0.48 ms | moderate | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.88 | 0.89 | +0.01 | ±10% / ±0.09 ms | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.22 | 0.29 | +0.07 | ±55% / ±0.16 ms | noisy | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.22 | 0.29 | +0.07 | ±55% / ±0.16 ms | noisy | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.59 | 0.58 | -0.01 | ±10% / ±0.06 ms | stable | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.59 | 0.58 | -0.01 | ±10% / ±0.06 ms | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | +0.00 | ±18% / ±0.02 ms | moderate | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03 | +0.00 | ±18% / ±0.02 ms | moderate | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.66 | 4.07 | +0.42 | ±29% / ±1.19 ms | noisy | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.66 | 4.07 | +0.42 | ±29% / ±1.19 ms | noisy | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.06 | 1.82 | -0.24 | ±41% / ±0.84 ms | noisy | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.06 | 1.82 | -0.24 | ±41% / ±0.84 ms | noisy | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 7.82 | 8.29 | +0.47 | ±18% / ±1.51 ms | moderate | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 7.82 | 8.29 | +0.47 | ±18% / ±1.51 ms | moderate | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.19 | 0.23 | +0.04 | ±32% / ±0.08 ms | noisy | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.19 | 0.23 | +0.04 | ±32% / ±0.08 ms | noisy | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | +0.00 | ±19% / ±0.02 ms | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | +0.00 | ±19% / ±0.02 ms | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.46 | 0.47 | +0.02 | ±25% / ±0.12 ms | noisy | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.46 | 0.47 | +0.02 | ±25% / ±0.12 ms | noisy | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.43 | 4.84 | +0.40 | ±21% / ±1.00 ms | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.43 | 4.84 | +0.40 | ±21% / ±1.00 ms | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.63 | 0.92 | +0.30 | ±15% / ±0.13 ms | moderate | 🔴 Regression (+47%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.63 | 0.92 | +0.30 | ±15% / ±0.13 ms | moderate | 🔴 Regression (+47%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.09 | +0.02 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.09 | +0.02 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 5.50 | 8.14 | +2.64 | ±19% / ±1.51 ms | moderate | 🔴 Regression (+48%) |
| Write Performance / Batched Write Inside Transaction (100... | 5.50 | 8.14 | +2.64 | ±19% / ±1.51 ms | moderate | 🔴 Regression (+48%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.43 | 0.52 | +0.09 | ±16% / ±0.08 ms | moderate | 🔴 Regression (+20%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.43 | 0.52 | +0.09 | ±16% / ±0.08 ms | moderate | 🔴 Regression (+20%) |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.06 | +0.01 | ±40% / ±0.02 ms | noisy | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.06 | +0.01 | ±40% / ±0.02 ms | noisy | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.66 | 2.10 | +0.44 | ±10% / ±0.21 ms | moderate | 🔴 Regression (+26%) |
| Write Performance / Single Inserts (100 sequential) / res... | 1.66 | 2.10 | +0.44 | ±10% / ±0.21 ms | moderate | 🔴 Regression (+26%) |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.20 | +0.02 | ±10% / ±0.02 ms | moderate | 🔴 Regression (+12%) |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.20 | +0.02 | ±10% / ±0.02 ms | moderate | 🔴 Regression (+12%) |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.12 | +0.01 | ±10% / ±0.02 ms | moderate | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.12 | +0.01 | ±10% / ±0.02 ms | moderate | ⚪ Within noise |

**Summary:** 3 wins, 14 regressions, 136 neutral

Comparison threshold uses `max(10%, 3 × current MAD%)`, plus an absolute floor of `±0.02 ms`.
That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.00 | 0.09 | +0.09 MB | ±1.26 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 0.00 | 1.72 | +1.72 MB | ±1.66 MB | 🔴 Regression (+1.72 MB) |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 5.39 | 0.00 | -5.39 MB | ±34.32 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 0.00 | 0.00 | +0.00 MB | ±18.44 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 2.00 | 0.00 | -2.00 MB | ±4.00 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 0.00 | 0.00 | +0.00 MB | ±4.37 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±6.05 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 6.05 | 11.77 | +5.72 MB | ±9.51 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / resqlite select() | 5.25 | 0.86 | -4.39 MB | ±2.26 MB | 🟢 Win (-4.39 MB) |
| Memory / Select 10k rows → Maps / sqlite3 select() | 2.34 | 3.86 | +1.52 MB | ±3.07 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 1.00 | 1.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.06 | 0.11 | +0.05 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 1 wins, 1 regressions, 13 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 4142 | 3250 | -892 | ±100 | 🟢 Fewer re-emits (-892) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 20 | +10 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 3249 | 3009 | -240 | ±100 | 🔴 Invalidation elided (-240) — writes not firing |

**Granularity summary:** 1 fewer-re-emit, 1 more-re-emit, 4 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


