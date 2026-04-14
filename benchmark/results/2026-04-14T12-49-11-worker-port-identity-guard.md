# resqlite Benchmark Results

Generated: 2026-04-14T12:49:11.961167

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `worker-port-identity-guard`
- Repeats: `3`
- Comparison baseline: `2026-04-14T10-22-58-event-port-cleanup.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.01 | 0.01 | 0.00 | 0.00 |
| sqlite3 select() | 0.01 | 0.01 | 0.01 | 0.01 |
| sqlite_async getAll() | 0.03 | 0.03 | 0.00 | 0.00 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.05 | 0.05 | 0.01 | 0.01 |
| sqlite3 select() | 0.08 | 0.08 | 0.08 | 0.08 |
| sqlite_async getAll() | 0.09 | 0.09 | 0.02 | 0.02 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.38 | 0.45 | 0.10 | 0.10 |
| sqlite3 select() | 0.76 | 0.88 | 0.76 | 0.88 |
| sqlite_async getAll() | 0.70 | 0.87 | 0.16 | 0.19 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 5.33 | 6.87 | 0.98 | 1.14 |
| sqlite3 select() | 7.83 | 8.86 | 7.83 | 8.86 |
| sqlite_async getAll() | 7.86 | 9.43 | 1.67 | 1.82 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.01 | 0.02 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.03 | 0.03 | 0.03 | 0.03 |
| sqlite_async + jsonEncode | 0.05 | 0.05 | 0.02 | 0.02 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.06 | 0.06 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.27 | 0.28 | 0.27 | 0.28 |
| sqlite_async + jsonEncode | 0.27 | 0.28 | 0.20 | 0.20 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.49 | 0.52 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 2.61 | 4.93 | 2.61 | 4.93 |
| sqlite_async + jsonEncode | 2.50 | 4.42 | 1.96 | 3.53 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 5.39 | 6.06 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 29.54 | 32.23 | 29.54 | 32.23 |
| sqlite_async + jsonEncode | 30.80 | 32.91 | 21.50 | 23.37 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.12 | 0.13 | 0.05 | 0.05 |
| sqlite3 | 0.22 | 0.26 | 0.22 | 0.26 |
| sqlite_async | 0.27 | 0.33 | 0.09 | 0.10 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.05 | 1.18 | 0.39 | 0.44 |
| sqlite3 | 1.92 | 1.99 | 1.92 | 1.99 |
| sqlite_async | 1.64 | 1.95 | 0.52 | 0.56 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.58 | 0.59 | 0.15 | 0.15 |
| sqlite3 | 1.07 | 1.14 | 1.07 | 1.14 |
| sqlite_async | 1.01 | 1.06 | 0.21 | 0.22 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.33 | 0.35 | 0.14 | 0.15 |
| sqlite3 | 0.63 | 0.73 | 0.63 | 0.73 |
| sqlite_async | 0.58 | 0.65 | 0.21 | 0.22 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.33 | 0.34 | 0.14 | 0.15 |
| sqlite3 | 0.60 | 0.67 | 0.60 | 0.67 |
| sqlite_async | 0.63 | 0.65 | 0.23 | 0.25 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

| Rows | resqlite wall | resqlite main | sqlite3 wall | sqlite_async wall |
|---|---|---|---|---|
| 10 | 0.01 | 0.00 | 0.01 | 0.03 |
| 50 | 0.03 | 0.01 | 0.04 | 0.05 |
| 100 | 0.05 | 0.01 | 0.08 | 0.09 |
| 500 | 0.21 | 0.06 | 0.39 | 0.38 |
| 1000 | 0.42 | 0.13 | 0.78 | 0.72 |
| 2000 | 0.88 | 0.25 | 1.65 | 1.49 |
| 5000 | 2.31 | 0.63 | 4.01 | 4.06 |
| 10000 | 5.90 | 1.27 | 8.72 | 9.37 |
| 20000 | 11.59 | 2.50 | 20.88 | 26.24 |

### Bytes (selectBytes → JSON)

| Rows | resqlite wall | sqlite3+json wall | async+json wall |
|---|---|---|---|
| 10 | 0.01 | 0.03 | 0.05 |
| 50 | 0.03 | 0.14 | 0.15 |
| 100 | 0.06 | 0.28 | 0.28 |
| 500 | 0.25 | 1.33 | 1.28 |
| 1000 | 0.49 | 2.59 | 2.56 |
| 2000 | 1.04 | 5.77 | 5.44 |
| 5000 | 2.52 | 15.60 | 17.34 |
| 10000 | 5.48 | 28.45 | 30.01 |
| 20000 | 10.75 | 62.63 | 66.58 |

## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency).

| Concurrency | resqlite wall | resqlite/query | async wall | async/query |
|---|---|---|---|---|
| 1 | 0.29 | 0.29 | 0.55 | 0.55 |
| 2 | 0.32 | 0.16 | 0.58 | 0.29 |
| 4 | 0.44 | 0.11 | 0.64 | 0.16 |
| 8 | 0.81 | 0.10 | 1.25 | 0.16 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead of the reader pool.

| Metric | Value |
|---|---:|
| resqlite qps | 141764 |
| resqlite per query | 0.007 ms |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 14.46 | 14.72 | 14.46 | 14.72 |
| sqlite3 (no cache) | 22.97 | 23.24 | 22.97 | 23.24 |
| sqlite3 (cached stmt) | 22.66 | 24.33 | 22.66 | 24.33 |
| sqlite_async getAll() | 23.01 | 24.05 | 23.01 | 24.05 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.52 | 2.40 | 1.52 | 2.40 |
| sqlite3 execute() | 3.94 | 6.18 | 3.94 | 6.18 |
| sqlite_async execute() | 2.94 | 3.80 | 2.94 | 3.80 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.06 | 0.06 | 0.00 | 0.00 |
| sqlite3 (manual tx + stmt) | 0.10 | 0.12 | 0.10 | 0.12 |
| sqlite_async executeBatch() | 0.09 | 0.11 | 0.09 | 0.11 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.42 | 0.49 | 0.00 | 0.00 |
| sqlite3 (manual tx + stmt) | 0.51 | 0.55 | 0.51 | 0.55 |
| sqlite_async executeBatch() | 0.54 | 0.65 | 0.54 | 0.65 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.36 | 5.17 | 0.00 | 0.00 |
| sqlite3 (manual tx + stmt) | 4.34 | 4.60 | 4.34 | 4.60 |
| sqlite_async executeBatch() | 4.79 | 5.08 | 4.79 | 5.08 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.05 | 0.06 | 0.05 | 0.06 |
| sqlite_async writeTransaction() | 0.08 | 0.09 | 0.08 | 0.09 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.07 | 0.08 | 0.07 | 0.08 |
| resqlite tx.execute() loop | 0.68 | 0.85 | 0.68 | 0.85 |
| sqlite_async tx.execute() loop | 0.98 | 1.22 | 0.98 | 1.22 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.44 | 0.48 | 0.44 | 0.48 |
| resqlite tx.execute() loop | 5.48 | 5.86 | 5.48 | 5.86 |
| sqlite_async tx.execute() loop | 9.64 | 13.18 | 9.64 | 13.18 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.10 | 0.11 | 0.10 | 0.11 |
| sqlite_async tx.getAll() | 0.20 | 0.24 | 0.20 | 0.24 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.19 | 0.22 | 0.19 | 0.22 |
| sqlite_async tx.getAll() | 0.37 | 0.41 | 0.37 | 0.41 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.03 | 0.04 | 0.03 | 0.04 |
| sqlite_async watch() | 0.11 | 0.16 | 0.11 | 0.16 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.04 | 0.07 | 0.04 | 0.07 |
| sqlite_async | 0.06 | 0.10 | 0.06 | 0.10 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.18 | 0.21 | 0.18 | 0.21 |
| sqlite_async | 0.27 | 0.50 | 0.27 | 0.50 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 4.43 | 4.43 | 4.43 | 4.43 |
| sqlite_async | 11.72 | 11.72 | 11.72 | 11.72 |


## Repeat Stability

These rows summarize resqlite wall medians across repeated full-suite runs.
Use this section to judge whether small deltas are real or just noise.

| Benchmark | Median (ms) | Min | Max | Range | MAD | Stability |
|---|---|---|---|---|---|---|
| Concurrent Reads (1000 rows per query) / resqlite concurrent 1x | 0.29 | 0.29 | 0.30 | 3.4% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / resqlite concurrent 2x | 0.31 | 0.30 | 0.32 | 6.5% | 3.2% | moderate |
| Concurrent Reads (1000 rows per query) / resqlite concurrent 4x | 0.37 | 0.35 | 0.44 | 24.3% | 5.4% | moderate |
| Concurrent Reads (1000 rows per query) / resqlite concurrent 8x | 0.71 | 0.67 | 0.81 | 19.7% | 5.6% | moderate |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite sel... | 14.28 | 14.10 | 14.46 | 2.5% | 1.3% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite sel... | 14.28 | 14.10 | 14.46 | 2.5% | 1.3% | stable |
| Point Query Throughput / resqlite qps | 133869.00 | 104297.00 | 141764.00 | 28.0% | 5.9% | moderate |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.11 | 0.11 | 0.12 | 9.1% | 0.0% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.05 | 0.04 | 0.05 | 20.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.34 | 0.33 | 0.34 | 2.9% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.14 | 0.14 | 0.15 | 7.1% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.34 | 0.33 | 0.34 | 2.9% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.15 | 0.14 | 0.15 | 6.7% | 0.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.60 | 0.58 | 0.61 | 5.0% | 1.7% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.15 | 0.15 | 0.15 | 0.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 1.02 | 1.02 | 1.05 | 2.9% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.39 | 0.39 | 0.39 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.02 | 0.01 | 0.02 | 50.0% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.06 | 0.06 | 0.06 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.49 | 0.49 | 0.49 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 5.48 | 5.39 | 5.58 | 3.5% | 1.6% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | 0.08 | 700.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | 0.02 | 0.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.06 | 0.05 | 0.09 | 66.7% | 16.7% | noisy |
| Select → Maps / 100 rows / resqlite select() [main] | 0.02 | 0.01 | 0.03 | 100.0% | 50.0% | noisy |
| Select → Maps / 1000 rows / resqlite select() | 0.39 | 0.38 | 0.41 | 7.7% | 2.6% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.10 | 0.10 | 0.10 | 0.0% | 0.0% | stable |
| Select → Maps / 10000 rows / resqlite select() | 4.71 | 4.55 | 5.33 | 16.6% | 3.4% | moderate |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.96 | 0.94 | 0.98 | 4.2% | 2.1% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.17 | 0.17 | 0.18 | 5.9% | 0.0% | stable |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.17 | 0.17 | 0.18 | 5.9% | 0.0% | stable |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | 0.08 | 166.7% | 0.0% | stable |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03 | 0.08 | 166.7% | 0.0% | stable |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.04 | 0.06 | 40.0% | 20.0% | noisy |
| Streaming / Invalidation Latency / resqlite [main] | 0.05 | 0.04 | 0.06 | 40.0% | 20.0% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.61 | 2.49 | 4.43 | 74.3% | 4.6% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.61 | 2.49 | 4.43 | 74.3% | 4.6% | moderate |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.06 | 0.07 | 16.7% | 0.0% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.43 | 0.42 | 0.44 | 4.7% | 2.3% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.51 | 4.36 | 4.55 | 4.2% | 0.9% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.68 | 0.64 | 0.68 | 5.9% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.68 | 0.64 | 0.68 | 5.9% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07 | 0.08 | 14.3% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07 | 0.08 | 14.3% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.58 | 5.48 | 6.09 | 10.9% | 1.8% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 5.58 | 5.48 | 6.09 | 10.9% | 1.8% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.44 | 0.44 | 0.45 | 2.3% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.44 | 0.44 | 0.45 | 2.3% | 0.0% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05 | 0.06 | 20.0% | 0.0% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05 | 0.06 | 20.0% | 0.0% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.52 | 1.46 | 1.61 | 9.9% | 3.9% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.52 | 1.46 | 1.61 | 9.9% | 3.9% | moderate |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.19 | 0.19 | 0.0% | 0.0% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.19 | 0.19 | 0.0% | 0.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.11 | 0.10 | 0.11 | 9.1% | 0.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.11 | 0.10 | 0.11 | 9.1% | 0.0% | stable |


## Comparison vs Previous Run

Previous: `2026-04-14T10-22-58-event-port-cleanup.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Noise threshold | Stability | Status |
|---|---|---|---|---|---|---|
| Concurrent Reads (1000 rows per query) / resqlite concurr... | 0.30 | 0.29 | -0.01 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / resqlite concurr... | 0.35 | 0.31 | -0.04 | ±10% / ±0.03 ms | moderate | 🟢 Win (-11%) |
| Concurrent Reads (1000 rows per query) / resqlite concurr... | 0.37 | 0.37 | +0.00 | ±16% / ±0.06 ms | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / resqlite concurr... | 0.71 | 0.71 | +0.00 | ±17% / ±0.12 ms | moderate | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.66 | 14.28 | -0.38 | ±10% / ±1.47 ms | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.66 | 14.28 | -0.38 | ±10% / ±1.47 ms | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 116659.00 | 133869.00 | +17210.00 | ±18% / ±23685.00 ms | moderate | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.33 | 0.34 | +0.01 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.14 | 0.14 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.33 | 0.34 | +0.01 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.15 | 0.15 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.62 | 0.60 | -0.02 | ±10% / ±0.06 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.15 | 0.15 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 1.01 | 1.02 | +0.01 | ±10% / ±0.10 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.38 | 0.39 | +0.01 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.02 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.48 | 0.49 | +0.01 | ±10% / ±0.05 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 5.88 | 5.48 | -0.40 | ±10% / ±0.59 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.06 | +0.01 | ±50% / ±0.03 ms | noisy | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.02 | +0.01 | ±150% / ±0.03 ms | noisy | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.38 | 0.39 | +0.01 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 4.74 | 4.71 | -0.03 | ±10% / ±0.48 ms | moderate | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.98 | 0.96 | -0.02 | ±10% / ±0.10 ms | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.14 | 0.17 | +0.03 | ±10% / ±0.02 ms | stable | 🔴 Regression (+21%) |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.14 | 0.17 | +0.03 | ±10% / ±0.02 ms | stable | 🔴 Regression (+21%) |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.04 | 0.05 | +0.01 | ±60% / ±0.03 ms | noisy | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.04 | 0.05 | +0.01 | ±60% / ±0.03 ms | noisy | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.06 | 2.61 | +0.55 | ±14% / ±0.36 ms | moderate | 🔴 Regression (+27%) |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.06 | 2.61 | +0.55 | ±14% / ±0.36 ms | moderate | 🔴 Regression (+27%) |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.45 | 0.43 | -0.02 | ±10% / ±0.05 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.42 | 4.51 | +0.09 | ±10% / ±0.45 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.64 | 0.68 | +0.04 | ±10% / ±0.07 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.64 | 0.68 | +0.04 | ±10% / ±0.07 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.08 | 0.07 | -0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.08 | 0.07 | -0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 6.92 | 5.58 | -1.34 | ±10% / ±0.69 ms | stable | 🟢 Win (-19%) |
| Write Performance / Batched Write Inside Transaction (100... | 6.92 | 5.58 | -1.34 | ±10% / ±0.69 ms | stable | 🟢 Win (-19%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.46 | 0.44 | -0.02 | ±10% / ±0.05 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.46 | 0.44 | -0.02 | ±10% / ±0.05 ms | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.05 | -0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.05 | -0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 2.03 | 1.52 | -0.51 | ±12% / ±0.24 ms | moderate | 🟢 Win (-25%) |
| Write Performance / Single Inserts (100 sequential) / res... | 2.03 | 1.52 | -0.51 | ±12% / ±0.24 ms | moderate | 🟢 Win (-25%) |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.20 | 0.19 | -0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.20 | 0.19 | -0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.11 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.10 | 0.11 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |

**Summary:** 5 wins, 4 regressions, 54 neutral

Comparison threshold uses `max(10%, 3 × current MAD%)`, plus an absolute floor of `±0.02 ms`.
That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


