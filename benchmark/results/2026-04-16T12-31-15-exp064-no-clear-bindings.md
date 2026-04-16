# resqlite Benchmark Results

Generated: 2026-04-16T12:31:15.736582

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `exp064-no-clear-bindings`
- Repeats: `3`
- Comparison baseline: `2026-04-16T12-27-42-exp063-with-fastpath.md`

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
| resqlite select() | 0.39 | 0.41 | 0.10 | 0.10 |
| sqlite3 select() | 0.75 | 0.82 | 0.75 | 0.82 |
| sqlite_async getAll() | 0.69 | 0.75 | 0.16 | 0.18 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 5.52 | 7.06 | 0.99 | 1.13 |
| sqlite3 select() | 7.65 | 7.78 | 7.65 | 7.78 |
| sqlite_async getAll() | 7.97 | 9.67 | 1.67 | 1.92 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.01 | 0.01 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.04 | 0.04 | 0.04 | 0.04 |
| sqlite_async + jsonEncode | 0.05 | 0.06 | 0.02 | 0.03 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.06 | 0.06 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.27 | 0.29 | 0.27 | 0.29 |
| sqlite_async + jsonEncode | 0.28 | 0.32 | 0.20 | 0.22 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.50 | 0.54 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 2.72 | 5.41 | 2.72 | 5.41 |
| sqlite_async + jsonEncode | 2.68 | 5.27 | 2.06 | 3.79 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 5.62 | 6.07 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 30.61 | 32.27 | 30.61 | 32.27 |
| sqlite_async + jsonEncode | 31.09 | 35.00 | 21.87 | 24.18 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.12 | 0.13 | 0.05 | 0.06 |
| sqlite3 | 0.24 | 0.25 | 0.24 | 0.25 |
| sqlite_async | 0.27 | 0.31 | 0.10 | 0.11 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.03 | 1.10 | 0.39 | 0.41 |
| sqlite3 | 1.90 | 2.02 | 1.90 | 2.02 |
| sqlite_async | 1.62 | 1.84 | 0.54 | 0.56 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.60 | 0.65 | 0.15 | 0.16 |
| sqlite3 | 1.11 | 1.18 | 1.11 | 1.18 |
| sqlite_async | 1.05 | 1.13 | 0.22 | 0.24 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.33 | 0.35 | 0.14 | 0.15 |
| sqlite3 | 0.63 | 0.71 | 0.63 | 0.71 |
| sqlite_async | 0.60 | 0.64 | 0.22 | 0.24 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.35 | 0.37 | 0.15 | 0.15 |
| sqlite3 | 0.59 | 0.65 | 0.59 | 0.65 |
| sqlite_async | 0.60 | 0.69 | 0.22 | 0.25 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

| Rows | resqlite wall | resqlite main | sqlite3 wall | sqlite_async wall |
|---|---|---|---|---|
| 10 | 0.01 | 0.00 | 0.01 | 0.03 |
| 50 | 0.03 | 0.01 | 0.04 | 0.06 |
| 100 | 0.05 | 0.01 | 0.08 | 0.09 |
| 500 | 0.21 | 0.06 | 0.38 | 0.36 |
| 1000 | 0.40 | 0.13 | 0.76 | 0.70 |
| 2000 | 0.88 | 0.26 | 1.56 | 1.45 |
| 5000 | 2.44 | 0.65 | 4.00 | 3.84 |
| 10000 | 5.51 | 1.24 | 7.94 | 8.32 |
| 20000 | 13.32 | 2.49 | 22.69 | 25.30 |

### Bytes (selectBytes → JSON)

| Rows | resqlite wall | sqlite3+json wall | async+json wall |
|---|---|---|---|
| 10 | 0.01 | 0.03 | 0.05 |
| 50 | 0.03 | 0.14 | 0.15 |
| 100 | 0.06 | 0.26 | 0.28 |
| 500 | 0.26 | 1.28 | 1.30 |
| 1000 | 0.49 | 2.68 | 2.67 |
| 2000 | 1.10 | 5.91 | 5.81 |
| 5000 | 2.69 | 13.59 | 15.80 |
| 10000 | 5.22 | 29.59 | 31.60 |
| 20000 | 10.79 | 61.38 | 68.61 |

## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency).

| Concurrency | resqlite wall | resqlite/query | async wall | async/query |
|---|---|---|---|---|
| 1 | 0.29 | 0.29 | 0.51 | 0.51 |
| 2 | 0.32 | 0.16 | 0.64 | 0.32 |
| 4 | 0.38 | 0.10 | 0.65 | 0.16 |
| 8 | 0.71 | 0.09 | 1.26 | 0.16 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead of the reader pool.

| Metric | Value |
|---|---:|
| resqlite qps | 124069 |
| resqlite per query | 0.008 ms |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 14.56 | 14.94 | 14.56 | 14.94 |
| sqlite3 (no cache) | 23.49 | 24.01 | 23.49 | 24.01 |
| sqlite3 (cached stmt) | 23.10 | 23.64 | 23.10 | 23.64 |
| sqlite_async getAll() | 24.17 | 25.30 | 24.17 | 25.30 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 2.03 | 2.55 | 2.03 | 2.55 |
| sqlite3 execute() | 3.96 | 6.71 | 3.96 | 6.71 |
| sqlite_async execute() | 2.92 | 3.73 | 2.92 | 3.73 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.06 | 0.07 | 0.00 | 0.00 |
| sqlite3 (manual tx + stmt) | 0.09 | 0.12 | 0.09 | 0.12 |
| sqlite_async executeBatch() | 0.10 | 0.12 | 0.10 | 0.12 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.45 | 0.50 | 0.00 | 0.00 |
| sqlite3 (manual tx + stmt) | 0.52 | 0.61 | 0.52 | 0.61 |
| sqlite_async executeBatch() | 0.54 | 0.62 | 0.54 | 0.62 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.65 | 5.87 | 0.00 | 0.00 |
| sqlite3 (manual tx + stmt) | 4.44 | 4.89 | 4.44 | 4.89 |
| sqlite_async executeBatch() | 4.79 | 5.41 | 4.79 | 5.41 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.06 | 0.07 | 0.06 | 0.07 |
| sqlite_async writeTransaction() | 0.07 | 0.08 | 0.07 | 0.08 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.07 | 0.07 | 0.07 | 0.07 |
| resqlite tx.execute() loop | 0.65 | 0.81 | 0.65 | 0.81 |
| sqlite_async tx.execute() loop | 0.89 | 0.97 | 0.89 | 0.97 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.44 | 0.49 | 0.44 | 0.49 |
| resqlite tx.execute() loop | 5.90 | 6.58 | 5.90 | 6.58 |
| sqlite_async tx.execute() loop | 9.53 | 9.89 | 9.53 | 9.89 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.10 | 0.14 | 0.10 | 0.14 |
| sqlite_async tx.getAll() | 0.20 | 0.23 | 0.20 | 0.23 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.19 | 0.23 | 0.19 | 0.23 |
| sqlite_async tx.getAll() | 0.35 | 0.37 | 0.35 | 0.37 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.04 | 0.05 | 0.04 | 0.05 |
| sqlite_async watch() | 0.11 | 0.13 | 0.11 | 0.13 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.04 | 0.06 | 0.04 | 0.06 |
| sqlite_async | 0.06 | 0.09 | 0.06 | 0.09 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.16 | 0.26 | 0.16 | 0.26 |
| sqlite_async | 0.26 | 0.49 | 0.26 | 0.49 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.14 | 2.14 | 2.14 | 2.14 |
| sqlite_async | 10.51 | 10.51 | 10.51 | 10.51 |


## Repeat Stability

These rows summarize resqlite wall medians across repeated full-suite runs.
Use this section to judge whether small deltas are real or just noise.

| Benchmark | Median (ms) | Min | Max | Range | MAD | Stability |
|---|---|---|---|---|---|---|
| Concurrent Reads (1000 rows per query) / resqlite concurrent 1x | 0.29 | 0.29 | 0.30 | 3.4% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / resqlite concurrent 2x | 0.31 | 0.31 | 0.32 | 3.2% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / resqlite concurrent 4x | 0.37 | 0.35 | 0.38 | 8.1% | 2.7% | stable |
| Concurrent Reads (1000 rows per query) / resqlite concurrent 8x | 0.71 | 0.67 | 0.74 | 9.9% | 4.2% | moderate |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite sel... | 14.56 | 14.50 | 14.57 | 0.5% | 0.1% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite sel... | 14.56 | 14.50 | 14.57 | 0.5% | 0.1% | stable |
| Point Query Throughput / resqlite qps | 105130.00 | 104102.00 | 124069.00 | 19.0% | 1.0% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.12 | 0.11 | 0.12 | 8.3% | 0.0% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.05 | 0.04 | 0.05 | 20.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.34 | 0.34 | 0.35 | 2.9% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.14 | 0.14 | 0.15 | 7.1% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.35 | 0.33 | 0.35 | 5.7% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.15 | 0.14 | 0.15 | 6.7% | 0.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.60 | 0.59 | 0.60 | 1.7% | 0.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.15 | 0.15 | 0.15 | 0.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 1.02 | 1.01 | 1.03 | 2.0% | 1.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.39 | 0.38 | 0.39 | 2.6% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | 0.02 | 100.0% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.06 | 0.06 | 0.06 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.49 | 0.48 | 0.50 | 4.1% | 2.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 5.66 | 5.62 | 5.80 | 3.2% | 0.7% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | 0.08 | 700.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | 0.02 | 0.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.06 | 0.05 | 0.15 | 166.7% | 16.7% | noisy |
| Select → Maps / 100 rows / resqlite select() [main] | 0.02 | 0.01 | 0.03 | 100.0% | 50.0% | noisy |
| Select → Maps / 1000 rows / resqlite select() | 0.39 | 0.39 | 0.39 | 0.0% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.10 | 0.10 | 0.10 | 0.0% | 0.0% | stable |
| Select → Maps / 10000 rows / resqlite select() | 4.67 | 4.59 | 5.52 | 19.9% | 1.7% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.97 | 0.96 | 0.99 | 3.1% | 1.0% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.16 | 0.14 | 0.17 | 18.8% | 6.3% | moderate |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.16 | 0.14 | 0.17 | 18.8% | 6.3% | moderate |
| Streaming / Initial Emission / resqlite stream() | 0.04 | 0.03 | 0.06 | 75.0% | 25.0% | noisy |
| Streaming / Initial Emission / resqlite stream() [main] | 0.04 | 0.03 | 0.06 | 75.0% | 25.0% | noisy |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.04 | 0.05 | 25.0% | 0.0% | stable |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.04 | 0.05 | 25.0% | 0.0% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.24 | 2.14 | 2.31 | 7.6% | 3.1% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.24 | 2.14 | 2.31 | 7.6% | 3.1% | moderate |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.06 | 0.07 | 16.7% | 0.0% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.45 | 0.43 | 0.47 | 8.9% | 4.4% | moderate |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.60 | 4.38 | 4.65 | 5.9% | 1.1% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.59 | 0.58 | 0.65 | 11.9% | 1.7% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.59 | 0.58 | 0.65 | 11.9% | 1.7% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07 | 0.07 | 0.0% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07 | 0.07 | 0.0% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.90 | 5.69 | 5.97 | 4.7% | 1.2% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.90 | 5.69 | 5.97 | 4.7% | 1.2% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.45 | 0.44 | 0.47 | 6.7% | 2.2% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.45 | 0.44 | 0.47 | 6.7% | 2.2% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.06 | 0.06 | 0.06 | 0.0% | 0.0% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.06 | 0.06 | 0.06 | 0.0% | 0.0% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.69 | 1.57 | 2.03 | 27.2% | 7.1% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.69 | 1.57 | 2.03 | 27.2% | 7.1% | moderate |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.18 | 0.19 | 5.3% | 0.0% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.18 | 0.19 | 5.3% | 0.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.10 | 0.10 | 0.11 | 10.0% | 0.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.10 | 0.10 | 0.11 | 10.0% | 0.0% | stable |


## Comparison vs Previous Run

Previous: `2026-04-16T12-27-42-exp063-with-fastpath.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Noise threshold | Stability | Status |
|---|---|---|---|---|---|---|
| Concurrent Reads (1000 rows per query) / resqlite concurr... | 0.31 | 0.29 | -0.02 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / resqlite concurr... | 0.33 | 0.31 | -0.02 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / resqlite concurr... | 0.39 | 0.37 | -0.02 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / resqlite concurr... | 0.75 | 0.71 | -0.04 | ±13% / ±0.10 ms | moderate | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.70 | 14.56 | -0.14 | ±10% / ±1.47 ms | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.70 | 14.56 | -0.14 | ±10% / ±1.47 ms | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 125031.00 | 105130.00 | -19901.00 | ±10% / ±12503.10 ms | stable | 🔴 Regression (-16%) |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.11 | 0.12 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.34 | 0.34 | +0.00 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.14 | 0.14 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.33 | 0.35 | +0.02 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.14 | 0.15 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.61 | 0.60 | -0.01 | ±10% / ±0.06 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.15 | 0.15 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 1.01 | 1.02 | +0.01 | ±10% / ±0.10 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.38 | 0.39 | +0.01 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.49 | 0.49 | +0.00 | ±10% / ±0.05 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 5.58 | 5.66 | +0.08 | ±10% / ±0.57 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.06 | +0.01 | ±50% / ±0.03 ms | noisy | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.02 | +0.01 | ±150% / ±0.03 ms | noisy | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.37 | 0.39 | +0.02 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 5.27 | 4.67 | -0.60 | ±10% / ±0.53 ms | stable | 🟢 Win (-11%) |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.97 | 0.97 | +0.00 | ±10% / ±0.10 ms | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.16 | 0.16 | +0.00 | ±19% / ±0.03 ms | moderate | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.16 | 0.16 | +0.00 | ±19% / ±0.03 ms | moderate | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.04 | +0.01 | ±75% / ±0.03 ms | noisy | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.04 | +0.01 | ±75% / ±0.03 ms | noisy | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.29 | 2.24 | -0.05 | ±10% / ±0.23 ms | moderate | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.29 | 2.24 | -0.05 | ±10% / ±0.23 ms | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.05 | 0.06 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.44 | 0.45 | +0.01 | ±13% / ±0.06 ms | moderate | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.58 | 4.60 | +0.02 | ±10% / ±0.46 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.61 | 0.59 | -0.02 | ±10% / ±0.06 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.61 | 0.59 | -0.02 | ±10% / ±0.06 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.07 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.07 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 5.63 | 5.90 | +0.27 | ±10% / ±0.59 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 5.63 | 5.90 | +0.27 | ±10% / ±0.59 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.45 | 0.45 | +0.00 | ±10% / ±0.05 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.45 | 0.45 | +0.00 | ±10% / ±0.05 ms | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.58 | 1.69 | +0.11 | ±21% / ±0.36 ms | moderate | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.58 | 1.69 | +0.11 | ±21% / ±0.36 ms | moderate | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.19 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.19 | 0.19 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |

**Summary:** 1 wins, 1 regressions, 61 neutral

Comparison threshold uses `max(10%, 3 × current MAD%)`, plus an absolute floor of `±0.02 ms`.
That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


