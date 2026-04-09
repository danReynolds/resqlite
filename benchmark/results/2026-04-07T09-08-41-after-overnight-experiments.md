# resqlite Benchmark Results

Generated: 2026-04-07T09:08:11.013303

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.30 | 0.73 | 0.06 | 0.19 |
| sqlite3 select() | 0.27 | 0.53 | 0.27 | 0.53 |
| sqlite_async getAll() | 0.18 | 0.25 | 0.04 | 0.05 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.49 | 0.59 | 0.10 | 0.10 |
| sqlite3 select() | 0.71 | 1.00 | 0.71 | 1.00 |
| sqlite_async getAll() | 0.70 | 0.84 | 0.11 | 0.12 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 2.49 | 7.05 | 0.47 | 0.58 |
| sqlite3 select() | 3.63 | 4.90 | 3.63 | 4.90 |
| sqlite_async getAll() | 3.71 | 4.16 | 0.59 | 0.74 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.13 | 0.16 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.36 | 0.52 | 0.36 | 0.52 |
| sqlite_async + jsonEncode | 0.33 | 0.39 | 0.21 | 0.24 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.77 | 0.91 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 2.65 | 6.09 | 2.65 | 6.09 |
| sqlite_async + jsonEncode | 2.98 | 5.80 | 2.07 | 4.18 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 3.62 | 3.80 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 15.96 | 17.45 | 15.96 | 17.45 |
| sqlite_async + jsonEncode | 15.27 | 17.80 | 10.43 | 11.14 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.17 | 0.28 | 0.04 | 0.15 |
| sqlite3 | 0.21 | 0.41 | 0.21 | 0.41 |
| sqlite_async | 0.29 | 0.37 | 0.07 | 0.08 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 1.10 | 1.26 | 0.42 | 0.44 |
| sqlite3 | 1.86 | 1.94 | 1.86 | 1.94 |
| sqlite_async | 1.59 | 1.87 | 0.38 | 0.42 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.63 | 0.78 | 0.15 | 0.17 |
| sqlite3 | 1.06 | 1.18 | 1.06 | 1.18 |
| sqlite_async | 1.07 | 1.25 | 0.16 | 0.18 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.40 | 0.44 | 0.15 | 0.16 |
| sqlite3 | 0.57 | 0.60 | 0.57 | 0.60 |
| sqlite_async | 0.56 | 0.64 | 0.16 | 0.17 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.40 | 0.42 | 0.15 | 0.15 |
| sqlite3 | 0.53 | 0.56 | 0.53 | 0.56 |
| sqlite_async | 0.54 | 0.58 | 0.15 | 0.15 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

| Rows | resqlite wall | resqlite main | sqlite3 wall | sqlite_async wall |
|---|---|---|---|---|
| 10 | 0.07 | 0.00 | 0.02 | 0.06 |
| 50 | 0.10 | 0.01 | 0.04 | 0.08 |
| 100 | 0.10 | 0.01 | 0.08 | 0.10 |
| 500 | 0.27 | 0.07 | 0.37 | 0.30 |
| 1000 | 0.48 | 0.13 | 0.72 | 0.57 |
| 2000 | 0.89 | 0.26 | 1.46 | 1.10 |
| 5000 | 2.35 | 0.63 | 3.72 | 3.01 |
| 10000 | 5.37 | 1.29 | 7.51 | 6.13 |
| 20000 | 14.27 | 2.52 | 20.43 | 20.35 |

### Bytes (selectBytes → JSON)

| Rows | resqlite wall | sqlite3+json wall | async+json wall |
|---|---|---|---|
| 10 | 0.07 | 0.04 | 0.08 |
| 50 | 0.10 | 0.15 | 0.21 |
| 100 | 0.13 | 0.27 | 0.30 |
| 500 | 0.40 | 1.31 | 1.36 |
| 1000 | 0.73 | 2.63 | 2.70 |
| 2000 | 1.52 | 5.87 | 6.02 |
| 5000 | 3.58 | 14.67 | 15.37 |
| 10000 | 7.08 | 32.57 | 30.71 |
| 20000 | 15.13 | 60.67 | 64.77 |

## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency).

| Concurrency | resqlite wall | resqlite/query | async wall | async/query |
|---|---|---|---|---|
| 1 | 0.36 | 0.36 | 0.57 | 0.57 |
| 2 | 0.37 | 0.19 | 0.63 | 0.32 |
| 4 | 0.52 | 0.13 | 0.75 | 0.19 |
| 8 | 0.81 | 0.10 | 1.64 | 0.20 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 18.64 | 20.99 | 18.64 | 20.99 |
| sqlite3 (no cache) | 22.67 | 23.37 | 22.67 | 23.37 |
| sqlite3 (cached stmt) | 22.84 | 23.22 | 22.84 | 23.22 |
| sqlite_async getAll() | 25.86 | 26.92 | 25.86 | 26.92 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.81 | 2.42 | 1.81 | 2.42 |
| sqlite3 execute() | 4.99 | 5.43 | 4.99 | 5.43 |
| sqlite_async execute() | 3.79 | 4.68 | 3.79 | 4.68 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.09 | 0.09 | 0.09 | 0.09 |
| sqlite3 (manual tx + stmt) | 0.16 | 0.20 | 0.16 | 0.20 |
| sqlite_async executeBatch() | 0.12 | 0.14 | 0.12 | 0.14 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.47 | 0.51 | 0.47 | 0.51 |
| sqlite3 (manual tx + stmt) | 0.51 | 0.59 | 0.51 | 0.59 |
| sqlite_async executeBatch() | 0.54 | 0.65 | 0.54 | 0.65 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.85 | 11.56 | 4.85 | 11.56 |
| sqlite3 (manual tx + stmt) | 4.61 | 5.15 | 4.61 | 5.15 |
| sqlite_async executeBatch() | 5.34 | 6.55 | 5.34 | 6.55 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.06 | 0.08 | 0.06 | 0.08 |
| sqlite_async writeTransaction() | 0.10 | 0.11 | 0.10 | 0.11 |

## Comparison vs Previous Run

Previous: `2026-04-06T22-40-34-after-authorizer-hooks.md`

| Benchmark | Previous (ms) | Current (ms) | Delta | Status |
|---|---|---|---|---|
| Parameterized Queries / 100 queries × ~500 rows each / sq... | 18.96 | 18.64 | -0.32 | ⚪ Neutral |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / s... | 0.19 | 0.17 | -0.02 | 🟢 Win (-11%) |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.41 | 0.40 | -0.01 | ⚪ Neutral |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.42 | 0.40 | -0.02 | ⚪ Neutral |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.81 | 0.63 | -0.18 | 🟢 Win (-22%) |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 1.18 | 1.10 | -0.08 | ⚪ Neutral |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.14 | 0.13 | -0.01 | ⚪ Neutral |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.76 | 0.77 | +0.01 | ⚪ Neutral |
| Select → JSON Bytes / 5000 rows / resqlite selectBytes() | 3.75 | 3.62 | -0.13 | ⚪ Neutral |
| Select → Maps / 100 rows / resqlite select() | 0.46 | 0.30 | -0.16 | 🟢 Win (-35%) |
| Select → Maps / 1000 rows / resqlite select() | 0.53 | 0.49 | -0.04 | ⚪ Neutral |
| Select → Maps / 5000 rows / resqlite select() | 2.56 | 2.49 | -0.07 | ⚪ Neutral |
| Write Performance / Batch Insert (100 rows) / resqlite exe... | 0.09 | 0.09 | +0.00 | ⚪ Neutral |
| Write Performance / Batch Insert (1000 rows) / resqlite ex... | 0.47 | 0.47 | +0.00 | ⚪ Neutral |
| Write Performance / Batch Insert (10000 rows) / resqlite e... | 4.77 | 4.85 | +0.08 | ⚪ Neutral |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.06 | +0.00 | ⚪ Neutral |
| Write Performance / Single Inserts (100 sequential) / sql... | 1.73 | 1.81 | +0.08 | ⚪ Neutral |

**Summary:** 3 wins, 0 regressions, 14 neutral (threshold: ±10%)

✅ **No regressions.** 3 benchmarks improved.


