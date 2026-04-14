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
No separate notification channel. Every write response includes the set of dirty tables. The StreamEngine checks these against active stream dependencies and re-queries affected streams through the reader pool.

## Subsystems

### [Reading: select() and selectBytes()](./reading.md)

The read path is where most of the performance engineering lives. Key innovations:
- **Persistent reader pool** with hybrid SendPort/Isolate.exit transmission, busy tracking, and automatic respawn
- **C-level connection pool** with per-connection statement caches and per-query locking (instead of SQLite's per-API-call `FULLMUTEX`)
- **Batch FFI** via `resqlite_step_row()` — one C call per row instead of ~16 individual FFI calls
- **Flat value list with lazy ResultSet** — all values in one `List<Object?>`, `Row` objects created on-demand. Reduces the `Isolate.exit` validation graph from ~200k objects to ~3
- **C-native JSON serialization** for `selectBytes()` — zero Dart objects for result data, scan-then-flush string escaping, hand-rolled integer formatting

### [Writing: execute(), executeBatch(), transaction()](./writing.md)

The write path uses a persistent writer isolate that processes messages sequentially. Key design choices:
- **Persistent isolate** instead of one-off — avoids the closure sendability footgun and enables interactive transactions
- **C batch runner** (`resqlite_run_batch`) for `executeBatch()` — one FFI call for the entire batch, single prepared statement reused
- **Async transaction API** — the callback runs on main (no isolate scope leakage), sends messages to the writer for each operation
- **Preupdate hook** on the writer connection tracks dirty tables, accumulated across transaction scope

### [Streaming: stream()](./streaming.md)

Reactive queries that re-emit when underlying data changes. Key design choices:
- **Authorizer hook** (`sqlite3_set_authorizer`) on all readers captures read dependencies during query execution — no SQL parsing
- **StreamEngine** owns full lifecycle: registration, initial query, dependency tracking, invalidation, re-query, result dedup, subscriber management
- **Per-subscriber buffered controllers** — eliminates broadcast race conditions
- **Per-entry re-query generation** — discards stale out-of-order results from concurrent re-queries
- **Error propagation** — bad SQL or connection errors reach subscribers instead of hanging
- **Deduplication** by `Object.hash(sql, Object.hashAll(params))` — 100 widgets listening to the same query = 1 actual SQLite query per invalidation

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
  │    ├─ resqlite_get_dirty_tables() → reads tables dirtied by preupdate hook
  │    └─ Sends ExecuteResponse(result, dirtyTables) back via SendPort
  │
  ├─ Main receives response
  │   ├─ Returns WriteResult to caller
  │   └─ streamEngine.handleDirtyTables() → checks against active streams → re-queries
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
  │   └─ Same as select() but also reads authorizer-captured read tables
  │
  ├─ Register in StreamEngine with read tables
  │
  ├─ Push initial results to all subscribers
  │
  └─ On subsequent writes:
      ├─ handleDirtyTables() finds intersection with readTables
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

- **[Reading](./reading.md)** — select(), selectBytes(), reader pool, batch FFI, flat list architecture
- **[Writing](./writing.md)** — execute(), executeBatch(), transaction(), writer isolate, C batch runner
- **[Streaming](./streaming.md)** — stream(), authorizer hooks, dependency tracking, invalidation, deduplication
- **[experiments/](../../experiments/)** — Individual experiment logs with benchmarks and reasoning
