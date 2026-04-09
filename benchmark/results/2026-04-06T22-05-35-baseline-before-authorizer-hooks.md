# resqlite Benchmark Results

Generated: 2026-04-06T22:05:10.054337

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.52 | 1.04 | 0.06 | 0.21 |
| sqlite3 select() | 0.38 | 0.64 | 0.38 | 0.64 |
| sqlite_async getAll() | 0.21 | 0.35 | 0.05 | 0.06 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.51 | 0.60 | 0.10 | 0.11 |
| sqlite3 select() | 0.74 | 1.07 | 0.74 | 1.07 |
| sqlite_async getAll() | 0.71 | 0.85 | 0.16 | 0.16 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 2.33 | 4.55 | 0.46 | 0.48 |
| sqlite3 select() | 3.64 | 3.76 | 3.64 | 3.76 |
| sqlite_async getAll() | 3.50 | 4.37 | 0.79 | 0.82 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.14 | 0.15 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.35 | 0.56 | 0.35 | 0.56 |
| sqlite_async + jsonEncode | 0.32 | 0.35 | 0.21 | 0.23 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.71 | 0.74 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 2.55 | 4.30 | 2.55 | 4.30 |
| sqlite_async + jsonEncode | 2.60 | 4.08 | 1.94 | 3.08 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 3.44 | 3.61 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 12.80 | 15.35 | 12.80 | 15.35 |
| sqlite_async + jsonEncode | 14.87 | 16.30 | 10.01 | 11.60 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.15 | 0.26 | 0.04 | 0.08 |
| sqlite3 | 0.23 | 0.36 | 0.23 | 0.36 |
| sqlite_async | 0.29 | 0.30 | 0.10 | 0.10 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.07 | 1.14 | 0.38 | 0.40 |
| sqlite3 | 1.86 | 1.94 | 1.86 | 1.94 |
| sqlite_async | 1.57 | 1.60 | 0.50 | 0.51 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.78 | 1.23 | 0.15 | 0.16 |
| sqlite3 | 1.05 | 1.06 | 1.05 | 1.06 |
| sqlite_async | 1.03 | 1.10 | 0.21 | 0.21 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.40 | 0.41 | 0.15 | 0.16 |
| sqlite3 | 0.61 | 0.63 | 0.61 | 0.63 |
| sqlite_async | 0.60 | 0.67 | 0.21 | 0.21 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.41 | 0.42 | 0.15 | 0.15 |
| sqlite3 | 0.59 | 0.59 | 0.59 | 0.59 |
| sqlite_async | 0.60 | 0.62 | 0.21 | 0.22 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

| Rows | resqlite wall | resqlite main | sqlite3 wall | sqlite_async wall |
|---|---|---|---|---|
| 10 | 0.07 | 0.00 | 0.02 | 0.05 |
| 50 | 0.09 | 0.01 | 0.05 | 0.07 |
| 100 | 0.10 | 0.01 | 0.08 | 0.10 |
| 500 | 0.28 | 0.06 | 0.39 | 0.30 |
| 1000 | 0.52 | 0.13 | 0.79 | 0.58 |
| 2000 | 0.94 | 0.25 | 1.51 | 1.06 |
| 5000 | 2.53 | 0.61 | 3.77 | 2.65 |
| 10000 | 5.13 | 1.22 | 7.57 | 6.00 |
| 20000 | 14.99 | 2.52 | 20.39 | 18.98 |

### Bytes (selectBytes → JSON)

| Rows | resqlite wall | sqlite3+json wall | async+json wall |
|---|---|---|---|
| 10 | 0.07 | 0.04 | 0.08 |
| 50 | 0.10 | 0.15 | 0.17 |
| 100 | 0.13 | 0.27 | 0.29 |
| 500 | 0.40 | 1.27 | 1.29 |
| 1000 | 0.71 | 2.52 | 2.54 |
| 2000 | 1.41 | 5.90 | 5.65 |
| 5000 | 3.65 | 13.64 | 15.78 |
| 10000 | 6.96 | 27.26 | 29.67 |
| 20000 | 14.85 | 59.69 | 63.67 |

## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency).

| Concurrency | resqlite wall | resqlite/query | async wall | async/query |
|---|---|---|---|---|
| 1 | 0.40 | 0.40 | 0.59 | 0.59 |
| 2 | 0.46 | 0.23 | 0.61 | 0.30 |
| 4 | 0.57 | 0.14 | 0.71 | 0.18 |
| 8 | 1.07 | 0.13 | 1.49 | 0.19 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 18.30 | 19.62 | 18.30 | 19.62 |
| sqlite3 (no cache) | 22.46 | 23.32 | 22.46 | 23.32 |
| sqlite3 (cached stmt) | 22.26 | 23.10 | 22.26 | 23.10 |
| sqlite_async getAll() | 24.60 | 26.36 | 24.60 | 26.36 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.72 | 2.11 | 1.72 | 2.11 |
| sqlite3 execute() | 5.70 | 9.36 | 5.70 | 9.36 |
| sqlite_async execute() | 3.53 | 3.98 | 3.53 | 3.98 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.08 | 0.09 | 0.08 | 0.09 |
| sqlite3 (manual tx + stmt) | 0.23 | 0.28 | 0.23 | 0.28 |
| sqlite_async executeBatch() | 0.12 | 0.14 | 0.12 | 0.14 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.45 | 0.59 | 0.45 | 0.59 |
| sqlite3 (manual tx + stmt) | 0.51 | 0.56 | 0.51 | 0.56 |
| sqlite_async executeBatch() | 0.52 | 0.62 | 0.52 | 0.62 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.55 | 6.24 | 4.55 | 6.24 |
| sqlite3 (manual tx + stmt) | 4.26 | 4.59 | 4.26 | 4.59 |
| sqlite_async executeBatch() | 4.91 | 7.18 | 4.91 | 7.18 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.06 | 0.16 | 0.06 | 0.16 |
| sqlite_async writeTransaction() | 0.10 | 0.14 | 0.10 | 0.14 |

