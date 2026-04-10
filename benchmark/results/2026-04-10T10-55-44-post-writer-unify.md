# resqlite Benchmark Results

Generated: 2026-04-10T10:55:44.094740

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `post-writer-unify`
- Repeats: `3`
- Comparison baseline: `2026-04-10T10-27-41-post-byte-threshold.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.05 | 0.07 | 0.01 | 0.01 |
| sqlite3 select() | 0.09 | 0.10 | 0.09 | 0.10 |
| sqlite_async getAll() | 0.09 | 0.09 | 0.02 | 0.02 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.39 | 0.40 | 0.10 | 0.10 |
| sqlite3 select() | 0.80 | 0.82 | 0.80 | 0.82 |
| sqlite_async getAll() | 0.72 | 0.78 | 0.17 | 0.17 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 2.22 | 4.83 | 0.50 | 0.51 |
| sqlite3 select() | 4.12 | 4.31 | 4.12 | 4.31 |
| sqlite_async getAll() | 3.81 | 4.24 | 0.82 | 0.86 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.06 | 0.07 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.28 | 0.29 | 0.28 | 0.29 |
| sqlite_async + jsonEncode | 0.28 | 0.30 | 0.21 | 0.22 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.56 | 0.60 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 2.72 | 5.44 | 2.72 | 5.44 |
| sqlite_async + jsonEncode | 2.75 | 5.55 | 2.09 | 4.26 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 2.93 | 3.88 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 15.91 | 17.03 | 15.91 | 17.03 |
| sqlite_async + jsonEncode | 17.04 | 18.35 | 10.39 | 11.21 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.12 | 0.13 | 0.05 | 0.06 |
| sqlite3 | 0.24 | 0.27 | 0.24 | 0.27 |
| sqlite_async | 0.28 | 0.29 | 0.10 | 0.10 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.03 | 1.05 | 0.40 | 0.40 |
| sqlite3 | 2.05 | 2.09 | 2.05 | 2.09 |
| sqlite_async | 1.64 | 1.68 | 0.53 | 0.54 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.60 | 0.64 | 0.15 | 0.16 |
| sqlite3 | 1.17 | 1.21 | 1.17 | 1.21 |
| sqlite_async | 1.06 | 1.06 | 0.22 | 0.22 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.35 | 0.36 | 0.15 | 0.16 |
| sqlite3 | 0.67 | 0.68 | 0.67 | 0.68 |
| sqlite_async | 0.60 | 0.61 | 0.22 | 0.22 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.35 | 0.36 | 0.15 | 0.15 |
| sqlite3 | 0.64 | 0.65 | 0.64 | 0.65 |
| sqlite_async | 0.60 | 0.61 | 0.23 | 0.23 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

| Rows | resqlite wall | resqlite main | sqlite3 wall | sqlite_async wall |
|---|---|---|---|---|
| 10 | 0.01 | 0.00 | 0.01 | 0.03 |
| 50 | 0.03 | 0.01 | 0.05 | 0.06 |
| 100 | 0.05 | 0.01 | 0.08 | 0.09 |
| 500 | 0.21 | 0.06 | 0.43 | 0.39 |
| 1000 | 0.42 | 0.13 | 0.84 | 0.75 |
| 2000 | 0.88 | 0.26 | 1.72 | 1.48 |
| 5000 | 2.39 | 0.65 | 4.26 | 4.02 |
| 10000 | 5.68 | 1.31 | 8.59 | 8.65 |
| 20000 | 13.24 | 2.65 | 23.06 | 26.14 |

### Bytes (selectBytes → JSON)

| Rows | resqlite wall | sqlite3+json wall | async+json wall |
|---|---|---|---|
| 10 | 0.01 | 0.03 | 0.05 |
| 50 | 0.04 | 0.14 | 0.15 |
| 100 | 0.07 | 0.28 | 0.29 |
| 500 | 0.28 | 1.39 | 1.37 |
| 1000 | 0.55 | 2.74 | 2.73 |
| 2000 | 1.17 | 5.77 | 5.80 |
| 5000 | 2.93 | 16.49 | 16.68 |
| 10000 | 6.45 | 31.09 | 31.96 |
| 20000 | 12.20 | 63.60 | 67.80 |

## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency).

| Concurrency | resqlite wall | resqlite/query | async wall | async/query |
|---|---|---|---|---|
| 1 | 0.28 | 0.28 | 0.55 | 0.55 |
| 2 | 0.31 | 0.16 | 0.57 | 0.29 |
| 4 | 0.36 | 0.09 | 0.63 | 0.16 |
| 8 | 0.66 | 0.08 | 1.20 | 0.15 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead of the reader pool.

| Metric | Value |
|---|---:|
| resqlite qps | 104932 |
| resqlite per query | 0.010 ms |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 14.71 | 15.07 | 14.71 | 15.07 |
| sqlite3 (no cache) | 25.02 | 25.40 | 25.02 | 25.40 |
| sqlite3 (cached stmt) | 24.70 | 25.03 | 24.70 | 25.03 |
| sqlite_async getAll() | 24.28 | 24.70 | 24.28 | 24.70 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.54 | 2.12 | 1.54 | 2.12 |
| sqlite3 execute() | 3.63 | 5.64 | 3.63 | 5.64 |
| sqlite_async execute() | 2.88 | 3.50 | 2.88 | 3.50 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.06 | 0.06 | 0.06 | 0.06 |
| sqlite3 (manual tx + stmt) | 0.09 | 0.09 | 0.09 | 0.09 |
| sqlite_async executeBatch() | 0.09 | 0.11 | 0.09 | 0.11 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.44 | 0.46 | 0.44 | 0.46 |
| sqlite3 (manual tx + stmt) | 0.50 | 0.52 | 0.50 | 0.52 |
| sqlite_async executeBatch() | 0.53 | 0.54 | 0.53 | 0.54 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.38 | 5.73 | 4.38 | 5.73 |
| sqlite3 (manual tx + stmt) | 4.42 | 5.27 | 4.42 | 5.27 |
| sqlite_async executeBatch() | 4.87 | 5.11 | 4.87 | 5.11 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.05 | 0.08 | 0.05 | 0.08 |
| sqlite_async writeTransaction() | 0.08 | 0.11 | 0.08 | 0.11 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.03 | 0.04 | 0.03 | 0.04 |
| sqlite_async watch() | 0.10 | 0.12 | 0.10 | 0.12 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.04 | 0.05 | 0.04 | 0.05 |
| sqlite_async | 0.06 | 0.09 | 0.06 | 0.09 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.15 | 0.22 | 0.15 | 0.22 |
| sqlite_async | 0.27 | 0.34 | 0.27 | 0.34 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.85 | 1.85 | 1.85 | 1.85 |
| sqlite_async | 8.59 | 8.59 | 8.59 | 8.59 |


## Repeat Stability

These rows summarize resqlite wall medians across repeated full-suite runs.
Use this section to judge whether small deltas are real or just noise.

| Benchmark | Median (ms) | Min | Max | Range | MAD | Stability |
|---|---|---|---|---|---|---|
| Parameterized Queries / 100 queries × ~500 rows each / resqlite sel... | 14.71 | 14.68 | 15.16 | 3.3% | 0.2% | stable |
| Point Query Throughput / resqlite qps | 101999.00 | 87658.00 | 104932.00 | 16.9% | 2.9% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.12 | 0.12 | 0.12 | 0.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.35 | 0.35 | 0.35 | 0.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.35 | 0.33 | 0.35 | 5.7% | 0.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.60 | 0.60 | 0.60 | 0.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 1.03 | 1.03 | 1.03 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.07 | 0.06 | 0.07 | 14.3% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.56 | 0.55 | 0.57 | 3.6% | 1.8% | stable |
| Select → JSON Bytes / 5000 rows / resqlite selectBytes() | 2.99 | 2.93 | 3.01 | 2.7% | 0.7% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.06 | 0.05 | 0.48 | 716.7% | 16.7% | noisy |
| Select → Maps / 1000 rows / resqlite select() | 0.39 | 0.39 | 0.40 | 2.6% | 0.0% | stable |
| Select → Maps / 5000 rows / resqlite select() | 2.23 | 2.22 | 2.35 | 5.8% | 0.4% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.15 | 0.14 | 0.22 | 53.3% | 6.7% | moderate |
| Streaming / Initial Emission / resqlite stream() | 0.04 | 0.03 | 0.07 | 100.0% | 25.0% | noisy |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.04 | 0.05 | 25.0% | 0.0% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.33 | 1.85 | 2.55 | 30.0% | 9.4% | noisy |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.06 | 0.07 | 16.7% | 0.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.45 | 0.44 | 0.46 | 4.4% | 2.2% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.42 | 4.38 | 4.66 | 6.3% | 0.9% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05 | 0.05 | 0.0% | 0.0% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.54 | 1.53 | 2.12 | 38.3% | 0.6% | stable |


## Comparison vs Previous Run

Previous: `2026-04-10T10-27-41-post-byte-threshold.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Noise threshold | Stability | Status |
|---|---|---|---|---|---|---|
| Parameterized Queries / 100 queries × ~500 rows each / re... | 15.24 | 14.71 | -0.53 | ±10% / ±1.52 ms | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 59432.00 | 101999.00 | +42567.00 | ±10% / ±10199.90 ms | stable | 🔴 Regression (+72%) |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.12 | 0.12 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.35 | 0.35 | +0.00 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.34 | 0.35 | +0.01 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.61 | 0.60 | -0.01 | ±10% / ±0.06 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 1.07 | 1.03 | -0.04 | ±10% / ±0.11 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.07 | 0.07 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.56 | 0.56 | +0.00 | ±10% / ±0.06 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 5000 rows / resqlite selectBytes() | 3.02 | 2.99 | -0.03 | ±10% / ±0.30 ms | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.06 | +0.01 | ±50% / ±0.03 ms | noisy | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.40 | 0.39 | -0.01 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Select → Maps / 5000 rows / resqlite select() | 2.27 | 2.23 | -0.04 | ±10% / ±0.23 ms | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.20 | 0.15 | -0.05 | ±20% / ±0.04 ms | moderate | 🟢 Win (-25%) |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.04 | +0.01 | ±75% / ±0.03 ms | noisy | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.88 | 2.33 | +0.45 | ±28% / ±0.66 ms | noisy | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.45 | 0.45 | +0.00 | ±10% / ±0.05 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.55 | 4.42 | -0.13 | ±10% / ±0.46 ms | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.60 | 1.54 | -0.06 | ±10% / ±0.16 ms | stable | ⚪ Within noise |

**Summary:** 1 wins, 1 regressions, 20 neutral

Comparison threshold uses `max(10%, 3 × current MAD%)`, plus an absolute floor of `±0.02 ms`.
That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


