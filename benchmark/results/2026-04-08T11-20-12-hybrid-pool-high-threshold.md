# resqlite Benchmark Results

Generated: 2026-04-08T11:19:46.325830

Libraries compared:
- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy
- **sqlite3** — raw FFI, synchronous, per-cell column reads
- **sqlite_async** — PowerSync, async connection pool

## Select → Maps

Query returns `List<Map<String, Object?>>`, caller iterates every field.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.29 | 0.52 | 0.08 | 0.16 |
| sqlite3 select() | 0.27 | 0.51 | 0.27 | 0.51 |
| sqlite_async getAll() | 0.20 | 0.28 | 0.06 | 0.06 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.39 | 0.47 | 0.10 | 0.10 |
| sqlite3 select() | 0.84 | 1.16 | 0.84 | 1.16 |
| sqlite_async getAll() | 0.87 | 1.00 | 0.17 | 0.18 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 2.13 | 4.26 | 0.47 | 0.48 |
| sqlite3 select() | 4.00 | 4.17 | 4.00 | 4.17 |
| sqlite_async getAll() | 3.63 | 4.07 | 0.82 | 0.84 |

## Select → JSON Bytes

Query result serialized to JSON-encoded `Uint8List` for HTTP response.

### 100 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.13 | 0.15 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 0.38 | 0.56 | 0.38 | 0.56 |
| sqlite_async + jsonEncode | 0.32 | 0.34 | 0.21 | 0.22 |

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 0.73 | 0.76 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 2.66 | 4.42 | 2.66 | 4.42 |
| sqlite_async + jsonEncode | 2.67 | 4.25 | 2.02 | 3.19 |

### 5000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite selectBytes() | 3.61 | 4.01 | 0.00 | 0.00 |
| sqlite3 + jsonEncode | 14.63 | 15.40 | 14.63 | 15.40 |
| sqlite_async + jsonEncode | 14.93 | 15.88 | 10.13 | 10.96 |

## Schema Shapes (1000 rows)

Tests performance across different column counts and data types.

### Narrow (2 cols: id + int)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.11 | 0.20 | 0.04 | 0.13 |
| sqlite3 | 0.25 | 0.41 | 0.25 | 0.41 |
| sqlite_async | 0.30 | 0.33 | 0.10 | 0.11 |

### Wide (20 cols: mixed types)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.96 | 0.98 | 0.39 | 0.40 |
| sqlite3 | 2.02 | 2.10 | 2.02 | 2.10 |
| sqlite_async | 1.65 | 1.70 | 0.53 | 0.53 |

### Text-heavy (4 long TEXT cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.55 | 0.57 | 0.15 | 0.15 |
| sqlite3 | 1.14 | 1.15 | 1.14 | 1.15 |
| sqlite_async | 1.07 | 1.20 | 0.22 | 0.23 |

### Numeric-heavy (5 numeric cols)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.34 | 0.35 | 0.15 | 0.16 |
| sqlite3 | 0.68 | 0.69 | 0.68 | 0.69 |
| sqlite_async | 0.64 | 0.83 | 0.22 | 0.24 |

### Nullable (50% NULLs)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite | 0.34 | 0.35 | 0.15 | 0.15 |
| sqlite3 | 0.64 | 0.69 | 0.64 | 0.69 |
| sqlite_async | 0.63 | 0.68 | 0.23 | 0.23 |

## Scaling (10 → 20,000 rows)

Shows how each library scales with result size. Identifies the crossover point where resqlite's isolate overhead becomes negligible.

### Maps (select → iterate all fields)

| Rows | resqlite wall | resqlite main | sqlite3 wall | sqlite_async wall |
|---|---|---|---|---|
| 10 | 0.02 | 0.00 | 0.02 | 0.06 |
| 50 | 0.03 | 0.01 | 0.05 | 0.08 |
| 100 | 0.05 | 0.01 | 0.09 | 0.12 |
| 500 | 0.22 | 0.07 | 0.42 | 0.40 |
| 1000 | 0.42 | 0.13 | 0.83 | 0.76 |
| 2000 | 0.82 | 0.25 | 1.66 | 1.49 |
| 5000 | 2.27 | 0.64 | 4.13 | 3.77 |
| 10000 | 4.98 | 1.27 | 8.30 | 8.12 |
| 20000 | 12.33 | 2.54 | 21.59 | 24.87 |

### Bytes (selectBytes → JSON)

| Rows | resqlite wall | sqlite3+json wall | async+json wall |
|---|---|---|---|
| 10 | 0.07 | 0.04 | 0.09 |
| 50 | 0.09 | 0.15 | 0.18 |
| 100 | 0.13 | 0.28 | 0.30 |
| 500 | 0.40 | 1.34 | 1.41 |
| 1000 | 0.72 | 2.69 | 2.61 |
| 2000 | 1.45 | 5.68 | 6.63 |
| 5000 | 3.78 | 14.99 | 14.96 |
| 10000 | 7.35 | 28.87 | 29.70 |
| 20000 | 15.12 | 62.85 | 66.98 |

## Concurrent Reads (1000 rows per query)

Multiple parallel `select()` calls via `Future.wait`. sqlite3 is excluded (synchronous, no concurrency).

| Concurrency | resqlite wall | resqlite/query | async wall | async/query |
|---|---|---|---|---|
| 1 | 0.29 | 0.29 | 0.58 | 0.58 |
| 2 | 0.33 | 0.16 | 0.65 | 0.32 |
| 4 | 0.36 | 0.09 | 0.83 | 0.21 |
| 8 | 0.77 | 0.10 | 2.27 | 0.28 |

## Parameterized Queries

Same `SELECT WHERE category = ?` query run 100 times with different parameter values. Table has 5000 rows with an index on `category` (~500 rows per category).

### 100 queries × ~500 rows each

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 14.79 | 15.04 | 14.79 | 15.04 |
| sqlite3 (no cache) | 24.83 | 25.14 | 24.83 | 25.14 |
| sqlite3 (cached stmt) | 24.43 | 25.04 | 24.43 | 25.04 |
| sqlite_async getAll() | 26.01 | 27.29 | 26.01 | 27.29 |

## Write Performance

### Single Inserts (100 sequential)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite execute() | 1.70 | 2.26 | 1.70 | 2.26 |
| sqlite3 execute() | 5.16 | 6.38 | 5.16 | 6.38 |
| sqlite_async execute() | 4.38 | 5.48 | 4.38 | 5.48 |

### Batch Insert (100 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.07 | 0.08 | 0.07 | 0.08 |
| sqlite3 (manual tx + stmt) | 0.10 | 0.12 | 0.10 | 0.12 |
| sqlite_async executeBatch() | 0.11 | 0.18 | 0.11 | 0.18 |

### Batch Insert (1000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 0.47 | 0.53 | 0.47 | 0.53 |
| sqlite3 (manual tx + stmt) | 0.56 | 0.65 | 0.56 | 0.65 |
| sqlite_async executeBatch() | 0.58 | 0.66 | 0.58 | 0.66 |

### Batch Insert (10000 rows)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite executeBatch() | 4.56 | 7.12 | 4.56 | 7.12 |
| sqlite3 (manual tx + stmt) | 4.47 | 5.74 | 4.47 | 5.74 |
| sqlite_async executeBatch() | 5.11 | 5.51 | 5.11 | 5.51 |

### Interactive Transaction (insert + select + conditional delete)

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite transaction() | 0.06 | 0.09 | 0.06 | 0.09 |
| sqlite_async writeTransaction() | 0.12 | 0.21 | 0.12 | 0.21 |

## Comparison vs Previous Run

Previous: `2026-04-07T22-55-38-post-stream-fix.md`

| Benchmark | Previous (ms) | Current (ms) | Delta | Status |
|---|---|---|---|---|
| Parameterized Queries / 100 queries × ~500 rows each / sq... | 19.14 | 14.79 | -4.35 | 🟢 Win (-23%) |
| Schema Shapes (1000 rows) / Narrow (2 cols: id + int) / s... | 0.16 | 0.11 | -0.05 | 🟢 Win (-31%) |
| Schema Shapes (1000 rows) / Nullable (50% NULLs) / resqlite | 0.44 | 0.34 | -0.10 | 🟢 Win (-23%) |
| Schema Shapes (1000 rows) / Numeric-heavy (5 numeric cols... | 0.40 | 0.34 | -0.06 | 🟢 Win (-15%) |
| Schema Shapes (1000 rows) / Text-heavy (4 long TEXT cols)... | 0.63 | 0.55 | -0.08 | 🟢 Win (-13%) |
| Schema Shapes (1000 rows) / Wide (20 cols: mixed types) /... | 1.13 | 0.96 | -0.17 | 🟢 Win (-15%) |
| Select → JSON Bytes / 100 rows / resqlite selectBytes() | 0.21 | 0.13 | -0.08 | 🟢 Win (-38%) |
| Select → JSON Bytes / 1000 rows / resqlite selectBytes() | 0.89 | 0.73 | -0.16 | 🟢 Win (-18%) |
| Select → JSON Bytes / 5000 rows / resqlite selectBytes() | 3.67 | 3.61 | -0.06 | ⚪ Neutral |
| Select → Maps / 100 rows / resqlite select() | 0.38 | 0.29 | -0.09 | 🟢 Win (-24%) |
| Select → Maps / 1000 rows / resqlite select() | 0.59 | 0.39 | -0.20 | 🟢 Win (-34%) |
| Select → Maps / 5000 rows / resqlite select() | 2.64 | 2.13 | -0.51 | 🟢 Win (-19%) |
| Write Performance / Batch Insert (100 rows) / resqlite exe... | 0.07 | 0.07 | +0.00 | ⚪ Neutral |
| Write Performance / Batch Insert (1000 rows) / resqlite ex... | 0.47 | 0.47 | +0.00 | ⚪ Neutral |
| Write Performance / Batch Insert (10000 rows) / resqlite e... | 4.38 | 4.56 | +0.18 | ⚪ Neutral |
| Write Performance / Interactive Transaction (insert + sel... | 0.06 | 0.06 | +0.00 | ⚪ Neutral |
| Write Performance / Single Inserts (100 sequential) / sql... | 1.76 | 1.70 | -0.06 | ⚪ Neutral |

**Summary:** 11 wins, 0 regressions, 6 neutral (threshold: ±10%)

✅ **No regressions.** 11 benchmarks improved.


