# resqlite Benchmark Results

Generated: 2026-06-16T06:19:03.478902

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp175-large-selectbytes-coverage`
- Repeats: `1`
- Runtime: `dart-vm / Dart 3.11.5`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `exp-175-large-selectbytes-coverage @ cd0cb27ef618 (dirty)`
- Comparison baseline: `none`
- Comparison mode: `none`
- Comparison baseline compatibility: `not applicable`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.078 | 0.113 | 0.018 | 0.050 |
| sqlite3 select() | 0.136 | 0.330 | 0.136 | 0.330 |
| sqlite_async select() | 0.170 | 0.268 | 0.019 | 0.021 |
| drift select() | 0.134 | 0.213 | 0.007 | 0.010 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.063 | 0.099 | 0.008 | 0.010 |
| sqlite3 select() | 0.190 | 0.302 | 0.190 | 0.302 |
| sqlite_async select() | 0.222 | 0.266 | 0.011 | 0.013 |
| drift select() | 0.305 | 0.380 | 0.011 | 0.014 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.355 | 0.439 | 0.053 | 0.059 |
| sqlite3 select() | 1.078 | 1.304 | 1.078 | 1.304 |
| sqlite_async select() | 1.083 | 1.169 | 0.073 | 0.078 |
| drift select() | 1.515 | 1.596 | 0.071 | 0.074 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.267 | 11.375 | 0.520 | 0.849 |
| sqlite3 select() | 13.195 | 16.144 | 13.195 | 16.144 |
| sqlite_async select() | 12.154 | 13.563 | 0.718 | 1.374 |
| drift select() | 19.784 | 24.754 | 0.717 | 1.126 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row. The large-payload row isolates resqlite selectBytes because it guards the native bytes transfer policy without multiplying large JSON encoding work across every peer.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.090 | 0.100 | 0.068 | 0.072 |
| sqlite3 + jsonEncode | 0.085 | 0.171 | 0.085 | 0.171 |
| sqlite_async + jsonEncode | 0.111 | 0.207 | 0.028 | 0.043 |
| drift + jsonEncode | 0.095 | 0.121 | 0.026 | 0.030 |
| resqlite selectBytes() | 0.018 | 0.024 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.209 | 0.248 | 0.163 | 0.204 |
| sqlite3 + jsonEncode | 0.262 | 0.314 | 0.262 | 0.314 |
| sqlite_async + jsonEncode | 0.306 | 0.343 | 0.154 | 0.163 |
| drift + jsonEncode | 0.335 | 0.345 | 0.152 | 0.158 |
| resqlite selectBytes() | 0.051 | 0.054 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.714 | 1.789 | 1.423 | 1.455 |
| sqlite3 + jsonEncode | 2.438 | 2.667 | 2.438 | 2.667 |
| sqlite_async + jsonEncode | 2.445 | 2.538 | 1.446 | 1.502 |
| drift + jsonEncode | 2.885 | 3.151 | 1.437 | 1.480 |
| resqlite selectBytes() | 0.361 | 0.372 | 0.000 | 0.000 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.493 | 22.024 | 14.489 | 17.032 |
| sqlite3 + jsonEncode | 27.714 | 31.316 | 27.714 | 31.316 |
| sqlite_async + jsonEncode | 29.893 | 31.755 | 14.826 | 16.420 |
| drift + jsonEncode | 35.895 | 40.865 | 15.061 | 19.938 |
| resqlite selectBytes() | 3.545 | 5.036 | 0.000 | 0.004 |

### Large payload (~650KB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.323 | 0.942 | 0.000 | 0.003 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.157 | 0.347 | 0.030 | 0.221 |
| sqlite3 | 0.332 | 0.616 | 0.332 | 0.616 |
| sqlite_async | 0.421 | 0.552 | 0.037 | 0.045 |
| drift | 0.630 | 0.993 | 0.036 | 0.051 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.882 | 0.940 | 0.219 | 0.232 |
| sqlite3 | 3.253 | 3.496 | 3.253 | 3.496 |
| sqlite_async | 2.973 | 3.577 | 0.238 | 0.257 |
| drift | 4.595 | 6.394 | 0.240 | 0.261 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.512 | 1.004 | 0.062 | 0.068 |
| sqlite3 | 1.408 | 1.445 | 1.408 | 1.445 |
| sqlite_async | 1.378 | 1.425 | 0.085 | 0.088 |
| drift | 1.888 | 2.126 | 0.085 | 0.091 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.256 | 0.261 | 0.060 | 0.063 |
| sqlite3 | 0.959 | 0.991 | 0.959 | 0.991 |
| sqlite_async | 0.942 | 0.987 | 0.084 | 0.087 |
| drift | 1.400 | 1.556 | 0.082 | 0.089 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.261 | 0.268 | 0.060 | 0.063 |
| sqlite3 | 0.938 | 0.956 | 0.938 | 0.956 |
| sqlite_async | 0.955 | 0.987 | 0.083 | 0.089 |
| drift | 1.390 | 1.496 | 0.083 | 0.087 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.013 | 0.014 | 0.001 | 0.002 |
| sqlite3 | 0.021 | 0.023 | 0.021 | 0.023 |
| sqlite_async | 0.066 | 0.113 | 0.004 | 0.007 |
| drift | 0.058 | 0.076 | 0.004 | 0.004 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.028 | 0.035 | 0.003 | 0.003 |
| sqlite3 | 0.064 | 0.093 | 0.064 | 0.093 |
| sqlite_async | 0.100 | 0.115 | 0.005 | 0.006 |
| drift | 0.115 | 0.119 | 0.005 | 0.006 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.045 | 0.046 | 0.005 | 0.006 |
| sqlite3 | 0.115 | 0.124 | 0.115 | 0.124 |
| sqlite_async | 0.151 | 0.161 | 0.009 | 0.009 |
| drift | 0.190 | 0.238 | 0.010 | 0.012 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.176 | 0.180 | 0.026 | 0.027 |
| sqlite3 | 0.542 | 0.561 | 0.542 | 0.561 |
| sqlite_async | 0.544 | 0.592 | 0.036 | 0.037 |
| drift | 0.763 | 0.789 | 0.036 | 0.038 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.348 | 0.354 | 0.052 | 0.055 |
| sqlite3 | 1.072 | 1.078 | 1.072 | 1.078 |
| sqlite_async | 1.037 | 1.051 | 0.071 | 0.073 |
| drift | 1.497 | 1.733 | 0.070 | 0.073 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.737 | 1.451 | 0.108 | 0.120 |
| sqlite3 | 2.138 | 2.538 | 2.138 | 2.538 |
| sqlite_async | 2.086 | 2.412 | 0.140 | 0.144 |
| drift | 2.991 | 3.462 | 0.140 | 0.145 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.936 | 4.718 | 0.262 | 0.304 |
| sqlite3 | 5.366 | 6.516 | 5.366 | 6.516 |
| sqlite_async | 5.353 | 6.081 | 0.350 | 0.355 |
| drift | 8.198 | 8.861 | 0.354 | 0.373 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.535 | 7.759 | 0.521 | 0.934 |
| sqlite3 | 12.962 | 15.480 | 12.962 | 15.480 |
| sqlite_async | 12.200 | 17.022 | 0.710 | 0.742 |
| drift | 19.820 | 25.859 | 0.707 | 1.516 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 11.020 | 13.820 | 1.035 | 2.226 |
| sqlite3 | 29.907 | 32.715 | 29.907 | 32.715 |
| sqlite_async | 37.184 | 38.376 | 1.434 | 1.559 |
| drift | 46.165 | 54.526 | 1.400 | 7.029 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.035 | 0.039 | 0.035 | 0.039 |
| sqlite3 + jsonEncode | 0.043 | 0.545 | 0.043 | 0.545 |
| sqlite_async + jsonEncode | 0.090 | 0.115 | 0.090 | 0.115 |
| drift + jsonEncode | 0.113 | 0.161 | 0.113 | 0.161 |
| resqlite selectBytes() | 0.012 | 0.013 | 0.012 | 0.013 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.115 | 0.133 | 0.115 | 0.133 |
| sqlite3 + jsonEncode | 0.144 | 0.251 | 0.144 | 0.251 |
| sqlite_async + jsonEncode | 0.168 | 0.203 | 0.168 | 0.203 |
| drift + jsonEncode | 0.185 | 0.200 | 0.185 | 0.200 |
| resqlite selectBytes() | 0.026 | 0.029 | 0.026 | 0.029 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.191 | 0.196 | 0.191 | 0.196 |
| sqlite3 + jsonEncode | 0.259 | 0.301 | 0.259 | 0.301 |
| sqlite_async + jsonEncode | 0.302 | 0.312 | 0.302 | 0.312 |
| drift + jsonEncode | 0.358 | 0.440 | 0.358 | 0.440 |
| resqlite selectBytes() | 0.045 | 0.051 | 0.045 | 0.051 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.911 | 0.988 | 0.911 | 0.988 |
| sqlite3 + jsonEncode | 1.245 | 1.373 | 1.245 | 1.373 |
| sqlite_async + jsonEncode | 1.327 | 1.436 | 1.327 | 1.436 |
| drift + jsonEncode | 1.520 | 1.638 | 1.520 | 1.638 |
| resqlite selectBytes() | 0.180 | 0.185 | 0.180 | 0.185 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.741 | 1.869 | 1.741 | 1.869 |
| sqlite3 + jsonEncode | 2.458 | 2.539 | 2.458 | 2.539 |
| sqlite_async + jsonEncode | 2.490 | 3.964 | 2.490 | 3.964 |
| drift + jsonEncode | 2.878 | 4.864 | 2.878 | 4.864 |
| resqlite selectBytes() | 0.356 | 0.361 | 0.356 | 0.361 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.655 | 5.434 | 3.655 | 5.434 |
| sqlite3 + jsonEncode | 5.045 | 7.259 | 5.045 | 7.259 |
| sqlite_async + jsonEncode | 5.150 | 7.833 | 5.150 | 7.833 |
| drift + jsonEncode | 5.922 | 8.442 | 5.922 | 8.442 |
| resqlite selectBytes() | 0.697 | 0.716 | 0.697 | 0.716 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 10.046 | 12.532 | 10.046 | 12.532 |
| sqlite3 + jsonEncode | 14.014 | 15.379 | 14.014 | 15.379 |
| sqlite_async + jsonEncode | 13.517 | 16.528 | 13.517 | 16.528 |
| drift + jsonEncode | 17.658 | 19.953 | 17.658 | 19.953 |
| resqlite selectBytes() | 1.718 | 1.741 | 1.718 | 1.741 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.411 | 21.587 | 20.411 | 21.587 |
| sqlite3 + jsonEncode | 29.800 | 30.980 | 29.800 | 30.980 |
| sqlite_async + jsonEncode | 31.890 | 32.840 | 31.890 | 32.840 |
| drift + jsonEncode | 35.174 | 41.021 | 35.174 | 41.021 |
| resqlite selectBytes() | 3.562 | 5.160 | 3.562 | 5.160 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 41.603 | 45.125 | 41.603 | 45.125 |
| sqlite3 + jsonEncode | 61.866 | 64.586 | 61.866 | 64.586 |
| sqlite_async + jsonEncode | 65.126 | 68.980 | 65.126 | 68.980 |
| drift + jsonEncode | 75.331 | 91.498 | 75.331 | 91.498 |
| resqlite selectBytes() | 7.242 | 9.590 | 7.242 | 9.590 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.33 | 0.44 | 0.33 |
| sqlite_async | 0.99 | 1.04 | 0.99 |
| drift | 1.53 | 1.69 | 1.53 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.31 | 0.32 | 0.15 |
| sqlite_async | 1.53 | 1.76 | 0.77 |
| drift | 2.71 | 3.15 | 1.35 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.38 | 0.61 | 0.10 |
| sqlite_async | 2.52 | 3.12 | 0.63 |
| drift | 5.06 | 6.18 | 1.27 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.76 | 1.04 | 0.09 |
| sqlite_async | 5.13 | 5.35 | 0.64 |
| drift | 9.98 | 10.60 | 1.25 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 157226 |
| resqlite per query | 0.006 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 157226 | 147647..158298 | 3.4 | 3.8 |
| sqlite3 | 201899 | 200705..202715 | 0.5 | 1.5 |
| sqlite_async | 53022 | 52655..53251 | 0.6 | 1.6 |
| drift | 49319 | 48992..49669 | 0.7 | 2.4 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 14.327 | 14.718 | 14.327 | 14.718 |
| sqlite_async | 35.757 | 35.996 | 35.757 | 35.996 |
| drift | 50.810 | 51.785 | 50.810 | 51.785 |
| sqlite3 (no cache) | 22.483 | 22.576 | 22.483 | 22.576 |
| sqlite3 (cached stmt) | 22.187 | 22.501 | 22.187 | 22.501 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.381 | 1.807 | 1.381 | 1.807 |
| sqlite3 execute() | 0.871 | 1.526 | 0.871 | 1.526 |
| sqlite_async execute() | 2.822 | 3.334 | 2.822 | 3.334 |
| drift execute() | 3.286 | 3.759 | 3.286 | 3.759 |

### Concurrent Single Inserts (100 concurrent)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite concurrent execute() | 0.978 | 1.352 | 0.978 | 1.352 |
| sqlite3 concurrent execute() | 0.882 | 1.562 | 0.882 | 1.562 |
| sqlite_async concurrent execute() | 2.601 | 3.396 | 2.601 | 3.396 |
| drift concurrent execute() | 1.686 | 2.305 | 1.686 | 2.305 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.052 | 0.054 | 0.052 | 0.054 |
| sqlite3 executeBatch() | 0.052 | 0.068 | 0.052 | 0.068 |
| sqlite_async executeBatch() | 0.122 | 0.162 | 0.122 | 0.162 |
| drift executeBatch() | 0.124 | 0.212 | 0.124 | 0.212 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.407 | 0.442 | 0.407 | 0.442 |
| sqlite3 executeBatch() | 0.439 | 0.449 | 0.439 | 0.449 |
| sqlite_async executeBatch() | 0.528 | 0.582 | 0.528 | 0.582 |
| drift executeBatch() | 0.696 | 0.790 | 0.696 | 0.790 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 3.894 | 4.607 | 3.894 | 4.607 |
| sqlite3 executeBatch() | 4.067 | 4.266 | 4.067 | 4.266 |
| sqlite_async executeBatch() | 4.628 | 5.650 | 4.628 | 5.650 |
| drift executeBatch() | 5.847 | 7.949 | 5.847 | 7.949 |

### Wide Batch Insert (10000 rows x 20 params)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 13.119 | 22.852 | 13.119 | 22.852 |
| sqlite3 executeBatch() | 19.004 | 21.304 | 19.004 | 21.304 |
| sqlite_async executeBatch() | 23.032 | 27.740 | 23.032 | 27.740 |
| drift executeBatch() | 26.914 | 32.115 | 26.914 | 32.115 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.046 | 0.050 | 0.046 | 0.050 |
| sqlite_async writeTransaction() | 0.077 | 0.085 | 0.077 | 0.085 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.064 | 0.100 | 0.064 | 0.100 |
| resqlite tx.execute() loop | 0.430 | 0.624 | 0.430 | 0.624 |
| sqlite_async tx.execute() loop | 0.979 | 1.098 | 0.979 | 1.098 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.397 | 0.421 | 0.397 | 0.421 |
| resqlite tx.execute() loop | 4.169 | 5.246 | 4.169 | 5.246 |
| sqlite_async tx.execute() loop | 8.995 | 9.465 | 8.995 | 9.465 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.102 | 0.109 | 0.102 | 0.109 |
| sqlite_async tx.getAll() | 0.193 | 0.214 | 0.193 | 0.214 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.182 | 0.187 | 0.182 | 0.187 |
| sqlite_async tx.getAll() | 0.345 | 0.372 | 0.345 | 0.372 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 0.788 | 0.965 | 0.788 | 0.965 |
| resqlite nested transaction() depth=5 | 0.077 | 0.081 | 0.077 | 0.081 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.067 | 0.077 | 0.067 | 0.077 |
| sqlite_async watch() | 0.130 | 0.249 | 0.130 | 0.249 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.046 | 0.072 | 0.046 | 0.072 |
| sqlite_async | 0.069 | 0.130 | 0.069 | 0.130 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.229 | 0.304 | 0.229 | 0.304 |
| sqlite_async | 0.655 | 1.708 | 0.655 | 1.708 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.880 | 3.809 | 1.880 | 3.809 |

### Long-Payload Unchanged Fanout (8 streams, 64 rows x 32KB TEXT + 32KB BLOB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.542 | 5.236 | 3.542 | 5.236 |

### Long-Text 32KB Unchanged Fanout (8 unchanged streams, 64 rows x 32KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.834 | 5.201 | 3.834 | 5.201 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.238 | 0.319 | 0.238 | 0.319 |
| sqlite_async | 0.319 | 0.381 | 0.319 | 0.381 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.514 | 2.514 | 2.514 | 2.514 |
| sqlite_async | 10.245 | 10.245 | 10.245 | 10.245 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.409 | 3.957 | 3.409 | 3.957 |
| sqlite_async | 5.807 | 6.924 | 5.807 | 6.924 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.552 | 0.692 | 0.552 | 0.692 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 6.521 | 9.251 | 6.521 | 9.251 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. For resqlite, this emission metric can reflect writer-side column-level invalidation, experiment 075's native result-hash short-circuit, or both. Use A11c (Many-Streams Writer Throughput) when the question is specifically writer-side dispatch elision.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 76.5 | 0.000 |
| sqlite_async | 3979 | 1108.1 | 1.012 |
| drift | 5000 | 991.2 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 78.8 | 0.000 |
| sqlite_async | 3930 | 1093.4 | 1.012 |
| drift | 5000 | 986.9 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 224.18 | 230.43 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 441.86 | 442.32 | 0.00 | 0.00 | 1103 | 3 |
| drift stream() | 548.49 | 552.54 | 0.00 | 0.00 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.018 | 0.027 | 0.000 | 0.000 |
| sqlite3 | 0.018 | 0.022 | 0.018 | 0.022 |
| sqlite_async | 0.034 | 0.040 | 0.000 | 0.000 |
| drift | 0.037 | 0.043 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.013 | 0.019 | 0.000 | 0.000 |
| sqlite3 | 0.011 | 0.013 | 0.011 | 0.013 |
| sqlite_async | 0.027 | 0.031 | 0.000 | 0.000 |
| drift | 0.029 | 0.035 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.023 | 0.031 | 0.000 | 0.000 |
| sqlite3 | 0.030 | 0.031 | 0.030 | 0.031 |
| sqlite_async | 0.055 | 0.064 | 0.000 | 0.000 |
| drift | 0.052 | 0.055 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.008 | 0.014 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.019 | 0.025 | 0.000 | 0.000 |
| drift | 0.019 | 0.023 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.046 | 0.053 | 0.004 | 0.004 |
| sqlite3 | 0.067 | 0.081 | 0.067 | 0.081 |
| sqlite_async | 0.085 | 0.089 | 0.001 | 0.001 |
| drift | 0.089 | 0.092 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 110.982 | 112.976 | 0.000 | 0.000 | 0 |
| sqlite_async | 220.301 | 220.508 | 0.000 | 0.000 | 35 |
| drift | 233.664 | 234.352 | 0.000 | 0.002 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 238.43 | 238.43 | 0.00 | 0.00 | 12.70 | 225.77 | 0 |
| sqlite_async | 484.92 | 484.92 | 0.00 | 0.00 | 24.84 | 460.07 | 1182 |
| drift | 1661.29 | 1661.29 | 0.01 | 0.01 | 14.84 | 1647.68 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 1.45 | 11.59 | 0.00..6.00 | ±3.00 |
| sqlite3 select() | 5.77 | 10.23 | 2.45..7.73 | ±2.64 |
| sqlite_async select() | 0.50 | 1.00 | 0.50..0.50 | ±0.00 |
| drift select() | 2.27 | 51.66 | 0.00..11.83 | ±5.91 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 14.00 | 0.00..1.00 | ±0.50 |
| resqlite + jsonEncode | 2.50 | 22.00 | 0.00..10.72 | ±5.36 |
| sqlite3 + jsonEncode | 0.00 | 23.69 | 0.00..23.69 | ±11.84 |
| sqlite_async + jsonEncode | 0.00 | 27.69 | 0.00..0.00 | ±0.00 |
| drift + jsonEncode | 0.00 | 29.91 | 0.00..10.86 | ±5.43 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.39 | 33.53 | 0.00..1.45 | ±0.73 |
| sqlite3 executeBatch() | 0.00 | 1.83 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.00 | 4.38 | 0.00..0.00 | ±0.00 |
| drift batch() | 0.00 | 4.50 | 0.00..2.50 | ±1.25 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.00 | 0.13 | 0.00..0.06 | ±0.03 |
| sqlite_async watch() | 0.00 | 1.00 | 0.00..0.02 | ±0.01 |

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

## Comparison

Automatic comparison is disabled. Use `--compare-to=...` for an explicit baseline comparison.

