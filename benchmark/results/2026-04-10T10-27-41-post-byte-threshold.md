# resqlite Benchmark Results

Generated: 2026-04-10T10:27:41.894828

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `post-byte-threshold`
- Repeats: `3`
- Comparison baseline: `2026-04-09T10-29-34-readme-numbers.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.05 | 0.06 | 0.01 | 0.01 |
| sqlite3 select() | 0.09 | 0.09 | 0.09 | 0.09 |
| sqlite_async getAll() | 0.09 | 0.09 | 0.02 | 0.02 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.40 | 0.41 | 0.10 | 0.10 |
| sqlite3 select() | 0.81 | 0.83 | 0.81 | 0.83 |
| sqlite_async getAll() | 0.72 | 0.77 | 0.17 | 0.17 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 2.27 | 5.27 | 0.50 | 0.52 |
| sqlite3 select() | 4.07 | 4.32 | 4.07 | 4.32 |
| sqlite_async getAll() | 3.68 | 4.09 | 0.84 | 0.85 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.07 | 0.07 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.28 | 0.30 | 0.28 | 0.30 |
| sqlite_async + jsonEncode | 0.29 | 0.32 | 0.21 | 0.23 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.56 | 0.59 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 2.82 | 5.40 | 2.82 | 5.40 |
| sqlite_async + jsonEncode | 2.75 | 5.33 | 2.11 | 4.19 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 3.02 | 3.75 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 16.77 | 17.78 | 16.77 | 17.78 |
| sqlite_async + jsonEncode | 17.12 | 18.70 | 10.61 | 11.09 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.12 | 0.13 | 0.05 | 0.06 |
| sqlite3 | 0.24 | 0.26 | 0.24 | 0.26 |
| sqlite_async | 0.28 | 0.29 | 0.10 | 0.10 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.07 | 1.18 | 0.40 | 0.42 |
| sqlite3 | 2.08 | 2.22 | 2.08 | 2.22 |
| sqlite_async | 1.66 | 1.86 | 0.53 | 0.55 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.61 | 0.67 | 0.16 | 0.16 |
| sqlite3 | 1.17 | 1.29 | 1.17 | 1.29 |
| sqlite_async | 1.07 | 1.26 | 0.22 | 0.24 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.34 | 0.36 | 0.15 | 0.16 |
| sqlite3 | 0.69 | 0.71 | 0.69 | 0.71 |
| sqlite_async | 0.61 | 0.66 | 0.22 | 0.22 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.35 | 0.39 | 0.15 | 0.16 |
| sqlite3 | 0.65 | 0.68 | 0.65 | 0.68 |
| sqlite_async | 0.60 | 0.66 | 0.23 | 0.23 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

| Rows | resqlite wall | resqlite main | sqlite3 wall | sqlite_async wall |
|---|---|---|---|---|
| 10 | 0.01 | 0.00 | 0.01 | 0.03 |
| 50 | 0.03 | 0.01 | 0.05 | 0.06 |
| 100 | 0.06 | 0.01 | 0.09 | 0.09 |
| 500 | 0.22 | 0.07 | 0.43 | 0.39 |
| 1000 | 0.44 | 0.13 | 0.84 | 0.77 |
| 2000 | 0.90 | 0.26 | 1.68 | 1.51 |
| 5000 | 2.41 | 0.65 | 4.22 | 3.84 |
| 10000 | 5.01 | 1.30 | 8.58 | 8.39 |
| 20000 | 13.38 | 2.64 | 22.98 | 25.84 |

### Bytes (selectBytes → JSON)

| Rows | resqlite wall | sqlite3+json wall | async+json wall |
|---|---|---|---|
| 10 | 0.02 | 0.03 | 0.05 |
| 50 | 0.04 | 0.14 | 0.16 |
| 100 | 0.07 | 0.28 | 0.28 |
| 500 | 0.28 | 1.37 | 1.38 |
| 1000 | 0.55 | 2.72 | 2.75 |
| 2000 | 1.47 | 5.97 | 6.01 |
| 5000 | 2.96 | 16.56 | 17.32 |
| 10000 | 6.41 | 31.66 | 31.99 |
| 20000 | 12.48 | 65.72 | 70.04 |

## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency).

| Concurrency | resqlite wall | resqlite/query | async wall | async/query |
|---|---|---|---|---|
| 1 | 0.30 | 0.30 | 0.55 | 0.55 |
| 2 | 0.33 | 0.16 | 0.60 | 0.30 |
| 4 | 0.88 | 0.22 | 1.08 | 0.27 |
| 8 | 1.58 | 0.20 | 2.36 | 0.30 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead of the reader pool.

| Metric | Value |
|---|---:|
| resqlite qps | 59432 |
| resqlite per query | 0.017 ms |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 15.24 | 15.63 | 15.24 | 15.63 |
| sqlite3 (no cache) | 25.29 | 25.55 | 25.29 | 25.55 |
| sqlite3 (cached stmt) | 24.83 | 25.19 | 24.83 | 25.19 |
| sqlite_async getAll() | 24.69 | 25.07 | 24.69 | 25.07 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.60 | 2.23 | 1.60 | 2.23 |
| sqlite3 execute() | 3.45 | 6.67 | 3.45 | 6.67 |
| sqlite_async execute() | 2.86 | 3.65 | 2.86 | 3.65 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.06 | 0.07 | 0.06 | 0.07 |
| sqlite3 (manual tx + stmt) | 0.09 | 0.10 | 0.09 | 0.10 |
| sqlite_async executeBatch() | 0.09 | 0.10 | 0.09 | 0.10 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.45 | 0.48 | 0.45 | 0.48 |
| sqlite3 (manual tx + stmt) | 0.52 | 0.55 | 0.52 | 0.55 |
| sqlite_async executeBatch() | 0.53 | 0.57 | 0.53 | 0.57 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.55 | 7.30 | 4.55 | 7.30 |
| sqlite3 (manual tx + stmt) | 4.44 | 4.70 | 4.44 | 4.70 |
| sqlite_async executeBatch() | 5.03 | 5.53 | 5.03 | 5.53 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.05 | 0.05 | 0.05 | 0.05 |
| sqlite_async writeTransaction() | 0.08 | 0.09 | 0.08 | 0.09 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.03 | 0.04 | 0.03 | 0.04 |
| sqlite_async watch() | 0.12 | 0.15 | 0.12 | 0.15 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.04 | 0.05 | 0.04 | 0.05 |
| sqlite_async | 0.06 | 0.09 | 0.06 | 0.09 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.20 | 0.24 | 0.20 | 0.24 |
| sqlite_async | 0.27 | 0.38 | 0.27 | 0.38 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.88 | 1.88 | 1.88 | 1.88 |
| sqlite_async | 9.37 | 9.37 | 9.37 | 9.37 |


## Repeat Stability

These rows summarize resqlite wall medians across repeated full-suite runs.
Use this section to judge whether small deltas are real or just noise.

| Benchmark | Median (ms) | Min | Max | Range | MAD | Stability |
|---|---|---|---|---|---|---|
| Parameterized Queries / 100 queries × ~500 rows each / resqlite sel... | 15.24 | 15.15 | 16.45 | 8.5% | 0.6% | stable |
| Point Query Throughput / resqlite qps | 64641.00 | 59432.00 | 83710.00 | 37.6% | 8.1% | noisy |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.12 | 0.11 | 0.12 | 8.3% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.35 | 0.35 | 0.36 | 2.9% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.35 | 0.34 | 0.35 | 2.9% | 0.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.61 | 0.61 | 0.62 | 1.6% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 1.06 | 1.04 | 1.07 | 2.8% | 0.9% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.07 | 0.07 | 0.07 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.55 | 0.55 | 0.56 | 1.8% | 0.0% | stable |
| Select → JSON Bytes / 5000 rows / resqlite selectBytes() | 2.97 | 2.92 | 3.02 | 3.4% | 1.7% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.06 | 0.05 | 0.43 | 633.3% | 16.7% | noisy |
| Select → Maps / 1000 rows / resqlite select() | 0.40 | 0.40 | 0.41 | 2.5% | 0.0% | stable |
| Select → Maps / 5000 rows / resqlite select() | 2.27 | 2.24 | 2.27 | 1.3% | 0.0% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.19 | 0.18 | 0.20 | 10.5% | 5.3% | moderate |
| Streaming / Initial Emission / resqlite stream() | 0.04 | 0.03 | 0.06 | 75.0% | 25.0% | noisy |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.04 | 0.06 | 40.0% | 20.0% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.20 | 1.88 | 2.56 | 30.9% | 14.5% | noisy |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.06 | 0.07 | 16.7% | 0.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.45 | 0.45 | 0.46 | 2.2% | 0.0% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.55 | 4.43 | 4.56 | 2.9% | 0.2% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05 | 0.09 | 80.0% | 0.0% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.60 | 1.60 | 1.69 | 5.6% | 0.0% | stable |


## Comparison vs Previous Run

Previous: `2026-04-09T10-29-34-readme-numbers.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Noise threshold | Stability | Status |
|---|---|---|---|---|---|---|
| Parameterized Queries / 100 queries × ~500 rows each / re... | 18.49 | 15.24 | -3.25 | ±10% / ±1.85 ms | stable | 🟢 Win (-18%) |
| Point Query Throughput / resqlite qps | 64086.00 | 64641.00 | +555.00 | ±24% / ±15627.00 ms | noisy | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.12 | 0.12 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.43 | 0.35 | -0.08 | ±10% / ±0.04 ms | stable | 🟢 Win (-19%) |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.42 | 0.35 | -0.07 | ±10% / ±0.04 ms | stable | 🟢 Win (-17%) |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.83 | 0.61 | -0.22 | ±10% / ±0.08 ms | stable | 🟢 Win (-27%) |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 1.20 | 1.06 | -0.14 | ±10% / ±0.12 ms | stable | 🟢 Win (-12%) |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.06 | 0.07 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.60 | 0.55 | -0.05 | ±10% / ±0.06 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 5000 rows / resqlite selectBytes() | 3.60 | 2.97 | -0.63 | ±10% / ±0.36 ms | stable | 🟢 Win (-17%) |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.06 | +0.01 | ±50% / ±0.03 ms | noisy | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.40 | 0.40 | +0.00 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Select → Maps / 5000 rows / resqlite select() | 3.74 | 2.27 | -1.47 | ±10% / ±0.37 ms | stable | 🟢 Win (-39%) |
| Streaming / Fan-out (10 streams) / resqlite | 0.34 | 0.19 | -0.15 | ±16% / ±0.05 ms | moderate | 🟢 Win (-44%) |
| Streaming / Initial Emission / resqlite stream() | 0.04 | 0.04 | +0.00 | ±75% / ±0.03 ms | noisy | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.12 | 0.05 | -0.07 | ±60% / ±0.07 ms | noisy | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 3.71 | 2.20 | -1.51 | ±44% / ±1.62 ms | noisy | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.09 | 0.06 | -0.03 | ±10% / ±0.02 ms | stable | 🟢 Win (-33%) |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.80 | 0.45 | -0.35 | ±10% / ±0.08 ms | stable | 🟢 Win (-44%) |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 6.35 | 4.55 | -1.80 | ±10% / ±0.64 ms | stable | 🟢 Win (-28%) |
| Write Performance / Interactive Transaction (insert + sel... | 0.12 | 0.05 | -0.07 | ±10% / ±0.02 ms | stable | 🟢 Win (-58%) |
| Write Performance / Single Inserts (100 sequential) / res... | 2.83 | 1.60 | -1.23 | ±10% / ±0.28 ms | stable | 🟢 Win (-43%) |

**Summary:** 13 wins, 0 regressions, 9 neutral

Comparison threshold uses `max(10%, 3 × current MAD%)`, plus an absolute floor of `±0.02 ms`.
That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

✅ **No regressions beyond noise.** 13 benchmarks improved.


