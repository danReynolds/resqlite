# resqlite Benchmark Results

Generated: 2026-04-09T10:23:18.339405

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `bench-improvements`
- Repeats: `1`
- Comparison baseline: `2026-04-09T10-13-29-MacBook-Pro-14.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.42 | 0.66 | 0.11 | 0.19 |
| sqlite3 select() | 0.38 | 0.65 | 0.38 | 0.65 |
| sqlite_async getAll() | 0.36 | 0.64 | 0.09 | 0.28 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.42 | 0.55 | 0.10 | 0.12 |
| sqlite3 select() | 0.85 | 1.14 | 0.85 | 1.14 |
| sqlite_async getAll() | 0.85 | 1.17 | 0.17 | 0.29 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 2.35 | 5.38 | 0.49 | 0.55 |
| sqlite3 select() | 4.04 | 4.33 | 4.04 | 4.33 |
| sqlite_async getAll() | 4.26 | 4.74 | 0.89 | 0.98 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.07 | 0.09 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.39 | 0.62 | 0.39 | 0.62 |
| sqlite_async + jsonEncode | 0.35 | 0.49 | 0.22 | 0.27 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.57 | 0.62 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 2.81 | 6.48 | 2.81 | 6.48 |
| sqlite_async + jsonEncode | 3.09 | 5.46 | 2.14 | 3.79 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 3.36 | 4.14 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 16.12 | 18.41 | 16.12 | 18.41 |
| sqlite_async + jsonEncode | 17.38 | 19.47 | 11.10 | 12.56 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.12 | 0.20 | 0.04 | 0.09 |
| sqlite3 | 0.27 | 0.43 | 0.27 | 0.43 |
| sqlite_async | 0.32 | 0.51 | 0.10 | 0.13 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.12 | 1.21 | 0.40 | 0.41 |
| sqlite3 | 2.07 | 2.19 | 2.07 | 2.19 |
| sqlite_async | 1.84 | 2.34 | 0.54 | 0.61 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.62 | 0.68 | 0.15 | 0.17 |
| sqlite3 | 1.14 | 1.30 | 1.14 | 1.30 |
| sqlite_async | 1.20 | 1.41 | 0.22 | 0.31 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.39 | 0.42 | 0.15 | 0.16 |
| sqlite3 | 0.67 | 0.78 | 0.67 | 0.78 |
| sqlite_async | 0.65 | 0.80 | 0.22 | 0.24 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.41 | 0.50 | 0.15 | 0.16 |
| sqlite3 | 0.64 | 0.68 | 0.64 | 0.68 |
| sqlite_async | 0.68 | 0.94 | 0.23 | 0.27 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

| Rows | resqlite wall | resqlite main | sqlite3 wall | sqlite_async wall |
|---|---|---|---|---|
| 10 | 0.02 | 0.00 | 0.02 | 0.07 |
| 50 | 0.04 | 0.01 | 0.05 | 0.09 |
| 100 | 0.06 | 0.01 | 0.09 | 0.13 |
| 500 | 0.22 | 0.07 | 0.41 | 0.44 |
| 1000 | 0.43 | 0.13 | 0.85 | 0.83 |
| 2000 | 0.94 | 0.26 | 1.66 | 1.70 |
| 5000 | 2.48 | 0.65 | 4.21 | 4.21 |
| 10000 | 5.15 | 1.31 | 8.84 | 9.43 |
| 20000 | 13.74 | 2.69 | 24.84 | 35.91 |

### Bytes (selectBytes → JSON)

| Rows | resqlite wall | sqlite3+json wall | async+json wall |
|---|---|---|---|
| 10 | 0.02 | 0.04 | 0.09 |
| 50 | 0.05 | 0.19 | 0.22 |
| 100 | 0.07 | 0.28 | 0.34 |
| 500 | 0.29 | 1.57 | 1.67 |
| 1000 | 0.62 | 3.07 | 3.23 |
| 2000 | 1.27 | 6.32 | 6.35 |
| 5000 | 3.20 | 16.64 | 17.93 |
| 10000 | 6.49 | 31.98 | 33.02 |
| 20000 | 12.29 | 64.86 | 71.10 |

## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency).

| Concurrency | resqlite wall | resqlite/query | async wall | async/query |
|---|---|---|---|---|
| 1 | 0.29 | 0.29 | 0.59 | 0.59 |
| 2 | 0.33 | 0.17 | 0.63 | 0.32 |
| 4 | 0.40 | 0.10 | 0.76 | 0.19 |
| 8 | 0.75 | 0.09 | 2.10 | 0.26 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead of the reader pool.

| Metric | Value |
|---|---:|
| resqlite qps | 77676 |
| resqlite per query | 0.013 ms |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 14.81 | 15.18 | 14.81 | 15.18 |
| sqlite3 (no cache) | 24.68 | 27.34 | 24.68 | 27.34 |
| sqlite3 (cached stmt) | 24.34 | 31.00 | 24.34 | 31.00 |
| sqlite_async getAll() | 27.52 | 35.55 | 27.52 | 35.55 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 6.04 | 18.15 | 6.04 | 18.15 |
| sqlite3 execute() | 8.30 | 15.31 | 8.30 | 15.31 |
| sqlite_async execute() | 6.57 | 17.12 | 6.57 | 17.12 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.10 | 0.13 | 0.10 | 0.13 |
| sqlite3 (manual tx + stmt) | 0.12 | 0.18 | 0.12 | 0.18 |
| sqlite_async executeBatch() | 0.15 | 0.31 | 0.15 | 0.31 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.71 | 1.05 | 0.71 | 1.05 |
| sqlite3 (manual tx + stmt) | 0.79 | 1.69 | 0.79 | 1.69 |
| sqlite_async executeBatch() | 0.73 | 0.94 | 0.73 | 0.94 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 5.64 | 9.23 | 5.64 | 9.23 |
| sqlite3 (manual tx + stmt) | 5.21 | 6.78 | 5.21 | 6.78 |
| sqlite_async executeBatch() | 6.39 | 8.25 | 6.39 | 8.25 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.11 | 0.20 | 0.11 | 0.20 |
| sqlite_async writeTransaction() | 0.15 | 0.26 | 0.15 | 0.26 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.06 | 0.14 | 0.06 | 0.14 |
| sqlite_async watch() | 0.18 | 0.35 | 0.18 | 0.35 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.11 | 0.25 | 0.11 | 0.25 |
| sqlite_async | 0.14 | 0.28 | 0.14 | 0.28 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.31 | 0.47 | 0.31 | 0.47 |
| sqlite_async | 0.40 | 0.94 | 0.40 | 0.94 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.24 | 4.24 | 4.24 | 4.24 |
| sqlite_async | 17.83 | 17.83 | 17.83 | 17.83 |


## Comparison vs Previous Run

Previous: `2026-04-09T10-13-29-MacBook-Pro-14.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Noise threshold | Stability | Status |
|---|---|---|---|---|---|---|
| Parameterized Queries / 100 queries × ~500 rows each / sq... | 14.91 | 14.81 | -0.10 | ±10% / ±1.49 ms | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / s... | 0.11 | 0.12 | +0.01 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.39 | 0.41 | +0.02 | ±10% / ±0.04 ms | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.38 | 0.39 | +0.01 | ±10% / ±0.04 ms | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.63 | 0.62 | -0.01 | ±10% / ±0.06 ms | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 1.19 | 1.12 | -0.07 | ±10% / ±0.12 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.07 | 0.07 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.61 | 0.57 | -0.04 | ±10% / ±0.06 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 5000 rows / resqlite selectBytes() | 3.12 | 3.36 | +0.24 | ±10% / ±0.34 ms | single run | ⚪ Neutral |
| Select → Maps / 100 rows / resqlite select() | 0.49 | 0.42 | -0.07 | ±10% / ±0.05 ms | single run | 🟢 Win (-14%) |
| Select → Maps / 1000 rows / resqlite select() | 0.48 | 0.42 | -0.06 | ±10% / ±0.05 ms | single run | 🟢 Win (-13%) |
| Select → Maps / 5000 rows / resqlite select() | 2.41 | 2.35 | -0.06 | ±10% / ±0.24 ms | single run | ⚪ Neutral |
| Streaming / Fan-out (10 streams) / resqlite | 0.24 | 0.31 | +0.07 | ±10% / ±0.03 ms | single run | 🔴 Regression (+29%) |
| Streaming / Initial Emission / resqlite stream() | 0.10 | 0.06 | -0.04 | ±10% / ±0.02 ms | single run | 🟢 Win (-40%) |
| Streaming / Invalidation Latency / resqlite | 0.09 | 0.11 | +0.02 | ±10% / ±0.02 ms | single run | 🔴 Regression (+22%) |
| Streaming / Stream Churn (100 cycles) / resqlite | 3.71 | 4.24 | +0.53 | ±10% / ±0.42 ms | single run | 🔴 Regression (+14%) |
| Write Performance / Batch Insert (100 rows) / resqlite exe... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Write Performance / Batch Insert (1000 rows) / resqlite ex... | 0.75 | 0.71 | -0.04 | ±10% / ±0.08 ms | single run | ⚪ Neutral |
| Write Performance / Batch Insert (10000 rows) / resqlite e... | 4.58 | 5.64 | +1.06 | ±10% / ±0.56 ms | single run | 🔴 Regression (+23%) |
| Write Performance / Interactive Transaction (insert + sel... | 0.08 | 0.11 | +0.03 | ±10% / ±0.02 ms | single run | 🔴 Regression (+38%) |
| Write Performance / Single Inserts (100 sequential) / sql... | 2.29 | 6.04 | +3.75 | ±10% / ±0.60 ms | single run | 🔴 Regression (+164%) |

**Summary:** 3 wins, 6 regressions, 12 neutral

Comparison threshold uses `max(10%, 3 × current MAD%)`, plus an absolute floor of `±0.02 ms`.
That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


