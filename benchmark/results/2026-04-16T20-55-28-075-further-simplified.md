# resqlite Benchmark Results

Generated: 2026-04-16T20:55:28.376785

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

Run settings:
- Label: `075-further-simplified`
- Repeats: `5`
- Comparison baseline: `2026-04-16T20-22-03-075-simplified.md`

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
| sqlite_async getAll() | 0.09 | 0.12 | 0.02 | 0.02 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.37 | 0.44 | 0.10 | 0.10 |
| sqlite3 select() | 0.77 | 0.87 | 0.77 | 0.87 |
| sqlite_async getAll() | 0.69 | 0.86 | 0.16 | 0.16 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 4.60 | 11.20 | 0.99 | 1.04 |
| sqlite3 select() | 8.09 | 8.35 | 8.09 | 8.35 |
| sqlite_async getAll() | 8.50 | 17.21 | 1.88 | 3.81 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response.

### 10 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.01 | 0.01 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.03 | 0.04 | 0.03 | 0.04 |
| sqlite_async + jsonEncode | 0.05 | 0.07 | 0.02 | 0.02 |

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.04 | 0.04 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.28 | 0.30 | 0.28 | 0.30 |
| sqlite_async + jsonEncode | 0.28 | 0.34 | 0.20 | 0.23 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.37 | 0.39 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 2.76 | 6.13 | 2.76 | 6.13 |
| sqlite_async + jsonEncode | 2.78 | 5.54 | 2.09 | 3.90 |

### 10000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 4.25 | 5.02 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 31.94 | 33.59 | 31.94 | 33.59 |
| sqlite_async + jsonEncode | 31.52 | 33.76 | 21.91 | 23.98 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.11 | 0.12 | 0.05 | 0.05 |
| sqlite3 | 0.23 | 0.24 | 0.23 | 0.24 |
| sqlite_async | 0.27 | 0.35 | 0.10 | 0.11 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.01 | 1.12 | 0.38 | 0.41 |
| sqlite3 | 2.06 | 2.15 | 2.06 | 2.15 |
| sqlite_async | 1.64 | 1.88 | 0.53 | 0.58 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.61 | 0.67 | 0.15 | 0.17 |
| sqlite3 | 1.15 | 1.27 | 1.15 | 1.27 |
| sqlite_async | 1.05 | 1.26 | 0.22 | 0.26 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.34 | 0.41 | 0.15 | 0.16 |
| sqlite3 | 0.67 | 0.71 | 0.67 | 0.71 |
| sqlite_async | 0.58 | 0.78 | 0.22 | 0.24 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.34 | 0.39 | 0.15 | 0.15 |
| sqlite3 | 0.63 | 0.70 | 0.63 | 0.70 |
| sqlite_async | 0.60 | 0.62 | 0.22 | 0.23 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

| Rows | resqlite wall | resqlite main | sqlite3 wall | sqlite_async wall |
|---|---|---|---|---|
| 10 | 0.01 | 0.00 | 0.01 | 0.03 |
| 50 | 0.04 | 0.01 | 0.05 | 0.06 |
| 100 | 0.05 | 0.01 | 0.09 | 0.09 |
| 500 | 0.21 | 0.06 | 0.40 | 0.38 |
| 1000 | 0.40 | 0.12 | 0.82 | 0.74 |
| 2000 | 0.88 | 0.26 | 1.63 | 1.47 |
| 5000 | 2.43 | 0.65 | 4.19 | 3.99 |
| 10000 | 5.80 | 1.30 | 8.43 | 8.12 |
| 20000 | 11.24 | 2.51 | 21.81 | 26.94 |

### Bytes (selectBytes → JSON)

| Rows | resqlite wall | sqlite3+json wall | async+json wall |
|---|---|---|---|
| 10 | 0.01 | 0.03 | 0.05 |
| 50 | 0.03 | 0.14 | 0.15 |
| 100 | 0.04 | 0.28 | 0.28 |
| 500 | 0.18 | 1.33 | 1.32 |
| 1000 | 0.34 | 2.71 | 2.74 |
| 2000 | 0.84 | 5.89 | 5.91 |
| 5000 | 2.00 | 16.21 | 16.15 |
| 10000 | 4.25 | 32.28 | 32.39 |
| 20000 | 8.46 | 64.24 | 67.62 |

## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency).

| Concurrency | resqlite wall | resqlite/query | async wall | async/query |
|---|---|---|---|---|
| 1 | 0.30 | 0.30 | 0.53 | 0.53 |
| 2 | 0.32 | 0.16 | 0.59 | 0.30 |
| 4 | 0.39 | 0.10 | 0.70 | 0.18 |
| 8 | 0.76 | 0.09 | 1.53 | 0.19 |

## Point Query Throughput

Single-row lookup by primary key in a hot loop. Measures the per-query dispatch overhead of the reader pool.

| Metric | Value |
|---|---:|
| resqlite qps | 124782 |
| resqlite per query | 0.008 ms |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 14.48 | 14.81 | 14.48 | 14.81 |
| sqlite3 (no cache) | 25.07 | 25.30 | 25.07 | 25.30 |
| sqlite3 (cached stmt) | 24.73 | 25.11 | 24.73 | 25.11 |
| sqlite_async getAll() | 24.72 | 26.20 | 24.72 | 26.20 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.60 | 2.45 | 1.60 | 2.45 |
| sqlite3 execute() | 3.67 | 5.82 | 3.67 | 5.82 |
| sqlite_async execute() | 3.03 | 3.63 | 3.03 | 3.63 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.06 | 0.06 | 0.00 | 0.00 |
| sqlite3 (manual tx + stmt) | 0.10 | 0.12 | 0.10 | 0.12 |
| sqlite_async executeBatch() | 0.10 | 0.17 | 0.10 | 0.17 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.44 | 0.51 | 0.00 | 0.00 |
| sqlite3 (manual tx + stmt) | 0.51 | 0.58 | 0.51 | 0.58 |
| sqlite_async executeBatch() | 0.54 | 0.64 | 0.54 | 0.64 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.57 | 7.60 | 0.00 | 0.00 |
| sqlite3 (manual tx + stmt) | 4.63 | 4.83 | 4.63 | 4.83 |
| sqlite_async executeBatch() | 5.17 | 6.20 | 5.17 | 6.20 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.08 | 0.12 | 0.08 | 0.12 |
| sqlite_async writeTransaction() | 0.08 | 0.10 | 0.08 | 0.10 |

### Batched Write Inside Transaction (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.07 | 0.13 | 0.07 | 0.13 |
| resqlite tx.execute() loop | 0.66 | 0.88 | 0.66 | 0.88 |
| sqlite_async tx.execute() loop | 0.94 | 1.25 | 0.94 | 1.25 |

### Batched Write Inside Transaction (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.executeBatch() | 0.44 | 0.51 | 0.44 | 0.51 |
| resqlite tx.execute() loop | 5.97 | 6.54 | 5.97 | 6.54 |
| sqlite_async tx.execute() loop | 9.58 | 10.11 | 9.58 | 10.11 |

### Transaction Read (500 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.11 | 0.16 | 0.11 | 0.16 |
| sqlite_async tx.getAll() | 0.21 | 0.26 | 0.21 | 0.26 |

### Transaction Read (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite tx.select() | 0.18 | 0.19 | 0.18 | 0.19 |
| sqlite_async tx.getAll() | 0.36 | 0.44 | 0.36 | 0.44 |

## Streaming

Reactive query performance. resqlite uses per-subscriber buffered controllers with authorizer-based dependency tracking. sqlite_async uses a 30ms default throttle (disabled here via throttle: Duration.zero).

### Initial Emission

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite stream() | 0.04 | 0.04 | 0.04 | 0.04 |
| sqlite_async watch() | 0.11 | 0.12 | 0.11 | 0.12 |

### Invalidation Latency

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.05 | 0.06 | 0.05 | 0.06 |
| sqlite_async | 0.07 | 0.14 | 0.07 | 0.14 |

### Unchanged Fanout Throughput (1 canary + 10 unchanged streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.26 | 0.29 | 0.26 | 0.29 |
| sqlite_async | 0.52 | 1.10 | 0.52 | 1.10 |

### Fan-out (10 streams)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.22 | 0.28 | 0.22 | 0.28 |
| sqlite_async | 0.27 | 0.36 | 0.27 | 0.36 |

### Stream Churn (100 cycles)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 2.37 | 2.37 | 2.37 | 2.37 |
| sqlite_async | 10.43 | 10.43 | 10.43 | 10.43 |


## Repeat Stability

These rows summarize resqlite wall medians across repeated full-suite runs.
Use this section to judge whether small deltas are real or just noise.

| Benchmark | Median (ms) | Min | Max | Range | MAD | Stability |
|---|---|---|---|---|---|---|
| Concurrent Reads (1000 rows per query) / resqlite concurrent 1x | 0.28 | 0.28 | 0.30 | 7.1% | 0.0% | stable |
| Concurrent Reads (1000 rows per query) / resqlite concurrent 2x | 0.32 | 0.30 | 0.33 | 9.4% | 3.1% | moderate |
| Concurrent Reads (1000 rows per query) / resqlite concurrent 4x | 0.38 | 0.36 | 0.40 | 10.5% | 2.6% | stable |
| Concurrent Reads (1000 rows per query) / resqlite concurrent 8x | 0.76 | 0.68 | 0.79 | 14.5% | 3.9% | moderate |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite sel... | 14.48 | 14.39 | 14.53 | 1.0% | 0.2% | stable |
| Parameterized Queries / 100 queries × ~500 rows each / resqlite sel... | 14.48 | 14.39 | 14.53 | 1.0% | 0.2% | stable |
| Point Query Throughput / resqlite qps | 124782.00 | 104145.00 | 130242.00 | 20.9% | 4.3% | moderate |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite | 0.11 | 0.11 | 0.13 | 18.2% | 0.0% | stable |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / resqlite [m... | 0.05 | 0.04 | 0.05 | 20.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.34 | 0.33 | 0.34 | 2.9% | 0.0% | stable |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite [main] | 0.14 | 0.14 | 0.15 | 7.1% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqlite | 0.34 | 0.33 | 0.34 | 2.9% | 0.0% | stable |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols) / resqli... | 0.15 | 0.14 | 0.15 | 6.7% | 0.0% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlite | 0.61 | 0.60 | 0.62 | 3.3% | 1.6% | stable |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols) / resqlit... | 0.15 | 0.15 | 0.15 | 0.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite | 1.01 | 1.01 | 1.06 | 5.0% | 0.0% | stable |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) / resqlite ... | 0.39 | 0.38 | 0.39 | 2.6% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | 0.02 | 100.0% | 0.0% | stable |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.05 | 0.04 | 0.05 | 20.0% | 0.0% | stable |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.36 | 0.35 | 0.37 | 5.6% | 2.8% | stable |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 4.00 | 3.85 | 4.30 | 11.2% | 3.7% | moderate |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() [main] | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | 0.08 | 700.0% | 0.0% | stable |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | 0.02 | 0.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.05 | 0.09 | 80.0% | 0.0% | stable |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | 0.03 | 200.0% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() | 0.39 | 0.37 | 0.39 | 5.1% | 0.0% | stable |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.10 | 0.09 | 0.10 | 10.0% | 0.0% | stable |
| Select → Maps / 10000 rows / resqlite select() | 4.72 | 4.60 | 5.38 | 16.5% | 2.5% | stable |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.99 | 0.96 | 1.00 | 4.0% | 0.0% | stable |
| Streaming / Fan-out (10 streams) / resqlite | 0.22 | 0.20 | 0.26 | 27.3% | 9.1% | noisy |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.22 | 0.20 | 0.26 | 27.3% | 9.1% | noisy |
| Streaming / Initial Emission / resqlite stream() | 0.04 | 0.04 | 0.05 | 25.0% | 0.0% | stable |
| Streaming / Initial Emission / resqlite stream() [main] | 0.04 | 0.04 | 0.05 | 25.0% | 0.0% | stable |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.04 | 0.06 | 40.0% | 20.0% | noisy |
| Streaming / Invalidation Latency / resqlite [main] | 0.05 | 0.04 | 0.06 | 40.0% | 20.0% | noisy |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.74 | 2.37 | 2.86 | 17.9% | 4.4% | moderate |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.74 | 2.37 | 2.86 | 17.9% | 4.4% | moderate |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.27 | 0.26 | 0.29 | 11.1% | 0.0% | stable |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged st... | 0.27 | 0.26 | 0.29 | 11.1% | 0.0% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch() | 0.06 | 0.06 | 0.07 | 16.7% | 0.0% | stable |
| Write Performance / Batch Insert (100 rows) / resqlite executeBatch... | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatch() | 0.44 | 0.43 | 0.46 | 6.8% | 2.3% | stable |
| Write Performance / Batch Insert (1000 rows) / resqlite executeBatc... | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 4.57 | 4.40 | 4.65 | 5.5% | 1.1% | stable |
| Write Performance / Batch Insert (10000 rows) / resqlite executeBat... | 0.00 | 0.00 | 0.00 | 0.0% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.66 | 0.59 | 0.71 | 18.2% | 4.5% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.66 | 0.59 | 0.71 | 18.2% | 4.5% | moderate |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07 | 0.08 | 14.3% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (100 rows) / r... | 0.07 | 0.07 | 0.08 | 14.3% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 6.00 | 5.96 | 6.10 | 2.3% | 0.7% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 6.00 | 5.96 | 6.10 | 2.3% | 0.7% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.45 | 0.44 | 0.45 | 2.2% | 0.0% | stable |
| Write Performance / Batched Write Inside Transaction (1000 rows) / ... | 0.45 | 0.44 | 0.45 | 2.2% | 0.0% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05 | 0.08 | 60.0% | 0.0% | stable |
| Write Performance / Interactive Transaction (insert + select + cond... | 0.05 | 0.05 | 0.08 | 60.0% | 0.0% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.78 | 1.60 | 1.80 | 11.2% | 1.1% | stable |
| Write Performance / Single Inserts (100 sequential) / resqlite exec... | 1.78 | 1.60 | 1.80 | 11.2% | 1.1% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.18 | 0.19 | 5.6% | 0.0% | stable |
| Write Performance / Transaction Read (1000 rows) / resqlite tx.sele... | 0.18 | 0.18 | 0.19 | 5.6% | 0.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.select() | 0.11 | 0.10 | 0.11 | 9.1% | 0.0% | stable |
| Write Performance / Transaction Read (500 rows) / resqlite tx.selec... | 0.11 | 0.10 | 0.11 | 9.1% | 0.0% | stable |


## Comparison vs Previous Run

Previous: `2026-04-16T20-22-03-075-simplified.md`

| Benchmark | Previous (ms) | Current med (ms) | Delta | Noise threshold | Stability | Status |
|---|---|---|---|---|---|---|
| Concurrent Reads (1000 rows per query) / resqlite concurr... | 0.30 | 0.28 | -0.02 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / resqlite concurr... | 0.31 | 0.32 | +0.01 | ±10% / ±0.03 ms | moderate | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / resqlite concurr... | 0.37 | 0.38 | +0.01 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Concurrent Reads (1000 rows per query) / resqlite concurr... | 0.69 | 0.76 | +0.07 | ±12% / ±0.09 ms | moderate | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.66 | 14.48 | -0.18 | ±10% / ±1.47 ms | stable | ⚪ Within noise |
| Parameterized Queries / 100 queries × ~500 rows each / re... | 14.66 | 14.48 | -0.18 | ±10% / ±1.47 ms | stable | ⚪ Within noise |
| Point Query Throughput / resqlite qps | 130959.00 | 124782.00 | -6177.00 | ±13% / ±16872.85 ms | moderate | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / r... | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.34 | 0.34 | +0.00 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqli... | 0.14 | 0.14 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.33 | 0.34 | +0.01 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.14 | 0.15 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.63 | 0.61 | -0.02 | ±10% / ±0.06 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.15 | 0.15 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 1.02 | 1.01 | -0.01 | ±10% / ±0.10 ms | stable | ⚪ Within noise |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 0.38 | 0.39 | +0.01 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10 rows / resqlite selectBytes() [m... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.04 | 0.05 | +0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() [... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.36 | 0.36 | +0.00 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes() | 4.13 | 4.00 | -0.13 | ±11% / ±0.46 ms | moderate | ⚪ Within noise |
| Select → JSON Bytes / 10000 rows / resqlite selectBytes()... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 10 rows / resqlite select() [main] | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() | 0.05 | 0.05 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 100 rows / resqlite select() [main] | 0.01 | 0.01 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() | 0.39 | 0.39 | +0.00 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Select → Maps / 1000 rows / resqlite select() [main] | 0.10 | 0.10 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Select → Maps / 10000 rows / resqlite select() | 5.37 | 4.72 | -0.65 | ±10% / ±0.54 ms | stable | 🟢 Win (-12%) |
| Select → Maps / 10000 rows / resqlite select() [main] | 0.97 | 0.99 | +0.02 | ±10% / ±0.10 ms | stable | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite | 0.21 | 0.22 | +0.01 | ±27% / ±0.06 ms | noisy | ⚪ Within noise |
| Streaming / Fan-out (10 streams) / resqlite [main] | 0.21 | 0.22 | +0.01 | ±27% / ±0.06 ms | noisy | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Streaming / Initial Emission / resqlite stream() [main] | 0.04 | 0.04 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite | 0.05 | 0.05 | +0.00 | ±60% / ±0.03 ms | noisy | ⚪ Within noise |
| Streaming / Invalidation Latency / resqlite [main] | 0.05 | 0.05 | +0.00 | ±60% / ±0.03 ms | noisy | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite | 2.54 | 2.74 | +0.20 | ±13% / ±0.36 ms | moderate | ⚪ Within noise |
| Streaming / Stream Churn (100 cycles) / resqlite [main] | 2.54 | 2.74 | +0.20 | ±13% / ±0.36 ms | moderate | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.27 | 0.27 | +0.00 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Streaming / Unchanged Fanout Throughput (1 canary + 10 un... | 0.27 | 0.27 | +0.00 | ±10% / ±0.03 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.06 | 0.06 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (100 rows) / resqlite ex... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.44 | 0.44 | +0.00 | ±10% / ±0.04 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (1000 rows) / resqlite e... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 4.40 | 4.57 | +0.17 | ±10% / ±0.46 ms | stable | ⚪ Within noise |
| Write Performance / Batch Insert (10000 rows) / resqlite ... | 0.00 | 0.00 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.58 | 0.66 | +0.08 | ±14% / ±0.09 ms | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.58 | 0.66 | +0.08 | ±14% / ±0.09 ms | moderate | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.07 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.07 | 0.07 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 5.90 | 6.00 | +0.10 | ±10% / ±0.60 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 5.90 | 6.00 | +0.10 | ±10% / ±0.60 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.45 | 0.45 | +0.00 | ±10% / ±0.05 ms | stable | ⚪ Within noise |
| Write Performance / Batched Write Inside Transaction (100... | 0.45 | 0.45 | +0.00 | ±10% / ±0.05 ms | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.05 | -0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.05 | -0.01 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.84 | 1.78 | -0.06 | ±10% / ±0.18 ms | stable | ⚪ Within noise |
| Write Performance / Single Inserts (100 sequential) / res... | 1.84 | 1.78 | -0.06 | ±10% / ±0.18 ms | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.18 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Transaction Read (1000 rows) / resqli... | 0.18 | 0.18 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |
| Write Performance / Transaction Read (500 rows) / resqlit... | 0.11 | 0.11 | +0.00 | ±10% / ±0.02 ms | stable | ⚪ Within noise |

**Summary:** 1 wins, 0 regressions, 64 neutral

Comparison threshold uses `max(10%, 3 × current MAD%)`, plus an absolute floor of `±0.02 ms`.
That keeps stable cases sensitive while treating noisy and ultra-fast cases more conservatively.

✅ **No regressions beyond noise.** 1 benchmarks improved.


