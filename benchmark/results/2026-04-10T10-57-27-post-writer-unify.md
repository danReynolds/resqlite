# resqlite Benchmark Results

Generated: 2026-04-10T10:57:27.706152

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `post-writer-unify`
- Repeats: `3`
- Comparison baseline: `2026-04-10T10-55-44-post-writer-unify.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.05 | 0.06 | 0.01 | 0.01 |
| sqlite3 select() | 0.08 | 0.10 | 0.08 | 0.10 |
| sqlite_async getAll() | 0.10 | 0.14 | 0.02 | 0.02 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.40 | 0.43 | 0.10 | 0.10 |
| sqlite3 select() | 0.77 | 0.88 | 0.77 | 0.88 |
| sqlite_async getAll() | 0.73 | 0.91 | 0.17 | 0.18 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 2.35 | 5.32 | 0.51 | 0.54 |
| sqlite3 select() | 3.96 | 4.16 | 3.96 | 4.16 |
| sqlite_async getAll() | 3.90 | 4.42 | 0.85 | 0.94 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.07 | 0.07 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.27 | 0.32 | 0.27 | 0.32 |
| sqlite_async + jsonEncode | 0.29 | 0.35 | 0.21 | 0.23 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.56 | 0.68 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 2.75 | 5.21 | 2.75 | 5.21 |
| sqlite_async + jsonEncode | 2.73 | 5.09 | 2.06 | 4.05 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 2.92 | 3.73 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 15.72 | 17.35 | 15.72 | 17.35 |
| sqlite_async + jsonEncode | 16.64 | 17.52 | 10.48 | 10.96 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.12 | 0.12 | 0.05 | 0.05 |
| sqlite3 | 0.23 | 0.24 | 0.23 | 0.24 |
| sqlite_async | 0.26 | 0.28 | 0.09 | 0.09 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.02 | 1.05 | 0.40 | 0.41 |
| sqlite3 | 1.97 | 1.99 | 1.97 | 1.99 |
| sqlite_async | 1.64 | 1.85 | 0.54 | 0.55 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.59 | 0.63 | 0.15 | 0.16 |
| sqlite3 | 1.10 | 1.13 | 1.10 | 1.13 |
| sqlite_async | 1.08 | 1.18 | 0.22 | 0.24 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.34 | 0.35 | 0.15 | 0.16 |
| sqlite3 | 0.65 | 0.71 | 0.65 | 0.71 |
| sqlite_async | 0.62 | 0.79 | 0.22 | 0.25 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.35 | 0.36 | 0.15 | 0.15 |
| sqlite3 | 0.61 | 0.71 | 0.61 | 0.71 |
| sqlite_async | 0.61 | 0.64 | 0.23 | 0.23 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

| Rows | resqlite wall | resqlite main | sqlite3 wall | sqlite_async wall |
|---|---|---|---|---|
| 10 | 0.01 | 0.00 | 0.01 | 0.03 |
| 50 | 0.03 | 0.01 | 0.04 | 0.06 |
| 100 | 0.05 | 0.01 | 0.09 | 0.09 |
| 500 | 0.21 | 0.06 | 0.39 | 0.38 |
| 1000 | 0.42 | 0.13 | 0.81 | 0.74 |
| 2000 | 0.88 | 0.26 | 1.61 | 1.50 |
| 5000 | 2.37 | 0.66 | 4.02 | 3.83 |
| 10000 | 5.59 | 1.31 | 8.23 | 8.84 |
| 20000 | 12.97 | 2.60 | 21.19 | 25.66 |

### Bytes (selectBytes → JSON)

| Rows | resqlite wall | sqlite3+json wall | async+json wall |
|---|---|---|---|
| 10 | 0.02 | 0.04 | 0.05 |
| 50 | 0.04 | 0.14 | 0.16 |
| 100 | 0.07 | 0.29 | 0.28 |
| 500 | 0.29 | 1.36 | 1.33 |
| 1000 | 0.55 | 2.72 | 2.69 |
| 2000 | 1.23 | 5.65 | 6.20 |
| 5000 | 2.92 | 16.27 | 15.60 |
| 10000 | 6.32 | 29.46 | 31.29 |
| 20000 | 12.31 | 65.61 | 66.65 |

## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency).

| Concurrency | resqlite wall | resqlite/query | async wall | async/query |
|---|---|---|---|---|
| 1 | 0.29 | 0.29 | 0.54 | 0.54 |
| 2 | 0.32 | 0.16 | 0.58 | 0.29 |
| 4 | 0.38 | 0.09 | 0.64 | 0.16 |
| 8 | 0.71 | 0.09 | 1.24 | 0.15 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead of the reader pool.

| Metric | Value |
|---|---:|
| resqlite qps | 107921 |
| resqlite per query | 0.009 ms |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 14.96 | 15.45 | 14.96 | 15.45 |
| sqlite3 (no cache) | 23.57 | 23.84 | 23.57 | 23.84 |
| sqlite3 (cached stmt) | 23.36 | 23.70 | 23.36 | 23.70 |
| sqlite_async getAll() | 23.89 | 25.46 | 23.89 | 25.46 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.56 | 1.95 | 1.56 | 1.95 |
| sqlite3 execute() | 3.94 | 6.22 | 3.94 | 6.22 |
| sqlite_async execute() | 2.88 | 3.49 | 2.88 | 3.49 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.05 | 0.06 | 0.05 | 0.06 |
| sqlite3 (manual tx + stmt) | 0.09 | 0.10 | 0.09 | 0.10 |
| sqlite_async executeBatch() | 0.09 | 0.11 | 0.09 | 0.11 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.45 | 0.48 | 0.45 | 0.48 |
| sqlite3 (manual tx + stmt) | 0.52 | 0.56 | 0.52 | 0.56 |
| sqlite_async executeBatch() | 0.53 | 0.58 | 0.53 | 0.58 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.38 | 5.00 | 4.38 | 5.00 |
| sqlite3 (manual tx + stmt) | 4.33 | 4.63 | 4.33 | 4.63 |
| sqlite_async executeBatch() | 4.78 | 5.33 | 4.78 | 5.33 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.05 | 0.06 | 0.05 | 0.06 |
| sqlite_async writeTransaction() | 0.08 | 0.09 | 0.08 | 0.09 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.03 | 0.04 | 0.03 | 0.04 |
| sqlite_async watch() | 0.11 | 0.15 | 0.11 | 0.15 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.04 | 0.05 | 0.04 | 0.05 |
| sqlite_async | 0.06 | 0.14 | 0.06 | 0.14 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.13 | 0.17 | 0.13 | 0.17 |
| sqlite_async | 0.23 | 0.29 | 0.23 | 0.29 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.72 | 1.72 | 1.72 | 1.72 |
| sqlite_async | 7.99 | 7.99 | 7.99 | 7.99 |


## Repeat Stability

These rows summarize resqlite wall medians across repeated full-suite runs.
Use this section to judge whether small deltas are real or just noise.

| Benchmark | Median (ms) | Min | Max | Range | MAD | Stability |
|---|---|---|---|---|---|---|
| Parameterized Queries / 100 queries × ~500 rows each / resqlite sel... | 14.96 | 14.73 | 14.96 | 1.5% | 0.0% | stable |
| Point Query Throughput / resqlite qps | 94733.00 | 93545.00 | 107921.00 | 15.2% | 1.3% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.12 | 0.11 | 0.12 | 8.3% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.35 | 0.35 | 0.35 | 0.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.35 | 0.34 | 0.35 | 2.9% | 0.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.61 | 0.59 | 0.61 | 3.3% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 1.02 | 1.02 | 1.06 | 3.9% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.07 | 0.07 | 0.07 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.56 | 0.55 | 0.56 | 1.8% | 0.0% | stable |
| Select → JSON Bytes / 5000 rows / resqlite selectBytes() | 2.93 | 2.92 | 3.01 | 3.1% | 0.3% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.06 | 0.05 | 0.40 | 583.3% | 16.7% | noisy |
| Select → Maps / 1000 rows / resqlite select() | 0.39 | 0.39 | 0.40 | 2.6% | 0.0% | stable |
| Select → Maps / 5000 rows / resqlite select() | 2.26 | 2.20 | 2.35 | 6.6% | 2.7% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.18 | 0.13 | 0.35 | 122.2% | 27.8% | noisy |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | 0.06 | 100.0% | 0.0% | stable |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.04 | 0.05 | 20.0% | 0.0% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.40 | 1.72 | 2.41 | 28.8% | 0.4% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.05 | 0.05 | 0.06 | 20.0% | 0.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.45 | 0.45 | 0.46 | 2.2% | 0.0% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.38 | 4.37 | 4.39 | 0.5% | 0.2% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05 | 0.06 | 20.0% | 0.0% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.57 | 1.56 | 1.57 | 0.6% | 0.0% | stable |


## Comparison vs Previous Run

Previous: `2026-04-10T10-55-44-post-writer-unify.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Noise threshold | Stability | Status |
|---|---|---|---|---|---|---|
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.71 | 14.96 | +0.25 | ±10% / ±1.50 ms | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 104932.00 | 94733.00 | -10199.00 | ±10% / ±10493.20 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.12 | 0.12 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.35 | 0.35 | +0.00 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.35 | 0.35 | +0.00 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.60 | 0.61 | +0.01 | ±10% / ±0.06 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 1.03 | 1.02 | -0.01 | ±10% / ±0.10 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.06 | 0.07 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.56 | 0.56 | +0.00 | ±10% / ±0.06 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 5000 rows / resqlite selectBytes() | 2.93 | 2.93 | +0.00 | ±10% / ±0.29 ms | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.06 | +0.01 | ±50% / ±0.03 ms | noisy | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.39 | 0.39 | +0.00 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Select → Maps / 5000 rows / resqlite select() | 2.22 | 2.26 | +0.04 | ±10% / ±0.23 ms | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.15 | 0.18 | +0.03 | ±83% / ±0.15 ms | noisy | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.05 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.85 | 2.40 | +0.55 | ±10% / ±0.24 ms | stable | 🔴 Regression (+30%) |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.05 | -0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.44 | 0.45 | +0.01 | ±10% / ±0.05 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.38 | 4.38 | +0.00 | ±10% / ±0.44 ms | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.54 | 1.57 | +0.03 | ±10% / ±0.16 ms | stable | ⚪ Within noise |

**Summary:** 0 wins, 1 regressions, 21 neutral

Comparison threshold uses `max(10%, 3 × current MAD%)`, plus an absolute floor of `±0.02 ms`.
That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


