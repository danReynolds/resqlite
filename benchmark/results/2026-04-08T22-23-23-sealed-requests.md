# resqlite Benchmark Results

Generated: 2026-04-08T22:23:23.187987

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `sealed-requests`
- Repeats: `1`
- Comparison baseline: `2026-04-08T17-50-03-dedicated-readers-merged.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.37 | 0.59 | 0.08 | 0.15 |
| sqlite3 select() | 0.31 | 0.63 | 0.31 | 0.63 |
| sqlite_async getAll() | 0.21 | 0.33 | 0.06 | 0.06 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.54 | 3.36 | 0.10 | 0.65 |
| sqlite3 select() | 0.82 | 1.37 | 0.82 | 1.37 |
| sqlite_async getAll() | 1.06 | 1.47 | 0.18 | 0.21 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 2.42 | 5.30 | 0.49 | 0.55 |
| sqlite3 select() | 4.03 | 5.05 | 4.03 | 5.05 |
| sqlite_async getAll() | 4.14 | 4.89 | 0.89 | 1.15 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.07 | 0.11 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.40 | 0.67 | 0.40 | 0.67 |
| sqlite_async + jsonEncode | 0.37 | 0.51 | 0.22 | 0.28 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.60 | 0.74 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 2.79 | 6.42 | 2.79 | 6.42 |
| sqlite_async + jsonEncode | 2.88 | 4.98 | 2.14 | 3.26 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 3.21 | 3.67 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 16.14 | 17.91 | 16.14 | 17.91 |
| sqlite_async + jsonEncode | 17.57 | 23.15 | 11.27 | 13.00 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.12 | 0.19 | 0.04 | 0.11 |
| sqlite3 | 0.27 | 0.49 | 0.27 | 0.49 |
| sqlite_async | 0.33 | 0.46 | 0.10 | 0.11 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.06 | 1.35 | 0.39 | 0.42 |
| sqlite3 | 2.05 | 2.33 | 2.05 | 2.33 |
| sqlite_async | 1.76 | 2.22 | 0.54 | 0.57 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.60 | 0.67 | 0.15 | 0.16 |
| sqlite3 | 1.14 | 1.27 | 1.14 | 1.27 |
| sqlite_async | 1.12 | 1.41 | 0.22 | 0.24 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.36 | 0.41 | 0.15 | 0.17 |
| sqlite3 | 0.65 | 0.73 | 0.65 | 0.73 |
| sqlite_async | 0.65 | 0.75 | 0.22 | 0.23 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.38 | 0.48 | 0.15 | 0.16 |
| sqlite3 | 0.63 | 0.70 | 0.63 | 0.70 |
| sqlite_async | 0.65 | 0.82 | 0.23 | 0.24 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

| Rows | resqlite wall | resqlite main | sqlite3 wall | sqlite_async wall |
|---|---|---|---|---|
| 10 | 0.02 | 0.00 | 0.02 | 0.06 |
| 50 | 0.04 | 0.01 | 0.05 | 0.10 |
| 100 | 0.06 | 0.01 | 0.09 | 0.13 |
| 500 | 0.22 | 0.07 | 0.40 | 0.43 |
| 1000 | 0.43 | 0.13 | 0.82 | 0.79 |
| 2000 | 0.89 | 0.26 | 1.64 | 1.65 |
| 5000 | 2.49 | 0.67 | 4.14 | 4.38 |
| 10000 | 5.05 | 1.30 | 8.20 | 9.02 |
| 20000 | 13.52 | 2.63 | 25.16 | 30.11 |

### Bytes (selectBytes → JSON)

| Rows | resqlite wall | sqlite3+json wall | async+json wall |
|---|---|---|---|
| 10 | 0.02 | 0.04 | 0.09 |
| 50 | 0.04 | 0.16 | 0.19 |
| 100 | 0.07 | 0.28 | 0.31 |
| 500 | 0.29 | 1.42 | 1.48 |
| 1000 | 0.59 | 2.80 | 3.06 |
| 2000 | 1.28 | 6.01 | 6.17 |
| 5000 | 3.16 | 16.54 | 16.95 |
| 10000 | 6.66 | 30.57 | 35.50 |
| 20000 | 15.00 | 66.99 | 68.55 |

## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency).

| Concurrency | resqlite wall | resqlite/query | async wall | async/query |
|---|---|---|---|---|
| 1 | 0.30 | 0.30 | 0.58 | 0.58 |
| 2 | 0.34 | 0.17 | 0.69 | 0.34 |
| 4 | 0.44 | 0.11 | 0.73 | 0.18 |
| 8 | 0.87 | 0.11 | 2.84 | 0.35 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 15.47 | 22.22 | 15.47 | 22.22 |
| sqlite3 (no cache) | 23.74 | 24.07 | 23.74 | 24.07 |
| sqlite3 (cached stmt) | 23.32 | 24.42 | 23.32 | 24.42 |
| sqlite_async getAll() | 26.16 | 30.98 | 26.16 | 30.98 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.54 | 2.37 | 1.54 | 2.37 |
| sqlite3 execute() | 5.55 | 7.00 | 5.55 | 7.00 |
| sqlite_async execute() | 4.14 | 5.03 | 4.14 | 5.03 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.07 | 0.07 | 0.07 | 0.07 |
| sqlite3 (manual tx + stmt) | 0.10 | 0.11 | 0.10 | 0.11 |
| sqlite_async executeBatch() | 0.11 | 0.17 | 0.11 | 0.17 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.47 | 0.57 | 0.47 | 0.57 |
| sqlite3 (manual tx + stmt) | 0.54 | 0.71 | 0.54 | 0.71 |
| sqlite_async executeBatch() | 0.56 | 0.72 | 0.56 | 0.72 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.61 | 8.07 | 4.61 | 8.07 |
| sqlite3 (manual tx + stmt) | 4.42 | 4.87 | 4.42 | 4.87 |
| sqlite_async executeBatch() | 5.22 | 5.51 | 5.22 | 5.51 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.05 | 0.06 | 0.05 | 0.06 |
| sqlite_async writeTransaction() | 0.09 | 0.13 | 0.09 | 0.13 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.11 | 0.15 | 0.11 | 0.15 |
| sqlite_async watch() | 0.17 | 0.42 | 0.17 | 0.42 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.06 | 0.14 | 0.06 | 0.14 |
| sqlite_async | 0.07 | 0.26 | 0.07 | 0.26 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.21 | 0.26 | 0.21 | 0.26 |
| sqlite_async | 0.34 | 0.65 | 0.34 | 0.65 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.83 | 2.83 | 2.83 | 2.83 |
| sqlite_async | 11.89 | 11.89 | 11.89 | 11.89 |


## Comparison vs Previous Run

Previous: `2026-04-08T17-50-03-dedicated-readers-merged.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Noise threshold | Stability | Status |
|---|---|---|---|---|---|---|
| Parameterized Queries / 100 queries × ~500 rows each / sq... | 15.98 | 15.47 | -0.51 | ±10% / ±1.60 ms | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / s... | 0.12 | 0.12 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.41 | 0.38 | -0.03 | ±10% / ±0.04 ms | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.39 | 0.36 | -0.03 | ±10% / ±0.04 ms | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.62 | 0.60 | -0.02 | ±10% / ±0.06 ms | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 1.08 | 1.06 | -0.02 | ±10% / ±0.11 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.07 | 0.07 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.59 | 0.60 | +0.01 | ±10% / ±0.06 ms | single run | ⚪ Neutral |
| Select → JSON Bytes / 5000 rows / resqlite selectBytes() | 3.64 | 3.21 | -0.43 | ±10% / ±0.36 ms | single run | 🟢 Win (-12%) |
| Select → Maps / 100 rows / resqlite select() | 0.38 | 0.37 | -0.01 | ±10% / ±0.04 ms | single run | ⚪ Neutral |
| Select → Maps / 1000 rows / resqlite select() | 0.46 | 0.54 | +0.08 | ±10% / ±0.05 ms | single run | 🔴 Regression (+17%) |
| Select → Maps / 5000 rows / resqlite select() | 2.52 | 2.42 | -0.10 | ±10% / ±0.25 ms | single run | ⚪ Neutral |
| Streaming / Fan-out (10 streams) / resqlite | 0.20 | 0.21 | +0.01 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Streaming / Initial Emission / resqlite stream() | 0.13 | 0.11 | -0.02 | ±10% / ±0.02 ms | single run | 🟢 Win (-15%) |
| Streaming / Invalidation Latency / resqlite | 0.07 | 0.06 | -0.01 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Streaming / Stream Churn (100 cycles) / resqlite | 3.99 | 2.83 | -1.16 | ±10% / ±0.40 ms | single run | 🟢 Win (-29%) |
| Write Performance / Batch Insert (100 rows) / resqlite exe... | 0.07 | 0.07 | +0.00 | ±10% / ±0.02 ms | single run | ⚪ Neutral |
| Write Performance / Batch Insert (1000 rows) / resqlite ex... | 0.51 | 0.47 | -0.04 | ±10% / ±0.05 ms | single run | ⚪ Neutral |
| Write Performance / Batch Insert (10000 rows) / resqlite e... | 4.95 | 4.61 | -0.34 | ±10% / ±0.50 ms | single run | ⚪ Neutral |
| Write Performance / Interactive Transaction (insert + sel... | 0.08 | 0.05 | -0.03 | ±10% / ±0.02 ms | single run | 🟢 Win (-38%) |
| Write Performance / Single Inserts (100 sequential) / sql... | 1.96 | 1.54 | -0.42 | ±10% / ±0.20 ms | single run | 🟢 Win (-21%) |

**Summary:** 5 wins, 1 regressions, 15 neutral

Comparison threshold uses `max(10%, 3 × current MAD%)`, plus an absolute floor of `±0.02 ms`.
That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


