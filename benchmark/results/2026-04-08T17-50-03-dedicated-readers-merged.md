# resqlite Benchmark Results

Generated: 2026-04-08T17:50:03.461987

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `dedicated-readers-merged`
- Repeats: `1`
- Comparison baseline: `2026-04-08T17-36-27-exp030-adopted.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.38 | 0.84 | 0.10 | 0.20 |
| sqlite3 select() | 0.34 | 0.77 | 0.34 | 0.77 |
| sqlite_async getAll() | 0.26 | 0.58 | 0.06 | 0.08 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.46 | 0.65 | 0.10 | 0.12 |
| sqlite3 select() | 0.89 | 1.18 | 0.89 | 1.18 |
| sqlite_async getAll() | 0.91 | 1.37 | 0.17 | 0.27 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 2.52 | 5.81 | 0.50 | 0.56 |
| sqlite3 select() | 4.10 | 4.33 | 4.10 | 4.33 |
| sqlite_async getAll() | 4.70 | 5.90 | 0.96 | 1.18 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.07 | 0.08 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.41 | 0.63 | 0.41 | 0.63 |
| sqlite_async + jsonEncode | 0.37 | 0.55 | 0.22 | 0.26 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.59 | 0.69 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 2.90 | 6.07 | 2.90 | 6.07 |
| sqlite_async + jsonEncode | 3.20 | 6.37 | 2.22 | 4.85 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 3.64 | 4.21 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 16.79 | 18.10 | 16.79 | 18.10 |
| sqlite_async + jsonEncode | 18.51 | 19.55 | 11.13 | 12.46 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.12 | 0.23 | 0.04 | 0.13 |
| sqlite3 | 0.27 | 0.41 | 0.27 | 0.41 |
| sqlite_async | 0.34 | 0.42 | 0.10 | 0.11 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.08 | 1.30 | 0.40 | 0.42 |
| sqlite3 | 2.06 | 2.31 | 2.06 | 2.31 |
| sqlite_async | 1.91 | 2.19 | 0.54 | 0.61 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.62 | 0.77 | 0.15 | 0.16 |
| sqlite3 | 1.19 | 1.42 | 1.19 | 1.42 |
| sqlite_async | 1.32 | 1.50 | 0.22 | 0.33 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.39 | 0.54 | 0.15 | 0.17 |
| sqlite3 | 0.69 | 0.78 | 0.69 | 0.78 |
| sqlite_async | 0.68 | 0.95 | 0.22 | 0.28 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.41 | 0.49 | 0.15 | 0.20 |
| sqlite3 | 0.65 | 0.73 | 0.65 | 0.73 |
| sqlite_async | 0.68 | 0.79 | 0.23 | 0.23 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

| Rows | resqlite wall | resqlite main | sqlite3 wall | sqlite_async wall |
|---|---|---|---|---|
| 10 | 0.02 | 0.00 | 0.02 | 0.07 |
| 50 | 0.04 | 0.01 | 0.05 | 0.10 |
| 100 | 0.06 | 0.01 | 0.09 | 0.12 |
| 500 | 0.22 | 0.06 | 0.41 | 0.42 |
| 1000 | 0.42 | 0.13 | 0.86 | 0.83 |
| 2000 | 0.93 | 0.26 | 1.65 | 1.70 |
| 5000 | 2.72 | 0.67 | 4.22 | 4.63 |
| 10000 | 5.26 | 1.31 | 8.44 | 9.70 |
| 20000 | 13.03 | 2.64 | 21.93 | 31.30 |

### Bytes (selectBytes → JSON)

| Rows | resqlite wall | sqlite3+json wall | async+json wall |
|---|---|---|---|
| 10 | 0.02 | 0.04 | 0.12 |
| 50 | 0.05 | 0.15 | 0.19 |
| 100 | 0.07 | 0.29 | 0.33 |
| 500 | 0.30 | 1.49 | 1.68 |
| 1000 | 0.63 | 2.83 | 3.08 |
| 2000 | 1.32 | 7.99 | 6.46 |
| 5000 | 3.20 | 17.22 | 17.90 |
| 10000 | 6.52 | 30.12 | 33.44 |
| 20000 | 14.79 | 70.03 | 76.83 |

## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency).

| Concurrency | resqlite wall | resqlite/query | async wall | async/query |
|---|---|---|---|---|
| 1 | 0.30 | 0.30 | 0.70 | 0.70 |
| 2 | 0.37 | 0.19 | 0.81 | 0.40 |
| 4 | 0.42 | 0.11 | 1.08 | 0.27 |
| 8 | 1.09 | 0.14 | 2.26 | 0.28 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 15.98 | 16.60 | 15.98 | 16.60 |
| sqlite3 (no cache) | 24.55 | 25.28 | 24.55 | 25.28 |
| sqlite3 (cached stmt) | 24.00 | 24.47 | 24.00 | 24.47 |
| sqlite_async getAll() | 28.17 | 30.29 | 28.17 | 30.29 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.96 | 2.19 | 1.96 | 2.19 |
| sqlite3 execute() | 5.75 | 6.79 | 5.75 | 6.79 |
| sqlite_async execute() | 4.66 | 5.30 | 4.66 | 5.30 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.07 | 0.09 | 0.07 | 0.09 |
| sqlite3 (manual tx + stmt) | 0.13 | 0.19 | 0.13 | 0.19 |
| sqlite_async executeBatch() | 0.11 | 0.19 | 0.11 | 0.19 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.51 | 0.59 | 0.51 | 0.59 |
| sqlite3 (manual tx + stmt) | 0.61 | 0.73 | 0.61 | 0.73 |
| sqlite_async executeBatch() | 0.64 | 0.75 | 0.64 | 0.75 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.95 | 8.31 | 4.95 | 8.31 |
| sqlite3 (manual tx + stmt) | 4.78 | 5.15 | 4.78 | 5.15 |
| sqlite_async executeBatch() | 6.13 | 7.02 | 6.13 | 7.02 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.08 | 0.14 | 0.08 | 0.14 |
| sqlite_async writeTransaction() | 0.14 | 0.33 | 0.14 | 0.33 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.13 | 0.23 | 0.13 | 0.23 |
| sqlite_async watch() | 0.30 | 0.70 | 0.30 | 0.70 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.07 | 0.09 | 0.07 | 0.09 |
| sqlite_async | 0.14 | 0.44 | 0.14 | 0.44 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.20 | 0.44 | 0.20 | 0.44 |
| sqlite_async | 0.43 | 0.69 | 0.43 | 0.69 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 3.99 | 3.99 | 3.99 | 3.99 |
| sqlite_async | 14.73 | 14.73 | 14.73 | 14.73 |


## Comparison vs Previous Run

Previous: `2026-04-08T17-36-27-exp030-adopted.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Noise threshold | Stability | Status |
|---|---|---|---|---|---|---|
| Parameterized Queries / 100 queries × ~500 rows each / sq... | 15.48 | 15.98 | +0.50 | ±10% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / s... | 0.14 | 0.12 | -0.02 | ±10% | single run | 🟢 Win (-14%) |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.46 | 0.41 | -0.05 | ±10% | single run | 🟢 Win (-11%) |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.41 | 0.39 | -0.02 | ±10% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.65 | 0.62 | -0.03 | ±10% | single run | ⚪ Neutral |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 1.06 | 1.08 | +0.02 | ±10% | single run | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.07 | 0.07 | +0.00 | ±10% | single run | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.67 | 0.59 | -0.08 | ±10% | single run | 🟢 Win (-12%) |
| Select → JSON Bytes / 5000 rows / resqlite selectBytes() | 3.42 | 3.64 | +0.22 | ±10% | single run | ⚪ Neutral |
| Select → Maps / 100 rows / resqlite select() | 0.61 | 0.38 | -0.23 | ±10% | single run | 🟢 Win (-38%) |
| Select → Maps / 1000 rows / resqlite select() | 0.42 | 0.46 | +0.04 | ±10% | single run | ⚪ Neutral |
| Select → Maps / 5000 rows / resqlite select() | 2.38 | 2.52 | +0.14 | ±10% | single run | ⚪ Neutral |
| Streaming / Fan-out (10 streams) / resqlite | 0.21 | 0.20 | -0.01 | ±10% | single run | ⚪ Neutral |
| Streaming / Initial Emission / resqlite stream() | 0.14 | 0.13 | -0.01 | ±10% | single run | ⚪ Neutral |
| Streaming / Invalidation Latency / resqlite | 0.08 | 0.07 | -0.01 | ±10% | single run | 🟢 Win (-12%) |
| Streaming / Stream Churn (100 cycles) / resqlite | 4.51 | 3.99 | -0.52 | ±10% | single run | 🟢 Win (-12%) |
| Write Performance / Batch Insert (100 rows) / resqlite exe... | 0.07 | 0.07 | +0.00 | ±10% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (1000 rows) / resqlite ex... | 0.50 | 0.51 | +0.01 | ±10% | single run | ⚪ Neutral |
| Write Performance / Batch Insert (10000 rows) / resqlite e... | 5.20 | 4.95 | -0.25 | ±10% | single run | ⚪ Neutral |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.08 | +0.02 | ±10% | single run | 🔴 Regression (+33%) |
| Write Performance / Single Inserts (100 sequential) / sql... | 2.30 | 1.96 | -0.34 | ±10% | single run | 🟢 Win (-15%) |

**Summary:** 7 wins, 1 regressions, 13 neutral

Comparison threshold uses `max(10%, 3 × current MAD%)` for each benchmark.
That keeps stable cases sensitive while treating noisy cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


