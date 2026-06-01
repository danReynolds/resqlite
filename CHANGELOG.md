## Unreleased

- Added open-scoped SQLite extension loading via `Database.open(extensions: ...)`
  and `ResqliteExtension`, plus companion package wrappers for SQLite Vector
  and SQLite JS.
- Added declarative open-time extension setup with writer/reader/all connection
  scopes, plus `SqliteVectorIndex` helpers for SQLite Vector's `vector_init`.

## 0.3.1

- **Bug fix (Linux):** Fixed `undefined symbol` crashes on Linux caused by `resqlite_step_row_hash` and `sqlite3_db_handle` being omitted from the linker version script's export list ([#96](https://github.com/danReynolds/resqlite/pull/96), [#97](https://github.com/danReynolds/resqlite/pull/97)).

## 0.3.0

- **Behavior change:** `PRAGMA foreign_keys = ON` is now applied by default on every connection ([#77](https://github.com/danReynolds/resqlite/pull/77)). Code that relied on FK constraints being silently ignored will now see them enforced.
- **Column-level reactive invalidation.** Streams now record the columns they read and writes record the columns they touch; a write to a column no stream watches no longer dispatches re-queries. Adds public `TableDependencies` / `TableDependency` / `TableColumnDependency` types ([#48](https://github.com/danReynolds/resqlite/pull/48)). +82% on disjoint-column writer-throughput benchmarks (A11c).
- Further write-path and stream-dispatch wins: cached BEGIN/COMMIT/ROLLBACK statements, inline-packed parameter buffer, direct batch parameter matrix encoding, FIFO reader-pool dispatch with bounded synchronous stream admission. See the [interactive benchmark dashboard](https://danreynolds.github.io/resqlite/benchmarks/) for current cross-library numbers.
- Documented that streams over virtual tables (FTS5, R-Tree, JSON1 `json_each`, etc.) don't get reactive invalidation; use `select` instead.

## 0.2.0

- Faster streaming fan-out and write-path marshalling. See the [interactive benchmark dashboard](https://danreynolds.github.io/resqlite/benchmarks/) for current cross-library numbers.

## 0.1.0

- Initial release.
- Persistent reader pool with dedicated worker isolates and automatic sacrifice/respawn for large results.
- Reactive streams with table-level invalidation, result-change detection (FNV-1a hashing), and per-subscriber buffered controllers.
- Native C engine with connection pool, statement cache, JSON serialization, and cell buffer reuse.
- Dedicated reader assignment bypassing C pool mutex for point-query throughput.
- `selectBytes` for zero-copy JSON transfer to server frameworks.
- Transactions with read-your-writes semantics.
- Batch writes via `executeBatch`.
- Encryption support via sqlite3mc.
