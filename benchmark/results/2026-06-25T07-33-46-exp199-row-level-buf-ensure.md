# resqlite Benchmark Results

Generated: 2026-06-25T07:33:45.832652

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp199-row-level-buf-ensure`
- Repeats: `5`
- Runtime: `dart-vm / Dart 3.11.5`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `exp-199-row-level-buf-ensure @ 97838492c050 (dirty)`
- Comparison baseline: `2026-06-24T07-30-24-exp198-direct-buf-int-json.md`
- Comparison mode: `automatic`
- Comparison baseline compatibility: `compatible`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.011 | 0.012 | 0.000 | 0.000 |
| sqlite3 select() | 0.016 | 0.016 | 0.016 | 0.016 |
| sqlite_async select() | 0.032 | 0.035 | 0.001 | 0.002 |
| drift select() | 0.036 | 0.040 | 0.001 | 0.001 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.042 | 0.045 | 0.005 | 0.006 |
| sqlite3 select() | 0.119 | 0.125 | 0.119 | 0.125 |
| sqlite_async select() | 0.129 | 0.133 | 0.012 | 0.013 |
| drift select() | 0.181 | 0.188 | 0.012 | 0.013 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.338 | 0.345 | 0.051 | 0.051 |
| sqlite3 select() | 1.150 | 1.200 | 1.150 | 1.200 |
| sqlite_async select() | 1.078 | 1.269 | 0.115 | 0.127 |
| drift select() | 1.571 | 1.873 | 0.114 | 0.117 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.005 | 9.985 | 0.513 | 0.723 |
| sqlite3 select() | 14.080 | 16.972 | 14.080 | 16.972 |
| sqlite_async select() | 12.347 | 15.256 | 1.152 | 2.474 |
| drift select() | 22.261 | 25.464 | 1.172 | 2.563 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row. The large-payload row isolates resqlite selectBytes because it guards the native bytes transfer policy without multiplying large JSON encoding work across every peer.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.026 | 0.028 | 0.015 | 0.016 |
| sqlite3 + jsonEncode | 0.030 | 0.031 | 0.030 | 0.031 |
| sqlite_async + jsonEncode | 0.045 | 0.047 | 0.016 | 0.016 |
| drift + jsonEncode | 0.052 | 0.054 | 0.016 | 0.016 |
| resqlite selectBytes() | 0.011 | 0.012 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.193 | 0.205 | 0.153 | 0.158 |
| sqlite3 + jsonEncode | 0.260 | 0.276 | 0.260 | 0.276 |
| sqlite_async + jsonEncode | 0.275 | 0.299 | 0.152 | 0.168 |
| drift + jsonEncode | 0.314 | 0.320 | 0.150 | 0.152 |
| resqlite selectBytes() | 0.038 | 0.042 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.733 | 2.579 | 1.439 | 2.158 |
| sqlite3 + jsonEncode | 2.496 | 3.203 | 2.496 | 3.203 |
| sqlite_async + jsonEncode | 2.405 | 2.953 | 1.443 | 1.762 |
| drift + jsonEncode | 2.918 | 3.688 | 1.436 | 2.221 |
| resqlite selectBytes() | 0.268 | 0.272 | 0.000 | 0.000 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 22.109 | 23.554 | 14.601 | 16.664 |
| sqlite3 + jsonEncode | 28.548 | 34.149 | 28.548 | 34.149 |
| sqlite_async + jsonEncode | 30.002 | 33.767 | 14.861 | 17.125 |
| drift + jsonEncode | 36.907 | 39.681 | 14.830 | 16.507 |
| resqlite selectBytes() | 2.714 | 2.749 | 0.000 | 0.000 |

### Large payload (~650KB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.233 | 0.256 | 0.000 | 0.000 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.088 | 0.095 | 0.023 | 0.028 |
| sqlite3 | 0.311 | 0.322 | 0.311 | 0.322 |
| sqlite_async | 0.344 | 0.375 | 0.032 | 0.035 |
| drift | 0.566 | 0.578 | 0.031 | 0.034 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.858 | 0.891 | 0.219 | 0.222 |
| sqlite3 | 3.252 | 3.775 | 3.252 | 3.775 |
| sqlite_async | 2.885 | 3.351 | 0.230 | 0.247 |
| drift | 4.544 | 5.737 | 0.231 | 0.238 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.486 | 0.512 | 0.063 | 0.065 |
| sqlite3 | 1.441 | 1.560 | 1.441 | 1.560 |
| sqlite_async | 1.354 | 1.656 | 0.083 | 0.086 |
| drift | 1.878 | 2.146 | 0.082 | 0.084 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.254 | 0.260 | 0.060 | 0.062 |
| sqlite3 | 0.996 | 1.023 | 0.996 | 1.023 |
| sqlite_async | 0.928 | 0.936 | 0.082 | 0.084 |
| drift | 1.415 | 1.431 | 0.080 | 0.082 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.258 | 0.261 | 0.060 | 0.060 |
| sqlite3 | 0.947 | 0.991 | 0.947 | 0.991 |
| sqlite_async | 0.919 | 0.931 | 0.082 | 0.084 |
| drift | 1.400 | 1.670 | 0.081 | 0.082 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.010 | 0.011 | 0.000 | 0.000 |
| sqlite3 | 0.015 | 0.016 | 0.015 | 0.016 |
| sqlite_async | 0.029 | 0.030 | 0.001 | 0.001 |
| drift | 0.036 | 0.037 | 0.001 | 0.001 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.025 | 0.025 | 0.002 | 0.003 |
| sqlite3 | 0.059 | 0.061 | 0.059 | 0.061 |
| sqlite_async | 0.072 | 0.075 | 0.004 | 0.004 |
| drift | 0.099 | 0.101 | 0.004 | 0.004 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.042 | 0.044 | 0.005 | 0.005 |
| sqlite3 | 0.115 | 0.119 | 0.115 | 0.119 |
| sqlite_async | 0.123 | 0.126 | 0.007 | 0.008 |
| drift | 0.178 | 0.184 | 0.007 | 0.008 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.176 | 0.188 | 0.026 | 0.028 |
| sqlite3 | 0.578 | 0.647 | 0.578 | 0.647 |
| sqlite_async | 0.523 | 0.530 | 0.035 | 0.038 |
| drift | 0.769 | 0.775 | 0.035 | 0.037 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.341 | 0.346 | 0.052 | 0.053 |
| sqlite3 | 1.106 | 1.124 | 1.106 | 1.124 |
| sqlite_async | 1.020 | 1.032 | 0.070 | 0.074 |
| drift | 1.520 | 1.626 | 0.069 | 0.073 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.712 | 0.741 | 0.107 | 0.109 |
| sqlite3 | 2.210 | 2.602 | 2.210 | 2.602 |
| sqlite_async | 2.060 | 2.370 | 0.141 | 0.151 |
| drift | 3.050 | 3.440 | 0.139 | 0.141 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.911 | 4.170 | 0.258 | 0.272 |
| sqlite3 | 5.577 | 7.155 | 5.577 | 7.155 |
| sqlite_async | 5.194 | 5.822 | 0.350 | 0.366 |
| drift | 8.147 | 8.226 | 0.348 | 0.363 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.017 | 8.992 | 0.518 | 0.927 |
| sqlite3 | 13.769 | 16.247 | 13.769 | 16.247 |
| sqlite_async | 11.021 | 11.854 | 0.703 | 0.726 |
| drift | 17.921 | 26.493 | 0.722 | 1.193 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 10.026 | 14.963 | 1.027 | 1.874 |
| sqlite3 | 31.799 | 35.567 | 31.799 | 35.567 |
| sqlite_async | 32.688 | 36.772 | 1.419 | 1.540 |
| drift | 45.982 | 54.728 | 1.425 | 5.415 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.028 | 0.028 | 0.028 | 0.028 |
| sqlite3 + jsonEncode | 0.030 | 0.112 | 0.030 | 0.112 |
| sqlite_async + jsonEncode | 0.053 | 0.068 | 0.053 | 0.068 |
| drift + jsonEncode | 0.061 | 0.080 | 0.061 | 0.080 |
| resqlite selectBytes() | 0.010 | 0.011 | 0.010 | 0.011 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.101 | 0.109 | 0.101 | 0.109 |
| sqlite3 + jsonEncode | 0.131 | 0.138 | 0.131 | 0.138 |
| sqlite_async + jsonEncode | 0.147 | 0.149 | 0.147 | 0.149 |
| drift + jsonEncode | 0.173 | 0.179 | 0.173 | 0.179 |
| resqlite selectBytes() | 0.022 | 0.022 | 0.022 | 0.022 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.197 | 0.211 | 0.197 | 0.211 |
| sqlite3 + jsonEncode | 0.260 | 0.297 | 0.260 | 0.297 |
| sqlite_async + jsonEncode | 0.265 | 0.269 | 0.265 | 0.269 |
| drift + jsonEncode | 0.316 | 0.325 | 0.316 | 0.325 |
| resqlite selectBytes() | 0.034 | 0.037 | 0.034 | 0.037 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.887 | 1.272 | 0.887 | 1.272 |
| sqlite3 + jsonEncode | 1.258 | 2.139 | 1.258 | 2.139 |
| sqlite_async + jsonEncode | 1.224 | 1.693 | 1.224 | 1.693 |
| drift + jsonEncode | 1.462 | 1.714 | 1.462 | 1.714 |
| resqlite selectBytes() | 0.139 | 0.140 | 0.139 | 0.140 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.746 | 2.952 | 1.746 | 2.952 |
| sqlite3 + jsonEncode | 2.477 | 2.958 | 2.477 | 2.958 |
| sqlite_async + jsonEncode | 2.508 | 3.097 | 2.508 | 3.097 |
| drift + jsonEncode | 2.908 | 3.234 | 2.908 | 3.234 |
| resqlite selectBytes() | 0.267 | 0.274 | 0.267 | 0.274 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.700 | 6.047 | 3.700 | 6.047 |
| sqlite3 + jsonEncode | 5.153 | 8.706 | 5.153 | 8.706 |
| sqlite_async + jsonEncode | 5.013 | 7.858 | 5.013 | 7.858 |
| drift + jsonEncode | 5.980 | 9.199 | 5.980 | 9.199 |
| resqlite selectBytes() | 0.516 | 0.532 | 0.516 | 0.532 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 9.701 | 12.660 | 9.701 | 12.660 |
| sqlite3 + jsonEncode | 13.501 | 18.444 | 13.501 | 18.444 |
| sqlite_async + jsonEncode | 13.593 | 18.101 | 13.593 | 18.101 |
| drift + jsonEncode | 16.159 | 20.859 | 16.159 | 20.859 |
| resqlite selectBytes() | 1.349 | 1.402 | 1.349 | 1.402 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 22.218 | 23.815 | 22.218 | 23.815 |
| sqlite3 + jsonEncode | 28.283 | 33.598 | 28.283 | 33.598 |
| sqlite_async + jsonEncode | 30.028 | 31.139 | 30.028 | 31.139 |
| drift + jsonEncode | 35.381 | 38.381 | 35.381 | 38.381 |
| resqlite selectBytes() | 2.669 | 2.725 | 2.669 | 2.725 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 43.324 | 44.951 | 43.324 | 44.951 |
| sqlite3 + jsonEncode | 61.967 | 65.734 | 61.967 | 65.734 |
| sqlite_async + jsonEncode | 64.171 | 70.175 | 64.171 | 70.175 |
| drift + jsonEncode | 78.845 | 91.491 | 78.845 | 91.491 |
| resqlite selectBytes() | 5.797 | 7.109 | 5.797 | 7.109 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.29 | 0.30 | 0.29 |
| sqlite_async | 0.95 | 0.96 | 0.95 |
| drift | 1.45 | 1.49 | 1.45 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.30 | 0.15 |
| sqlite_async | 1.41 | 1.70 | 0.70 |
| drift | 2.65 | 3.05 | 1.32 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.36 | 0.64 | 0.09 |
| sqlite_async | 2.43 | 3.71 | 0.61 |
| drift | 5.11 | 5.48 | 1.28 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.68 | 1.11 | 0.08 |
| sqlite_async | 4.88 | 5.98 | 0.61 |
| drift | 10.37 | 11.16 | 1.30 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 152534 |
| resqlite per query | 0.007 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 152534 | 151636..153191 | 0.5 | 2.7 |
| sqlite3 | 201357 | 200687..201456 | 0.2 | 0.4 |
| sqlite_async | 52818 | 52462..52948 | 0.5 | 2.0 |
| drift | 48698 | 48562..48854 | 0.3 | 1.0 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 13.964 | 14.211 | 13.964 | 14.211 |
| sqlite_async | 36.257 | 36.989 | 36.257 | 36.989 |
| drift | 52.136 | 52.770 | 52.136 | 52.770 |
| sqlite3 (no cache) | 24.001 | 24.346 | 24.001 | 24.346 |
| sqlite3 (cached stmt) | 23.707 | 23.812 | 23.707 | 23.812 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.482 | 1.985 | 1.482 | 1.985 |
| sqlite3 execute() | 0.871 | 1.512 | 0.871 | 1.512 |
| sqlite_async execute() | 2.563 | 3.306 | 2.563 | 3.306 |
| drift execute() | 2.507 | 3.195 | 2.507 | 3.195 |

### Concurrent Single Inserts (100 concurrent)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite concurrent execute() | 0.788 | 1.167 | 0.788 | 1.167 |
| sqlite3 concurrent execute() | 0.845 | 1.507 | 0.845 | 1.507 |
| sqlite_async concurrent execute() | 2.481 | 3.241 | 2.481 | 3.241 |
| drift concurrent execute() | 1.597 | 2.301 | 1.597 | 2.301 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.050 | 0.053 | 0.050 | 0.053 |
| sqlite3 executeBatch() | 0.047 | 0.049 | 0.047 | 0.049 |
| sqlite_async executeBatch() | 0.095 | 0.124 | 0.095 | 0.124 |
| drift executeBatch() | 0.110 | 0.116 | 0.110 | 0.116 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.396 | 0.427 | 0.396 | 0.427 |
| sqlite3 executeBatch() | 0.431 | 0.439 | 0.431 | 0.439 |
| sqlite_async executeBatch() | 0.506 | 0.515 | 0.506 | 0.515 |
| drift executeBatch() | 0.634 | 0.675 | 0.634 | 0.675 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 3.751 | 4.564 | 3.751 | 4.564 |
| sqlite3 executeBatch() | 4.065 | 4.254 | 4.065 | 4.254 |
| sqlite_async executeBatch() | 4.696 | 5.163 | 4.696 | 5.163 |
| drift executeBatch() | 5.824 | 6.536 | 5.824 | 6.536 |

### Wide Batch Insert (10000 rows x 20 params)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 12.168 | 19.736 | 12.168 | 19.736 |
| sqlite3 executeBatch() | 18.764 | 21.040 | 18.764 | 21.040 |
| sqlite_async executeBatch() | 21.529 | 25.367 | 21.529 | 25.367 |
| drift executeBatch() | 24.646 | 29.363 | 24.646 | 29.363 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.045 | 0.049 | 0.045 | 0.049 |
| sqlite_async writeTransaction() | 0.084 | 0.088 | 0.084 | 0.088 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.060 | 0.065 | 0.060 | 0.065 |
| resqlite tx.execute() loop | 0.362 | 0.607 | 0.362 | 0.607 |
| sqlite_async tx.execute() loop | 0.960 | 1.176 | 0.960 | 1.176 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.395 | 0.420 | 0.395 | 0.420 |
| resqlite tx.execute() loop | 4.377 | 5.347 | 4.377 | 5.347 |
| sqlite_async tx.execute() loop | 9.475 | 9.962 | 9.475 | 9.962 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.101 | 0.104 | 0.101 | 0.104 |
| sqlite_async tx.getAll() | 0.199 | 0.211 | 0.199 | 0.211 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.180 | 0.186 | 0.180 | 0.186 |
| sqlite_async tx.getAll() | 0.345 | 0.353 | 0.345 | 0.353 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 0.681 | 0.828 | 0.681 | 0.828 |
| resqlite nested transaction() depth=5 | 0.067 | 0.071 | 0.067 | 0.071 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.030 | 0.034 | 0.030 | 0.034 |
| sqlite_async watch() | 0.100 | 0.105 | 0.100 | 0.105 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.042 | 0.080 | 0.042 | 0.080 |
| sqlite_async | 0.065 | 0.102 | 0.065 | 0.102 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.173 | 0.267 | 0.173 | 0.267 |
| sqlite_async | 0.516 | 0.949 | 0.516 | 0.949 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.609 | 3.282 | 1.609 | 3.282 |

### Long-Payload Unchanged Fanout (8 streams, 64 rows x 32KB TEXT + 32KB BLOB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.644 | 3.067 | 2.644 | 3.067 |

### Long-Text 32KB Unchanged Fanout (8 unchanged streams, 64 rows x 32KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.741 | 4.332 | 2.741 | 4.332 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.168 | 0.239 | 0.168 | 0.239 |
| sqlite_async | 0.237 | 0.296 | 0.237 | 0.296 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.579 | 1.579 | 1.579 | 1.579 |
| sqlite_async | 8.860 | 8.860 | 8.860 | 8.860 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.087 | 3.766 | 3.087 | 3.766 |
| sqlite_async | 5.165 | 6.157 | 5.165 | 6.157 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.518 | 0.698 | 0.518 | 0.698 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 6.042 | 7.533 | 6.042 | 7.533 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. For resqlite, this emission metric can reflect writer-side column-level invalidation, experiment 075's native result-hash short-circuit, or both. Use A11c (Many-Streams Writer Throughput) when the question is specifically writer-side dispatch elision.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 67.1 | 0.000 |
| sqlite_async | 3847 | 1054.0 | 0.906 |
| drift | 5000 | 991.9 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 69.8 | 0.000 |
| sqlite_async | 4247 | 1134.9 | 0.906 |
| drift | 5000 | 984.6 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 225.00 | 227.18 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 443.15 | 444.48 | 0.00 | 0.00 | 1101 | 3 |
| drift stream() | 545.65 | 552.25 | 0.00 | 0.00 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.017 | 0.029 | 0.000 | 0.000 |
| sqlite3 | 0.018 | 0.022 | 0.018 | 0.022 |
| sqlite_async | 0.035 | 0.043 | 0.000 | 0.000 |
| drift | 0.035 | 0.041 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.013 | 0.021 | 0.000 | 0.000 |
| sqlite3 | 0.011 | 0.013 | 0.011 | 0.013 |
| sqlite_async | 0.028 | 0.033 | 0.000 | 0.000 |
| drift | 0.028 | 0.033 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.023 | 0.033 | 0.000 | 0.000 |
| sqlite3 | 0.030 | 0.032 | 0.030 | 0.032 |
| sqlite_async | 0.054 | 0.063 | 0.000 | 0.000 |
| drift | 0.052 | 0.055 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.008 | 0.014 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.020 | 0.023 | 0.000 | 0.000 |
| drift | 0.018 | 0.022 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.037 | 0.039 | 0.001 | 0.001 |
| sqlite3 | 0.065 | 0.066 | 0.065 | 0.066 |
| sqlite_async | 0.079 | 0.082 | 0.001 | 0.001 |
| drift | 0.090 | 0.096 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 110.753 | 113.244 | 0.000 | 0.000 | 0 |
| sqlite_async | 217.772 | 220.038 | 0.000 | 0.000 | 41 |
| drift | 232.342 | 235.833 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 236.78 | 236.78 | 0.00 | 0.00 | 12.51 | 224.26 | 0 |
| sqlite_async | 484.15 | 484.15 | 0.00 | 0.00 | 24.66 | 459.50 | 1182 |
| drift | 1679.36 | 1679.36 | 0.02 | 0.02 | 14.08 | 1665.87 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 0.34 | 10.31 | 0.00..6.08 | ±3.04 |
| sqlite3 select() | 4.55 | 9.22 | 0.00..7.91 | ±3.95 |
| sqlite_async select() | 1.00 | 1.09 | 0.98..1.00 | ±0.01 |
| drift select() | 7.11 | 74.09 | 0.00..74.02 | ±37.01 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 1.38 | 0.00..0.00 | ±0.00 |
| resqlite + jsonEncode | 4.92 | 88.36 | 0.00..10.48 | ±5.24 |
| sqlite3 + jsonEncode | 0.00 | 13.02 | 0.00..3.50 | ±1.75 |
| sqlite_async + jsonEncode | 0.00 | 7.55 | 0.00..6.56 | ±3.28 |
| drift + jsonEncode | 0.45 | 79.56 | 0.00..32.55 | ±16.27 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.00 | 5.08 | 0.00..4.08 | ±2.04 |
| sqlite3 executeBatch() | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| drift batch() | 0.03 | 4.50 | 0.00..1.50 | ±0.75 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.13 | 0.00..0.06 | ±0.03 |
| sqlite_async watch() | 0.00 | 0.50 | 0.00..0.02 | ±0.01 |

## SQLite Diagnostics

resqlite-only internal SQLite counters captured via `Database.diagnostics()` after representative workloads. Values reflect the writer plus idle readers in this connection pool; they are not process-global SQLite totals.

### Warm read working set (20000 rows + 2000 point lookups)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | JSON buf (KiB) | Readers busy |
|---|---|---|---|---|---|---|---|
| resqlite | 3211.0 | 3189.5 | 5.3 | 16.2 | 2048.0 | 64.0 | 0 |

### Statement cache footprint (48 distinct SELECT texts)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | JSON buf (KiB) | Readers busy |
|---|---|---|---|---|---|---|---|
| resqlite | 3304.0 | 3189.5 | 5.3 | 109.2 | 2048.0 | 64.0 | 0 |

### WAL after write burst (1000 inserted rows)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | JSON buf (KiB) | Readers busy |
|---|---|---|---|---|---|---|---|
| resqlite | 261.5 | 240.0 | 5.3 | 16.2 | 161.0 | 64.0 | 0 |

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
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 6.3% | 12.5% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02..0.02 | 2.9% | 5.9% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.01..0.01 | 3.6% | 7.1% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.29 | 0.29..0.30 | 1.7% | 3.4% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.29 | 0.29..0.30 | 1.7% | 3.4% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.30 | 0.30..0.30 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.15 | 0.15..0.15 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.37 | 0.36..0.39 | 4.1% | 8.1% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.09 | 0.09..0.10 | 5.6% | 11.1% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.69 | 0.68..0.73 | 3.6% | 7.2% | 1.4% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.09 | 0.08..0.09 | 5.6% | 11.1% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.04 | 2.6% | 5.3% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 150.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 110.84 | 108.72..111.39 | 1.2% | 2.4% | 0.4% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 241.60 | 234.05..244.11 | 2.1% | 4.2% | 1.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 224.99 | 218.76..225.37 | 1.5% | 2.9% | 0.2% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 13.97 | 13.94..14.09 | 0.5% | 1.1% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 13.97 | 13.94..14.09 | 0.5% | 1.1% | 0.0% | stable |
| Point Query Throughput / resqlite qps | 153844.00 | 142993.00..154540.00 | 3.8% | 7.5% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.01 | 22.7% | 45.5% | 9.1% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.03 | 12.5% | 25.0% | 3.6% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.03 | 12.5% | 25.0% | 3.6% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.01 | 10.0% | 20.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.01 | 10.0% | 20.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.04..0.04 | 2.3% | 4.7% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.19 | 0.19..0.20 | 2.1% | 4.1% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.19 | 0.19..0.20 | 2.1% | 4.1% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.04 | 0.03..0.04 | 4.2% | 8.3% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.04 | 0.03..0.04 | 4.2% | 8.3% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.34 | 0.34..0.34 | 0.4% | 0.9% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.74 | 1.72..1.75 | 0.8% | 1.6% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.74 | 1.72..1.75 | 0.8% | 1.6% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.05 | 0.05..0.05 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.27 | 0.27..0.27 | 0.4% | 0.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.27 | 0.27..0.27 | 0.4% | 0.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.09 | 4.02..4.15 | 1.6% | 3.3% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 21.95 | 20.37..22.22 | 4.2% | 8.4% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 21.95 | 20.37..22.22 | 4.2% | 8.4% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.52 | 0.52..0.53 | 1.4% | 2.9% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 2.70 | 2.65..2.72 | 1.2% | 2.5% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 2.70 | 2.65..2.72 | 1.2% | 2.5% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.71 | 0.71..0.74 | 2.3% | 4.6% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.68 | 3.65..3.72 | 0.8% | 1.7% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.68 | 3.65..3.72 | 0.8% | 1.7% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.11 | 0.10..0.11 | 1.4% | 2.8% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.52 | 0.52..0.55 | 3.6% | 7.3% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.52 | 0.52..0.55 | 3.6% | 7.3% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.05 | 9.89..11.13 | 6.2% | 12.3% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 41.84 | 40.90..43.32 | 2.9% | 5.8% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 41.84 | 40.90..43.32 | 2.9% | 5.8% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.03 | 1.02..1.03 | 0.4% | 0.8% | 0.1% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 5.59 | 5.44..5.80 | 3.2% | 6.3% | 2.6% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 5.59 | 5.44..5.80 | 3.2% | 6.3% | 2.6% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.02..0.03 | 8.0% | 16.0% | 4.0% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10..0.11 | 5.0% | 9.9% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.10 | 0.10..0.11 | 5.0% | 9.9% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.00 | 25.0% | 50.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.02 | 0.02..0.02 | 4.5% | 9.1% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.02 | 0.02..0.02 | 4.5% | 9.1% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.18 | 0.17..0.18 | 0.3% | 0.6% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.89 | 0.89..0.89 | 0.2% | 0.3% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.89 | 0.89..0.89 | 0.2% | 0.3% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.03 | 0.03..0.03 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.14 | 0.14..0.15 | 2.9% | 5.7% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.14 | 0.14..0.15 | 2.9% | 5.7% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 1.93 | 1.90..1.95 | 1.3% | 2.5% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 9.50 | 9.23..10.27 | 5.4% | 10.9% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 9.50 | 9.23..10.27 | 5.4% | 10.9% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.26 | 0.26..0.26 | 0.6% | 1.2% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 1.30 | 1.29..1.35 | 2.3% | 4.5% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 1.30 | 1.29..1.35 | 2.3% | 4.5% | 1.0% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.09 | 0.09..0.15 | 39.7% | 79.3% | 1.1% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.02 | 0.02..0.04 | 37.0% | 73.9% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.26 | 0.26..0.26 | 0.6% | 1.2% | 0.4% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.06 | 0.06..0.06 | 0.0% | 0.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.25 | 0.25..0.26 | 2.0% | 3.9% | 0.4% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.06 | 0.06..0.06 | 0.8% | 1.7% | 0.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.49 | 0.48..0.49 | 1.0% | 2.1% | 0.8% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.06 | 0.06..0.06 | 0.8% | 1.6% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.86 | 0.85..0.86 | 0.3% | 0.7% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.22 | 0.22..0.22 | 0.5% | 0.9% | 0.5% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.12 | 188.5% | 376.9% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.01 | 0.01..0.10 | 290.0% | 580.0% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.01 | 18.2% | 36.4% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.19 | 0.19..0.23 | 9.3% | 18.7% | 1.6% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.15 | 0.15..0.17 | 6.2% | 12.4% | 0.7% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.04 | 7.9% | 15.8% | 5.3% | moderate |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.73 | 1.72..1.80 | 2.3% | 4.6% | 1.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.44 | 1.43..1.50 | 2.6% | 5.1% | 0.8% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.27 | 0.27..0.28 | 3.0% | 5.9% | 0.4% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 22.11 | 20.37..22.48 | 4.8% | 9.5% | 0.6% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 14.64 | 14.60..14.76 | 0.6% | 1.2% | 0.3% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 2.71 | 2.65..2.75 | 2.0% | 4.0% | 1.1% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / Large payload (~650KB) / resqlite selectBytes() | 0.23 | 0.23..0.28 | 9.6% | 19.2% | 0.4% | stable |
| Select → JSON Bytes / Large payload (~650KB) / resqlite selectBytes... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.08 | 327.3% | 654.5% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.04 | 0.04..0.14 | 120.2% | 240.5% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 30.0% | 60.0% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.34 | 0.34..0.36 | 3.4% | 6.8% | 0.3% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.05 | 0.05..0.05 | 2.0% | 3.9% | 0.0% | stable |
| Select → Maps / 10000 rows / resqlite select() | 4.04 | 3.96..4.43 | 5.8% | 11.7% | 2.0% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.51 | 0.51..0.53 | 2.5% | 5.1% | 0.2% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.18 | 0.16..0.19 | 7.1% | 14.1% | 5.1% | moderate |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.18 | 0.16..0.19 | 7.1% | 14.1% | 5.1% | moderate |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.52 | 0.52..0.54 | 2.5% | 5.0% | 1.0% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.52 | 0.52..0.54 | 2.5% | 5.0% | 1.0% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03..0.06 | 68.5% | 137.0% | 0.0% | stable |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03..0.06 | 68.5% | 137.0% | 0.0% | stable |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.04..0.05 | 8.3% | 16.7% | 2.4% | stable |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.04..0.05 | 8.3% | 16.7% | 2.4% | stable |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows x 32K... | 2.66 | 2.56..2.68 | 2.1% | 4.3% | 0.5% | stable |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows x 32K... | 2.66 | 2.56..2.68 | 2.1% | 4.3% | 0.5% | stable |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged streams, 6... | 2.72 | 2.62..2.85 | 4.3% | 8.6% | 0.9% | stable |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged streams, 6... | 2.72 | 2.62..2.85 | 4.3% | 8.6% | 0.9% | stable |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 1.64 | 1.61..1.75 | 4.2% | 8.4% | 2.0% | stable |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 1.64 | 1.61..1.75 | 4.2% | 8.4% | 2.0% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.20 | 3.09..3.23 | 2.3% | 4.6% | 1.1% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.20 | 3.09..3.23 | 2.3% | 4.6% | 1.1% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.80 | 1.58..3.17 | 44.3% | 88.6% | 9.7% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.80 | 1.58..3.17 | 44.3% | 88.6% | 9.7% | noisy |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.04 | 5.98..6.49 | 4.2% | 8.4% | 1.0% | stable |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.04 | 5.98..6.49 | 4.2% | 8.4% | 1.0% | stable |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.19 | 0.17..0.22 | 11.5% | 23.0% | 7.5% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.19 | 0.17..0.22 | 11.5% | 23.0% | 7.5% | moderate |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.05 | 0.05..0.05 | 2.0% | 3.9% | 2.0% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.05 | 0.05..0.05 | 2.0% | 3.9% | 2.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.40 | 0.39..0.41 | 1.8% | 3.5% | 0.8% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.40 | 0.39..0.41 | 1.8% | 3.5% | 0.8% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.72 | 3.68..3.75 | 0.9% | 1.9% | 0.4% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.72 | 3.68..3.75 | 0.9% | 1.9% | 0.4% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.44 | 0.36..0.55 | 20.9% | 41.9% | 8.1% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.44 | 0.36..0.55 | 20.9% | 41.9% | 8.1% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.06 | 0.06..0.07 | 4.9% | 9.8% | 1.6% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.06 | 0.06..0.07 | 4.9% | 9.8% | 1.6% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 4.36 | 4.12..4.56 | 5.1% | 10.2% | 0.3% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 4.36 | 4.12..4.56 | 5.1% | 10.2% | 0.3% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.40 | 0.40..0.41 | 1.4% | 2.8% | 0.8% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.40 | 0.40..0.41 | 1.4% | 2.8% | 0.8% | stable |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 0.79 | 0.79..0.83 | 2.8% | 5.5% | 0.6% | stable |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 0.79 | 0.79..0.83 | 2.8% | 5.5% | 0.6% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.04 | 0.04..0.05 | 7.8% | 15.6% | 6.7% | moderate |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.04 | 0.04..0.05 | 7.8% | 15.6% | 6.7% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.07 | 0.06..0.07 | 13.4% | 26.9% | 10.4% | noisy |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.07 | 0.06..0.07 | 13.4% | 26.9% | 10.4% | noisy |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.71 | 0.68..0.89 | 14.7% | 29.5% | 3.5% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.71 | 0.68..0.89 | 14.7% | 29.5% | 3.5% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.48 | 1.43..1.57 | 5.1% | 10.1% | 1.6% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.48 | 1.43..1.57 | 5.1% | 10.1% | 1.6% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.18..0.18 | 0.8% | 1.7% | 0.0% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.18..0.18 | 0.8% | 1.7% | 0.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.10 | 0.10..0.10 | 1.5% | 3.0% | 1.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.10 | 0.10..0.10 | 1.5% | 3.0% | 1.0% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 12.29 | 12.17..12.87 | 2.9% | 5.7% | 0.8% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 12.29 | 12.17..12.87 | 2.9% | 5.7% | 0.8% | stable |


## Comparison vs Previous Run

Previous: `2026-06-24T07-30-24-exp198-direct-buf-int-json.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 6.3% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02 | -0.00 | ±10% / ±0.02 ms | 2.9% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | 3.6% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.29 | -0.01 | ±10% / ±0.03 ms | 1.7% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.29 | -0.01 | ±10% / ±0.03 ms | 1.7% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.33 | 0.30 | -0.03 | ±10% / ±0.03 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.16 | 0.15 | -0.01 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.37 | 0.37 | +0.00 | ±10% / ±0.04 ms | 4.1% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 5.6% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.69 | 0.69 | +0.00 | ±10% / ±0.07 ms | 3.6% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 5.6% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 2.6% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | -0.00 | ±150% / ±0.02 ms | 150.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 108.05 | 110.84 | +2.79 | ±10% / ±11.08 ms | 1.2% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 241.60 | 241.60 | +0.00 | ±10% / ±24.16 ms | 2.1% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 226.22 | 224.99 | -1.23 | ±10% / ±22.62 ms | 1.5% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 13.94 | 13.97 | +0.03 | ±10% / ±1.40 ms | 0.5% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 13.94 | 13.97 | +0.03 | ±10% / ±1.40 ms | 0.5% | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 144183.00 | 153844.00 | +9661.00 | ±10% / ±15384.40 ms | 3.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.02 | 0.01 | -0.01 | ±27% / ±0.02 ms | 22.7% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | -0.01 | ±13% / ±0.02 ms | 12.5% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.03 | -0.01 | ±13% / ±0.02 ms | 12.5% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | -0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | 10.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | 10.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.19 | -0.00 | ±10% / ±0.02 ms | 2.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.19 | -0.00 | ±10% / ±0.02 ms | 2.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 4.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 4.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.34 | 0.34 | -0.00 | ±10% / ±0.03 ms | 0.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.73 | 1.74 | +0.01 | ±10% / ±0.17 ms | 0.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.73 | 1.74 | +0.01 | ±10% / ±0.17 ms | 0.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.27 | 0.27 | -0.00 | ±10% / ±0.03 ms | 0.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.27 | 0.27 | -0.00 | ±10% / ±0.03 ms | 0.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.01 | 4.09 | +0.08 | ±10% / ±0.41 ms | 1.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 20.16 | 21.95 | +1.80 | ±10% / ±2.20 ms | 4.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 20.16 | 21.95 | +1.80 | ±10% / ±2.20 ms | 4.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.52 | 0.52 | -0.00 | ±10% / ±0.05 ms | 1.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 2.68 | 2.70 | +0.02 | ±10% / ±0.27 ms | 1.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 2.68 | 2.70 | +0.02 | ±10% / ±0.27 ms | 1.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.73 | 0.71 | -0.02 | ±10% / ±0.07 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.81 | 3.68 | -0.13 | ±10% / ±0.38 ms | 0.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.81 | 3.68 | -0.13 | ±10% / ±0.38 ms | 0.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | 1.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.53 | 0.52 | -0.01 | ±10% / ±0.05 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.53 | 0.52 | -0.01 | ±10% / ±0.05 ms | 3.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.13 | 10.05 | -0.07 | ±10% / ±1.01 ms | 6.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 40.80 | 41.84 | +1.04 | ±10% / ±4.18 ms | 2.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 40.80 | 41.84 | +1.04 | ±10% / ±4.18 ms | 2.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.05 | 1.03 | -0.02 | ±10% / ±0.10 ms | 0.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 5.51 | 5.59 | +0.08 | ±10% / ±0.56 ms | 3.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 5.51 | 5.59 | +0.08 | ±10% / ±0.56 ms | 3.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03 | -0.00 | ±12% / ±0.02 ms | 8.0% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 5.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 5.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00 | -0.00 | ±25% / ±0.02 ms | 25.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.02 | -0.00 | ±10% / ±0.02 ms | 4.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.02 | -0.00 | ±10% / ±0.02 ms | 4.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.18 | 0.18 | -0.00 | ±10% / ±0.02 ms | 0.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.89 | 0.89 | +0.00 | ±10% / ±0.09 ms | 0.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.89 | 0.89 | +0.00 | ±10% / ±0.09 ms | 0.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.14 | 0.14 | +0.00 | ±10% / ±0.02 ms | 2.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.14 | 0.14 | +0.00 | ±10% / ±0.02 ms | 2.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 1.95 | 1.93 | -0.02 | ±10% / ±0.20 ms | 1.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.76 | 9.50 | -1.26 | ±10% / ±1.08 ms | 5.4% | stable | 🟢 Win (-12%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.76 | 9.50 | -1.26 | ±10% / ±1.08 ms | 5.4% | stable | 🟢 Win (-12%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.26 | 0.26 | -0.00 | ±10% / ±0.03 ms | 0.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.35 | 1.30 | -0.05 | ±10% / ±0.14 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.35 | 1.30 | -0.05 | ±10% / ±0.14 ms | 2.3% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.13 | 0.09 | -0.04 | ±40% / ±0.05 ms | 39.7% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.04 | 0.02 | -0.01 | ±37% / ±0.02 ms | 37.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.26 | 0.26 | +0.00 | ±10% / ±0.03 ms | 0.6% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.26 | 0.25 | -0.00 | ±10% / ±0.03 ms | 2.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 0.8% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.50 | 0.49 | -0.01 | ±10% / ±0.05 ms | 1.0% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 0.8% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.85 | 0.86 | +0.01 | ±10% / ±0.09 ms | 0.3% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.22 | 0.22 | +0.00 | ±10% / ±0.02 ms | 0.5% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.09 | 0.03 | -0.07 | ±188% / ±0.17 ms | 188.5% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.07 | 0.01 | -0.06 | ±290% / ±0.21 ms | 290.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.02 | 0.01 | -0.01 | ±18% / ±0.02 ms | 18.2% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.21 | 0.19 | -0.02 | ±10% / ±0.02 ms | 9.3% | stable | 🟢 Win (-10%) |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.17 | 0.15 | -0.02 | ±10% / ±0.02 ms | 6.2% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04 | -0.01 | ±16% / ±0.02 ms | 7.9% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.73 | 1.73 | +0.00 | ±10% / ±0.17 ms | 2.3% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.44 | 1.44 | +0.00 | ±10% / ±0.14 ms | 2.6% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.29 | 0.27 | -0.02 | ±10% / ±0.03 ms | 3.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.48 | 22.11 | +1.63 | ±10% / ±2.21 ms | 4.8% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 14.98 | 14.64 | -0.34 | ±10% / ±1.50 ms | 0.6% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 2.74 | 2.71 | -0.03 | ±10% / ±0.27 ms | 2.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / Large payload (~650KB) / resqlite s... | 0.28 | 0.23 | -0.05 | ±10% / ±0.03 ms | 9.6% | stable | 🟢 Win (-17%) |
| Select → JSON Bytes / Large payload (~650KB) / resqlite s... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.09 | 0.01 | -0.07 | ±327% / ±0.28 ms | 327.3% | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.02 | 0.00 | -0.02 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.07 | 0.04 | -0.03 | ±120% / ±0.08 ms | 120.2% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | -0.00 | ±30% / ±0.02 ms | 30.0% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.38 | 0.34 | -0.04 | ±10% / ±0.04 ms | 3.4% | stable | 🟢 Win (-11%) |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.06 | 0.05 | -0.00 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 4.02 | 4.04 | +0.02 | ±10% / ±0.40 ms | 5.8% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.51 | 0.51 | +0.00 | ±10% / ±0.05 ms | 2.5% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.21 | 0.18 | -0.04 | ±15% / ±0.03 ms | 7.1% | moderate | 🟢 Win (-17%) |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.21 | 0.18 | -0.04 | ±15% / ±0.03 ms | 7.1% | moderate | 🟢 Win (-17%) |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.56 | 0.52 | -0.04 | ±10% / ±0.06 ms | 2.5% | stable | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.56 | 0.52 | -0.04 | ±10% / ±0.06 ms | 2.5% | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.07 | 0.03 | -0.04 | ±69% / ±0.04 ms | 68.5% | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.07 | 0.03 | -0.04 | ±69% / ±0.04 ms | 68.5% | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.06 | 0.04 | -0.02 | ±10% / ±0.02 ms | 8.3% | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.06 | 0.04 | -0.02 | ±10% / ±0.02 ms | 8.3% | stable | ⚪ Within noise |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 ... | 2.85 | 2.66 | -0.19 | ±10% / ±0.29 ms | 2.1% | stable | ⚪ Within noise |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 ... | 2.85 | 2.66 | -0.19 | ±10% / ±0.29 ms | 2.1% | stable | ⚪ Within noise |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged ... | 2.80 | 2.72 | -0.08 | ±10% / ±0.28 ms | 4.3% | stable | ⚪ Within noise |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged ... | 2.80 | 2.72 | -0.08 | ±10% / ±0.28 ms | 4.3% | stable | ⚪ Within noise |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 1.86 | 1.64 | -0.22 | ±10% / ±0.19 ms | 4.2% | stable | 🟢 Win (-12%) |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 1.86 | 1.64 | -0.22 | ±10% / ±0.19 ms | 4.2% | stable | 🟢 Win (-12%) |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.60 | 3.20 | -0.40 | ±10% / ±0.36 ms | 2.3% | stable | 🟢 Win (-11%) |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.60 | 3.20 | -0.40 | ±10% / ±0.36 ms | 2.3% | stable | 🟢 Win (-11%) |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.87 | 1.80 | -1.07 | ±44% / ±1.27 ms | 44.3% | noisy | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.87 | 1.80 | -1.07 | ±44% / ±1.27 ms | 44.3% | noisy | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 7.06 | 6.04 | -1.02 | ±10% / ±0.71 ms | 4.2% | stable | 🟢 Win (-14%) |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 7.06 | 6.04 | -1.02 | ±10% / ±0.71 ms | 4.2% | stable | 🟢 Win (-14%) |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.21 | 0.19 | -0.03 | ±22% / ±0.05 ms | 11.5% | moderate | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.21 | 0.19 | -0.03 | ±22% / ±0.05 ms | 11.5% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.07 | 0.05 | -0.02 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.07 | 0.05 | -0.02 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.48 | 0.40 | -0.08 | ±10% / ±0.05 ms | 1.8% | stable | 🟢 Win (-18%) |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.48 | 0.40 | -0.08 | ±10% / ±0.05 ms | 1.8% | stable | 🟢 Win (-18%) |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.87 | 3.72 | -0.15 | ±10% / ±0.39 ms | 0.9% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.87 | 3.72 | -0.15 | ±10% / ±0.39 ms | 0.9% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.47 | 0.44 | -0.03 | ±24% / ±0.12 ms | 20.9% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.47 | 0.44 | -0.03 | ±24% / ±0.12 ms | 20.9% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.08 | 0.06 | -0.02 | ±10% / ±0.02 ms | 4.9% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.08 | 0.06 | -0.02 | ±10% / ±0.02 ms | 4.9% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 4.98 | 4.36 | -0.61 | ±10% / ±0.50 ms | 5.1% | stable | 🟢 Win (-12%) |
| Write Performance / Batched Write Inside Transaction (100... | 4.98 | 4.36 | -0.61 | ±10% / ±0.50 ms | 5.1% | stable | 🟢 Win (-12%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.47 | 0.40 | -0.07 | ±10% / ±0.05 ms | 1.4% | stable | 🟢 Win (-16%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.47 | 0.40 | -0.07 | ±10% / ±0.05 ms | 1.4% | stable | 🟢 Win (-16%) |
| Write Performance / Concurrent Single Inserts (100 concur... | 0.87 | 0.79 | -0.08 | ±10% / ±0.09 ms | 2.8% | stable | ⚪ Within noise |
| Write Performance / Concurrent Single Inserts (100 concur... | 0.87 | 0.79 | -0.08 | ±10% / ±0.09 ms | 2.8% | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.04 | -0.01 | ±20% / ±0.02 ms | 7.8% | moderate | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.04 | -0.01 | ±20% / ±0.02 ms | 7.8% | moderate | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.09 | 0.07 | -0.02 | ±31% / ±0.03 ms | 13.4% | noisy | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.09 | 0.07 | -0.02 | ±31% / ±0.03 ms | 13.4% | noisy | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.86 | 0.71 | -0.16 | ±15% / ±0.13 ms | 14.7% | moderate | 🟢 Win (-18%) |
| Write Performance / Nested Transactions (savepoints) / re... | 0.86 | 0.71 | -0.16 | ±15% / ±0.13 ms | 14.7% | moderate | 🟢 Win (-18%) |
| Write Performance / Single Inserts (100 sequential) / res... | 1.68 | 1.48 | -0.20 | ±10% / ±0.17 ms | 5.1% | stable | 🟢 Win (-12%) |
| Write Performance / Single Inserts (100 sequential) / res... | 1.68 | 1.48 | -0.20 | ±10% / ±0.17 ms | 5.1% | stable | 🟢 Win (-12%) |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.18 | +0.00 | ±10% / ±0.02 ms | 0.8% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.18 | +0.00 | ±10% / ±0.02 ms | 0.8% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 1.5% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 1.5% | stable | ⚪ Within noise |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 13.06 | 12.29 | -0.76 | ±10% / ±1.31 ms | 2.9% | stable | ⚪ Within noise |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 13.06 | 12.29 | -0.76 | ±10% / ±1.31 ms | 2.9% | stable | ⚪ Within noise |

**Summary:** 23 wins, 0 regressions, 146 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

✅ **No regressions beyond noise.** 23 benchmarks improved.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.00 | 0.03 | +0.03 MB | ±0.75 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 0.50 | 0.00 | -0.50 MB | ±2.04 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 0.00 | 0.45 | +0.45 MB | ±16.27 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 5.80 | 4.92 | -0.88 MB | ±5.24 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 0.00 | 0.00 | +0.00 MB | ±1.75 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±3.28 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 11.30 | 7.11 | -4.19 MB | ±37.01 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / resqlite select() | 2.58 | 0.34 | -2.24 MB | ±3.04 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite3 select() | 3.28 | 4.55 | +1.27 MB | ±3.95 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 0.50 | 1.00 | +0.50 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.06 | 0.06 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 0 wins, 0 regressions, 15 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 4482 | 3847 | -635 | ±100 | 🟢 Fewer re-emits (-635) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 4199 | 4247 | +48 | ±100 | ⚪ Within noise |

**Granularity summary:** 1 fewer-re-emit, 0 more-re-emit, 5 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


