# How resqlite Makes Queries Reactive

Most database libraries give you a one-shot query: ask for data, get data, done. resqlite's `stream()` API turns any query into a live data source — it emits results immediately and then re-emits whenever the underlying data changes. No polling, no manual invalidation, no table lists to maintain.

## Overview

```dart
final stream = db.stream('SELECT * FROM users WHERE active = ?', [1]);
stream.listen((rows) {
  // Fires immediately with current results.
  // Re-fires whenever the users table changes.
  setState(() => users = rows);
});
```

`stream()` returns a reactive query that emits results and re-emits whenever the underlying data changes. It combines three mechanisms:

1. **Authorizer hook** on readers — captures which tables a query reads
2. **Preupdate hook** on writer — captures which tables a write modifies
3. **StreamEngine** on main — matches dirty tables against stream dependencies, manages lifecycle

## How Dependencies Are Captured

SQLite's [authorizer callback](https://www.sqlite.org/c3ref/set_authorizer.html) fires during query preparation and execution. For action code `SQLITE_READ` (20), it receives the table name being read. We install this on every reader connection:

```c
// In resqlite_open(), for each reader:
sqlite3_set_authorizer(rdb, authorizer_callback, &reader->read_tables);
```

The callback appends table names to a per-reader `resqlite_read_set` (deduplicated). After a query completes, Dart reads the set via `resqlite_get_read_tables()` and clears it.

### Why the authorizer instead of SQL parsing

The authorizer handles cases that SQL parsing cannot:
- **JOINs:** `SELECT * FROM users JOIN posts ON ...` → reads both `users` and `posts`
- **Subqueries:** `SELECT * FROM users WHERE id IN (SELECT user_id FROM posts)` → reads both
- **Views:** `SELECT * FROM active_users` where `active_users` is a view on `users` → reads `users`
- **CTEs:** Common table expressions that reference multiple tables
- **Triggers:** If a read triggers a trigger that reads another table
- **Attached databases:** Tables from attached database files

SQLite itself tells us what it's reading. No parsing heuristics needed.

### Performance impact

The authorizer fires per-table-access during query planning/execution — typically 1-5 calls per query. Each call is a C function that does a `strcmp` for deduplication and a `strdup` for new entries. Benchmarks showed **no measurable performance regression** from having the authorizer installed on all readers (see `benchmark/results/2026-04-06T22-40-34-after-authorizer-hooks.md`).

## How Dirty Tables Are Tracked

The writer connection has a `sqlite3_preupdate_hook` installed (see [Writing](./writing.md)). It fires per-row during INSERT/UPDATE/DELETE, recording the affected table name. The dirty table set is returned with every write response to main.

For transactions, dirty tables accumulate until commit. Rolled-back transactions clear the set without notifying.

## StreamEngine

The `StreamEngine` (in `stream_engine.dart`) owns the full reactive query lifecycle. It receives a reference to the reader pool and manages all active streams.

Internally it maintains:
- `_entries` — `Map<int, StreamEntry>` keyed by `Object.hash(sql, Object.hashAll(params))`
- `_tableToKeys` — inverted index from table name to stream keys, for O(dirtyTables) invalidation
- `_writeGeneration` — monotonic counter to detect writes during initial query setup

Each `StreamEntry` holds:
- `sql` and `params` — for re-querying
- `readTables` — `Set<String>` of tables this query depends on
- `lastResult` — cached most recent result for late joiners
- `lastResultHash` — hash for result-change detection (suppresses no-op re-emissions)
- `reQueryGeneration` — per-entry counter to discard stale out-of-order re-query results
- `subscribers` — list of per-subscriber buffered `StreamController`s

### Per-subscriber buffered controllers

Each subscriber gets its own non-broadcast `StreamController` that buffers events. This eliminates the race condition where broadcast controllers silently drop events when no listener is attached during async gaps (e.g., between `yield` and `listen`).

When a new subscriber joins an existing stream, it receives the cached `lastResult` immediately:

```dart
Stream<List<Map<String, Object?>>> _subscribe(StreamEntry entry) {
  final controller = StreamController<List<Map<String, Object?>>>();
  entry.subscribers.add(controller);
  // Seed with cached result.
  if (entry.lastResult != null) controller.add(entry.lastResult!);
  // Clean up entry when last subscriber cancels.
  controller.onCancel = () { ... };
  return controller.stream;
}
```

### Deduplication

Multiple calls to `db.stream()` with the same SQL and params share a single `StreamEntry`. This means 100 widgets listening to the same query produce 1 SQLite query per invalidation, not 100.

### Invalidation

When a write completes and returns dirty tables, `database.dart` calls `streamEngine.handleDirtyTables()`:

```dart
void handleDirtyTables(List<String> dirtyTables) {
  _writeGeneration++;
  // Look up affected stream keys via inverted index.
  final affected = <int>{};
  for (final table in dirtyTables) {
    final keys = _tableToKeys[table];
    if (keys != null) affected.addAll(keys);
  }
  // Dispatch re-queries, bumping per-entry generation to discard stale results.
  for (final key in affected) {
    final entry = _entries[key];
    entry.reQueryGeneration++;
    unawaited(_reQuery(entry, entry.reQueryGeneration));
  }
}
```

`_reQuery()` runs the query on the reader pool. When the result arrives, it checks the entry's `reQueryGeneration` — if a newer re-query was dispatched while this one was in-flight, the result is stale and discarded. This prevents out-of-order delivery when rapid writes fire multiple concurrent re-queries.

Result-change detection via `_hashResult()` suppresses duplicate emissions when a write dirtied a table but didn't change the query's actual results (e.g., `UPDATE items SET value = value`).

### Error handling

If the initial query fails (bad SQL, connection error), the error is propagated to all subscribers via `controller.addError()` and the entry is cleaned up. Subscribers receive the error instead of hanging forever.

## Lifecycle

```
db.stream(sql, params)
  │
  ├─ Hash key = Object.hash(sql, Object.hashAll(params))
  │
  ├─ StreamEngine has existing entry?
  │   ├─ Yes: return new subscriber seeded with cached result
  │   └─ No: create new stream ↓
  │
  ├─ pool.selectWithDeps(sql, params)
  │   ├─ Executes query on a reader pool worker
  │   └─ Also reads authorizer-captured read tables
  │
  ├─ Register in StreamEngine with read tables
  │
  ├─ Push initial results to all subscribers
  │
  ├─ If _writeGeneration changed during query → immediate re-query
  │
  └─ Stream stays active until last subscriber cancels
      └─ On cancel: remove from engine if no subscribers remain
```

## Design Decisions

### Why not poll?

Polling (`Timer.periodic` + re-query) adds latency (up to the poll interval) and wastes CPU when nothing changed. Our approach re-queries immediately on write completion — sub-millisecond latency.

### Why not a separate watcher isolate?

We initially considered a persistent "watcher" isolate that would listen for commits and notify main. But since every write already goes through the writer isolate and returns dirty tables in the response, the notification is free — it piggybacks on the write result. No extra isolate needed.

### Why re-query through the reader pool instead of the writer?

Stream re-queries are reads. They use the reader pool for parallelism and the same hybrid SendPort/Isolate.exit transfer as `select()`. Routing them through the writer would serialize them and block writes.

### Why per-entry re-query generation?

Rapid writes to the same table fire multiple concurrent re-queries for the same stream. Each runs on a different pool worker and sees a different WAL snapshot. Without generation tracking, an older snapshot's result could arrive after a newer one, causing the stream to emit stale data. The per-entry generation counter ensures only the latest result is accepted.

### Throttling

resqlite currently re-queries immediately on every write. sqlite_async uses a 30ms default throttle to batch rapid writes. For resqlite, throttling is left as a future enhancement — the unthrottled approach gives the lowest possible latency. Apps that need throttling can debounce on the stream consumer side.

## Performance Characteristics

| Metric | resqlite | sqlite_async |
|---|---|---|
| Initial emission | **0.01 ms** | 0.64 ms |
| Invalidation latency | **0.36 ms** | 32.61 ms* |

*sqlite_async has a 30ms default throttle. The comparison shows raw latency, not typical throttled behavior.

## Key Files

- `lib/src/database.dart` — `stream()` (delegates to StreamEngine)
- `lib/src/stream_engine.dart` — `StreamEngine`, `StreamEntry`, lifecycle, invalidation, re-query
- `lib/src/reader_pool.dart` — `selectWithDeps()` (initial query with dependency capture)
- `lib/src/native/resqlite_bindings.dart` — `getReadTables()`, `resqliteGetReadTables()`
- `native/resqlite.c` — `authorizer_callback()`, `resqlite_get_read_tables()`
