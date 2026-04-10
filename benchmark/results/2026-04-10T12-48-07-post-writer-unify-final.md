# resqlite Benchmark Results

Generated: 2026-04-10T12:48:07.335751

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `post-writer-unify-final`
- Repeats: `3`
- Comparison baseline: `2026-04-10T11-09-15-post-cleanup.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.05 | 0.05 | 0.01 | 0.01 |
| sqlite3 select() | 0.08 | 0.09 | 0.08 | 0.09 |
| sqlite_async getAll() | 0.09 | 0.09 | 0.02 | 0.02 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.37 | 0.43 | 0.09 | 0.11 |
| sqlite3 select() | 0.74 | 0.83 | 0.74 | 0.83 |
| sqlite_async getAll() | 0.70 | 0.85 | 0.16 | 0.20 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 2.31 | 6.08 | 0.49 | 0.54 |
| sqlite3 select() | 3.84 | 4.31 | 3.84 | 4.31 |
| sqlite_async getAll() | 3.88 | 4.27 | 0.85 | 0.96 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.07 | 0.08 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.26 | 0.36 | 0.26 | 0.36 |
| sqlite_async + jsonEncode | 0.29 | 0.35 | 0.21 | 0.24 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.55 | 0.63 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 2.71 | 5.23 | 2.71 | 5.23 |
| sqlite_async + jsonEncode | 2.75 | 5.89 | 2.08 | 4.58 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 2.93 | 3.82 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 15.53 | 16.61 | 15.53 | 16.61 |
| sqlite_async + jsonEncode | 16.40 | 18.02 | 10.43 | 11.19 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.12 | 0.12 | 0.05 | 0.05 |
| sqlite3 | 0.22 | 0.26 | 0.22 | 0.26 |
| sqlite_async | 0.27 | 0.45 | 0.10 | 0.12 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.06 | 1.15 | 0.39 | 0.42 |
| sqlite3 | 1.93 | 2.05 | 1.93 | 2.05 |
| sqlite_async | 1.67 | 1.97 | 0.52 | 0.58 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.61 | 0.67 | 0.15 | 0.17 |
| sqlite3 | 1.09 | 1.16 | 1.09 | 1.16 |
| sqlite_async | 1.02 | 1.08 | 0.21 | 0.22 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.34 | 0.35 | 0.15 | 0.16 |
| sqlite3 | 0.62 | 0.67 | 0.62 | 0.67 |
| sqlite_async | 0.57 | 0.61 | 0.21 | 0.23 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.34 | 0.35 | 0.15 | 0.15 |
| sqlite3 | 0.59 | 0.66 | 0.59 | 0.66 |
| sqlite_async | 0.58 | 0.65 | 0.21 | 0.23 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

| Rows | resqlite wall | resqlite main | sqlite3 wall | sqlite_async wall |
|---|---|---|---|---|
| 10 | 0.01 | 0.00 | 0.01 | 0.03 |
| 50 | 0.03 | 0.01 | 0.04 | 0.06 |
| 100 | 0.05 | 0.01 | 0.08 | 0.10 |
| 500 | 0.21 | 0.06 | 0.43 | 0.39 |
| 1000 | 0.43 | 0.13 | 0.79 | 0.74 |
| 2000 | 0.90 | 0.26 | 1.54 | 1.61 |
| 5000 | 2.56 | 0.66 | 4.05 | 4.09 |
| 10000 | 5.94 | 1.34 | 8.14 | 8.63 |
| 20000 | 13.83 | 2.53 | 22.94 | 27.44 |

### Bytes (selectBytes → JSON)

| Rows | resqlite wall | sqlite3+json wall | async+json wall |
|---|---|---|---|
| 10 | 0.02 | 0.03 | 0.05 |
| 50 | 0.04 | 0.14 | 0.15 |
| 100 | 0.07 | 0.28 | 0.27 |
| 500 | 0.27 | 1.34 | 1.32 |
| 1000 | 0.55 | 2.70 | 2.67 |
| 2000 | 1.21 | 5.75 | 5.86 |
| 5000 | 2.92 | 16.13 | 16.49 |
| 10000 | 6.36 | 30.20 | 32.48 |
| 20000 | 12.17 | 63.56 | 68.54 |

## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency).

| Concurrency | resqlite wall | resqlite/query | async wall | async/query |
|---|---|---|---|---|
| 1 | 0.29 | 0.29 | 0.53 | 0.53 |
| 2 | 0.31 | 0.16 | 0.60 | 0.30 |
| 4 | 0.37 | 0.09 | 0.63 | 0.16 |
| 8 | 0.71 | 0.09 | 1.32 | 0.16 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead of the reader pool.

| Metric | Value |
|---|---:|
| resqlite qps | 101792 |
| resqlite per query | 0.010 ms |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 14.79 | 15.03 | 14.79 | 15.03 |
| sqlite3 (no cache) | 22.85 | 23.31 | 22.85 | 23.31 |
| sqlite3 (cached stmt) | 22.90 | 23.28 | 22.90 | 23.28 |
| sqlite_async getAll() | 24.58 | 25.28 | 24.58 | 25.28 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.64 | 2.32 | 1.64 | 2.32 |
| sqlite3 execute() | 3.79 | 6.27 | 3.79 | 6.27 |
| sqlite_async execute() | 3.08 | 3.64 | 3.08 | 3.64 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.06 | 0.06 | 0.06 | 0.06 |
| sqlite3 (manual tx + stmt) | 0.10 | 0.13 | 0.10 | 0.13 |
| sqlite_async executeBatch() | 0.09 | 0.13 | 0.09 | 0.13 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.44 | 0.49 | 0.44 | 0.49 |
| sqlite3 (manual tx + stmt) | 0.52 | 0.56 | 0.52 | 0.56 |
| sqlite_async executeBatch() | 0.52 | 0.55 | 0.52 | 0.55 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.29 | 5.38 | 4.29 | 5.38 |
| sqlite3 (manual tx + stmt) | 4.24 | 4.47 | 4.24 | 4.47 |
| sqlite_async executeBatch() | 4.82 | 5.16 | 4.82 | 5.16 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.07 | 0.12 | 0.07 | 0.12 |
| sqlite_async writeTransaction() | 0.08 | 0.18 | 0.08 | 0.18 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.10 | 0.12 | 0.10 | 0.12 |
| sqlite_async tx.getAll() | 0.21 | 0.26 | 0.21 | 0.26 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.18 | 0.21 | 0.18 | 0.21 |
| sqlite_async tx.getAll() | 0.37 | 0.48 | 0.37 | 0.48 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.03 | 0.06 | 0.03 | 0.06 |
| sqlite_async watch() | 0.11 | 0.15 | 0.11 | 0.15 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.05 | 0.06 | 0.05 | 0.06 |
| sqlite_async | 0.05 | 0.10 | 0.05 | 0.10 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.18 | 0.26 | 0.18 | 0.26 |
| sqlite_async | 0.27 | 0.36 | 0.27 | 0.36 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.64 | 2.64 | 2.64 | 2.64 |
| sqlite_async | 25.70 | 25.70 | 25.70 | 25.70 |


## Repeat Stability

These rows summarize resqlite wall medians across repeated full-suite runs.
Use this section to judge whether small deltas are real or just noise.

| Benchmark | Median (ms) | Min | Max | Range | MAD | Stability |
|---|---|---|---|---|---|---|
| Parameterized Queries / 100 queries × ~500 rows each / resqlite sel... | 14.79 | 14.59 | 14.88 | 2.0% | 0.6% | stable |
| Point Query Throughput / resqlite qps | 99226.00 | 97485.00 | 101792.00 | 4.3% | 1.8% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.12 | 0.11 | 0.12 | 8.3% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.35 | 0.34 | 0.35 | 2.9% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.34 | 0.34 | 0.34 | 0.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.59 | 0.58 | 0.61 | 5.1% | 1.7% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 1.02 | 1.01 | 1.06 | 4.9% | 1.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.07 | 0.07 | 0.07 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.55 | 0.53 | 0.56 | 5.5% | 1.8% | stable |
| Select → JSON Bytes / 5000 rows / resqlite selectBytes() | 2.95 | 2.93 | 3.74 | 27.5% | 0.7% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.06 | 0.05 | 0.40 | 583.3% | 16.7% | noisy |
| Select → Maps / 1000 rows / resqlite select() | 0.39 | 0.37 | 0.40 | 7.7% | 2.6% | stable |
| Select → Maps / 5000 rows / resqlite select() | 2.40 | 2.31 | 2.40 | 3.7% | 0.0% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.18 | 0.17 | 0.22 | 27.8% | 5.6% | moderate |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | 0.06 | 100.0% | 0.0% | stable |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.04 | 0.05 | 20.0% | 0.0% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.64 | 2.54 | 3.08 | 20.5% | 3.8% | moderate |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.05 | 0.06 | 16.7% | 0.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.44 | 0.44 | 0.45 | 2.3% | 0.0% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.35 | 4.29 | 4.41 | 2.8% | 1.4% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05 | 0.07 | 40.0% | 0.0% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.67 | 1.64 | 1.77 | 7.8% | 1.8% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.18 | 0.18 | 0.0% | 0.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.10 | 0.10 | 0.11 | 10.0% | 0.0% | stable |


## Comparison vs Previous Run

Previous: `2026-04-10T11-09-15-post-cleanup.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Noise threshold | Stability | Status |
|---|---|---|---|---|---|---|
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.98 | 14.79 | -0.19 | ±10% / ±1.50 ms | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 104450.00 | 99226.00 | -5224.00 | ±10% / ±10445.00 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.12 | 0.12 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.37 | 0.35 | -0.02 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.62 | 0.34 | -0.28 | ±10% / ±0.06 ms | stable | 🟢 Win (-45%) |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.78 | 0.59 | -0.19 | ±10% / ±0.08 ms | stable | 🟢 Win (-24%) |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 1.07 | 1.02 | -0.05 | ±10% / ±0.11 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.07 | 0.07 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.57 | 0.55 | -0.02 | ±10% / ±0.06 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 5000 rows / resqlite selectBytes() | 3.08 | 2.95 | -0.13 | ±10% / ±0.31 ms | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.06 | +0.01 | ±50% / ±0.03 ms | noisy | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.40 | 0.39 | -0.01 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Select → Maps / 5000 rows / resqlite select() | 3.25 | 2.40 | -0.85 | ±10% / ±0.33 ms | stable | 🟢 Win (-26%) |
| Streaming / Fan-out (10 streams) / resqlite | 0.16 | 0.18 | +0.02 | ±17% / ±0.03 ms | moderate | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.04 | 0.03 | -0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.05 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.77 | 2.64 | +0.87 | ±11% / ±0.30 ms | moderate | 🔴 Regression (+49%) |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.07 | 0.06 | -0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.46 | 0.44 | -0.02 | ±10% / ±0.05 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.38 | 4.35 | -0.03 | ±10% / ±0.44 ms | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.56 | 1.67 | +0.11 | ±10% / ±0.17 ms | stable | ⚪ Within noise |

**Summary:** 3 wins, 1 regressions, 18 neutral

Comparison threshold uses `max(10%, 3 × current MAD%)`, plus an absolute floor of `±0.02 ms`.
That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


