# resqlite Benchmark Results

Generated: 2026-08-12T07:39:57.362817

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp270-read-result-cache`
- Repeats: `5`
- Runtime: `dart-vm / Dart 3.12.2`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `exp-270-read-result-cache @ dae9c6c4c6df`
- Comparison baseline: `2026-08-12T10-15-00Z-exp269-opaque-work.md`
- Comparison mode: `automatic`
- Comparison baseline compatibility: `incompatible (automatic comparison skipped)`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.001 | 0.001 | 0.000 | 0.000 |
| sqlite3 select() | 0.015 | 0.016 | 0.015 | 0.016 |
| sqlite_async select() | 0.031 | 0.032 | 0.001 | 0.001 |
| drift select() | 0.037 | 0.039 | 0.001 | 0.001 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.005 | 0.006 | 0.005 | 0.005 |
| sqlite3 select() | 0.115 | 0.118 | 0.115 | 0.118 |
| sqlite_async select() | 0.126 | 0.131 | 0.010 | 0.010 |
| drift select() | 0.176 | 0.183 | 0.010 | 0.010 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.312 | 0.324 | 0.051 | 0.053 |
| sqlite3 select() | 1.101 | 1.150 | 1.101 | 1.150 |
| sqlite_async select() | 1.039 | 1.052 | 0.091 | 0.093 |
| drift select() | 1.501 | 1.818 | 0.091 | 0.094 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 3.316 | 8.458 | 0.506 | 0.842 |
| sqlite3 select() | 13.460 | 16.106 | 13.460 | 16.106 |
| sqlite_async select() | 13.291 | 15.631 | 0.961 | 1.564 |
| drift select() | 20.031 | 26.914 | 0.924 | 1.278 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row. The large-payload row isolates resqlite selectBytes because it guards the native bytes transfer policy without multiplying large JSON encoding work across every peer.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.016 | 0.017 | 0.016 | 0.016 |
| sqlite3 + jsonEncode | 0.030 | 0.031 | 0.030 | 0.031 |
| sqlite_async + jsonEncode | 0.046 | 0.049 | 0.017 | 0.018 |
| drift + jsonEncode | 0.052 | 0.053 | 0.017 | 0.018 |
| resqlite selectBytes() | 0.010 | 0.012 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.158 | 0.160 | 0.157 | 0.159 |
| sqlite3 + jsonEncode | 0.264 | 0.272 | 0.264 | 0.272 |
| sqlite_async + jsonEncode | 0.275 | 0.280 | 0.158 | 0.162 |
| drift + jsonEncode | 0.319 | 0.324 | 0.159 | 0.161 |
| resqlite selectBytes() | 0.033 | 0.034 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.776 | 2.292 | 1.526 | 1.873 |
| sqlite3 + jsonEncode | 2.545 | 5.061 | 2.545 | 5.061 |
| sqlite_async + jsonEncode | 2.482 | 5.266 | 1.531 | 3.385 |
| drift + jsonEncode | 3.072 | 3.456 | 1.572 | 1.872 |
| resqlite selectBytes() | 0.261 | 0.280 | 0.000 | 0.000 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.579 | 26.465 | 16.407 | 18.547 |
| sqlite3 + jsonEncode | 29.128 | 36.191 | 29.128 | 36.191 |
| sqlite_async + jsonEncode | 30.500 | 36.473 | 16.333 | 18.212 |
| drift + jsonEncode | 39.377 | 44.776 | 16.087 | 21.131 |
| resqlite selectBytes() | 2.625 | 6.148 | 0.000 | 0.003 |

### Large payload (~650KB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.229 | 0.328 | 0.000 | 0.000 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.083 | 0.088 | 0.023 | 0.023 |
| sqlite3 | 0.320 | 0.325 | 0.320 | 0.325 |
| sqlite_async | 0.363 | 0.373 | 0.032 | 0.034 |
| drift | 0.554 | 0.596 | 0.031 | 0.032 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.772 | 0.794 | 0.217 | 0.223 |
| sqlite3 | 3.139 | 3.593 | 3.139 | 3.593 |
| sqlite_async | 2.852 | 3.291 | 0.228 | 0.238 |
| drift | 4.420 | 6.903 | 0.230 | 0.243 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.371 | 0.379 | 0.060 | 0.063 |
| sqlite3 | 1.400 | 1.430 | 1.400 | 1.430 |
| sqlite_async | 1.338 | 1.609 | 0.083 | 0.085 |
| drift | 1.831 | 2.115 | 0.082 | 0.084 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.240 | 0.250 | 0.060 | 0.063 |
| sqlite3 | 0.959 | 0.987 | 0.959 | 0.987 |
| sqlite_async | 0.941 | 0.956 | 0.082 | 0.085 |
| drift | 1.426 | 1.639 | 0.083 | 0.088 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.255 | 0.257 | 0.063 | 0.065 |
| sqlite3 | 0.967 | 0.996 | 0.967 | 0.996 |
| sqlite_async | 0.969 | 1.009 | 0.085 | 0.088 |
| drift | 1.437 | 1.737 | 0.085 | 0.089 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.001 | 0.001 | 0.000 | 0.000 |
| sqlite3 | 0.015 | 0.016 | 0.015 | 0.016 |
| sqlite_async | 0.030 | 0.031 | 0.001 | 0.001 |
| drift | 0.035 | 0.038 | 0.001 | 0.001 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.003 | 0.003 | 0.002 | 0.002 |
| sqlite3 | 0.060 | 0.063 | 0.060 | 0.063 |
| sqlite_async | 0.075 | 0.076 | 0.004 | 0.004 |
| drift | 0.100 | 0.109 | 0.004 | 0.004 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.006 | 0.006 | 0.005 | 0.005 |
| sqlite3 | 0.118 | 0.122 | 0.118 | 0.122 |
| sqlite_async | 0.129 | 0.135 | 0.008 | 0.008 |
| drift | 0.175 | 0.179 | 0.007 | 0.008 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.167 | 0.172 | 0.027 | 0.029 |
| sqlite3 | 0.561 | 0.571 | 0.561 | 0.571 |
| sqlite_async | 0.540 | 0.547 | 0.036 | 0.039 |
| drift | 0.769 | 0.784 | 0.035 | 0.036 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.321 | 0.328 | 0.054 | 0.058 |
| sqlite3 | 1.121 | 1.177 | 1.121 | 1.177 |
| sqlite_async | 1.084 | 1.129 | 0.072 | 0.076 |
| drift | 1.563 | 1.614 | 0.072 | 0.075 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.627 | 1.171 | 0.108 | 0.146 |
| sqlite3 | 2.239 | 2.844 | 2.239 | 2.844 |
| sqlite_async | 2.182 | 2.429 | 0.146 | 0.152 |
| drift | 2.950 | 3.317 | 0.137 | 0.159 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.775 | 5.109 | 0.265 | 0.414 |
| sqlite3 | 5.424 | 6.755 | 5.424 | 6.755 |
| sqlite_async | 5.180 | 5.761 | 0.345 | 0.372 |
| drift | 7.869 | 7.977 | 0.343 | 0.344 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.447 | 9.170 | 0.527 | 0.901 |
| sqlite3 | 14.610 | 19.110 | 14.610 | 19.110 |
| sqlite_async | 12.074 | 13.400 | 0.735 | 0.764 |
| drift | 17.517 | 26.945 | 0.715 | 1.138 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 8.694 | 15.709 | 1.080 | 2.250 |
| sqlite3 | 35.302 | 42.354 | 35.302 | 42.354 |
| sqlite_async | 35.475 | 41.707 | 1.460 | 2.200 |
| drift | 47.483 | 59.049 | 1.432 | 2.073 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.017 | 0.017 | 0.017 | 0.017 |
| sqlite3 + jsonEncode | 0.031 | 0.036 | 0.031 | 0.036 |
| sqlite_async + jsonEncode | 0.048 | 0.056 | 0.048 | 0.056 |
| drift + jsonEncode | 0.053 | 0.062 | 0.053 | 0.062 |
| resqlite selectBytes() | 0.011 | 0.018 | 0.011 | 0.018 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.081 | 0.083 | 0.081 | 0.083 |
| sqlite3 + jsonEncode | 0.140 | 0.145 | 0.140 | 0.145 |
| sqlite_async + jsonEncode | 0.155 | 0.159 | 0.155 | 0.159 |
| drift + jsonEncode | 0.177 | 0.179 | 0.177 | 0.179 |
| resqlite selectBytes() | 0.026 | 0.030 | 0.026 | 0.030 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.163 | 0.167 | 0.163 | 0.167 |
| sqlite3 + jsonEncode | 0.277 | 0.282 | 0.277 | 0.282 |
| sqlite_async + jsonEncode | 0.286 | 0.292 | 0.286 | 0.292 |
| drift + jsonEncode | 0.333 | 0.351 | 0.333 | 0.351 |
| resqlite selectBytes() | 0.041 | 0.046 | 0.041 | 0.046 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.916 | 0.949 | 0.916 | 0.949 |
| sqlite3 + jsonEncode | 1.289 | 1.451 | 1.289 | 1.451 |
| sqlite_async + jsonEncode | 1.274 | 1.339 | 1.274 | 1.339 |
| drift + jsonEncode | 1.494 | 1.519 | 1.494 | 1.519 |
| resqlite selectBytes() | 0.132 | 0.136 | 0.132 | 0.136 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.781 | 1.817 | 1.781 | 1.817 |
| sqlite3 + jsonEncode | 2.545 | 2.867 | 2.545 | 2.867 |
| sqlite_async + jsonEncode | 2.479 | 2.742 | 2.479 | 2.742 |
| drift + jsonEncode | 2.951 | 3.360 | 2.951 | 3.360 |
| resqlite selectBytes() | 0.256 | 0.267 | 0.256 | 0.267 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.776 | 6.759 | 3.776 | 6.759 |
| sqlite3 + jsonEncode | 5.383 | 8.404 | 5.383 | 8.404 |
| sqlite_async + jsonEncode | 5.262 | 8.640 | 5.262 | 8.640 |
| drift + jsonEncode | 6.216 | 10.386 | 6.216 | 10.386 |
| resqlite selectBytes() | 0.598 | 0.624 | 0.598 | 0.624 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 10.058 | 13.201 | 10.058 | 13.201 |
| sqlite3 + jsonEncode | 14.476 | 18.738 | 14.476 | 18.738 |
| sqlite_async + jsonEncode | 13.982 | 18.587 | 13.982 | 18.587 |
| drift + jsonEncode | 16.235 | 20.825 | 16.235 | 20.825 |
| resqlite selectBytes() | 1.313 | 1.364 | 1.313 | 1.364 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 23.611 | 25.219 | 23.611 | 25.219 |
| sqlite3 + jsonEncode | 28.826 | 35.794 | 28.826 | 35.794 |
| sqlite_async + jsonEncode | 31.880 | 34.372 | 31.880 | 34.372 |
| drift + jsonEncode | 37.735 | 43.466 | 37.735 | 43.466 |
| resqlite selectBytes() | 2.593 | 2.647 | 2.593 | 2.647 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 45.880 | 47.882 | 45.880 | 47.882 |
| sqlite3 + jsonEncode | 63.827 | 69.146 | 63.827 | 69.146 |
| sqlite_async + jsonEncode | 68.334 | 76.308 | 68.334 | 76.308 |
| drift + jsonEncode | 84.400 | 97.453 | 84.400 | 97.453 |
| resqlite selectBytes() | 5.325 | 5.811 | 5.325 | 5.811 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.26 | 0.26 | 0.26 |
| sqlite_async | 0.95 | 1.02 | 0.95 |
| drift | 1.41 | 1.43 | 1.41 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.27 | 0.29 | 0.14 |
| sqlite_async | 1.40 | 1.67 | 0.70 |
| drift | 2.57 | 2.89 | 1.28 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.33 | 0.69 | 0.08 |
| sqlite_async | 2.34 | 3.01 | 0.58 |
| drift | 4.96 | 5.41 | 1.24 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.68 | 2.03 | 0.09 |
| sqlite_async | 4.72 | 5.66 | 0.59 |
| drift | 10.42 | 11.23 | 1.30 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 150182 |
| resqlite per query | 0.007 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 150182 | 149981..156892 | 2.3 | 2.9 |
| sqlite3 | 193654 | 193103..198819 | 1.5 | 2.1 |
| sqlite_async | 50153 | 49897..51706 | 1.8 | 2.3 |
| drift | 48574 | 48521..48688 | 0.2 | 1.0 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.200 | 14.445 | 14.200 | 14.445 |
| sqlite_async | 35.751 | 37.477 | 35.751 | 37.477 |
| drift | 50.671 | 53.179 | 50.671 | 53.179 |
| sqlite3 (no cache) | 23.121 | 23.386 | 23.121 | 23.386 |
| sqlite3 (cached stmt) | 22.108 | 22.365 | 22.108 | 22.365 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.466 | 1.931 | 1.466 | 1.931 |
| sqlite3 execute() | 0.917 | 1.522 | 0.917 | 1.522 |
| sqlite_async execute() | 2.757 | 3.397 | 2.757 | 3.397 |
| drift execute() | 2.712 | 3.481 | 2.712 | 3.481 |

### Concurrent Single Inserts (100 concurrent)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite concurrent execute() | 0.821 | 1.232 | 0.821 | 1.232 |
| sqlite3 concurrent execute() | 0.857 | 1.544 | 0.857 | 1.544 |
| sqlite_async concurrent execute() | 2.648 | 3.277 | 2.648 | 3.277 |
| drift concurrent execute() | 1.699 | 2.366 | 1.699 | 2.366 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.051 | 0.053 | 0.051 | 0.053 |
| sqlite3 executeBatch() | 0.049 | 0.049 | 0.049 | 0.049 |
| sqlite_async executeBatch() | 0.094 | 0.098 | 0.094 | 0.098 |
| drift executeBatch() | 0.110 | 0.115 | 0.110 | 0.115 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.412 | 0.435 | 0.412 | 0.435 |
| sqlite3 executeBatch() | 0.437 | 0.454 | 0.437 | 0.454 |
| sqlite_async executeBatch() | 0.515 | 0.545 | 0.515 | 0.545 |
| drift executeBatch() | 0.665 | 0.682 | 0.665 | 0.682 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 3.779 | 4.511 | 3.779 | 4.511 |
| sqlite3 executeBatch() | 3.876 | 4.137 | 3.876 | 4.137 |
| sqlite_async executeBatch() | 4.542 | 5.035 | 4.542 | 5.035 |
| drift executeBatch() | 5.752 | 6.364 | 5.752 | 6.364 |

### Wide Batch Insert (10000 rows x 20 params)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 12.900 | 23.868 | 12.900 | 23.868 |
| sqlite3 executeBatch() | 18.760 | 20.797 | 18.760 | 20.797 |
| sqlite_async executeBatch() | 22.248 | 26.718 | 22.248 | 26.718 |
| drift executeBatch() | 24.821 | 27.406 | 24.821 | 27.406 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.044 | 0.051 | 0.044 | 0.051 |
| sqlite_async writeTransaction() | 0.079 | 0.085 | 0.079 | 0.085 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.059 | 0.067 | 0.059 | 0.067 |
| resqlite tx.execute() loop | 0.372 | 0.448 | 0.372 | 0.448 |
| sqlite_async tx.execute() loop | 0.915 | 1.011 | 0.915 | 1.011 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.399 | 0.407 | 0.399 | 0.407 |
| resqlite tx.execute() loop | 4.372 | 5.167 | 4.372 | 5.167 |
| sqlite_async tx.execute() loop | 9.508 | 10.212 | 9.508 | 10.212 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.101 | 0.107 | 0.101 | 0.107 |
| sqlite_async tx.getAll() | 0.208 | 0.227 | 0.208 | 0.227 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.176 | 0.179 | 0.176 | 0.179 |
| sqlite_async tx.getAll() | 0.370 | 0.392 | 0.370 | 0.392 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 0.782 | 0.861 | 0.782 | 0.861 |
| resqlite nested transaction() depth=5 | 0.067 | 0.074 | 0.067 | 0.074 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.026 | 0.028 | 0.026 | 0.028 |
| sqlite_async watch() | 0.101 | 0.108 | 0.101 | 0.108 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.041 | 0.059 | 0.041 | 0.059 |
| sqlite_async | 0.063 | 0.067 | 0.063 | 0.067 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.186 | 0.298 | 0.186 | 0.298 |
| sqlite_async | 0.513 | 1.126 | 0.513 | 1.126 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.462 | 2.175 | 1.462 | 2.175 |

### Long-Payload Unchanged Fanout (8 streams, 64 rows x 32KB TEXT + 32KB BLOB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.261 | 2.980 | 2.261 | 2.980 |

### Long-Text 32KB Unchanged Fanout (8 unchanged streams, 64 rows x 32KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.562 | 3.745 | 2.562 | 3.745 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.180 | 0.224 | 0.180 | 0.224 |
| sqlite_async | 0.247 | 0.302 | 0.247 | 0.302 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.647 | 1.647 | 1.647 | 1.647 |
| sqlite_async | 9.083 | 9.083 | 9.083 | 9.083 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.349 | 3.834 | 3.349 | 3.834 |
| sqlite_async | 5.211 | 6.206 | 5.211 | 6.206 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.473 | 0.644 | 0.473 | 0.644 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 5.872 | 6.648 | 5.872 | 6.648 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. For resqlite, this emission metric can reflect writer-side column-level invalidation, experiment 075's native result-hash short-circuit, or both. Use A11c (Many-Streams Writer Throughput) when the question is specifically writer-side dispatch elision.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 67.4 | 0.000 |
| sqlite_async | 4568 | 1261.3 | 1.184 |
| drift | 5000 | 1020.4 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 70.2 | 0.000 |
| sqlite_async | 3857 | 1076.5 | 1.184 |
| drift | 5000 | 1022.1 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 222.68 | 225.19 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 445.81 | 446.70 | 0.00 | 0.00 | 1112 | 3 |
| drift stream() | 581.19 | 583.34 | 0.03 | 0.04 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.019 | 0.033 | 0.000 | 0.000 |
| sqlite3 | 0.018 | 0.025 | 0.018 | 0.025 |
| sqlite_async | 0.038 | 0.048 | 0.000 | 0.000 |
| drift | 0.040 | 0.062 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.015 | 0.023 | 0.000 | 0.000 |
| sqlite3 | 0.011 | 0.014 | 0.011 | 0.014 |
| sqlite_async | 0.030 | 0.038 | 0.000 | 0.000 |
| drift | 0.032 | 0.050 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.019 | 0.031 | 0.000 | 0.000 |
| sqlite3 | 0.030 | 0.031 | 0.030 | 0.031 |
| sqlite_async | 0.057 | 0.067 | 0.000 | 0.000 |
| drift | 0.054 | 0.062 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.007 | 0.014 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.021 | 0.025 | 0.000 | 0.000 |
| drift | 0.022 | 0.028 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.000 | 0.000 | 0.001 | 0.001 |
| sqlite3 | 0.066 | 0.068 | 0.066 | 0.068 |
| sqlite_async | 0.080 | 0.083 | 0.001 | 0.001 |
| drift | 0.088 | 0.091 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 110.228 | 112.283 | 0.000 | 0.000 | 0 |
| sqlite_async | 214.015 | 219.568 | 0.000 | 0.000 | 36 |
| drift | 220.935 | 235.841 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 237.62 | 237.62 | 0.00 | 0.00 | 12.07 | 226.65 | 0 |
| sqlite_async | 482.58 | 482.58 | 0.00 | 0.00 | 24.39 | 458.19 | 1184 |
| drift | 1680.50 | 1680.50 | 0.66 | 0.66 | 14.80 | 1665.90 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 0.00 | 11.58 | 0.00..3.97 | ±1.98 |
| sqlite3 select() | 2.64 | 9.61 | 2.00..8.63 | ±3.31 |
| sqlite_async select() | 1.00 | 1.00 | 1.00..1.00 | ±0.00 |
| drift select() | 8.88 | 73.95 | 0.00..19.98 | ±9.99 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 20.00 | 0.00..2.00 | ±1.00 |
| resqlite + jsonEncode | 3.09 | 13.27 | 0.00..5.11 | ±2.55 |
| sqlite3 + jsonEncode | 0.00 | 47.91 | 0.00..18.06 | ±9.03 |
| sqlite_async + jsonEncode | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| drift + jsonEncode | 0.00 | 32.09 | 0.00..15.17 | ±7.59 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 7.06 | 7.73 | 0.45..7.58 | ±3.56 |
| sqlite3 executeBatch() | 0.00 | 1.20 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 0.52 | 0.00..0.00 | ±0.00 |
| drift batch() | 0.50 | 4.50 | 0.00..3.05 | ±1.52 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.13 | 0.02..0.08 | ±0.03 |
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
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.02 | 0.02..0.02 | 2.8% | 5.6% | 0.0% | stable |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02..0.02 | 2.6% | 5.3% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.01..0.01 | 3.6% | 7.1% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.26 | 0.26..0.27 | 1.9% | 3.8% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.26 | 0.26..0.27 | 1.9% | 3.8% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.27 | 0.27..0.29 | 3.7% | 7.4% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.14 | 0.14..0.15 | 3.6% | 7.1% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.33 | 0.33..0.41 | 12.1% | 24.2% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.08 | 0.08..0.10 | 12.5% | 25.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.64 | 0.62..0.76 | 10.9% | 21.9% | 3.1% | moderate |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.08 | 0.08..0.09 | 6.2% | 12.5% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 150.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 110.23 | 109.83..110.56 | 0.3% | 0.7% | 0.2% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 238.90 | 235.22..441.49 | 43.2% | 86.3% | 0.9% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 222.68 | 217.01..225.80 | 2.0% | 3.9% | 1.2% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 13.64 | 13.49..14.20 | 2.6% | 5.2% | 1.1% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 13.64 | 13.49..14.20 | 2.6% | 5.2% | 1.1% | stable |
| Point Query Throughput / resqlite qps | 151537.00 | 149666.00..160516.00 | 3.6% | 7.2% | 0.9% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.00 | 0.00..0.00 | 50.0% | 100.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.02 | 0.02..0.02 | 17.6% | 35.3% | 5.9% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02..0.02 | 17.6% | 35.3% | 5.9% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.01 | 9.1% | 18.2% | 9.1% | noisy |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.01 | 9.1% | 18.2% | 9.1% | noisy |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.01 | 0.01..0.01 | 10.0% | 20.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.16 | 0.16..0.16 | 1.9% | 3.8% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.16 | 0.16..0.16 | 1.9% | 3.8% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.04 | 0.03..0.04 | 10.0% | 20.0% | 2.9% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.04 | 0.03..0.04 | 10.0% | 20.0% | 2.9% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.31 | 0.31..0.32 | 2.3% | 4.5% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.79 | 1.78..1.89 | 3.0% | 5.9% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.79 | 1.78..1.89 | 3.0% | 5.9% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.05 | 0.05..0.05 | 1.9% | 3.8% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.26 | 0.26..0.27 | 2.3% | 4.6% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.26 | 0.26..0.27 | 2.3% | 4.6% | 1.1% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 3.37 | 3.29..3.46 | 2.4% | 4.9% | 2.3% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 23.61 | 20.16..24.24 | 8.6% | 17.3% | 2.7% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 23.61 | 20.16..24.24 | 8.6% | 17.3% | 2.7% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.52 | 0.51..0.54 | 2.7% | 5.4% | 1.4% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 2.59 | 2.54..2.77 | 4.6% | 9.2% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 2.59 | 2.54..2.77 | 4.6% | 9.2% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.60 | 0.60..0.63 | 2.3% | 4.7% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.80 | 3.73..3.85 | 1.6% | 3.3% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.80 | 3.73..3.85 | 1.6% | 3.3% | 1.2% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.10 | 0.10..0.11 | 2.4% | 4.8% | 1.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.53 | 0.50..0.60 | 9.6% | 19.2% | 3.4% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.53 | 0.50..0.60 | 9.6% | 19.2% | 3.4% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 8.38 | 7.50..8.76 | 7.5% | 15.1% | 4.6% | moderate |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 43.95 | 42.56..45.88 | 3.8% | 7.6% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 43.95 | 42.56..45.88 | 3.8% | 7.6% | 1.6% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.05 | 1.03..1.08 | 2.3% | 4.7% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 5.34 | 5.25..5.57 | 3.0% | 6.0% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 5.34 | 5.25..5.57 | 3.0% | 6.0% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.08 | 0.08..0.08 | 3.2% | 6.3% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.08 | 0.08..0.08 | 3.2% | 6.3% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.00 | 25.0% | 50.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.03 | 0.02..0.03 | 10.0% | 20.0% | 4.0% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.03 | 0.02..0.03 | 10.0% | 20.0% | 4.0% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.16 | 0.16..0.17 | 2.8% | 5.5% | 2.5% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.92 | 0.91..1.00 | 4.8% | 9.6% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.92 | 0.91..1.00 | 4.8% | 9.6% | 0.3% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.03 | 0.03..0.03 | 1.9% | 3.8% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.14 | 0.13..0.14 | 1.5% | 3.0% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.14 | 0.13..0.14 | 1.5% | 3.0% | 0.7% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 1.77 | 1.70..1.82 | 3.6% | 7.2% | 2.8% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 10.06 | 9.89..10.42 | 2.7% | 5.3% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 10.06 | 9.89..10.42 | 2.7% | 5.3% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.27 | 0.26..0.27 | 1.9% | 3.8% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 1.31 | 1.23..1.52 | 11.0% | 22.0% | 5.7% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 1.31 | 1.23..1.52 | 11.0% | 22.0% | 5.7% | moderate |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.08 | 0.08..0.14 | 33.3% | 66.7% | 1.2% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.02 | 0.02..0.07 | 104.3% | 208.7% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.25 | 0.24..0.26 | 2.4% | 4.9% | 1.2% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.06 | 0.06..0.06 | 2.5% | 4.9% | 1.6% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.24 | 0.24..0.25 | 2.7% | 5.4% | 0.8% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.06 | 0.06..0.06 | 2.5% | 5.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.37 | 0.37..0.39 | 2.6% | 5.1% | 0.5% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.06 | 0.06..0.06 | 1.7% | 3.3% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.78 | 0.77..0.81 | 2.3% | 4.6% | 0.4% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.22 | 0.22..0.23 | 1.8% | 3.7% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.02 | 0.02..0.04 | 78.1% | 156.3% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.01..0.04 | 71.9% | 143.8% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.01 | 25.0% | 50.0% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.16 | 0.16..0.19 | 8.9% | 17.7% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.16 | 0.16..0.18 | 8.6% | 17.2% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.03..0.04 | 11.8% | 23.7% | 7.9% | moderate |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.79 | 1.78..1.82 | 1.3% | 2.5% | 1.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.53 | 1.53..1.55 | 0.8% | 1.6% | 0.5% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.27 | 0.26..0.28 | 4.3% | 8.7% | 1.5% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.29 | 19.59..20.58 | 2.4% | 4.9% | 1.4% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 16.04 | 15.48..16.41 | 2.9% | 5.8% | 0.7% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 2.63 | 2.59..2.69 | 1.8% | 3.6% | 1.2% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / Large payload (~650KB) / resqlite selectBytes() | 0.24 | 0.23..0.27 | 8.4% | 16.9% | 3.4% | moderate |
| Select → JSON Bytes / Large payload (~650KB) / resqlite selectBytes... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.00 | 0.00..0.02 | 950.0% | 1900.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.01 | 0.01..0.01 | 60.0% | 120.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 20.0% | 40.0% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.31 | 0.31..0.38 | 10.7% | 21.5% | 1.0% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.05 | 0.05..0.06 | 7.8% | 15.7% | 0.0% | stable |
| Select → Maps / 10000 rows / resqlite select() | 3.32 | 3.26..3.49 | 3.5% | 7.0% | 1.7% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.51 | 0.50..0.53 | 2.4% | 4.7% | 0.6% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.18 | 0.16..0.25 | 26.1% | 52.2% | 9.4% | noisy |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.18 | 0.16..0.25 | 26.1% | 52.2% | 9.4% | noisy |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.48 | 0.47..0.51 | 3.7% | 7.3% | 0.8% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.48 | 0.47..0.51 | 3.7% | 7.3% | 0.8% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03..0.06 | 71.2% | 142.3% | 3.8% | moderate |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03..0.06 | 71.2% | 142.3% | 3.8% | moderate |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.04..0.05 | 11.0% | 22.0% | 2.4% | stable |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.04..0.05 | 11.0% | 22.0% | 2.4% | stable |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows x 32K... | 2.64 | 2.26..2.73 | 8.8% | 17.6% | 3.4% | moderate |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows x 32K... | 2.64 | 2.26..2.73 | 8.8% | 17.6% | 3.4% | moderate |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged streams, 6... | 2.50 | 2.37..2.67 | 6.1% | 12.2% | 3.6% | moderate |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged streams, 6... | 2.50 | 2.37..2.67 | 6.1% | 12.2% | 3.6% | moderate |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 1.49 | 1.46..2.00 | 17.9% | 35.9% | 1.8% | stable |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 1.49 | 1.46..2.00 | 17.9% | 35.9% | 1.8% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.22 | 2.97..3.35 | 5.8% | 11.7% | 2.9% | stable |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.22 | 2.97..3.35 | 5.8% | 11.7% | 2.9% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.65 | 1.57..2.45 | 26.9% | 53.9% | 2.4% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.65 | 1.57..2.45 | 26.9% | 53.9% | 2.4% | stable |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.03 | 5.76..6.47 | 5.9% | 11.8% | 2.7% | stable |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.03 | 5.76..6.47 | 5.9% | 11.8% | 2.7% | stable |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.18 | 0.16..0.21 | 13.7% | 27.3% | 3.3% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.18 | 0.16..0.21 | 13.7% | 27.3% | 3.3% | moderate |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.05 | 0.05..0.05 | 2.0% | 4.0% | 0.0% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.05 | 0.05..0.05 | 2.0% | 4.0% | 0.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.40 | 0.39..0.42 | 3.2% | 6.3% | 0.5% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.40 | 0.39..0.42 | 3.2% | 6.3% | 0.5% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.70 | 3.65..4.02 | 5.0% | 9.9% | 1.4% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.70 | 3.65..4.02 | 5.0% | 9.9% | 1.4% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.48 | 0.37..0.58 | 21.7% | 43.4% | 18.8% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.48 | 0.37..0.58 | 21.7% | 43.4% | 18.8% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.06 | 0.06..0.07 | 7.8% | 15.6% | 1.6% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.06 | 0.06..0.07 | 7.8% | 15.6% | 1.6% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 4.83 | 4.37..4.97 | 6.2% | 12.4% | 2.1% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 4.83 | 4.37..4.97 | 6.2% | 12.4% | 2.1% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.41 | 0.39..0.41 | 2.3% | 4.6% | 0.5% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.41 | 0.39..0.41 | 2.3% | 4.6% | 0.5% | stable |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 0.82 | 0.80..0.90 | 6.1% | 12.2% | 1.1% | stable |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 0.82 | 0.80..0.90 | 6.1% | 12.2% | 1.1% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.04..0.05 | 7.4% | 14.9% | 4.3% | moderate |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.04..0.05 | 7.4% | 14.9% | 4.3% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.07 | 0.07..0.07 | 5.8% | 11.6% | 4.3% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.07 | 0.07..0.07 | 5.8% | 11.6% | 4.3% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.77 | 0.72..0.93 | 13.3% | 26.6% | 3.6% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.77 | 0.72..0.93 | 13.3% | 26.6% | 3.6% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.47 | 1.43..1.61 | 6.1% | 12.2% | 2.8% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.47 | 1.43..1.61 | 6.1% | 12.2% | 2.8% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.17 | 0.17..0.18 | 2.9% | 5.9% | 0.6% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.17 | 0.17..0.18 | 2.9% | 5.9% | 0.6% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.10 | 0.10..0.10 | 4.0% | 7.9% | 3.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.10 | 0.10..0.10 | 4.0% | 7.9% | 3.0% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 12.85 | 12.37..13.00 | 2.4% | 4.9% | 1.2% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 12.85 | 12.37..13.00 | 2.4% | 4.9% | 1.2% | stable |


## Comparison

Automatic comparison skipped because `2026-08-12T10-15-00Z-exp269-opaque-work.md` was not captured in a compatible environment:
- baseline sidecar is missing environment metadata

Use `--compare-to=benchmark/results/2026-08-12T10-15-00Z-exp269-opaque-work.md` to run an explicit reference comparison anyway.


