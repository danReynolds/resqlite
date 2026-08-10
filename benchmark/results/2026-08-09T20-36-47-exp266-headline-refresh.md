# resqlite Benchmark Results

Generated: 2026-08-09T20:43:05.911368

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp266-headline-refresh`
- Repeats: `5`
- Runtime: `dart-vm / Dart 3.12.2`
- OS: `macos Version 26.2 (Build 25C56)`
- Git: `HEAD @ fc65d3c5e2c9`
- Comparison baseline: `none`
- Comparison mode: `none`
- Comparison baseline compatibility: `not applicable`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.011 | 0.012 | 0.000 | 0.000 |
| sqlite3 select() | 0.016 | 0.017 | 0.016 | 0.017 |
| sqlite_async select() | 0.031 | 0.032 | 0.001 | 0.002 |
| drift select() | 0.037 | 0.038 | 0.001 | 0.001 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.043 | 0.044 | 0.005 | 0.006 |
| sqlite3 select() | 0.123 | 0.123 | 0.123 | 0.123 |
| sqlite_async select() | 0.133 | 0.166 | 0.010 | 0.013 |
| drift select() | 0.191 | 0.203 | 0.010 | 0.011 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.320 | 0.331 | 0.053 | 0.056 |
| sqlite3 select() | 1.230 | 1.317 | 1.230 | 1.317 |
| sqlite_async select() | 1.162 | 1.245 | 0.101 | 0.110 |
| drift select() | 1.633 | 1.865 | 0.096 | 0.105 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 3.413 | 8.530 | 0.512 | 0.960 |
| sqlite3 select() | 14.015 | 16.475 | 14.015 | 16.475 |
| sqlite_async select() | 13.023 | 16.354 | 0.976 | 1.631 |
| drift select() | 23.577 | 31.042 | 1.016 | 2.394 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row. The large-payload row isolates resqlite selectBytes because it guards the native bytes transfer policy without multiplying large JSON encoding work across every peer.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.027 | 0.028 | 0.017 | 0.017 |
| sqlite3 + jsonEncode | 0.032 | 0.034 | 0.032 | 0.034 |
| sqlite_async + jsonEncode | 0.048 | 0.053 | 0.017 | 0.018 |
| drift + jsonEncode | 0.053 | 0.062 | 0.017 | 0.018 |
| resqlite selectBytes() | 0.011 | 0.021 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.204 | 0.208 | 0.168 | 0.170 |
| sqlite3 + jsonEncode | 0.276 | 0.292 | 0.276 | 0.292 |
| sqlite_async + jsonEncode | 0.288 | 0.308 | 0.164 | 0.179 |
| drift + jsonEncode | 0.368 | 0.563 | 0.173 | 0.323 |
| resqlite selectBytes() | 0.041 | 0.044 | 0.000 | 0.000 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.878 | 3.787 | 1.599 | 2.492 |
| sqlite3 + jsonEncode | 2.593 | 3.132 | 2.593 | 3.132 |
| sqlite_async + jsonEncode | 2.513 | 4.904 | 1.549 | 3.111 |
| drift + jsonEncode | 2.995 | 3.503 | 1.526 | 2.027 |
| resqlite selectBytes() | 0.260 | 0.269 | 0.000 | 0.000 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 20.412 | 25.193 | 15.592 | 17.623 |
| sqlite3 + jsonEncode | 31.334 | 35.797 | 31.334 | 35.797 |
| sqlite_async + jsonEncode | 34.617 | 40.798 | 17.251 | 19.701 |
| drift + jsonEncode | 45.362 | 53.886 | 17.385 | 22.098 |
| resqlite selectBytes() | 2.621 | 2.678 | 0.000 | 0.000 |

### Large payload (~650KB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.273 | 0.286 | 0.000 | 0.000 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.086 | 0.095 | 0.023 | 0.029 |
| sqlite3 | 0.334 | 0.348 | 0.334 | 0.348 |
| sqlite_async | 0.369 | 0.448 | 0.033 | 0.042 |
| drift | 0.569 | 0.587 | 0.033 | 0.035 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.785 | 0.805 | 0.222 | 0.227 |
| sqlite3 | 3.321 | 3.716 | 3.321 | 3.716 |
| sqlite_async | 2.892 | 3.199 | 0.238 | 0.245 |
| drift | 4.659 | 5.851 | 0.241 | 0.263 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.373 | 0.381 | 0.060 | 0.064 |
| sqlite3 | 1.457 | 1.479 | 1.457 | 1.479 |
| sqlite_async | 1.359 | 1.410 | 0.086 | 0.091 |
| drift | 1.892 | 2.157 | 0.085 | 0.087 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.239 | 0.244 | 0.060 | 0.061 |
| sqlite3 | 1.049 | 1.664 | 1.049 | 1.664 |
| sqlite_async | 0.979 | 1.022 | 0.088 | 0.091 |
| drift | 1.525 | 1.668 | 0.089 | 0.092 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.254 | 0.286 | 0.062 | 0.071 |
| sqlite3 | 1.014 | 1.030 | 1.014 | 1.030 |
| sqlite_async | 0.983 | 1.039 | 0.089 | 0.091 |
| drift | 1.473 | 1.517 | 0.088 | 0.090 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.014 | 0.022 | 0.000 | 0.000 |
| sqlite3 | 0.017 | 0.023 | 0.017 | 0.023 |
| sqlite_async | 0.033 | 0.035 | 0.001 | 0.001 |
| drift | 0.039 | 0.063 | 0.001 | 0.001 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.027 | 0.029 | 0.003 | 0.003 |
| sqlite3 | 0.062 | 0.063 | 0.062 | 0.063 |
| sqlite_async | 0.075 | 0.078 | 0.004 | 0.004 |
| drift | 0.102 | 0.107 | 0.004 | 0.004 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.039 | 0.040 | 0.005 | 0.006 |
| sqlite3 | 0.125 | 0.128 | 0.125 | 0.128 |
| sqlite_async | 0.136 | 0.150 | 0.008 | 0.009 |
| drift | 0.192 | 0.199 | 0.008 | 0.010 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.170 | 0.176 | 0.028 | 0.028 |
| sqlite3 | 0.617 | 1.063 | 0.617 | 1.063 |
| sqlite_async | 0.578 | 0.909 | 0.041 | 0.045 |
| drift | 0.842 | 1.169 | 0.039 | 0.050 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.319 | 0.322 | 0.054 | 0.055 |
| sqlite3 | 1.179 | 1.250 | 1.179 | 1.250 |
| sqlite_async | 1.132 | 1.223 | 0.079 | 0.085 |
| drift | 1.618 | 1.877 | 0.075 | 0.083 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.635 | 0.665 | 0.108 | 0.110 |
| sqlite3 | 2.321 | 2.762 | 2.321 | 2.762 |
| sqlite_async | 2.197 | 2.422 | 0.153 | 0.161 |
| drift | 3.120 | 3.457 | 0.146 | 0.148 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.737 | 4.938 | 0.259 | 0.374 |
| sqlite3 | 5.702 | 6.874 | 5.702 | 6.874 |
| sqlite_async | 5.263 | 6.108 | 0.364 | 0.504 |
| drift | 8.124 | 8.272 | 0.359 | 0.367 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.726 | 9.462 | 0.554 | 2.291 |
| sqlite3 | 14.825 | 17.989 | 14.825 | 17.989 |
| sqlite_async | 11.878 | 12.899 | 0.756 | 0.769 |
| drift | 18.173 | 28.417 | 0.749 | 1.121 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 8.843 | 14.268 | 1.038 | 1.988 |
| sqlite3 | 37.671 | 45.237 | 37.671 | 45.237 |
| sqlite_async | 36.467 | 40.959 | 1.587 | 2.084 |
| drift | 51.509 | 66.729 | 1.565 | 3.336 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.027 | 0.028 | 0.027 | 0.028 |
| sqlite3 + jsonEncode | 0.033 | 0.101 | 0.033 | 0.101 |
| sqlite_async + jsonEncode | 0.054 | 0.076 | 0.054 | 0.076 |
| drift + jsonEncode | 0.059 | 0.066 | 0.059 | 0.066 |
| resqlite selectBytes() | 0.012 | 0.040 | 0.012 | 0.040 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.105 | 0.108 | 0.105 | 0.108 |
| sqlite3 + jsonEncode | 0.143 | 0.146 | 0.143 | 0.146 |
| sqlite_async + jsonEncode | 0.158 | 0.177 | 0.158 | 0.177 |
| drift + jsonEncode | 0.182 | 0.218 | 0.182 | 0.218 |
| resqlite selectBytes() | 0.025 | 0.029 | 0.025 | 0.029 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.201 | 0.203 | 0.201 | 0.203 |
| sqlite3 + jsonEncode | 0.279 | 0.316 | 0.279 | 0.316 |
| sqlite_async + jsonEncode | 0.285 | 0.290 | 0.285 | 0.290 |
| drift + jsonEncode | 0.337 | 0.345 | 0.337 | 0.345 |
| resqlite selectBytes() | 0.034 | 0.035 | 0.034 | 0.035 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.978 | 1.582 | 0.978 | 1.582 |
| sqlite3 + jsonEncode | 1.358 | 3.288 | 1.358 | 3.288 |
| sqlite_async + jsonEncode | 1.315 | 1.571 | 1.315 | 1.571 |
| drift + jsonEncode | 1.615 | 1.692 | 1.615 | 1.692 |
| resqlite selectBytes() | 0.135 | 0.151 | 0.135 | 0.151 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.910 | 4.267 | 1.910 | 4.267 |
| sqlite3 + jsonEncode | 2.710 | 4.937 | 2.710 | 4.937 |
| sqlite_async + jsonEncode | 2.549 | 3.182 | 2.549 | 3.182 |
| drift + jsonEncode | 3.019 | 3.824 | 3.019 | 3.824 |
| resqlite selectBytes() | 0.279 | 0.301 | 0.279 | 0.301 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 3.836 | 6.475 | 3.836 | 6.475 |
| sqlite3 + jsonEncode | 5.347 | 9.047 | 5.347 | 9.047 |
| sqlite_async + jsonEncode | 5.221 | 8.338 | 5.221 | 8.338 |
| drift + jsonEncode | 6.705 | 11.312 | 6.705 | 11.312 |
| resqlite selectBytes() | 0.522 | 0.540 | 0.522 | 0.540 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 10.364 | 14.588 | 10.364 | 14.588 |
| sqlite3 + jsonEncode | 15.321 | 18.504 | 15.321 | 18.504 |
| sqlite_async + jsonEncode | 14.685 | 19.387 | 14.685 | 19.387 |
| drift + jsonEncode | 17.868 | 24.835 | 17.868 | 24.835 |
| resqlite selectBytes() | 1.330 | 1.482 | 1.330 | 1.482 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 23.687 | 25.909 | 23.687 | 25.909 |
| sqlite3 + jsonEncode | 32.481 | 36.145 | 32.481 | 36.145 |
| sqlite_async + jsonEncode | 33.311 | 38.233 | 33.311 | 38.233 |
| drift + jsonEncode | 40.992 | 48.582 | 40.992 | 48.582 |
| resqlite selectBytes() | 2.779 | 2.905 | 2.779 | 2.905 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 44.324 | 46.397 | 44.324 | 46.397 |
| sqlite3 + jsonEncode | 64.438 | 71.564 | 64.438 | 71.564 |
| sqlite_async + jsonEncode | 66.708 | 76.780 | 66.708 | 76.780 |
| drift + jsonEncode | 83.902 | 96.605 | 83.902 | 96.605 |
| resqlite selectBytes() | 5.485 | 6.717 | 5.485 | 6.717 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.27 | 0.37 | 0.27 |
| sqlite_async | 1.05 | 1.09 | 1.05 |
| drift | 1.53 | 1.80 | 1.53 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.29 | 0.32 | 0.14 |
| sqlite_async | 1.53 | 1.80 | 0.76 |
| drift | 2.91 | 3.26 | 1.46 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.34 | 0.56 | 0.09 |
| sqlite_async | 2.50 | 3.19 | 0.62 |
| drift | 5.54 | 6.27 | 1.39 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.63 | 0.97 | 0.08 |
| sqlite_async | 5.08 | 5.77 | 0.64 |
| drift | 10.44 | 11.26 | 1.31 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each sample runs the same adaptive number of 500-query batches, chosen after warmup so that 15 samples target about 1000 ms of total measurement per library after warmup. 95% CI and MDE values derive from per-sample QPS via percentile bootstrap (deterministic, seed=202440478).

Adaptive schedule: `15 samples, target 1000 ms total` (batch count chosen per library after warmup).

| Metric | Value |
|---|---:|
| resqlite qps | 164941 |
| resqlite per query | 0.006 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 164941 | 155222..172151 | 5.1 | 16.0 |
| sqlite3 | 188984 | 187995..195753 | 2.1 | 4.6 |
| sqlite_async | 49979 | 49532..50030 | 0.5 | 4.6 |
| drift | 48735 | 48045..48793 | 0.8 | 1.9 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 13.581 | 13.934 | 13.581 | 13.934 |
| sqlite_async | 37.227 | 38.024 | 37.227 | 38.024 |
| drift | 53.517 | 54.922 | 53.517 | 54.922 |
| sqlite3 (no cache) | 23.792 | 24.266 | 23.792 | 24.266 |
| sqlite3 (cached stmt) | 24.085 | 24.322 | 24.085 | 24.322 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.577 | 2.134 | 1.577 | 2.134 |
| sqlite3 execute() | 0.934 | 1.615 | 0.934 | 1.615 |
| sqlite_async execute() | 2.703 | 3.269 | 2.703 | 3.269 |
| drift execute() | 2.648 | 3.493 | 2.648 | 3.493 |

### Concurrent Single Inserts (100 concurrent)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite concurrent execute() | 0.819 | 1.190 | 0.819 | 1.190 |
| sqlite3 concurrent execute() | 0.858 | 1.522 | 0.858 | 1.522 |
| sqlite_async concurrent execute() | 2.517 | 3.159 | 2.517 | 3.159 |
| drift concurrent execute() | 1.623 | 2.364 | 1.623 | 2.364 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.050 | 0.052 | 0.050 | 0.052 |
| sqlite3 executeBatch() | 0.047 | 0.048 | 0.047 | 0.048 |
| sqlite_async executeBatch() | 0.092 | 0.095 | 0.092 | 0.095 |
| drift executeBatch() | 0.111 | 0.116 | 0.111 | 0.116 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.393 | 0.398 | 0.393 | 0.398 |
| sqlite3 executeBatch() | 0.438 | 0.443 | 0.438 | 0.443 |
| sqlite_async executeBatch() | 0.493 | 0.501 | 0.493 | 0.501 |
| drift executeBatch() | 0.631 | 0.645 | 0.631 | 0.645 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 3.654 | 4.271 | 3.654 | 4.271 |
| sqlite3 executeBatch() | 4.030 | 4.135 | 4.030 | 4.135 |
| sqlite_async executeBatch() | 4.650 | 5.074 | 4.650 | 5.074 |
| drift executeBatch() | 6.285 | 9.015 | 6.285 | 9.015 |

### Wide Batch Insert (10000 rows x 20 params)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 13.013 | 25.068 | 13.013 | 25.068 |
| sqlite3 executeBatch() | 18.562 | 20.898 | 18.562 | 20.898 |
| sqlite_async executeBatch() | 23.193 | 29.486 | 23.193 | 29.486 |
| drift executeBatch() | 25.898 | 30.274 | 25.898 | 30.274 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.049 | 0.067 | 0.049 | 0.067 |
| sqlite_async writeTransaction() | 0.084 | 0.110 | 0.084 | 0.110 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.067 | 0.092 | 0.067 | 0.092 |
| resqlite tx.execute() loop | 0.524 | 0.615 | 0.524 | 0.615 |
| sqlite_async tx.execute() loop | 1.218 | 1.581 | 1.218 | 1.581 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.419 | 0.445 | 0.419 | 0.445 |
| resqlite tx.execute() loop | 5.201 | 5.794 | 5.201 | 5.794 |
| sqlite_async tx.execute() loop | 9.401 | 10.735 | 9.401 | 10.735 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.098 | 0.101 | 0.098 | 0.101 |
| sqlite_async tx.getAll() | 0.201 | 0.206 | 0.201 | 0.206 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.169 | 0.177 | 0.169 | 0.177 |
| sqlite_async tx.getAll() | 0.343 | 0.352 | 0.343 | 0.352 |

### Nested Transactions (savepoints)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite nested transaction() x50 | 0.775 | 0.806 | 0.775 | 0.806 |
| resqlite nested transaction() depth=5 | 0.065 | 0.071 | 0.065 | 0.071 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.030 | 0.051 | 0.030 | 0.051 |
| sqlite_async watch() | 0.116 | 0.129 | 0.116 | 0.129 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.049 | 0.073 | 0.049 | 0.073 |
| sqlite_async | 0.067 | 0.147 | 0.067 | 0.147 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.188 | 0.331 | 0.188 | 0.331 |
| sqlite_async | 0.530 | 0.919 | 0.530 | 0.919 |

### Long-Text Unchanged Fanout (8 unchanged streams, 256 rows x 4KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.310 | 2.504 | 2.310 | 2.504 |

### Long-Payload Unchanged Fanout (8 streams, 64 rows x 32KB TEXT + 32KB BLOB)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.432 | 3.430 | 2.432 | 3.430 |

### Long-Text 32KB Unchanged Fanout (8 unchanged streams, 64 rows x 32KB TEXT)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.608 | 4.317 | 2.608 | 4.317 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.175 | 0.204 | 0.175 | 0.204 |
| sqlite_async | 0.236 | 0.296 | 0.236 | 0.296 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.775 | 1.775 | 1.775 | 1.775 |
| sqlite_async | 9.335 | 9.335 | 9.335 | 9.335 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.177 | 3.934 | 3.177 | 3.934 |
| sqlite_async | 5.608 | 6.297 | 5.608 | 6.297 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.480 | 0.698 | 0.480 | 0.698 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 6.267 | 7.225 | 6.267 | 7.225 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. For resqlite, this emission metric can reflect writer-side column-level invalidation, experiment 075's native result-hash short-circuit, or both. Use A11c (Many-Streams Writer Throughput) when the question is specifically writer-side dispatch elision.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 67.8 | 0.000 |
| sqlite_async | 4193 | 1192.2 | 1.166 |
| drift | 5000 | 1035.5 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 70.3 | 0.000 |
| sqlite_async | 3595 | 1147.5 | 1.166 |
| drift | 5000 | 1030.6 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 217.93 | 226.54 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 431.16 | 431.22 | 0.00 | 0.00 | 1112 | 3 |
| drift stream() | 535.51 | 554.61 | 0.01 | 0.01 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.018 | 0.029 | 0.000 | 0.000 |
| sqlite3 | 0.018 | 0.023 | 0.018 | 0.023 |
| sqlite_async | 0.049 | 0.073 | 0.000 | 0.000 |
| drift | 0.053 | 0.084 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.014 | 0.020 | 0.000 | 0.000 |
| sqlite3 | 0.012 | 0.014 | 0.012 | 0.014 |
| sqlite_async | 0.040 | 0.056 | 0.000 | 0.000 |
| drift | 0.044 | 0.075 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.018 | 0.028 | 0.000 | 0.000 |
| sqlite3 | 0.031 | 0.033 | 0.031 | 0.033 |
| sqlite_async | 0.066 | 0.085 | 0.000 | 0.000 |
| drift | 0.064 | 0.087 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.006 | 0.012 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.006 | 0.005 | 0.006 |
| sqlite_async | 0.027 | 0.036 | 0.000 | 0.000 |
| drift | 0.026 | 0.045 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.043 | 0.061 | 0.001 | 0.001 |
| sqlite3 | 0.070 | 0.082 | 0.070 | 0.082 |
| sqlite_async | 0.084 | 0.092 | 0.001 | 0.001 |
| drift | 0.090 | 0.094 | 0.001 | 0.001 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 108.672 | 108.839 | 0.000 | 0.000 | 0 |
| sqlite_async | 216.647 | 216.945 | 0.000 | 0.000 | 38 |
| drift | 218.820 | 223.790 | 0.000 | 0.000 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 241.01 | 241.01 | 0.00 | 0.00 | 13.42 | 227.58 | 0 |
| drift | 1711.03 | 1711.03 | 0.03 | 0.03 | 14.26 | 1696.77 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## SQLite Diagnostics

resqlite-only internal SQLite counters captured via `Database.diagnostics()` after representative workloads. Values reflect the writer plus idle readers in this connection pool; they are not process-global SQLite totals.

### Warm read working set (20000 rows + 2000 point lookups)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | JSON buf (KiB) | Readers busy |
|---|---|---|---|---|---|---|---|
| resqlite | 3178.6 | 3164.0 | 4.2 | 10.4 | 2048.0 | 64.0 | 0 |

### Statement cache footprint (48 distinct SELECT texts)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | JSON buf (KiB) | Readers busy |
|---|---|---|---|---|---|---|---|
| resqlite | 3238.7 | 3164.0 | 4.2 | 70.5 | 2048.0 | 64.0 | 0 |

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
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite | 0.02 | 0.02..0.02 | 5.6% | 11.1% | 0.0% | stable |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01..0.01 | 16.7% | 33.3% | 0.0% | stable |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite | 0.02 | 0.02..0.02 | 5.6% | 11.1% | 0.0% | stable |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite | 0.01 | 0.01..0.02 | 7.1% | 14.3% | 0.0% | stable |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite | 0.26 | 0.26..0.27 | 1.9% | 3.8% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 1× concurrency / resqlite ... | 0.26 | 0.26..0.27 | 1.9% | 3.8% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite | 0.29 | 0.27..0.29 | 3.4% | 6.9% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 2× concurrency / resqlite ... | 0.14 | 0.14..0.15 | 3.6% | 7.1% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite | 0.33 | 0.32..0.34 | 3.0% | 6.1% | 3.0% | moderate |
| Concurrent Reads (1000 rows per query) / 4× concurrency / resqlite ... | 0.08 | 0.08..0.09 | 6.2% | 12.5% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite | 0.61 | 0.60..0.63 | 2.5% | 4.9% | 1.6% | stable |
| Concurrent Reads (1000 rows per query) / 8× concurrency / resqlite ... | 0.08 | 0.07..0.08 | 6.2% | 12.5% | 0.0% | stable |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlite | 0.04 | 0.04..0.04 | 6.2% | 12.5% | 5.0% | moderate |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows) / resqlit... | 0.00 | 0.00..0.00 | 150.0% | 300.0% | 0.0% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resqlite | 109.26 | 108.57..109.89 | 0.6% | 1.2% | 0.5% | stable |
| Feed Paging (v1) / Reactive feed with 100 concurrent writes / resql... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 237.79 | 229.90..241.01 | 2.3% | 4.7% | 1.0% | stable |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 217.93 | 215.76..226.55 | 2.5% | 5.0% | 1.0% | stable |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK writes / r... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite | 14.08 | 13.58..14.11 | 1.9% | 3.7% | 0.2% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite [main] | 14.08 | 13.58..14.11 | 1.9% | 3.7% | 0.2% | stable |
| Point Query Throughput / resqlite qps | 164941.00 | 99947.00..174558.00 | 22.6% | 45.2% | 3.5% | moderate |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.01 | 0.01..0.01 | 20.0% | 40.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.04 | 20.4% | 40.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode [main] | 0.03 | 0.03..0.04 | 20.4% | 40.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.01 | 4.2% | 8.3% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectBytes() [main] | 0.01 | 0.01..0.01 | 4.2% | 8.3% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.04 | 0.04..0.04 | 6.2% | 12.5% | 2.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode | 0.20 | 0.20..0.21 | 2.2% | 4.5% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEncode [main] | 0.20 | 0.20..0.21 | 2.2% | 4.5% | 1.5% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01..0.01 | 10.0% | 20.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() | 0.04 | 0.03..0.04 | 6.8% | 13.5% | 5.4% | moderate |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBytes() [main] | 0.04 | 0.03..0.04 | 6.8% | 13.5% | 5.4% | moderate |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.32 | 0.31..0.32 | 2.2% | 4.4% | 0.6% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode | 1.89 | 1.77..1.91 | 3.6% | 7.2% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonEncode [main] | 1.89 | 1.77..1.91 | 3.6% | 7.2% | 0.8% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.05 | 0.05..0.05 | 1.9% | 3.8% | 1.9% | stable |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() | 0.27 | 0.26..0.28 | 5.4% | 10.9% | 4.5% | moderate |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectBytes() [main] | 0.27 | 0.26..0.28 | 5.4% | 10.9% | 4.5% | moderate |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 3.44 | 3.34..3.73 | 5.6% | 11.2% | 2.9% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode | 23.34 | 19.85..26.95 | 15.2% | 30.4% | 14.0% | noisy |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + jsonEncode [main] | 23.34 | 19.85..26.95 | 15.2% | 30.4% | 14.0% | noisy |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.53 | 0.52..0.55 | 3.4% | 6.8% | 2.4% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() | 2.60 | 2.52..2.78 | 4.9% | 9.8% | 2.7% | stable |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite selectBytes() [m... | 2.60 | 2.52..2.78 | 4.9% | 9.8% | 2.7% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.63 | 0.60..0.64 | 2.8% | 5.5% | 0.5% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode | 3.84 | 3.67..3.96 | 3.7% | 7.4% | 3.1% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonEncode [main] | 3.84 | 3.67..3.96 | 3.7% | 7.4% | 3.1% | moderate |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.11 | 0.10..0.11 | 2.3% | 4.6% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() | 0.52 | 0.51..0.52 | 1.1% | 2.1% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectBytes() [main] | 0.52 | 0.51..0.52 | 1.1% | 2.1% | 0.2% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 8.76 | 8.43..9.22 | 4.5% | 9.0% | 1.8% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode | 44.32 | 43.17..45.72 | 2.9% | 5.7% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + jsonEncode [main] | 44.32 | 43.17..45.72 | 2.9% | 5.7% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 1.07 | 1.04..1.10 | 3.2% | 6.4% | 2.7% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() | 5.49 | 5.25..5.60 | 3.2% | 6.5% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite selectBytes() [m... | 5.49 | 5.25..5.60 | 3.2% | 6.5% | 2.1% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.02 | 0.02..0.03 | 10.4% | 20.8% | 8.3% | noisy |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.11 | 0.10..0.11 | 1.4% | 2.8% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode [main] | 0.11 | 0.10..0.11 | 1.4% | 2.8% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() | 0.02 | 0.02..0.03 | 10.4% | 20.8% | 4.2% | moderate |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectBytes() [main] | 0.02 | 0.02..0.03 | 10.4% | 20.8% | 4.2% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.16 | 0.16..0.17 | 3.4% | 6.7% | 3.0% | moderate |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode | 0.98 | 0.92..0.98 | 3.1% | 6.1% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEncode [main] | 0.98 | 0.92..0.98 | 3.1% | 6.1% | 0.4% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.03 | 0.03..0.03 | 3.8% | 7.7% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() | 0.14 | 0.14..0.15 | 4.4% | 8.9% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBytes() [main] | 0.14 | 0.14..0.15 | 4.4% | 8.9% | 0.0% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 1.78 | 1.69..1.90 | 5.9% | 11.7% | 2.4% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode | 10.55 | 10.26..12.01 | 8.3% | 16.6% | 2.8% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonEncode [main] | 10.55 | 10.26..12.01 | 8.3% | 16.6% | 2.8% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.27 | 0.26..0.28 | 4.9% | 9.7% | 3.0% | stable |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() | 1.33 | 1.26..1.64 | 14.4% | 28.7% | 3.5% | moderate |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectBytes() [main] | 1.33 | 1.26..1.64 | 14.4% | 28.7% | 3.5% | moderate |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.09 | 0.08..0.12 | 22.1% | 44.2% | 3.5% | moderate |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.02 | 0.02..0.04 | 43.5% | 87.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.25 | 0.24..0.26 | 2.2% | 4.3% | 0.8% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.06 | 0.06..0.06 | 1.6% | 3.2% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.24 | 0.24..0.25 | 2.1% | 4.1% | 1.2% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.06 | 0.06..0.06 | 1.7% | 3.3% | 0.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.38 | 0.37..0.43 | 7.3% | 14.6% | 1.1% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.06 | 0.06..0.06 | 3.3% | 6.6% | 1.6% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.81 | 0.79..0.82 | 2.2% | 4.3% | 0.7% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.23 | 0.22..0.23 | 2.8% | 5.6% | 0.9% | stable |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.03 | 0.03..0.06 | 57.1% | 114.3% | 3.6% | moderate |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.02 | 0.02..0.04 | 61.8% | 123.5% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01..0.02 | 45.5% | 90.9% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.20 | 0.20..0.23 | 8.4% | 16.8% | 2.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [main] | 0.17 | 0.16..0.18 | 8.1% | 16.2% | 2.4% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.04..0.04 | 10.3% | 20.5% | 10.3% | noisy |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 1.88 | 1.87..2.01 | 3.9% | 7.7% | 0.8% | stable |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [main] | 1.60 | 1.59..1.69 | 3.2% | 6.3% | 0.6% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.26 | 0.25..0.28 | 4.8% | 9.6% | 3.1% | moderate |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 20.41 | 19.69..21.40 | 4.2% | 8.4% | 2.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode [main] | 15.79 | 15.56..16.59 | 3.3% | 6.5% | 1.2% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 2.68 | 2.60..2.73 | 2.5% | 5.0% | 1.9% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → JSON Bytes / Large payload (~650KB) / resqlite selectBytes() | 0.24 | 0.24..0.28 | 7.9% | 15.8% | 1.3% | stable |
| Select → JSON Bytes / Large payload (~650KB) / resqlite selectBytes... | 0.00 | 0.00..0.00 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01..0.06 | 218.2% | 436.4% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00..0.02 | 0.0% | 0.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.04 | 0.04..0.15 | 155.3% | 310.5% | 2.6% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01..0.01 | 20.0% | 40.0% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.31 | 0.30..0.37 | 10.5% | 21.0% | 1.9% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.05 | 0.05..0.06 | 6.9% | 13.7% | 3.9% | moderate |
| Select → Maps / 10000 rows / resqlite select() | 3.44 | 3.35..3.56 | 3.1% | 6.2% | 0.8% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.51 | 0.51..0.54 | 3.0% | 6.1% | 1.0% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.19 | 0.17..0.23 | 15.0% | 30.1% | 7.8% | moderate |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.19 | 0.17..0.23 | 15.0% | 30.1% | 7.8% | moderate |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.48 | 0.47..0.59 | 12.9% | 25.7% | 0.4% | stable |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watc... | 0.48 | 0.47..0.59 | 12.9% | 25.7% | 0.4% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03..0.07 | 72.2% | 144.4% | 3.7% | moderate |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03..0.07 | 72.2% | 144.4% | 3.7% | moderate |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.04..0.05 | 7.4% | 14.9% | 4.3% | moderate |
| Streaming / Invalidation Latency / resqlite [main] | 0.05 | 0.04..0.05 | 7.4% | 14.9% | 4.3% | moderate |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows x 32K... | 2.65 | 2.43..2.73 | 5.6% | 11.2% | 3.1% | moderate |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows x 32K... | 2.65 | 2.43..2.73 | 5.6% | 11.2% | 3.1% | moderate |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged streams, 6... | 2.76 | 2.48..2.90 | 7.6% | 15.1% | 5.1% | moderate |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged streams, 6... | 2.76 | 2.48..2.90 | 7.6% | 15.1% | 5.1% | moderate |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 1.55 | 1.47..2.31 | 27.3% | 54.6% | 5.3% | moderate |
| Streaming / Long-Text Unchanged Fanout (8 unchanged streams, 256 ro... | 1.55 | 1.47..2.31 | 27.3% | 54.6% | 5.3% | moderate |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.18 | 3.07..3.51 | 7.0% | 13.9% | 3.2% | moderate |
| Streaming / No-Streams Write Throughput (200 inserts, no active str... | 3.18 | 3.07..3.51 | 7.0% | 13.9% | 3.2% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.58 | 1.43..2.96 | 48.4% | 96.7% | 9.1% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.58 | 1.43..2.96 | 48.4% | 96.7% | 9.1% | noisy |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.27 | 5.88..7.19 | 10.4% | 20.9% | 6.2% | moderate |
| Streaming / Stream Subscription Rate (500 subscribe+cancel cycles) ... | 6.27 | 5.88..7.19 | 10.4% | 20.9% | 6.2% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.19 | 0.17..0.24 | 17.8% | 35.6% | 6.4% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.19 | 0.17..0.24 | 17.8% | 35.6% | 6.4% | moderate |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.05 | 0.05..0.05 | 3.8% | 7.7% | 1.9% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.05 | 0.05..0.05 | 3.8% | 7.7% | 1.9% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.41 | 0.39..0.41 | 2.4% | 4.9% | 0.7% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.41 | 0.39..0.41 | 2.4% | 4.9% | 0.7% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.93 | 3.65..3.97 | 4.0% | 8.1% | 1.1% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 3.93 | 3.65..3.97 | 4.0% | 8.1% | 1.1% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.52 | 0.35..0.56 | 20.1% | 40.3% | 7.8% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.52 | 0.35..0.56 | 20.1% | 40.3% | 7.8% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.06..0.07 | 3.0% | 6.1% | 3.0% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.06..0.07 | 3.0% | 6.1% | 3.0% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.01 | 4.79..5.61 | 8.1% | 16.3% | 3.9% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.01 | 4.79..5.61 | 8.1% | 16.3% | 3.9% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.40 | 0.39..0.43 | 4.7% | 9.4% | 0.3% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.40 | 0.39..0.43 | 4.7% | 9.4% | 0.3% | stable |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 0.83 | 0.81..0.87 | 3.5% | 6.9% | 1.9% | stable |
| Write Performance / Concurrent Single Inserts (100 concurrent) / re... | 0.83 | 0.81..0.87 | 3.5% | 6.9% | 1.9% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.04..0.05 | 5.2% | 10.4% | 2.1% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.04..0.05 | 5.2% | 10.4% | 2.1% | stable |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.07 | 0.06..0.09 | 18.1% | 36.2% | 5.8% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.07 | 0.06..0.09 | 18.1% | 36.2% | 5.8% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.88 | 0.70..0.92 | 12.3% | 24.6% | 4.1% | moderate |
| Write Performance / Nested Transactions (savepoints) / resqlite nes... | 0.88 | 0.70..0.92 | 12.3% | 24.6% | 4.1% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.54 | 1.48..1.58 | 3.1% | 6.2% | 1.3% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.54 | 1.48..1.58 | 3.1% | 6.2% | 1.3% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.17..0.18 | 3.1% | 6.2% | 1.7% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.17..0.18 | 3.1% | 6.2% | 1.7% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.10 | 0.10..0.10 | 3.9% | 7.8% | 2.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.10 | 0.10..0.10 | 3.9% | 7.8% | 2.0% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 13.18 | 12.35..13.32 | 3.7% | 7.3% | 1.1% | stable |
| Write Performance / Wide Batch Insert (10000 rows x 20 params) / re... | 13.18 | 12.35..13.32 | 3.7% | 7.3% | 1.1% | stable |


## Comparison

Automatic comparison is disabled. Use `--compare-to=...` for an explicit baseline comparison.

