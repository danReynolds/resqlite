# resqlite Benchmark Results

Generated: 2026-04-23T19:19:25.240869

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp095-writer-result-buffer`
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
| resqlite select() | 0.016 | 0.026 | 0.001 | 0.002 |
| sqlite3 select() | 0.016 | 0.017 | 0.016 | 0.017 |
| sqlite_async select() | 0.030 | 0.034 | 0.001 | 0.001 |
| drift select() | 0.053 | 0.066 | 0.001 | 0.002 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.049 | 0.054 | 0.009 | 0.009 |
| sqlite3 select() | 0.117 | 0.120 | 0.117 | 0.120 |
| sqlite_async select() | 0.123 | 0.128 | 0.010 | 0.010 |
| drift select() | 0.187 | 0.231 | 0.010 | 0.013 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.371 | 0.394 | 0.086 | 0.090 |
| sqlite3 select() | 1.083 | 1.190 | 1.083 | 1.190 |
| sqlite_async select() | 0.984 | 1.061 | 0.091 | 0.095 |
| drift select() | 1.642 | 1.865 | 0.095 | 0.100 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.504 | 9.807 | 0.869 | 1.186 |
| sqlite3 select() | 14.956 | 18.629 | 14.956 | 18.629 |
| sqlite_async select() | 12.495 | 18.057 | 0.957 | 2.351 |
| drift select() | 21.148 | 31.958 | 0.945 | 2.217 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.027 | 0.031 | 0.016 | 0.017 |
| sqlite3 + jsonEncode | 0.031 | 0.032 | 0.031 | 0.032 |
| sqlite_async + jsonEncode | 0.045 | 0.047 | 0.016 | 0.017 |
| drift + jsonEncode | 0.052 | 0.062 | 0.016 | 0.017 |
| resqlite selectBytes() | 0.012 | 0.013 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.197 | 0.200 | 0.158 | 0.160 |
| sqlite3 + jsonEncode | 0.270 | 0.422 | 0.270 | 0.422 |
| sqlite_async + jsonEncode | 0.281 | 0.324 | 0.159 | 0.175 |
| drift + jsonEncode | 0.489 | 0.816 | 0.178 | 0.359 |
| resqlite selectBytes() | 0.050 | 0.060 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.862 | 3.991 | 1.544 | 3.297 |
| sqlite3 + jsonEncode | 2.462 | 2.926 | 2.462 | 2.926 |
| sqlite_async + jsonEncode | 2.398 | 4.154 | 1.470 | 2.078 |
| drift + jsonEncode | 3.225 | 5.702 | 1.547 | 2.071 |
| resqlite selectBytes() | 0.372 | 0.411 | 0.000 | 0.001 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.295 | 24.220 | 15.185 | 17.948 |
| sqlite3 + jsonEncode | 32.062 | 36.365 | 32.062 | 36.365 |
| sqlite_async + jsonEncode | 29.926 | 35.398 | 15.693 | 16.872 |
| drift + jsonEncode | 38.767 | 47.591 | 15.653 | 18.029 |
| resqlite selectBytes() | 3.611 | 3.819 | 0.000 | 0.002 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.101 | 0.111 | 0.038 | 0.044 |
| sqlite3 | 0.319 | 0.324 | 0.319 | 0.324 |
| sqlite_async | 0.351 | 0.358 | 0.041 | 0.043 |
| drift | 0.570 | 0.577 | 0.041 | 0.042 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.972 | 1.011 | 0.347 | 0.354 |
| sqlite3 | 3.300 | 3.664 | 3.300 | 3.664 |
| sqlite_async | 2.804 | 3.161 | 0.319 | 0.326 |
| drift | 4.868 | 6.342 | 0.335 | 0.348 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.580 | 1.747 | 0.132 | 0.140 |
| sqlite3 | 1.452 | 1.639 | 1.452 | 1.639 |
| sqlite_async | 1.362 | 1.623 | 0.116 | 0.123 |
| drift | 1.945 | 2.296 | 0.114 | 0.121 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.319 | 0.415 | 0.126 | 0.133 |
| sqlite3 | 0.967 | 0.997 | 0.967 | 0.997 |
| sqlite_async | 0.890 | 0.916 | 0.113 | 0.116 |
| drift | 1.472 | 1.630 | 0.115 | 0.118 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.326 | 0.361 | 0.123 | 0.136 |
| sqlite3 | 0.955 | 1.052 | 0.955 | 1.052 |
| sqlite_async | 0.947 | 1.065 | 0.120 | 0.132 |
| drift | 1.531 | 2.085 | 0.118 | 0.127 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.014 | 0.028 | 0.001 | 0.002 |
| sqlite3 | 0.016 | 0.019 | 0.016 | 0.019 |
| sqlite_async | 0.032 | 0.050 | 0.001 | 0.003 |
| drift | 0.048 | 0.075 | 0.001 | 0.003 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.028 | 0.029 | 0.004 | 0.004 |
| sqlite3 | 0.062 | 0.063 | 0.062 | 0.063 |
| sqlite_async | 0.074 | 0.076 | 0.005 | 0.005 |
| drift | 0.122 | 0.134 | 0.005 | 0.006 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.052 | 0.058 | 0.009 | 0.010 |
| sqlite3 | 0.120 | 0.132 | 0.120 | 0.132 |
| sqlite_async | 0.122 | 0.125 | 0.010 | 0.010 |
| drift | 0.208 | 0.219 | 0.010 | 0.011 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.197 | 0.243 | 0.044 | 0.047 |
| sqlite3 | 0.550 | 0.598 | 0.550 | 0.598 |
| sqlite_async | 0.531 | 0.639 | 0.048 | 0.060 |
| drift | 0.811 | 0.837 | 0.047 | 0.048 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.382 | 0.406 | 0.088 | 0.090 |
| sqlite3 | 1.134 | 1.236 | 1.134 | 1.236 |
| sqlite_async | 1.054 | 1.103 | 0.096 | 0.101 |
| drift | 1.607 | 1.873 | 0.092 | 0.099 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.845 | 1.075 | 0.178 | 0.188 |
| sqlite3 | 2.258 | 2.809 | 2.258 | 2.809 |
| sqlite_async | 2.042 | 2.537 | 0.187 | 0.200 |
| drift | 3.261 | 3.827 | 0.187 | 0.206 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.213 | 6.090 | 0.445 | 0.665 |
| sqlite3 | 5.590 | 7.488 | 5.590 | 7.488 |
| sqlite_async | 5.289 | 7.014 | 0.463 | 0.485 |
| drift | 8.676 | 9.588 | 0.469 | 0.488 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.514 | 12.392 | 0.871 | 0.922 |
| sqlite3 | 15.436 | 18.523 | 15.436 | 18.523 |
| sqlite_async | 12.915 | 16.921 | 0.953 | 1.539 |
| drift | 21.974 | 27.702 | 0.939 | 2.349 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 10.564 | 17.490 | 1.696 | 1.782 |
| sqlite3 | 31.027 | 43.735 | 31.027 | 43.735 |
| sqlite_async | 35.672 | 47.490 | 1.868 | 4.161 |
| drift | 48.127 | 65.797 | 1.871 | 6.073 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.027 | 0.029 | 0.027 | 0.029 |
| sqlite3 + jsonEncode | 0.031 | 0.032 | 0.031 | 0.032 |
| sqlite_async + jsonEncode | 0.045 | 0.047 | 0.045 | 0.047 |
| drift + jsonEncode | 0.053 | 0.056 | 0.053 | 0.056 |
| resqlite selectBytes() | 0.011 | 0.012 | 0.011 | 0.012 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.109 | 0.119 | 0.109 | 0.119 |
| sqlite3 + jsonEncode | 0.134 | 0.148 | 0.134 | 0.148 |
| sqlite_async + jsonEncode | 0.140 | 0.143 | 0.140 | 0.143 |
| drift + jsonEncode | 0.170 | 0.176 | 0.170 | 0.176 |
| resqlite selectBytes() | 0.026 | 0.029 | 0.026 | 0.029 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.211 | 0.224 | 0.211 | 0.224 |
| sqlite3 + jsonEncode | 0.255 | 0.264 | 0.255 | 0.264 |
| sqlite_async + jsonEncode | 0.266 | 0.270 | 0.266 | 0.270 |
| drift + jsonEncode | 0.319 | 0.331 | 0.319 | 0.331 |
| resqlite selectBytes() | 0.043 | 0.044 | 0.043 | 0.044 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.936 | 1.605 | 0.936 | 1.605 |
| sqlite3 + jsonEncode | 1.317 | 2.841 | 1.317 | 2.841 |
| sqlite_async + jsonEncode | 1.394 | 4.753 | 1.394 | 4.753 |
| drift + jsonEncode | 1.598 | 5.132 | 1.598 | 5.132 |
| resqlite selectBytes() | 0.189 | 0.247 | 0.189 | 0.247 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.861 | 4.135 | 1.861 | 4.135 |
| sqlite3 + jsonEncode | 2.510 | 4.683 | 2.510 | 4.683 |
| sqlite_async + jsonEncode | 2.379 | 3.407 | 2.379 | 3.407 |
| drift + jsonEncode | 2.951 | 3.234 | 2.951 | 3.234 |
| resqlite selectBytes() | 0.351 | 0.359 | 0.351 | 0.359 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 4.175 | 7.675 | 4.175 | 7.675 |
| sqlite3 + jsonEncode | 5.387 | 9.390 | 5.387 | 9.390 |
| sqlite_async + jsonEncode | 5.339 | 9.748 | 5.339 | 9.748 |
| drift + jsonEncode | 6.278 | 11.614 | 6.278 | 11.614 |
| resqlite selectBytes() | 0.747 | 0.968 | 0.747 | 0.968 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 10.066 | 12.884 | 10.066 | 12.884 |
| sqlite3 + jsonEncode | 15.047 | 22.083 | 15.047 | 22.083 |
| sqlite_async + jsonEncode | 13.715 | 21.422 | 13.715 | 21.422 |
| drift + jsonEncode | 17.749 | 21.244 | 17.749 | 21.244 |
| resqlite selectBytes() | 1.820 | 3.508 | 1.820 | 3.508 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 22.013 | 27.944 | 22.013 | 27.944 |
| sqlite3 + jsonEncode | 28.555 | 34.181 | 28.555 | 34.181 |
| sqlite_async + jsonEncode | 32.291 | 37.085 | 32.291 | 37.085 |
| drift + jsonEncode | 37.922 | 44.557 | 37.922 | 44.557 |
| resqlite selectBytes() | 4.204 | 7.304 | 4.204 | 7.304 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 42.052 | 49.316 | 42.052 | 49.316 |
| sqlite3 + jsonEncode | 64.820 | 75.479 | 64.820 | 75.479 |
| sqlite_async + jsonEncode | 69.848 | 99.043 | 69.848 | 99.043 |
| drift + jsonEncode | 84.189 | 106.956 | 84.189 | 106.956 |
| resqlite selectBytes() | 7.704 | 11.400 | 7.704 | 11.400 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.29 | 0.31 | 0.29 |
| sqlite_async | 0.91 | 1.07 | 0.91 |
| drift | 1.54 | 1.75 | 1.54 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.31 | 0.45 | 0.16 |
| sqlite_async | 1.34 | 1.70 | 0.67 |
| drift | 2.82 | 3.18 | 1.41 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.37 | 0.68 | 0.09 |
| sqlite_async | 2.17 | 3.03 | 0.54 |
| drift | 6.09 | 8.68 | 1.52 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 1.93 | 3.78 | 0.24 |
| sqlite_async | 4.60 | 5.05 | 0.57 |
| drift | 10.77 | 11.88 | 1.35 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 116081 |
| resqlite per query | 0.009 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 116081 | 102722..122217 | 8.4 | 26.5 |
| sqlite3 | 189260 | 185503..189801 | 1.1 | 5.0 |
| sqlite_async | 46512 | 43840..47906 | 4.4 | 14.5 |
| drift | 42938 | 35205..45136 | 11.6 | 17.3 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.747 | 15.824 | 14.747 | 15.824 |
| sqlite_async | 36.612 | 40.477 | 36.612 | 40.477 |
| drift | 56.475 | 60.463 | 56.475 | 60.463 |
| sqlite3 (no cache) | 27.098 | 31.702 | 27.098 | 31.702 |
| sqlite3 (cached stmt) | 27.648 | 34.985 | 27.648 | 34.985 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 2.063 | 3.352 | 2.063 | 3.352 |
| sqlite3 execute() | 1.066 | 2.332 | 1.066 | 2.332 |
| sqlite_async execute() | 3.979 | 4.856 | 3.979 | 4.856 |
| drift execute() | 4.216 | 8.079 | 4.216 | 8.079 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.059 | 0.128 | 0.059 | 0.128 |
| sqlite3 executeBatch() | 0.052 | 0.057 | 0.052 | 0.057 |
| sqlite_async executeBatch() | 0.116 | 0.174 | 0.116 | 0.174 |
| drift executeBatch() | 0.143 | 0.208 | 0.143 | 0.208 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.488 | 0.761 | 0.488 | 0.761 |
| sqlite3 executeBatch() | 0.483 | 0.651 | 0.483 | 0.651 |
| sqlite_async executeBatch() | 0.807 | 1.963 | 0.807 | 1.963 |
| drift executeBatch() | 0.816 | 1.745 | 0.816 | 1.745 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 5.233 | 10.204 | 5.233 | 10.204 |
| sqlite3 executeBatch() | 4.398 | 4.984 | 4.398 | 4.984 |
| sqlite_async executeBatch() | 4.979 | 5.365 | 4.979 | 5.365 |
| drift executeBatch() | 6.327 | 6.780 | 6.327 | 6.780 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.053 | 0.057 | 0.053 | 0.057 |
| sqlite_async writeTransaction() | 0.079 | 0.083 | 0.079 | 0.083 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.080 | 0.109 | 0.080 | 0.109 |
| resqlite tx.execute() loop | 0.760 | 0.949 | 0.760 | 0.949 |
| sqlite_async tx.execute() loop | 1.460 | 9.038 | 1.460 | 9.038 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.538 | 1.164 | 0.538 | 1.164 |
| resqlite tx.execute() loop | 7.264 | 7.960 | 7.264 | 7.960 |
| sqlite_async tx.execute() loop | 10.429 | 12.054 | 10.429 | 12.054 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.112 | 0.139 | 0.112 | 0.139 |
| sqlite_async tx.getAll() | 0.202 | 0.216 | 0.202 | 0.216 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.189 | 0.223 | 0.189 | 0.223 |
| sqlite_async tx.getAll() | 0.367 | 0.464 | 0.367 | 0.464 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.036 | 0.044 | 0.036 | 0.044 |
| sqlite_async watch() | 0.113 | 0.130 | 0.113 | 0.130 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.059 | 0.112 | 0.059 | 0.112 |
| sqlite_async | 0.059 | 0.078 | 0.059 | 0.078 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.204 | 0.276 | 0.204 | 0.276 |
| sqlite_async | 0.495 | 1.992 | 0.495 | 1.992 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.215 | 0.282 | 0.215 | 0.282 |
| sqlite_async | 0.297 | 0.438 | 0.297 | 0.438 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.045 | 2.045 | 2.045 | 2.045 |
| sqlite_async | 12.025 | 12.025 | 12.025 | 12.025 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.637 | 4.160 | 3.637 | 4.160 |
| sqlite_async | 7.282 | 8.855 | 7.282 | 8.855 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.521 | 0.720 | 0.521 | 0.720 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 7.807 | 9.067 | 7.807 | 9.067 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. On resqlite's main branch this ratio is driven toward 0 by experiment 075 (C-side result-hash short-circuit), not by writer-side column-tracking (exp 052 is not implemented). The two mechanisms are indistinguishable on this read-side benchmark.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 77.8 | 0.000 |
| sqlite_async | 3761 | 985.1 | 1.104 |
| drift | 5000 | 1095.0 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 71.1 | 0.000 |
| sqlite_async | 3407 | 893.9 | 1.104 |
| drift | 5000 | 1112.9 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 218.78 | 230.82 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 438.75 | 445.21 | 0.00 | 0.00 | 1169 | 3 |
| drift stream() | 619.31 | 698.42 | 0.06 | 0.09 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.036 | 0.065 | 0.000 | 0.000 |
| sqlite3 | 0.024 | 0.042 | 0.024 | 0.042 |
| sqlite_async | 0.063 | 0.134 | 0.000 | 0.000 |
| drift | 0.044 | 0.072 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.025 | 0.046 | 0.000 | 0.000 |
| sqlite3 | 0.015 | 0.024 | 0.015 | 0.024 |
| sqlite_async | 0.050 | 0.110 | 0.000 | 0.000 |
| drift | 0.035 | 0.055 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.033 | 0.053 | 0.000 | 0.000 |
| sqlite3 | 0.032 | 0.037 | 0.032 | 0.037 |
| sqlite_async | 0.065 | 0.112 | 0.000 | 0.000 |
| drift | 0.056 | 0.070 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.014 | 0.028 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.007 | 0.005 | 0.007 |
| sqlite_async | 0.024 | 0.045 | 0.000 | 0.000 |
| drift | 0.022 | 0.032 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.038 | 0.048 | 0.001 | 0.001 |
| sqlite3 | 0.063 | 0.066 | 0.063 | 0.066 |
| sqlite_async | 0.083 | 0.106 | 0.001 | 0.001 |
| drift | 0.101 | 0.140 | 0.001 | 0.002 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 107.998 | 109.769 | 0.000 | 0.000 | 0 |
| sqlite_async | 212.132 | 214.188 | 0.000 | 0.000 | 40 |
| drift | 229.504 | 236.377 | 0.001 | 0.001 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 240.53 | 240.53 | 0.00 | 0.00 | 12.27 | 229.00 | 0 |
| sqlite_async | 472.13 | 472.13 | 0.01 | 0.01 | 23.23 | 448.89 | 1181 |
| drift | 2258.78 | 2258.78 | 6.15 | 6.15 | 14.45 | 2246.48 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 3.81 | 27.58 | 0.00..10.28 | ±5.14 |
| sqlite3 select() | 2.19 | 8.22 | 1.34..5.63 | ±2.14 |
| sqlite_async select() | 1.00 | 3.61 | 0.97..1.03 | ±0.03 |
| drift select() | 7.25 | 58.83 | 0.00..51.20 | ±25.60 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 4.00 | 0.00..1.17 | ±0.59 |
| resqlite + jsonEncode | 0.00 | 25.00 | 0.00..0.00 | ±0.00 |
| sqlite3 + jsonEncode | 0.00 | 62.05 | 0.00..45.11 | ±22.55 |
| sqlite_async + jsonEncode | 3.03 | 35.28 | 0.00..3.31 | ±1.66 |
| drift + jsonEncode | 0.00 | 17.19 | 0.00..1.45 | ±0.73 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.00 | 11.41 | 0.00..0.00 | ±0.00 |
| sqlite3 executeBatch() | 0.00 | 0.50 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| drift batch() | 0.00 | 4.33 | 0.00..2.52 | ±1.26 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.16 | 0.00..0.11 | ±0.05 |
| sqlite_async watch() | 0.00 | 0.55 | 0.00..0.50 | ±0.25 |

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
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.03 | 0.03..0.03 | 23.3% | 23.3% | 10.0% | noisy |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 50.0% | 50.0% | 10.0% | noisy |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.03 | 0.02..0.04 | 42.9% | 42.9% | 14.3% | noisy |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02..0.03 | 33.3% | 33.3% | 14.3% | noisy |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.29 | 0.29..0.29 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.29 | 0.29..0.29 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.34 | 0.31..0.35 | 11.8% | 11.8% | 2.9% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.17 | 0.16..0.18 | 11.8% | 11.8% | 5.9% | moderate |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.36 | 0.33..0.37 | 11.1% | 11.1% | 2.8% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.09 | 0.08..0.09 | 11.1% | 11.1% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.85 | 0.66..1.93 | 149.4% | 149.4% | 22.4% | noisy |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.11 | 0.08..0.24 | 145.5% | 145.5% | 27.3% | noisy |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.04 | 10.5% | 10.5% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 300.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 108.00 | 106.94..108.26 | 1.2% | 1.2% | 0.2% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 234.40 | 234.06..240.53 | 2.8% | 2.8% | 0.1% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 218.36 | 217.67..218.78 | 0.5% | 0.5% | 0.2% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 15.09 | 14.75..16.85 | 13.9% | 13.9% | 2.3% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 15.09 | 14.75..16.85 | 13.9% | 13.9% | 2.3% | stable |
| Point Query Throughput / resqlite qps | 116081.00 | 89518.00..122392.00 | 28.3% | 28.3% | 5.4% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.02 | 0.01..0.02 | 18.8% | 18.8% | 6.3% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.04 | 48.3% | 48.3% | 6.9% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.04 | 48.3% | 48.3% | 6.9% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 100.0% | 100.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 42.9% | 42.9% | 21.4% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.02 | 42.9% | 42.9% | 21.4% | noisy |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05..0.05 | 3.8% | 3.8% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.20 | 0.20..0.21 | 5.4% | 5.4% | 2.4% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.20 | 0.20..0.21 | 5.4% | 5.4% | 2.4% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.05 | 0.04..0.05 | 23.4% | 23.4% | 8.5% | noisy |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.05 | 0.04..0.05 | 23.4% | 23.4% | 8.5% | noisy |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.38 | 0.37..0.40 | 7.6% | 7.6% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.86 | 1.79..1.91 | 6.0% | 6.0% | 2.4% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.86 | 1.79..1.91 | 6.0% | 6.0% | 2.4% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09..0.09 | 5.7% | 5.7% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.36 | 0.35..0.38 | 8.1% | 8.1% | 2.5% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.36 | 0.35..0.38 | 8.1% | 8.1% | 2.5% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.63 | 4.51..4.63 | 2.6% | 2.6% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 22.01 | 20.99..28.79 | 35.5% | 35.5% | 4.7% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 22.01 | 20.99..28.79 | 35.5% | 35.5% | 4.7% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.86 | 0.86..0.87 | 1.3% | 1.3% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 4.06 | 4.05..4.20 | 3.8% | 3.8% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 4.06 | 4.05..4.20 | 3.8% | 3.8% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.87 | 0.84..0.89 | 5.7% | 5.7% | 2.5% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.97 | 3.91..4.17 | 6.6% | 6.6% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.97 | 3.91..4.17 | 6.6% | 6.6% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.18 | 0.18..0.18 | 3.9% | 3.9% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.79 | 0.75..0.80 | 7.1% | 7.1% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.79 | 0.75..0.80 | 7.1% | 7.1% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 12.06 | 10.56..12.19 | 13.5% | 13.5% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 49.99 | 42.05..63.24 | 42.4% | 42.4% | 15.9% | noisy |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 49.99 | 42.05..63.24 | 42.4% | 42.4% | 15.9% | noisy |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.75 | 1.70..1.82 | 7.2% | 7.2% | 3.2% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 7.93 | 7.70..8.37 | 8.4% | 8.4% | 2.9% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 7.93 | 7.70..8.37 | 8.4% | 8.4% | 2.9% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03..0.03 | 18.8% | 18.8% | 6.3% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.11..0.11 | 1.8% | 1.8% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.11 | 0.11..0.11 | 1.8% | 1.8% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.03..0.04 | 26.5% | 26.5% | 2.9% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.03..0.04 | 26.5% | 26.5% | 2.9% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.20 | 0.20..0.20 | 2.5% | 2.5% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.93 | 0.93..0.94 | 0.5% | 0.5% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.93 | 0.93..0.94 | 0.5% | 0.5% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04..0.04 | 2.3% | 2.3% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.19 | 0.18..0.19 | 5.3% | 5.3% | 2.6% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.19 | 0.18..0.19 | 5.3% | 5.3% | 2.6% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.25 | 2.21..2.34 | 5.6% | 5.6% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 10.27 | 10.07..11.10 | 10.0% | 10.0% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 10.27 | 10.07..11.10 | 10.0% | 10.0% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.45 | 0.44..0.45 | 2.5% | 2.5% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 2.02 | 1.82..2.02 | 10.1% | 10.1% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 2.02 | 1.82..2.02 | 10.1% | 10.1% | 0.2% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.11 | 0.10..0.16 | 50.5% | 50.5% | 7.3% | moderate |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.04 | 0.03..0.04 | 34.2% | 34.2% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.33 | 0.32..0.34 | 5.2% | 5.2% | 2.1% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.12 | 0.12..0.13 | 6.5% | 6.5% | 1.6% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.32 | 0.32..0.33 | 3.4% | 3.4% | 0.3% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.13 | 0.13..0.13 | 4.0% | 4.0% | 0.8% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.58 | 0.58..0.96 | 64.4% | 64.4% | 0.7% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.13 | 0.13..0.14 | 8.3% | 8.3% | 1.5% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 1.07 | 0.97..1.27 | 28.3% | 28.3% | 9.1% | noisy |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.37 | 0.35..0.38 | 9.2% | 9.2% | 3.5% | moderate |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.13 | 350.0% | 350.0% | 3.6% | moderate |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02..0.10 | 525.0% | 525.0% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 76.9% | 76.9% | 7.7% | moderate |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.22 | 0.20..0.24 | 18.9% | 18.9% | 7.7% | moderate |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.18 | 0.16..0.18 | 10.2% | 10.2% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.05..0.05 | 8.0% | 8.0% | 2.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.86 | 1.80..2.03 | 12.4% | 12.4% | 3.2% | moderate |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.54 | 1.50..1.62 | 7.8% | 7.8% | 2.8% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.37 | 0.37..0.38 | 1.9% | 1.9% | 0.8% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 21.51 | 20.30..24.23 | 18.3% | 18.3% | 5.7% | moderate |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 15.35 | 15.19..15.58 | 2.6% | 2.6% | 1.1% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.96 | 3.61..4.50 | 22.4% | 22.4% | 8.8% | noisy |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.01 | 0.00..0.01 | 120.0% | 120.0% | 20.0% | noisy |
| Select → Maps / 10 rows / resqlite select() | 0.02 | 0.02..0.09 | 388.9% | 388.9% | 11.1% | noisy |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 1050.0% | 1050.0% | 50.0% | noisy |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.05..0.15 | 204.1% | 204.1% | 2.0% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 11.1% | 11.1% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.37 | 0.37..0.44 | 18.3% | 18.3% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.08..0.09 | 11.8% | 11.8% | 1.2% | stable |
| Select → Maps / 10000 rows / resqlite select() | 4.79 | 4.50..5.04 | 11.1% | 11.1% | 5.0% | moderate |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.87 | 0.70..0.89 | 21.6% | 21.6% | 2.0% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.24 | 0.21..0.26 | 19.9% | 19.9% | 9.1% | noisy |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.24 | 0.21..0.26 | 19.9% | 19.9% | 9.1% | noisy |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.54 | 0.52..0.58 | 10.7% | 10.7% | 3.7% | moderate |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.54 | 0.52..0.58 | 10.7% | 10.7% | 3.7% | moderate |
| Streaming / Initial Emission / resqlite stream() | 0.04 | 0.04..0.04 | 5.3% | 5.3% | 0.0% | stable |
| Streaming / Initial Emission / resqlite stream() [main] | 0.04 | 0.04..0.04 | 5.3% | 5.3% | 0.0% | stable |
| Streaming / Invalidation Latency / resqlite | 0.06 | 0.06..0.06 | 7.0% | 7.0% | 3.5% | moderate |
| Streaming / Invalidation Latency / resqlite [main] | 0.06 | 0.06..0.06 | 7.0% | 7.0% | 3.5% | moderate |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.64 | 3.48..4.52 | 28.7% | 28.7% | 4.3% | moderate |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.64 | 3.48..4.52 | 28.7% | 28.7% | 4.3% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.04 | 1.89..2.53 | 31.7% | 31.7% | 7.8% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.04 | 1.89..2.53 | 31.7% | 31.7% | 7.8% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 7.31 | 6.79..7.81 | 13.9% | 13.9% | 6.9% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 7.31 | 6.79..7.81 | 13.9% | 13.9% | 6.9% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.22 | 0.20..0.36 | 69.9% | 69.9% | 6.8% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.22 | 0.20..0.36 | 69.9% | 69.9% | 6.8% | moderate |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.06..0.06 | 5.1% | 5.1% | 1.7% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.06 | 0.06..0.06 | 5.1% | 5.1% | 1.7% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.46 | 0.46..0.49 | 6.7% | 6.7% | 0.9% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.46 | 0.46..0.49 | 6.7% | 6.7% | 0.9% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.93 | 4.75..5.23 | 9.8% | 9.8% | 3.7% | moderate |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.93 | 4.75..5.23 | 9.8% | 9.8% | 3.7% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.76 | 0.61..0.97 | 46.6% | 46.6% | 19.2% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.76 | 0.61..0.97 | 46.6% | 46.6% | 19.2% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.08 | 0.07..0.08 | 14.5% | 14.5% | 5.3% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.08 | 0.07..0.08 | 14.5% | 14.5% | 5.3% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 7.02 | 5.61..7.26 | 23.6% | 23.6% | 3.5% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 7.02 | 5.61..7.26 | 23.6% | 23.6% | 3.5% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.46 | 0.46..0.54 | 16.9% | 16.9% | 0.2% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.46 | 0.46..0.54 | 16.9% | 16.9% | 0.2% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.06 | 0.05..0.06 | 5.5% | 5.5% | 1.8% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.06 | 0.05..0.06 | 5.5% | 5.5% | 1.8% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 2.06 | 2.01..2.33 | 15.3% | 15.3% | 2.6% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 2.06 | 2.01..2.33 | 15.3% | 15.3% | 2.6% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.18..0.21 | 13.8% | 13.8% | 4.8% | moderate |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.18..0.21 | 13.8% | 13.8% | 4.8% | moderate |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.11 | 0.11..0.11 | 4.6% | 4.6% | 1.8% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.11 | 0.11..0.11 | 4.6% | 4.6% | 1.8% | stable |


## Comparison vs Previous Run

Previous: `2026-04-23T18-44-25-internal-perf-review.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.03 | 0.03 | +0.00 | ±30% / ±0.02 ms | 23.3% | noisy | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | -0.00 | ±50% / ±0.02 ms | 50.0% | noisy | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.03 | 0.03 | -0.00 | ±43% / ±0.02 ms | 42.9% | noisy | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.02 | +0.00 | ±43% / ±0.02 ms | 33.3% | noisy | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.29 | -0.01 | ±10% / ±0.03 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.29 | -0.01 | ±10% / ±0.03 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.30 | 0.34 | +0.04 | ±12% / ±0.04 ms | 11.8% | stable | 🔴 Regression (+13%) |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.15 | 0.17 | +0.02 | ±18% / ±0.03 ms | 11.8% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.36 | 0.36 | +0.00 | ±11% / ±0.04 ms | 11.1% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.09 | 0.09 | +0.00 | ±11% / ±0.02 ms | 11.1% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.66 | 0.85 | +0.19 | ±149% / ±1.27 ms | 149.4% | noisy | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.08 | 0.11 | +0.03 | ±145% / ±0.16 ms | 145.5% | noisy | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | -0.00 | ±11% / ±0.02 ms | 10.5% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±300% / ±0.02 ms | 300.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 110.22 | 108.00 | -2.22 | ±10% / ±11.02 ms | 1.2% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 238.40 | 234.40 | -4.00 | ±10% / ±23.84 ms | 2.8% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 220.53 | 218.36 | -2.17 | ±10% / ±22.05 ms | 0.5% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.11 | 15.09 | +0.98 | ±14% / ±2.10 ms | 13.9% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.11 | 15.09 | +0.98 | ±14% / ±2.10 ms | 13.9% | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 143726.00 | 116081.00 | -27645.00 | ±28% / ±40703.03 ms | 28.3% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.02 | +0.01 | ±19% / ±0.02 ms | 18.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±48% / ±0.02 ms | 48.3% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.03 | +0.00 | ±48% / ±0.02 ms | 48.3% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±100% / ±0.02 ms | 100.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±64% / ±0.02 ms | 42.9% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±64% / ±0.02 ms | 42.9% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 3.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.20 | +0.01 | ±10% / ±0.02 ms | 5.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.20 | +0.01 | ±10% / ±0.02 ms | 5.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.05 | +0.00 | ±26% / ±0.02 ms | 23.4% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.05 | +0.00 | ±26% / ±0.02 ms | 23.4% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.37 | 0.38 | +0.01 | ±10% / ±0.04 ms | 7.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.88 | 1.86 | -0.01 | ±10% / ±0.19 ms | 6.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.88 | 1.86 | -0.01 | ±10% / ±0.19 ms | 6.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 5.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.36 | +0.01 | ±10% / ±0.04 ms | 8.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.36 | +0.01 | ±10% / ±0.04 ms | 8.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.31 | 4.63 | +0.32 | ±10% / ±0.46 ms | 2.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 20.73 | 22.01 | +1.28 | ±35% / ±7.80 ms | 35.5% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 20.73 | 22.01 | +1.28 | ±35% / ±7.80 ms | 35.5% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.85 | 0.86 | +0.01 | ±10% / ±0.09 ms | 1.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.58 | 4.06 | +0.47 | ±10% / ±0.41 ms | 3.8% | stable | 🔴 Regression (+13%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.58 | 4.06 | +0.47 | ±10% / ±0.41 ms | 3.8% | stable | 🔴 Regression (+13%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.76 | 0.87 | +0.11 | ±10% / ±0.09 ms | 5.7% | stable | 🔴 Regression (+15%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.85 | 3.97 | +0.13 | ±10% / ±0.40 ms | 6.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.85 | 3.97 | +0.13 | ±10% / ±0.40 ms | 6.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.17 | 0.18 | +0.01 | ±10% / ±0.02 ms | 3.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.74 | 0.79 | +0.04 | ±10% / ±0.08 ms | 7.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.74 | 0.79 | +0.04 | ±10% / ±0.08 ms | 7.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.43 | 12.06 | +1.63 | ±13% / ±1.63 ms | 13.5% | stable | 🔴 Regression (+16%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 43.46 | 49.99 | +6.53 | ±48% / ±23.82 ms | 42.4% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 43.46 | 49.99 | +6.53 | ±48% / ±23.82 ms | 42.4% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.71 | 1.75 | +0.04 | ±10% / ±0.18 ms | 7.2% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.34 | 7.93 | -0.41 | ±10% / ±0.83 ms | 8.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.34 | 7.93 | -0.41 | ±10% / ±0.83 ms | 8.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03 | +0.00 | ±19% / ±0.02 ms | 18.8% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.11 | +0.01 | ±10% / ±0.02 ms | 1.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.10 | 0.11 | +0.01 | ±10% / ±0.02 ms | 1.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.03 | +0.01 | ±26% / ±0.02 ms | 26.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.03 | +0.01 | ±26% / ±0.02 ms | 26.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.19 | 0.20 | +0.01 | ±10% / ±0.02 ms | 2.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.89 | 0.93 | +0.05 | ±10% / ±0.09 ms | 0.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.89 | 0.93 | +0.05 | ±10% / ±0.09 ms | 0.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.19 | 0.19 | -0.00 | ±10% / ±0.02 ms | 5.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.19 | 0.19 | -0.00 | ±10% / ±0.02 ms | 5.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.26 | 2.25 | -0.01 | ±10% / ±0.23 ms | 5.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 9.77 | 10.27 | +0.50 | ±10% / ±1.03 ms | 10.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 9.77 | 10.27 | +0.50 | ±10% / ±1.03 ms | 10.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.45 | 0.45 | +0.00 | ±10% / ±0.04 ms | 2.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.83 | 2.02 | +0.19 | ±10% / ±0.20 ms | 10.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.83 | 2.02 | +0.19 | ±10% / ±0.20 ms | 10.1% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.10 | 0.11 | +0.01 | ±50% / ±0.06 ms | 50.5% | moderate | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.04 | 0.04 | +0.00 | ±34% / ±0.02 ms | 34.2% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.31 | 0.33 | +0.02 | ±10% / ±0.03 ms | 5.2% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.10 | 0.12 | +0.02 | ±10% / ±0.02 ms | 6.5% | stable | 🔴 Regression (+22%) |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.30 | 0.32 | +0.02 | ±10% / ±0.03 ms | 3.4% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.10 | 0.13 | +0.03 | ±10% / ±0.02 ms | 4.0% | stable | 🔴 Regression (+29%) |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.52 | 0.58 | +0.06 | ±64% / ±0.38 ms | 64.4% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.10 | 0.13 | +0.03 | ±10% / ±0.02 ms | 8.3% | stable | 🔴 Regression (+32%) |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.89 | 1.07 | +0.17 | ±28% / ±0.30 ms | 28.3% | noisy | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.27 | 0.37 | +0.10 | ±11% / ±0.04 ms | 9.2% | moderate | 🔴 Regression (+37%) |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±350% / ±0.10 ms | 350.0% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02 | +0.00 | ±525% / ±0.08 ms | 525.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | +0.00 | ±77% / ±0.02 ms | 76.9% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.19 | 0.22 | +0.03 | ±23% / ±0.05 ms | 18.9% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.15 | 0.18 | +0.02 | ±10% / ±0.02 ms | 10.2% | stable | 🔴 Regression (+16%) |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 8.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.80 | 1.86 | +0.06 | ±12% / ±0.23 ms | 12.4% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.49 | 1.54 | +0.05 | ±10% / ±0.15 ms | 7.8% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.37 | 0.37 | +0.01 | ±10% / ±0.04 ms | 1.9% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.82 | 21.51 | +0.69 | ±18% / ±3.93 ms | 18.3% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 15.01 | 15.35 | +0.34 | ±10% / ±1.54 ms | 2.6% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.77 | 3.96 | +0.19 | ±26% / ±1.04 ms | 22.4% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.01 | +0.00 | ±120% / ±0.02 ms | 120.0% | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.02 | +0.01 | ±389% / ±0.07 ms | 388.9% | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±1050% / ±0.02 ms | 1050.0% | noisy | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.04 | 0.05 | +0.01 | ±204% / ±0.10 ms | 204.1% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±11% / ±0.02 ms | 11.1% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.37 | 0.37 | +0.00 | ±18% / ±0.07 ms | 18.3% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.09 | +0.00 | ±12% / ±0.02 ms | 11.8% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 4.43 | 4.79 | +0.37 | ±15% / ±0.73 ms | 11.1% | moderate | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.86 | 0.87 | +0.01 | ±22% / ±0.19 ms | 21.6% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.24 | 0.24 | -0.00 | ±27% / ±0.07 ms | 19.9% | noisy | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.24 | 0.24 | -0.00 | ±27% / ±0.07 ms | 19.9% | noisy | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.57 | 0.54 | -0.02 | ±11% / ±0.06 ms | 10.7% | moderate | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.57 | 0.54 | -0.02 | ±11% / ±0.06 ms | 10.7% | moderate | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.04 | +0.00 | ±10% / ±0.02 ms | 5.3% | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.04 | +0.00 | ±10% / ±0.02 ms | 5.3% | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.06 | +0.01 | ±11% / ±0.02 ms | 7.0% | moderate | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.06 | +0.01 | ±11% / ±0.02 ms | 7.0% | moderate | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.36 | 3.64 | +0.28 | ±29% / ±1.04 ms | 28.7% | moderate | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.36 | 3.64 | +0.28 | ±29% / ±1.04 ms | 28.7% | moderate | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.06 | 2.04 | -0.01 | ±32% / ±0.65 ms | 31.7% | moderate | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.06 | 2.04 | -0.01 | ±32% / ±0.65 ms | 31.7% | moderate | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 7.22 | 7.31 | +0.09 | ±21% / ±1.50 ms | 13.9% | moderate | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 7.22 | 7.31 | +0.09 | ±21% / ±1.50 ms | 13.9% | moderate | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.18 | 0.22 | +0.04 | ±70% / ±0.15 ms | 69.9% | moderate | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.18 | 0.22 | +0.04 | ±70% / ±0.15 ms | 69.9% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.07 | 0.06 | -0.01 | ±10% / ±0.02 ms | 5.1% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.07 | 0.06 | -0.01 | ±10% / ±0.02 ms | 5.1% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.47 | 0.46 | -0.01 | ±10% / ±0.05 ms | 6.7% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.47 | 0.46 | -0.01 | ±10% / ±0.05 ms | 6.7% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.14 | 4.93 | +0.79 | ±11% / ±0.55 ms | 9.8% | moderate | 🔴 Regression (+19%) |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.14 | 4.93 | +0.79 | ±11% / ±0.55 ms | 9.8% | moderate | 🔴 Regression (+19%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.56 | 0.76 | +0.20 | ±58% / ±0.44 ms | 46.6% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.56 | 0.76 | +0.20 | ±58% / ±0.44 ms | 46.6% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.08 | +0.00 | ±16% / ±0.02 ms | 14.5% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.08 | +0.00 | ±16% / ±0.02 ms | 14.5% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 6.59 | 7.02 | +0.43 | ±24% / ±1.65 ms | 23.6% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 6.59 | 7.02 | +0.43 | ±24% / ±1.65 ms | 23.6% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.43 | 0.46 | +0.03 | ±17% / ±0.08 ms | 16.9% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.43 | 0.46 | +0.03 | ±17% / ±0.08 ms | 16.9% | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.06 | +0.01 | ±10% / ±0.02 ms | 5.5% | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.06 | +0.01 | ±10% / ±0.02 ms | 5.5% | stable | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.53 | 2.06 | +0.54 | ±15% / ±0.32 ms | 15.3% | stable | 🔴 Regression (+35%) |
| Write Performance / Single Inserts (100 sequential) / res... | 1.53 | 2.06 | +0.54 | ±15% / ±0.32 ms | 15.3% | stable | 🔴 Regression (+35%) |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.19 | +0.00 | ±14% / ±0.03 ms | 13.8% | moderate | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.19 | +0.00 | ±14% / ±0.03 ms | 13.8% | moderate | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.11 | +0.01 | ±10% / ±0.02 ms | 4.6% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.11 | +0.01 | ±10% / ±0.02 ms | 4.6% | stable | ⚪ Within noise |

**Summary:** 0 wins, 14 regressions, 139 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.02 | 0.00 | -0.02 MB | ±1.26 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 0.00 | 0.00 | +0.00 MB | ±0.73 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 2.00 | 0.00 | -2.00 MB | ±0.50 MB | 🟢 Win (-2.00 MB) |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 0.00 | +0.00 MB | ±0.59 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 1.34 | 0.00 | -1.34 MB | ±22.55 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 3.03 | +3.03 MB | ±1.66 MB | 🔴 Regression (+3.03 MB) |
| Memory / Select 10k rows → Maps / drift select() | 11.36 | 7.25 | -4.11 MB | ±25.60 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / resqlite select() | 5.45 | 3.81 | -1.64 MB | ±5.14 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite3 select() | 2.66 | 2.19 | -0.47 MB | ±2.14 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 1.00 | 1.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.06 | 0.06 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 1 wins, 1 regressions, 13 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 3969 | 3761 | -208 | ±100 | 🟢 Fewer re-emits (-208) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 3879 | 3407 | -472 | ±100 | 🔴 Invalidation elided (-472) — writes not firing |

**Granularity summary:** 1 fewer-re-emit, 1 more-re-emit, 4 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.
