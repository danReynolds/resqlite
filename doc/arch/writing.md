# Writing: execute(), executeBatch(), transaction()

## Overview

All writes go through a **persistent writer isolate** — a single long-lived Dart isolate that owns the writer connection and processes messages sequentially. This mirrors SQLite's own model: one writer at a time.

Three write APIs:

- **`execute(sql, params)`** → `Future<WriteResult>` — single write, returns affected rows + last insert ID
- **`executeBatch(sql, paramSets)`** → `Future<void>` — one SQL with many param sets in a transaction
- **`transaction(callback)`** → `Future<T>` — interactive multi-statement transaction with reads

## Why a Persistent Writer Isolate?

We considered three approaches:

1. **One-off `Isolate.run` per write** (like reads) — would give us `Isolate.exit` zero-copy, but writes are typically small (affected rows, last insert ID), so the copy savings are negligible. And transactions can't span multiple one-off isolates.

2. **Run writes on main** — simplest, but any write that triggers index updates or cascading deletes would jank the UI.

3. **Persistent writer isolate** — processes messages sequentially (matching SQLite's single-writer model), holds transaction state across messages, and keeps all write work off main.

We chose option 3. The persistent isolate spawns non-blocking during `Database.open()`. The first write awaits it being ready. If the app never writes, the isolate still spawns but sits idle.

## Writer Isolate Message Protocol

Six message types, each a sealed class in `write_worker.dart`:

| Message | Purpose | Response |
|---|---|---|
| `ExecuteRequest` | Single parameterized write | `ExecuteResponse(WriteResult, dirtyTables)` |
| `QueryRequest` | Read within a transaction | `QueryResponse(rows, dirtyTables)` |
| `BatchRequest` | Batch write | `BatchResponse(dirtyTables)` |
| `BeginRequest` | Start transaction | `true` |
| `CommitRequest` | Commit transaction | `BatchResponse(dirtyTables)` |
| `RollbackRequest` | Rollback transaction | `true` |

Each request carries a `SendPort replyPort` for the response. The writer isolate pattern-matches on the message type and dispatches to the appropriate C function.

### Transaction state

The writer isolate tracks `inTransaction` as a boolean. When true:
- Individual `ExecuteRequest` responses include empty dirty tables (accumulated until commit)
- `CommitRequest` reads and returns the full dirty table set
- `RollbackRequest` clears dirty tables without returning them (rolled-back changes don't count)

## execute()

```dart
final result = await db.execute('INSERT INTO users(name) VALUES (?)', ['alice']);
print(result.affectedRows);  // 1
print(result.lastInsertId);  // 42
```

The C function `resqlite_execute()` prepares (or retrieves from cache), binds, steps, and reads `sqlite3_changes()` + `sqlite3_last_insert_rowid()`. The result struct is 16 bytes (int + long long), read via `ByteData` on the writer isolate.

For DDL and non-parameterized writes (e.g., `CREATE TABLE`), we use the simpler `resqlite_exec()` which calls `sqlite3_exec()` directly.

## executeBatch()

```dart
await db.executeBatch(
  'INSERT INTO items(name, value) VALUES (?, ?)',
  [['alice', 1], ['bob', 2], ['charlie', 3]],
);
```

The C function `resqlite_run_batch()` handles the entire batch in one FFI call:

1. Lock writer mutex
2. `BEGIN` transaction
3. Prepare statement once (or retrieve from cache)
4. Loop: bind params → step → reset (for each param set)
5. `COMMIT`
6. Unlock

The statement is prepared once and reused with `sqlite3_reset()` + `sqlite3_clear_bindings()` between iterations. This is significantly faster than the Dart-loop approach because all bind/step/reset cycles happen in C with no FFI boundary crossings between rows.

On error, the batch `ROLLBACK`s automatically. The Dart side receives a `StateError`.

### Parameter serialization

Parameters are serialized into a flat native array of `resqlite_param` structs (24 bytes each). For a batch of 1000 rows × 2 params, that's one contiguous 48KB allocation. The C function indexes into this array: `param_sets[i * param_count + j]`.

## transaction()

```dart
final result = await db.transaction((tx) async {
  await tx.execute('INSERT INTO users(name) VALUES (?)', ['alice']);
  final rows = await tx.select('SELECT COUNT(*) as cnt FROM users');
  if (rows[0]['cnt'] as int > 100) {
    await tx.execute('DELETE FROM users WHERE old = 1');
  }
  return rows[0]['cnt'];
});
```

### Design: async on main, not a closure on the worker

We deliberately chose an async API where the callback runs on main and sends messages to the writer isolate. The alternative — running a synchronous closure on the worker via `Isolate.run` — would require the closure to only capture sendable values. This is a non-obvious constraint that causes confusing runtime errors when the closure captures a `StreamController`, a `Database` reference, or any other non-sendable object.

With the async approach, the callback is a normal Dart function on main. `tx.execute()` and `tx.select()` send messages to the writer isolate and await responses. No closure sendability constraints.

### Reads within transactions

`tx.select()` sends a `QueryRequest` to the writer isolate, which executes the query on the **writer connection** (not the reader pool). This is necessary because SQLite's uncommitted writes are only visible on the connection that made them. The reader pool's connections wouldn't see data inserted earlier in the same transaction.

The query result is built on the writer isolate (same per-cell FFI approach as the reader path) and sent back via `SendPort.send()` (deep copy). This is the one place where we don't get `Isolate.exit` zero-copy transfer. But transaction reads are typically small (checking a count, reading an ID, verifying a constraint), so the copy cost is negligible.

### Error handling

If any operation within the callback throws, `Database.transaction()` catches the error, sends a `RollbackRequest`, and rethrows. The writer isolate rolls back and clears dirty tables. The caller sees the original error.

## Dirty Table Tracking

Every write response includes the set of tables modified by the operation. This is captured by the `sqlite3_preupdate_hook` installed on the writer connection in C.

The preupdate hook fires per-row during INSERT/UPDATE/DELETE and records the table name in a deduplicated set (`resqlite_dirty_set`). After the write completes, Dart reads the set via `resqlite_get_dirty_tables()` and clears it.

For transactions: dirty tables accumulate across all writes within the transaction. Individual `ExecuteRequest` responses return empty dirty tables. The `CommitRequest` response returns the accumulated set. This ensures stream invalidation happens once on commit, not per-statement.

For rolled-back transactions: dirty tables are cleared without returning them. Rolled-back writes don't trigger stream invalidation.

## Performance Characteristics

Single inserts (100 sequential):

| Library | Wall time |
|---|---|
| resqlite | **1.73 ms** |
| sqlite3 | 5.19 ms |
| sqlite_async | 4.10 ms |

Batch insert (1,000 rows):

| Library | Wall time |
|---|---|
| resqlite | **0.48 ms** |
| sqlite3 (manual) | 0.57 ms |
| sqlite_async | 0.63 ms |

Interactive transaction (insert + select + conditional delete):

| Library | Wall time |
|---|---|
| resqlite | **0.06 ms** |
| sqlite_async | 0.12 ms |

## Key Files

- `lib/src/database.dart` — `execute()`, `executeBatch()`, `transaction()`, `Transaction` class
- `lib/src/write_worker.dart` — Writer worker entrypoint, message handling, FFI bindings
- `lib/src/native/resqlite_bindings.dart` — `executeWrite()`, `executeBatchWrite()`, `getDirtyTables()`
- `native/resqlite.c` — `resqlite_execute()`, `resqlite_run_batch()`, `resqlite_get_dirty_tables()`, preupdate hook
