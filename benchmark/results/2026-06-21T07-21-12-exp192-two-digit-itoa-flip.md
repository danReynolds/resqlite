# resqlite Benchmark Results

Generated: 2026-06-21T07:21:12.609558

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp192-two-digit-itoa-flip`
- Repeats: `1`
- Runtime: `dart-vm / Dart 3.11.5`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `exp-192-two-digit-itoa @ bb9def2d371d (dirty)`
- Comparison baseline: `none`
- Comparison mode: `none`
- Comparison baseline compatibility: `not applicable`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.081 | 0.103 | 0.018 | 0.023 |
| sqlite3 select() | 0.140 | 0.322 | 0.140 | 0.322 |
| sqlite_async select() | 0.193 | 0.271 | 0.020 | 0.024 |
| drift select() | 0.137 | 0.270 | 0.007 | 0.014 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.061 | 0.116 | 0.007 | 0.010 |
| sqlite3 select() | 0.214 | 0.281 | 0.214 | 0.281 |
| sqlite_async select() | 0.226 | 0.296 | 0.011 | 0.015 |
| drift select() | 0.312 | 0.467 | 0.012 | 0.014 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.368 | 0.473 | 0.054 | 0.065 |
| sqlite3 select() | 1.216 | 1.530 | 1.216 | 1.530 |
| sqlite_async select() | 1.120 | 1.192 | 0.074 | 0.090 |
| drift select() | 1.620 | 1.879 | 0.075 | 0.084 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.140 | 10.295 | 0.528 | 0.933 |
| sqlite3 select() | 14.311 | 17.093 | 14.311 | 17.093 |
| sqlite_async select() | 12.866 | 17.701 | 0.755 | 1.897 |
| drift select() | 20.716 | 27.298 | 0.736 | 1.237 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row. The large-payload row isolates resqlite selectBytes because it guards the native bytes transfer policy without multiplying large JSON encoding work across every peer.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.114 | 0.224 | 0.084 | 0.186 |
| sqlite3 + jsonEncode | 0.051 | 0.084 | 0.051 | 0.084 |
| sqlite_async + jsonEncode | 0.114 | 0.261 | 0.029 | 0.054 |
| drift + jsonEncode | 0.108 | 0.189 | 0.028 | 0.046 |
| resqlite selectBytes() | 0.019 | 0.026 | 0.000 | 0.001 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.238 | 0.288 | 0.182 | 0.214 |
| sqlite3 + jsonEncode | 0.284 | 0.316 | 0.284 | 0.316 |
| sqlite_async + jsonEncode | 0.346 | 0.394 | 0.167 | 0.202 |
| drift + jsonEncode | 0.367 | 0.395 | 0.163 | 0.171 |
| resqlite selectBytes() | 0.053 | 0.057 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.835 | 1.930 | 1.504 | 1.576 |
| sqlite3 + jsonEncode | 2.708 | 2.934 | 2.708 | 2.934 |
| sqlite_async + jsonEncode | 2.741 | 2.936 | 1.569 | 1.743 |
| drift + jsonEncode | 3.221 | 6.034 | 1.548 | 3.162 |
| resqlite selectBytes() | 0.373 | 0.399 | 0.000 | 0.001 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.660 | 23.617 | 15.011 | 17.340 |
| sqlite3 + jsonEncode | 29.397 | 32.364 | 29.397 | 32.364 |
| sqlite_async + jsonEncode | 30.774 | 32.971 | 15.111 | 16.514 |
| drift + jsonEncode | 38.648 | 42.312 | 15.343 | 19.896 |
| resqlite selectBytes() | 3.677 | 3.927 | 0.001 | 0.004 |

### Large payload (~650KB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.290 | 0.414 | 0.000 | 0.001 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.089 | 0.250 | 0.014 | 0.179 |
| sqlite3 | 0.340 | 0.541 | 0.340 | 0.541 |
| sqlite_async | 0.406 | 0.479 | 0.036 | 0.040 |
| drift | 0.615 | 0.990 | 0.036 | 0.042 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.874 | 0.937 | 0.222 | 0.247 |
| sqlite3 | 3.314 | 3.634 | 3.314 | 3.634 |
| sqlite_async | 2.986 | 3.302 | 0.248 | 0.260 |
| drift | 4.738 | 6.758 | 0.251 | 0.275 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.507 | 0.534 | 0.063 | 0.070 |
| sqlite3 | 1.471 | 2.274 | 1.471 | 2.274 |
| sqlite_async | 1.446 | 1.693 | 0.091 | 0.098 |
| drift | 1.968 | 2.203 | 0.091 | 0.099 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.260 | 0.291 | 0.061 | 0.065 |
| sqlite3 | 1.010 | 1.047 | 1.010 | 1.047 |
| sqlite_async | 1.009 | 1.142 | 0.091 | 0.100 |
| drift | 1.507 | 1.701 | 0.089 | 0.098 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.260 | 0.275 | 0.060 | 0.063 |
| sqlite3 | 0.981 | 1.027 | 0.981 | 1.027 |
| sqlite_async | 0.987 | 1.068 | 0.087 | 0.099 |
| drift | 1.478 | 1.645 | 0.088 | 0.099 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.014 | 0.018 | 0.002 | 0.003 |
| sqlite3 | 0.022 | 0.034 | 0.022 | 0.034 |
| sqlite_async | 0.063 | 0.079 | 0.004 | 0.005 |
| drift | 0.055 | 0.069 | 0.004 | 0.004 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.026 | 0.028 | 0.003 | 0.003 |
| sqlite3 | 0.066 | 0.078 | 0.066 | 0.078 |
| sqlite_async | 0.102 | 0.123 | 0.006 | 0.006 |
| drift | 0.117 | 0.124 | 0.006 | 0.006 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.044 | 0.047 | 0.005 | 0.006 |
| sqlite3 | 0.122 | 0.133 | 0.122 | 0.133 |
| sqlite_async | 0.164 | 0.196 | 0.010 | 0.011 |
| drift | 0.194 | 0.215 | 0.010 | 0.010 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.179 | 0.201 | 0.026 | 0.030 |
| sqlite3 | 0.570 | 0.635 | 0.570 | 0.635 |
| sqlite_async | 0.565 | 0.614 | 0.039 | 0.042 |
| drift | 0.804 | 0.880 | 0.039 | 0.041 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.347 | 0.367 | 0.052 | 0.054 |
| sqlite3 | 1.125 | 1.176 | 1.125 | 1.176 |
| sqlite_async | 1.067 | 1.127 | 0.075 | 0.081 |
| drift | 1.586 | 1.835 | 0.075 | 0.082 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.750 | 1.490 | 0.109 | 0.444 |
| sqlite3 | 2.248 | 2.628 | 2.248 | 2.628 |
| sqlite_async | 2.153 | 2.490 | 0.151 | 0.158 |
| drift | 3.160 | 4.000 | 0.150 | 0.167 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.103 | 4.477 | 0.273 | 0.342 |
| sqlite3 | 5.693 | 7.242 | 5.693 | 7.242 |
| sqlite_async | 5.427 | 7.307 | 0.379 | 0.408 |
| drift | 8.658 | 9.652 | 0.390 | 0.424 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.176 | 10.962 | 0.530 | 0.659 |
| sqlite3 | 14.089 | 16.316 | 14.089 | 16.316 |
| sqlite_async | 12.772 | 14.271 | 0.768 | 1.860 |
| drift | 20.996 | 29.334 | 0.782 | 1.132 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 10.365 | 16.195 | 1.058 | 1.155 |
| sqlite3 | 31.986 | 36.440 | 31.986 | 36.440 |
| sqlite_async | 34.388 | 41.635 | 1.521 | 5.969 |
| drift | 50.769 | 60.918 | 1.541 | 6.616 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.035 | 0.037 | 0.035 | 0.037 |
| sqlite3 + jsonEncode | 0.036 | 0.041 | 0.036 | 0.041 |
| sqlite_async + jsonEncode | 0.084 | 0.104 | 0.084 | 0.104 |
| drift + jsonEncode | 0.069 | 0.084 | 0.069 | 0.084 |
| resqlite selectBytes() | 0.012 | 0.016 | 0.012 | 0.016 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.110 | 0.171 | 0.110 | 0.171 |
| sqlite3 + jsonEncode | 0.142 | 0.171 | 0.142 | 0.171 |
| sqlite_async + jsonEncode | 0.172 | 0.182 | 0.172 | 0.182 |
| drift + jsonEncode | 0.186 | 0.201 | 0.186 | 0.201 |
| resqlite selectBytes() | 0.027 | 0.028 | 0.027 | 0.028 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.194 | 0.222 | 0.194 | 0.222 |
| sqlite3 + jsonEncode | 0.262 | 0.275 | 0.262 | 0.275 |
| sqlite_async + jsonEncode | 0.294 | 0.325 | 0.294 | 0.325 |
| drift + jsonEncode | 0.335 | 0.359 | 0.335 | 0.359 |
| resqlite selectBytes() | 0.050 | 0.055 | 0.050 | 0.055 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.897 | 0.975 | 0.897 | 0.975 |
| sqlite3 + jsonEncode | 1.299 | 1.376 | 1.299 | 1.376 |
| sqlite_async + jsonEncode | 1.275 | 1.373 | 1.275 | 1.373 |
| drift + jsonEncode | 1.541 | 1.684 | 1.541 | 1.684 |
| resqlite selectBytes() | 0.191 | 0.211 | 0.191 | 0.211 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.776 | 1.908 | 1.776 | 1.908 |
| sqlite3 + jsonEncode | 2.527 | 2.685 | 2.527 | 2.685 |
| sqlite_async + jsonEncode | 2.546 | 2.766 | 2.546 | 2.766 |
| drift + jsonEncode | 3.047 | 3.316 | 3.047 | 3.316 |
| resqlite selectBytes() | 0.346 | 0.372 | 0.346 | 0.372 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.926 | 5.539 | 3.926 | 5.539 |
| sqlite3 + jsonEncode | 5.340 | 7.833 | 5.340 | 7.833 |
| sqlite_async + jsonEncode | 5.344 | 8.332 | 5.344 | 8.332 |
| drift + jsonEncode | 6.550 | 8.952 | 6.550 | 8.952 |
| resqlite selectBytes() | 0.689 | 0.766 | 0.689 | 0.766 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 10.021 | 12.005 | 10.021 | 12.005 |
| sqlite3 + jsonEncode | 15.913 | 19.219 | 15.913 | 19.219 |
| sqlite_async + jsonEncode | 15.524 | 17.996 | 15.524 | 17.996 |
| drift + jsonEncode | 17.442 | 21.893 | 17.442 | 21.893 |
| resqlite selectBytes() | 1.861 | 2.041 | 1.861 | 2.041 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.498 | 22.195 | 20.498 | 22.195 |
| sqlite3 + jsonEncode | 28.952 | 33.436 | 28.952 | 33.436 |
| sqlite_async + jsonEncode | 30.586 | 32.739 | 30.586 | 32.739 |
| drift + jsonEncode | 37.852 | 41.231 | 37.852 | 41.231 |
| resqlite selectBytes() | 3.744 | 3.815 | 3.744 | 3.815 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 43.455 | 47.075 | 43.455 | 47.075 |
| sqlite3 + jsonEncode | 64.912 | 68.777 | 64.912 | 68.777 |
| sqlite_async + jsonEncode | 66.672 | 73.718 | 66.672 | 73.718 |
| drift + jsonEncode | 78.567 | 97.503 | 78.567 | 97.503 |
| resqlite selectBytes() | 7.374 | 7.931 | 7.374 | 7.931 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.30 | 0.34 | 0.30 |
| sqlite_async | 0.98 | 1.02 | 0.98 |
| drift | 1.53 | 1.63 | 1.53 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.31 | 0.34 | 0.15 |
| sqlite_async | 1.48 | 1.70 | 0.74 |
| drift | 2.78 | 3.27 | 1.39 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.38 | 0.65 | 0.09 |
| sqlite_async | 2.53 | 3.25 | 0.63 |
| drift | 5.47 | 6.29 | 1.37 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.71 | 0.99 | 0.09 |
| sqlite_async | 5.20 | 5.64 | 0.65 |
| drift | 10.65 | 11.26 | 1.33 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 147710 |
| resqlite per query | 0.007 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 147710 | 145688..149042 | 1.1 | 3.1 |
| sqlite3 | 200169 | 195745..200896 | 1.3 | 1.3 |
| sqlite_async | 51517 | 50741..51827 | 1.1 | 3.2 |
| drift | 47703 | 47624..47847 | 0.2 | 1.3 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.254 | 14.622 | 14.254 | 14.622 |
| sqlite_async | 37.115 | 38.000 | 37.115 | 38.000 |
| drift | 53.478 | 54.453 | 53.478 | 54.453 |
| sqlite3 (no cache) | 24.207 | 24.568 | 24.207 | 24.568 |
| sqlite3 (cached stmt) | 23.951 | 24.399 | 23.951 | 24.399 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.494 | 3.191 | 1.494 | 3.191 |
| sqlite3 execute() | 0.927 | 3.206 | 0.927 | 3.206 |
| sqlite_async execute() | 3.164 | 4.753 | 3.164 | 4.753 |
| drift execute() | 3.524 | 7.621 | 3.524 | 7.621 |

### Concurrent Single Inserts (100 concurrent)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite concurrent execute() | 0.873 | 2.299 | 0.873 | 2.299 |
| sqlite3 concurrent execute() | 0.937 | 4.501 | 0.937 | 4.501 |
| sqlite_async concurrent execute() | 2.798 | 6.315 | 2.798 | 6.315 |
| drift concurrent execute() | 1.796 | 4.496 | 1.796 | 4.496 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.057 | 0.059 | 0.057 | 0.059 |
| sqlite3 executeBatch() | 0.055 | 0.063 | 0.055 | 0.063 |
| sqlite_async executeBatch() | 0.100 | 0.109 | 0.100 | 0.109 |
| drift executeBatch() | 0.126 | 0.154 | 0.126 | 0.154 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.485 | 0.509 | 0.485 | 0.509 |
| sqlite3 executeBatch() | 0.495 | 0.521 | 0.495 | 0.521 |
| sqlite_async executeBatch() | 0.570 | 0.633 | 0.570 | 0.633 |
| drift executeBatch() | 0.727 | 0.926 | 0.727 | 0.926 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 3.843 | 5.169 | 3.843 | 5.169 |
| sqlite3 executeBatch() | 4.216 | 4.625 | 4.216 | 4.625 |
| sqlite_async executeBatch() | 5.288 | 6.038 | 5.288 | 6.038 |
| drift executeBatch() | 6.794 | 11.241 | 6.794 | 11.241 |

### Wide Batch Insert (10000 rows x 20 params)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 13.547 | 24.852 | 13.547 | 24.852 |
| sqlite3 executeBatch() | 19.399 | 26.827 | 19.399 | 26.827 |
| sqlite_async executeBatch() | 23.907 | 30.858 | 23.907 | 30.858 |
| drift executeBatch() | 27.170 | 34.233 | 27.170 | 34.233 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.060 | 0.080 | 0.060 | 0.080 |
| sqlite_async writeTransaction() | 0.094 | 0.112 | 0.094 | 0.112 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.077 | 0.085 | 0.077 | 0.085 |
| resqlite tx.execute() loop | 0.570 | 0.705 | 0.570 | 0.705 |
| sqlite_async tx.execute() loop | 0.996 | 1.146 | 0.996 | 1.146 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.501 | 0.547 | 0.501 | 0.547 |
| resqlite tx.execute() loop | 4.576 | 5.616 | 4.576 | 5.616 |
| sqlite_async tx.execute() loop | 9.702 | 10.536 | 9.702 | 10.536 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.101 | 0.112 | 0.101 | 0.112 |
| sqlite_async tx.getAll() | 0.203 | 0.217 | 0.203 | 0.217 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.180 | 0.191 | 0.180 | 0.191 |
| sqlite_async tx.getAll() | 0.356 | 0.395 | 0.356 | 0.395 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 0.773 | 1.008 | 0.773 | 1.008 |
| resqlite nested transaction() depth=5 | 0.081 | 0.101 | 0.081 | 0.101 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.064 | 0.073 | 0.064 | 0.073 |
| sqlite_async watch() | 0.132 | 0.226 | 0.132 | 0.226 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.060 | 0.092 | 0.060 | 0.092 |
| sqlite_async | 0.089 | 0.145 | 0.089 | 0.145 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.215 | 0.348 | 0.215 | 0.348 |
| sqlite_async | 0.721 | 1.432 | 0.721 | 1.432 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.872 | 2.548 | 1.872 | 2.548 |

### Long-Payload Unchanged Fanout (8 streams, 64 rows x 32KB TEXT + 32KB BLOB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.733 | 7.047 | 2.733 | 7.047 |

### Long-Text 32KB Unchanged Fanout (8 unchanged streams, 64 rows x 32KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.924 | 4.334 | 2.924 | 4.334 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.275 | 0.336 | 0.275 | 0.336 |
| sqlite_async | 0.366 | 0.530 | 0.366 | 0.530 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.088 | 3.088 | 3.088 | 3.088 |
| sqlite_async | 10.762 | 10.762 | 10.762 | 10.762 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.384 | 5.395 | 3.384 | 5.395 |
| sqlite_async | 6.046 | 11.400 | 6.046 | 11.400 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.568 | 0.725 | 0.568 | 0.725 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 6.827 | 9.171 | 6.827 | 9.171 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. For resqlite, this emission metric can reflect writer-side column-level invalidation, experiment 075's native result-hash short-circuit, or both. Use A11c (Many-Streams Writer Throughput) when the question is specifically writer-side dispatch elision.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 87.8 | 0.000 |
| sqlite_async | 4418 | 1226.2 | 1.051 |
| drift | 5000 | 1023.3 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 74.8 | 0.000 |
| sqlite_async | 4205 | 1172.1 | 1.051 |
| drift | 5000 | 1023.1 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 224.92 | 225.89 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 441.58 | 443.98 | 0.00 | 0.00 | 1112 | 3 |
| drift stream() | 555.42 | 555.48 | 0.01 | 0.01 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.020 | 0.043 | 0.000 | 0.000 |
| sqlite3 | 0.035 | 0.048 | 0.035 | 0.048 |
| sqlite_async | 0.054 | 0.075 | 0.000 | 0.000 |
| drift | 0.053 | 0.076 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.015 | 0.027 | 0.000 | 0.000 |
| sqlite3 | 0.020 | 0.029 | 0.020 | 0.029 |
| sqlite_async | 0.037 | 0.052 | 0.000 | 0.000 |
| drift | 0.039 | 0.054 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.024 | 0.033 | 0.000 | 0.000 |
| sqlite3 | 0.031 | 0.033 | 0.031 | 0.033 |
| sqlite_async | 0.056 | 0.067 | 0.000 | 0.000 |
| drift | 0.054 | 0.061 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.008 | 0.015 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.020 | 0.025 | 0.000 | 0.000 |
| drift | 0.020 | 0.025 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.040 | 0.043 | 0.004 | 0.004 |
| sqlite3 | 0.066 | 0.084 | 0.066 | 0.084 |
| sqlite_async | 0.081 | 0.091 | 0.001 | 0.001 |
| drift | 0.091 | 0.101 | 0.001 | 0.002 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 108.791 | 111.601 | 0.000 | 0.000 | 0 |
| sqlite_async | 218.987 | 220.139 | 0.000 | 0.000 | 41 |
| drift | 231.453 | 234.777 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 239.10 | 239.10 | 0.00 | 0.00 | 13.65 | 225.44 | 0 |
| sqlite_async | 488.01 | 488.01 | 0.01 | 0.01 | 26.09 | 461.91 | 1188 |
| drift | 1755.10 | 1755.10 | 0.09 | 0.09 | 14.63 | 1741.24 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 0.58 | 12.19 | 0.00..5.58 | ±2.79 |
| sqlite3 select() | 5.59 | 10.70 | 1.31..8.78 | ±3.73 |
| sqlite_async select() | 0.97 | 1.11 | 0.50..1.00 | ±0.25 |
| drift select() | 5.66 | 51.44 | 0.00..7.16 | ±3.58 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 8.02 | 0.00..0.00 | ±0.00 |
| resqlite + jsonEncode | 0.00 | 38.97 | 0.00..8.22 | ±4.11 |
| sqlite3 + jsonEncode | 7.48 | 77.92 | 2.39..59.66 | ±28.63 |
| sqlite_async + jsonEncode | 0.00 | 39.31 | 0.00..19.66 | ±9.83 |
| drift + jsonEncode | 0.00 | 13.56 | 0.00..4.53 | ±2.27 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.52 | 1.69 | 0.02..0.53 | ±0.26 |
| sqlite3 executeBatch() | 0.00 | 0.50 | 0.00..0.02 | ±0.01 |
| sqlite_async executeBatch() | 0.02 | 2.75 | 0.00..0.03 | ±0.02 |
| drift batch() | 0.00 | 2.16 | 0.00..0.06 | ±0.03 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.56 | 0.06..0.19 | ±0.06 |
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

## Comparison

Automatic comparison is disabled. Use `--compare-to=...` for an explicit baseline comparison.

