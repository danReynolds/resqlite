# resqlite Benchmark Results

Generated: 2026-06-21T07:23:45.370272

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `baseline-for-exp192-flip`
- Repeats: `1`
- Runtime: `dart-vm / Dart 3.11.5`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `HEAD @ bb9def2d371d (dirty)`
- Comparison baseline: `2026-06-21T07-21-12-exp192-two-digit-itoa-flip.md`
- Comparison mode: `explicit`
- Comparison baseline compatibility: `compatible`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.081 | 0.117 | 0.018 | 0.021 |
| sqlite3 select() | 0.125 | 0.292 | 0.125 | 0.292 |
| sqlite_async select() | 0.166 | 0.239 | 0.019 | 0.020 |
| drift select() | 0.127 | 0.220 | 0.006 | 0.012 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.058 | 0.158 | 0.007 | 0.009 |
| sqlite3 select() | 0.208 | 0.298 | 0.208 | 0.298 |
| sqlite_async select() | 0.233 | 0.354 | 0.012 | 0.020 |
| drift select() | 0.309 | 0.419 | 0.011 | 0.016 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.352 | 0.425 | 0.052 | 0.054 |
| sqlite3 select() | 1.243 | 1.347 | 1.243 | 1.347 |
| sqlite_async select() | 1.107 | 1.234 | 0.074 | 0.082 |
| drift select() | 1.647 | 1.775 | 0.076 | 0.086 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.280 | 9.195 | 0.513 | 0.657 |
| sqlite3 select() | 13.995 | 17.519 | 13.995 | 17.519 |
| sqlite_async select() | 12.587 | 13.489 | 0.737 | 1.818 |
| drift select() | 22.200 | 26.463 | 0.756 | 1.166 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row. The large-payload row isolates resqlite selectBytes because it guards the native bytes transfer policy without multiplying large JSON encoding work across every peer.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.120 | 0.188 | 0.092 | 0.137 |
| sqlite3 + jsonEncode | 0.050 | 0.077 | 0.050 | 0.077 |
| sqlite_async + jsonEncode | 0.106 | 0.142 | 0.028 | 0.034 |
| drift + jsonEncode | 0.099 | 0.166 | 0.026 | 0.041 |
| resqlite selectBytes() | 0.021 | 0.026 | 0.000 | 0.001 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.227 | 0.321 | 0.181 | 0.199 |
| sqlite3 + jsonEncode | 0.282 | 0.314 | 0.282 | 0.314 |
| sqlite_async + jsonEncode | 0.322 | 0.408 | 0.158 | 0.186 |
| drift + jsonEncode | 0.349 | 0.436 | 0.153 | 0.168 |
| resqlite selectBytes() | 0.053 | 0.062 | 0.000 | 0.001 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.823 | 3.853 | 1.507 | 2.362 |
| sqlite3 + jsonEncode | 2.551 | 4.802 | 2.551 | 4.802 |
| sqlite_async + jsonEncode | 2.602 | 4.260 | 1.493 | 2.310 |
| drift + jsonEncode | 3.078 | 4.986 | 1.474 | 2.070 |
| resqlite selectBytes() | 0.354 | 0.382 | 0.000 | 0.000 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.398 | 24.306 | 14.893 | 17.528 |
| sqlite3 + jsonEncode | 29.778 | 33.161 | 29.778 | 33.161 |
| sqlite_async + jsonEncode | 30.804 | 33.000 | 15.138 | 17.089 |
| drift + jsonEncode | 38.250 | 44.656 | 15.835 | 20.521 |
| resqlite selectBytes() | 3.545 | 5.213 | 0.001 | 0.007 |

### Large payload (~650KB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.292 | 0.332 | 0.000 | 0.001 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.151 | 0.292 | 0.083 | 0.219 |
| sqlite3 | 0.338 | 0.629 | 0.338 | 0.629 |
| sqlite_async | 0.402 | 0.455 | 0.035 | 0.040 |
| drift | 0.641 | 1.091 | 0.036 | 0.055 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.863 | 0.919 | 0.217 | 0.225 |
| sqlite3 | 3.314 | 3.689 | 3.314 | 3.689 |
| sqlite_async | 3.031 | 3.320 | 0.243 | 0.267 |
| drift | 4.743 | 7.012 | 0.242 | 0.253 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.515 | 0.564 | 0.064 | 0.072 |
| sqlite3 | 1.465 | 1.543 | 1.465 | 1.543 |
| sqlite_async | 1.415 | 1.639 | 0.086 | 0.096 |
| drift | 1.990 | 2.186 | 0.089 | 0.095 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.256 | 0.303 | 0.060 | 0.063 |
| sqlite3 | 1.010 | 1.414 | 1.010 | 1.414 |
| sqlite_async | 1.056 | 1.240 | 0.091 | 0.099 |
| drift | 1.503 | 1.819 | 0.087 | 0.094 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.261 | 0.278 | 0.060 | 0.065 |
| sqlite3 | 0.990 | 1.064 | 0.990 | 1.064 |
| sqlite_async | 1.000 | 1.082 | 0.086 | 0.093 |
| drift | 1.455 | 1.702 | 0.084 | 0.094 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.014 | 0.014 | 0.001 | 0.002 |
| sqlite3 | 0.022 | 0.027 | 0.022 | 0.027 |
| sqlite_async | 0.069 | 0.083 | 0.004 | 0.006 |
| drift | 0.063 | 0.101 | 0.004 | 0.009 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.028 | 0.032 | 0.003 | 0.003 |
| sqlite3 | 0.064 | 0.069 | 0.064 | 0.069 |
| sqlite_async | 0.107 | 0.126 | 0.006 | 0.007 |
| drift | 0.121 | 0.143 | 0.006 | 0.007 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.047 | 0.055 | 0.005 | 0.007 |
| sqlite3 | 0.119 | 0.133 | 0.119 | 0.133 |
| sqlite_async | 0.155 | 0.189 | 0.009 | 0.009 |
| drift | 0.197 | 0.247 | 0.009 | 0.013 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.178 | 0.194 | 0.026 | 0.029 |
| sqlite3 | 0.569 | 0.605 | 0.569 | 0.605 |
| sqlite_async | 0.568 | 0.663 | 0.038 | 0.045 |
| drift | 0.813 | 0.871 | 0.037 | 0.040 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.347 | 0.362 | 0.053 | 0.054 |
| sqlite3 | 1.120 | 1.167 | 1.120 | 1.167 |
| sqlite_async | 1.060 | 1.116 | 0.072 | 0.076 |
| drift | 1.578 | 1.736 | 0.072 | 0.077 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.786 | 1.296 | 0.111 | 0.130 |
| sqlite3 | 2.248 | 2.595 | 2.248 | 2.595 |
| sqlite_async | 2.132 | 2.849 | 0.144 | 0.153 |
| drift | 3.152 | 4.316 | 0.145 | 0.164 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.992 | 5.139 | 0.266 | 0.333 |
| sqlite3 | 5.683 | 6.989 | 5.683 | 6.989 |
| sqlite_async | 5.625 | 6.288 | 0.374 | 0.392 |
| drift | 8.511 | 8.824 | 0.364 | 0.382 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.237 | 8.442 | 0.529 | 0.771 |
| sqlite3 | 14.214 | 16.586 | 14.214 | 16.586 |
| sqlite_async | 12.697 | 17.772 | 0.738 | 0.791 |
| drift | 20.935 | 28.333 | 0.741 | 1.478 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 10.403 | 17.452 | 1.094 | 1.868 |
| sqlite3 | 30.778 | 39.973 | 30.778 | 39.973 |
| sqlite_async | 34.971 | 41.837 | 1.485 | 5.472 |
| drift | 47.056 | 61.927 | 1.506 | 5.507 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.035 | 0.040 | 0.035 | 0.040 |
| sqlite3 + jsonEncode | 0.036 | 0.038 | 0.036 | 0.038 |
| sqlite_async + jsonEncode | 0.074 | 0.102 | 0.074 | 0.102 |
| drift + jsonEncode | 0.070 | 0.083 | 0.070 | 0.083 |
| resqlite selectBytes() | 0.012 | 0.017 | 0.012 | 0.017 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.114 | 0.149 | 0.114 | 0.149 |
| sqlite3 + jsonEncode | 0.147 | 0.169 | 0.147 | 0.169 |
| sqlite_async + jsonEncode | 0.201 | 0.288 | 0.201 | 0.288 |
| drift + jsonEncode | 0.191 | 0.306 | 0.191 | 0.306 |
| resqlite selectBytes() | 0.027 | 0.031 | 0.027 | 0.031 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.193 | 0.227 | 0.193 | 0.227 |
| sqlite3 + jsonEncode | 0.273 | 0.290 | 0.273 | 0.290 |
| sqlite_async + jsonEncode | 0.310 | 0.365 | 0.310 | 0.365 |
| drift + jsonEncode | 0.332 | 0.343 | 0.332 | 0.343 |
| resqlite selectBytes() | 0.044 | 0.045 | 0.044 | 0.045 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.887 | 0.938 | 0.887 | 0.938 |
| sqlite3 + jsonEncode | 1.267 | 1.328 | 1.267 | 1.328 |
| sqlite_async + jsonEncode | 1.251 | 1.388 | 1.251 | 1.388 |
| drift + jsonEncode | 1.495 | 1.579 | 1.495 | 1.579 |
| resqlite selectBytes() | 0.178 | 0.184 | 0.178 | 0.184 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.733 | 1.804 | 1.733 | 1.804 |
| sqlite3 + jsonEncode | 2.522 | 2.786 | 2.522 | 2.786 |
| sqlite_async + jsonEncode | 2.485 | 2.738 | 2.485 | 2.738 |
| drift + jsonEncode | 2.983 | 3.332 | 2.983 | 3.332 |
| resqlite selectBytes() | 0.339 | 0.349 | 0.339 | 0.349 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.867 | 5.476 | 3.867 | 5.476 |
| sqlite3 + jsonEncode | 5.269 | 7.838 | 5.269 | 7.838 |
| sqlite_async + jsonEncode | 5.173 | 7.990 | 5.173 | 7.990 |
| drift + jsonEncode | 6.841 | 11.362 | 6.841 | 11.362 |
| resqlite selectBytes() | 0.719 | 0.810 | 0.719 | 0.810 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 11.782 | 15.503 | 11.782 | 15.503 |
| sqlite3 + jsonEncode | 15.353 | 17.804 | 15.353 | 17.804 |
| sqlite_async + jsonEncode | 14.225 | 18.648 | 14.225 | 18.648 |
| drift + jsonEncode | 17.487 | 21.426 | 17.487 | 21.426 |
| resqlite selectBytes() | 1.801 | 1.968 | 1.801 | 1.968 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.822 | 23.206 | 20.822 | 23.206 |
| sqlite3 + jsonEncode | 32.017 | 35.076 | 32.017 | 35.076 |
| sqlite_async + jsonEncode | 31.195 | 32.774 | 31.195 | 32.774 |
| drift + jsonEncode | 37.946 | 43.089 | 37.946 | 43.089 |
| resqlite selectBytes() | 3.550 | 3.730 | 3.550 | 3.730 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 43.374 | 46.426 | 43.374 | 46.426 |
| sqlite3 + jsonEncode | 66.275 | 71.559 | 66.275 | 71.559 |
| sqlite_async + jsonEncode | 68.522 | 76.056 | 68.522 | 76.056 |
| drift + jsonEncode | 81.767 | 100.248 | 81.767 | 100.248 |
| resqlite selectBytes() | 7.716 | 10.463 | 7.716 | 10.463 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.33 | 0.30 |
| sqlite_async | 1.00 | 1.22 | 1.00 |
| drift | 1.58 | 1.73 | 1.58 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.33 | 0.35 | 0.17 |
| sqlite_async | 1.55 | 1.75 | 0.78 |
| drift | 2.83 | 3.36 | 1.42 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.43 | 0.55 | 0.11 |
| sqlite_async | 2.55 | 3.29 | 0.64 |
| drift | 5.51 | 6.25 | 1.38 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.80 | 1.13 | 0.10 |
| sqlite_async | 5.27 | 7.55 | 0.66 |
| drift | 11.03 | 11.86 | 1.38 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 140851 |
| resqlite per query | 0.007 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 140851 | 131388..142009 | 3.8 | 2.9 |
| sqlite3 | 194900 | 194007..195304 | 0.3 | 1.0 |
| sqlite_async | 49500 | 48948..49677 | 0.7 | 2.5 |
| drift | 46730 | 45548..47311 | 1.9 | 4.9 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.858 | 15.563 | 14.858 | 15.563 |
| sqlite_async | 38.296 | 39.779 | 38.296 | 39.779 |
| drift | 55.093 | 56.941 | 55.093 | 56.941 |
| sqlite3 (no cache) | 24.894 | 25.170 | 24.894 | 25.170 |
| sqlite3 (cached stmt) | 24.569 | 25.100 | 24.569 | 25.100 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.626 | 3.509 | 1.626 | 3.509 |
| sqlite3 execute() | 0.950 | 2.944 | 0.950 | 2.944 |
| sqlite_async execute() | 3.268 | 4.923 | 3.268 | 4.923 |
| drift execute() | 3.677 | 6.046 | 3.677 | 6.046 |

### Concurrent Single Inserts (100 concurrent)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite concurrent execute() | 0.881 | 1.400 | 0.881 | 1.400 |
| sqlite3 concurrent execute() | 0.930 | 1.953 | 0.930 | 1.953 |
| sqlite_async concurrent execute() | 2.819 | 4.186 | 2.819 | 4.186 |
| drift concurrent execute() | 1.826 | 2.897 | 1.826 | 2.897 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.059 | 0.073 | 0.059 | 0.073 |
| sqlite3 executeBatch() | 0.057 | 0.058 | 0.057 | 0.058 |
| sqlite_async executeBatch() | 0.101 | 0.112 | 0.101 | 0.112 |
| drift executeBatch() | 0.118 | 0.148 | 0.118 | 0.148 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.484 | 0.682 | 0.484 | 0.682 |
| sqlite3 executeBatch() | 0.538 | 0.668 | 0.538 | 0.668 |
| sqlite_async executeBatch() | 0.644 | 0.864 | 0.644 | 0.864 |
| drift executeBatch() | 0.845 | 0.987 | 0.845 | 0.987 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 3.937 | 5.193 | 3.937 | 5.193 |
| sqlite3 executeBatch() | 4.430 | 5.465 | 4.430 | 5.465 |
| sqlite_async executeBatch() | 5.165 | 6.940 | 5.165 | 6.940 |
| drift executeBatch() | 6.368 | 7.686 | 6.368 | 7.686 |

### Wide Batch Insert (10000 rows x 20 params)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 13.681 | 22.564 | 13.681 | 22.564 |
| sqlite3 executeBatch() | 20.024 | 22.916 | 20.024 | 22.916 |
| sqlite_async executeBatch() | 25.857 | 29.435 | 25.857 | 29.435 |
| drift executeBatch() | 28.951 | 33.345 | 28.951 | 33.345 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.063 | 0.119 | 0.063 | 0.119 |
| sqlite_async writeTransaction() | 0.096 | 0.117 | 0.096 | 0.117 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.078 | 0.109 | 0.078 | 0.109 |
| resqlite tx.execute() loop | 0.518 | 0.624 | 0.518 | 0.624 |
| sqlite_async tx.execute() loop | 1.115 | 1.476 | 1.115 | 1.476 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.467 | 0.564 | 0.467 | 0.564 |
| resqlite tx.execute() loop | 4.921 | 6.040 | 4.921 | 6.040 |
| sqlite_async tx.execute() loop | 12.298 | 13.256 | 12.298 | 13.256 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.109 | 0.135 | 0.109 | 0.135 |
| sqlite_async tx.getAll() | 0.229 | 0.317 | 0.229 | 0.317 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.195 | 0.238 | 0.195 | 0.238 |
| sqlite_async tx.getAll() | 0.420 | 0.602 | 0.420 | 0.602 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 1.125 | 1.261 | 1.125 | 1.261 |
| resqlite nested transaction() depth=5 | 0.113 | 0.139 | 0.113 | 0.139 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.111 | 0.138 | 0.111 | 0.138 |
| sqlite_async watch() | 0.140 | 0.365 | 0.140 | 0.365 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.105 | 0.162 | 0.105 | 0.162 |
| sqlite_async | 0.094 | 0.197 | 0.094 | 0.197 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.229 | 0.362 | 0.229 | 0.362 |
| sqlite_async | 0.914 | 1.738 | 0.914 | 1.738 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.690 | 4.013 | 2.690 | 4.013 |

### Long-Payload Unchanged Fanout (8 streams, 64 rows x 32KB TEXT + 32KB BLOB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.353 | 7.327 | 3.353 | 7.327 |

### Long-Text 32KB Unchanged Fanout (8 unchanged streams, 64 rows x 32KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.528 | 4.626 | 3.528 | 4.626 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.307 | 0.519 | 0.307 | 0.519 |
| sqlite_async | 0.367 | 0.563 | 0.367 | 0.563 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.722 | 2.722 | 2.722 | 2.722 |
| sqlite_async | 11.737 | 11.737 | 11.737 | 11.737 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.805 | 5.952 | 3.805 | 5.952 |
| sqlite_async | 6.530 | 11.177 | 6.530 | 11.177 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.643 | 0.848 | 0.643 | 0.848 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 7.285 | 9.736 | 7.285 | 9.736 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. For resqlite, this emission metric can reflect writer-side column-level invalidation, experiment 075's native result-hash short-circuit, or both. Use A11c (Many-Streams Writer Throughput) when the question is specifically writer-side dispatch elision.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 93.0 | 0.000 |
| sqlite_async | 4074 | 1268.1 | 1.107 |
| drift | 5000 | 1077.1 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 75.9 | 0.000 |
| sqlite_async | 3681 | 1087.8 | 1.107 |
| drift | 5000 | 1117.1 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 224.45 | 232.21 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 444.62 | 445.41 | 0.00 | 0.00 | 1122 | 3 |
| drift stream() | 556.79 | 562.15 | 0.00 | 0.01 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.022 | 0.051 | 0.000 | 0.000 |
| sqlite3 | 0.032 | 0.043 | 0.032 | 0.043 |
| sqlite_async | 0.055 | 0.077 | 0.000 | 0.000 |
| drift | 0.057 | 0.084 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.016 | 0.032 | 0.000 | 0.000 |
| sqlite3 | 0.019 | 0.026 | 0.019 | 0.026 |
| sqlite_async | 0.039 | 0.051 | 0.000 | 0.000 |
| drift | 0.041 | 0.060 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.025 | 0.035 | 0.000 | 0.000 |
| sqlite3 | 0.032 | 0.036 | 0.032 | 0.036 |
| sqlite_async | 0.059 | 0.071 | 0.000 | 0.000 |
| drift | 0.056 | 0.064 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.009 | 0.017 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.022 | 0.027 | 0.000 | 0.000 |
| drift | 0.021 | 0.027 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.042 | 0.052 | 0.004 | 0.004 |
| sqlite3 | 0.071 | 0.086 | 0.071 | 0.086 |
| sqlite_async | 0.083 | 0.091 | 0.001 | 0.001 |
| drift | 0.093 | 0.099 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 109.184 | 110.244 | 0.000 | 0.000 | 0 |
| sqlite_async | 223.090 | 224.243 | 0.000 | 0.000 | 42 |
| drift | 234.910 | 235.114 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 462.20 | 462.20 | 0.00 | 0.00 | 12.86 | 449.47 | 2 |
| sqlite_async | 490.15 | 490.15 | 0.00 | 0.00 | 23.96 | 466.35 | 1183 |
| drift | 1767.97 | 1767.97 | 0.13 | 0.13 | 16.96 | 1751.40 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 3.00 | 12.64 | 0.00..10.92 | ±5.46 |
| sqlite3 select() | 1.67 | 9.83 | 1.17..7.56 | ±3.20 |
| sqlite_async select() | 1.00 | 2.00 | 0.41..1.50 | ±0.55 |
| drift select() | 6.70 | 59.88 | 0.00..11.89 | ±5.95 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 20.02 | 0.00..1.50 | ±0.75 |
| resqlite + jsonEncode | 5.53 | 93.38 | 0.00..21.44 | ±10.72 |
| sqlite3 + jsonEncode | 7.06 | 73.70 | 0.00..51.25 | ±25.63 |
| sqlite_async + jsonEncode | 0.00 | 27.22 | 0.00..15.13 | ±7.56 |
| drift + jsonEncode | 0.86 | 16.02 | 0.00..4.88 | ±2.44 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.02 | 4.59 | 0.00..1.03 | ±0.52 |
| sqlite3 executeBatch() | 0.00 | 0.00 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 5.09 | 0.00..0.03 | ±0.02 |
| drift batch() | 0.00 | 2.02 | 0.00..0.02 | ±0.01 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.13 | 0.06..0.06 | ±0.00 |
| sqlite_async watch() | 0.00 | 0.50 | 0.00..0.50 | ±0.25 |

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

Previous: `2026-06-21T07-21-12-exp192-two-digit-itoa-flip.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |
|---|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.02 | 0.03 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.02 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.30 | +0.00 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.30 | +0.00 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.31 | 0.33 | +0.02 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.15 | 0.17 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+13%) |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.38 | 0.43 | +0.05 | ±10% / ±0.04 ms | 0.0% | single run | 🔴 Regression (+13%) |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.09 | 0.11 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+22%) |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.71 | 0.80 | +0.09 | ±10% / ±0.08 ms | 0.0% | single run | 🔴 Regression (+13%) |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.09 | 0.10 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 108.79 | 109.18 | +0.39 | ±10% / ±10.92 ms | 0.0% | single run | ⚪ Neutral |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 239.10 | 462.20 | +223.10 | ±10% / ±46.22 ms | 0.0% | single run | 🔴 Regression (+93%) |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 224.92 | 224.45 | -0.47 | ±10% / ±22.49 ms | 0.0% | single run | ⚪ Neutral |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.25 | 14.86 | +0.60 | ±10% / ±1.49 ms | 0.0% | single run | ⚪ Neutral |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.25 | 14.86 | +0.60 | ±10% / ±1.49 ms | 0.0% | single run | ⚪ Neutral |
| Point Query Throughput / resqlite qps | 147710.00 | 140851.00 | -6859.00 | ±10% / ±14771.00 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.05 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.19 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.19 | 0.19 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.05 | 0.04 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.05 | 0.04 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.35 | 0.35 | +0.00 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.78 | 1.73 | -0.04 | ±10% / ±0.18 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 1.78 | 1.73 | -0.04 | ±10% / ±0.18 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.34 | -0.01 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.35 | 0.34 | -0.01 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 4.18 | 4.24 | +0.06 | ±10% / ±0.42 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 20.50 | 20.82 | +0.32 | ±10% / ±2.08 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 20.50 | 20.82 | +0.32 | ±10% / ±2.08 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.53 | 0.53 | -0.00 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.74 | 3.55 | -0.19 | ±10% / ±0.37 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 3.74 | 3.55 | -0.19 | ±10% / ±0.37 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.75 | 0.79 | +0.04 | ±10% / ±0.08 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.93 | 3.87 | -0.06 | ±10% / ±0.39 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 3.93 | 3.87 | -0.06 | ±10% / ±0.39 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.69 | 0.72 | +0.03 | ±10% / ±0.07 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 0.69 | 0.72 | +0.03 | ±10% / ±0.07 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 10.37 | 10.40 | +0.04 | ±10% / ±1.04 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 43.45 | 43.37 | -0.08 | ±10% / ±4.35 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 43.45 | 43.37 | -0.08 | ±10% / ±4.35 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.06 | 1.09 | +0.04 | ±10% / ±0.11 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 7.37 | 7.72 | +0.34 | ±10% / ±0.77 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 7.37 | 7.72 | +0.34 | ±10% / ±0.77 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.18 | 0.18 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.90 | 0.89 | -0.01 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 0.90 | 0.89 | -0.01 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.19 | 0.18 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.19 | 0.18 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.10 | 1.99 | -0.11 | ±10% / ±0.21 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.02 | 11.78 | +1.76 | ±10% / ±1.18 ms | 0.0% | single run | 🔴 Regression (+18%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 10.02 | 11.78 | +1.76 | ±10% / ±1.18 ms | 0.0% | single run | 🔴 Regression (+18%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.27 | 0.27 | -0.01 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.86 | 1.80 | -0.06 | ±10% / ±0.19 ms | 0.0% | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 1.86 | 1.80 | -0.06 | ±10% / ±0.19 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.09 | 0.15 | +0.06 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+70%) |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.01 | 0.08 | +0.07 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+493%) |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.26 | 0.26 | +0.00 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.26 | 0.26 | -0.00 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.06 | 0.06 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.51 | 0.52 | +0.01 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.87 | 0.86 | -0.01 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.22 | 0.22 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.11 | 0.12 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.08 | 0.09 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.24 | 0.23 | -0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.18 | 0.18 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.83 | 1.82 | -0.01 | ±10% / ±0.18 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 1.50 | 1.51 | +0.00 | ±10% / ±0.15 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.37 | 0.35 | -0.02 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.66 | 20.40 | -0.26 | ±10% / ±2.07 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 15.01 | 14.89 | -0.12 | ±10% / ±1.50 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 3.68 | 3.54 | -0.13 | ±10% / ±0.37 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / Large payload (~650KB) / resqlite s... | 0.29 | 0.29 | +0.00 | ±10% / ±0.03 ms | 0.0% | single run | ⚪ Neutral |
| Select → JSON Bytes / Large payload (~650KB) / resqlite s... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 10 rows / resqlite select() | 0.08 | 0.08 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 10 rows / resqlite select() [main] | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 100 rows / resqlite select() | 0.06 | 0.06 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 1000 rows / resqlite select() | 0.37 | 0.35 | -0.02 | ±10% / ±0.04 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.05 | 0.05 | -0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 10000 rows / resqlite select() | 4.14 | 4.28 | +0.14 | ±10% / ±0.43 ms | 0.0% | single run | ⚪ Neutral |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.53 | 0.51 | -0.02 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Fan-out (10 streams) / resqlite | 0.28 | 0.31 | +0.03 | ±10% / ±0.03 ms | 0.0% | single run | 🔴 Regression (+12%) |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.28 | 0.31 | +0.03 | ±10% / ±0.03 ms | 0.0% | single run | 🔴 Regression (+12%) |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.57 | 0.64 | +0.08 | ±10% / ±0.06 ms | 0.0% | single run | 🔴 Regression (+13%) |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.57 | 0.64 | +0.08 | ±10% / ±0.06 ms | 0.0% | single run | 🔴 Regression (+13%) |
| Streaming / Initial Emission / resqlite stream() | 0.06 | 0.11 | +0.05 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+73%) |
| Streaming / Initial Emission / resqlite stream() [main] | 0.06 | 0.11 | +0.05 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+73%) |
| Streaming / Invalidation Latency / resqlite | 0.06 | 0.10 | +0.04 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+75%) |
| Streaming / Invalidation Latency / resqlite [main] | 0.06 | 0.10 | +0.04 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+75%) |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 ... | 2.73 | 3.35 | +0.62 | ±10% / ±0.34 ms | 0.0% | single run | 🔴 Regression (+23%) |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 ... | 2.73 | 3.35 | +0.62 | ±10% / ±0.34 ms | 0.0% | single run | 🔴 Regression (+23%) |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged ... | 2.92 | 3.53 | +0.60 | ±10% / ±0.35 ms | 0.0% | single run | 🔴 Regression (+21%) |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged ... | 2.92 | 3.53 | +0.60 | ±10% / ±0.35 ms | 0.0% | single run | 🔴 Regression (+21%) |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 1.87 | 2.69 | +0.82 | ±10% / ±0.27 ms | 0.0% | single run | 🔴 Regression (+44%) |
| Streaming / Long-Text Unchanged Fanout (8 unchanged strea... | 1.87 | 2.69 | +0.82 | ±10% / ±0.27 ms | 0.0% | single run | 🔴 Regression (+44%) |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.38 | 3.81 | +0.42 | ±10% / ±0.38 ms | 0.0% | single run | 🔴 Regression (+12%) |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 3.38 | 3.81 | +0.42 | ±10% / ±0.38 ms | 0.0% | single run | 🔴 Regression (+12%) |
| Streaming / Stream Churn (100 cycles) / resqlite | 3.09 | 2.72 | -0.37 | ±10% / ±0.31 ms | 0.0% | single run | 🟢 Win (-12%) |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 3.09 | 2.72 | -0.37 | ±10% / ±0.31 ms | 0.0% | single run | 🟢 Win (-12%) |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.83 | 7.29 | +0.46 | ±10% / ±0.73 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 6.83 | 7.29 | +0.46 | ±10% / ±0.73 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.21 | 0.23 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.21 | 0.23 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.48 | 0.48 | -0.00 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.48 | 0.48 | -0.00 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.84 | 3.94 | +0.09 | ±10% / ±0.39 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 3.84 | 3.94 | +0.09 | ±10% / ±0.39 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.57 | 0.52 | -0.05 | ±10% / ±0.06 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.57 | 0.52 | -0.05 | ±10% / ±0.06 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.08 | 0.08 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.08 | 0.08 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 4.58 | 4.92 | +0.35 | ±10% / ±0.49 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 4.58 | 4.92 | +0.35 | ±10% / ±0.49 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.50 | 0.47 | -0.03 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.50 | 0.47 | -0.03 | ±10% / ±0.05 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Concurrent Single Inserts (100 concur... | 0.87 | 0.88 | +0.01 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Concurrent Single Inserts (100 concur... | 0.87 | 0.88 | +0.01 | ±10% / ±0.09 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Nested Transactions (savepoints) / re... | 0.08 | 0.11 | +0.03 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+40%) |
| Write Performance / Nested Transactions (savepoints) / re... | 0.08 | 0.11 | +0.03 | ±10% / ±0.02 ms | 0.0% | single run | 🔴 Regression (+40%) |
| Write Performance / Nested Transactions (savepoints) / re... | 0.77 | 1.13 | +0.35 | ±10% / ±0.11 ms | 0.0% | single run | 🔴 Regression (+46%) |
| Write Performance / Nested Transactions (savepoints) / re... | 0.77 | 1.13 | +0.35 | ±10% / ±0.11 ms | 0.0% | single run | 🔴 Regression (+46%) |
| Write Performance / Single Inserts (100 sequential) / res... | 1.49 | 1.63 | +0.13 | ±10% / ±0.16 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Single Inserts (100 sequential) / res... | 1.49 | 1.63 | +0.13 | ±10% / ±0.16 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.20 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.20 | +0.02 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.11 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.11 | +0.01 | ±10% / ±0.02 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 13.55 | 13.68 | +0.13 | ±10% / ±1.37 ms | 0.0% | single run | ⚪ Neutral |
| Write Performance / Wide Batch Insert (10000 rows x 20 pa... | 13.55 | 13.68 | +0.13 | ±10% / ±1.37 ms | 0.0% | single run | ⚪ Neutral |

**Summary:** 2 wins, 29 regressions, 138 neutral

Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, plus an absolute floor of `±0.02 ms`.
MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 0.52 | 0.02 | -0.50 MB | ±0.52 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.02 | 0.00 | -0.02 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 0.00 | 0.86 | +0.86 MB | ±2.44 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 0.00 | 5.53 | +5.53 MB | ±10.72 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 0.00 | +0.00 MB | ±0.75 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 7.48 | 7.06 | -0.42 MB | ±25.63 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±7.56 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 5.66 | 6.70 | +1.04 MB | ±5.95 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / resqlite select() | 0.58 | 3.00 | +2.42 MB | ±5.46 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite3 select() | 5.59 | 1.67 | -3.92 MB | ±3.20 MB | 🟢 Win (-3.92 MB) |
| Memory / Select 10k rows → Maps / sqlite_async select() | 0.97 | 1.00 | +0.03 MB | ±0.55 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.06 | 0.06 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 1 wins, 0 regressions, 14 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 4418 | 4074 | -344 | ±100 | 🟢 Fewer re-emits (-344) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 10 | 10 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 4205 | 3681 | -524 | ±100 | 🔴 Invalidation elided (-524) — writes not firing |

**Granularity summary:** 1 fewer-re-emit, 1 more-re-emit, 4 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


