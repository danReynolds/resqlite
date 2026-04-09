# resqlite Benchmark Results

Generated: 2026-04-07T19:25:51.813802

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.34 | 1.18 | 0.08 | 0.12 |
| sqlite3 select() | 0.27 | 0.55 | 0.27 | 0.55 |
| sqlite_async getAll() | 0.19 | 0.25 | 0.06 | 0.06 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.51 | 0.73 | 0.10 | 0.11 |
| sqlite3 select() | 0.82 | 1.17 | 0.82 | 1.17 |
| sqlite_async getAll() | 0.94 | 1.16 | 0.18 | 0.20 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 2.43 | 5.77 | 0.47 | 0.50 |
| sqlite3 select() | 3.79 | 4.18 | 3.79 | 4.18 |
| sqlite_async getAll() | 4.22 | 4.82 | 0.96 | 1.01 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.14 | 0.22 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.40 | 0.57 | 0.40 | 0.57 |
| sqlite_async + jsonEncode | 0.38 | 0.46 | 0.23 | 0.25 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.86 | 0.93 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 2.82 | 5.75 | 2.82 | 5.75 |
| sqlite_async + jsonEncode | 3.06 | 6.17 | 2.19 | 4.55 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 4.09 | 4.75 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 16.98 | 17.99 | 16.98 | 17.99 |
| sqlite_async + jsonEncode | 15.97 | 18.14 | 10.50 | 12.18 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.16 | 0.27 | 0.04 | 0.10 |
| sqlite3 | 0.23 | 0.39 | 0.23 | 0.39 |
| sqlite_async | 0.30 | 0.37 | 0.09 | 0.10 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.08 | 1.19 | 0.39 | 0.41 |
| sqlite3 | 1.95 | 2.04 | 1.95 | 2.04 |
| sqlite_async | 1.64 | 1.90 | 0.51 | 0.54 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.62 | 0.94 | 0.14 | 0.16 |
| sqlite3 | 1.09 | 1.18 | 1.09 | 1.18 |
| sqlite_async | 1.15 | 1.40 | 0.21 | 0.23 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.41 | 0.46 | 0.15 | 0.16 |
| sqlite3 | 0.62 | 0.63 | 0.62 | 0.63 |
| sqlite_async | 0.65 | 0.96 | 0.21 | 0.23 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.41 | 0.43 | 0.15 | 0.15 |
| sqlite3 | 0.60 | 0.70 | 0.60 | 0.70 |
| sqlite_async | 0.64 | 0.78 | 0.22 | 0.24 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

| Rows | resqlite wall | resqlite main | sqlite3 wall | sqlite_async wall |
|---|---|---|---|---|
| 10 | 0.11 | 0.00 | 0.02 | 0.07 |
| 50 | 0.10 | 0.01 | 0.05 | 0.08 |
| 100 | 0.10 | 0.01 | 0.09 | 0.10 |
| 500 | 0.27 | 0.07 | 0.41 | 0.30 |
| 1000 | 0.48 | 0.13 | 0.79 | 0.57 |
| 2000 | 0.91 | 0.25 | 1.57 | 1.07 |
| 5000 | 2.48 | 0.64 | 3.94 | 2.83 |
| 10000 | 5.71 | 1.24 | 8.08 | 6.06 |
| 20000 | 12.20 | 2.57 | 21.66 | 22.29 |

### Bytes (selectBytes → JSON)

| Rows | resqlite wall | sqlite3+json wall | async+json wall |
|---|---|---|---|
| 10 | 0.06 | 0.04 | 0.09 |
| 50 | 0.10 | 0.15 | 0.23 |
| 100 | 0.13 | 0.28 | 0.32 |
| 500 | 0.41 | 1.36 | 1.38 |
| 1000 | 0.74 | 2.77 | 2.77 |
| 2000 | 1.55 | 5.98 | 6.08 |
| 5000 | 3.85 | 15.28 | 16.12 |
| 10000 | 7.83 | 29.86 | 32.37 |
| 20000 | 15.56 | 63.27 | 69.15 |

## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency).

| Concurrency | resqlite wall | resqlite/query | async wall | async/query |
|---|---|---|---|---|
| 1 | 0.35 | 0.35 | 0.58 | 0.58 |
| 2 | 0.41 | 0.21 | 0.72 | 0.36 |
| 4 | 0.58 | 0.15 | 0.84 | 0.21 |
| 8 | 0.90 | 0.11 | 1.67 | 0.21 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 18.69 | 19.23 | 18.69 | 19.23 |
| sqlite3 (no cache) | 23.44 | 23.95 | 23.44 | 23.95 |
| sqlite3 (cached stmt) | 23.18 | 23.70 | 23.18 | 23.70 |
| sqlite_async getAll() | 25.85 | 26.84 | 25.85 | 26.84 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.91 | 2.47 | 1.91 | 2.47 |
| sqlite3 execute() | 6.11 | 6.57 | 6.11 | 6.57 |
| sqlite_async execute() | 3.75 | 4.93 | 3.75 | 4.93 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.08 | 0.09 | 0.08 | 0.09 |
| sqlite3 (manual tx + stmt) | 0.17 | 0.28 | 0.17 | 0.28 |
| sqlite_async executeBatch() | 0.12 | 0.20 | 0.12 | 0.20 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.47 | 0.63 | 0.47 | 0.63 |
| sqlite3 (manual tx + stmt) | 0.58 | 0.63 | 0.58 | 0.63 |
| sqlite_async executeBatch() | 0.58 | 0.72 | 0.58 | 0.72 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.92 | 8.82 | 4.92 | 8.82 |
| sqlite3 (manual tx + stmt) | 4.70 | 5.17 | 4.70 | 5.17 |
| sqlite_async executeBatch() | 5.31 | 7.94 | 5.31 | 7.94 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.06 | 0.29 | 0.06 | 0.29 |
| sqlite_async writeTransaction() | 0.10 | 0.13 | 0.10 | 0.13 |

## Comparison vs Previous Run

Previous: `2026-04-07T19-14-36-writer-tuning.md`

| Benchmark | Previous (ms) | Current (ms) | Delta | Status |
|---|---|---|---|---|
| Parameterized Queries / 100 queries × ~500 rows each / sq... | 18.45 | 18.69 | +0.24 | ⚪ Neutral |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / s... | 0.16 | 0.16 | +0.00 | ⚪ Neutral |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.41 | 0.41 | +0.00 | ⚪ Neutral |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.42 | 0.41 | -0.01 | ⚪ Neutral |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.60 | 0.62 | +0.02 | ⚪ Neutral |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 1.06 | 1.08 | +0.02 | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.14 | 0.14 | +0.00 | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.78 | 0.86 | +0.08 | 🔴 Regression (+10%) |
| Select → JSON Bytes / 5000 rows / resqlite selectBytes() | 3.88 | 4.09 | +0.21 | ⚪ Neutral |
| Select → Maps / 100 rows / resqlite select() | 0.28 | 0.34 | +0.06 | 🔴 Regression (+21%) |
| Select → Maps / 1000 rows / resqlite select() | 0.50 | 0.51 | +0.01 | ⚪ Neutral |
| Select → Maps / 5000 rows / resqlite select() | 2.53 | 2.43 | -0.10 | ⚪ Neutral |
| Write Performance / Batch Insert (100 rows) / resqlite exe... | 0.09 | 0.08 | -0.01 | 🟢 Win (-11%) |
| Write Performance / Batch Insert (1000 rows) / resqlite ex... | 0.48 | 0.47 | -0.01 | ⚪ Neutral |
| Write Performance / Batch Insert (10000 rows) / resqlite e... | 5.28 | 4.92 | -0.36 | ⚪ Neutral |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.06 | +0.00 | ⚪ Neutral |
| Write Performance / Single Inserts (100 sequential) / sql... | 1.75 | 1.91 | +0.16 | ⚪ Neutral |

**Summary:** 1 wins, 2 regressions, 14 neutral (threshold: ±10%)

⚠️ **Regressions detected.** Review the flagged benchmarks above.


