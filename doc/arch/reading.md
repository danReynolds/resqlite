# Reading: select() and selectBytes()

## Overview

Reads are resqlite's core strength. Two APIs serve different use cases:

- **`select(sql, params)`** → `Future<List<Map<String, Object?>>>` — standard row access
- **`selectBytes(sql, params)`** → `Future<Uint8List>` — JSON bytes for HTTP responses

Both use the same architecture: a **persistent reader pool** of worker isolates that dispatch queries to the C connection pool. Small results return via SendPort (fast round-trip). Large results trigger Isolate.exit for zero-copy transfer — the pool auto-respawns the worker.

## Architecture

```
select()/selectBytes()
  └─ ReaderPool._dispatch() → find available worker
      └─ Worker Isolate (persistent)
          ├─ resqlite_stmt_acquire() → acquires idle reader from C pool
          ├─ Query execution (different for select vs selectBytes)
          ├─ resqlite_stmt_release() → returns reader to pool
          └─ SendPort.send or Isolate.exit (based on result size)
```

## Reader Pool

The reader pool (in `reader_pool.dart`) manages a fleet of persistent worker isolates. Each worker handles one query at a time.

**Dispatch:** Round-robin with busy tracking. A worker is "available" if it's alive, has a SendPort, and isn't currently processing a query. If all workers are busy, callers wait on a shared `Completer` that fires when any worker becomes free.

**Hybrid transmission:** After executing a query, the worker decides based on result size:
- Below threshold (6000 cells): `SendPort.send` — copies the result but worker stays alive for the next query
- Above threshold: `Isolate.exit` — zero-copy transfer but worker dies. Pool detects the death and spawns a replacement.

The sacrifice threshold was tuned empirically (see Experiment 019). At 1000 rows × 6 cols, pool and one-off are tied. Above that, zero-copy wins.

**Sacrifice safety:** The worker wraps every reply as `[result, sacrificed]`. The pool checks this flag — if the worker sacrificed, the slot stays unavailable until the replacement finishes spawning. This prevents a race where callers claim a slot between the replyPort handler (which fires first) and the exitPort handler (which fires later).

**Error handling:** If a query throws (bad SQL, connection error), the worker catches the exception and sends it back via a 3-element error envelope `[message, false, true]`. The pool completes the caller's future with an error. The worker stays alive for the next query.

**Parallel spawn:** Workers are spawned concurrently via `Future.wait` during `Database.open`, reducing startup time from N × spawn_time to max(spawn_time).

## select(): The Maps Path

### The flat list + lazy ResultSet

This was the most impactful design choice. See [Experiment 008](../../experiments/008-flat-list-lazy-resultset.md).

Instead of building `LinkedHashMap` per row (~8-10 internal objects each), we store all values in a single flat `List<Object?>`:

```
values = [row0_col0, row0_col1, ..., row0_colN, row1_col0, ...]
```

`ResultSet` creates lightweight `Row` objects **lazily on main** when `result[i]` is accessed. Each `Row` implements `Map<String, Object?>` via `MapMixin`, looking up column indices from a shared `RowSchema`.

Why this matters: `Isolate.exit()` validates every Dart heap object in the transfer graph. With `LinkedHashMap`, 20,000 rows created ~200,000 internal objects. With our flat list approach, the structural objects drop to ~3 (ResultSet + RowSchema + the values List). The actual value objects (strings, ints, doubles) are the same either way, but eliminating the map internals cut the validation time dramatically.

`Row` creation on main is trivial: 3 field assignments (list ref, schema ref, offset int). No decoding, no FFI, no `utf8.decode` — the values are already fully-materialized Dart objects sitting in the flat list.

### Batch FFI: resqlite_step_row

See [Experiment 009](../../experiments/009-batch-ffi-step-row.md).

Instead of ~16 individual FFI calls per row (step + column_type × N + column_value × N + column_bytes × N), we make one C call per row:

```c
int resqlite_step_row(sqlite3_stmt* stmt, int col_count, resqlite_cell* cells);
```

C steps the row and fills a pre-allocated native struct array with all column types and values. Dart reads from this buffer via `ByteData` — no FFI call per cell.

The cells buffer is allocated once (native memory) and reused across all rows. Dart reads integers and doubles directly via `ByteData.getInt64/getFloat64`. Text values require `utf8.decode` from a native pointer, which is the unavoidable cost for creating Dart `String` objects.

### Connection pool

The C layer maintains N read-only `sqlite3*` connections (default matching Dart pool size), each with its own prepared statement LRU cache. `resqlite_stmt_acquire()` finds an idle reader (spin-wait via `sqlite3_sleep` if all busy), and `resqlite_stmt_release()` returns it.

This enables true parallel reads — multiple pool workers execute simultaneously on different reader connections. SQLite's WAL mode supports concurrent readers natively.

### NOMUTEX

All connections are opened with `SQLITE_OPEN_NOMUTEX`. See [Experiment 004](../../experiments/004-nomutex-per-query-locking.md).

SQLite's default `FULLMUTEX` wraps every API call in a mutex — ~60,000 lock/unlock operations for a 20,000-row query. Our per-query mutex (lock in `stmt_acquire`, unlock in `stmt_release`) replaces this with 2 operations per query.

## selectBytes(): The C JSON Path

See [Experiment 001](../../experiments/001-c-native-json-serialization.md).

`selectBytes()` takes a completely different path. Instead of building Dart objects, a C function reads SQLite columns and writes JSON directly into a `malloc`'d buffer:

```c
int resqlite_query_bytes(resqlite_db* db, const char* sql, ...);
```

The C function handles: string escaping (scan-then-flush for unescaped spans), integer formatting (hand-rolled `fast_i64_to_str` — avoids `snprintf` format parsing), double formatting, null literals, and array/object structure. The resulting `Uint8List` transfers to main — one object, O(1) validation.

This bypasses all Dart object creation for result data. No `Map`, no `String`, no `Row`. The bytes are ready to hand to shelf/dart_frog.

### When to use which

- **`select()`** when you need to access row data in Dart (UI binding, data processing)
- **`selectBytes()`** when the end consumer wants JSON (HTTP responses, file export, inter-service communication)

## Performance Characteristics

At 5,000 rows (6 columns, mixed types):

| Metric | select() | selectBytes() | sqlite3 | sqlite_async |
|---|---|---|---|---|
| Wall time | 2.25 ms | 3.14 ms | 4.20 ms | 4.10 ms |
| Main-isolate time | 0.49 ms | 0.00 ms | 4.20 ms | 0.83 ms |

## Key Files

- `lib/src/database.dart` — `select()`, `selectBytes()` (delegates to reader pool)
- `lib/src/reader_pool.dart` — `ReaderPool`, `_WorkerSlot`, dispatch, lifecycle
- `lib/src/read_worker.dart` — worker entrypoint, `executeQuery`, `executeQueryBytes`, FFI bindings
- `lib/src/row.dart` — `Row`, `RowSchema`, `ResultSet`
- `lib/src/native/resqlite_bindings.dart` — FFI bindings, parameter allocation
- `native/resqlite.c` — `resqlite_stmt_acquire/release`, `resqlite_step_row`, `resqlite_query_bytes`
