## 0.6.0

Performance and observability release. No breaking changes, and no changes to the
public export surface — safe to upgrade from 0.5.x.

**Wins at a glance:** up to **~30% faster concurrent writes** on top of 0.5.0's
pipelining, a new diagnostics counter for native read-buffer memory, and automatic
reclaim of that memory after large-`selectBytes` bursts — bounding the RSS trade-off
0.5.0 introduced with native-view transfer.

- **New API:** `Diagnostics.readerJsonBufHighWaterBytes` — the summed capacity of
  every reader isolate's native `json_buf`, making the read-buffer high-water mark
  directly observable. Surfaces workloads that pin large native buffers after big
  `selectBytes` reads ([#183](https://github.com/danReynolds/resqlite/pull/183),
  [exp 183](https://github.com/danReynolds/resqlite/blob/main/experiments/183-json-buf-retention-audit.md)).
- **Behavior change:** a buffered group of `execute()` calls that races
  `Database.close()` is now atomic — every call in the group either flushes or is
  rejected, never the old lock-order-dependent partial outcome. It still never hangs,
  and per-call success/failure semantics are unchanged ([#184](https://github.com/danReynolds/resqlite/pull/184),
  [exp 180](https://github.com/danReynolds/resqlite/blob/main/experiments/180-group-commit-request-batching.md)).
- **Memory:** native read buffers that grow to serve a large `selectBytes` read now
  reclaim back to their initial capacity on the next small read, once a reader's
  `json_buf` exceeds 1 MB. A one-off concurrent burst of large reads (e.g. 8 × 8 MB)
  previously pinned tens of MB for the connection's lifetime; that high-water now
  settles back to ~64 KB. Warm large-read workloads keep their capacity (a 256 KB
  last-read guard prevents shrink-then-regrow churn) ([#183](https://github.com/danReynolds/resqlite/pull/183),
  [exp 183](https://github.com/danReynolds/resqlite/blob/main/experiments/183-json-buf-retention-audit.md)).
- **Performance.** See the [interactive benchmark dashboard](https://danreynolds.github.io/resqlite/benchmarks/)
  for current cross-library numbers.
  - **Cross-call write batching (group commit)** — standalone `execute()` calls that
    pile up while a write is in flight now coalesce into a single cross-isolate
    request (each statement still its own autocommit), collapsing a concurrent
    burst's per-write round-trips toward two. −26% to −32% on the concurrent
    single-insert lane, on top of 0.5.0's pipelining; isolated and sequential writes
    are unaffected ([#184](https://github.com/danReynolds/resqlite/pull/184),
    [exp 180](https://github.com/danReynolds/resqlite/blob/main/experiments/180-group-commit-request-batching.md)).

## 0.5.0

Performance and reliability release. No breaking changes, and no changes to the
public export surface — safe to upgrade from 0.4.x.

**Wins at a glance:** up to **45% faster concurrent writes**, **~1.8× faster large
`selectBytes` reads** (>256 KB), faster `Row` lookups and batch writes, a new
diagnostics counter for silent re-query fallbacks, and a reader-isolate crash fix
for `diagnostics()` under load.

- **New API:** `Diagnostics.unknownDependencyFallbackCount` — a cumulative counter
  of writes that conservatively re-queried *every* registered stream because native
  dependency tracking overflowed its caps (or hit OOM). Surfaces workloads silently
  paying full re-query fan-out on every write, which was previously unobservable
  ([#151](https://github.com/danReynolds/resqlite/pull/151)).
- **Bug fix:** `Database.diagnostics()` could intermittently crash a reader isolate
  (SEGV) when polled while readers were mid-query — it toggled SQLite memory
  accounting on live `NOMUTEX` reader connections. Read workers now bracket each
  request with a real busy guard, and diagnostics reports busy readers as a partial
  snapshot ([#156](https://github.com/danReynolds/resqlite/pull/156)).
- **Performance.** Each accepted experiment below; see the [interactive benchmark dashboard](https://danreynolds.github.io/resqlite/benchmarks/)
  for current cross-library numbers.
  - **Writer-request pipelining** over a persistent reply port — −36% to −45% on
    concurrent standalone writes ([#153](https://github.com/danReynolds/resqlite/pull/153),
    [exp 159](https://github.com/danReynolds/resqlite/blob/main/experiments/159-writer-pipelining.md)).
  - **`selectBytes` native-view transfer** — sends a view over the reader's native
    `json_buf` instead of taking the sacrifice/respawn path; −44% (~1.8×) on large
    (>256 KB) byte reads, at a bounded ~+15 MB RSS ([#169](https://github.com/danReynolds/resqlite/pull/169),
    [exp 174](https://github.com/danReynolds/resqlite/blob/main/experiments/174-selectbytes-view-transfer.md)).
  - **`Row.containsKey` identity fast path** — pointer-identity membership scan for
    interned keys on schemas ≤ 32 columns; −23% on the `containsKey` lane
    ([#173](https://github.com/danReynolds/resqlite/pull/173),
    [exp 176](https://github.com/danReynolds/resqlite/blob/main/experiments/176-row-containskey-identity-fastpath.md)).
  - **`RowSchema` lookup fast path** — schema-name identity scan with `HashMap`
    fallback; ~2× faster main-isolate map consumption at 10K rows
    ([#150](https://github.com/danReynolds/resqlite/pull/150),
    [exp 158](https://github.com/danReynolds/resqlite/blob/main/experiments/158-row-schema-hash-index.md)).
  - **Six-parameter batch packing** — extends guarded ASCII batch packing to the
    six-parameter shape; `executeBatch` p50 88 → 75 µs ([#141](https://github.com/danReynolds/resqlite/pull/141),
    [exp 149](https://github.com/danReynolds/resqlite/blob/main/experiments/149-six-param-batch-packing.md)).
  - **Nullable batch packing** — nullable-aware packed batch encoder for first-row
    `NULL` text columns; nullable ASCII 10k×20 25.7 → 21.7 ms ([#145](https://github.com/danReynolds/resqlite/pull/145),
    [exp 150](https://github.com/danReynolds/resqlite/blob/main/experiments/150-nullable-batch-packing.md)).

## 0.4.0

- Added open-scoped SQLite extension loading via `Database.open(extensions: ...)`
  and `ResqliteExtension`, plus companion package wrappers for SQLite Vector
  and SQLite JS.
- Added declarative open-time extension setup with `onRegister`, writer/reader/all
  connection scopes, and `SqliteVectorIndex` helpers for SQLite Vector's
  `vector_init`.

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
