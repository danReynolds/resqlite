# resqlite Benchmark Results

Generated: 2026-06-24T07:30:24.040569

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp198-direct-buf-int-json`
- Repeats: `1`
- Runtime: `dart-vm / Dart 3.11.5`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `exp-198-soa-result-frame @ 0f17307138cd (dirty)`
- Comparison baseline: `2026-06-24T07-27-32-baseline-for-exp198.md`
- Comparison mode: `explicit`
- Comparison baseline compatibility: `compatible`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.085 | 0.142 | 0.019 | 0.029 |
| sqlite3 select() | 0.131 | 0.306 | 0.131 | 0.306 |
| sqlite_async select() | 0.174 | 0.290 | 0.019 | 0.023 |
| drift select() | 0.135 | 0.216 | 0.007 | 0.012 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.067 | 0.107 | 0.008 | 0.009 |
| sqlite3 select() | 0.233 | 0.301 | 0.233 | 0.301 |
| sqlite_async select() | 0.247 | 0.338 | 0.013 | 0.017 |
| drift select() | 0.300 | 0.414 | 0.011 | 0.015 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.384 | 0.427 | 0.055 | 0.058 |
| sqlite3 select() | 1.143 | 1.406 | 1.143 | 1.406 |
| sqlite_async select() | 1.112 | 1.233 | 0.075 | 0.085 |
| drift select() | 1.580 | 1.660 | 0.072 | 0.077 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.021 | 7.981 | 0.508 | 0.596 |
| sqlite3 select() | 13.460 | 16.615 | 13.460 | 16.615 |
| sqlite_async select() | 12.235 | 15.956 | 0.719 | 1.229 |
| drift select() | 19.856 | 25.805 | 0.719 | 0.822 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row. The large-payload row isolates resqlite selectBytes because it guards the native bytes transfer policy without multiplying large JSON encoding work across every peer.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.091 | 0.188 | 0.072 | 0.084 |
| sqlite3 + jsonEncode | 0.048 | 0.070 | 0.048 | 0.070 |
| sqlite_async + jsonEncode | 0.104 | 0.127 | 0.027 | 0.031 |
| drift + jsonEncode | 0.092 | 0.101 | 0.026 | 0.027 |
| resqlite selectBytes() | 0.019 | 0.026 | 0.000 | 0.001 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.215 | 0.247 | 0.168 | 0.200 |
| sqlite3 + jsonEncode | 0.267 | 0.285 | 0.267 | 0.285 |
| sqlite_async + jsonEncode | 0.324 | 0.386 | 0.165 | 0.206 |
| drift + jsonEncode | 0.339 | 0.345 | 0.152 | 0.155 |
| resqlite selectBytes() | 0.044 | 0.046 | 0.000 | 0.001 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.732 | 2.710 | 1.436 | 1.673 |
| sqlite3 + jsonEncode | 2.749 | 6.482 | 2.749 | 6.482 |
| sqlite_async + jsonEncode | 2.914 | 4.718 | 1.602 | 2.616 |
| drift + jsonEncode | 3.056 | 3.721 | 1.491 | 1.676 |
| resqlite selectBytes() | 0.287 | 0.301 | 0.000 | 0.000 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.484 | 22.685 | 14.978 | 17.806 |
| sqlite3 + jsonEncode | 28.778 | 32.573 | 28.778 | 32.573 |
| sqlite_async + jsonEncode | 30.253 | 32.117 | 14.883 | 16.590 |
| drift + jsonEncode | 39.356 | 44.292 | 15.604 | 20.333 |
| resqlite selectBytes() | 2.744 | 2.774 | 0.000 | 0.000 |

### Large payload (~650KB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.281 | 0.296 | 0.000 | 0.000 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.131 | 0.370 | 0.035 | 0.206 |
| sqlite3 | 0.336 | 0.526 | 0.336 | 0.526 |
| sqlite_async | 0.392 | 0.422 | 0.034 | 0.041 |
| drift | 0.579 | 0.904 | 0.033 | 0.039 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.852 | 0.867 | 0.217 | 0.222 |
| sqlite3 | 3.221 | 3.543 | 3.221 | 3.543 |
| sqlite_async | 2.890 | 3.244 | 0.232 | 0.239 |
| drift | 4.573 | 5.877 | 0.235 | 0.249 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.497 | 0.611 | 0.063 | 0.065 |
| sqlite3 | 1.449 | 1.488 | 1.449 | 1.488 |
| sqlite_async | 1.375 | 1.409 | 0.085 | 0.088 |
| drift | 1.916 | 2.181 | 0.085 | 0.089 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.255 | 0.263 | 0.060 | 0.061 |
| sqlite3 | 0.996 | 1.030 | 0.996 | 1.030 |
| sqlite_async | 0.951 | 1.001 | 0.084 | 0.086 |
| drift | 1.437 | 1.604 | 0.082 | 0.085 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.259 | 0.263 | 0.060 | 0.061 |
| sqlite3 | 0.966 | 1.009 | 0.966 | 1.009 |
| sqlite_async | 0.959 | 1.011 | 0.083 | 0.087 |
| drift | 1.432 | 1.647 | 0.084 | 0.105 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.016 | 0.022 | 0.002 | 0.003 |
| sqlite3 | 0.023 | 0.025 | 0.023 | 0.025 |
| sqlite_async | 0.066 | 0.082 | 0.004 | 0.006 |
| drift | 0.058 | 0.067 | 0.004 | 0.005 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.027 | 0.028 | 0.003 | 0.003 |
| sqlite3 | 0.064 | 0.065 | 0.064 | 0.065 |
| sqlite_async | 0.101 | 0.126 | 0.005 | 0.007 |
| drift | 0.117 | 0.123 | 0.005 | 0.006 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.044 | 0.045 | 0.005 | 0.006 |
| sqlite3 | 0.119 | 0.120 | 0.119 | 0.120 |
| sqlite_async | 0.149 | 0.160 | 0.009 | 0.009 |
| drift | 0.195 | 0.210 | 0.009 | 0.010 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.178 | 0.189 | 0.026 | 0.027 |
| sqlite3 | 0.560 | 0.572 | 0.560 | 0.572 |
| sqlite_async | 0.544 | 0.558 | 0.036 | 0.038 |
| drift | 0.783 | 0.805 | 0.036 | 0.038 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.345 | 0.350 | 0.052 | 0.053 |
| sqlite3 | 1.110 | 1.158 | 1.110 | 1.158 |
| sqlite_async | 1.044 | 1.110 | 0.071 | 0.076 |
| drift | 1.546 | 1.693 | 0.070 | 0.074 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.726 | 0.996 | 0.106 | 0.111 |
| sqlite3 | 2.217 | 2.707 | 2.217 | 2.707 |
| sqlite_async | 2.083 | 2.880 | 0.140 | 0.149 |
| drift | 3.063 | 3.460 | 0.139 | 0.143 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.950 | 4.752 | 0.262 | 0.299 |
| sqlite3 | 5.577 | 6.873 | 5.577 | 6.873 |
| sqlite_async | 5.369 | 7.150 | 0.353 | 0.380 |
| drift | 8.374 | 8.657 | 0.350 | 0.354 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.014 | 10.064 | 0.521 | 0.705 |
| sqlite3 | 13.332 | 14.761 | 13.332 | 14.761 |
| sqlite_async | 12.288 | 14.864 | 0.712 | 1.249 |
| drift | 21.711 | 26.602 | 0.735 | 1.254 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 10.128 | 16.189 | 1.046 | 1.665 |
| sqlite3 | 31.448 | 35.971 | 31.448 | 35.971 |
| sqlite_async | 33.196 | 40.211 | 1.413 | 5.171 |
| drift | 44.478 | 55.252 | 1.445 | 5.888 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.033 | 0.035 | 0.033 | 0.035 |
| sqlite3 + jsonEncode | 0.036 | 0.040 | 0.036 | 0.040 |
| sqlite_async + jsonEncode | 0.078 | 0.100 | 0.078 | 0.100 |
| drift + jsonEncode | 0.069 | 0.084 | 0.069 | 0.084 |
| resqlite selectBytes() | 0.011 | 0.013 | 0.011 | 0.013 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.104 | 0.147 | 0.104 | 0.147 |
| sqlite3 + jsonEncode | 0.138 | 0.147 | 0.138 | 0.147 |
| sqlite_async + jsonEncode | 0.167 | 0.177 | 0.167 | 0.177 |
| drift + jsonEncode | 0.186 | 0.203 | 0.186 | 0.203 |
| resqlite selectBytes() | 0.024 | 0.027 | 0.024 | 0.027 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.194 | 0.218 | 0.194 | 0.218 |
| sqlite3 + jsonEncode | 0.262 | 0.271 | 0.262 | 0.271 |
| sqlite_async + jsonEncode | 0.287 | 0.305 | 0.287 | 0.305 |
| drift + jsonEncode | 0.328 | 0.336 | 0.328 | 0.336 |
| resqlite selectBytes() | 0.037 | 0.038 | 0.037 | 0.038 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.886 | 0.913 | 0.886 | 0.913 |
| sqlite3 + jsonEncode | 1.257 | 1.290 | 1.257 | 1.290 |
| sqlite_async + jsonEncode | 1.250 | 1.327 | 1.250 | 1.327 |
| drift + jsonEncode | 1.490 | 1.633 | 1.490 | 1.633 |
| resqlite selectBytes() | 0.139 | 0.142 | 0.139 | 0.142 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.728 | 1.776 | 1.728 | 1.776 |
| sqlite3 + jsonEncode | 2.485 | 2.766 | 2.485 | 2.766 |
| sqlite_async + jsonEncode | 2.433 | 2.657 | 2.433 | 2.657 |
| drift + jsonEncode | 2.916 | 3.263 | 2.916 | 3.263 |
| resqlite selectBytes() | 0.271 | 0.278 | 0.271 | 0.278 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.813 | 5.457 | 3.813 | 5.457 |
| sqlite3 + jsonEncode | 5.382 | 7.103 | 5.382 | 7.103 |
| sqlite_async + jsonEncode | 5.268 | 7.531 | 5.268 | 7.531 |
| drift + jsonEncode | 6.294 | 9.301 | 6.294 | 9.301 |
| resqlite selectBytes() | 0.528 | 0.559 | 0.528 | 0.559 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 10.758 | 12.796 | 10.758 | 12.796 |
| sqlite3 + jsonEncode | 14.020 | 17.771 | 14.020 | 17.771 |
| sqlite_async + jsonEncode | 13.261 | 17.858 | 13.261 | 17.858 |
| drift + jsonEncode | 17.858 | 20.352 | 17.858 | 20.352 |
| resqlite selectBytes() | 1.351 | 1.372 | 1.351 | 1.372 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.158 | 21.844 | 20.158 | 21.844 |
| sqlite3 + jsonEncode | 28.129 | 31.836 | 28.129 | 31.836 |
| sqlite_async + jsonEncode | 29.272 | 31.737 | 29.272 | 31.737 |
| drift + jsonEncode | 37.029 | 40.129 | 37.029 | 40.129 |
| resqlite selectBytes() | 2.680 | 2.748 | 2.680 | 2.748 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 40.800 | 43.149 | 40.800 | 43.149 |
| sqlite3 + jsonEncode | 61.012 | 67.382 | 61.012 | 67.382 |
| sqlite_async + jsonEncode | 64.741 | 69.176 | 64.741 | 69.176 |
| drift + jsonEncode | 76.015 | 93.217 | 76.015 | 93.217 |
| resqlite selectBytes() | 5.508 | 7.941 | 5.508 | 7.941 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.33 | 0.30 |
| sqlite_async | 0.97 | 0.99 | 0.97 |
| drift | 1.49 | 2.19 | 1.49 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.33 | 0.35 | 0.16 |
| sqlite_async | 1.46 | 1.74 | 0.73 |
| drift | 2.72 | 3.22 | 1.36 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.37 | 0.61 | 0.09 |
| sqlite_async | 2.47 | 3.13 | 0.62 |
| drift | 5.22 | 5.96 | 1.31 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.69 | 1.00 | 0.09 |
| sqlite_async | 5.11 | 5.20 | 0.64 |
| drift | 10.23 | 10.84 | 1.28 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 144183 |
| resqlite per query | 0.007 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 144183 | 138292..156198 | 6.2 | 21.1 |
| sqlite3 | 200261 | 200080..202499 | 0.6 | 3.1 |
| sqlite_async | 52550 | 51793..53603 | 1.7 | 6.0 |
| drift | 47983 | 45842..50026 | 4.4 | 13.4 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 13.940 | 14.211 | 13.940 | 14.211 |
| sqlite_async | 36.153 | 38.862 | 36.153 | 38.862 |
| drift | 52.034 | 53.564 | 52.034 | 53.564 |
| sqlite3 (no cache) | 23.850 | 24.034 | 23.850 | 24.034 |
| sqlite3 (cached stmt) | 23.685 | 24.161 | 23.685 | 24.161 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.682 | 2.838 | 1.682 | 2.838 |
| sqlite3 execute() | 0.927 | 3.951 | 0.927 | 3.951 |
| sqlite_async execute() | 2.875 | 6.240 | 2.875 | 6.240 |
| drift execute() | 3.281 | 6.331 | 3.281 | 6.331 |

### Concurrent Single Inserts (100 concurrent)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite concurrent execute() | 0.869 | 2.239 | 0.869 | 2.239 |
| sqlite3 concurrent execute() | 0.929 | 4.974 | 0.929 | 4.974 |
| sqlite_async concurrent execute() | 2.692 | 7.027 | 2.692 | 7.027 |
| drift concurrent execute() | 1.796 | 5.515 | 1.796 | 5.515 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.068 | 0.074 | 0.068 | 0.074 |
| sqlite3 executeBatch() | 0.064 | 0.068 | 0.064 | 0.068 |
| sqlite_async executeBatch() | 0.109 | 0.115 | 0.109 | 0.115 |
| drift executeBatch() | 0.120 | 0.130 | 0.120 | 0.130 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.481 | 0.519 | 0.481 | 0.519 |
| sqlite3 executeBatch() | 0.538 | 0.560 | 0.538 | 0.560 |
| sqlite_async executeBatch() | 0.600 | 0.638 | 0.600 | 0.638 |
| drift executeBatch() | 0.702 | 0.732 | 0.702 | 0.732 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 3.872 | 6.087 | 3.872 | 6.087 |
| sqlite3 executeBatch() | 4.271 | 5.207 | 4.271 | 5.207 |
| sqlite_async executeBatch() | 5.090 | 6.092 | 5.090 | 6.092 |
| drift executeBatch() | 6.391 | 7.116 | 6.391 | 7.116 |

### Wide Batch Insert (10000 rows x 20 params)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 13.057 | 19.944 | 13.057 | 19.944 |
| sqlite3 executeBatch() | 19.196 | 26.937 | 19.196 | 26.937 |
| sqlite_async executeBatch() | 24.284 | 30.643 | 24.284 | 30.643 |
| drift executeBatch() | 27.803 | 34.086 | 27.803 | 34.086 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.058 | 0.068 | 0.058 | 0.068 |
| sqlite_async writeTransaction() | 0.095 | 0.107 | 0.095 | 0.107 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.078 | 0.099 | 0.078 | 0.099 |
| resqlite tx.execute() loop | 0.475 | 0.558 | 0.475 | 0.558 |
| sqlite_async tx.execute() loop | 0.979 | 1.068 | 0.979 | 1.068 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.474 | 0.508 | 0.474 | 0.508 |
| resqlite tx.execute() loop | 4.977 | 5.497 | 4.977 | 5.497 |
| sqlite_async tx.execute() loop | 9.249 | 9.822 | 9.249 | 9.822 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.101 | 0.108 | 0.101 | 0.108 |
| sqlite_async tx.getAll() | 0.199 | 0.203 | 0.199 | 0.203 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.180 | 0.187 | 0.180 | 0.187 |
| sqlite_async tx.getAll() | 0.345 | 0.365 | 0.345 | 0.365 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 0.861 | 0.993 | 0.861 | 0.993 |
| resqlite nested transaction() depth=5 | 0.085 | 0.090 | 0.085 | 0.090 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.065 | 0.076 | 0.065 | 0.076 |
| sqlite_async watch() | 0.129 | 0.192 | 0.129 | 0.192 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.062 | 0.103 | 0.062 | 0.103 |
| sqlite_async | 0.084 | 0.174 | 0.084 | 0.174 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.214 | 0.309 | 0.214 | 0.309 |
| sqlite_async | 0.784 | 1.637 | 0.784 | 1.637 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.860 | 4.062 | 1.860 | 4.062 |

### Long-Payload Unchanged Fanout (8 streams, 64 rows x 32KB TEXT + 32KB BLOB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.850 | 6.928 | 2.850 | 6.928 |

### Long-Text 32KB Unchanged Fanout (8 unchanged streams, 64 rows x 32KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.798 | 3.327 | 2.798 | 3.327 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.213 | 0.273 | 0.213 | 0.273 |
| sqlite_async | 0.290 | 0.387 | 0.290 | 0.387 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.869 | 2.869 | 2.869 | 2.869 |
| sqlite_async | 10.938 | 10.938 | 10.938 | 10.938 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.600 | 6.672 | 3.600 | 6.672 |
| sqlite_async | 5.439 | 9.679 | 5.439 | 9.679 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.564 | 0.735 | 0.564 | 0.735 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 7.063 | 9.673 | 7.063 | 9.673 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. For resqlite, this emission metric can reflect writer-side column-level invalidation, experiment 075's native result-hash short-circuit, or both. Use A11c (Many-Streams Writer Throughput) when the question is specifically writer-side dispatch elision.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 80.0 | 0.000 |
| sqlite_async | 4482 | 1223.5 | 1.067 |
| drift | 5000 | 1013.5 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 71.0 | 0.000 |
| sqlite_async | 4199 | 1150.5 | 1.067 |
| drift | 5000 | 1025.8 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 226.22 | 227.95 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 444.28 | 444.53 | 0.00 | 0.01 | 1115 | 3 |
| drift stream() | 548.78 | 549.55 | 0.01 | 0.01 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.019 | 0.042 | 0.000 | 0.000 |
| sqlite3 | 0.035 | 0.052 | 0.035 | 0.052 |
| sqlite_async | 0.052 | 0.069 | 0.000 | 0.000 |
| drift | 0.054 | 0.079 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.015 | 0.027 | 0.000 | 0.000 |
| sqlite3 | 0.020 | 0.029 | 0.020 | 0.029 |
| sqlite_async | 0.036 | 0.046 | 0.000 | 0.000 |
| drift | 0.039 | 0.050 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.023 | 0.032 | 0.000 | 0.000 |
| sqlite3 | 0.031 | 0.033 | 0.031 | 0.033 |
| sqlite_async | 0.054 | 0.063 | 0.000 | 0.000 |
| drift | 0.053 | 0.056 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.008 | 0.015 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.020 | 0.023 | 0.000 | 0.000 |
| drift | 0.019 | 0.023 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.039 | 0.044 | 0.004 | 0.004 |
| sqlite3 | 0.067 | 0.078 | 0.067 | 0.078 |
| sqlite_async | 0.081 | 0.087 | 0.001 | 0.001 |
| drift | 0.090 | 0.091 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 108.050 | 108.325 | 0.000 | 0.000 | 0 |
| sqlite_async | 219.032 | 219.235 | 0.000 | 0.000 | 44 |
| drift | 233.979 | 235.817 | 0.002 | 0.003 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 241.60 | 241.60 | 0.00 | 0.00 | 13.40 | 228.18 | 0 |
| sqlite_async | 485.10 | 485.10 | 0.00 | 0.00 | 25.49 | 459.60 | 1187 |
| drift | 1690.44 | 1690.44 | 0.04 | 0.04 | 14.24 | 1676.49 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 2.58 | 21.02 | 0.00..11.48 | ±5.74 |
| sqlite3 select() | 3.28 | 9.72 | 0.00..8.73 | ±4.37 |
| sqlite_async select() | 0.50 | 0.50 | 0.50..0.50 | ±0.00 |
| drift select() | 11.30 | 74.45 | 0.00..16.94 | ±8.47 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 20.00 | 0.00..1.50 | ±0.75 |
| resqlite + jsonEncode | 5.80 | 83.27 | 0.00..15.53 | ±7.77 |
| sqlite3 + jsonEncode | 0.00 | 23.52 | 0.00..4.77 | ±2.38 |
| sqlite_async + jsonEncode | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| drift + jsonEncode | 0.00 | 70.42 | 0.00..24.84 | ±12.42 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.50 | 4.63 | 0.00..0.94 | ±0.47 |
| sqlite3 executeBatch() | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 3.38 | 0.00..0.03 | ±0.02 |
| drift batch() | 0.00 | 2.02 | 0.00..0.00 | ±0.00 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.14 | 0.00..0.06 | ±0.03 |
| sqlite_async watch() | 0.00 | 0.50 | 0.00..0.03 | ±0.02 |

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

## Comparison vs Previous Run

Previous: `2026-06-24T07-27-32-baseline-for-exp198.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.29 | 0.30 | +0.01 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.29 | 0.30 | +0.01 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.31 | 0.33 | +0.02 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.15 | 0.16 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.37 | 0.37 | +0.00 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.72 | 0.69 | -0.03 | ±10% / ±0.07 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.09 | 0.09 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 110.30 | 108.05 | -2.25 | ±10% / ±11.03 ms | 0.0% | single run | ⚪ Neutral |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 240.94 | 241.60 | +0.66 | ±10% / ±24.16 ms | 0.0% | single run | ⚪ Neutral |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 226.05 | 226.22 | +0.17 | ±10% / ±22.62 ms | 0.0% | single run | ⚪ Neutral |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 13.96 | 13.94 | -0.02 | ±10% / ±1.40 ms | 0.0% | single run | ⚪ Neutral |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 13.96 | 13.94 | -0.02 | ±10% / ±1.40 ms | 0.0% | single run | ⚪ Neutral |
| Point Query Throughput / resqlite qps | 155427.00 | 144183.00 | -11244.00 | ±10% / ±15542.70 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.02 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.19 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.19 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.35 | 0.34 | -0.00 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.79 | 1.73 | -0.06 | ±10% / ±0.18 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.79 | 1.73 | -0.06 | ±10% / ±0.18 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.28 | 0.27 | -0.01 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.28 | 0.27 | -0.01 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.07 | 4.01 | -0.05 | ±10% / ±0.41 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 20.51 | 20.16 | -0.35 | ±10% / ±2.05 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 20.51 | 20.16 | -0.35 | ±10% / ±2.05 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.52 | 0.52 | -0.00 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 2.84 | 2.68 | -0.16 | ±10% / ±0.28 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 2.84 | 2.68 | -0.16 | ±10% / ±0.28 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.73 | 0.73 | -0.01 | ±10% / ±0.07 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.71 | 3.81 | +0.10 | ±10% / ±0.38 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.71 | 3.81 | +0.10 | ±10% / ±0.38 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.11 | 0.11 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.56 | 0.53 | -0.04 | ±10% / ±0.06 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.56 | 0.53 | -0.04 | ±10% / ±0.06 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.13 | 10.13 | -0.00 | ±10% / ±1.01 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 41.98 | 40.80 | -1.18 | ±10% / ±4.20 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 41.98 | 40.80 | -1.18 | ±10% / ±4.20 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.03 | 1.05 | +0.02 | ±10% / ±0.10 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 5.80 | 5.51 | -0.29 | ±10% / ±0.58 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 5.80 | 5.51 | -0.29 | ±10% / ±0.58 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.18 | 0.18 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.88 | 0.89 | +0.00 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.88 | 0.89 | +0.00 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.16 | 0.14 | -0.02 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.16 | 0.14 | -0.02 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 1.95 | 1.95 | +0.00 | ±10% / ±0.20 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 9.61 | 10.76 | +1.15 | ±10% / ±1.08 ms | 0.0% | single run | 🔴 Regression (+12%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 9.61 | 10.76 | +1.15 | ±10% / ±1.08 ms | 0.0% | single run | 🔴 Regression (+12%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.26 | 0.26 | +0.00 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.45 | 1.35 | -0.09 | ±10% / ±0.14 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.45 | 1.35 | -0.09 | ±10% / ±0.14 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.15 | 0.13 | -0.02 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.02 | 0.04 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.26 | 0.26 | -0.00 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.26 | 0.26 | -0.00 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.50 | 0.50 | -0.00 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.86 | 0.85 | -0.01 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.22 | 0.22 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.10 | 0.09 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.07 | 0.07 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.02 | 0.02 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.24 | 0.21 | -0.03 | ±10% / ±0.02 ms | 0.0% | single run | 🟢 Win (-11%) |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.18 | 0.17 | -0.02 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.04 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.83 | 1.73 | -0.09 | ±10% / ±0.18 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.48 | 1.44 | -0.05 | ±10% / ±0.15 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.30 | 0.29 | -0.01 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.10 | 20.48 | +0.39 | ±10% / ±2.05 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 14.61 | 14.98 | +0.36 | ±10% / ±1.50 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 2.85 | 2.74 | -0.11 | ±10% / ±0.29 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / Large payload (~650KB) / resqlite s... | 0.23 | 0.28 | +0.05 | ±10% / ±0.03 ms | 0.0% | single run | 🔴 Regression (+21%) |
| Select → JSON Bytes / Large payload (~650KB) / resqlite s... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 10 rows / resqlite select() | 0.09 | 0.09 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 10 rows / resqlite select() [main] | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 100 rows / resqlite select() | 0.06 | 0.07 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 1000 rows / resqlite select() | 0.35 | 0.38 | +0.04 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.05 | 0.06 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 10000 rows / resqlite select() | 4.08 | 4.02 | -0.06 | ±10% / ±0.41 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.51 | 0.51 | +0.00 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Fan-out (10 streams) / resqlite | 0.23 | 0.21 | -0.02 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.23 | 0.21 | -0.02 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.57 | 0.56 | -0.00 | ±10% / ±0.06 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.57 | 0.56 | -0.00 | ±10% / ±0.06 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Initial Emission / resqlite stream() | 0.07 | 0.07 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Initial Emission / resqlite stream() [main] | 0.07 | 0.07 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Invalidation Latency / resqlite | 0.06 | 0.06 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Invalidation Latency / resqlite [main] | 0.06 | 0.06 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 ... | 2.66 | 2.85 | +0.19 | ±10% / ±0.29 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 ... | 2.66 | 2.85 | +0.19 | ±10% / ±0.29 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged ... | 2.80 | 2.80 | -0.01 | ±10% / ±0.28 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged ... | 2.80 | 2.80 | -0.01 | ±10% / ±0.28 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 1.82 | 1.86 | +0.04 | ±10% / ±0.19 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 1.82 | 1.86 | +0.04 | ±10% / ±0.19 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.34 | 3.60 | +0.26 | ±10% / ±0.36 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.34 | 3.60 | +0.26 | ±10% / ±0.36 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.94 | 2.87 | -0.07 | ±10% / ±0.29 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.94 | 2.87 | -0.07 | ±10% / ±0.29 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.49 | 7.06 | +0.57 | ±10% / ±0.71 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.49 | 7.06 | +0.57 | ±10% / ±0.71 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.21 | 0.21 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.21 | 0.21 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.07 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.07 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.48 | 0.48 | -0.00 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.48 | 0.48 | -0.00 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.71 | 3.87 | +0.16 | ±10% / ±0.39 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.71 | 3.87 | +0.16 | ±10% / ±0.39 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.52 | 0.47 | -0.05 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.52 | 0.47 | -0.05 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.08 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.08 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 4.61 | 4.98 | +0.36 | ±10% / ±0.50 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 4.61 | 4.98 | +0.36 | ±10% / ±0.50 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.55 | 0.47 | -0.07 | ±10% / ±0.05 ms | 0.0% | single run | 🟢 Win (-13%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.55 | 0.47 | -0.07 | ±10% / ±0.05 ms | 0.0% | single run | 🟢 Win (-13%) |
| Write Performance / Concurrent Single Inserts (100 concur... | 0.87 | 0.87 | -0.00 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Concurrent Single Inserts (100 concur... | 0.87 | 0.87 | -0.00 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.06 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.06 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Nested Transactions (savepoints) / re... | 0.09 | 0.09 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Nested Transactions (savepoints) / re... | 0.09 | 0.09 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Nested Transactions (savepoints) / re... | 0.82 | 0.86 | +0.04 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Nested Transactions (savepoints) / re... | 0.82 | 0.86 | +0.04 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Single Inserts (100 sequential) / res... | 1.50 | 1.68 | +0.18 | ±10% / ±0.17 ms | 0.0% | single run | 🔴 Regression (+12%) |
| Write Performance / Single Inserts (100 sequential) / res... | 1.50 | 1.68 | +0.18 | ±10% / ±0.17 ms | 0.0% | single run | 🔴 Regression (+12%) |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.18 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.18 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 13.19 | 13.06 | -0.13 | ±10% / ±1.32 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 13.19 | 13.06 | -0.13 | ±10% / ±1.32 ms | 0.0% | single run | ⚪ Neutral |

**Summary:** 3 wins, 5 regressions, 161 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 0.02 | 0.50 | +0.48 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.02 | 0.00 | -0.02 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 0.00 | 0.00 | +0.00 MB | ±12.42 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 0.00 | 5.80 | +5.80 MB | ±7.77 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 0.00 | +0.00 MB | ±0.75 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 0.00 | 0.00 | +0.00 MB | ±2.38 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 6.73 | 11.30 | +4.57 MB | ±8.47 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / resqlite select() | 0.00 | 2.58 | +2.58 MB | ±5.74 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite3 select() | 4.61 | 3.28 | -1.33 MB | ±4.37 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 0.98 | 0.50 | -0.48 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.06 | 0.06 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 0 wins, 0 regressions, 15 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 4222 | 4482 | +260 | ±100 | 🔴 More re-emits (+260) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 3869 | 4199 | +330 | ±100 | 🔴 More re-emits (+330) |

**Granularity summary:** 0 fewer-re-emit, 2 more-re-emit, 4 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


