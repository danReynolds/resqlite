# resqlite Benchmark Results

Generated: 2026-04-15T19:10:43.948623

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp045-microtask-coalesce`
- Repeats: `3`
- Comparison baseline: `2026-04-15T18-57-06-baseline.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.01 | 0.02 | 0.00 | 0.00 |
| sqlite3 select() | 0.01 | 0.01 | 0.01 | 0.01 |
| sqlite_async getAll() | 0.03 | 0.03 | 0.00 | 0.00 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.05 | 0.05 | 0.01 | 0.01 |
| sqlite3 select() | 0.08 | 0.08 | 0.08 | 0.08 |
| sqlite_async getAll() | 0.09 | 0.10 | 0.02 | 0.02 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.39 | 0.44 | 0.10 | 0.10 |
| sqlite3 select() | 0.75 | 0.80 | 0.75 | 0.80 |
| sqlite_async getAll() | 0.70 | 0.74 | 0.16 | 0.17 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.59 | 8.10 | 0.97 | 1.10 |
| sqlite3 select() | 7.55 | 9.18 | 7.55 | 9.18 |
| sqlite_async getAll() | 7.56 | 9.20 | 1.65 | 2.30 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.01 | 0.02 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.03 | 0.04 | 0.03 | 0.04 |
| sqlite_async + jsonEncode | 0.05 | 0.05 | 0.02 | 0.02 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.06 | 0.06 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.28 | 0.29 | 0.28 | 0.29 |
| sqlite_async + jsonEncode | 0.28 | 0.30 | 0.21 | 0.22 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.49 | 0.52 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 2.67 | 5.50 | 2.67 | 5.50 |
| sqlite_async + jsonEncode | 2.60 | 4.86 | 2.03 | 3.70 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 5.43 | 6.17 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 28.81 | 31.28 | 28.81 | 31.28 |
| sqlite_async + jsonEncode | 32.04 | 33.62 | 22.32 | 24.01 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.12 | 0.14 | 0.05 | 0.06 |
| sqlite3 | 0.22 | 0.26 | 0.22 | 0.26 |
| sqlite_async | 0.27 | 0.32 | 0.09 | 0.10 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.99 | 1.02 | 0.38 | 0.39 |
| sqlite3 | 1.86 | 1.92 | 1.86 | 1.92 |
| sqlite_async | 1.57 | 1.74 | 0.51 | 0.52 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.58 | 0.60 | 0.15 | 0.15 |
| sqlite3 | 1.06 | 1.14 | 1.06 | 1.14 |
| sqlite_async | 1.01 | 1.08 | 0.21 | 0.22 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.34 | 0.35 | 0.15 | 0.16 |
| sqlite3 | 0.62 | 0.66 | 0.62 | 0.66 |
| sqlite_async | 0.59 | 0.63 | 0.21 | 0.22 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.34 | 0.36 | 0.15 | 0.16 |
| sqlite3 | 0.60 | 0.65 | 0.60 | 0.65 |
| sqlite_async | 0.60 | 0.62 | 0.22 | 0.23 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

| Rows | resqlite wall | resqlite main | sqlite3 wall | sqlite_async wall |
|---|---|---|---|---|
| 10 | 0.01 | 0.00 | 0.01 | 0.03 |
| 50 | 0.03 | 0.01 | 0.04 | 0.06 |
| 100 | 0.05 | 0.01 | 0.08 | 0.09 |
| 500 | 0.21 | 0.07 | 0.39 | 0.37 |
| 1000 | 0.41 | 0.13 | 0.77 | 0.71 |
| 2000 | 0.86 | 0.26 | 1.53 | 1.45 |
| 5000 | 2.33 | 0.65 | 3.87 | 3.76 |
| 10000 | 4.75 | 1.28 | 7.92 | 7.97 |
| 20000 | 13.22 | 2.57 | 22.37 | 26.99 |

### Bytes (selectBytes → JSON)

| Rows | resqlite wall | sqlite3+json wall | async+json wall |
|---|---|---|---|
| 10 | 0.01 | 0.03 | 0.05 |
| 50 | 0.03 | 0.14 | 0.15 |
| 100 | 0.06 | 0.28 | 0.29 |
| 500 | 0.26 | 1.33 | 1.34 |
| 1000 | 0.49 | 2.62 | 2.60 |
| 2000 | 1.05 | 5.75 | 5.44 |
| 5000 | 2.90 | 13.24 | 14.80 |
| 10000 | 5.54 | 29.24 | 30.36 |
| 20000 | 11.00 | 61.44 | 66.97 |

## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency).

| Concurrency | resqlite wall | resqlite/query | async wall | async/query |
|---|---|---|---|---|
| 1 | 0.29 | 0.29 | 0.52 | 0.52 |
| 2 | 0.30 | 0.15 | 0.55 | 0.28 |
| 4 | 0.39 | 0.10 | 0.65 | 0.16 |
| 8 | 0.69 | 0.09 | 1.31 | 0.16 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead of the reader pool.

| Metric | Value |
|---|---:|
| resqlite qps | 139587 |
| resqlite per query | 0.007 ms |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 14.35 | 14.74 | 14.35 | 14.74 |
| sqlite3 (no cache) | 23.18 | 23.44 | 23.18 | 23.44 |
| sqlite3 (cached stmt) | 22.76 | 23.14 | 22.76 | 23.14 |
| sqlite_async getAll() | 23.83 | 24.29 | 23.83 | 24.29 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.58 | 2.42 | 1.58 | 2.42 |
| sqlite3 execute() | 3.41 | 5.11 | 3.41 | 5.11 |
| sqlite_async execute() | 2.76 | 3.50 | 2.76 | 3.50 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.06 | 0.06 | 0.00 | 0.00 |
| sqlite3 (manual tx + stmt) | 0.09 | 0.10 | 0.09 | 0.10 |
| sqlite_async executeBatch() | 0.09 | 0.11 | 0.09 | 0.11 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.45 | 0.48 | 0.00 | 0.00 |
| sqlite3 (manual tx + stmt) | 0.50 | 0.54 | 0.50 | 0.54 |
| sqlite_async executeBatch() | 0.52 | 0.63 | 0.52 | 0.63 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.43 | 7.29 | 0.00 | 0.00 |
| sqlite3 (manual tx + stmt) | 4.20 | 4.57 | 4.20 | 4.57 |
| sqlite_async executeBatch() | 4.77 | 5.36 | 4.77 | 5.36 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.05 | 0.06 | 0.05 | 0.06 |
| sqlite_async writeTransaction() | 0.07 | 0.08 | 0.07 | 0.08 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.07 | 0.07 | 0.07 | 0.07 |
| resqlite tx.execute() loop | 0.55 | 0.77 | 0.55 | 0.77 |
| sqlite_async tx.execute() loop | 0.92 | 1.07 | 0.92 | 1.07 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.44 | 0.50 | 0.44 | 0.50 |
| resqlite tx.execute() loop | 5.61 | 6.28 | 5.61 | 6.28 |
| sqlite_async tx.execute() loop | 9.03 | 9.27 | 9.03 | 9.27 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.11 | 0.15 | 0.11 | 0.15 |
| sqlite_async tx.getAll() | 0.19 | 0.21 | 0.19 | 0.21 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.18 | 0.22 | 0.18 | 0.22 |
| sqlite_async tx.getAll() | 0.34 | 0.38 | 0.34 | 0.38 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.03 | 0.04 | 0.03 | 0.04 |
| sqlite_async watch() | 0.11 | 0.14 | 0.11 | 0.14 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.04 | 0.06 | 0.04 | 0.06 |
| sqlite_async | 0.05 | 0.07 | 0.05 | 0.07 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.13 | 0.22 | 0.13 | 0.22 |
| sqlite_async | 0.24 | 0.33 | 0.24 | 0.33 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.94 | 1.94 | 1.94 | 1.94 |
| sqlite_async | 9.83 | 9.83 | 9.83 | 9.83 |


## Repeat Stability

These rows summarize resqlite wall medians across repeated full-suite runs.
Use this section to judge whether small deltas are real or just noise.

| Benchmark | Median (ms) | Min | Max | Range | MAD | Stability |
|---|---|---|---|---|---|---|
| Concurrent Reads (1000 rows per query) / resqlite concurrent 1x | 0.29 | 0.29 | 0.29 | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / resqlite concurrent 2x | 0.31 | 0.30 | 0.31 | 3.2% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / resqlite concurrent 4x | 0.37 | 0.36 | 0.39 | 8.1% | 2.7% | stable |
| Concurrent Reads (1000 rows per query) / resqlite concurrent 8x | 0.69 | 0.68 | 0.69 | 1.4% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite sel... | 14.35 | 14.17 | 14.35 | 1.3% | 0.0% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite sel... | 14.35 | 14.17 | 14.35 | 1.3% | 0.0% | stable |
| Point Query Throughput / resqlite qps | 131996.00 | 123244.00 | 139587.00 | 12.4% | 5.8% | moderate |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.12 | 0.11 | 0.12 | 8.3% | 0.0% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.05 | 0.04 | 0.05 | 20.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.34 | 0.34 | 0.35 | 2.9% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.15 | 0.15 | 0.15 | 0.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.34 | 0.34 | 0.34 | 0.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.15 | 0.15 | 0.15 | 0.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.59 | 0.58 | 0.59 | 1.7% | 0.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.15 | 0.15 | 0.15 | 0.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 0.99 | 0.99 | 1.00 | 1.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.38 | 0.38 | 0.38 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | 0.02 | 100.0% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.06 | 0.06 | 0.06 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.48 | 0.48 | 0.49 | 2.1% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 5.43 | 5.37 | 5.60 | 4.2% | 1.1% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | 0.08 | 700.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | 0.02 | 0.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.06 | 0.05 | 0.10 | 83.3% | 16.7% | noisy |
| Select → Maps / 100 rows / resqlite select() [main] | 0.02 | 0.01 | 0.03 | 100.0% | 50.0% | noisy |
| Select → Maps / 1000 rows / resqlite select() | 0.39 | 0.38 | 0.41 | 7.7% | 2.6% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.10 | 0.10 | 0.10 | 0.0% | 0.0% | stable |
| Select → Maps / 10000 rows / resqlite select() | 4.59 | 4.58 | 5.42 | 18.3% | 0.2% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.97 | 0.97 | 0.98 | 1.0% | 0.0% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.13 | 0.13 | 0.16 | 23.1% | 0.0% | stable |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.13 | 0.13 | 0.16 | 23.1% | 0.0% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | 0.06 | 100.0% | 0.0% | stable |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03 | 0.06 | 100.0% | 0.0% | stable |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.04 | 0.05 | 25.0% | 0.0% | stable |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.04 | 0.05 | 25.0% | 0.0% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.42 | 1.94 | 2.96 | 42.1% | 19.8% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.42 | 1.94 | 2.96 | 42.1% | 19.8% | noisy |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.06 | 0.07 | 16.7% | 0.0% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.45 | 0.45 | 0.45 | 0.0% | 0.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.51 | 4.43 | 4.72 | 6.4% | 1.8% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.55 | 0.54 | 0.59 | 9.1% | 1.8% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.55 | 0.54 | 0.59 | 9.1% | 1.8% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07 | 0.07 | 0.0% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07 | 0.07 | 0.0% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.66 | 5.61 | 5.67 | 1.1% | 0.2% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.66 | 5.61 | 5.67 | 1.1% | 0.2% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.45 | 0.44 | 0.47 | 6.7% | 2.2% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.45 | 0.44 | 0.47 | 6.7% | 2.2% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05 | 0.06 | 20.0% | 0.0% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05 | 0.06 | 20.0% | 0.0% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.61 | 1.58 | 1.61 | 1.9% | 0.0% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.61 | 1.58 | 1.61 | 1.9% | 0.0% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.18 | 0.19 | 5.6% | 0.0% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.18 | 0.19 | 5.6% | 0.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.10 | 0.10 | 0.11 | 10.0% | 0.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.10 | 0.10 | 0.11 | 10.0% | 0.0% | stable |


## Comparison vs Previous Run

Previous: `2026-04-15T18-57-06-baseline.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Noise threshold | Stability | Status |
|---|---|---|---|---|---|---|
| Concurrent Reads (1000 rows per query) / resqlite concurr... | 0.30 | 0.29 | -0.01 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / resqlite concurr... | 0.33 | 0.31 | -0.02 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / resqlite concurr... | 0.37 | 0.37 | +0.00 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / resqlite concurr... | 0.77 | 0.69 | -0.08 | ±10% / ±0.08 ms | stable | 🟢 Win (-10%) |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 15.89 | 14.35 | -1.54 | ±10% / ±1.59 ms | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 15.89 | 14.35 | -1.54 | ±10% / ±1.59 ms | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 60161.00 | 131996.00 | +71835.00 | ±17% / ±22773.00 ms | moderate | 🟢 Win (119%) |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.12 | 0.12 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.35 | 0.34 | -0.01 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.14 | 0.15 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.35 | 0.34 | -0.01 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.15 | 0.15 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.67 | 0.59 | -0.08 | ±10% / ±0.07 ms | stable | 🟢 Win (-12%) |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.15 | 0.15 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 1.00 | 0.99 | -0.01 | ±10% / ±0.10 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.38 | 0.38 | +0.00 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.02 | 0.01 | -0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.51 | 0.48 | -0.03 | ±10% / ±0.05 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 5.70 | 5.43 | -0.27 | ±10% / ±0.57 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.02 | 0.01 | -0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.06 | +0.01 | ±50% / ±0.03 ms | noisy | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.02 | +0.01 | ±150% / ±0.03 ms | noisy | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.40 | 0.39 | -0.01 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 4.77 | 4.59 | -0.18 | ±10% / ±0.48 ms | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 1.00 | 0.97 | -0.03 | ±10% / ±0.10 ms | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.24 | 0.13 | -0.11 | ±10% / ±0.02 ms | stable | 🟢 Win (-46%) |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.24 | 0.13 | -0.11 | ±10% / ±0.02 ms | stable | 🟢 Win (-46%) |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.04 | -0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.05 | 0.04 | -0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.41 | 2.42 | +0.01 | ±60% / ±1.44 ms | noisy | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.41 | 2.42 | +0.01 | ±60% / ±1.44 ms | noisy | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.46 | 0.45 | -0.01 | ±10% / ±0.05 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 6.26 | 4.51 | -1.75 | ±10% / ±0.63 ms | stable | 🟢 Win (-28%) |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.83 | 0.55 | -0.28 | ±10% / ±0.08 ms | stable | 🟢 Win (-34%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.83 | 0.55 | -0.28 | ±10% / ±0.08 ms | stable | 🟢 Win (-34%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.08 | 0.07 | -0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.08 | 0.07 | -0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 7.05 | 5.66 | -1.39 | ±10% / ±0.71 ms | stable | 🟢 Win (-20%) |
| Write Performance / Batched Write Inside Transaction (100... | 7.05 | 5.66 | -1.39 | ±10% / ±0.71 ms | stable | 🟢 Win (-20%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.50 | 0.45 | -0.05 | ±10% / ±0.05 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.50 | 0.45 | -0.05 | ±10% / ±0.05 ms | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.09 | 0.05 | -0.04 | ±10% / ±0.02 ms | stable | 🟢 Win (-44%) |
| Write Performance / Interactive Transaction (insert + sel... | 0.09 | 0.05 | -0.04 | ±10% / ±0.02 ms | stable | 🟢 Win (-44%) |
| Write Performance / Single Inserts (100 sequential) / res... | 1.99 | 1.61 | -0.38 | ±10% / ±0.20 ms | stable | 🟢 Win (-19%) |
| Write Performance / Single Inserts (100 sequential) / res... | 1.99 | 1.61 | -0.38 | ±10% / ±0.20 ms | stable | 🟢 Win (-19%) |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.20 | 0.18 | -0.02 | ±10% / ±0.02 ms | stable | 🟢 Win (-10%) |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.20 | 0.18 | -0.02 | ±10% / ±0.02 ms | stable | 🟢 Win (-10%) |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.13 | 0.10 | -0.03 | ±10% / ±0.02 ms | stable | 🟢 Win (-23%) |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.13 | 0.10 | -0.03 | ±10% / ±0.02 ms | stable | 🟢 Win (-23%) |

**Summary:** 18 wins, 0 regressions, 45 neutral

Comparison threshold uses `max(10%, 3 × current MAD%)`, plus an absolute floor of `±0.02 ms`.
That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

✅ **No regressions beyond noise.** 18 benchmarks improved.


