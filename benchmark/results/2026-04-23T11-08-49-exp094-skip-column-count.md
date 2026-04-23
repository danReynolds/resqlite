# resqlite Benchmark Results

Generated: 2026-04-23T11:08:49.439145

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp094-skip-column-count`
- Repeats: `1`
- Comparison baseline: `2026-04-23T11-05-03-round6-baseline.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.101 | 0.238 | 0.023 | 0.056 |
| sqlite3 select() | 0.145 | 0.248 | 0.145 | 0.248 |
| sqlite_async select() | 0.207 | 0.373 | 0.021 | 0.054 |
| drift select() | 0.307 | 0.503 | 0.014 | 0.027 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.071 | 0.123 | 0.010 | 0.011 |
| sqlite3 select() | 0.258 | 0.410 | 0.258 | 0.410 |
| sqlite_async select() | 0.288 | 0.462 | 0.016 | 0.031 |
| drift select() | 0.393 | 0.582 | 0.014 | 0.037 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.439 | 0.512 | 0.077 | 0.094 |
| sqlite3 select() | 1.218 | 1.624 | 1.218 | 1.624 |
| sqlite_async select() | 1.445 | 1.925 | 0.109 | 0.136 |
| drift select() | 1.994 | 2.270 | 0.100 | 0.129 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 5.686 | 18.088 | 0.793 | 2.576 |
| sqlite3 select() | 21.491 | 38.079 | 21.491 | 38.079 |
| sqlite_async select() | 14.394 | 16.256 | 0.806 | 1.035 |
| drift select() | 33.016 | 51.673 | 0.959 | 5.710 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response. resqlite's `selectBytes()` encodes natively on the worker isolate (zero-copy transfer to main); other peers and resqlite's own `select()` path go through `jsonEncode + utf8.encode` on the main isolate. Both numbers are reported per peer for the select+encode path; resqlite also reports its native selectBytes path as a separate row.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.070 | 0.176 | 0.039 | 0.082 |
| sqlite3 + jsonEncode | 0.052 | 0.135 | 0.052 | 0.135 |
| sqlite_async + jsonEncode | 0.176 | 0.383 | 0.035 | 0.071 |
| drift + jsonEncode | 0.130 | 0.246 | 0.031 | 0.057 |
| resqlite selectBytes() | 0.020 | 0.022 | 0.000 | 0.000 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.444 | 8.725 | 0.282 | 2.355 |
| sqlite3 + jsonEncode | 0.422 | 2.773 | 0.422 | 2.773 |
| sqlite_async + jsonEncode | 0.766 | 1.996 | 0.235 | 0.458 |
| drift + jsonEncode | 0.630 | 2.011 | 0.208 | 0.532 |
| resqlite selectBytes() | 0.058 | 0.232 | 0.001 | 0.008 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 5.689 | 12.729 | 4.492 | 11.458 |
| sqlite3 + jsonEncode | 5.505 | 17.128 | 5.505 | 17.128 |
| sqlite_async + jsonEncode | 5.009 | 16.399 | 2.225 | 6.767 |
| drift + jsonEncode | 4.943 | 8.830 | 2.183 | 3.905 |
| resqlite selectBytes() | 0.367 | 0.476 | 0.000 | 0.002 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 24.433 | 26.989 | 16.225 | 18.290 |
| sqlite3 + jsonEncode | 37.685 | 57.342 | 37.685 | 57.342 |
| sqlite_async + jsonEncode | 37.450 | 84.816 | 16.860 | 33.911 |
| drift + jsonEncode | 48.535 | 78.742 | 17.606 | 30.981 |
| resqlite selectBytes() | 4.668 | 7.205 | 0.006 | 0.009 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.298 | 0.723 | 0.172 | 0.462 |
| sqlite3 | 0.344 | 0.689 | 0.344 | 0.689 |
| sqlite_async | 0.404 | 0.589 | 0.046 | 0.059 |
| drift | 0.824 | 1.110 | 0.058 | 0.073 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.035 | 2.501 | 0.287 | 0.476 |
| sqlite3 | 3.544 | 4.073 | 3.544 | 4.073 |
| sqlite_async | 3.434 | 4.294 | 0.389 | 0.489 |
| drift | 5.892 | 7.983 | 0.404 | 0.495 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.681 | 2.396 | 0.107 | 0.119 |
| sqlite3 | 2.020 | 3.169 | 2.020 | 3.169 |
| sqlite_async | 1.880 | 4.221 | 0.148 | 0.187 |
| drift | 3.377 | 11.084 | 0.157 | 1.002 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.309 | 2.370 | 0.103 | 0.410 |
| sqlite3 | 1.065 | 1.600 | 1.065 | 1.600 |
| sqlite_async | 1.022 | 1.214 | 0.122 | 0.141 |
| drift | 1.740 | 2.440 | 0.131 | 0.175 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.309 | 0.332 | 0.100 | 0.105 |
| sqlite3 | 0.970 | 1.115 | 0.970 | 1.115 |
| sqlite_async | 1.031 | 1.216 | 0.123 | 0.136 |
| drift | 1.669 | 1.971 | 0.129 | 0.158 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.021 | 0.025 | 0.002 | 0.005 |
| sqlite3 | 0.022 | 0.024 | 0.022 | 0.024 |
| sqlite_async | 0.082 | 0.180 | 0.005 | 0.014 |
| drift | 0.110 | 0.242 | 0.009 | 0.021 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.035 | 0.056 | 0.005 | 0.006 |
| sqlite3 | 0.066 | 0.086 | 0.066 | 0.086 |
| sqlite_async | 0.105 | 0.121 | 0.007 | 0.008 |
| drift | 0.127 | 0.204 | 0.007 | 0.010 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.053 | 0.059 | 0.009 | 0.010 |
| sqlite3 | 0.120 | 0.124 | 0.120 | 0.124 |
| sqlite_async | 0.166 | 0.344 | 0.012 | 0.021 |
| drift | 0.203 | 0.320 | 0.012 | 0.022 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.201 | 0.227 | 0.044 | 0.049 |
| sqlite3 | 0.578 | 0.636 | 0.578 | 0.636 |
| sqlite_async | 0.630 | 0.855 | 0.054 | 0.071 |
| drift | 0.921 | 1.121 | 0.055 | 0.067 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.390 | 0.484 | 0.088 | 0.094 |
| sqlite3 | 1.216 | 1.327 | 1.216 | 1.327 |
| sqlite_async | 1.209 | 1.571 | 0.110 | 0.144 |
| drift | 2.150 | 2.822 | 0.127 | 0.214 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.001 | 1.587 | 0.183 | 0.276 |
| sqlite3 | 2.634 | 3.544 | 2.634 | 3.544 |
| sqlite_async | 2.645 | 3.273 | 0.224 | 0.241 |
| drift | 3.783 | 5.290 | 0.217 | 0.252 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.355 | 7.164 | 0.443 | 0.507 |
| sqlite3 | 6.014 | 8.207 | 6.014 | 8.207 |
| sqlite_async | 6.740 | 8.860 | 0.511 | 0.591 |
| drift | 10.710 | 19.905 | 0.527 | 0.732 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.833 | 12.763 | 0.879 | 1.455 |
| sqlite3 | 15.953 | 21.424 | 15.953 | 21.424 |
| sqlite_async | 15.034 | 22.822 | 1.013 | 3.105 |
| drift | 31.410 | 57.227 | 1.050 | 2.731 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 13.190 | 23.159 | 1.759 | 2.358 |
| sqlite3 | 43.907 | 71.938 | 43.907 | 71.938 |
| sqlite_async | 42.359 | 56.037 | 1.978 | 7.909 |
| drift | 62.875 | 103.180 | 2.002 | 10.102 |


### Bytes (selectBytes → JSON)

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.040 | 0.043 | 0.040 | 0.043 |
| sqlite3 + jsonEncode | 0.038 | 0.039 | 0.038 | 0.039 |
| sqlite_async + jsonEncode | 0.092 | 0.201 | 0.092 | 0.201 |
| drift + jsonEncode | 0.113 | 0.187 | 0.113 | 0.187 |
| resqlite selectBytes() | 0.014 | 0.016 | 0.014 | 0.016 |

### 50 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.116 | 0.152 | 0.116 | 0.152 |
| sqlite3 + jsonEncode | 0.151 | 0.245 | 0.151 | 0.245 |
| sqlite_async + jsonEncode | 0.180 | 0.198 | 0.180 | 0.198 |
| drift + jsonEncode | 0.260 | 0.324 | 0.260 | 0.324 |
| resqlite selectBytes() | 0.032 | 0.033 | 0.032 | 0.033 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 0.212 | 0.380 | 0.212 | 0.380 |
| sqlite3 + jsonEncode | 0.295 | 0.430 | 0.295 | 0.430 |
| sqlite_async + jsonEncode | 0.312 | 0.501 | 0.312 | 0.501 |
| drift + jsonEncode | 0.453 | 0.591 | 0.453 | 0.591 |
| resqlite selectBytes() | 0.059 | 0.141 | 0.059 | 0.141 |

### 500 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 1.178 | 1.875 | 1.178 | 1.875 |
| sqlite3 + jsonEncode | 1.824 | 7.954 | 1.824 | 7.954 |
| sqlite_async + jsonEncode | 3.958 | 6.371 | 3.958 | 6.371 |
| drift + jsonEncode | 3.330 | 8.490 | 3.330 | 8.490 |
| resqlite selectBytes() | 0.275 | 0.755 | 0.275 | 0.755 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 2.421 | 3.664 | 2.421 | 3.664 |
| sqlite3 + jsonEncode | 3.232 | 8.123 | 3.232 | 8.123 |
| sqlite_async + jsonEncode | 3.307 | 6.412 | 3.307 | 6.412 |
| drift + jsonEncode | 3.551 | 6.511 | 3.551 | 6.511 |
| resqlite selectBytes() | 0.371 | 0.460 | 0.371 | 0.460 |

### 2000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 4.080 | 7.155 | 4.080 | 7.155 |
| sqlite3 + jsonEncode | 6.244 | 12.616 | 6.244 | 12.616 |
| sqlite_async + jsonEncode | 10.675 | 37.552 | 10.675 | 37.552 |
| drift + jsonEncode | 7.078 | 11.387 | 7.078 | 11.387 |
| resqlite selectBytes() | 0.905 | 1.967 | 0.905 | 1.967 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 13.085 | 25.829 | 13.085 | 25.829 |
| sqlite3 + jsonEncode | 17.438 | 20.929 | 17.438 | 20.929 |
| sqlite_async + jsonEncode | 19.273 | 29.087 | 19.273 | 29.087 |
| drift + jsonEncode | 27.354 | 46.754 | 27.354 | 46.754 |
| resqlite selectBytes() | 2.161 | 4.418 | 2.161 | 4.418 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 22.509 | 26.876 | 22.509 | 26.876 |
| sqlite3 + jsonEncode | 35.097 | 57.830 | 35.097 | 57.830 |
| sqlite_async + jsonEncode | 35.289 | 39.642 | 35.289 | 39.642 |
| drift + jsonEncode | 45.341 | 70.984 | 45.341 | 70.984 |
| resqlite selectBytes() | 4.086 | 6.823 | 4.086 | 6.823 |

### 20000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite + jsonEncode | 50.518 | 102.039 | 50.518 | 102.039 |
| sqlite3 + jsonEncode | 72.674 | 129.146 | 72.674 | 129.146 |
| sqlite_async + jsonEncode | 96.286 | 141.798 | 96.286 | 141.798 |
| drift + jsonEncode | 161.938 | 301.364 | 161.938 | 301.364 |
| resqlite selectBytes() | 18.824 | 85.853 | 18.824 | 85.853 |


## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency). Each concurrency level runs `N` parallel queries; we report both total wall time and effective per-query latency (total / N).

### 1× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.42 | 1.22 | 0.42 |
| sqlite_async | 1.40 | 3.13 | 1.40 |
| drift | 1.94 | 2.23 | 1.94 |

### 2× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.39 | 0.67 | 0.19 |
| sqlite_async | 1.82 | 2.34 | 0.91 |
| drift | 3.51 | 4.04 | 1.76 |

### 4× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 0.60 | 1.11 | 0.15 |
| sqlite_async | 3.94 | 6.02 | 0.98 |
| drift | 9.05 | 15.01 | 2.26 |

### 8× concurrency

| Library | Wall med (ms) | Wall p90 (ms) | Per-query (ms) |
|---|---|---|---|
| resqlite | 2.18 | 5.33 | 0.27 |
| sqlite_async | 5.48 | 6.37 | 0.69 |
| drift | 11.85 | 13.06 | 1.48 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead. Each iteration runs 500 sequential queries over 100 iterations per library. 95% CI and MDE values derive from per-iteration QPS samples via percentile bootstrap (deterministic, seed=202440478).

| Metric | Value |
|---|---:|
| resqlite qps | 87827 |
| resqlite per query | 0.011 ms |

### QPS + MDE

| Library | QPS median | 95% CI | MDE_ci % | MDE_mad % |
|---|---:|---:|---:|---:|
| resqlite | 87827 | 86341..92114 | 3.3 | 36.5 |
| sqlite3 | 172712 | 168039..175131 | 2.1 | 22.7 |
| sqlite_async | 27766 | 25899..30422 | 8.1 | 56.3 |
| drift | 27239 | 25371..29755 | 8.0 | 58.6 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 19.244 | 42.209 | 19.244 | 42.209 |
| sqlite_async | 52.407 | 75.864 | 52.407 | 75.864 |
| drift | 71.547 | 80.689 | 71.547 | 80.689 |
| sqlite3 (no cache) | 28.173 | 29.967 | 28.173 | 29.967 |
| sqlite3 (cached stmt) | 30.132 | 37.961 | 30.132 | 37.961 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 2.279 | 3.138 | 2.279 | 3.138 |
| sqlite3 execute() | 1.172 | 1.910 | 1.172 | 1.910 |
| sqlite_async execute() | 5.537 | 14.736 | 5.537 | 14.736 |
| drift execute() | 8.243 | 27.967 | 8.243 | 27.967 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.062 | 0.081 | 0.062 | 0.081 |
| sqlite3 executeBatch() | 0.052 | 0.090 | 0.052 | 0.090 |
| sqlite_async executeBatch() | 0.109 | 0.208 | 0.109 | 0.208 |
| drift executeBatch() | 0.148 | 0.244 | 0.148 | 0.244 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.492 | 1.465 | 0.492 | 1.465 |
| sqlite3 executeBatch() | 0.493 | 0.867 | 0.493 | 0.867 |
| sqlite_async executeBatch() | 0.610 | 1.261 | 0.610 | 1.261 |
| drift executeBatch() | 0.840 | 1.175 | 0.840 | 1.175 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 9.281 | 18.936 | 9.281 | 18.936 |
| sqlite3 executeBatch() | 7.246 | 11.200 | 7.246 | 11.200 |
| sqlite_async executeBatch() | 7.433 | 13.370 | 7.433 | 13.370 |
| drift executeBatch() | 10.813 | 17.967 | 10.813 | 17.967 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.058 | 0.083 | 0.058 | 0.083 |
| sqlite_async writeTransaction() | 0.080 | 0.319 | 0.080 | 0.319 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.079 | 0.322 | 0.079 | 0.322 |
| resqlite tx.execute() loop | 0.877 | 1.116 | 0.877 | 1.116 |
| sqlite_async tx.execute() loop | 1.905 | 2.844 | 1.905 | 2.844 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.513 | 1.065 | 0.513 | 1.065 |
| resqlite tx.execute() loop | 8.095 | 9.345 | 8.095 | 9.345 |
| sqlite_async tx.execute() loop | 16.177 | 34.718 | 16.177 | 34.718 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.101 | 0.170 | 0.101 | 0.170 |
| sqlite_async tx.getAll() | 0.213 | 0.500 | 0.213 | 0.500 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.228 | 1.036 | 0.228 | 1.036 |
| sqlite_async tx.getAll() | 0.458 | 2.216 | 0.458 | 2.216 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.037 | 0.041 | 0.037 | 0.041 |
| sqlite_async watch() | 0.121 | 0.384 | 0.121 | 0.384 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.042 | 0.059 | 0.042 | 0.059 |
| sqlite_async | 0.133 | 1.863 | 0.133 | 1.863 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.750 | 7.362 | 1.750 | 7.362 |
| sqlite_async | 6.055 | 11.416 | 6.055 | 11.416 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.470 | 1.814 | 0.470 | 1.814 |
| sqlite_async | 0.601 | 3.240 | 0.601 | 3.240 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 5.116 | 5.116 | 5.116 | 5.116 |
| sqlite_async | 19.891 | 19.891 | 19.891 | 19.891 |


### No-Streams Write Throughput (200 inserts, no active streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 6.071 | 13.213 | 6.071 | 13.213 |
| sqlite_async | 11.816 | 25.172 | 11.816 | 25.172 |


### Growing-Stream Invalidation (batch-insert 100 into watched stream)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.603 | 0.970 | 0.603 | 0.970 |


### Stream Subscription Rate (500 subscribe+cancel cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 9.597 | 13.850 | 9.597 | 13.850 |


## Streaming (Column Granularity)

10 concurrent streams read `SELECT id, a, b FROM wide ...`. The writer issues 500 updates — first against a **disjoint** column (`c`, not in the projection), then against an **overlapping** column (`a`, in the projection). **`Re-emit ratio` = `disjoint / overlapping` is the primary metric**: it shows how effectively the library suppresses re-emission on writes that don't affect the query's result. Absolute counts are coalescing-dependent and not directly comparable across libraries. On resqlite's main branch this ratio is driven toward 0 by experiment 075 (C-side result-hash short-circuit), not by writer-side column-tracking (exp 052 is not implemented). The two mechanisms are indistinguishable on this read-side benchmark.

### Disjoint column writes (SET c = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 0 | 82.3 | 0.000 |
| sqlite_async | 3268 | 1161.7 | 1.040 |
| drift | 5000 | 1258.7 | 1.000 |

### Overlapping column writes (SET a = ?)

| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |
|---|---|---|---|
| resqlite | 10 | 85.4 | 0.000 |
| sqlite_async | 3142 | 1240.4 | 1.040 |
| drift | 5000 | 1198.6 | 1.000 |

## Keyed PK Subscriptions (v1)

50 reactive streams each watch one PK. 200 random-PK writes across a 10K-row table. The committed PRNG seed produces 3 hits on watched PKs, so both miss-path and hit-path are exercised each run. With keyed invalidation, a library fires only on those hits. With table-level invalidation, every write triggers a re-query on all 50 streams (10K re-queries, most suppressed by hash but still costly).

### 50 streams × 200 random-PK writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Total emits | Observed hits |
|---|---|---|---|---|---|---|
| resqlite stream() | 221.28 | 222.31 | 0.00 | 0.00 | 0 | 3 |
| sqlite_async stream() | 433.93 | 434.98 | 0.00 | 0.00 | 1138 | 3 |
| drift stream() | 590.66 | 620.71 | 0.14 | 0.22 | 10000 | 3 |

**Total emits**: post-baseline emissions summed across all 50 streams. **Observed hits**: how many of the 200 random writes actually targeted a watched PK. Perfect behavior: emissions == hits. Emissions < hits means hash suppression elided some writes whose row value did not change. Emissions > hits means over-fire.

Wall time is dominated by re-query work. A library with keyed-PK invalidation (Track D's planned `watchRow()`) can avoid re-querying for writes whose PK is unwatched, reducing wall time substantially even when emission counts already look clean due to hash suppression.

## Chat Sim (v1)

Mixed R/W workload: 500 users, 100 conversations, 10K seed messages (Zipfian distribution). 10K ops: 5% message inserts, 5% conversation last_msg_at updates, 45% fetch-last-20 with user JOIN, 45% fetch-user-by-PK. Measures each op type separately so per-library wall/main tradeoffs are legible.

### Insert message

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.034 | 0.073 | 0.000 | 0.000 |
| sqlite3 | 0.021 | 0.039 | 0.021 | 0.039 |
| sqlite_async | 0.059 | 0.106 | 0.000 | 0.000 |
| drift | 0.068 | 0.115 | 0.000 | 0.000 |

### Update conversation

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.024 | 0.063 | 0.000 | 0.000 |
| sqlite3 | 0.014 | 0.027 | 0.014 | 0.027 |
| sqlite_async | 0.046 | 0.085 | 0.000 | 0.000 |
| drift | 0.057 | 0.092 | 0.000 | 0.000 |

### Fetch last-20 messages (JOIN users)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.032 | 0.058 | 0.000 | 0.000 |
| sqlite3 | 0.032 | 0.039 | 0.032 | 0.039 |
| sqlite_async | 0.070 | 0.116 | 0.000 | 0.001 |
| drift | 0.063 | 0.088 | 0.000 | 0.000 |

### Fetch user by PK

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.012 | 0.027 | 0.000 | 0.000 |
| sqlite3 | 0.005 | 0.007 | 0.005 | 0.007 |
| sqlite_async | 0.027 | 0.046 | 0.000 | 0.000 |
| drift | 0.027 | 0.045 | 0.000 | 0.000 |

**Interpretation.** Each op type is timed independently. A library that dominates on one op type (e.g. reads) may lose on another (e.g. inserts under commit pressure). For Flutter-facing usage, the `Main med` column is the key number: it's the time spent on the UI thread per op.

## Feed Paging (v1)

100K posts. Part A: 20 keyset-paged queries of 50 posts each, all three peers. Part B: one reactive stream on latest-50 with 100 concurrent like_count writes, resqlite + sqlite_async. Models an infinite-scroll feed with live updates.

### Keyset pagination (20 pages × 50 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.045 | 0.078 | 0.004 | 0.004 |
| sqlite3 | 0.072 | 0.111 | 0.072 | 0.111 |
| sqlite_async | 0.087 | 0.112 | 0.001 | 0.002 |
| drift | 0.102 | 0.156 | 0.001 | 0.002 |

Keyset pagination walks backwards through the feed via `(created_at, id) < (?, ?)` rather than `OFFSET`, which scales with position rather than degrading on deep pages. Per-page timing is reported; reading the p90 catches occasional slow pages that would be invisible in a wall-aggregate.

### Reactive feed with 100 concurrent writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Emissions |
|---|---|---|---|---|---|
| resqlite | 107.409 | 110.334 | 0.000 | 0.000 | 0 |
| sqlite_async | 210.819 | 214.330 | 0.000 | 0.001 | 39 |
| drift | 227.751 | 236.312 | 0.000 | 0.001 | 100 |

One stream on latest-50. 100 `like_count` writes against random posts — most do not intersect the watched page. `Main med` is aggregate listener-callback time (UI thread cost, see METHODOLOGY.md § Measurement). `Emissions` is post-baseline; a library with hash-based unchanged suppression can stay near 0 when the watched page does not change.

## High-Cardinality Stream Fan-out (v1)

100 reactive streams each watching one of 100 owner partitions of a 10K-item table. 200 random-item writes target random items. Models Flutter list views with many simultaneous row watchers (detail screens, reactive timelines). Originally exposed a write-burst pool-saturation pathology; that was fixed in PR #17 by adding per-stream re-query coalescing in the stream engine. This benchmark remains as its regression guard.

### 100 streams × 200 writes

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) | Init drain (ms) | Write burst (ms) | Emissions |
|---|---|---|---|---|---|---|---|
| resqlite | 436.60 | 436.60 | 0.00 | 0.00 | 12.51 | 424.70 | 2 |
| sqlite_async | 479.45 | 479.45 | 0.01 | 0.01 | 23.56 | 456.07 | 1174 |
| drift | 2256.28 | 2256.28 | 0.73 | 0.73 | 12.86 | 2243.48 | 20000 |

**Init drain**: median wall time from subscribing all 100 streams to the last one producing its initial emission. Exposes cold-start cost of the subscriber fleet.

**Write burst**: median wall time from first write to last emission settled after 200 writes. Dominated by re-query cost × stream count × write count for libraries without per-row invalidation; hash suppression (resqlite exp 031/033) elides emissions but the re-query itself still runs.

**Wall / Main** columns are end-to-end (init + writes + settle). `Main` is aggregate listener-callback time — the UI thread cost.

## Memory

Process RSS delta around each workload. Values are a **lower bound** on real allocation volume because the Dart VM retains heap pages after GC. A visible reduction here implies the underlying allocation win is at least that large.

### Select 10k rows → Maps

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite select() | 7.09 | 11.11 | 0.00..9.39 | ±4.70 |
| sqlite3 select() | 2.92 | 10.25 | 0.00..7.47 | ±3.73 |
| sqlite_async select() | 1.00 | 5.59 | 0.50..1.52 | ±0.51 |
| drift select() | 9.00 | 52.97 | 0.00..38.33 | ±19.16 |

### Select 10k rows → JSON Bytes

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.00 | 12.02 | 0.00..2.08 | ±1.04 |
| resqlite + jsonEncode | 1.50 | 89.66 | 0.00..25.06 | ±12.53 |
| sqlite3 + jsonEncode | 0.25 | 81.69 | 0.00..36.89 | ±18.45 |
| sqlite_async + jsonEncode | 0.00 | 62.06 | 0.00..26.92 | ±13.46 |
| drift + jsonEncode | 1.17 | 84.19 | 0.00..54.52 | ±27.26 |

### Batch insert 10k rows

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.00 | 11.30 | 0.00..0.20 | ±0.10 |
| sqlite3 executeBatch() | 0.00 | 0.50 | 0.00..0.00 | ±0.00 |
| sqlite_async executeBatch() | 0.03 | 2.23 | 0.00..0.83 | ±0.41 |
| drift batch() | 0.00 | 2.05 | 0.00..0.06 | ±0.03 |

### Streaming fan-out (10 streams × 100 writes)

| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |
|---|---|---|---|---|
| resqlite stream() | 0.09 | 0.17 | 0.00..0.13 | ±0.06 |
| sqlite_async watch() | 0.00 | 0.63 | 0.00..0.52 | ±0.26 |

## SQLite Diagnostics

resqlite-only internal SQLite counters captured via `Database.diagnostics()` after representative workloads. Values reflect the writer plus idle readers in this connection pool; they are not process-global SQLite totals.

### Warm read working set (20000 rows + 2000 point lookups)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | Readers busy |
|---|---|---|---|---|---|---|
| resqlite | 3207.0 | 3189.5 | 5.3 | 12.2 | 2048.0 | 0 |

### Statement cache footprint (48 distinct SELECT texts)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | Readers busy |
|---|---|---|---|---|---|---|
| resqlite | 3300.0 | 3189.5 | 5.3 | 105.2 | 2048.0 | 0 |

### WAL after write burst (1000 inserted rows)

| Library | SQLite total (KiB) | Page cache (KiB) | Schema (KiB) | Stmt (KiB) | WAL (KiB) | Readers busy |
|---|---|---|---|---|---|---|
| resqlite | 257.5 | 240.0 | 5.3 | 12.2 | 161.0 | 0 |

## Comparison vs Previous Run

Previous: `2026-04-23T11-05-03-round6-baseline.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Noise threshold | Stability | Status |
|---|---|---|---|---|---|---|
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.04 | 0.03 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch last-20 messages (JOIN users) / res... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch user by PK / resqlite | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Chat Sim (v1) / Fetch user by PK / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Chat Sim (v1) / Insert message / resqlite | 0.04 | 0.03 | -0.01 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Chat Sim (v1) / Insert message / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Chat Sim (v1) / Update conversation / resqlite | 0.03 | 0.02 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Chat Sim (v1) / Update conversation / resqlite [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.42 | +0.12 | ±10% / ±0.04 ms | single run | 🔴 Regression (+40%) |
| Concurrent Reads (1000 rows per query) / 1× concurrency /... | 0.30 | 0.42 | +0.12 | ±10% / ±0.04 ms | single run | 🔴 Regression (+40%) |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.98 | 0.39 | -0.59 | ±10% / ±0.10 ms | single run | 🟢 Win (-60%) |
| Concurrent Reads (1000 rows per query) / 2× concurrency /... | 0.49 | 0.19 | -0.30 | ±10% / ±0.05 ms | single run | 🟢 Win (-61%) |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.45 | 0.60 | +0.15 | ±10% / ±0.06 ms | single run | 🔴 Regression (+33%) |
| Concurrent Reads (1000 rows per query) / 4× concurrency /... | 0.11 | 0.15 | +0.04 | ±10% / ±0.02 ms | single run | 🔴 Regression (+36%) |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 1.10 | 2.18 | +1.08 | ±10% / ±0.22 ms | single run | 🔴 Regression (+98%) |
| Concurrent Reads (1000 rows per query) / 8× concurrency /... | 0.14 | 0.27 | +0.13 | ±10% / ±0.03 ms | single run | 🔴 Regression (+93%) |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.05 | 0.04 | -0.01 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Feed Paging (v1) / Keyset pagination (20 pages × 50 rows)... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 109.06 | 107.41 | -1.65 | ±10% / ±10.91 ms | single run | ⚪ Neutral |
| Feed Paging (v1) / Reactive feed with 100 concurrent writ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 239.02 | 436.60 | +197.58 | ±10% / ±43.66 ms | single run | 🔴 Regression (+83%) |
| High-Cardinality Stream Fan-out (v1) / 100 streams × 200 ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 222.48 | 221.28 | -1.20 | ±10% / ±22.25 ms | single run | ⚪ Neutral |
| Keyed PK Subscriptions (v1) / 50 streams × 200 random-PK ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 15.33 | 19.24 | +3.92 | ±10% / ±1.92 ms | single run | 🔴 Regression (+26%) |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 15.33 | 19.24 | +3.92 | ±10% / ±1.92 ms | single run | 🔴 Regression (+26%) |
| Point Query Throughput / resqlite qps | 99493.00 | 87827.00 | -11666.00 | ±10% / ±9949.30 ms | single run | 🔴 Regression (-12%) |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite | 0.06 | 0.02 | -0.04 | ±10% / ±0.02 ms | single run | 🟢 Win (-66%) |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEncode | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite + jsonEnc... | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite [main] | 0.00 | 0.00 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.02 | 0.01 | -0.01 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10 rows / resqlite selectByt... | 0.02 | 0.01 | -0.01 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.30 | 0.21 | -0.08 | ±10% / ±0.03 ms | single run | 🟢 Win (-29%) |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite + jsonEn... | 0.30 | 0.21 | -0.08 | ±10% / ±0.03 ms | single run | 🟢 Win (-29%) |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.05 | 0.06 | +0.01 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 100 rows / resqlite selectBy... | 0.05 | 0.06 | +0.01 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite | 0.39 | 0.39 | -0.00 | ±10% / ±0.04 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 4.69 | 2.42 | -2.27 | ±10% / ±0.47 ms | single run | 🟢 Win (-48%) |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite + jsonE... | 4.69 | 2.42 | -2.27 | ±10% / ±0.47 ms | single run | 🟢 Win (-48%) |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite [main] | 0.09 | 0.09 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.50 | 0.37 | -0.13 | ±10% / ±0.05 ms | single run | 🟢 Win (-26%) |
| Scaling (10 → 20,000 rows) / 1000 rows / resqlite selectB... | 0.50 | 0.37 | -0.13 | ±10% / ±0.05 ms | single run | 🟢 Win (-26%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite | 5.93 | 4.83 | -1.10 | ±10% / ±0.59 ms | single run | 🟢 Win (-19%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 25.75 | 22.51 | -3.24 | ±10% / ±2.58 ms | single run | 🟢 Win (-13%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite + json... | 25.75 | 22.51 | -3.24 | ±10% / ±2.58 ms | single run | 🟢 Win (-13%) |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite [main] | 0.89 | 0.88 | -0.01 | ±10% / ±0.09 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 4.29 | 4.09 | -0.20 | ±10% / ±0.43 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 10000 rows / resqlite select... | 4.29 | 4.09 | -0.20 | ±10% / ±0.43 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite | 0.88 | 1.00 | +0.12 | ±10% / ±0.10 ms | single run | 🔴 Regression (+13%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 10.38 | 4.08 | -6.30 | ±10% / ±1.04 ms | single run | 🟢 Win (-61%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite + jsonE... | 10.38 | 4.08 | -6.30 | ±10% / ±1.04 ms | single run | 🟢 Win (-61%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite [main] | 0.18 | 0.18 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 1.60 | 0.91 | -0.70 | ±10% / ±0.16 ms | single run | 🟢 Win (-44%) |
| Scaling (10 → 20,000 rows) / 2000 rows / resqlite selectB... | 1.60 | 0.91 | -0.70 | ±10% / ±0.16 ms | single run | 🟢 Win (-44%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite | 16.00 | 13.19 | -2.81 | ±10% / ±1.60 ms | single run | 🟢 Win (-18%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 45.12 | 50.52 | +5.40 | ±10% / ±5.05 ms | single run | 🔴 Regression (+12%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite + json... | 45.12 | 50.52 | +5.40 | ±10% / ±5.05 ms | single run | 🔴 Regression (+12%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite [main] | 2.01 | 1.76 | -0.25 | ±10% / ±0.20 ms | single run | 🟢 Win (-12%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.09 | 18.82 | +10.73 | ±10% / ±1.88 ms | single run | 🔴 Regression (+133%) |
| Scaling (10 → 20,000 rows) / 20000 rows / resqlite select... | 8.09 | 18.82 | +10.73 | ±10% / ±1.88 ms | single run | 🔴 Regression (+133%) |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite | 0.17 | 0.04 | -0.14 | ±10% / ±0.02 ms | single run | 🟢 Win (-79%) |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEncode | 0.13 | 0.12 | -0.02 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite + jsonEnc... | 0.13 | 0.12 | -0.02 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite [main] | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 50 rows / resqlite selectByt... | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite | 0.22 | 0.20 | -0.02 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 1.83 | 1.18 | -0.65 | ±10% / ±0.18 ms | single run | 🟢 Win (-36%) |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite + jsonEn... | 1.83 | 1.18 | -0.65 | ±10% / ±0.18 ms | single run | 🟢 Win (-36%) |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite [main] | 0.05 | 0.04 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.22 | 0.28 | +0.06 | ±10% / ±0.03 ms | single run | 🔴 Regression (+27%) |
| Scaling (10 → 20,000 rows) / 500 rows / resqlite selectBy... | 0.22 | 0.28 | +0.06 | ±10% / ±0.03 ms | single run | 🔴 Regression (+27%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite | 2.69 | 2.35 | -0.33 | ±10% / ±0.27 ms | single run | 🟢 Win (-12%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 23.51 | 13.09 | -10.42 | ±10% / ±2.35 ms | single run | 🟢 Win (-44%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite + jsonE... | 23.51 | 13.09 | -10.42 | ±10% / ±2.35 ms | single run | 🟢 Win (-44%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite [main] | 0.46 | 0.44 | -0.02 | ±10% / ±0.05 ms | single run | ⚪ Neutral |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 3.68 | 2.16 | -1.52 | ±10% / ±0.37 ms | single run | 🟢 Win (-41%) |
| Scaling (10 → 20,000 rows) / 5000 rows / resqlite selectB... | 3.68 | 2.16 | -1.52 | ±10% / ±0.37 ms | single run | 🟢 Win (-41%) |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.16 | 0.30 | +0.13 | ±10% / ±0.03 ms | single run | 🔴 Regression (+83%) |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.09 | 0.17 | +0.08 | ±10% / ±0.02 ms | single run | 🔴 Regression (+91%) |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.32 | 0.31 | -0.01 | ±10% / ±0.03 ms | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.30 | 0.31 | +0.00 | ±10% / ±0.03 ms | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.66 | 0.68 | +0.03 | ±10% / ±0.07 ms | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 1.00 | 1.03 | +0.04 | ±10% / ±0.10 ms | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.29 | 0.29 | -0.00 | ±10% / ±0.03 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode | 0.17 | 0.07 | -0.10 | ±10% / ±0.02 ms | single run | 🟢 Win (-60%) |
| Select → JSON Bytes / 10 rows / resqlite + jsonEncode [main] | 0.09 | 0.04 | -0.05 | ±10% / ±0.02 ms | single run | 🟢 Win (-58%) |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.02 | 0.02 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode | 0.36 | 0.44 | +0.09 | ±10% / ±0.04 ms | single run | 🔴 Regression (+24%) |
| Select → JSON Bytes / 100 rows / resqlite + jsonEncode [m... | 0.23 | 0.28 | +0.06 | ±10% / ±0.03 ms | single run | 🔴 Regression (+25%) |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode | 2.70 | 5.69 | +2.99 | ±10% / ±0.57 ms | single run | 🔴 Regression (+111%) |
| Select → JSON Bytes / 1000 rows / resqlite + jsonEncode [... | 2.14 | 4.49 | +2.35 | ±10% / ±0.45 ms | single run | 🔴 Regression (+110%) |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.39 | 0.37 | -0.02 | ±10% / ±0.04 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode | 26.39 | 24.43 | -1.95 | ±10% / ±2.64 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite + jsonEncode ... | 19.46 | 16.23 | -3.24 | ±10% / ±1.95 ms | single run | 🟢 Win (-17%) |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 4.39 | 4.67 | +0.27 | ±10% / ±0.47 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.01 | 0.01 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Select → Maps / 10 rows / resqlite select() | 0.10 | 0.10 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Select → Maps / 10 rows / resqlite select() [main] | 0.02 | 0.02 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Select → Maps / 100 rows / resqlite select() | 0.16 | 0.07 | -0.09 | ±10% / ±0.02 ms | single run | 🟢 Win (-55%) |
| Select → Maps / 100 rows / resqlite select() [main] | 0.02 | 0.01 | -0.01 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Select → Maps / 1000 rows / resqlite select() | 0.70 | 0.44 | -0.26 | ±10% / ±0.07 ms | single run | 🟢 Win (-37%) |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.08 | 0.08 | -0.01 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Select → Maps / 10000 rows / resqlite select() | 8.87 | 5.69 | -3.18 | ±10% / ±0.89 ms | single run | 🟢 Win (-36%) |
| Select → Maps / 10000 rows / resqlite select() [main] | 1.06 | 0.79 | -0.27 | ±10% / ±0.11 ms | single run | 🟢 Win (-25%) |
| Streaming / Fan-out (10 streams) / resqlite | 0.68 | 0.47 | -0.21 | ±10% / ±0.07 ms | single run | 🟢 Win (-31%) |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.68 | 0.47 | -0.21 | ±10% / ±0.07 ms | single run | 🟢 Win (-31%) |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.57 | 0.60 | +0.03 | ±10% / ±0.06 ms | single run | ⚪ Neutral |
| Streaming / Growing-Stream Invalidation (batch-insert 100... | 0.57 | 0.60 | +0.03 | ±10% / ±0.06 ms | single run | ⚪ Neutral |
| Streaming / Initial Emission / resqlite stream() | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Streaming / Initial Emission / resqlite stream() [main] | 0.04 | 0.04 | -0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Streaming / Invalidation Latency / resqlite | 0.06 | 0.04 | -0.02 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Streaming / Invalidation Latency / resqlite [main] | 0.06 | 0.04 | -0.02 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 4.03 | 6.07 | +2.05 | ±10% / ±0.61 ms | single run | 🔴 Regression (+51%) |
| Streaming / No-Streams Write Throughput (200 inserts, no ... | 4.03 | 6.07 | +2.05 | ±10% / ±0.61 ms | single run | 🔴 Regression (+51%) |
| Streaming / Stream Churn (100 cycles) / resqlite | 3.31 | 5.12 | +1.81 | ±10% / ±0.51 ms | single run | 🔴 Regression (+55%) |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 3.31 | 5.12 | +1.81 | ±10% / ±0.51 ms | single run | 🔴 Regression (+55%) |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 8.64 | 9.60 | +0.96 | ±10% / ±0.96 ms | single run | ⚪ Neutral |
| Streaming / Stream Subscription Rate (500 subscribe+cance... | 8.64 | 9.60 | +0.96 | ±10% / ±0.96 ms | single run | ⚪ Neutral |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.31 | 1.75 | +1.44 | ±10% / ±0.18 ms | single run | 🔴 Regression (+466%) |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.31 | 1.75 | +1.44 | ±10% / ±0.18 ms | single run | 🔴 Regression (+466%) |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.08 | 0.06 | -0.02 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.08 | 0.06 | -0.02 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.50 | 0.49 | -0.01 | ±10% / ±0.05 ms | single run | ⚪ Neutral |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.50 | 0.49 | -0.01 | ±10% / ±0.05 ms | single run | ⚪ Neutral |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 5.39 | 9.28 | +3.89 | ±10% / ±0.93 ms | single run | 🔴 Regression (+72%) |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 5.39 | 9.28 | +3.89 | ±10% / ±0.93 ms | single run | 🔴 Regression (+72%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.87 | 0.88 | +0.01 | ±10% / ±0.09 ms | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.87 | 0.88 | +0.01 | ±10% / ±0.09 ms | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.08 | +0.01 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.08 | +0.01 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 7.39 | 8.10 | +0.71 | ±10% / ±0.81 ms | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 7.39 | 8.10 | +0.71 | ±10% / ±0.81 ms | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.50 | 0.51 | +0.01 | ±10% / ±0.05 ms | single run | ⚪ Neutral |
| Write Performance / Batched Write Inside Transaction (100... | 0.50 | 0.51 | +0.01 | ±10% / ±0.05 ms | single run | ⚪ Neutral |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Write Performance / Single Inserts (100 sequential) / res... | 1.98 | 2.28 | +0.30 | ±10% / ±0.23 ms | single run | 🔴 Regression (+15%) |
| Write Performance / Single Inserts (100 sequential) / res... | 1.98 | 2.28 | +0.30 | ±10% / ±0.23 ms | single run | 🔴 Regression (+15%) |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.23 | +0.04 | ±10% / ±0.02 ms | single run | 🔴 Regression (+23%) |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.23 | +0.04 | ±10% / ±0.02 ms | single run | 🔴 Regression (+23%) |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.11 | 0.10 | -0.01 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.11 | 0.10 | -0.01 | ±10% / ±0.02 ms | single run | ⚪ Neutral |

**Summary:** 35 wins, 35 regressions, 83 neutral

Comparison threshold uses `max(10%, 3 × current MAD%)`, plus an absolute floor of `±0.02 ms`.
That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / drift batch() | 0.55 | 0.00 | -0.55 MB | ±0.50 MB | 🟢 Win (-0.55 MB) |
| Memory / Batch insert 10k rows / resqlite executeBatch() | 0.59 | 0.00 | -0.59 MB | ±0.50 MB | 🟢 Win (-0.59 MB) |
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 0.00 | 0.00 | +0.00 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / sqlite_async executeBatch() | 0.00 | 0.03 | +0.03 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / drift + jsonEncode | 5.84 | 1.17 | -4.67 MB | ±27.26 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite + jsonEn... | 0.00 | 1.50 | +1.50 MB | ±12.53 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / resqlite selectBy... | 0.00 | 0.00 | +0.00 MB | ±1.04 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite3 + jsonEncode | 1.11 | 0.25 | -0.86 MB | ±18.45 MB | ⚪ Within MDE |
| Memory / Select 10k rows → JSON Bytes / sqlite_async + js... | 0.00 | 0.00 | +0.00 MB | ±13.46 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / drift select() | 8.16 | 9.00 | +0.84 MB | ±19.16 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / resqlite select() | 0.00 | 7.09 | +7.09 MB | ±4.70 MB | 🔴 Regression (+7.09 MB) |
| Memory / Select 10k rows → Maps / sqlite3 select() | 2.36 | 2.92 | +0.56 MB | ±3.73 MB | ⚪ Within MDE |
| Memory / Select 10k rows → Maps / sqlite_async select() | 1.00 | 1.00 | +0.00 MB | ±0.51 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / re... | 0.13 | 0.09 | -0.04 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Streaming fan-out (10 streams × 100 writes) / sq... | 0.20 | 0.00 | -0.20 MB | ±0.50 MB | ⚪ Within MDE |

**Memory summary:** 2 wins, 1 regressions, 12 neutral

Threshold uses per-benchmark MDE (95% bootstrap CI half-width on the median), with a `±0.5 MB` floor. RSS deltas are still a **lower bound** on real allocation change — the VM retains heap pages after GC, so sub-MDE wins may be real but invisible here.


## Streaming (Column Granularity) Comparison

| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |
|---|---|---|---|---|---|
| Streaming (Column Granularity) / Disjoint column writes (... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 0 | 0 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Disjoint column writes (... | 3128 | 3268 | +140 | ±100 | 🔴 More re-emits (+140) |
| Streaming (Column Granularity) / Overlapping column write... | 5000 | 5000 | +0 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 30 | 10 | -20 | ±100 | ⚪ Within noise |
| Streaming (Column Granularity) / Overlapping column write... | 3620 | 3142 | -478 | ±100 | 🔴 Invalidation elided (-478) — writes not firing |

**Granularity summary:** 0 fewer-re-emit, 2 more-re-emit, 4 neutral

For **disjoint** workloads, fewer re-emits means tighter dependency tracking — a library with column-level tracking approaches zero. For **overlapping** workloads, the count should stay stable across runs; a drop there means writes are being silently elided.


