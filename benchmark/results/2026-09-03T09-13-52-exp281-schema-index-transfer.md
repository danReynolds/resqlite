# resqlite Benchmark Results

Generated: 2026-09-03T09:25:30.550842

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp281-schema-index-transfer`
- Repeats: `5`
- Runtime: `dart-vm / Dart 3.12.2`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `exp-281-schema-index-transfer @ 3447436424b9`
- Comparison baseline: `2026-08-12T07-29-09-exp270-read-result-cache.md`
- Comparison mode: `explicit`
- Comparison baseline compatibility: `compatible`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.013 | 0.029 | 0.001 | 0.002 |
| sqlite3 select() | 0.016 | 0.017 | 0.016 | 0.017 |
| sqlite_async select() | 0.036 | 0.038 | 0.001 | 0.001 |
| drift select() | 0.060 | 0.083 | 0.002 | 0.003 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.043 | 0.045 | 0.005 | 0.006 |
| sqlite3 select() | 0.123 | 0.172 | 0.123 | 0.172 |
| sqlite_async select() | 0.137 | 0.140 | 0.010 | 0.012 |
| drift select() | 0.214 | 0.249 | 0.012 | 0.013 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.310 | 0.417 | 0.054 | 0.071 |
| sqlite3 select() | 1.196 | 1.527 | 1.196 | 1.527 |
| sqlite_async select() | 1.195 | 1.783 | 0.101 | 0.111 |
| drift select() | 1.712 | 2.063 | 0.102 | 0.124 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 3.651 | 13.529 | 0.561 | 1.630 |
| sqlite3 select() | 16.655 | 23.018 | 16.655 | 23.018 |
| sqlite_async select() | 15.462 | 19.243 | 1.012 | 2.562 |
| drift select() | 27.629 | 46.006 | 1.085 | 3.653 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row. The large-payload row isolates resqlite selectBytes because it guards the native bytes transfer policy without multiplying large JSON encoding work across every peer.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.031 | 0.033 | 0.017 | 0.018 |
| sqlite3 + jsonEncode | 0.033 | 0.036 | 0.033 | 0.036 |
| sqlite_async + jsonEncode | 0.053 | 0.061 | 0.018 | 0.018 |
| drift + jsonEncode | 0.079 | 0.099 | 0.019 | 0.025 |
| resqlite selectBytes() | 0.020 | 0.041 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.204 | 0.211 | 0.167 | 0.170 |
| sqlite3 + jsonEncode | 0.283 | 0.374 | 0.283 | 0.374 |
| sqlite_async + jsonEncode | 0.296 | 0.321 | 0.168 | 0.176 |
| drift + jsonEncode | 0.401 | 0.467 | 0.182 | 0.211 |
| resqlite selectBytes() | 0.048 | 0.081 | 0.000 | 0.001 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 2.242 | 2.980 | 1.782 | 2.529 |
| sqlite3 + jsonEncode | 3.217 | 4.419 | 3.217 | 4.419 |
| sqlite_async + jsonEncode | 2.980 | 7.313 | 1.693 | 2.830 |
| drift + jsonEncode | 3.386 | 6.870 | 1.699 | 2.679 |
| resqlite selectBytes() | 0.273 | 0.328 | 0.000 | 0.001 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 22.828 | 29.697 | 16.932 | 20.114 |
| sqlite3 + jsonEncode | 33.553 | 42.307 | 33.553 | 42.307 |
| sqlite_async + jsonEncode | 32.458 | 41.742 | 17.463 | 20.056 |
| drift + jsonEncode | 46.057 | 55.663 | 17.670 | 21.772 |
| resqlite selectBytes() | 2.903 | 3.582 | 0.003 | 0.005 |

### Large payload (~650KB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.252 | 0.462 | 0.000 | 0.003 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.092 | 0.119 | 0.024 | 0.026 |
| sqlite3 | 0.343 | 0.401 | 0.343 | 0.401 |
| sqlite_async | 0.393 | 0.464 | 0.034 | 0.042 |
| drift | 0.696 | 0.995 | 0.040 | 0.057 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.826 | 1.194 | 0.236 | 0.349 |
| sqlite3 | 3.446 | 4.201 | 3.446 | 4.201 |
| sqlite_async | 3.168 | 3.561 | 0.254 | 0.296 |
| drift | 5.033 | 9.408 | 0.271 | 0.304 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.381 | 0.518 | 0.064 | 0.081 |
| sqlite3 | 1.561 | 1.980 | 1.561 | 1.980 |
| sqlite_async | 1.540 | 1.876 | 0.092 | 0.100 |
| drift | 2.171 | 2.653 | 0.094 | 0.116 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.249 | 0.291 | 0.063 | 0.069 |
| sqlite3 | 1.008 | 1.215 | 1.008 | 1.215 |
| sqlite_async | 1.009 | 1.434 | 0.090 | 0.107 |
| drift | 1.584 | 3.086 | 0.092 | 0.153 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.252 | 0.277 | 0.062 | 0.065 |
| sqlite3 | 1.013 | 1.045 | 1.013 | 1.045 |
| sqlite_async | 0.992 | 1.174 | 0.088 | 0.095 |
| drift | 1.560 | 1.960 | 0.092 | 0.099 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.010 | 0.011 | 0.000 | 0.000 |
| sqlite3 | 0.016 | 0.021 | 0.016 | 0.021 |
| sqlite_async | 0.031 | 0.061 | 0.001 | 0.003 |
| drift | 0.046 | 0.104 | 0.001 | 0.002 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.027 | 0.056 | 0.003 | 0.004 |
| sqlite3 | 0.065 | 0.127 | 0.065 | 0.127 |
| sqlite_async | 0.080 | 0.128 | 0.004 | 0.006 |
| drift | 0.135 | 0.312 | 0.005 | 0.017 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.042 | 0.058 | 0.005 | 0.006 |
| sqlite3 | 0.128 | 0.242 | 0.128 | 0.242 |
| sqlite_async | 0.134 | 0.138 | 0.008 | 0.008 |
| drift | 0.212 | 0.269 | 0.008 | 0.011 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.163 | 0.272 | 0.027 | 0.031 |
| sqlite3 | 0.576 | 0.698 | 0.576 | 0.698 |
| sqlite_async | 0.557 | 0.684 | 0.037 | 0.039 |
| drift | 0.852 | 0.977 | 0.039 | 0.044 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.299 | 0.347 | 0.053 | 0.056 |
| sqlite3 | 1.159 | 1.278 | 1.159 | 1.278 |
| sqlite_async | 1.106 | 1.370 | 0.075 | 0.081 |
| drift | 1.746 | 1.972 | 0.081 | 0.094 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.612 | 0.685 | 0.110 | 0.117 |
| sqlite3 | 2.309 | 2.898 | 2.309 | 2.898 |
| sqlite_async | 2.397 | 2.697 | 0.155 | 0.164 |
| drift | 3.362 | 4.029 | 0.156 | 0.160 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.825 | 5.711 | 0.281 | 2.145 |
| sqlite3 | 5.930 | 7.681 | 5.930 | 7.681 |
| sqlite_async | 6.064 | 6.999 | 0.383 | 0.458 |
| drift | 8.560 | 9.271 | 0.379 | 0.399 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.418 | 10.564 | 0.553 | 2.367 |
| sqlite3 | 15.275 | 20.151 | 15.275 | 20.151 |
| sqlite_async | 12.576 | 14.754 | 0.752 | 0.819 |
| drift | 19.443 | 28.524 | 0.796 | 2.428 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 9.424 | 15.303 | 1.121 | 2.155 |
| sqlite3 | 35.070 | 44.925 | 35.070 | 44.925 |
| sqlite_async | 38.292 | 44.567 | 1.517 | 3.505 |
| drift | 56.826 | 67.100 | 1.501 | 3.331 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.031 | 0.045 | 0.031 | 0.045 |
| sqlite3 + jsonEncode | 0.032 | 0.034 | 0.032 | 0.034 |
| sqlite_async + jsonEncode | 0.052 | 0.059 | 0.052 | 0.059 |
| drift + jsonEncode | 0.060 | 0.087 | 0.060 | 0.087 |
| resqlite selectBytes() | 0.012 | 0.013 | 0.012 | 0.013 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.110 | 0.151 | 0.110 | 0.151 |
| sqlite3 + jsonEncode | 0.146 | 0.222 | 0.146 | 0.222 |
| sqlite_async + jsonEncode | 0.159 | 0.167 | 0.159 | 0.167 |
| drift + jsonEncode | 0.195 | 0.242 | 0.195 | 0.242 |
| resqlite selectBytes() | 0.027 | 0.036 | 0.027 | 0.036 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.205 | 0.238 | 0.205 | 0.238 |
| sqlite3 + jsonEncode | 0.284 | 0.324 | 0.284 | 0.324 |
| sqlite_async + jsonEncode | 0.293 | 0.349 | 0.293 | 0.349 |
| drift + jsonEncode | 0.371 | 0.438 | 0.371 | 0.438 |
| resqlite selectBytes() | 0.036 | 0.044 | 0.036 | 0.044 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.963 | 1.079 | 0.963 | 1.079 |
| sqlite3 + jsonEncode | 1.353 | 1.398 | 1.353 | 1.398 |
| sqlite_async + jsonEncode | 1.302 | 1.589 | 1.302 | 1.589 |
| drift + jsonEncode | 1.728 | 2.037 | 1.728 | 2.037 |
| resqlite selectBytes() | 0.140 | 0.183 | 0.140 | 0.183 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.882 | 2.000 | 1.882 | 2.000 |
| sqlite3 + jsonEncode | 2.848 | 5.623 | 2.848 | 5.623 |
| sqlite_async + jsonEncode | 2.773 | 6.338 | 2.773 | 6.338 |
| drift + jsonEncode | 3.253 | 6.622 | 3.253 | 6.622 |
| resqlite selectBytes() | 0.273 | 0.291 | 0.273 | 0.291 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 4.025 | 7.628 | 4.025 | 7.628 |
| sqlite3 + jsonEncode | 5.787 | 11.033 | 5.787 | 11.033 |
| sqlite_async + jsonEncode | 5.864 | 10.747 | 5.864 | 10.747 |
| drift + jsonEncode | 6.739 | 13.414 | 6.739 | 13.414 |
| resqlite selectBytes() | 0.530 | 0.583 | 0.530 | 0.583 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 10.632 | 16.105 | 10.632 | 16.105 |
| sqlite3 + jsonEncode | 15.012 | 18.907 | 15.012 | 18.907 |
| sqlite_async + jsonEncode | 14.427 | 22.794 | 14.427 | 22.794 |
| drift + jsonEncode | 17.108 | 26.251 | 17.108 | 26.251 |
| resqlite selectBytes() | 1.296 | 1.422 | 1.296 | 1.422 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 25.749 | 28.662 | 25.749 | 28.662 |
| sqlite3 + jsonEncode | 31.418 | 38.416 | 31.418 | 38.416 |
| sqlite_async + jsonEncode | 37.519 | 47.738 | 37.519 | 47.738 |
| drift + jsonEncode | 56.059 | 73.314 | 56.059 | 73.314 |
| resqlite selectBytes() | 3.343 | 4.512 | 3.343 | 4.512 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 52.009 | 63.527 | 52.009 | 63.527 |
| sqlite3 + jsonEncode | 77.759 | 95.446 | 77.759 | 95.446 |
| sqlite_async + jsonEncode | 85.226 | 123.839 | 85.226 | 123.839 |
| drift + jsonEncode | 132.241 | 173.744 | 132.241 | 173.744 |
| resqlite selectBytes() | 6.940 | 13.902 | 6.940 | 13.902 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.25 | 0.26 | 0.25 |
| sqlite_async | 1.04 | 1.23 | 1.04 |
| drift | 2.03 | 2.98 | 2.03 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.57 | 0.94 | 0.29 |
| sqlite_async | 2.81 | 4.36 | 1.41 |
| drift | 4.06 | 5.45 | 2.03 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 1.21 | 2.53 | 0.30 |
| sqlite_async | 3.59 | 4.74 | 0.90 |
| drift | 6.83 | 8.63 | 1.71 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 1.28 | 2.00 | 0.16 |
| sqlite_async | 6.08 | 8.96 | 0.76 |
| drift | 12.70 | 14.47 | 1.59 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 113114 |
| resqlite per query | 0.009 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 113114 | 108346..115716 | 3.3 | 9.1 |
| sqlite3 | 183733 | 182497..184355 | 0.5 | 2.0 |
| sqlite_async | 40673 | 40259..41091 | 1.0 | 3.1 |
| drift | 40741 | 40392..41688 | 1.6 | 7.0 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.469 | 14.835 | 14.469 | 14.835 |
| sqlite_async | 38.749 | 39.197 | 38.749 | 39.197 |
| drift | 55.002 | 55.822 | 55.002 | 55.822 |
| sqlite3 (no cache) | 23.646 | 24.128 | 23.646 | 24.128 |
| sqlite3 (cached stmt) | 23.314 | 23.632 | 23.314 | 23.632 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.722 | 3.615 | 1.722 | 3.615 |
| sqlite3 execute() | 1.039 | 1.671 | 1.039 | 1.671 |
| sqlite_async execute() | 3.400 | 5.301 | 3.400 | 5.301 |
| drift execute() | 3.661 | 4.083 | 3.661 | 4.083 |

### Concurrent Single Inserts (100 concurrent)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite concurrent execute() | 0.910 | 1.313 | 0.910 | 1.313 |
| sqlite3 concurrent execute() | 0.945 | 1.779 | 0.945 | 1.779 |
| sqlite_async concurrent execute() | 3.220 | 3.644 | 3.220 | 3.644 |
| drift concurrent execute() | 1.911 | 2.816 | 1.911 | 2.816 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.055 | 0.076 | 0.055 | 0.076 |
| sqlite3 executeBatch() | 0.051 | 0.066 | 0.051 | 0.066 |
| sqlite_async executeBatch() | 0.097 | 0.106 | 0.097 | 0.106 |
| drift executeBatch() | 0.125 | 0.175 | 0.125 | 0.175 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.432 | 0.570 | 0.432 | 0.570 |
| sqlite3 executeBatch() | 0.460 | 0.503 | 0.460 | 0.503 |
| sqlite_async executeBatch() | 0.583 | 0.748 | 0.583 | 0.748 |
| drift executeBatch() | 0.719 | 0.803 | 0.719 | 0.803 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.118 | 7.311 | 4.118 | 7.311 |
| sqlite3 executeBatch() | 4.320 | 4.775 | 4.320 | 4.775 |
| sqlite_async executeBatch() | 5.052 | 6.691 | 5.052 | 6.691 |
| drift executeBatch() | 6.448 | 9.260 | 6.448 | 9.260 |

### Wide Batch Insert (10000 rows x 20 params)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 13.813 | 24.846 | 13.813 | 24.846 |
| sqlite3 executeBatch() | 20.259 | 24.670 | 20.259 | 24.670 |
| sqlite_async executeBatch() | 24.470 | 30.618 | 24.470 | 30.618 |
| drift executeBatch() | 27.238 | 29.857 | 27.238 | 29.857 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.049 | 0.059 | 0.049 | 0.059 |
| sqlite_async writeTransaction() | 0.088 | 0.140 | 0.088 | 0.140 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.078 | 0.113 | 0.078 | 0.113 |
| resqlite tx.execute() loop | 0.667 | 0.811 | 0.667 | 0.811 |
| sqlite_async tx.execute() loop | 1.578 | 1.885 | 1.578 | 1.885 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.453 | 0.523 | 0.453 | 0.523 |
| resqlite tx.execute() loop | 6.830 | 7.655 | 6.830 | 7.655 |
| sqlite_async tx.execute() loop | 13.085 | 14.652 | 13.085 | 14.652 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.099 | 0.108 | 0.099 | 0.108 |
| sqlite_async tx.getAll() | 0.209 | 0.246 | 0.209 | 0.246 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.170 | 0.187 | 0.170 | 0.187 |
| sqlite_async tx.getAll() | 0.369 | 0.410 | 0.369 | 0.410 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 0.881 | 0.970 | 0.881 | 0.970 |
| resqlite nested transaction() depth=5 | 0.088 | 0.122 | 0.088 | 0.122 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.027 | 0.041 | 0.027 | 0.041 |
| sqlite_async watch() | 0.116 | 0.146 | 0.116 | 0.146 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.050 | 0.100 | 0.050 | 0.100 |
| sqlite_async | 0.081 | 0.178 | 0.081 | 0.178 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.200 | 0.287 | 0.200 | 0.287 |
| sqlite_async | 0.530 | 1.110 | 0.530 | 1.110 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.341 | 3.649 | 2.341 | 3.649 |

### Long-Payload Unchanged Fanout (8 streams, 64 rows x 32KB TEXT + 32KB BLOB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.608 | 3.539 | 2.608 | 3.539 |

### Long-Text 32KB Unchanged Fanout (8 unchanged streams, 64 rows x 32KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.876 | 3.669 | 2.876 | 3.669 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.213 | 0.421 | 0.213 | 0.421 |
| sqlite_async | 0.241 | 0.555 | 0.241 | 0.555 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.166 | 2.166 | 2.166 | 2.166 |
| sqlite_async | 8.132 | 8.132 | 8.132 | 8.132 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.448 | 5.173 | 3.448 | 5.173 |
| sqlite_async | 6.212 | 11.707 | 6.212 | 11.707 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.541 | 3.838 | 0.541 | 3.838 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 7.379 | 8.486 | 7.379 | 8.486 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. For resqlite, this emission metric can reflect writer-side column-level invalidation, experiment 075's native result-hash short-circuit, or both. Use A11c (Many-Streams Writer Throughput) when the question is specifically writer-side dispatch elision.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 67.9 | 0.000 |
| sqlite_async | 4093 | 1207.4 | 1.068 |
| drift | 5000 | 1101.7 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 72.8 | 0.000 |
| sqlite_async | 3832 | 1140.1 | 1.068 |
| drift | 5000 | 1059.8 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 215.12 | 220.46 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 428.66 | 432.20 | 0.00 | 0.00 | 1123 | 3 |
| drift stream() | 544.76 | 552.20 | 0.02 | 0.02 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.023 | 0.034 | 0.000 | 0.000 |
| sqlite3 | 0.020 | 0.028 | 0.020 | 0.028 |
| sqlite_async | 0.042 | 0.058 | 0.000 | 0.000 |
| drift | 0.039 | 0.049 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.017 | 0.024 | 0.000 | 0.000 |
| sqlite3 | 0.013 | 0.017 | 0.013 | 0.017 |
| sqlite_async | 0.035 | 0.043 | 0.000 | 0.000 |
| drift | 0.032 | 0.039 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.021 | 0.032 | 0.000 | 0.000 |
| sqlite3 | 0.032 | 0.035 | 0.032 | 0.035 |
| sqlite_async | 0.060 | 0.071 | 0.000 | 0.000 |
| drift | 0.054 | 0.059 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.008 | 0.016 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.025 | 0.029 | 0.000 | 0.000 |
| drift | 0.021 | 0.025 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.040 | 0.044 | 0.001 | 0.001 |
| sqlite3 | 0.068 | 0.069 | 0.068 | 0.069 |
| sqlite_async | 0.082 | 0.094 | 0.001 | 0.001 |
| drift | 0.093 | 0.101 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 107.746 | 108.196 | 0.000 | 0.000 | 0 |
| sqlite_async | 213.696 | 221.131 | 0.000 | 0.000 | 37 |
| drift | 218.850 | 220.954 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 437.23 | 437.23 | 0.00 | 0.00 | 14.06 | 423.17 | 2 |
| sqlite_async | 489.58 | 489.58 | 0.00 | 0.00 | 22.11 | 467.47 | 1189 |
| drift | 1816.89 | 1816.89 | 0.11 | 0.11 | 12.57 | 1804.47 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 0.05 | 13.16 | 0.00..6.03 | ±3.02 |
| sqlite3 select() | 1.31 | 9.38 | 0.44..6.77 | ±3.16 |
| sqlite_async select() | 1.00 | 4.36 | 0.92..1.00 | ±0.04 |
| drift select() | 11.58 | 73.77 | 0.00..39.94 | ±19.97 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 20.08 | 0.00..12.05 | ±6.02 |
| resqlite + jsonEncode | 1.06 | 13.70 | 0.00..3.13 | ±1.56 |
| sqlite3 + jsonEncode | 0.02 | 55.81 | 0.00..9.77 | ±4.88 |
| sqlite_async + jsonEncode | 0.00 | 22.50 | 0.00..7.38 | ±3.69 |
| drift + jsonEncode | 0.00 | 40.88 | 0.00..23.05 | ±11.52 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 2.02 | 34.91 | 0.00..12.02 | ±6.01 |
| sqlite3 executeBatch() | 0.00 | 2.25 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 0.16 | 0.00..0.00 | ±0.00 |
| drift batch() | 0.56 | 4.50 | 0.03..3.02 | ±1.49 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.08 | 0.13 | 0.00..0.11 | ±0.05 |
| sqlite_async watch() | 0.00 | 1.67 | 0.00..0.02 | ±0.01 |

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
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.02 | 0.02..0.02 | 5.0% | 10.0% | 5.0% | moderate |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 6.3% | 12.5% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02..0.02 | 4.8% | 9.5% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.02 | 0.01..0.02 | 6.3% | 12.5% | 6.3% | moderate |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.25 | 0.24..0.26 | 4.0% | 8.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.25 | 0.24..0.26 | 4.0% | 8.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.27 | 0.26..0.57 | 57.4% | 114.8% | 3.7% | moderate |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.13 | 0.13..0.29 | 61.5% | 123.1% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.36 | 0.32..1.21 | 123.6% | 247.2% | 11.1% | noisy |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.09 | 0.08..0.30 | 122.2% | 244.4% | 11.1% | noisy |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.65 | 0.58..1.28 | 53.8% | 107.7% | 9.2% | noisy |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.08 | 0.07..0.16 | 56.3% | 112.5% | 12.5% | noisy |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.04 | 10.0% | 20.0% | 5.0% | moderate |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 150.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 107.04 | 104.58..107.78 | 1.5% | 3.0% | 0.7% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 242.07 | 232.20..437.23 | 42.3% | 84.7% | 4.1% | moderate |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 215.51 | 213.75..225.62 | 2.8% | 5.5% | 0.8% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 13.48 | 13.41..14.47 | 3.9% | 7.9% | 0.5% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 13.48 | 13.41..14.47 | 3.9% | 7.9% | 0.5% | stable |
| Point Query Throughput / resqlite qps | 162635.00 | 113114.00..173577.00 | 18.6% | 37.2% | 6.7% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.01 | 20.0% | 40.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.04 | 14.5% | 29.0% | 12.9% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.04 | 14.5% | 29.0% | 12.9% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.01 | 9.1% | 18.2% | 9.1% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.01 | 9.1% | 18.2% | 9.1% | noisy |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.04..0.04 | 6.6% | 13.2% | 2.6% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.20 | 0.19..0.20 | 3.3% | 6.6% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.20 | 0.19..0.20 | 3.3% | 6.6% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.04 | 5.7% | 11.4% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.04 | 0.04..0.04 | 5.7% | 11.4% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.30 | 0.29..0.31 | 2.0% | 4.1% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.82 | 1.79..1.88 | 2.5% | 4.9% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.82 | 1.79..1.88 | 2.5% | 4.9% | 1.7% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.05 | 0.05..0.06 | 2.8% | 5.7% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.26 | 0.26..0.27 | 3.3% | 6.6% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.26 | 0.26..0.27 | 3.3% | 6.6% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 3.27 | 3.27..3.42 | 2.3% | 4.7% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 23.53 | 20.76..25.75 | 10.6% | 21.2% | 9.4% | noisy |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 23.53 | 20.76..25.75 | 10.6% | 21.2% | 9.4% | noisy |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.53 | 0.53..0.55 | 2.4% | 4.9% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 2.67 | 2.54..3.34 | 15.1% | 30.2% | 4.9% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 2.67 | 2.54..3.34 | 15.1% | 30.2% | 4.9% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.58 | 0.57..0.61 | 3.9% | 7.8% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.81 | 3.73..4.03 | 3.8% | 7.7% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.81 | 3.73..4.03 | 3.8% | 7.7% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.10 | 0.10..0.11 | 2.9% | 5.8% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.52 | 0.50..0.53 | 3.2% | 6.4% | 2.9% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.52 | 0.50..0.53 | 3.2% | 6.4% | 2.9% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 8.51 | 8.30..9.42 | 6.6% | 13.2% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 45.01 | 44.56..52.01 | 8.3% | 16.6% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 45.01 | 44.56..52.01 | 8.3% | 16.6% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.07 | 1.05..1.12 | 3.4% | 6.8% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 5.61 | 5.55..6.94 | 12.4% | 24.8% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 5.61 | 5.55..6.94 | 12.4% | 24.8% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.02 | 0.02..0.03 | 15.9% | 31.8% | 4.5% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.10..0.11 | 4.2% | 8.4% | 2.8% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.11 | 0.10..0.11 | 4.2% | 8.4% | 2.8% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.02 | 0.02..0.03 | 13.0% | 26.1% | 8.7% | noisy |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.02 | 0.02..0.03 | 13.0% | 26.1% | 8.7% | noisy |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.16 | 0.15..0.16 | 2.9% | 5.8% | 1.3% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.93 | 0.91..0.96 | 2.9% | 5.8% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.93 | 0.91..0.96 | 2.9% | 5.8% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.03 | 0.03..0.03 | 1.9% | 3.8% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.14 | 0.13..0.14 | 3.3% | 6.6% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.14 | 0.13..0.14 | 3.3% | 6.6% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 1.73 | 1.69..1.82 | 3.9% | 7.7% | 2.0% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 10.33 | 9.23..11.01 | 8.6% | 17.2% | 6.0% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 10.33 | 9.23..11.01 | 8.6% | 17.2% | 6.0% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.27 | 0.26..0.28 | 3.9% | 7.7% | 3.3% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 1.30 | 1.29..1.30 | 0.5% | 1.1% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 1.30 | 1.29..1.30 | 0.5% | 1.1% | 0.3% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.09 | 0.09..0.16 | 41.3% | 82.6% | 1.2% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.02 | 0.02..0.08 | 127.1% | 254.2% | 4.2% | moderate |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.25 | 0.24..0.25 | 2.2% | 4.5% | 0.8% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.06 | 0.06..0.06 | 1.6% | 3.3% | 1.6% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.24 | 0.23..0.25 | 3.4% | 6.8% | 0.8% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.06 | 0.06..0.06 | 2.5% | 4.9% | 1.6% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.36 | 0.36..0.38 | 3.2% | 6.3% | 1.1% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.06 | 0.06..0.06 | 2.5% | 4.9% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.77 | 0.77..0.83 | 3.7% | 7.4% | 0.3% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.23 | 0.22..0.24 | 2.7% | 5.3% | 0.4% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.06 | 58.3% | 116.7% | 3.3% | moderate |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02..0.04 | 61.8% | 123.5% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 37.5% | 75.0% | 8.3% | noisy |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.19..0.23 | 8.2% | 16.4% | 1.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.16 | 0.16..0.18 | 7.1% | 14.3% | 2.5% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.03..0.05 | 17.9% | 35.9% | 7.7% | moderate |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.89 | 1.80..2.24 | 11.6% | 23.1% | 4.4% | moderate |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.61 | 1.54..1.78 | 7.4% | 14.9% | 3.6% | moderate |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.26 | 0.25..0.27 | 3.7% | 7.4% | 1.2% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.18 | 19.52..24.72 | 12.9% | 25.7% | 3.2% | moderate |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 15.83 | 15.67..16.93 | 4.0% | 8.0% | 1.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 2.64 | 2.60..2.90 | 5.7% | 11.4% | 1.3% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 150.0% | 300.0% | 100.0% | noisy |
| Select → JSON Bytes / Large payload (~650KB) / resqlite selectBytes() | 0.25 | 0.24..0.27 | 6.7% | 13.5% | 4.8% | moderate |
| Select → JSON Bytes / Large payload (~650KB) / resqlite selectBytes... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.06 | 209.1% | 418.2% | 9.1% | noisy |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 850.0% | 1700.0% | 100.0% | noisy |
| Select → Maps / 100 rows / resqlite select() | 0.04 | 0.04..0.15 | 136.2% | 272.5% | 5.0% | moderate |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 30.0% | 60.0% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.31 | 0.30..0.36 | 9.7% | 19.4% | 2.6% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.05 | 0.05..0.06 | 4.6% | 9.3% | 3.7% | moderate |
| Select → Maps / 10000 rows / resqlite select() | 3.31 | 3.27..3.65 | 5.8% | 11.5% | 1.1% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.53 | 0.52..0.56 | 4.2% | 8.3% | 0.6% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.20 | 0.17..0.23 | 15.3% | 30.7% | 5.4% | moderate |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.20 | 0.17..0.23 | 15.3% | 30.7% | 5.4% | moderate |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.51 | 0.46..0.54 | 7.6% | 15.2% | 6.7% | moderate |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.51 | 0.46..0.54 | 7.6% | 15.2% | 6.7% | moderate |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03..0.07 | 75.9% | 151.9% | 3.7% | moderate |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03..0.07 | 75.9% | 151.9% | 3.7% | moderate |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.04..0.06 | 15.3% | 30.6% | 10.2% | noisy |
| Streaming / Invalidation Latency / resqlite [main] | 0.05 | 0.04..0.06 | 15.3% | 30.6% | 10.2% | noisy |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows x 32K... | 2.61 | 2.31..2.77 | 9.0% | 17.9% | 5.3% | moderate |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows x 32K... | 2.61 | 2.31..2.77 | 9.0% | 17.9% | 5.3% | moderate |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged streams, 6... | 2.69 | 2.44..3.20 | 14.0% | 28.1% | 7.5% | moderate |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged streams, 6... | 2.69 | 2.44..3.20 | 14.0% | 28.1% | 7.5% | moderate |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 2.25 | 1.49..2.34 | 18.9% | 37.7% | 4.0% | moderate |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 2.25 | 1.49..2.34 | 18.9% | 37.7% | 4.0% | moderate |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.45 | 3.10..3.58 | 7.1% | 14.1% | 4.0% | moderate |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.45 | 3.10..3.58 | 7.1% | 14.1% | 4.0% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.85 | 1.39..3.25 | 50.0% | 100.1% | 16.8% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.85 | 1.39..3.25 | 50.0% | 100.1% | 16.8% | noisy |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.67 | 6.13..7.38 | 9.3% | 18.7% | 8.0% | noisy |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.67 | 6.13..7.38 | 9.3% | 18.7% | 8.0% | noisy |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.20 | 0.18..0.22 | 10.8% | 21.5% | 4.5% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.20 | 0.18..0.22 | 10.8% | 21.5% | 4.5% | moderate |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.05..0.06 | 10.9% | 21.8% | 1.8% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.06 | 0.05..0.06 | 10.9% | 21.8% | 1.8% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.42 | 0.39..0.48 | 10.1% | 20.3% | 3.8% | moderate |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.42 | 0.39..0.48 | 10.1% | 20.3% | 3.8% | moderate |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.90 | 3.84..4.12 | 3.5% | 7.0% | 1.5% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.90 | 3.84..4.12 | 3.5% | 7.0% | 1.5% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.56 | 0.38..0.67 | 26.1% | 52.1% | 19.1% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.56 | 0.38..0.67 | 26.1% | 52.1% | 19.1% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.06..0.08 | 13.4% | 26.9% | 9.0% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.06..0.08 | 13.4% | 26.9% | 9.0% | noisy |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 4.93 | 4.67..6.83 | 21.9% | 43.8% | 3.7% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 4.93 | 4.67..6.83 | 21.9% | 43.8% | 3.7% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.42 | 0.40..0.49 | 11.0% | 22.0% | 3.6% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.42 | 0.40..0.49 | 11.0% | 22.0% | 3.6% | moderate |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 0.89 | 0.86..0.95 | 5.5% | 10.9% | 2.6% | stable |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 0.89 | 0.86..0.95 | 5.5% | 10.9% | 2.6% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.04..0.06 | 10.2% | 20.4% | 6.1% | moderate |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.04..0.06 | 10.2% | 20.4% | 6.1% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.07 | 0.06..0.09 | 17.1% | 34.3% | 8.6% | noisy |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.07 | 0.06..0.09 | 17.1% | 34.3% | 8.6% | noisy |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.82 | 0.65..0.89 | 14.7% | 29.4% | 7.4% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.82 | 0.65..0.89 | 14.7% | 29.4% | 7.4% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.58 | 1.52..3.10 | 50.0% | 100.1% | 3.8% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.58 | 1.52..3.10 | 50.0% | 100.1% | 3.8% | moderate |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.17 | 0.16..0.17 | 3.0% | 5.9% | 1.2% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.17 | 0.16..0.17 | 3.0% | 5.9% | 1.2% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.10 | 0.09..0.10 | 3.1% | 6.3% | 3.1% | moderate |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.10 | 0.09..0.10 | 3.1% | 6.3% | 3.1% | moderate |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 13.15 | 12.99..13.81 | 3.1% | 6.3% | 1.2% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 13.15 | 12.99..13.81 | 3.1% | 6.3% | 1.2% | stable |


## Comparison vs Previous Run

Previous: `2026-08-12T07-29-09-exp270-read-result-cache.md` (cross-repeat aggregate medians)

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.02 | 0.02 | +0.00 | ±15% / ±0.02 ms | 5.0% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 6.3% | stable | ⚪ Within noise |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 4.8% | stable | ⚪ Within noise |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.02 | +0.00 | ±19% / ±0.02 ms | 6.3% | moderate | ⚪ Within noise |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.26 | 0.25 | -0.01 | ±10% / ±0.03 ms | 4.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.26 | 0.25 | -0.01 | ±10% / ±0.03 ms | 4.0% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.27 | 0.27 | +0.00 | ±57% / ±0.15 ms | 57.4% | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.14 | 0.13 | -0.01 | ±62% / ±0.09 ms | 61.5% | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.33 | 0.36 | +0.03 | ±124% / ±0.44 ms | 123.6% | noisy | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.08 | 0.09 | +0.01 | ±122% / ±0.11 ms | 122.2% | noisy | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.64 | 0.65 | +0.01 | ±54% / ±0.35 ms | 53.8% | noisy | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.08 | 0.08 | +0.00 | ±56% / ±0.04 ms | 56.3% | noisy | ⚪ Within noise |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.04 | +0.04 | ±15% / ±0.02 ms | 10.0% | moderate | 🔴 Regression (0%) |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±150% / ±0.02 ms | 150.0% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 110.23 | 107.04 | -3.18 | ±10% / ±11.02 ms | 1.5% | stable | ⚪ Within noise |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 238.90 | 242.07 | +3.17 | ±42% / ±102.52 ms | 42.3% | moderate | ⚪ Within noise |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 222.68 | 215.51 | -7.17 | ±10% / ±22.27 ms | 2.8% | stable | ⚪ Within noise |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 13.64 | 13.48 | -0.17 | ±10% / ±1.36 ms | 3.9% | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 13.64 | 13.48 | -0.17 | ±10% / ±1.36 ms | 3.9% | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 151537.00 | 162635.00 | +11098.00 | ±20% / ±32826.00 ms | 18.6% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.00 | 0.01 | +0.01 | ±20% / ±0.02 ms | 20.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.02 | 0.03 | +0.01 | ±39% / ±0.02 ms | 14.5% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.02 | 0.03 | +0.01 | ±39% / ±0.02 ms | 14.5% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±27% / ±0.02 ms | 9.1% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±27% / ±0.02 ms | 9.1% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.01 | 0.04 | +0.03 | ±10% / ±0.02 ms | 6.6% | stable | 🔴 Regression (+660%) |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.16 | 0.20 | +0.04 | ±10% / ±0.02 ms | 3.3% | stable | 🔴 Regression (+25%) |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.16 | 0.20 | +0.04 | ±10% / ±0.02 ms | 3.3% | stable | 🔴 Regression (+25%) |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 5.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 5.7% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.31 | 0.30 | -0.01 | ±10% / ±0.03 ms | 2.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.79 | 1.82 | +0.04 | ±10% / ±0.18 ms | 2.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.79 | 1.82 | +0.04 | ±10% / ±0.18 ms | 2.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 2.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.26 | 0.26 | -0.01 | ±10% / ±0.03 ms | 3.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.26 | 0.26 | -0.01 | ±10% / ±0.03 ms | 3.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 3.37 | 3.27 | -0.10 | ±10% / ±0.34 ms | 2.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 23.61 | 23.53 | -0.09 | ±28% / ±6.69 ms | 10.6% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 23.61 | 23.53 | -0.09 | ±28% / ±6.69 ms | 10.6% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.52 | 0.53 | +0.02 | ±10% / ±0.05 ms | 2.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 2.59 | 2.67 | +0.08 | ±15% / ±0.40 ms | 15.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 2.59 | 2.67 | +0.08 | ±15% / ±0.40 ms | 15.1% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.60 | 0.58 | -0.02 | ±10% / ±0.06 ms | 3.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.80 | 3.81 | +0.01 | ±10% / ±0.38 ms | 3.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.80 | 3.81 | +0.01 | ±10% / ±0.38 ms | 3.8% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 2.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.53 | 0.52 | -0.01 | ±10% / ±0.05 ms | 3.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.53 | 0.52 | -0.01 | ±10% / ±0.05 ms | 3.2% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 8.38 | 8.51 | +0.13 | ±10% / ±0.85 ms | 6.6% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 43.95 | 45.01 | +1.06 | ±10% / ±4.50 ms | 8.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 43.95 | 45.01 | +1.06 | ±10% / ±4.50 ms | 8.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.05 | 1.07 | +0.02 | ±10% / ±0.11 ms | 3.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 5.34 | 5.61 | +0.27 | ±12% / ±0.70 ms | 12.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 5.34 | 5.61 | +0.27 | ±12% / ±0.70 ms | 12.4% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.00 | 0.02 | +0.02 | ±16% / ±0.02 ms | 15.9% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.08 | 0.11 | +0.03 | ±10% / ±0.02 ms | 4.2% | stable | 🔴 Regression (+35%) |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.08 | 0.11 | +0.03 | ±10% / ±0.02 ms | 4.2% | stable | 🔴 Regression (+35%) |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.02 | -0.00 | ±26% / ±0.02 ms | 13.0% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.02 | -0.00 | ±26% / ±0.02 ms | 13.0% | noisy | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.16 | 0.16 | -0.01 | ±10% / ±0.02 ms | 2.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.92 | 0.93 | +0.01 | ±10% / ±0.09 ms | 2.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.92 | 0.93 | +0.01 | ±10% / ±0.09 ms | 2.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 1.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.14 | 0.14 | +0.00 | ±10% / ±0.02 ms | 3.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.14 | 0.14 | +0.00 | ±10% / ±0.02 ms | 3.3% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 1.77 | 1.73 | -0.04 | ±10% / ±0.18 ms | 3.9% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.06 | 10.33 | +0.27 | ±18% / ±1.85 ms | 8.6% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.06 | 10.33 | +0.27 | ±18% / ±1.85 ms | 8.6% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.27 | 0.27 | +0.01 | ±10% / ±0.03 ms | 3.9% | moderate | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.31 | 1.30 | -0.02 | ±10% / ±0.13 ms | 0.5% | stable | ⚪ Within noise |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.31 | 1.30 | -0.02 | ±10% / ±0.13 ms | 0.5% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.08 | 0.09 | +0.00 | ±41% / ±0.04 ms | 41.3% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.02 | 0.02 | +0.00 | ±127% / ±0.03 ms | 127.1% | moderate | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.25 | 0.25 | -0.00 | ±10% / ±0.02 ms | 2.2% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 1.6% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.24 | 0.24 | -0.00 | ±10% / ±0.02 ms | 3.4% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 2.5% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.37 | 0.36 | -0.01 | ±10% / ±0.04 ms | 3.2% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 2.5% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.78 | 0.77 | -0.01 | ±10% / ±0.08 ms | 3.7% | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.22 | 0.23 | +0.01 | ±10% / ±0.02 ms | 2.7% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.02 | 0.03 | +0.01 | ±58% / ±0.02 ms | 58.3% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02 | +0.00 | ±62% / ±0.02 ms | 61.8% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | +0.00 | ±38% / ±0.02 ms | 37.5% | noisy | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.16 | 0.20 | +0.04 | ±10% / ±0.02 ms | 8.2% | stable | 🔴 Regression (+23%) |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.16 | 0.16 | +0.00 | ±10% / ±0.02 ms | 7.1% | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04 | +0.00 | ±23% / ±0.02 ms | 17.9% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.79 | 1.89 | +0.10 | ±13% / ±0.25 ms | 11.6% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.53 | 1.61 | +0.07 | ±11% / ±0.17 ms | 7.4% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.27 | 0.26 | -0.01 | ±10% / ±0.03 ms | 3.7% | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.29 | 20.18 | -0.12 | ±13% / ±2.61 ms | 12.9% | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 16.04 | 15.83 | -0.21 | ±10% / ±1.60 ms | 4.0% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 2.63 | 2.64 | +0.01 | ±10% / ±0.26 ms | 5.7% | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±300% / ±0.02 ms | 150.0% | noisy | ⚪ Within noise |
| Select → JSON Bytes / Large payload (~650KB) / resqlite s... | 0.24 | 0.25 | +0.02 | ±14% / ±0.04 ms | 6.7% | moderate | ⚪ Within noise |
| Select → JSON Bytes / Large payload (~650KB) / resqlite s... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.00 | 0.01 | +0.01 | ±209% / ±0.02 ms | 209.1% | noisy | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±850% / ±0.02 ms | 850.0% | noisy | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.01 | 0.04 | +0.04 | ±136% / ±0.05 ms | 136.2% | moderate | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±30% / ±0.02 ms | 30.0% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.31 | 0.31 | -0.00 | ±10% / ±0.03 ms | 9.7% | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.05 | 0.05 | +0.00 | ±11% / ±0.02 ms | 4.6% | moderate | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 3.32 | 3.31 | -0.01 | ±10% / ±0.33 ms | 5.8% | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.51 | 0.53 | +0.02 | ±10% / ±0.05 ms | 4.2% | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.18 | 0.20 | +0.02 | ±16% / ±0.03 ms | 15.3% | moderate | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.18 | 0.20 | +0.02 | ±16% / ±0.03 ms | 15.3% | moderate | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.48 | 0.51 | +0.03 | ±20% / ±0.10 ms | 7.6% | moderate | ⚪ Within noise |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.48 | 0.51 | +0.03 | ±20% / ±0.10 ms | 7.6% | moderate | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | +0.00 | ±76% / ±0.02 ms | 75.9% | moderate | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03 | +0.00 | ±76% / ±0.02 ms | 75.9% | moderate | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.05 | +0.01 | ±31% / ±0.02 ms | 15.3% | noisy | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.05 | +0.01 | ±31% / ±0.02 ms | 15.3% | noisy | ⚪ Within noise |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 ... | 2.64 | 2.61 | -0.03 | ±16% / ±0.42 ms | 9.0% | moderate | ⚪ Within noise |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 ... | 2.64 | 2.61 | -0.03 | ±16% / ±0.42 ms | 9.0% | moderate | ⚪ Within noise |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged ... | 2.50 | 2.69 | +0.19 | ±23% / ±0.61 ms | 14.0% | moderate | ⚪ Within noise |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged ... | 2.50 | 2.69 | +0.19 | ±23% / ±0.61 ms | 14.0% | moderate | ⚪ Within noise |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 1.49 | 2.25 | +0.76 | ±19% / ±0.42 ms | 18.9% | moderate | 🔴 Regression (+51%) |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 1.49 | 2.25 | +0.76 | ±19% / ±0.42 ms | 18.9% | moderate | 🔴 Regression (+51%) |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.22 | 3.45 | +0.23 | ±12% / ±0.41 ms | 7.1% | moderate | ⚪ Within noise |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.22 | 3.45 | +0.23 | ±12% / ±0.41 ms | 7.1% | moderate | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.65 | 1.85 | +0.21 | ±50% / ±0.94 ms | 50.0% | noisy | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.65 | 1.85 | +0.21 | ±50% / ±0.94 ms | 50.0% | noisy | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.03 | 6.67 | +0.64 | ±24% / ±1.61 ms | 9.3% | noisy | ⚪ Within noise |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.03 | 6.67 | +0.64 | ±24% / ±1.61 ms | 9.3% | noisy | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.18 | 0.20 | +0.02 | ±14% / ±0.03 ms | 10.8% | moderate | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.18 | 0.20 | +0.02 | ±14% / ±0.03 ms | 10.8% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.06 | +0.00 | ±11% / ±0.02 ms | 10.9% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.06 | +0.00 | ±11% / ±0.02 ms | 10.9% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.40 | 0.42 | +0.02 | ±11% / ±0.05 ms | 10.1% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.40 | 0.42 | +0.02 | ±11% / ±0.05 ms | 10.1% | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.70 | 3.90 | +0.20 | ±10% / ±0.39 ms | 3.5% | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.70 | 3.90 | +0.20 | ±10% / ±0.39 ms | 3.5% | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.48 | 0.56 | +0.08 | ±57% / ±0.32 ms | 26.1% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.48 | 0.56 | +0.08 | ±57% / ±0.32 ms | 26.1% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.06 | 0.07 | +0.00 | ±27% / ±0.02 ms | 13.4% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.06 | 0.07 | +0.00 | ±27% / ±0.02 ms | 13.4% | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 4.83 | 4.93 | +0.10 | ±22% / ±1.08 ms | 21.9% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 4.83 | 4.93 | +0.10 | ±22% / ±1.08 ms | 21.9% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.41 | 0.42 | +0.01 | ±11% / ±0.05 ms | 11.0% | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.41 | 0.42 | +0.01 | ±11% / ±0.05 ms | 11.0% | moderate | ⚪ Within noise |
| Write Performance / Concurrent Single Inserts (100 concur... | 0.82 | 0.89 | +0.07 | ±10% / ±0.09 ms | 5.5% | stable | ⚪ Within noise |
| Write Performance / Concurrent Single Inserts (100 concur... | 0.82 | 0.89 | +0.07 | ±10% / ±0.09 ms | 5.5% | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.05 | +0.00 | ±18% / ±0.02 ms | 10.2% | moderate | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.05 | +0.00 | ±18% / ±0.02 ms | 10.2% | moderate | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.07 | 0.07 | +0.00 | ±26% / ±0.02 ms | 17.1% | noisy | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.07 | 0.07 | +0.00 | ±26% / ±0.02 ms | 17.1% | noisy | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.77 | 0.82 | +0.05 | ±22% / ±0.18 ms | 14.7% | moderate | ⚪ Within noise |
| Write Performance / Nested Transactions (savepoints) / re... | 0.77 | 0.82 | +0.05 | ±22% / ±0.18 ms | 14.7% | moderate | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.47 | 1.58 | +0.11 | ±50% / ±0.79 ms | 50.0% | moderate | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.47 | 1.58 | +0.11 | ±50% / ±0.79 ms | 50.0% | moderate | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.17 | 0.17 | -0.00 | ±10% / ±0.02 ms | 3.0% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.17 | 0.17 | -0.00 | ±10% / ±0.02 ms | 3.0% | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | -0.01 | ±10% / ±0.02 ms | 3.1% | moderate | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | -0.01 | ±10% / ±0.02 ms | 3.1% | moderate | ⚪ Within noise |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 12.85 | 13.15 | +0.30 | ±10% / ±1.31 ms | 3.1% | stable | ⚪ Within noise |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 12.85 | 13.15 | +0.30 | ±10% / ±1.31 ms | 3.1% | stable | ⚪ Within noise |

**Summary:** 0 wins, 9 regressions, 160 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.50 | 0.56 | +0.06 MB | ±1.49 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 7.06 | 2.02 | -5.04 MB | ±6.01 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 0.00 | 0.00 | +0.00 MB | ±11.52 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 3.09 | 1.06 | -2.03 MB | ±1.56 MB | 🟢 Win (-2.03 MB) |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 0.00 | +0.00 MB | ±6.02 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 0.00 | 0.02 | +0.02 MB | ±4.88 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±3.69 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 8.88 | 11.58 | +2.70 MB | ±19.97 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / resqlite select() | 0.00 | 0.05 | +0.05 MB | ±3.02 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite3 select() | 2.64 | 1.31 | -1.33 MB | ±3.16 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 1.00 | 1.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.06 | 0.08 | +0.02 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 1 wins, 0 regressions, 14 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 4568 | 4093 | -475 | ±100 | 🟢 Fewer re-emits (-475) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 3857 | 3832 | -25 | ±100 | ⚪ Within noise |

**Granularity summary:** 1 fewer-re-emit, 0 more-re-emit, 5 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


