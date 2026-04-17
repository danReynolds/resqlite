# resqlite Benchmark Results

Generated: 2026-04-16T22:30:30.988036

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `rolling-history`
- Repeats: `3`
- Comparison baseline: `2026-04-16T18-00-15-round5-aggregate.md`

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.01 | 0.03 | 0.00 | 0.00 |
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
| resqlite select() | 0.37 | 0.42 | 0.10 | 0.10 |
| sqlite3 select() | 0.74 | 0.90 | 0.74 | 0.90 |
| sqlite_async getAll() | 0.69 | 0.80 | 0.16 | 0.18 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 5.73 | 10.59 | 1.02 | 1.18 |
| sqlite3 select() | 7.77 | 8.08 | 7.77 | 8.08 |
| sqlite_async getAll() | 8.13 | 9.92 | 1.80 | 1.97 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.01 | 0.02 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.03 | 0.05 | 0.03 | 0.05 |
| sqlite_async + jsonEncode | 0.05 | 0.06 | 0.02 | 0.03 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.04 | 0.07 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.27 | 0.29 | 0.27 | 0.29 |
| sqlite_async + jsonEncode | 0.28 | 0.29 | 0.20 | 0.21 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.35 | 0.42 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 2.81 | 5.09 | 2.81 | 5.09 |
| sqlite_async + jsonEncode | 2.76 | 5.08 | 2.13 | 3.68 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 4.01 | 4.96 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 29.63 | 31.55 | 29.63 | 31.55 |
| sqlite_async + jsonEncode | 32.06 | 33.18 | 22.15 | 23.90 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.12 | 0.15 | 0.05 | 0.07 |
| sqlite3 | 0.22 | 0.24 | 0.22 | 0.24 |
| sqlite_async | 0.27 | 0.33 | 0.09 | 0.10 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.00 | 1.15 | 0.38 | 0.44 |
| sqlite3 | 1.90 | 2.07 | 1.90 | 2.07 |
| sqlite_async | 1.64 | 1.77 | 0.53 | 0.56 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.62 | 0.69 | 0.15 | 0.17 |
| sqlite3 | 1.08 | 1.21 | 1.08 | 1.21 |
| sqlite_async | 1.03 | 1.35 | 0.21 | 0.24 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.33 | 0.35 | 0.14 | 0.15 |
| sqlite3 | 0.63 | 0.73 | 0.63 | 0.73 |
| sqlite_async | 0.58 | 0.73 | 0.21 | 0.23 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.35 | 0.39 | 0.15 | 0.15 |
| sqlite3 | 0.64 | 0.68 | 0.64 | 0.68 |
| sqlite_async | 0.60 | 0.66 | 0.22 | 0.23 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

| Rows | resqlite wall | resqlite main | sqlite3 wall | sqlite_async wall |
|---|---|---|---|---|
| 10 | 0.01 | 0.00 | 0.01 | 0.03 |
| 50 | 0.03 | 0.01 | 0.04 | 0.06 |
| 100 | 0.05 | 0.01 | 0.08 | 0.09 |
| 500 | 0.21 | 0.06 | 0.39 | 0.38 |
| 1000 | 0.42 | 0.13 | 0.81 | 0.75 |
| 2000 | 0.91 | 0.26 | 1.62 | 1.51 |
| 5000 | 2.38 | 0.63 | 4.02 | 4.14 |
| 10000 | 5.72 | 1.27 | 8.36 | 8.85 |
| 20000 | 11.43 | 2.52 | 22.67 | 29.11 |

### Bytes (selectBytes → JSON)

| Rows | resqlite wall | sqlite3+json wall | async+json wall |
|---|---|---|---|
| 10 | 0.01 | 0.03 | 0.05 |
| 50 | 0.03 | 0.14 | 0.15 |
| 100 | 0.05 | 0.28 | 0.28 |
| 500 | 0.20 | 1.42 | 1.31 |
| 1000 | 0.37 | 2.71 | 2.83 |
| 2000 | 0.86 | 5.77 | 5.87 |
| 5000 | 1.98 | 15.85 | 16.59 |
| 10000 | 4.04 | 30.93 | 32.97 |
| 20000 | 8.33 | 63.73 | 71.69 |

## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency).

| Concurrency | resqlite wall | resqlite/query | async wall | async/query |
|---|---|---|---|---|
| 1 | 0.29 | 0.29 | 0.58 | 0.58 |
| 2 | 0.32 | 0.16 | 0.64 | 0.32 |
| 4 | 0.38 | 0.09 | 0.71 | 0.18 |
| 8 | 0.70 | 0.09 | 1.39 | 0.17 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead of the reader pool.

| Metric | Value |
|---|---:|
| resqlite qps | 99741 |
| resqlite per query | 0.010 ms |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 15.39 | 17.44 | 15.39 | 17.44 |
| sqlite3 (no cache) | 23.93 | 24.74 | 23.93 | 24.74 |
| sqlite3 (cached stmt) | 23.52 | 23.78 | 23.52 | 23.78 |
| sqlite_async getAll() | 24.83 | 25.54 | 24.83 | 25.54 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 2.02 | 4.18 | 2.02 | 4.18 |
| sqlite3 execute() | 4.14 | 6.28 | 4.14 | 6.28 |
| sqlite_async execute() | 3.52 | 4.05 | 3.52 | 4.05 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.06 | 0.08 | 0.00 | 0.00 |
| sqlite3 (manual tx + stmt) | 0.10 | 0.11 | 0.10 | 0.11 |
| sqlite_async executeBatch() | 0.11 | 0.16 | 0.11 | 0.16 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.46 | 0.60 | 0.00 | 0.00 |
| sqlite3 (manual tx + stmt) | 0.56 | 0.63 | 0.56 | 0.63 |
| sqlite_async executeBatch() | 0.55 | 0.64 | 0.55 | 0.64 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.58 | 7.19 | 0.00 | 0.00 |
| sqlite3 (manual tx + stmt) | 4.53 | 5.14 | 4.53 | 5.14 |
| sqlite_async executeBatch() | 5.19 | 6.00 | 5.19 | 6.00 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.07 | 0.11 | 0.07 | 0.11 |
| sqlite_async writeTransaction() | 0.10 | 0.16 | 0.10 | 0.16 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.08 | 0.13 | 0.08 | 0.13 |
| resqlite tx.execute() loop | 0.67 | 0.79 | 0.67 | 0.79 |
| sqlite_async tx.execute() loop | 1.18 | 1.51 | 1.18 | 1.51 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.53 | 0.83 | 0.53 | 0.83 |
| resqlite tx.execute() loop | 6.83 | 7.72 | 6.83 | 7.72 |
| sqlite_async tx.execute() loop | 10.94 | 11.91 | 10.94 | 11.91 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.10 | 0.13 | 0.10 | 0.13 |
| sqlite_async tx.getAll() | 0.21 | 0.27 | 0.21 | 0.27 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.20 | 0.25 | 0.20 | 0.25 |
| sqlite_async tx.getAll() | 0.36 | 0.48 | 0.36 | 0.48 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.03 | 0.04 | 0.03 | 0.04 |
| sqlite_async watch() | 0.12 | 0.18 | 0.12 | 0.18 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.06 | 0.20 | 0.06 | 0.20 |
| sqlite_async | 0.10 | 0.16 | 0.10 | 0.16 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.22 | 0.28 | 0.22 | 0.28 |
| sqlite_async | 0.32 | 0.43 | 0.32 | 0.43 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.02 | 2.02 | 2.02 | 2.02 |
| sqlite_async | 14.80 | 14.80 | 14.80 | 14.80 |


## Repeat Stability

These rows summarize resqlite wall medians across repeated full-suite runs.
Use this section to judge whether small deltas are real or just noise.

| Benchmark | Median (ms) | Min | Max | Range | MAD | Stability |
|---|---|---|---|---|---|---|
| Concurrent Reads (1000 rows per query) / resqlite concurrent 1x | 0.29 | 0.28 | 0.30 | 6.9% | 3.4% | moderate |
| Concurrent Reads (1000 rows per query) / resqlite concurrent 2x | 0.32 | 0.32 | 0.34 | 6.3% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / resqlite concurrent 4x | 0.38 | 0.38 | 0.38 | 0.0% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / resqlite concurrent 8x | 0.70 | 0.69 | 0.73 | 5.7% | 1.4% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite sel... | 15.12 | 14.57 | 15.39 | 5.4% | 1.8% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite sel... | 15.12 | 14.57 | 15.39 | 5.4% | 1.8% | stable |
| Point Query Throughput / resqlite qps | 99741.00 | 99108.00 | 126231.00 | 27.2% | 0.6% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.12 | 0.11 | 0.12 | 8.3% | 0.0% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.05 | 0.04 | 0.05 | 20.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.35 | 0.34 | 0.35 | 2.9% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.15 | 0.15 | 0.15 | 0.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.33 | 0.33 | 0.35 | 6.1% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.15 | 0.14 | 0.15 | 6.7% | 0.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.62 | 0.61 | 0.64 | 4.8% | 1.6% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.15 | 0.15 | 0.15 | 0.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 1.02 | 1.00 | 1.08 | 7.8% | 2.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.39 | 0.38 | 0.40 | 5.1% | 2.6% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | 0.02 | 100.0% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.04 | 0.05 | 20.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.35 | 0.35 | 0.36 | 2.9% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 4.01 | 3.96 | 4.29 | 8.2% | 1.2% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | 0.09 | 800.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | 0.02 | 0.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.06 | 0.05 | 0.10 | 83.3% | 16.7% | noisy |
| Select → Maps / 100 rows / resqlite select() [main] | 0.02 | 0.01 | 0.03 | 100.0% | 50.0% | noisy |
| Select → Maps / 1000 rows / resqlite select() | 0.40 | 0.37 | 0.41 | 10.0% | 2.5% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.10 | 0.10 | 0.10 | 0.0% | 0.0% | stable |
| Select → Maps / 10000 rows / resqlite select() | 4.77 | 4.54 | 5.73 | 24.9% | 4.8% | moderate |
| Select → Maps / 10000 rows / resqlite select() [main] | 1.00 | 0.96 | 1.02 | 6.0% | 2.0% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.20 | 0.17 | 0.22 | 25.0% | 10.0% | noisy |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.20 | 0.17 | 0.22 | 25.0% | 10.0% | noisy |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | 0.06 | 100.0% | 0.0% | stable |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03 | 0.06 | 100.0% | 0.0% | stable |
| Streaming / Invalidation Latency / resqlite | 0.06 | 0.05 | 0.06 | 16.7% | 0.0% | stable |
| Streaming / Invalidation Latency / resqlite [main] | 0.06 | 0.05 | 0.06 | 16.7% | 0.0% | stable |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.14 | 2.02 | 2.44 | 19.6% | 5.6% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.14 | 2.02 | 2.44 | 19.6% | 5.6% | moderate |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.06 | 0.07 | 16.7% | 0.0% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.46 | 0.45 | 0.46 | 2.2% | 0.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.62 | 4.58 | 4.83 | 5.4% | 0.9% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.61 | 0.61 | 0.67 | 9.8% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.61 | 0.61 | 0.67 | 9.8% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.08 | 0.07 | 0.08 | 12.5% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.08 | 0.07 | 0.08 | 12.5% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 6.83 | 6.21 | 7.68 | 21.5% | 9.1% | noisy |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 6.83 | 6.21 | 7.68 | 21.5% | 9.1% | noisy |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.50 | 0.46 | 0.53 | 14.0% | 6.0% | moderate |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.50 | 0.46 | 0.53 | 14.0% | 6.0% | moderate |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.06 | 0.05 | 0.07 | 33.3% | 16.7% | noisy |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.06 | 0.05 | 0.07 | 33.3% | 16.7% | noisy |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 2.02 | 1.79 | 2.12 | 16.3% | 5.0% | moderate |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 2.02 | 1.79 | 2.12 | 16.3% | 5.0% | moderate |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.19 | 0.20 | 5.3% | 0.0% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.19 | 0.19 | 0.20 | 5.3% | 0.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.11 | 0.10 | 0.11 | 9.1% | 0.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.11 | 0.10 | 0.11 | 9.1% | 0.0% | stable |


## Comparison vs Previous Run

Previous: `2026-04-16T18-00-15-round5-aggregate.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Noise threshold | Stability | Status |
|---|---|---|---|---|---|---|
| Concurrent Reads (1000 rows per query) / resqlite concurr... | 0.30 | 0.29 | -0.01 | ±10% / ±0.03 ms | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / resqlite concurr... | 0.34 | 0.32 | -0.02 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / resqlite concurr... | 0.37 | 0.38 | +0.01 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / resqlite concurr... | 0.72 | 0.70 | -0.02 | ±10% / ±0.07 ms | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 15.35 | 15.12 | -0.23 | ±10% / ±1.54 ms | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 15.35 | 15.12 | -0.23 | ±10% / ±1.54 ms | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 100361.00 | 99741.00 | -620.00 | ±10% / ±10036.10 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.12 | 0.12 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.35 | 0.35 | +0.00 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.15 | 0.15 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.35 | 0.33 | -0.02 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.15 | 0.15 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.61 | 0.62 | +0.01 | ±10% / ±0.06 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.15 | 0.15 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 1.01 | 1.02 | +0.01 | ±10% / ±0.10 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.39 | 0.39 | +0.00 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.05 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.38 | 0.35 | -0.03 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 4.57 | 4.01 | -0.56 | ±10% / ±0.46 ms | stable | 🟢 Win (-12%) |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.02 | 0.01 | -0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.06 | +0.01 | ±50% / ±0.03 ms | noisy | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.02 | +0.01 | ±150% / ±0.03 ms | noisy | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.41 | 0.40 | -0.01 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 5.80 | 4.77 | -1.03 | ±14% / ±0.84 ms | moderate | 🟢 Win (-18%) |
| Select → Maps / 10000 rows / resqlite select() [main] | 1.01 | 1.00 | -0.01 | ±10% / ±0.10 ms | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.16 | 0.20 | +0.04 | ±30% / ±0.06 ms | noisy | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.16 | 0.20 | +0.04 | ±30% / ±0.06 ms | noisy | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.03 | 0.03 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.06 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.05 | 0.06 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 1.67 | 2.14 | +0.47 | ±17% / ±0.36 ms | moderate | 🔴 Regression (+28%) |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 1.67 | 2.14 | +0.47 | ±17% / ±0.36 ms | moderate | 🔴 Regression (+28%) |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.46 | 0.46 | +0.00 | ±10% / ±0.05 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.53 | 4.62 | +0.09 | ±10% / ±0.46 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.84 | 0.61 | -0.23 | ±10% / ±0.08 ms | stable | 🟢 Win (-27%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.84 | 0.61 | -0.23 | ±10% / ±0.08 ms | stable | 🟢 Win (-27%) |
| Write Performance / Batched Write Inside Transaction (100... | 0.08 | 0.08 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.08 | 0.08 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 8.02 | 6.83 | -1.19 | ±27% / ±2.18 ms | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 8.02 | 6.83 | -1.19 | ±27% / ±2.18 ms | noisy | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.53 | 0.50 | -0.03 | ±18% / ±0.10 ms | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.53 | 0.50 | -0.03 | ±18% / ±0.10 ms | moderate | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.06 | +0.00 | ±50% / ±0.03 ms | noisy | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.06 | +0.00 | ±50% / ±0.03 ms | noisy | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 2.27 | 2.02 | -0.25 | ±15% / ±0.34 ms | moderate | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 2.27 | 2.02 | -0.25 | ±15% / ±0.34 ms | moderate | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.20 | 0.19 | -0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.20 | 0.19 | -0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |

**Summary:** 4 wins, 2 regressions, 57 neutral

Comparison threshold uses `max(10%, 3 × current MAD%)`, plus an absolute floor of `±0.02 ms`.
That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.


