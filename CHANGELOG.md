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
