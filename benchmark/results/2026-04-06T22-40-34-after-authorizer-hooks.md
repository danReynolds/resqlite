# resqlite Benchmark Results

Generated: 2026-04-06T22:40:07.164552

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.46 | 0.90 | 0.08 | 0.21 |
| sqlite3 select() | 0.37 | 0.73 | 0.37 | 0.73 |
| sqlite_async getAll() | 0.20 | 0.25 | 0.05 | 0.06 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.53 | 0.62 | 0.10 | 0.11 |
| sqlite3 select() | 0.82 | 1.12 | 0.82 | 1.12 |
| sqlite_async getAll() | 0.81 | 0.95 | 0.17 | 0.22 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 2.56 | 5.93 | 0.47 | 0.51 |
| sqlite3 select() | 4.13 | 4.43 | 4.13 | 4.43 |
| sqlite_async getAll() | 3.92 | 4.71 | 0.86 | 0.99 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.14 | 0.16 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.37 | 0.58 | 0.37 | 0.58 |
| sqlite_async + jsonEncode | 0.36 | 0.44 | 0.21 | 0.28 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.76 | 0.98 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 2.81 | 5.38 | 2.81 | 5.38 |
| sqlite_async + jsonEncode | 2.87 | 5.42 | 2.10 | 3.97 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 3.75 | 4.13 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 13.66 | 15.38 | 13.66 | 15.38 |
| sqlite_async + jsonEncode | 15.73 | 16.94 | 10.74 | 12.83 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.19 | 0.26 | 0.04 | 0.08 |
| sqlite3 | 0.25 | 0.42 | 0.25 | 0.42 |
| sqlite_async | 0.30 | 0.41 | 0.10 | 0.10 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.18 | 1.27 | 0.39 | 0.43 |
| sqlite3 | 2.08 | 2.19 | 2.08 | 2.19 |
| sqlite_async | 1.77 | 1.92 | 0.52 | 0.65 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.81 | 1.07 | 0.15 | 0.16 |
| sqlite3 | 1.17 | 1.25 | 1.17 | 1.25 |
| sqlite_async | 1.17 | 1.29 | 0.21 | 0.23 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.42 | 0.49 | 0.15 | 0.16 |
| sqlite3 | 0.65 | 0.72 | 0.65 | 0.72 |
| sqlite_async | 0.65 | 0.76 | 0.21 | 0.31 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.41 | 0.51 | 0.15 | 0.16 |
| sqlite3 | 0.64 | 0.69 | 0.64 | 0.69 |
| sqlite_async | 0.63 | 0.78 | 0.22 | 0.23 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

| Rows | resqlite wall | resqlite main | sqlite3 wall | sqlite_async wall |
|---|---|---|---|---|
| 10 | 0.08 | 0.00 | 0.02 | 0.05 |
| 50 | 0.10 | 0.01 | 0.05 | 0.08 |
| 100 | 0.10 | 0.01 | 0.09 | 0.10 |
| 500 | 0.29 | 0.06 | 0.42 | 0.32 |
| 1000 | 0.55 | 0.13 | 0.86 | 0.57 |
| 2000 | 0.98 | 0.25 | 1.64 | 1.12 |
| 5000 | 2.85 | 0.65 | 4.05 | 2.69 |
| 10000 | 5.72 | 1.28 | 8.45 | 5.67 |
| 20000 | 14.72 | 2.47 | 20.07 | 18.24 |

### Bytes (selectBytes → JSON)

| Rows | resqlite wall | sqlite3+json wall | async+json wall |
|---|---|---|---|
| 10 | 0.07 | 0.04 | 0.09 |
| 50 | 0.10 | 0.15 | 0.17 |
| 100 | 0.13 | 0.27 | 0.29 |
| 500 | 0.40 | 1.29 | 1.28 |
| 1000 | 0.71 | 2.61 | 2.57 |
| 2000 | 1.41 | 5.82 | 5.56 |
| 5000 | 3.50 | 14.78 | 15.02 |
| 10000 | 6.95 | 29.20 | 29.39 |
| 20000 | 16.06 | 61.96 | 67.41 |

## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency).

| Concurrency | resqlite wall | resqlite/query | async wall | async/query |
|---|---|---|---|---|
| 1 | 0.39 | 0.39 | 0.55 | 0.55 |
| 2 | 0.41 | 0.21 | 0.60 | 0.30 |
| 4 | 0.54 | 0.14 | 0.66 | 0.17 |
| 8 | 1.07 | 0.13 | 2.08 | 0.26 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 18.96 | 20.22 | 18.96 | 20.22 |
| sqlite3 (no cache) | 23.96 | 24.14 | 23.96 | 24.14 |
| sqlite3 (cached stmt) | 23.86 | 24.65 | 23.86 | 24.65 |
| sqlite_async getAll() | 25.15 | 27.13 | 25.15 | 27.13 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.73 | 2.24 | 1.73 | 2.24 |
| sqlite3 execute() | 5.19 | 5.62 | 5.19 | 5.62 |
| sqlite_async execute() | 4.10 | 4.49 | 4.10 | 4.49 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.09 | 0.09 | 0.09 | 0.09 |
| sqlite3 (manual tx + stmt) | 0.21 | 0.26 | 0.21 | 0.26 |
| sqlite_async executeBatch() | 0.12 | 0.20 | 0.12 | 0.20 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.47 | 0.51 | 0.47 | 0.51 |
| sqlite3 (manual tx + stmt) | 0.55 | 0.61 | 0.55 | 0.61 |
| sqlite_async executeBatch() | 0.56 | 0.67 | 0.56 | 0.67 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.77 | 11.77 | 4.77 | 11.77 |
| sqlite3 (manual tx + stmt) | 4.46 | 5.32 | 4.46 | 5.32 |
| sqlite_async executeBatch() | 5.14 | 5.65 | 5.14 | 5.65 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.06 | 0.14 | 0.06 | 0.14 |
| sqlite_async writeTransaction() | 0.12 | 0.20 | 0.12 | 0.20 |

## Comparison vs Previous Run

Previous: `2026-04-06T22-05-35-baseline-before-authorizer-hooks.md`

| Benchmark | Previous (ms) | Current (ms) | Delta | Status |
|---|---|---|---|---|
| Parameterized Queries / 100 queries × ~500 rows each / sq... | 18.30 | 18.96 | +0.66 | ⚪ Neutral |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / s... | 0.15 | 0.19 | +0.04 | 🔴 Regression (+27%) |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.41 | 0.41 | +0.00 | ⚪ Neutral |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.40 | 0.42 | +0.02 | ⚪ Neutral |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.78 | 0.81 | +0.03 | ⚪ Neutral |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 1.07 | 1.18 | +0.11 | 🔴 Regression (+10%) |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.14 | 0.14 | +0.00 | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.71 | 0.76 | +0.05 | ⚪ Neutral |
| Select → JSON Bytes / 5000 rows / resqlite selectBytes() | 3.44 | 3.75 | +0.31 | ⚪ Neutral |
| Select → Maps / 100 rows / resqlite select() | 0.52 | 0.46 | -0.06 | 🟢 Win (-12%) |
| Select → Maps / 1000 rows / resqlite select() | 0.51 | 0.53 | +0.02 | ⚪ Neutral |
| Select → Maps / 5000 rows / resqlite select() | 2.33 | 2.56 | +0.23 | ⚪ Neutral |
| Write Performance / Batch Insert (100 rows) / resqlite exe... | 0.08 | 0.09 | +0.01 | 🔴 Regression (+12%) |
| Write Performance / Batch Insert (1000 rows) / resqlite ex... | 0.45 | 0.47 | +0.02 | ⚪ Neutral |
| Write Performance / Batch Insert (10000 rows) / resqlite e... | 4.55 | 4.77 | +0.22 | ⚪ Neutral |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.06 | +0.00 | ⚪ Neutral |
| Write Performance / Single Inserts (100 sequential) / sql... | 1.72 | 1.73 | +0.01 | ⚪ Neutral |

**Summary:** 1 wins, 3 regressions, 13 neutral (threshold: ±10%)

⚠️ **Regressions detected.** Review the flagged benchmarks above.


