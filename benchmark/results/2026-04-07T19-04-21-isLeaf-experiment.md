# resqlite Benchmark Results

Generated: 2026-04-07T19:03:56.753793

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.26 | 0.77 | 0.07 | 0.11 |
| sqlite3 select() | 0.26 | 0.64 | 0.26 | 0.64 |
| sqlite_async getAll() | 0.19 | 0.27 | 0.06 | 0.06 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.49 | 0.57 | 0.10 | 0.10 |
| sqlite3 select() | 0.78 | 1.14 | 0.78 | 1.14 |
| sqlite_async getAll() | 0.89 | 0.94 | 0.17 | 0.19 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 2.21 | 4.99 | 0.48 | 0.49 |
| sqlite3 select() | 3.87 | 3.98 | 3.87 | 3.98 |
| sqlite_async getAll() | 3.72 | 4.08 | 0.84 | 0.87 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.13 | 0.14 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.38 | 0.53 | 0.38 | 0.53 |
| sqlite_async + jsonEncode | 0.33 | 0.37 | 0.22 | 0.23 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.74 | 0.76 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 2.73 | 4.46 | 2.73 | 4.46 |
| sqlite_async + jsonEncode | 2.75 | 4.69 | 2.06 | 3.63 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 3.97 | 4.31 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 15.49 | 16.82 | 15.49 | 16.82 |
| sqlite_async + jsonEncode | 15.20 | 16.57 | 10.58 | 12.11 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.15 | 0.23 | 0.04 | 0.08 |
| sqlite3 | 0.22 | 0.39 | 0.22 | 0.39 |
| sqlite_async | 0.28 | 0.29 | 0.09 | 0.09 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.01 | 1.07 | 0.38 | 0.40 |
| sqlite3 | 1.85 | 2.01 | 1.85 | 2.01 |
| sqlite_async | 1.58 | 1.65 | 0.50 | 0.52 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.60 | 0.65 | 0.15 | 0.15 |
| sqlite3 | 1.05 | 1.10 | 1.05 | 1.10 |
| sqlite_async | 1.02 | 1.15 | 0.21 | 0.22 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.39 | 0.40 | 0.15 | 0.15 |
| sqlite3 | 0.62 | 0.62 | 0.62 | 0.62 |
| sqlite_async | 0.59 | 0.64 | 0.21 | 0.22 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.40 | 0.40 | 0.15 | 0.15 |
| sqlite3 | 0.59 | 0.59 | 0.59 | 0.59 |
| sqlite_async | 0.60 | 0.61 | 0.22 | 0.22 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

| Rows | resqlite wall | resqlite main | sqlite3 wall | sqlite_async wall |
|---|---|---|---|---|
| 10 | 0.07 | 0.00 | 0.02 | 0.06 |
| 50 | 0.09 | 0.01 | 0.05 | 0.07 |
| 100 | 0.10 | 0.01 | 0.08 | 0.10 |
| 500 | 0.26 | 0.07 | 0.38 | 0.29 |
| 1000 | 0.46 | 0.13 | 0.76 | 0.53 |
| 2000 | 0.84 | 0.25 | 1.51 | 1.05 |
| 5000 | 2.25 | 0.62 | 3.80 | 2.62 |
| 10000 | 4.62 | 1.23 | 7.89 | 5.49 |
| 20000 | 11.28 | 2.48 | 20.19 | 18.02 |

### Bytes (selectBytes → JSON)

| Rows | resqlite wall | sqlite3+json wall | async+json wall |
|---|---|---|---|
| 10 | 0.06 | 0.04 | 0.09 |
| 50 | 0.09 | 0.14 | 0.18 |
| 100 | 0.12 | 0.27 | 0.30 |
| 500 | 0.41 | 1.29 | 1.31 |
| 1000 | 0.74 | 2.57 | 2.54 |
| 2000 | 1.49 | 6.14 | 5.89 |
| 5000 | 3.50 | 13.09 | 14.28 |
| 10000 | 6.76 | 28.71 | 29.42 |
| 20000 | 14.88 | 58.89 | 65.15 |

## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency).

| Concurrency | resqlite wall | resqlite/query | async wall | async/query |
|---|---|---|---|---|
| 1 | 0.34 | 0.34 | 0.55 | 0.55 |
| 2 | 0.37 | 0.18 | 0.60 | 0.30 |
| 4 | 0.51 | 0.13 | 0.66 | 0.17 |
| 8 | 1.03 | 0.13 | 1.60 | 0.20 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 17.77 | 19.45 | 17.77 | 19.45 |
| sqlite3 (no cache) | 22.51 | 22.71 | 22.51 | 22.71 |
| sqlite3 (cached stmt) | 22.41 | 23.28 | 22.41 | 23.28 |
| sqlite_async getAll() | 23.96 | 25.52 | 23.96 | 25.52 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.73 | 2.10 | 1.73 | 2.10 |
| sqlite3 execute() | 5.04 | 5.24 | 5.04 | 5.24 |
| sqlite_async execute() | 3.47 | 4.34 | 3.47 | 4.34 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.08 | 0.09 | 0.08 | 0.09 |
| sqlite3 (manual tx + stmt) | 0.16 | 0.19 | 0.16 | 0.19 |
| sqlite_async executeBatch() | 0.12 | 0.13 | 0.12 | 0.13 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.45 | 0.47 | 0.45 | 0.47 |
| sqlite3 (manual tx + stmt) | 0.51 | 0.56 | 0.51 | 0.56 |
| sqlite_async executeBatch() | 0.53 | 0.57 | 0.53 | 0.57 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.52 | 9.61 | 4.52 | 9.61 |
| sqlite3 (manual tx + stmt) | 4.46 | 4.88 | 4.46 | 4.88 |
| sqlite_async executeBatch() | 5.04 | 6.56 | 5.04 | 6.56 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.06 | 0.08 | 0.06 | 0.08 |
| sqlite_async writeTransaction() | 0.09 | 0.11 | 0.09 | 0.11 |

## Comparison vs Previous Run

Previous: `2026-04-07T18-49-23-final-cleanup.md`

| Benchmark | Previous (ms) | Current (ms) | Delta | Status |
|---|---|---|---|---|
| Parameterized Queries / 100 queries × ~500 rows each / sq... | 19.34 | 17.77 | -1.57 | ⚪ Neutral |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / s... | 0.17 | 0.15 | -0.02 | 🟢 Win (-12%) |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.42 | 0.40 | -0.02 | ⚪ Neutral |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.40 | 0.39 | -0.01 | ⚪ Neutral |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.63 | 0.60 | -0.03 | ⚪ Neutral |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 1.11 | 1.01 | -0.10 | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.14 | 0.13 | -0.01 | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.78 | 0.74 | -0.04 | ⚪ Neutral |
| Select → JSON Bytes / 5000 rows / resqlite selectBytes() | 3.68 | 3.97 | +0.29 | ⚪ Neutral |
| Select → Maps / 100 rows / resqlite select() | 0.32 | 0.26 | -0.06 | 🟢 Win (-19%) |
| Select → Maps / 1000 rows / resqlite select() | 0.53 | 0.49 | -0.04 | ⚪ Neutral |
| Select → Maps / 5000 rows / resqlite select() | 2.39 | 2.21 | -0.18 | ⚪ Neutral |
| Write Performance / Batch Insert (100 rows) / resqlite exe... | 0.08 | 0.08 | +0.00 | ⚪ Neutral |
| Write Performance / Batch Insert (1000 rows) / resqlite ex... | 0.47 | 0.45 | -0.02 | ⚪ Neutral |
| Write Performance / Batch Insert (10000 rows) / resqlite e... | 4.83 | 4.52 | -0.31 | ⚪ Neutral |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.06 | +0.00 | ⚪ Neutral |
| Write Performance / Single Inserts (100 sequential) / sql... | 1.78 | 1.73 | -0.05 | ⚪ Neutral |

**Summary:** 2 wins, 0 regressions, 15 neutral (threshold: ±10%)

✅ **No regressions.** 2 benchmarks improved.


