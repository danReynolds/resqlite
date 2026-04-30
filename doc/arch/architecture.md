# resqlite Architecture

resqlite is a high-performance SQLite library for Dart built on raw C FFI (Foreign Function Interface — how Dart calls native C code). It's designed around a single principle: **minimize main-isolate work**.

In a Flutter app, the main isolate is the single thread responsible for rendering your UI at 60fps — that's a 16ms budget per frame. Every millisecond your database spends on the main isolate is a millisecond that could cause dropped frames, stuttery scrolling, or unresponsive touch handling. resqlite pushes virtually all database work off the main isolate, leaving it free for what it's meant to do: render your UI.

This post walks through the high-level architecture — how the pieces fit together and why they're designed this way.

## System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                       Main Isolate                          │
│                                                             │
│  Database                                                   │
│  ├── select() / selectBytes()  →  Reader Pool               │
│  │   └── Persistent worker isolates (SendPort or            │
│  │       Isolate.exit based on result size)                  │
│  │                                                          │
│  ├── execute() / executeBatch() / transaction()             │
│  │   └── Messages to persistent Writer Isolate              │
│  │       └── Results + dirty tables via SendPort            │
│  │                                                          │
│  ├── stream()  →  StreamEngine                              │
│  │   ├── Initial query via reader pool (captures deps)      │
│  │   ├── Per-subscriber buffered controllers                │
│  │   └── Re-queries via reader pool on invalidation         │
│  │                                                          │
│  └── C Connection Pool (process-global, survives isolates)  │
│      ├── Writer: 1 connection + statement cache + mutex     │
│      ├── Readers: N connections + statement caches           │
│      ├── Preupdate hook on writer (dirty table tracking)    │
│      └── Authorizer hook on readers (dependency tracking)   │
└─────────────────────────────────────────────────────────────┘
```

## Core Principles

**1. C owns the state, Dart owns the orchestration.**
Database connections, statement caches, mutexes, and hooks live in C structs that persist across Dart isolate lifetimes. Dart isolates are workers that call into C, do their work, and return results. This separation means the expensive state (open connections, cached prepared statements) survives worker isolate deaths and respawns.

**2. Reads use a persistent reader pool with hybrid transmission.**
A pool of 2-4 persistent worker isolates dispatches queries via SendPort. Small results return via SendPort (fast, no spawn cost). Large results trigger the worker to sacrifice itself via `Isolate.exit()` (zero-copy transfer) — the pool auto-respawns a replacement in the background. This eliminates the ~0.08ms isolate spawn cost that one-off `Isolate.run` would impose per query.

**3. Writes use a persistent isolate for sequential execution.**
SQLite only supports one writer at a time. A single persistent writer isolate processes all writes sequentially, maintaining transaction state across messages. Write results (small — affected rows, last insert ID) transfer via `SendPort.send()` which is fine for small payloads.

**4. Stream invalidation piggybacks on write responses.**
No separate notification channel. Every write response includes the tables and, when SQLite can report them precisely, columns modified by the write. The StreamEngine checks these against active stream dependencies and re-queries only the streams that can change.

## Read Path: select() and selectBytes()

Reads are the hot path for most SQLite-backed applications, and they are also where a Flutter library can most easily steal time from the UI thread. resqlite exposes two read APIs:

- **`select(sql, params)`** -> `Future<List<Map<String, Object?>>>`, for ordinary Dart row access.
- **`selectBytes(sql, params)`** -> `Future<Uint8List>`, for JSON bytes when the caller wants to write a response or file without first materializing Dart maps.

Both APIs dispatch through the same persistent reader pool. The pool keeps worker isolates alive, assigns one query at a time to each worker, and sends the worker into the C connection pool. Small results return over `SendPort.send()`. Large results return via `Isolate.exit()`, which avoids copying the result graph and lets the pool respawn the sacrificed worker in the background.

```
select()/selectBytes()
  └─ ReaderPool._dispatch() -> find available worker
      └─ Worker isolate
          ├─ resqlite_stmt_acquire() -> idle C reader + cached statement
          ├─ Execute query
          ├─ resqlite_stmt_release() -> return reader to pool
          └─ SendPort.send or Isolate.exit based on result size
```

### Reader pool

The Dart reader pool manages a small set of persistent worker isolates. Dispatch is round-robin with busy tracking: a worker is available when it is alive, has published a `SendPort`, and is not currently processing a query. If all workers are busy, callers wait on a shared completer that fires when any worker becomes available.

The hybrid transfer threshold was tuned empirically. Below the threshold, keeping the worker alive and paying the copy cost is cheaper. Above it, `Isolate.exit()` wins because the large result transfers without copying. The worker wraps replies in an envelope that tells the pool whether it sacrificed itself, so the slot stays unavailable until its replacement is ready.

### Flat-list ResultSet

The main `select()` path stores all row values in a single flat `List<Object?>`:

```
values = [row0_col0, row0_col1, ..., row0_colN, row1_col0, ...]
```

`ResultSet` creates lightweight `Row` views lazily when a caller indexes into the result. Each `Row` implements `Map<String, Object?>` against a shared `RowSchema`, so users keep normal map ergonomics without paying for a `LinkedHashMap` per row.

This mattered because `Isolate.exit()` still validates the object graph it transfers. With per-row maps, a 20,000-row result can contain hundreds of thousands of map-internal objects. With the flat list, the structural graph is essentially the result object, schema, and values list. The value objects are unchanged, but the transfer graph is dramatically smaller. See [Experiment 008](../../experiments/008-flat-list-lazy-resultset.md).

### Batch FFI

Instead of calling through FFI for every SQLite column operation, resqlite steps one row at a time with a batched C helper:

```c
int resqlite_step_row(sqlite3_stmt* stmt, int col_count, resqlite_cell* cells);
```

C advances the statement and fills a pre-allocated native cell buffer with all column types and values. Dart reads that buffer through `ByteData`. Integers and doubles are direct native reads; text still becomes Dart `String` objects, which is unavoidable for the map API. This reduces a typical row from many FFI calls to one. See [Experiment 009](../../experiments/009-batch-ffi-step-row.md).

### C connection pool

The C layer owns multiple read-only `sqlite3*` connections, each with its own prepared statement cache. `resqlite_stmt_acquire()` finds an idle reader, prepares or retrieves the statement, binds parameters, and holds the per-query mutex until the query is complete.

Connections are opened with `SQLITE_OPEN_NOMUTEX`. Instead of SQLite's `FULLMUTEX` locking around every API call, resqlite locks around the whole query. For large result sets, that replaces tens of thousands of lock/unlock operations with one acquire and one release. See [Experiment 004](../../experiments/004-nomutex-per-query-locking.md).

### selectBytes()

`selectBytes()` bypasses Dart row objects entirely. A C function reads SQLite columns and writes JSON directly into a `malloc`'d buffer:

```c
int resqlite_query_bytes(resqlite_db* db, const char* sql, ...);
```

The C path handles string escaping, integer formatting, double formatting, null literals, and JSON structure. The result is one `Uint8List`, which is cheap to transfer and ready for HTTP responses or file export. This is the right API when the consumer wants JSON and the application does not need to inspect each row in Dart. See [Experiment 001](../../experiments/001-c-native-json-serialization.md).

At 5,000 rows with six mixed columns:

| Metric | select() | selectBytes() | sqlite3 | sqlite_async |
|---|---|---|---|---|
| Wall time | 2.25 ms | 3.14 ms | 4.20 ms | 4.10 ms |
| Main-isolate time | 0.49 ms | 0.00 ms | 4.20 ms | 0.83 ms |

## Write Path: execute(), executeBatch(), transaction()

SQLite only allows one writer at a time. resqlite embraces that constraint by routing all writes through one persistent writer isolate. The writer processes messages sequentially, owns transaction state, and keeps write work off the main isolate.

The write API has three public shapes:

- **`execute(sql, params)`** -> `Future<WriteResult>`, for one statement.
- **`executeBatch(sql, paramSets)`** -> `Future<void>`, for one SQL statement with many parameter sets.
- **`transaction(callback)`** -> `Future<T>`, for interactive multi-statement work with reads.

### Writer isolate message protocol

The writer isolate receives sealed request messages from `write_worker.dart`:

| Message | Purpose | Response |
|---|---|---|
| `ExecuteRequest` | Single parameterized write | `ExecuteResponse(WriteResult, dirtyTables)` |
| `QueryRequest` | Read within a transaction | `QueryResponse(rows, dirtyTables)` |
| `BatchRequest` | Batch write | `BatchResponse(dirtyTables)` |
| `BeginRequest` | Start transaction | `true` |
| `CommitRequest` | Commit transaction | `BatchResponse(dirtyTables)` |
| `RollbackRequest` | Rollback transaction | `true` |

Each request carries a reply port. The writer pattern-matches the message, calls the relevant C function, and returns either a small result or an error envelope.

### execute() and executeBatch()

`execute()` prepares or retrieves a cached statement, binds parameters, steps, and returns `sqlite3_changes()` plus `sqlite3_last_insert_rowid()`. DDL and non-parameterized statements can use the simpler `sqlite3_exec()` path.

`executeBatch()` moves the loop into C:

1. Lock the writer mutex.
2. Begin a transaction.
3. Prepare the statement once.
4. Loop through the flat native parameter array: bind, step, reset.
5. Commit or roll back.
6. Unlock.

This avoids a Dart-to-C boundary crossing for every row in a batch. Parameters are serialized into a contiguous native array of `resqlite_param` structs, so C can index into `param_sets[i * param_count + j]`.

### transaction()

Transactions use an async callback on the main isolate:

```dart
final count = await db.transaction((tx) async {
  await tx.execute('INSERT INTO users(name) VALUES (?)', ['alice']);
  final rows = await tx.select('SELECT COUNT(*) AS cnt FROM users');
  return rows[0]['cnt'] as int;
});
```

The callback does not run on the worker. That is intentional. Running a closure on another isolate would require every captured object to be sendable, which is easy to violate accidentally. Instead, the callback is ordinary Dart code on main, and `tx.execute()` or `tx.select()` sends request messages to the writer isolate.

Transaction reads run on the writer connection, not the reader pool, because uncommitted writes are visible only on the connection that made them. Those results return through `SendPort.send()`, which is acceptable because transaction reads are usually small.

### Dirty table tracking

The writer connection installs `sqlite3_preupdate_hook`. Every INSERT, UPDATE, or DELETE records the affected table in a deduplicated dirty-table set. Write responses include that set so the stream engine can invalidate affected reactive queries.

Inside a transaction, dirty tables accumulate until commit. Individual statements return empty dirty sets, commit returns the accumulated set, and rollback clears the set without notifying streams.

Representative write benchmarks:

| Workload | resqlite | sqlite3 | sqlite_async |
|---|---:|---:|---:|
| 100 sequential inserts | 1.73 ms | 5.19 ms | 4.10 ms |
| 1,000-row batch insert | 0.48 ms | 0.57 ms | 0.63 ms |
| Interactive transaction | 0.06 ms | n/a | 0.12 ms |

## Reactive Streams: stream()

`stream()` turns a query into a live data source. It emits current results immediately, then re-emits when writes modify data the query can observe.

```dart
final stream = db.stream('SELECT * FROM users WHERE active = ?', [1]);
stream.listen((rows) {
  setState(() => users = rows);
});
```

The mechanism combines three pieces:

1. **SQLite authorizer hooks** on readers capture which tables a query reads.
2. **SQLite authorizer hooks** on prepared writes capture which columns a statement may modify.
3. **SQLite preupdate hooks** on the writer capture which tables actually changed.
4. **StreamEngine** on main matches dirty table/column dependencies and schedules re-queries.

### Dependency capture

SQLite's [authorizer callback](https://www.sqlite.org/c3ref/set_authorizer.html) fires during query planning and execution. For `SQLITE_READ`, it receives the table and column being read. resqlite installs this on every reader connection and stores the accumulated table/column set on the cached statement entry.

This avoids SQL parsing. The authorizer naturally handles joins, subqueries, views, common table expressions, triggers, and attached databases. SQLite tells resqlite what was actually read.

Column metadata is an optimization layer, not the correctness source of truth. If a query touches too many columns, allocation fails, a trigger or cascade writes outside the prepared statement metadata, or SQLite cannot provide column precision, resqlite falls back to table-level invalidation for the affected table. If table tracking itself is unavailable, every active stream re-queries.

### StreamEngine lifecycle

`StreamEngine` owns active reactive queries. It keeps:

- `_entries`, keyed by `Object.hash(sql, Object.hashAll(params))`, so identical streams share one SQLite query.
- `_unknownDepsEntries`, streams whose table dependencies are not available yet or fell back to unknown.
- `_tableIndex`, an inverted index from table name to affected stream entries.
- `_requeryQueue`, a bounded queue of dirty entries waiting for reader-pool capacity.

Each stream entry tracks its SQL, params, table dependencies, optional column dependencies, cached last result, in-flight state, and subscriber controllers.

Subscribers get individual non-broadcast controllers. That avoids the race where a broadcast stream drops events when a listener attaches during an async gap. New subscribers to an existing query receive the cached last result immediately.

### Invalidation and stale-result protection

When a write returns table dependencies, `database.dart` calls `streamEngine.onDependencyChanges()`. The engine first uses `_tableIndex` to find streams that share a table. If both the stream and the write have fixed column details for that table, it intersects those sets and skips the re-query when they are disjoint. A plain table dependency means column precision is unavailable, so streams on that table re-query.

If rapid writes dispatch multiple re-queries for the same stream, duplicate queue entries collapse before they reach the reader pool. A result hash suppresses no-op emissions when a table was dirtied but the query result did not actually change.

Initial stream emission and invalidation benchmark:

| Metric | resqlite | sqlite_async |
|---|---:|---:|
| Initial emission | 0.03 ms | 0.10 ms |
| Invalidation latency | 0.07 ms | 0.05 ms |

In the many-stream writer-throughput benchmark, 50 streams watch selected columns on one wide table. On the April 30, 2026 MacBook Pro run, resqlite wrote to a disjoint column at **23,045 writes/sec** and to an overlapping column at **7,915 writes/sec**. That spread is the signature of column-level dispatch elision: disjoint writes skip stream re-query dispatch instead of paying table-level fanout cost.

The benchmark disables sqlite_async's default throttle so the table reports the measured end-to-end latency for the benchmarked scenario.

## C Layer

The native code lives in `native/resqlite.c` and is compiled alongside the SQLite amalgamation via Dart's native assets build hooks (`hook/build.dart`).

### Key C structures

```c
struct resqlite_db {
    sqlite3* writer;              // Single write connection
    resqlite_stmt_cache writer_cache;
    sqlite3_mutex* writer_mutex;
    resqlite_dirty_set dirty_tables;  // Accumulated by preupdate hook

    resqlite_reader readers[MAX_READERS];  // Read connection pool
    int reader_count;
    sqlite3_mutex* pool_mutex;
};

struct resqlite_reader {
    sqlite3* db;                    // Read-only connection
    resqlite_stmt_cache cache;       // Per-reader statement cache
    resqlite_read_set read_tables;   // Accumulated by authorizer hook
    int in_use;                     // Pool tracking
};
```

### Threading model

All connections are opened with `SQLITE_OPEN_NOMUTEX` — SQLite does no internal locking. Thread safety is managed by resqlite:

- **Reader pool:** `sqlite3_mutex` for pool coordination. Multiple readers execute truly in parallel (SQLite WAL mode supports concurrent reads).
- **Writer:** `sqlite3_mutex` serializes all writes. The persistent writer isolate is the only writer, but the mutex protects against edge cases.
- **Per-query locking:** Lock is acquired in `resqlite_stmt_acquire` and released in `resqlite_stmt_release`. The entire query (prepare → bind → step all rows → reset) runs under one lock, eliminating the ~60k lock/unlock operations that `FULLMUTEX` would produce for a large query.

## FFI Boundary

All FFI declarations use `@ffi.Native` annotations with `@ffi.DefaultAsset('package:resqlite/src/native/resqlite_bindings.dart')` to resolve against the compiled resqlite library.

Key FFI patterns:
- **Native memory for parameters:** `allocateParams()` serializes Dart parameter lists into a flat native `resqlite_param` array, avoiding per-parameter FFI calls
- **Native cell buffer for batch reads:** `resqlite_step_row()` fills a pre-allocated native struct array with all column values. Dart reads via `ByteData` (no per-cell FFI call)
- **Pointer passing for connections:** The C `resqlite_db*` handle address is passed as an `int` to worker isolates. The worker reconstructs the pointer via `Pointer.fromAddress()`. This works because native memory is process-global.

## Data Flow: select()

```
Main: db.select(sql, params)
  │
  ├─ ReaderPool._dispatch() → find available worker
  │
  │  Worker isolate (persistent):
  │    ├─ resqlite_stmt_acquire() → C locks reader mutex, finds idle reader,
  │    │   looks up statement cache, binds params
  │    ├─ Loop: resqlite_step_row() → C fills cell buffer for one row
  │    │   └─ Dart reads cells via ByteData, decodes strings, appends to flat list
  │    ├─ resqlite_stmt_release() → C unlocks reader mutex
  │    └─ Returns [ResultSet, sacrificed] envelope
  │
  ├─ Small result: SendPort.send (worker stays alive)
  │   Large result: Isolate.exit (zero-copy, worker dies, pool respawns)
  │
  └─ Main receives ResultSet
      └─ result[i] creates lightweight Row on demand (3 field assignments)
```

## Data Flow: execute()

```
Main: db.execute(sql, params)
  │
  ├─ Sends ExecuteRequest to writer isolate via SendPort
  │
  │  Writer isolate:
  │    ├─ resqlite_execute() → C locks writer mutex, looks up cached stmt,
  │    │   binds params, steps, reads affected rows + last insert ID
  │    ├─ Reads dirty table dependencies from the native writer
  │    │   → tables plus precise columns when available
  │    └─ Sends ExecuteResponse(result, modifications) back via SendPort
  │
  ├─ Main receives response
  │   ├─ Returns WriteResult to caller
  │   └─ streamEngine.onDependencyChanges()
  │       → table/column intersection against active streams → re-queries
  │
  └─ Stream invalidation (if any):
      └─ Reader pool → select() → emit to subscribers
```

## Data Flow: stream()

```
Main: db.stream(sql, params)
  │
  ├─ StreamEngine checks for existing entry with same key
  │   ├─ If exists: return new subscriber seeded with cached result
  │   └─ If not: create new stream ↓
  │
  ├─ pool.selectWithDeps(sql, params)
  │   └─ Same as select() but also reads authorizer-captured table/column deps
  │
  ├─ Register in StreamEngine with table/column dependencies
  │
  ├─ Push initial results to all subscribers
  │
  └─ On subsequent writes:
      ├─ onDependencyChanges() finds table/column intersections
      ├─ _reQuery() → pool.select() on reader pool
      ├─ Generation check: discard if stale
      └─ _emitResult() → hash check → push to all subscriber controllers
```

## File Layout

```
lib/src/
├── database.dart          — public API (Database, Transaction), subsystem init
├── reader_pool.dart       — pool management (dispatch, slots, lifecycle)
├── read_worker.dart       — read worker entrypoint + query execution + FFI
├── write_worker.dart      — write worker entrypoint + request/response types + FFI
├── stream_engine.dart     — reactive query lifecycle (StreamEngine, StreamEntry)
├── row.dart               — ResultSet, Row, RowSchema
├── exceptions.dart        — exception hierarchy
└── native/
    └── resqlite_bindings.dart — C FFI bindings (connection, write, params)

native/
├── resqlite.c              — C implementation (pool, cache, serialization)
└── resqlite.h              — C API declarations
```

## Related Documents

- **[Experiment posts](../../experiments/)** — individual experiment logs with benchmark numbers and reasoning
- **[Benchmark dashboard](../benchmarks/)** — generated charts for current results, history, devices, and workload comparisons
- **[API docs](../api/resqlite/resqlite-library.html)** — generated Dart API reference
