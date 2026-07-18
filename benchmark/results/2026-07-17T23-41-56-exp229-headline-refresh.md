# resqlite Benchmark Results

Generated: 2026-07-17T23:41:56.796988

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp229-headline-refresh`
- Repeats: `5`
- Runtime: `dart-vm / Dart 3.12.2`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `danreynolds/resqlite-experiments-missing-entries-c551ce @ 5c51bd760a94`
- Comparison baseline: `none`
- Comparison mode: `none`
- Comparison baseline compatibility: `not applicable`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.012 | 0.013 | 0.000 | 0.001 |
| sqlite3 select() | 0.017 | 0.017 | 0.017 | 0.017 |
| sqlite_async select() | 0.032 | 0.034 | 0.001 | 0.002 |
| drift select() | 0.037 | 0.040 | 0.001 | 0.001 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.040 | 0.042 | 0.005 | 0.006 |
| sqlite3 select() | 0.119 | 0.129 | 0.119 | 0.129 |
| sqlite_async select() | 0.128 | 0.146 | 0.010 | 0.010 |
| drift select() | 0.191 | 0.203 | 0.010 | 0.014 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.319 | 0.336 | 0.051 | 0.055 |
| sqlite3 select() | 1.140 | 1.220 | 1.140 | 1.220 |
| sqlite_async select() | 1.059 | 1.137 | 0.093 | 0.101 |
| drift select() | 1.583 | 1.877 | 0.093 | 0.098 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 3.910 | 10.952 | 0.514 | 0.733 |
| sqlite3 select() | 15.108 | 18.381 | 15.108 | 18.381 |
| sqlite_async select() | 12.976 | 17.807 | 0.956 | 2.469 |
| drift select() | 21.061 | 28.375 | 0.956 | 1.414 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row. The large-payload row isolates resqlite selectBytes because it guards the native bytes transfer policy without multiplying large JSON encoding work across every peer.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.028 | 0.043 | 0.016 | 0.023 |
| sqlite3 + jsonEncode | 0.031 | 0.032 | 0.031 | 0.032 |
| sqlite_async + jsonEncode | 0.048 | 0.050 | 0.017 | 0.017 |
| drift + jsonEncode | 0.053 | 0.058 | 0.016 | 0.017 |
| resqlite selectBytes() | 0.011 | 0.016 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.188 | 0.196 | 0.149 | 0.150 |
| sqlite3 + jsonEncode | 0.263 | 0.333 | 0.263 | 0.333 |
| sqlite_async + jsonEncode | 0.287 | 0.349 | 0.160 | 0.171 |
| drift + jsonEncode | 0.353 | 0.424 | 0.163 | 0.177 |
| resqlite selectBytes() | 0.041 | 0.046 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.830 | 3.680 | 1.527 | 3.244 |
| sqlite3 + jsonEncode | 2.707 | 5.379 | 2.707 | 5.379 |
| sqlite_async + jsonEncode | 2.615 | 4.890 | 1.548 | 1.890 |
| drift + jsonEncode | 3.162 | 3.614 | 1.550 | 1.862 |
| resqlite selectBytes() | 0.273 | 0.289 | 0.000 | 0.000 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 23.062 | 26.575 | 15.811 | 17.987 |
| sqlite3 + jsonEncode | 32.012 | 36.406 | 32.012 | 36.406 |
| sqlite_async + jsonEncode | 32.014 | 36.305 | 15.372 | 16.985 |
| drift + jsonEncode | 39.187 | 43.438 | 15.121 | 21.656 |
| resqlite selectBytes() | 2.596 | 2.651 | 0.000 | 0.001 |

### Large payload (~650KB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.271 | 0.293 | 0.000 | 0.000 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.084 | 0.087 | 0.023 | 0.023 |
| sqlite3 | 0.331 | 0.341 | 0.331 | 0.341 |
| sqlite_async | 0.368 | 0.427 | 0.033 | 0.036 |
| drift | 0.566 | 0.627 | 0.032 | 0.037 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.803 | 0.899 | 0.231 | 0.245 |
| sqlite3 | 3.470 | 4.020 | 3.470 | 4.020 |
| sqlite_async | 3.110 | 3.589 | 0.260 | 0.282 |
| drift | 4.984 | 6.096 | 0.266 | 0.279 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.502 | 0.556 | 0.064 | 0.068 |
| sqlite3 | 1.598 | 1.732 | 1.598 | 1.732 |
| sqlite_async | 1.650 | 2.053 | 0.103 | 0.112 |
| drift | 2.031 | 2.275 | 0.091 | 0.099 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.251 | 0.292 | 0.062 | 0.067 |
| sqlite3 | 1.117 | 1.250 | 1.117 | 1.250 |
| sqlite_async | 1.034 | 1.265 | 0.094 | 0.105 |
| drift | 1.555 | 1.767 | 0.092 | 0.099 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.257 | 0.261 | 0.062 | 0.064 |
| sqlite3 | 1.057 | 1.197 | 1.057 | 1.197 |
| sqlite_async | 1.017 | 1.133 | 0.092 | 0.103 |
| drift | 1.522 | 1.767 | 0.091 | 0.096 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.013 | 0.032 | 0.000 | 0.001 |
| sqlite3 | 0.016 | 0.021 | 0.016 | 0.021 |
| sqlite_async | 0.037 | 0.072 | 0.001 | 0.003 |
| drift | 0.049 | 0.071 | 0.001 | 0.002 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.024 | 0.026 | 0.003 | 0.003 |
| sqlite3 | 0.063 | 0.067 | 0.063 | 0.067 |
| sqlite_async | 0.074 | 0.079 | 0.004 | 0.004 |
| drift | 0.123 | 0.138 | 0.004 | 0.005 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.047 | 0.062 | 0.005 | 0.009 |
| sqlite3 | 0.125 | 0.142 | 0.125 | 0.142 |
| sqlite_async | 0.134 | 0.169 | 0.008 | 0.009 |
| drift | 0.213 | 0.227 | 0.008 | 0.009 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.175 | 0.182 | 0.027 | 0.029 |
| sqlite3 | 0.593 | 0.605 | 0.593 | 0.605 |
| sqlite_async | 0.563 | 0.669 | 0.038 | 0.047 |
| drift | 0.871 | 0.911 | 0.039 | 0.044 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.335 | 0.342 | 0.054 | 0.055 |
| sqlite3 | 1.195 | 1.244 | 1.195 | 1.244 |
| sqlite_async | 1.118 | 1.329 | 0.077 | 0.087 |
| drift | 1.694 | 2.361 | 0.078 | 0.098 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.711 | 0.807 | 0.109 | 0.133 |
| sqlite3 | 2.438 | 3.379 | 2.438 | 3.379 |
| sqlite_async | 2.369 | 2.650 | 0.157 | 0.173 |
| drift | 3.433 | 3.850 | 0.154 | 0.561 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.000 | 6.312 | 0.276 | 0.541 |
| sqlite3 | 6.144 | 8.060 | 6.144 | 8.060 |
| sqlite_async | 6.047 | 6.863 | 0.384 | 0.486 |
| drift | 8.873 | 9.241 | 0.381 | 0.401 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.231 | 15.485 | 0.577 | 1.148 |
| sqlite3 | 15.499 | 16.706 | 15.499 | 16.706 |
| sqlite_async | 11.676 | 12.477 | 0.728 | 0.813 |
| drift | 18.872 | 25.465 | 0.742 | 1.100 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 10.116 | 16.038 | 1.064 | 1.964 |
| sqlite3 | 32.742 | 45.401 | 32.742 | 45.401 |
| sqlite_async | 35.291 | 39.055 | 1.453 | 3.473 |
| drift | 53.022 | 60.679 | 1.447 | 2.024 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.026 | 0.027 | 0.026 | 0.027 |
| sqlite3 + jsonEncode | 0.030 | 0.032 | 0.030 | 0.032 |
| sqlite_async + jsonEncode | 0.046 | 0.052 | 0.046 | 0.052 |
| drift + jsonEncode | 0.054 | 0.118 | 0.054 | 0.118 |
| resqlite selectBytes() | 0.011 | 0.011 | 0.011 | 0.011 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.098 | 0.103 | 0.098 | 0.103 |
| sqlite3 + jsonEncode | 0.134 | 0.151 | 0.134 | 0.151 |
| sqlite_async + jsonEncode | 0.146 | 0.149 | 0.146 | 0.149 |
| drift + jsonEncode | 0.172 | 0.195 | 0.172 | 0.195 |
| resqlite selectBytes() | 0.024 | 0.027 | 0.024 | 0.027 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.187 | 0.190 | 0.187 | 0.190 |
| sqlite3 + jsonEncode | 0.262 | 0.292 | 0.262 | 0.292 |
| sqlite_async + jsonEncode | 0.278 | 0.340 | 0.278 | 0.340 |
| drift + jsonEncode | 0.326 | 0.336 | 0.326 | 0.336 |
| resqlite selectBytes() | 0.034 | 0.034 | 0.034 | 0.034 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.927 | 1.256 | 0.927 | 1.256 |
| sqlite3 + jsonEncode | 1.310 | 3.185 | 1.310 | 3.185 |
| sqlite_async + jsonEncode | 1.284 | 1.669 | 1.284 | 1.669 |
| drift + jsonEncode | 1.524 | 3.199 | 1.524 | 3.199 |
| resqlite selectBytes() | 0.130 | 0.137 | 0.130 | 0.137 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.844 | 3.853 | 1.844 | 3.853 |
| sqlite3 + jsonEncode | 2.611 | 5.604 | 2.611 | 5.604 |
| sqlite_async + jsonEncode | 2.467 | 3.915 | 2.467 | 3.915 |
| drift + jsonEncode | 2.963 | 5.742 | 2.963 | 5.742 |
| resqlite selectBytes() | 0.251 | 0.274 | 0.251 | 0.274 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.742 | 6.885 | 3.742 | 6.885 |
| sqlite3 + jsonEncode | 5.565 | 8.662 | 5.565 | 8.662 |
| sqlite_async + jsonEncode | 5.529 | 9.317 | 5.529 | 9.317 |
| drift + jsonEncode | 6.726 | 11.147 | 6.726 | 11.147 |
| resqlite selectBytes() | 0.534 | 0.598 | 0.534 | 0.598 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 10.365 | 16.226 | 10.365 | 16.226 |
| sqlite3 + jsonEncode | 14.728 | 18.571 | 14.728 | 18.571 |
| sqlite_async + jsonEncode | 14.047 | 19.782 | 14.047 | 19.782 |
| drift + jsonEncode | 17.519 | 21.460 | 17.519 | 21.460 |
| resqlite selectBytes() | 1.278 | 1.319 | 1.278 | 1.319 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 22.422 | 24.380 | 22.422 | 24.380 |
| sqlite3 + jsonEncode | 31.629 | 34.826 | 31.629 | 34.826 |
| sqlite_async + jsonEncode | 31.350 | 32.697 | 31.350 | 32.697 |
| drift + jsonEncode | 37.055 | 42.282 | 37.055 | 42.282 |
| resqlite selectBytes() | 2.570 | 2.617 | 2.570 | 2.617 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 43.838 | 46.774 | 43.838 | 46.774 |
| sqlite3 + jsonEncode | 65.298 | 69.806 | 65.298 | 69.806 |
| sqlite_async + jsonEncode | 67.031 | 76.279 | 67.031 | 76.279 |
| drift + jsonEncode | 84.955 | 108.171 | 84.955 | 108.171 |
| resqlite selectBytes() | 5.628 | 6.949 | 5.628 | 6.949 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.28 | 0.35 | 0.28 |
| sqlite_async | 1.05 | 1.14 | 1.05 |
| drift | 1.58 | 1.68 | 1.58 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.28 | 0.31 | 0.14 |
| sqlite_async | 1.51 | 1.84 | 0.75 |
| drift | 2.88 | 3.69 | 1.44 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.31 | 0.71 | 0.08 |
| sqlite_async | 2.56 | 3.29 | 0.64 |
| drift | 5.53 | 6.11 | 1.38 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.63 | 1.18 | 0.08 |
| sqlite_async | 5.21 | 6.61 | 0.65 |
| drift | 10.52 | 11.31 | 1.31 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 137543 |
| resqlite per query | 0.007 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 137543 | 122712..138414 | 5.7 | 5.6 |
| sqlite3 | 187377 | 186817..187921 | 0.3 | 0.9 |
| sqlite_async | 50089 | 50016..50467 | 0.5 | 2.3 |
| drift | 46832 | 46666..47345 | 0.7 | 2.0 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 13.625 | 14.075 | 13.625 | 14.075 |
| sqlite_async | 36.769 | 37.908 | 36.769 | 37.908 |
| drift | 53.988 | 58.428 | 53.988 | 58.428 |
| sqlite3 (no cache) | 24.154 | 25.041 | 24.154 | 25.041 |
| sqlite3 (cached stmt) | 23.978 | 25.122 | 23.978 | 25.122 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.770 | 2.780 | 1.770 | 2.780 |
| sqlite3 execute() | 0.987 | 1.659 | 0.987 | 1.659 |
| sqlite_async execute() | 2.918 | 3.507 | 2.918 | 3.507 |
| drift execute() | 2.840 | 3.652 | 2.840 | 3.652 |

### Concurrent Single Inserts (100 concurrent)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite concurrent execute() | 0.862 | 1.244 | 0.862 | 1.244 |
| sqlite3 concurrent execute() | 0.938 | 1.626 | 0.938 | 1.626 |
| sqlite_async concurrent execute() | 2.656 | 3.363 | 2.656 | 3.363 |
| drift concurrent execute() | 2.082 | 3.393 | 2.082 | 3.393 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.054 | 0.064 | 0.054 | 0.064 |
| sqlite3 executeBatch() | 0.054 | 0.057 | 0.054 | 0.057 |
| sqlite_async executeBatch() | 0.095 | 0.113 | 0.095 | 0.113 |
| drift executeBatch() | 0.124 | 0.196 | 0.124 | 0.196 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.433 | 0.495 | 0.433 | 0.495 |
| sqlite3 executeBatch() | 0.442 | 0.480 | 0.442 | 0.480 |
| sqlite_async executeBatch() | 0.514 | 0.559 | 0.514 | 0.559 |
| drift executeBatch() | 0.640 | 0.774 | 0.640 | 0.774 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 3.828 | 4.479 | 3.828 | 4.479 |
| sqlite3 executeBatch() | 4.057 | 4.321 | 4.057 | 4.321 |
| sqlite_async executeBatch() | 4.757 | 5.301 | 4.757 | 5.301 |
| drift executeBatch() | 6.004 | 6.814 | 6.004 | 6.814 |

### Wide Batch Insert (10000 rows x 20 params)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 13.256 | 24.448 | 13.256 | 24.448 |
| sqlite3 executeBatch() | 18.921 | 21.006 | 18.921 | 21.006 |
| sqlite_async executeBatch() | 23.346 | 29.838 | 23.346 | 29.838 |
| drift executeBatch() | 25.661 | 27.241 | 25.661 | 27.241 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.046 | 0.051 | 0.046 | 0.051 |
| sqlite_async writeTransaction() | 0.081 | 0.088 | 0.081 | 0.088 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.065 | 0.073 | 0.065 | 0.073 |
| resqlite tx.execute() loop | 0.518 | 0.594 | 0.518 | 0.594 |
| sqlite_async tx.execute() loop | 0.984 | 1.182 | 0.984 | 1.182 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.405 | 0.484 | 0.405 | 0.484 |
| resqlite tx.execute() loop | 4.560 | 5.264 | 4.560 | 5.264 |
| sqlite_async tx.execute() loop | 9.426 | 9.892 | 9.426 | 9.892 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.096 | 0.140 | 0.096 | 0.140 |
| sqlite_async tx.getAll() | 0.197 | 0.206 | 0.197 | 0.206 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.170 | 0.175 | 0.170 | 0.175 |
| sqlite_async tx.getAll() | 0.367 | 0.414 | 0.367 | 0.414 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 0.772 | 0.903 | 0.772 | 0.903 |
| resqlite nested transaction() depth=5 | 0.072 | 0.090 | 0.072 | 0.090 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.027 | 0.032 | 0.027 | 0.032 |
| sqlite_async watch() | 0.112 | 0.156 | 0.112 | 0.156 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.070 | 0.104 | 0.070 | 0.104 |
| sqlite_async | 0.076 | 0.126 | 0.076 | 0.126 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.199 | 0.272 | 0.199 | 0.272 |
| sqlite_async | 0.547 | 1.074 | 0.547 | 1.074 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.821 | 3.606 | 1.821 | 3.606 |

### Long-Payload Unchanged Fanout (8 streams, 64 rows x 32KB TEXT + 32KB BLOB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.005 | 3.377 | 3.005 | 3.377 |

### Long-Text 32KB Unchanged Fanout (8 unchanged streams, 64 rows x 32KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.824 | 3.574 | 2.824 | 3.574 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.186 | 0.251 | 0.186 | 0.251 |
| sqlite_async | 0.254 | 0.306 | 0.254 | 0.306 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.136 | 2.136 | 2.136 | 2.136 |
| sqlite_async | 13.668 | 13.668 | 13.668 | 13.668 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.562 | 4.175 | 3.562 | 4.175 |
| sqlite_async | 5.543 | 6.518 | 5.543 | 6.518 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.497 | 0.663 | 0.497 | 0.663 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 6.856 | 8.062 | 6.856 | 8.062 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. For resqlite, this emission metric can reflect writer-side column-level invalidation, experiment 075's native result-hash short-circuit, or both. Use A11c (Many-Streams Writer Throughput) when the question is specifically writer-side dispatch elision.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 69.0 | 0.000 |
| sqlite_async | 3527 | 1053.9 | 0.899 |
| drift | 5000 | 1015.8 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 71.1 | 0.000 |
| sqlite_async | 3925 | 1122.9 | 0.899 |
| drift | 5000 | 1019.9 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 223.33 | 225.74 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 442.23 | 447.02 | 0.00 | 0.00 | 1103 | 3 |
| drift stream() | 555.68 | 567.74 | 0.01 | 0.01 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.020 | 0.032 | 0.000 | 0.000 |
| sqlite3 | 0.019 | 0.026 | 0.019 | 0.026 |
| sqlite_async | 0.039 | 0.055 | 0.000 | 0.000 |
| drift | 0.039 | 0.052 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.015 | 0.022 | 0.000 | 0.000 |
| sqlite3 | 0.012 | 0.016 | 0.012 | 0.016 |
| sqlite_async | 0.030 | 0.040 | 0.000 | 0.000 |
| drift | 0.031 | 0.038 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.024 | 0.034 | 0.000 | 0.000 |
| sqlite3 | 0.031 | 0.034 | 0.031 | 0.034 |
| sqlite_async | 0.057 | 0.069 | 0.000 | 0.000 |
| drift | 0.053 | 0.059 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.008 | 0.015 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.021 | 0.026 | 0.000 | 0.000 |
| drift | 0.019 | 0.024 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.039 | 0.042 | 0.001 | 0.001 |
| sqlite3 | 0.066 | 0.068 | 0.066 | 0.068 |
| sqlite_async | 0.080 | 0.088 | 0.001 | 0.001 |
| drift | 0.092 | 0.105 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 107.812 | 110.374 | 0.000 | 0.000 | 0 |
| sqlite_async | 220.051 | 220.962 | 0.000 | 0.000 | 35 |
| drift | 233.359 | 234.453 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 428.44 | 428.44 | 0.00 | 0.00 | 13.26 | 415.18 | 2 |
| sqlite_async | 472.51 | 472.51 | 0.00 | 0.00 | 13.28 | 459.22 | 1175 |
| drift | 1743.20 | 1743.20 | 0.11 | 0.11 | 15.78 | 1728.01 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 6.31 | 16.63 | 0.00..9.63 | ±4.81 |
| sqlite3 select() | 4.00 | 9.50 | 1.75..9.03 | ±3.64 |
| sqlite_async select() | 1.00 | 1.50 | 1.00..1.00 | ±0.00 |
| drift select() | 6.14 | 74.48 | 0.00..73.83 | ±36.91 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.50 | 18.06 | 0.00..6.61 | ±3.30 |
| resqlite + jsonEncode | 0.61 | 16.52 | 0.00..2.17 | ±1.09 |
| sqlite3 + jsonEncode | 6.48 | 39.13 | 0.00..39.11 | ±19.55 |
| sqlite_async + jsonEncode | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| drift + jsonEncode | 0.97 | 87.64 | 0.00..28.25 | ±14.13 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 5.28 | 10.31 | 3.02..7.97 | ±2.48 |
| sqlite3 executeBatch() | 0.00 | 0.03 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 0.03 | 0.00..0.02 | ±0.01 |
| drift batch() | 0.00 | 2.50 | 0.00..0.31 | ±0.16 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.13 | 0.06..0.06 | ±0.00 |
| sqlite_async watch() | 0.00 | 0.52 | 0.00..0.00 | ±0.00 |

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
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.03 | 0.02..0.03 | 5.8% | 11.5% | 3.8% | moderate |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 11.1% | 22.2% | 11.1% | noisy |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02..0.02 | 11.4% | 22.7% | 9.1% | noisy |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.01..0.02 | 14.7% | 29.4% | 11.8% | noisy |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.28 | 0.27..0.29 | 3.6% | 7.1% | 3.6% | moderate |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.28 | 0.27..0.29 | 3.6% | 7.1% | 3.6% | moderate |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.28 | 0.28..0.31 | 5.4% | 10.7% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.14 | 0.14..0.16 | 7.1% | 14.3% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.34 | 0.31..0.35 | 5.9% | 11.8% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.09 | 0.08..0.09 | 5.6% | 11.1% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.63 | 0.62..0.67 | 4.0% | 7.9% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.08 | 0.08..0.08 | 0.0% | 0.0% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.04 | 3.8% | 7.7% | 2.6% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 100.0% | 200.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 108.44 | 106.13..112.92 | 3.1% | 6.3% | 2.1% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 236.16 | 229.36..428.44 | 42.1% | 84.3% | 1.7% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 221.38 | 216.40..223.33 | 1.6% | 3.1% | 0.9% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 14.03 | 13.63..15.04 | 5.0% | 10.1% | 2.9% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 14.03 | 13.63..15.04 | 5.0% | 10.1% | 2.9% | stable |
| Point Query Throughput / resqlite qps | 136888.00 | 115016.00..138899.00 | 8.7% | 17.4% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.01 | 15.4% | 30.8% | 15.4% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.03 | 14.8% | 29.6% | 3.7% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.03 | 14.8% | 29.6% | 3.7% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.01 | 9.1% | 18.2% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.01 | 9.1% | 18.2% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.04..0.05 | 10.7% | 21.4% | 4.8% | moderate |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.19 | 0.19..0.19 | 1.8% | 3.6% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.19 | 0.19..0.19 | 1.8% | 3.6% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 10.0% | 20.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.04 | 0.03..0.04 | 8.6% | 17.1% | 2.9% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.04 | 0.03..0.04 | 8.6% | 17.1% | 2.9% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.33 | 0.32..0.34 | 2.0% | 4.0% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.83 | 1.77..1.89 | 3.4% | 6.7% | 3.2% | moderate |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.83 | 1.77..1.89 | 3.4% | 6.7% | 3.2% | moderate |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.05 | 0.05..0.05 | 1.9% | 3.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.26 | 0.25..0.28 | 5.7% | 11.4% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.26 | 0.25..0.28 | 5.7% | 11.4% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.09 | 3.92..4.23 | 3.8% | 7.6% | 2.5% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 22.42 | 20.84..23.05 | 4.9% | 9.8% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 22.42 | 20.84..23.05 | 4.9% | 9.8% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.54 | 0.53..0.58 | 4.5% | 9.1% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 2.69 | 2.57..2.74 | 3.2% | 6.5% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 2.69 | 2.57..2.74 | 3.2% | 6.5% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.70 | 0.68..0.73 | 4.2% | 8.4% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.79 | 3.67..3.95 | 3.6% | 7.3% | 3.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.79 | 3.67..3.95 | 3.6% | 7.3% | 3.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.11 | 0.11..0.11 | 1.4% | 2.8% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.51 | 0.49..0.54 | 4.8% | 9.5% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.51 | 0.49..0.54 | 4.8% | 9.5% | 2.2% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.40 | 10.12..11.34 | 5.9% | 11.8% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 43.84 | 41.94..47.51 | 6.4% | 12.7% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 43.84 | 41.94..47.51 | 6.4% | 12.7% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.08 | 1.06..1.11 | 2.0% | 4.0% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 5.63 | 5.38..5.80 | 3.8% | 7.6% | 3.1% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 5.63 | 5.38..5.80 | 3.8% | 7.6% | 3.1% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.02 | 0.02..0.03 | 10.4% | 20.8% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10..0.12 | 10.2% | 20.4% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.10 | 0.10..0.12 | 10.2% | 20.4% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.02 | 0.02..0.03 | 10.4% | 20.8% | 4.2% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.02 | 0.02..0.03 | 10.4% | 20.8% | 4.2% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.17 | 0.16..0.17 | 4.1% | 8.2% | 2.9% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.93 | 0.90..1.01 | 6.1% | 12.3% | 3.0% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.93 | 0.90..1.01 | 6.1% | 12.3% | 3.0% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.03 | 0.03..0.03 | 3.7% | 7.4% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.13 | 0.13..0.14 | 4.1% | 8.3% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.13 | 0.13..0.14 | 4.1% | 8.3% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 1.91 | 1.89..2.00 | 2.9% | 5.8% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 9.99 | 9.54..10.37 | 4.2% | 8.3% | 2.7% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 9.99 | 9.54..10.37 | 4.2% | 8.3% | 2.7% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.27 | 0.27..0.28 | 2.0% | 4.1% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 1.28 | 1.28..1.32 | 1.8% | 3.6% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 1.28 | 1.28..1.32 | 1.8% | 3.6% | 0.2% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.08 | 0.08..0.15 | 42.9% | 85.7% | 2.4% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.02 | 0.02..0.08 | 132.6% | 265.2% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.25 | 0.25..0.26 | 2.0% | 4.0% | 0.4% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.06 | 0.06..0.06 | 0.8% | 1.6% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.24 | 0.24..0.25 | 2.7% | 5.3% | 2.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.06 | 0.06..0.06 | 1.6% | 3.2% | 0.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.47 | 0.46..0.50 | 4.4% | 8.7% | 1.9% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.06 | 0.06..0.06 | 0.8% | 1.6% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.80 | 0.78..0.81 | 1.9% | 3.9% | 1.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.23 | 0.23..0.23 | 0.9% | 1.7% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.06 | 58.9% | 117.9% | 7.1% | moderate |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.01..0.04 | 68.8% | 137.5% | 6.3% | moderate |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.01 | 22.7% | 45.5% | 9.1% | noisy |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.19 | 0.19..0.22 | 8.2% | 16.3% | 1.1% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.15 | 0.15..0.18 | 9.5% | 19.0% | 2.6% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.04 | 5.1% | 10.3% | 2.6% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.81 | 1.76..1.85 | 2.3% | 4.6% | 1.2% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.50 | 1.46..1.53 | 2.2% | 4.4% | 1.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.27 | 0.25..0.28 | 4.7% | 9.3% | 1.9% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 21.30 | 19.86..23.06 | 7.5% | 15.0% | 6.0% | moderate |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 15.61 | 14.62..15.81 | 3.8% | 7.6% | 0.9% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 2.60 | 2.59..2.65 | 1.2% | 2.3% | 0.4% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / Large payload (~650KB) / resqlite selectBytes() | 0.24 | 0.23..0.28 | 9.8% | 19.7% | 3.3% | moderate |
| Select → JSON Bytes / Large payload (~650KB) / resqlite selectBytes... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.09 | 320.8% | 641.7% | 8.3% | noisy |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.04 | 0.04..0.06 | 19.8% | 39.5% | 7.0% | moderate |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 20.0% | 40.0% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.33 | 0.32..0.38 | 10.2% | 20.4% | 3.6% | moderate |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.05 | 0.05..0.06 | 7.7% | 15.4% | 3.8% | moderate |
| Select → Maps / 10000 rows / resqlite select() | 3.91 | 3.86..4.18 | 4.1% | 8.2% | 1.2% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.52 | 0.51..0.55 | 3.4% | 6.9% | 1.9% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.19 | 0.17..0.21 | 9.7% | 19.4% | 5.9% | moderate |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.19 | 0.17..0.21 | 9.7% | 19.4% | 5.9% | moderate |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.51 | 0.48..0.53 | 4.5% | 9.0% | 2.5% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.51 | 0.48..0.53 | 4.5% | 9.0% | 2.5% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03..0.07 | 78.6% | 157.1% | 3.6% | moderate |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03..0.07 | 78.6% | 157.1% | 3.6% | moderate |
| Streaming / Invalidation Latency / resqlite | 0.06 | 0.04..0.07 | 22.7% | 45.5% | 10.9% | noisy |
| Streaming / Invalidation Latency / resqlite [main] | 0.06 | 0.04..0.07 | 22.7% | 45.5% | 10.9% | noisy |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows x 32K... | 2.75 | 2.44..3.00 | 10.2% | 20.5% | 4.1% | moderate |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows x 32K... | 2.75 | 2.44..3.00 | 10.2% | 20.5% | 4.1% | moderate |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged streams, 6... | 2.87 | 2.82..3.29 | 8.0% | 16.1% | 0.9% | stable |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged streams, 6... | 2.87 | 2.82..3.29 | 8.0% | 16.1% | 0.9% | stable |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 1.79 | 1.77..1.82 | 1.3% | 2.6% | 0.7% | stable |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 1.79 | 1.77..1.82 | 1.3% | 2.6% | 0.7% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.51 | 3.31..3.56 | 3.5% | 7.1% | 1.4% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.51 | 3.31..3.56 | 3.5% | 7.1% | 1.4% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.97 | 1.65..2.77 | 28.4% | 56.8% | 11.4% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.97 | 1.65..2.77 | 28.4% | 56.8% | 11.4% | noisy |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.86 | 6.51..7.32 | 5.9% | 11.8% | 4.4% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.86 | 6.51..7.32 | 5.9% | 11.8% | 4.4% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.20 | 0.18..0.23 | 12.8% | 25.6% | 9.0% | noisy |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.20 | 0.18..0.23 | 12.8% | 25.6% | 9.0% | noisy |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.05 | 0.05..0.05 | 1.9% | 3.7% | 0.0% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.05 | 0.05..0.05 | 1.9% | 3.7% | 0.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.41 | 0.40..0.43 | 4.4% | 8.7% | 3.2% | moderate |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.41 | 0.40..0.43 | 4.4% | 8.7% | 3.2% | moderate |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.87 | 3.83..4.08 | 3.3% | 6.6% | 0.5% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.87 | 3.83..4.08 | 3.3% | 6.6% | 0.5% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.52 | 0.42..0.60 | 17.7% | 35.3% | 6.9% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.52 | 0.42..0.60 | 17.7% | 35.3% | 6.9% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.06..0.08 | 9.0% | 17.9% | 3.0% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.06..0.08 | 9.0% | 17.9% | 3.0% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 4.56 | 4.30..5.30 | 10.9% | 21.8% | 0.6% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 4.56 | 4.30..5.30 | 10.9% | 21.8% | 0.6% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.41 | 0.40..0.42 | 3.1% | 6.2% | 1.2% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.41 | 0.40..0.42 | 3.1% | 6.2% | 1.2% | stable |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 0.86 | 0.86..1.02 | 9.3% | 18.7% | 0.5% | stable |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 0.86 | 0.86..1.02 | 9.3% | 18.7% | 0.5% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05..0.05 | 8.0% | 16.0% | 6.0% | moderate |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05..0.05 | 8.0% | 16.0% | 6.0% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.07 | 0.06..0.08 | 16.7% | 33.3% | 14.5% | noisy |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.07 | 0.06..0.08 | 16.7% | 33.3% | 14.5% | noisy |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.77 | 0.73..1.10 | 24.5% | 49.0% | 6.0% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.77 | 0.73..1.10 | 24.5% | 49.0% | 6.0% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.76 | 1.59..1.93 | 9.7% | 19.4% | 3.5% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.76 | 1.59..1.93 | 9.7% | 19.4% | 3.5% | moderate |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.17 | 0.17..0.19 | 7.8% | 15.6% | 4.0% | moderate |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.17 | 0.17..0.19 | 7.8% | 15.6% | 4.0% | moderate |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.10 | 0.10..0.11 | 5.6% | 11.1% | 3.0% | moderate |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.10 | 0.10..0.11 | 5.6% | 11.1% | 3.0% | moderate |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 13.26 | 12.83..14.00 | 4.4% | 8.8% | 3.2% | moderate |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 13.26 | 12.83..14.00 | 4.4% | 8.8% | 3.2% | moderate |


## Comparison

Automatic comparison is disabled. Use `--compare-to=...` for an explicit baseline comparison.

