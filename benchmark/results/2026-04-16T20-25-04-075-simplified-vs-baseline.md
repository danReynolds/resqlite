# resqlite Benchmark Results

Generated: 2026-04-16T20:25:04.531339

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `075-simplified-vs-baseline`
- Repeats: `5`
- Comparison baseline: `2026-04-16T19-45-07-075-baseline.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.01 | 0.01 | 0.00 | 0.00 |
| sqlite3 select() | 0.01 | 0.01 | 0.01 | 0.01 |
| sqlite_async getAll() | 0.03 | 0.04 | 0.00 | 0.00 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.05 | 0.05 | 0.01 | 0.01 |
| sqlite3 select() | 0.08 | 0.09 | 0.08 | 0.09 |
| sqlite_async getAll() | 0.09 | 0.09 | 0.02 | 0.02 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.39 | 0.44 | 0.10 | 0.10 |
| sqlite3 select() | 0.74 | 0.82 | 0.74 | 0.82 |
| sqlite_async getAll() | 0.70 | 0.87 | 0.16 | 0.17 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 5.71 | 9.68 | 1.00 | 1.34 |
| sqlite3 select() | 8.05 | 9.78 | 8.05 | 9.78 |
| sqlite_async getAll() | 9.96 | 15.59 | 2.04 | 3.11 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.01 | 0.05 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.03 | 0.03 | 0.03 | 0.03 |
| sqlite_async + jsonEncode | 0.05 | 0.08 | 0.02 | 0.03 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.04 | 0.07 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.28 | 0.31 | 0.28 | 0.31 |
| sqlite_async + jsonEncode | 0.29 | 0.34 | 0.21 | 0.22 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.36 | 0.42 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 2.76 | 6.26 | 2.76 | 6.26 |
| sqlite_async + jsonEncode | 2.63 | 5.86 | 2.00 | 4.49 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 4.33 | 5.14 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 32.42 | 34.68 | 32.42 | 34.68 |
| sqlite_async + jsonEncode | 32.74 | 34.21 | 22.19 | 24.10 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.12 | 0.12 | 0.05 | 0.05 |
| sqlite3 | 0.23 | 0.25 | 0.23 | 0.25 |
| sqlite_async | 0.26 | 0.29 | 0.09 | 0.10 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.04 | 1.08 | 0.39 | 0.41 |
| sqlite3 | 1.92 | 2.04 | 1.92 | 2.04 |
| sqlite_async | 1.69 | 1.89 | 0.52 | 0.55 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.60 | 0.69 | 0.15 | 0.16 |
| sqlite3 | 1.07 | 1.17 | 1.07 | 1.17 |
| sqlite_async | 1.03 | 1.20 | 0.20 | 0.21 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.33 | 0.37 | 0.14 | 0.15 |
| sqlite3 | 0.62 | 0.70 | 0.62 | 0.70 |
| sqlite_async | 0.58 | 0.64 | 0.21 | 0.22 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.36 | 0.40 | 0.15 | 0.15 |
| sqlite3 | 0.61 | 0.73 | 0.61 | 0.73 |
| sqlite_async | 0.59 | 0.68 | 0.22 | 0.24 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

| Rows | resqlite wall | resqlite main | sqlite3 wall | sqlite_async wall |
|---|---|---|---|---|
| 10 | 0.01 | 0.00 | 0.01 | 0.03 |
| 50 | 0.04 | 0.01 | 0.04 | 0.06 |
| 100 | 0.05 | 0.01 | 0.09 | 0.09 |
| 500 | 0.21 | 0.06 | 0.38 | 0.37 |
| 1000 | 0.41 | 0.12 | 0.78 | 0.73 |
| 2000 | 0.91 | 0.26 | 1.60 | 1.64 |
| 5000 | 2.38 | 0.62 | 3.98 | 3.86 |
| 10000 | 5.71 | 1.26 | 8.15 | 8.27 |
| 20000 | 14.08 | 2.52 | 21.03 | 26.14 |

### Bytes (selectBytes → JSON)

| Rows | resqlite wall | sqlite3+json wall | async+json wall |
|---|---|---|---|
| 10 | 0.01 | 0.03 | 0.05 |
| 50 | 0.03 | 0.13 | 0.15 |
| 100 | 0.04 | 0.26 | 0.28 |
| 500 | 0.18 | 1.33 | 1.32 |
| 1000 | 0.36 | 2.66 | 2.66 |
| 2000 | 0.85 | 5.96 | 6.03 |
| 5000 | 2.00 | 15.65 | 14.57 |
| 10000 | 4.24 | 31.36 | 32.22 |
| 20000 | 8.32 | 63.75 | 66.41 |

## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency).

| Concurrency | resqlite wall | resqlite/query | async wall | async/query |
|---|---|---|---|---|
| 1 | 0.28 | 0.28 | 0.54 | 0.54 |
| 2 | 0.31 | 0.15 | 0.60 | 0.30 |
| 4 | 0.38 | 0.09 | 0.73 | 0.18 |
| 8 | 0.80 | 0.10 | 1.29 | 0.16 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead of the reader pool.

| Metric | Value |
|---|---:|
| resqlite qps | 125063 |
| resqlite per query | 0.008 ms |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 14.70 | 14.93 | 14.70 | 14.93 |
| sqlite3 (no cache) | 23.60 | 24.10 | 23.60 | 24.10 |
| sqlite3 (cached stmt) | 23.19 | 23.54 | 23.19 | 23.54 |
| sqlite_async getAll() | 24.61 | 25.59 | 24.61 | 25.59 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.87 | 2.53 | 1.87 | 2.53 |
| sqlite3 execute() | 4.13 | 7.28 | 4.13 | 7.28 |
| sqlite_async execute() | 4.02 | 5.70 | 4.02 | 5.70 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.06 | 0.07 | 0.00 | 0.00 |
| sqlite3 (manual tx + stmt) | 0.10 | 0.18 | 0.10 | 0.18 |
| sqlite_async executeBatch() | 0.11 | 0.18 | 0.11 | 0.18 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.45 | 0.74 | 0.00 | 0.00 |
| sqlite3 (manual tx + stmt) | 0.57 | 0.72 | 0.57 | 0.72 |
| sqlite_async executeBatch() | 0.62 | 0.76 | 0.62 | 0.76 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.66 | 5.56 | 0.00 | 0.00 |
| sqlite3 (manual tx + stmt) | 4.45 | 5.04 | 4.45 | 5.04 |
| sqlite_async executeBatch() | 5.00 | 5.82 | 5.00 | 5.82 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.06 | 0.10 | 0.06 | 0.10 |
| sqlite_async writeTransaction() | 0.09 | 0.13 | 0.09 | 0.13 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.07 | 0.09 | 0.07 | 0.09 |
| resqlite tx.execute() loop | 0.81 | 0.95 | 0.81 | 0.95 |
| sqlite_async tx.execute() loop | 1.28 | 1.67 | 1.28 | 1.67 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.49 | 0.65 | 0.49 | 0.65 |
| resqlite tx.execute() loop | 7.81 | 8.44 | 7.81 | 8.44 |
| sqlite_async tx.execute() loop | 12.32 | 13.36 | 12.32 | 13.36 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.11 | 0.14 | 0.11 | 0.14 |
| sqlite_async tx.getAll() | 0.21 | 0.29 | 0.21 | 0.29 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.19 | 0.24 | 0.19 | 0.24 |
| sqlite_async tx.getAll() | 0.39 | 0.54 | 0.39 | 0.54 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.04 | 0.04 | 0.04 | 0.04 |
| sqlite_async watch() | 0.11 | 0.14 | 0.11 | 0.14 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.05 | 0.06 | 0.05 | 0.06 |
| sqlite_async | 0.10 | 0.21 | 0.10 | 0.21 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.26 | 0.33 | 0.26 | 0.33 |
| sqlite_async | 0.56 | 1.15 | 0.56 | 1.15 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.22 | 0.30 | 0.22 | 0.30 |
| sqlite_async | 0.26 | 0.35 | 0.26 | 0.35 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.34 | 2.34 | 2.34 | 2.34 |
| sqlite_async | 9.50 | 9.50 | 9.50 | 9.50 |


## Repeat Stability

These rows summarize resqlite wall medians across repeated full-suite runs.
Use this section to judge whether small deltas are real or just noise.

| Benchmark | Median (ms) | Min | Max | Range | MAD | Stability |
|---|---|---|---|---|---|---|
| Concurrent Reads (1000 rows per query) / resqlite concurrent 1x | 0.30 | 0.28 | 0.32 | 13.3% | 3.3% | moderate |
| Concurrent Reads (1000 rows per query) / resqlite concurrent 2x | 0.32 | 0.31 | 0.33 | 6.3% | 3.1% | moderate |
| Concurrent Reads (1000 rows per query) / resqlite concurrent 4x | 0.39 | 0.38 | 0.43 | 12.8% | 2.6% | stable |
| Concurrent Reads (1000 rows per query) / resqlite concurrent 8x | 0.76 | 0.72 | 0.85 | 17.1% | 5.3% | moderate |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite sel... | 14.64 | 14.45 | 14.79 | 2.3% | 0.4% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite sel... | 14.64 | 14.45 | 14.79 | 2.3% | 0.4% | stable |
| Point Query Throughput / resqlite qps | 125063.00 | 106792.00 | 127033.00 | 16.2% | 1.6% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.12 | 0.10 | 0.12 | 16.7% | 0.0% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.05 | 0.04 | 0.05 | 20.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.35 | 0.34 | 0.36 | 5.7% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.15 | 0.14 | 0.15 | 6.7% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.34 | 0.33 | 0.35 | 5.9% | 2.9% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.14 | 0.14 | 0.15 | 7.1% | 0.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.61 | 0.60 | 0.66 | 9.8% | 1.6% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.15 | 0.15 | 0.15 | 0.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 1.03 | 1.02 | 1.04 | 1.9% | 1.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.39 | 0.38 | 0.39 | 2.6% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | 0.02 | 100.0% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.04 | 0.05 | 20.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.36 | 0.36 | 0.36 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 4.33 | 3.95 | 4.40 | 10.4% | 1.6% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | 0.09 | 800.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | 0.02 | 0.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.05 | 0.15 | 200.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | 0.03 | 200.0% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.40 | 0.38 | 0.40 | 5.0% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.10 | 0.10 | 0.10 | 0.0% | 0.0% | stable |
| Select → Maps / 10000 rows / resqlite select() | 5.32 | 4.53 | 5.71 | 22.2% | 7.3% | moderate |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.98 | 0.95 | 1.00 | 5.1% | 2.0% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.24 | 0.22 | 0.26 | 16.7% | 8.3% | noisy |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.24 | 0.22 | 0.26 | 16.7% | 8.3% | noisy |
| Streaming / Initial Emission / resqlite stream() | 0.04 | 0.04 | 0.04 | 0.0% | 0.0% | stable |
| Streaming / Initial Emission / resqlite stream() [main] | 0.04 | 0.04 | 0.04 | 0.0% | 0.0% | stable |
| Streaming / Invalidation Latency / resqlite | 0.06 | 0.05 | 0.06 | 16.7% | 0.0% | stable |
| Streaming / Invalidation Latency / resqlite [main] | 0.06 | 0.05 | 0.06 | 16.7% | 0.0% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.46 | 2.15 | 2.57 | 17.1% | 4.5% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.46 | 2.15 | 2.57 | 17.1% | 4.5% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.27 | 0.26 | 0.27 | 3.7% | 0.0% | stable |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.27 | 0.26 | 0.27 | 3.7% | 0.0% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.06 | 0.07 | 16.7% | 0.0% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.44 | 0.44 | 0.45 | 2.3% | 0.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.66 | 4.38 | 4.73 | 7.5% | 1.5% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.63 | 0.57 | 0.81 | 38.1% | 9.5% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.63 | 0.57 | 0.81 | 38.1% | 9.5% | noisy |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.08 | 0.07 | 0.08 | 12.5% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.08 | 0.07 | 0.08 | 12.5% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.95 | 5.85 | 7.81 | 32.9% | 1.7% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.95 | 5.85 | 7.81 | 32.9% | 1.7% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.48 | 0.44 | 0.49 | 10.4% | 2.1% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.48 | 0.44 | 0.49 | 10.4% | 2.1% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.06 | 0.05 | 0.06 | 16.7% | 0.0% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.06 | 0.05 | 0.06 | 16.7% | 0.0% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.73 | 1.64 | 1.87 | 13.3% | 2.3% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.73 | 1.64 | 1.87 | 13.3% | 2.3% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.19 | 0.20 | 5.3% | 0.0% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.19 | 0.20 | 5.3% | 0.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.11 | 0.10 | 0.13 | 27.3% | 0.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.11 | 0.10 | 0.13 | 27.3% | 0.0% | stable |


## Comparison vs Previous Run

Previous: `2026-04-16T19-45-07-075-baseline.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Noise threshold | Stability | Status |
|---|---|---|---|---|---|---|
| Concurrent Reads (1000 rows per query) / resqlite concurr... | 0.30 | 0.30 | +0.00 | ±10% / ±0.03 ms | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / resqlite concurr... | 0.32 | 0.32 | +0.00 | ±10% / ±0.03 ms | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / resqlite concurr... | 0.39 | 0.39 | +0.00 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / resqlite concurr... | 0.77 | 0.76 | -0.01 | ±16% / ±0.12 ms | moderate | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.52 | 14.64 | +0.12 | ±10% / ±1.46 ms | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.52 | 14.64 | +0.12 | ±10% / ±1.46 ms | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 126518.00 | 125063.00 | -1455.00 | ±10% / ±12651.80 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.12 | 0.12 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.35 | 0.35 | +0.00 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.14 | 0.15 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.34 | 0.34 | +0.00 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.15 | 0.14 | -0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.61 | 0.61 | +0.00 | ±10% / ±0.06 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.15 | 0.15 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 1.02 | 1.03 | +0.01 | ±10% / ±0.10 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.39 | 0.39 | +0.00 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.05 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.36 | 0.36 | +0.00 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 4.22 | 4.33 | +0.11 | ±10% / ±0.43 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.04 | 0.05 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.37 | 0.40 | +0.03 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.09 | 0.10 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 4.67 | 5.32 | +0.65 | ±22% / ±1.17 ms | moderate | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.97 | 0.98 | +0.01 | ±10% / ±0.10 ms | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.21 | 0.24 | +0.03 | ±25% / ±0.06 ms | noisy | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.21 | 0.24 | +0.03 | ±25% / ±0.06 ms | noisy | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.13 | 0.04 | -0.09 | ±10% / ±0.02 ms | stable | 🟢 Win (-69%) |
| Streaming / Initial Emission / resqlite stream() [main] | 0.13 | 0.04 | -0.09 | ±10% / ±0.02 ms | stable | 🟢 Win (-69%) |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.06 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.05 | 0.06 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.48 | 2.46 | -0.02 | ±13% / ±0.33 ms | moderate | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.48 | 2.46 | -0.02 | ±13% / ±0.33 ms | moderate | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.43 | 0.27 | -0.16 | ±10% / ±0.04 ms | stable | 🟢 Win (-37%) |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.43 | 0.27 | -0.16 | ±10% / ±0.04 ms | stable | 🟢 Win (-37%) |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.43 | 0.44 | +0.01 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.49 | 4.66 | +0.17 | ±10% / ±0.47 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.65 | 0.63 | -0.02 | ±29% / ±0.19 ms | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.65 | 0.63 | -0.02 | ±29% / ±0.19 ms | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.08 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.08 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 5.80 | 5.95 | +0.15 | ±10% / ±0.60 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 5.80 | 5.95 | +0.15 | ±10% / ±0.60 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.45 | 0.48 | +0.03 | ±10% / ±0.05 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.45 | 0.48 | +0.03 | ±10% / ±0.05 ms | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.06 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.05 | 0.06 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.78 | 1.73 | -0.05 | ±10% / ±0.18 ms | stable | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.78 | 1.73 | -0.05 | ±10% / ±0.18 ms | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.19 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.19 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |

**Summary:** 4 wins, 0 regressions, 61 neutral

Comparison threshold uses `max(10%, 3 × current MAD%)`, plus an absolute floor of `±0.02 ms`.
That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

✅ **No regressions beyond noise.** 4 benchmarks improved.


