# resqlite Benchmark Results

Generated: 2026-06-18T07:48:45.974049

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp186-single-row-large-text-bind`
- Repeats: `5`
- Runtime: `dart-vm / Dart 3.11.5`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `exp-186-large-text-bind-encoder @ 485d5f6ab428 (dirty)`
- Comparison baseline: `2026-06-18T07-38-02-baseline-for-exp186.md`
- Comparison mode: `explicit`
- Comparison baseline compatibility: `compatible`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.011 | 0.012 | 0.000 | 0.000 |
| sqlite3 select() | 0.016 | 0.016 | 0.016 | 0.016 |
| sqlite_async select() | 0.031 | 0.039 | 0.001 | 0.002 |
| drift select() | 0.037 | 0.044 | 0.001 | 0.002 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.043 | 0.047 | 0.005 | 0.006 |
| sqlite3 select() | 0.124 | 0.127 | 0.124 | 0.127 |
| sqlite_async select() | 0.130 | 0.132 | 0.010 | 0.010 |
| drift select() | 0.184 | 0.204 | 0.010 | 0.010 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.349 | 0.371 | 0.053 | 0.057 |
| sqlite3 select() | 1.156 | 1.209 | 1.156 | 1.209 |
| sqlite_async select() | 1.044 | 1.092 | 0.089 | 0.092 |
| drift select() | 1.549 | 2.134 | 0.088 | 0.092 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.105 | 11.971 | 0.515 | 2.077 |
| sqlite3 select() | 13.874 | 16.640 | 13.874 | 16.640 |
| sqlite_async select() | 12.175 | 16.020 | 0.898 | 2.209 |
| drift select() | 20.518 | 25.857 | 0.898 | 0.952 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row. The large-payload row isolates resqlite selectBytes because it guards the native bytes transfer policy without multiplying large JSON encoding work across every peer.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.028 | 0.035 | 0.016 | 0.019 |
| sqlite3 + jsonEncode | 0.031 | 0.035 | 0.031 | 0.035 |
| sqlite_async + jsonEncode | 0.044 | 0.046 | 0.016 | 0.016 |
| drift + jsonEncode | 0.051 | 0.053 | 0.016 | 0.016 |
| resqlite selectBytes() | 0.010 | 0.011 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.193 | 0.228 | 0.155 | 0.181 |
| sqlite3 + jsonEncode | 0.263 | 0.285 | 0.263 | 0.285 |
| sqlite_async + jsonEncode | 0.263 | 0.275 | 0.148 | 0.150 |
| drift + jsonEncode | 0.318 | 0.336 | 0.151 | 0.156 |
| resqlite selectBytes() | 0.042 | 0.050 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.797 | 3.573 | 1.489 | 2.636 |
| sqlite3 + jsonEncode | 2.556 | 2.983 | 2.556 | 2.983 |
| sqlite_async + jsonEncode | 2.577 | 4.780 | 1.483 | 2.266 |
| drift + jsonEncode | 2.915 | 3.741 | 1.440 | 2.237 |
| resqlite selectBytes() | 0.349 | 0.361 | 0.000 | 0.000 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 19.793 | 24.401 | 14.713 | 16.436 |
| sqlite3 + jsonEncode | 28.216 | 34.116 | 28.216 | 34.116 |
| sqlite_async + jsonEncode | 26.985 | 33.009 | 14.971 | 16.467 |
| drift + jsonEncode | 36.431 | 41.138 | 14.944 | 18.567 |
| resqlite selectBytes() | 3.505 | 3.587 | 0.000 | 0.001 |

### Large payload (~650KB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.296 | 0.308 | 0.000 | 0.000 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.087 | 0.098 | 0.023 | 0.029 |
| sqlite3 | 0.320 | 0.355 | 0.320 | 0.355 |
| sqlite_async | 0.351 | 0.367 | 0.032 | 0.035 |
| drift | 0.567 | 0.576 | 0.031 | 0.032 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.857 | 0.896 | 0.218 | 0.227 |
| sqlite3 | 3.256 | 3.864 | 3.256 | 3.864 |
| sqlite_async | 2.926 | 3.305 | 0.233 | 0.240 |
| drift | 4.657 | 6.137 | 0.230 | 0.252 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.486 | 0.500 | 0.062 | 0.065 |
| sqlite3 | 1.436 | 1.472 | 1.436 | 1.472 |
| sqlite_async | 1.363 | 1.540 | 0.083 | 0.091 |
| drift | 1.890 | 2.165 | 0.082 | 0.086 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.253 | 0.265 | 0.060 | 0.063 |
| sqlite3 | 0.991 | 1.005 | 0.991 | 1.005 |
| sqlite_async | 0.920 | 0.929 | 0.081 | 0.082 |
| drift | 1.420 | 1.489 | 0.080 | 0.083 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.258 | 0.264 | 0.060 | 0.062 |
| sqlite3 | 0.967 | 1.038 | 0.967 | 1.038 |
| sqlite_async | 0.935 | 0.973 | 0.082 | 0.086 |
| drift | 1.411 | 1.439 | 0.081 | 0.087 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.012 | 0.017 | 0.000 | 0.001 |
| sqlite3 | 0.016 | 0.018 | 0.016 | 0.018 |
| sqlite_async | 0.033 | 0.037 | 0.001 | 0.001 |
| drift | 0.038 | 0.049 | 0.001 | 0.002 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.024 | 0.025 | 0.002 | 0.003 |
| sqlite3 | 0.063 | 0.068 | 0.063 | 0.068 |
| sqlite_async | 0.072 | 0.074 | 0.004 | 0.004 |
| drift | 0.101 | 0.106 | 0.004 | 0.004 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.043 | 0.044 | 0.005 | 0.006 |
| sqlite3 | 0.116 | 0.122 | 0.116 | 0.122 |
| sqlite_async | 0.125 | 0.129 | 0.008 | 0.008 |
| drift | 0.177 | 0.180 | 0.007 | 0.008 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.175 | 0.179 | 0.026 | 0.027 |
| sqlite3 | 0.556 | 0.574 | 0.556 | 0.574 |
| sqlite_async | 0.519 | 0.537 | 0.035 | 0.036 |
| drift | 0.775 | 0.822 | 0.035 | 0.036 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.347 | 0.364 | 0.052 | 0.054 |
| sqlite3 | 1.111 | 1.156 | 1.111 | 1.156 |
| sqlite_async | 1.017 | 1.030 | 0.070 | 0.071 |
| drift | 1.524 | 1.606 | 0.069 | 0.070 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.713 | 0.766 | 0.108 | 0.112 |
| sqlite3 | 2.231 | 2.741 | 2.231 | 2.741 |
| sqlite_async | 2.069 | 2.400 | 0.142 | 0.151 |
| drift | 3.045 | 3.418 | 0.138 | 0.490 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.941 | 3.716 | 0.265 | 0.346 |
| sqlite3 | 5.624 | 7.438 | 5.624 | 7.438 |
| sqlite_async | 5.237 | 5.813 | 0.354 | 0.381 |
| drift | 8.235 | 8.529 | 0.349 | 0.361 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.003 | 10.175 | 0.522 | 0.571 |
| sqlite3 | 13.707 | 16.486 | 13.707 | 16.486 |
| sqlite_async | 11.008 | 12.070 | 0.703 | 0.720 |
| drift | 18.567 | 27.254 | 0.724 | 1.070 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 10.363 | 15.059 | 1.043 | 1.829 |
| sqlite3 | 31.823 | 35.319 | 31.823 | 35.319 |
| sqlite_async | 33.152 | 36.142 | 1.425 | 1.568 |
| drift | 46.651 | 54.013 | 1.413 | 1.477 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.026 | 0.033 | 0.026 | 0.033 |
| sqlite3 + jsonEncode | 0.030 | 0.031 | 0.030 | 0.031 |
| sqlite_async + jsonEncode | 0.045 | 0.047 | 0.045 | 0.047 |
| drift + jsonEncode | 0.052 | 0.057 | 0.052 | 0.057 |
| resqlite selectBytes() | 0.011 | 0.017 | 0.011 | 0.017 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.100 | 0.106 | 0.100 | 0.106 |
| sqlite3 + jsonEncode | 0.131 | 0.140 | 0.131 | 0.140 |
| sqlite_async + jsonEncode | 0.146 | 0.151 | 0.146 | 0.151 |
| drift + jsonEncode | 0.171 | 0.179 | 0.171 | 0.179 |
| resqlite selectBytes() | 0.024 | 0.027 | 0.024 | 0.027 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.190 | 0.196 | 0.190 | 0.196 |
| sqlite3 + jsonEncode | 0.258 | 0.263 | 0.258 | 0.263 |
| sqlite_async + jsonEncode | 0.268 | 0.282 | 0.268 | 0.282 |
| drift + jsonEncode | 0.318 | 0.325 | 0.318 | 0.325 |
| resqlite selectBytes() | 0.041 | 0.044 | 0.041 | 0.044 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.885 | 0.915 | 0.885 | 0.915 |
| sqlite3 + jsonEncode | 1.251 | 1.296 | 1.251 | 1.296 |
| sqlite_async + jsonEncode | 1.231 | 1.296 | 1.231 | 1.296 |
| drift + jsonEncode | 1.476 | 1.608 | 1.476 | 1.608 |
| resqlite selectBytes() | 0.174 | 0.178 | 0.174 | 0.178 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.730 | 1.768 | 1.730 | 1.768 |
| sqlite3 + jsonEncode | 2.552 | 4.242 | 2.552 | 4.242 |
| sqlite_async + jsonEncode | 2.408 | 2.926 | 2.408 | 2.926 |
| drift + jsonEncode | 2.958 | 3.650 | 2.958 | 3.650 |
| resqlite selectBytes() | 0.345 | 0.365 | 0.345 | 0.365 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.703 | 7.230 | 3.703 | 7.230 |
| sqlite3 + jsonEncode | 5.303 | 8.290 | 5.303 | 8.290 |
| sqlite_async + jsonEncode | 5.149 | 8.083 | 5.149 | 8.083 |
| drift + jsonEncode | 6.037 | 10.109 | 6.037 | 10.109 |
| resqlite selectBytes() | 0.668 | 0.710 | 0.668 | 0.710 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 9.724 | 13.164 | 9.724 | 13.164 |
| sqlite3 + jsonEncode | 14.300 | 17.560 | 14.300 | 17.560 |
| sqlite_async + jsonEncode | 14.224 | 17.842 | 14.224 | 17.842 |
| drift + jsonEncode | 16.712 | 21.052 | 16.712 | 21.052 |
| resqlite selectBytes() | 1.679 | 1.777 | 1.679 | 1.777 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 22.550 | 23.870 | 22.550 | 23.870 |
| sqlite3 + jsonEncode | 28.371 | 34.439 | 28.371 | 34.439 |
| sqlite_async + jsonEncode | 31.300 | 32.073 | 31.300 | 32.073 |
| drift + jsonEncode | 35.950 | 39.763 | 35.950 | 39.763 |
| resqlite selectBytes() | 3.361 | 3.434 | 3.361 | 3.434 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 43.242 | 44.771 | 43.242 | 44.771 |
| sqlite3 + jsonEncode | 61.886 | 67.217 | 61.886 | 67.217 |
| sqlite_async + jsonEncode | 61.242 | 69.131 | 61.242 | 69.131 |
| drift + jsonEncode | 80.612 | 93.036 | 80.612 | 93.036 |
| resqlite selectBytes() | 7.648 | 8.687 | 7.648 | 8.687 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.29 | 0.31 | 0.29 |
| sqlite_async | 0.96 | 1.07 | 0.96 |
| drift | 1.47 | 1.62 | 1.47 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.33 | 0.15 |
| sqlite_async | 1.42 | 1.68 | 0.71 |
| drift | 2.68 | 3.03 | 1.34 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.37 | 0.69 | 0.09 |
| sqlite_async | 2.37 | 3.98 | 0.59 |
| drift | 5.08 | 5.53 | 1.27 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.74 | 1.79 | 0.09 |
| sqlite_async | 4.78 | 5.14 | 0.60 |
| drift | 10.45 | 10.85 | 1.31 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 148207 |
| resqlite per query | 0.007 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 148207 | 139954..152272 | 4.2 | 12.8 |
| sqlite3 | 198395 | 197991..199212 | 0.3 | 1.1 |
| sqlite_async | 51906 | 51579..52062 | 0.5 | 1.9 |
| drift | 47739 | 47498..47882 | 0.4 | 0.9 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 13.968 | 14.179 | 13.968 | 14.179 |
| sqlite_async | 36.311 | 37.065 | 36.311 | 37.065 |
| drift | 52.341 | 52.985 | 52.341 | 52.985 |
| sqlite3 (no cache) | 23.957 | 24.206 | 23.957 | 24.206 |
| sqlite3 (cached stmt) | 23.708 | 23.958 | 23.708 | 23.958 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.467 | 2.396 | 1.467 | 2.396 |
| sqlite3 execute() | 0.872 | 1.514 | 0.872 | 1.514 |
| sqlite_async execute() | 2.678 | 3.265 | 2.678 | 3.265 |
| drift execute() | 2.578 | 3.282 | 2.578 | 3.282 |

### Concurrent Single Inserts (100 concurrent)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite concurrent execute() | 0.796 | 1.158 | 0.796 | 1.158 |
| sqlite3 concurrent execute() | 0.850 | 1.509 | 0.850 | 1.509 |
| sqlite_async concurrent execute() | 2.563 | 3.258 | 2.563 | 3.258 |
| drift concurrent execute() | 1.629 | 2.315 | 1.629 | 2.315 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.050 | 0.052 | 0.050 | 0.052 |
| sqlite3 executeBatch() | 0.048 | 0.049 | 0.048 | 0.049 |
| sqlite_async executeBatch() | 0.098 | 0.103 | 0.098 | 0.103 |
| drift executeBatch() | 0.108 | 0.113 | 0.108 | 0.113 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.394 | 0.433 | 0.394 | 0.433 |
| sqlite3 executeBatch() | 0.428 | 0.454 | 0.428 | 0.454 |
| sqlite_async executeBatch() | 0.516 | 0.541 | 0.516 | 0.541 |
| drift executeBatch() | 0.642 | 0.656 | 0.642 | 0.656 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 3.704 | 4.288 | 3.704 | 4.288 |
| sqlite3 executeBatch() | 4.096 | 4.405 | 4.096 | 4.405 |
| sqlite_async executeBatch() | 4.672 | 5.068 | 4.672 | 5.068 |
| drift executeBatch() | 5.884 | 6.632 | 5.884 | 6.632 |

### Wide Batch Insert (10000 rows x 20 params)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 12.341 | 20.341 | 12.341 | 20.341 |
| sqlite3 executeBatch() | 18.850 | 21.112 | 18.850 | 21.112 |
| sqlite_async executeBatch() | 21.317 | 23.483 | 21.317 | 23.483 |
| drift executeBatch() | 25.447 | 28.075 | 25.447 | 28.075 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.045 | 0.050 | 0.045 | 0.050 |
| sqlite_async writeTransaction() | 0.085 | 0.092 | 0.085 | 0.092 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.063 | 0.068 | 0.063 | 0.068 |
| resqlite tx.execute() loop | 0.359 | 0.616 | 0.359 | 0.616 |
| sqlite_async tx.execute() loop | 0.992 | 1.115 | 0.992 | 1.115 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.391 | 0.470 | 0.391 | 0.470 |
| resqlite tx.execute() loop | 4.272 | 5.176 | 4.272 | 5.176 |
| sqlite_async tx.execute() loop | 9.373 | 9.905 | 9.373 | 9.905 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.101 | 0.106 | 0.101 | 0.106 |
| sqlite_async tx.getAll() | 0.200 | 0.231 | 0.200 | 0.231 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.177 | 0.185 | 0.177 | 0.185 |
| sqlite_async tx.getAll() | 0.347 | 0.360 | 0.347 | 0.360 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 0.775 | 0.804 | 0.775 | 0.804 |
| resqlite nested transaction() depth=5 | 0.065 | 0.082 | 0.065 | 0.082 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.027 | 0.030 | 0.027 | 0.030 |
| sqlite_async watch() | 0.103 | 0.123 | 0.103 | 0.123 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.041 | 0.062 | 0.041 | 0.062 |
| sqlite_async | 0.065 | 0.078 | 0.065 | 0.078 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.192 | 0.239 | 0.192 | 0.239 |
| sqlite_async | 0.486 | 1.045 | 0.486 | 1.045 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.725 | 2.127 | 1.725 | 2.127 |

### Long-Payload Unchanged Fanout (8 streams, 64 rows x 32KB TEXT + 32KB BLOB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.762 | 3.106 | 2.762 | 3.106 |

### Long-Text 32KB Unchanged Fanout (8 unchanged streams, 64 rows x 32KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.882 | 3.701 | 2.882 | 3.701 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.201 | 0.228 | 0.201 | 0.228 |
| sqlite_async | 0.232 | 0.332 | 0.232 | 0.332 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.581 | 1.581 | 1.581 | 1.581 |
| sqlite_async | 8.785 | 8.785 | 8.785 | 8.785 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.194 | 3.718 | 3.194 | 3.718 |
| sqlite_async | 5.236 | 6.222 | 5.236 | 6.222 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.517 | 0.700 | 0.517 | 0.700 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 6.009 | 6.457 | 6.009 | 6.457 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. For resqlite, this emission metric can reflect writer-side column-level invalidation, experiment 075's native result-hash short-circuit, or both. Use A11c (Many-Streams Writer Throughput) when the question is specifically writer-side dispatch elision.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 66.7 | 0.000 |
| sqlite_async | 4272 | 1151.3 | 1.004 |
| drift | 5000 | 1003.4 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 67.3 | 0.000 |
| sqlite_async | 4256 | 1157.1 | 1.004 |
| drift | 5000 | 993.8 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 221.38 | 228.08 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 442.68 | 444.07 | 0.00 | 0.00 | 1105 | 3 |
| drift stream() | 552.09 | 553.12 | 0.01 | 0.01 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.018 | 0.029 | 0.000 | 0.000 |
| sqlite3 | 0.018 | 0.022 | 0.018 | 0.022 |
| sqlite_async | 0.035 | 0.042 | 0.000 | 0.000 |
| drift | 0.035 | 0.043 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.014 | 0.021 | 0.000 | 0.000 |
| sqlite3 | 0.011 | 0.014 | 0.011 | 0.014 |
| sqlite_async | 0.028 | 0.033 | 0.000 | 0.000 |
| drift | 0.029 | 0.035 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.023 | 0.033 | 0.000 | 0.000 |
| sqlite3 | 0.030 | 0.032 | 0.030 | 0.032 |
| sqlite_async | 0.055 | 0.064 | 0.000 | 0.000 |
| drift | 0.053 | 0.057 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.008 | 0.014 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.020 | 0.024 | 0.000 | 0.000 |
| drift | 0.019 | 0.023 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.038 | 0.039 | 0.001 | 0.001 |
| sqlite3 | 0.065 | 0.070 | 0.065 | 0.070 |
| sqlite_async | 0.081 | 0.085 | 0.001 | 0.001 |
| drift | 0.090 | 0.095 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 111.249 | 111.613 | 0.000 | 0.000 | 0 |
| sqlite_async | 219.127 | 220.122 | 0.000 | 0.000 | 40 |
| drift | 230.539 | 231.425 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 240.37 | 240.37 | 0.00 | 0.00 | 13.26 | 228.39 | 0 |
| sqlite_async | 484.26 | 484.26 | 0.00 | 0.00 | 25.05 | 459.21 | 1184 |
| drift | 1707.41 | 1707.41 | 0.69 | 0.69 | 14.01 | 1694.17 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 0.00 | 10.09 | 0.00..1.95 | ±0.98 |
| sqlite3 select() | 2.03 | 8.70 | 0.53..6.64 | ±3.05 |
| sqlite_async select() | 1.00 | 1.00 | 1.00..1.00 | ±0.00 |
| drift select() | 10.83 | 74.61 | 0.00..74.16 | ±37.08 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 1.38 | 0.00..0.00 | ±0.00 |
| resqlite + jsonEncode | 0.00 | 23.75 | 0.00..0.00 | ±0.00 |
| sqlite3 + jsonEncode | 1.33 | 69.48 | 0.00..48.81 | ±24.41 |
| sqlite_async + jsonEncode | 0.00 | 11.58 | 0.00..3.02 | ±1.51 |
| drift + jsonEncode | 0.00 | 67.42 | 0.00..2.03 | ±1.02 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 1.39 | 4.59 | 0.42..3.00 | ±1.29 |
| sqlite3 executeBatch() | 0.00 | 0.50 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.02 | 0.55 | 0.00..0.03 | ±0.02 |
| drift batch() | 0.00 | 2.52 | 0.00..0.50 | ±0.25 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.13 | 0.06..0.06 | ±0.00 |
| sqlite_async watch() | 0.00 | 0.30 | 0.00..0.00 | ±0.00 |

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
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.02 | 0.02..0.03 | 4.2% | 8.3% | 4.2% | moderate |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02..0.02 | 5.6% | 11.1% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.01..0.01 | 7.1% | 14.3% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.29 | 0.29..0.30 | 1.7% | 3.4% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.29 | 0.29..0.30 | 1.7% | 3.4% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.30 | 0.30..0.33 | 5.0% | 10.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.15 | 0.15..0.16 | 3.3% | 6.7% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.37 | 0.36..0.37 | 1.4% | 2.7% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.09 | 0.09..0.09 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.70 | 0.68..0.74 | 4.3% | 8.6% | 1.4% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.09 | 0.09..0.09 | 0.0% | 0.0% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.04 | 1.3% | 2.6% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 150.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 110.71 | 109.26..111.27 | 0.9% | 1.8% | 0.5% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 240.37 | 239.30..241.41 | 0.4% | 0.9% | 0.4% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 225.29 | 221.38..225.80 | 1.0% | 2.0% | 0.2% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 13.97 | 13.86..14.14 | 1.0% | 2.0% | 0.3% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 13.97 | 13.86..14.14 | 1.0% | 2.0% | 0.3% | stable |
| Point Query Throughput / resqlite qps | 154596.00 | 148207.00..154977.00 | 2.2% | 4.4% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.02 | 25.0% | 50.0% | 8.3% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.04 | 16.1% | 32.1% | 7.1% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.04 | 16.1% | 32.1% | 7.1% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.01 | 9.1% | 18.2% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.01 | 9.1% | 18.2% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.04..0.05 | 14.0% | 27.9% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.19 | 0.19..0.20 | 3.4% | 6.8% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.19 | 0.19..0.20 | 3.4% | 6.8% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.05 | 7.1% | 14.3% | 2.4% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.04 | 0.04..0.05 | 7.1% | 14.3% | 2.4% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.35 | 0.34..0.35 | 1.0% | 2.0% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.74 | 1.72..1.79 | 1.8% | 3.7% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.74 | 1.72..1.79 | 1.8% | 3.7% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.05 | 0.05..0.05 | 1.0% | 1.9% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.34 | 0.34..0.35 | 1.0% | 2.0% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.34 | 0.34..0.35 | 1.0% | 2.0% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.08 | 4.00..4.15 | 1.8% | 3.7% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 22.10 | 20.45..22.55 | 4.7% | 9.5% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 22.10 | 20.45..22.55 | 4.7% | 9.5% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.53 | 0.52..0.53 | 0.8% | 1.5% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 3.41 | 3.36..3.50 | 2.1% | 4.2% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 3.41 | 3.36..3.50 | 2.1% | 4.2% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.71 | 0.70..0.72 | 1.2% | 2.4% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.70 | 3.67..3.74 | 0.9% | 1.9% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.70 | 3.67..3.74 | 0.9% | 1.9% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.11 | 0.11..0.11 | 0.9% | 1.9% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.67 | 0.66..0.69 | 1.8% | 3.6% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.67 | 0.66..0.69 | 1.8% | 3.6% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.36 | 9.93..10.60 | 3.2% | 6.5% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 42.43 | 41.46..43.24 | 2.1% | 4.2% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 42.43 | 41.46..43.24 | 2.1% | 4.2% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.04 | 1.03..1.05 | 0.8% | 1.6% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 7.24 | 7.10..7.65 | 3.8% | 7.5% | 1.3% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 7.24 | 7.10..7.65 | 3.8% | 7.5% | 1.3% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.02 | 0.02..0.03 | 6.2% | 12.5% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10..0.10 | 2.0% | 3.9% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.10 | 0.10..0.10 | 2.0% | 3.9% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.00 | 16.7% | 33.3% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.02..0.03 | 4.0% | 8.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.02..0.03 | 4.0% | 8.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.18 | 0.17..0.18 | 1.1% | 2.3% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.89 | 0.88..0.93 | 2.4% | 4.8% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.89 | 0.88..0.93 | 2.4% | 4.8% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.03 | 0.03..0.03 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.17 | 0.17..0.18 | 1.1% | 2.3% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.17 | 0.17..0.18 | 1.1% | 2.3% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 1.94 | 1.92..2.03 | 2.8% | 5.7% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 9.74 | 9.72..11.61 | 9.7% | 19.4% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 9.74 | 9.72..11.61 | 9.7% | 19.4% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.26 | 0.26..0.28 | 2.9% | 5.7% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 1.68 | 1.67..1.81 | 4.3% | 8.7% | 0.1% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 1.68 | 1.67..1.81 | 4.3% | 8.7% | 0.1% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.09 | 0.09..0.11 | 13.8% | 27.6% | 1.1% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.02 | 0.02..0.03 | 21.7% | 43.5% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.26 | 0.26..0.27 | 1.9% | 3.9% | 0.4% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.06 | 0.06..0.06 | 1.7% | 3.3% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.26 | 0.25..0.26 | 2.1% | 4.3% | 1.6% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.06 | 0.06..0.06 | 1.6% | 3.3% | 1.6% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.49 | 0.49..0.52 | 3.1% | 6.1% | 0.6% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.06 | 0.06..0.06 | 1.6% | 3.2% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.86 | 0.85..0.86 | 0.5% | 0.9% | 0.2% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.22 | 0.22..0.22 | 0.2% | 0.5% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.13 | 183.3% | 366.7% | 3.7% | moderate |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.01..0.10 | 271.9% | 543.7% | 6.3% | moderate |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 40.9% | 81.8% | 9.1% | noisy |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.19 | 0.19..0.23 | 11.5% | 22.9% | 0.5% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.15 | 0.15..0.18 | 10.8% | 21.6% | 0.7% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.05 | 11.4% | 22.7% | 4.5% | moderate |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.79 | 1.74..1.80 | 1.9% | 3.7% | 0.6% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.47 | 1.44..1.49 | 1.6% | 3.2% | 1.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.36 | 0.35..0.36 | 2.0% | 3.9% | 0.8% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 22.01 | 19.79..22.12 | 5.3% | 10.6% | 0.5% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 14.73 | 14.70..14.78 | 0.3% | 0.6% | 0.1% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.50 | 3.50..3.53 | 0.4% | 0.9% | 0.1% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / Large payload (~650KB) / resqlite selectBytes() | 0.27 | 0.26..0.30 | 7.5% | 15.0% | 3.4% | moderate |
| Select → JSON Bytes / Large payload (~650KB) / resqlite selectBytes... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.08 | 287.5% | 575.0% | 8.3% | noisy |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.04 | 0.04..0.06 | 22.1% | 44.2% | 2.3% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 30.0% | 60.0% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.34 | 0.34..0.38 | 6.1% | 12.2% | 0.3% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.05 | 0.05..0.06 | 3.8% | 7.7% | 1.9% | stable |
| Select → Maps / 10000 rows / resqlite select() | 4.11 | 4.01..4.27 | 3.2% | 6.3% | 1.8% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.52 | 0.51..0.52 | 0.8% | 1.6% | 0.8% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.20 | 0.19..0.23 | 9.9% | 19.8% | 2.0% | stable |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.20 | 0.19..0.23 | 9.9% | 19.8% | 2.0% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.53 | 0.52..0.54 | 2.3% | 4.6% | 1.0% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.53 | 0.52..0.54 | 2.3% | 4.6% | 1.0% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03..0.07 | 72.2% | 144.4% | 0.0% | stable |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03..0.07 | 72.2% | 144.4% | 0.0% | stable |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.04..0.05 | 10.2% | 20.5% | 6.8% | moderate |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.04..0.05 | 10.2% | 20.5% | 6.8% | moderate |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows x 32K... | 2.69 | 2.67..2.82 | 2.8% | 5.5% | 0.6% | stable |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows x 32K... | 2.69 | 2.67..2.82 | 2.8% | 5.5% | 0.6% | stable |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged streams, 6... | 2.84 | 2.76..2.88 | 2.1% | 4.3% | 1.6% | stable |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged streams, 6... | 2.84 | 2.76..2.88 | 2.1% | 4.3% | 1.6% | stable |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 1.67 | 1.64..1.81 | 5.2% | 10.4% | 1.9% | stable |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 1.67 | 1.64..1.81 | 5.2% | 10.4% | 1.9% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.19 | 3.13..3.27 | 2.2% | 4.4% | 0.9% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.19 | 3.13..3.27 | 2.2% | 4.4% | 0.9% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.73 | 1.58..3.01 | 41.5% | 82.9% | 8.4% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.73 | 1.58..3.01 | 41.5% | 82.9% | 8.4% | noisy |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.00 | 5.97..6.50 | 4.4% | 8.8% | 0.4% | stable |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.00 | 5.97..6.50 | 4.4% | 8.8% | 0.4% | stable |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.20 | 0.19..0.23 | 10.3% | 20.7% | 5.4% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.20 | 0.19..0.23 | 10.3% | 20.7% | 5.4% | moderate |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.05 | 0.05..0.05 | 2.0% | 4.0% | 0.0% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.05 | 0.05..0.05 | 2.0% | 4.0% | 0.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.40 | 0.39..0.40 | 1.3% | 2.5% | 0.5% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.40 | 0.39..0.40 | 1.3% | 2.5% | 0.5% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.71 | 3.68..3.74 | 0.8% | 1.6% | 0.3% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.71 | 3.68..3.74 | 0.8% | 1.6% | 0.3% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.53 | 0.36..0.56 | 18.8% | 37.5% | 4.9% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.53 | 0.36..0.56 | 18.8% | 37.5% | 4.9% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.06 | 0.06..0.07 | 3.2% | 6.3% | 1.6% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.06 | 0.06..0.07 | 3.2% | 6.3% | 1.6% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 4.27 | 4.14..4.57 | 5.0% | 10.1% | 1.6% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 4.27 | 4.14..4.57 | 5.0% | 10.1% | 1.6% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.39 | 0.39..0.42 | 3.2% | 6.3% | 0.8% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.39 | 0.39..0.42 | 3.2% | 6.3% | 0.8% | stable |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 0.81 | 0.79..0.84 | 3.4% | 6.7% | 1.1% | stable |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 0.81 | 0.79..0.84 | 3.4% | 6.7% | 1.1% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.04 | 0.04..0.05 | 4.4% | 8.9% | 2.2% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.04 | 0.04..0.05 | 4.4% | 8.9% | 2.2% | stable |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.07 | 0.06..0.07 | 11.5% | 23.1% | 7.7% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.07 | 0.06..0.07 | 11.5% | 23.1% | 7.7% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.75 | 0.59..0.78 | 12.8% | 25.7% | 4.1% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.75 | 0.59..0.78 | 12.8% | 25.7% | 4.1% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.47 | 1.43..1.50 | 2.4% | 4.8% | 1.3% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.47 | 1.43..1.50 | 2.4% | 4.8% | 1.3% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.18..0.18 | 1.7% | 3.4% | 0.6% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.18..0.18 | 1.7% | 3.4% | 0.6% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.10 | 0.10..0.10 | 2.0% | 4.0% | 1.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.10 | 0.10..0.10 | 2.0% | 4.0% | 1.0% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 12.48 | 12.28..12.95 | 2.7% | 5.3% | 1.1% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 12.48 | 12.28..12.95 | 2.7% | 5.3% | 1.1% | stable |


## Comparison vs Previous Run

Previous: `2026-06-18T07-38-02-baseline-for-exp186.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.02 | 0.02 | +0.00 | ±13% / ±0.02 ms | 4.2% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 5.6% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 7.1% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.29 | 0.29 | +0.00 | ±10% / ±0.03 ms | 1.7% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.29 | 0.29 | +0.00 | ±10% / ±0.03 ms | 1.7% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.32 | 0.30 | -0.02 | ±10% / ±0.03 ms | 5.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.16 | 0.15 | -0.01 | ±10% / ±0.02 ms | 3.3% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.37 | 0.37 | +0.00 | ±10% / ±0.04 ms | 1.4% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.68 | 0.70 | +0.02 | ±10% / ±0.07 ms | 4.3% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 1.3% | stable | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±150% / ±0.02 ms | 150.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 108.48 | 110.71 | +2.23 | ±10% / ±11.07 ms | 0.9% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 238.81 | 240.37 | +1.56 | ±10% / ±24.04 ms | 0.4% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 224.79 | 225.29 | +0.50 | ±10% / ±22.53 ms | 1.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.10 | 13.97 | -0.13 | ±10% / ±1.41 ms | 1.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.10 | 13.97 | -0.13 | ±10% / ±1.41 ms | 1.0% | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 151887.00 | 154596.00 | +2709.00 | ±10% / ±15459.60 ms | 2.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01 | +0.00 | ±25% / ±0.02 ms | 25.0% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±21% / ±0.02 ms | 16.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.03 | +0.00 | ±21% / ±0.02 ms | 16.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | 9.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | 9.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.04 | -0.00 | ±14% / ±0.02 ms | 14.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.20 | 0.19 | -0.01 | ±10% / ±0.02 ms | 3.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.20 | 0.19 | -0.01 | ±10% / ±0.02 ms | 3.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 7.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 7.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.36 | 0.35 | -0.01 | ±10% / ±0.04 ms | 1.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.81 | 1.74 | -0.07 | ±10% / ±0.18 ms | 1.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.81 | 1.74 | -0.07 | ±10% / ±0.18 ms | 1.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.05 | 0.05 | -0.00 | ±10% / ±0.02 ms | 1.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.34 | -0.01 | ±10% / ±0.04 ms | 1.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.34 | -0.01 | ±10% / ±0.04 ms | 1.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.38 | 4.08 | -0.30 | ±10% / ±0.44 ms | 1.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 21.81 | 22.10 | +0.29 | ±10% / ±2.21 ms | 4.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 21.81 | 22.10 | +0.29 | ±10% / ±2.21 ms | 4.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.54 | 0.53 | -0.01 | ±10% / ±0.05 ms | 0.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.51 | 3.41 | -0.10 | ±10% / ±0.35 ms | 2.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.51 | 3.41 | -0.10 | ±10% / ±0.35 ms | 2.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.74 | 0.71 | -0.02 | ±10% / ±0.07 ms | 1.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.94 | 3.70 | -0.24 | ±10% / ±0.39 ms | 0.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.94 | 3.70 | -0.24 | ±10% / ±0.39 ms | 0.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | 0.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.71 | 0.67 | -0.04 | ±10% / ±0.07 ms | 1.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.71 | 0.67 | -0.04 | ±10% / ±0.07 ms | 1.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.64 | 10.36 | -0.28 | ±10% / ±1.06 ms | 3.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 45.39 | 42.43 | -2.97 | ±10% / ±4.54 ms | 2.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 45.39 | 42.43 | -2.97 | ±10% / ±4.54 ms | 2.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.09 | 1.04 | -0.05 | ±10% / ±0.11 ms | 0.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.03 | 7.24 | -0.79 | ±10% / ±0.80 ms | 3.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.03 | 7.24 | -0.79 | ±10% / ±0.80 ms | 3.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.02 | -0.00 | ±10% / ±0.02 ms | 6.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.10 | -0.01 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.11 | 0.10 | -0.01 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±17% / ±0.02 ms | 16.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 4.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 4.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.18 | 0.18 | -0.00 | ±10% / ±0.02 ms | 1.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.91 | 0.89 | -0.02 | ±10% / ±0.09 ms | 2.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.91 | 0.89 | -0.02 | ±10% / ±0.09 ms | 2.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.03 | 0.03 | -0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.17 | -0.01 | ±10% / ±0.02 ms | 1.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.18 | 0.17 | -0.01 | ±10% / ±0.02 ms | 1.1% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.05 | 1.94 | -0.11 | ±10% / ±0.20 ms | 2.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.82 | 9.74 | -1.08 | ±10% / ±1.08 ms | 9.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.82 | 9.74 | -1.08 | ±10% / ±1.08 ms | 9.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.27 | 0.26 | -0.01 | ±10% / ±0.03 ms | 2.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.72 | 1.68 | -0.04 | ±10% / ±0.17 ms | 4.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.72 | 1.68 | -0.04 | ±10% / ±0.17 ms | 4.3% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.09 | 0.09 | -0.00 | ±14% / ±0.02 ms | 13.8% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.02 | 0.02 | +0.00 | ±22% / ±0.02 ms | 21.7% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.27 | 0.26 | -0.01 | ±10% / ±0.03 ms | 1.9% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.06 | 0.06 | -0.00 | ±10% / ±0.02 ms | 1.7% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.27 | 0.26 | -0.01 | ±10% / ±0.03 ms | 2.1% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.06 | 0.06 | -0.00 | ±10% / ±0.02 ms | 1.6% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.50 | 0.49 | -0.02 | ±10% / ±0.05 ms | 3.1% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.06 | 0.06 | -0.00 | ±10% / ±0.02 ms | 1.6% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.89 | 0.86 | -0.03 | ±10% / ±0.09 ms | 0.5% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.23 | 0.22 | -0.01 | ±10% / ±0.02 ms | 0.2% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | -0.00 | ±183% / ±0.05 ms | 183.3% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02 | +0.00 | ±272% / ±0.04 ms | 271.9% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | +0.00 | ±41% / ±0.02 ms | 40.9% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.19 | -0.01 | ±11% / ±0.02 ms | 11.5% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.16 | 0.15 | -0.00 | ±11% / ±0.02 ms | 10.8% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04 | +0.00 | ±14% / ±0.02 ms | 11.4% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.84 | 1.79 | -0.05 | ±10% / ±0.18 ms | 1.9% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.52 | 1.47 | -0.05 | ±10% / ±0.15 ms | 1.6% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.36 | 0.36 | -0.00 | ±10% / ±0.04 ms | 2.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 21.02 | 22.01 | +0.99 | ±10% / ±2.20 ms | 5.3% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 15.24 | 14.73 | -0.51 | ±10% / ±1.52 ms | 0.3% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.71 | 3.50 | -0.20 | ±10% / ±0.37 ms | 0.4% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | -0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / Large payload (~650KB) / resqlite s... | 0.32 | 0.27 | -0.05 | ±10% / ±0.03 ms | 7.5% | moderate | 🟢 Win (-16%) |
| Select → JSON Bytes / Large payload (~650KB) / resqlite s... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | +0.00 | ±288% / ±0.03 ms | 287.5% | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.04 | 0.04 | +0.00 | ±22% / ±0.02 ms | 22.1% | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±30% / ±0.02 ms | 30.0% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.35 | 0.34 | -0.01 | ±10% / ±0.04 ms | 6.1% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.05 | 0.05 | -0.00 | ±10% / ±0.02 ms | 3.8% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 4.29 | 4.11 | -0.19 | ±10% / ±0.43 ms | 3.2% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.53 | 0.52 | -0.01 | ±10% / ±0.05 ms | 0.8% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.20 | 0.20 | -0.00 | ±10% / ±0.02 ms | 9.9% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.20 | 0.20 | -0.00 | ±10% / ±0.02 ms | 9.9% | stable | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.52 | 0.53 | +0.00 | ±10% / ±0.05 ms | 2.3% | stable | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.52 | 0.53 | +0.00 | ±10% / ±0.05 ms | 2.3% | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | -0.00 | ±72% / ±0.02 ms | 72.2% | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03 | -0.00 | ±72% / ±0.02 ms | 72.2% | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.04 | +0.00 | ±20% / ±0.02 ms | 10.2% | moderate | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.04 | +0.00 | ±20% / ±0.02 ms | 10.2% | moderate | ⚪ Within noise |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 ... | 2.75 | 2.69 | -0.07 | ±10% / ±0.28 ms | 2.8% | stable | ⚪ Within noise |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 ... | 2.75 | 2.69 | -0.07 | ±10% / ±0.28 ms | 2.8% | stable | ⚪ Within noise |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged ... | 2.81 | 2.84 | +0.03 | ±10% / ±0.28 ms | 2.1% | stable | ⚪ Within noise |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged ... | 2.81 | 2.84 | +0.03 | ±10% / ±0.28 ms | 2.1% | stable | ⚪ Within noise |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 1.74 | 1.67 | -0.07 | ±10% / ±0.17 ms | 5.2% | stable | ⚪ Within noise |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 1.74 | 1.67 | -0.07 | ±10% / ±0.17 ms | 5.2% | stable | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 2.97 | 3.19 | +0.21 | ±10% / ±0.32 ms | 2.2% | stable | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 2.97 | 3.19 | +0.21 | ±10% / ±0.32 ms | 2.2% | stable | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.61 | 1.73 | +0.12 | ±41% / ±0.72 ms | 41.5% | noisy | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.61 | 1.73 | +0.12 | ±41% / ±0.72 ms | 41.5% | noisy | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.05 | 6.00 | -0.05 | ±10% / ±0.60 ms | 4.4% | stable | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.05 | 6.00 | -0.05 | ±10% / ±0.60 ms | 4.4% | stable | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.18 | 0.20 | +0.02 | ±16% / ±0.03 ms | 10.3% | moderate | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.18 | 0.20 | +0.02 | ±16% / ±0.03 ms | 10.3% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.39 | 0.40 | +0.00 | ±10% / ±0.04 ms | 1.3% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.39 | 0.40 | +0.00 | ±10% / ±0.04 ms | 1.3% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.76 | 3.71 | -0.05 | ±10% / ±0.38 ms | 0.8% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.76 | 3.71 | -0.05 | ±10% / ±0.38 ms | 0.8% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.37 | 0.53 | +0.16 | ±19% / ±0.10 ms | 18.8% | moderate | 🔴 Regression (+44%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.37 | 0.53 | +0.16 | ±19% / ±0.10 ms | 18.8% | moderate | 🔴 Regression (+44%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 3.2% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 3.2% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 4.77 | 4.27 | -0.50 | ±10% / ±0.48 ms | 5.0% | stable | 🟢 Win (-10%) |
| Write Performance / Batched Write Inside Transaction (100... | 4.77 | 4.27 | -0.50 | ±10% / ±0.48 ms | 5.0% | stable | 🟢 Win (-10%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.41 | 0.39 | -0.01 | ±10% / ±0.04 ms | 3.2% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.41 | 0.39 | -0.01 | ±10% / ±0.04 ms | 3.2% | stable | ⚪ Within noise |
| Write Performance / Concurrent Single Inserts (100 concur... | 0.80 | 0.81 | +0.00 | ±10% / ±0.08 ms | 3.4% | stable | ⚪ Within noise |
| Write Performance / Concurrent Single Inserts (100 concur... | 0.80 | 0.81 | +0.00 | ±10% / ±0.08 ms | 3.4% | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 4.4% | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 4.4% | stable | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.07 | 0.07 | -0.01 | ±23% / ±0.02 ms | 11.5% | moderate | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.07 | 0.07 | -0.01 | ±23% / ±0.02 ms | 11.5% | moderate | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.81 | 0.75 | -0.06 | ±13% / ±0.10 ms | 12.8% | moderate | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.81 | 0.75 | -0.06 | ±13% / ±0.10 ms | 12.8% | moderate | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.48 | 1.47 | -0.01 | ±10% / ±0.15 ms | 2.4% | stable | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.48 | 1.47 | -0.01 | ±10% / ±0.15 ms | 2.4% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.18 | -0.00 | ±10% / ±0.02 ms | 1.7% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.18 | -0.00 | ±10% / ±0.02 ms | 1.7% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 2.0% | stable | ⚪ Within noise |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 12.59 | 12.48 | -0.11 | ±10% / ±1.26 ms | 2.7% | stable | ⚪ Within noise |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 12.59 | 12.48 | -0.11 | ±10% / ±1.26 ms | 2.7% | stable | ⚪ Within noise |

**Summary:** 3 wins, 2 regressions, 164 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.50 | 0.00 | -0.50 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 1.03 | 1.39 | +0.36 MB | ±1.29 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.02 | +0.02 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 0.97 | 0.00 | -0.97 MB | ±1.02 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 1.27 | 0.00 | -1.27 MB | ±0.50 MB | 🟢 Win (-1.27 MB) |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 6.72 | 1.33 | -5.39 MB | ±24.41 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±1.51 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 10.25 | 10.83 | +0.58 MB | ±37.08 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / resqlite select() | 8.81 | 0.00 | -8.81 MB | ±0.98 MB | 🟢 Win (-8.81 MB) |
| Memory / Select 10k rows → Maps / sqlite3 select() | 5.36 | 2.03 | -3.33 MB | ±3.05 MB | 🟢 Win (-3.33 MB) |
| Memory / Select 10k rows → Maps / sqlite_async select() | 1.00 | 1.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.06 | 0.06 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 3 wins, 0 regressions, 12 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 3799 | 4272 | +473 | ±100 | 🔴 More re-emits (+473) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 4082 | 4256 | +174 | ±100 | 🔴 More re-emits (+174) |

**Granularity summary:** 0 fewer-re-emit, 2 more-re-emit, 4 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


