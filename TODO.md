# resqlite TODO

## Stream Refinements

- [x] **Result-change detection on streams.** Incremental hash comparison suppresses duplicate emissions when query results are unchanged after a write. *(Implemented: overnight experiments iteration 40)*

- [x] **Stream cleanup robustness.** Broadcast controller `onCancel` removes stream entries when the last listener cancels, preventing memory leaks. Tested with single-listener, multi-listener, and re-creation scenarios. *(Implemented: commit 181f0df)*

- [ ] **Stream dedup for late joiners.** If two `db.stream()` calls with the same SQL+params happen before the first initial query completes, both create separate entries. Add a "pending" state to the registry that queues late joiners until the initial query finishes. Low priority — harmless (just duplicate work).

## Error Handling

- [x] **Proper exception types.** `ResqliteException` (base), `ResqliteQueryException` (with sql, params, sqliteCode), `ResqliteConnectionException`. *(Implemented: commit e8d5691)*

- [ ] **Writer isolate crash detection.** If the writer isolate crashes (native segfault), `_writerPort` becomes stale and subsequent writes hang. Listen to the isolate's exit port and throw `ResqliteConnectionException` on subsequent writes. Deferred — recovery (respawning) adds complexity for an extreme edge case.

- [ ] **Read isolate error propagation.** Errors from `_selectOnWorker` arrive as `RemoteError`. Wrap in `ResqliteQueryException` with the original SQL and params for debuggability.

## Connection Configuration

- [x] **Encryption support.** sqlite3mc integrated, `encryptionKey` parameter on `Database.open`. *(Implemented: commit abf06db)*

- [ ] **Database.open options.** Support configuring: busy timeout, synchronous level, foreign keys, custom PRAGMAs, max reader count. Currently hardcoded in C. Could pass a config struct or run PRAGMAs after open.

## API Polish

- [ ] **selectBytes blob encoding.** Currently uses hex encoding for BLOBs in JSON output. Switch to base64 for standard JSON/REST compatibility. Requires updating C code.

- [ ] **Read-only Database.open.** Open in read-only mode (no writer connection, no writer isolate). Useful for read replicas or archive databases.

## Documentation

- [ ] **API documentation.** Dartdoc comments on all public types and methods.

- [ ] **README.** Getting started, API overview, benchmarks, comparison with other libraries.
