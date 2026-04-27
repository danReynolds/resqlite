# 40 Experiments Later: How We Built a Blazing Fast SQLite Library for Flutter

Every SQLite library in the Dart ecosystem has the same bottleneck: getting data from SQLite's C engine to your Dart code without blocking the UI. Over 40 experiments, we ended up building something optimized for the metric that matters most in Flutter: main-isolate time. Here's the story of how we got there — including the dead ends.

**The bottom line:** resqlite reads 1,000 rows in 0.40ms (1.8x faster than the next best library), writes in 1.78ms (2.1x faster), and keeps main-isolate time under 1ms for 10,000-row queries. Point query throughput is 107K queries/sec. Every optimization is documented — including the ones that failed.

## The Problem We Were Trying to Solve

We were building a Flutter app backed by [SQLite](https://sqlite.org/) — the embedded database that runs on basically everything. The [sqlite3](https://pub.dev/packages/sqlite3) package worked, but we were hitting two problems:

1. **Jank.** Loading a screen with a few thousand rows caused visible frame drops. The sqlite3 package runs synchronously on whatever thread you call it from — and in Flutter, that's the main isolate, the same thread responsible for rendering your UI at 60fps. A query that takes 4ms blocks 4ms of frame time.

2. **No reactivity.** We wanted live-updating UI — when a write modifies the database, every widget showing that data should update automatically. sqlite3 gives you one-shot queries. We were manually invalidating, polling, and managing state ourselves.

We decided to build something from scratch. Could we make a SQLite library with zero main-isolate jank and built-in reactive queries?

If you're not familiar with Dart: your application runs on the "main isolate" — a single thread that handles UI rendering, user input, and your application logic. Think of it like JavaScript's main thread, but stricter. [Isolates](https://dart.dev/language/isolates) are Dart's concurrency primitive: independent threads with their own memory that communicate by passing messages (no shared memory, no locks). [FFI](https://dart.dev/interop/c-interop) (Foreign Function Interface) is how Dart calls C code — each call has a small overhead. Most SQLite libraries use a background isolate to run queries, then send results back to the main isolate.

The data path with the sqlite3 package looked like this:

```
SQLite C engine
  → sqlite3 package reads each cell via FFI (30,000 FFI calls for 5k × 6 columns)
  → Dart Map objects created (on the main isolate — sqlite3 is synchronous)
  → All 5,000 maps available immediately (no transfer needed, but main is blocked)
```

With an async library, you move the query to a background isolate, but now you need to transfer the result back:

```
Worker isolate:
  → sqlite3 reads each cell via FFI → Dart Map objects
  → SendPort.send() deep-copies every map to main isolate
Main isolate:
  → Receives deep-copied maps (allocation + validation cost)
```

Either way, the main isolate was doing real work — either running the query directly, or receiving and validating thousands of Dart objects transferred from a worker.

We set ourselves a principle: **minimize main-isolate work above all else.** In Flutter, the main isolate runs your UI at 60fps — that's a 16ms budget per frame. Every millisecond spent on database work there is a millisecond that could cause dropped frames, stuttery scrolling, or unresponsive touch handling. Total wall time matters, but main-isolate time is what users feel.

## Attempt 1: Move the Query Off Main

The first idea was simple: run the query on a background isolate and send the result back. Dart's `Isolate.run()` uses `Isolate.exit()` under the hood, which transfers the return value to the receiving isolate **without copying**. This is different from `SendPort.send()`, which deep-copies everything. The trade-off: `Isolate.exit()` kills the sending isolate, so it only works for one-off workers.

```dart
final rows = await Isolate.run(() {
  final db = sqlite3.open('app.db');
  return db.select('SELECT * FROM items');
});
```

We measured wall time and main-isolate time separately:

| Path (5,000 rows) | Wall | Main |
|---|---|---|
| Synchronous on main | 15.30 ms | **8.64 ms** |
| `Isolate.run()` → `List<Map>` | 15.15 ms | **7.84 ms** |
| `Isolate.run()` → `Uint8List` (bytes) | 16.03 ms | **0.00 ms** |

Returning maps: still ~8ms on main. The maps arrived via `Isolate.exit()` without copying, but the Dart VM still needed to walk and validate every object in the graph before accepting it. 5,000 rows × 6 columns means ~5,000 `LinkedHashMap` instances, each with ~8-10 internal objects (hash buckets, linked list nodes), plus ~60,000 key and value objects. Over 100,000 Dart heap objects to validate. That took nearly as long as building them.

But returning raw bytes (`Uint8List`) — a single contiguous block of memory — cost 0.00ms on main. One object, instant validation.

**Lesson:** The cost of `Isolate.exit()` isn't the transfer — it's the validation walk. The fewer Dart objects in the result, the cheaper it is. This insight drove everything that followed.

## Attempt 2: A New Library, Built on Raw FFI

We started resqlite from scratch. No dependency on the existing `sqlite3` Dart package. Raw FFI bindings to SQLite's C API — Dart can call C functions directly with ~100ns overhead per call. We bundled the SQLite amalgamation (the entire database engine as a single C file) and compiled it as part of our build.

The goal was to control the entire data path from SQLite's C engine to Dart objects, looking for places to reduce the object count.

Our first C function packed results into a compact binary buffer, then decoded it to maps in Dart. This was only ~7% faster than the `sqlite3` package's per-cell FFI approach. Disappointing. The Dart object allocation cost (creating `Map`, `String`, etc.) was the floor that everyone hits regardless of how they read the data. We needed to rethink the data structure, not just the transport.

While exploring the C layer, we also wrote a function that serializes query results directly to JSON bytes in C — zero Dart objects involved. At 5,000 rows, this was 3.5x faster than Dart-side `jsonEncode`. Not useful for building Flutter widgets (you need Dart maps for that), but we shipped it as `selectBytes()` for HTTP server use cases where you want raw JSON. The real lesson was confirming: object count is what matters, not the serialization format.

## Attempt 3: C-Level Connection That Outlives Isolates

Each `Isolate.run()` call spawned a fresh isolate and opened a new database connection. The connection setup (open file, configure WAL mode, set pragmas) cost ~0.5-1ms per query.

We moved the `sqlite3*` connection handle and a prepared statement LRU cache into a C struct. Dart isolates call into C using the pointer address — since native memory is process-global (not isolate-scoped), the same C connection is accessible from any isolate. The connection and its cached statements outlive any individual Dart isolate.

We also discovered that SQLite's default threading mode (`SQLITE_OPEN_FULLMUTEX`) wraps every single API call in a mutex — every `sqlite3_step()`, every `sqlite3_column_text()`, every `sqlite3_column_int64()`. For 20,000 rows × 6 columns, that's ~60,000 lock/unlock operations. We switched to `SQLITE_OPEN_NOMUTEX` with our own `pthread_mutex` locked once per query — one lock for the entire stepping loop instead of 60,000.

Wall time dropped from 4.92ms to 4.21ms at 5,000 rows. Incremental, but the architecture was now clean.

## The Scaling Cliff

Everything looked good up to ~5,000 rows. Then we ran the scaling benchmark and saw this:

| Rows | resqlite | sqlite3 |
|---|---|---|
| 5,000 | 4.82 ms | 4.43 ms |
| 10,000 | 12.85 ms | 8.65 ms |
| 20,000 | 26.81 ms | 22.37 ms |

The gap grew with result size. Something was scaling worse than linear.

We wrote a breakdown benchmark that timed each phase independently:

| Phase (20,000 rows) | Cost | % |
|---|---|---|
| Isolate spawn | 0.09 ms | 0.4% |
| SQLite step | 2.10 ms | 9.5% |
| Map building | 11.50 ms | 52.0% |
| **Isolate.exit validation** | **8.44 ms** | **38.1%** |

Almost 40% of the time was in `Isolate.exit()` — the thing we'd assumed was free.

## Down the Rabbit Hole: What Does "Zero-Copy" Actually Mean?

We dug into the Dart VM source code. In `runtime/lib/isolate.cc`, before `Isolate.exit()` transfers any message, a `MessageValidator` walks the **entire object graph** to verify every object is safe to transfer between isolates. Some types can't cross isolate boundaries (open ports, native finalizers, closures over mutable state), so the VM must check. This walk is O(n) in the number of Dart heap objects.

The [documentation](https://api.dart.dev/dart-isolate/Isolate/exit.html) says the receiving isolate gets the message "in most cases in constant time." That's technically true — the *transfer* (pointer reassignment) is constant. But the *validation pass* that precedes it is linear. For one `Uint8List`: one object to check, instant. For 20,000 maps with 120,000+ strings: every single one gets visited.

This explained why `selectBytes()` had zero transfer overhead while `select()` had a cost that grew with row count. And it meant the solution had to involve reducing the number of objects, not just their size.

## Dead End: Binary Codec with TransferableTypedData

Before we understood the validation cost, we tried encoding maps into a binary `Uint8List` using [`TransferableTypedData`](https://api.dart.dev/dart-isolate/TransferableTypedData-class.html) — a special Dart type that transfers zero-copy over regular `SendPort.send()` without killing the sending isolate. This would let us keep persistent worker pools.

**Result: 5-7x slower** than the VM's native `SendPort.send()`. The Dart-level encode/decode overhead (iterating values, writing bytes to a `BytesBuilder`, reading them back) was far worse than the VM's optimized C++ object serializer. We couldn't beat the VM at its own game in Dart.

## Dead End: String Interning

We hypothesized that the `MessageValidator` might skip already-visited objects. If all 20,000 rows shared the same `String` instances for repeated values (like `"category_3"` appearing 2,000 times), the validator would visit each unique string once.

We benchmarked interning: `intern.putIfAbsent(decoded, () => decoded)` for every string value. For columns with few unique values (category, dates), interning saved object count. But for columns with unique values per row (names, descriptions), the intern table hash lookup added overhead with no deduplication. You usually can't predict data cardinality at query time.

Net result: **slower overall.**

## A Tempting Path: Lazy Byte-Backed Maps

Knowing that `Uint8List` transfers in O(1) but maps transfer in O(n), we tried a hybrid. The worker packed results into a `Uint8List` using our C binary format (O(1) transfer via `Isolate.exit`). The main isolate wrapped it in a `ByteBackedResultSet` — a `List<Map<String, Object?>>` where each map decoded values lazily from the byte buffer only when the caller accessed them.

At 20,000 rows:

| Path | Wall | Main |
|---|---|---|
| Direct maps + Isolate.exit | 27.45 ms | **2.12 ms** |
| ByteBackedResultSet (full iteration) | **11.92 ms** | 7.29 ms |
| ByteBackedResultSet (20 rows only) | **4.50 ms** | **0.01 ms** |

For partial access — like a Flutter `ListView` rendering 20 visible items from a 20,000-row result — this was spectacular. 4.50ms wall, 0.01ms main. The lazy decode meant you only paid for what you rendered.

But for full iteration, the decode happened on the main isolate: **7.29ms of main-isolate work**. Each `row['name']` access triggered `utf8.decode` on the byte buffer, on main, at access time. Our direct maps approach put only 2.12ms on main because the maps arrived pre-built — all the decode work happened on the worker.

We had to choose: better wall time (byte-backed), or less main-isolate jank (direct maps)? Given our guiding principle, we chose direct maps. A library can't predict how callers will access their data, but it can guarantee that the main isolate doesn't do heavy lifting. The byte-backed approach optimized for the wrong metric.

## The Breakthrough: What If We Just Used Fewer Objects?

We'd been optimizing the C pipeline, the isolate transfer, the mutex strategy. But the breakdown showed that `Isolate.exit` validation was dominated by sheer object count. So we asked: how many objects does a Dart `LinkedHashMap` actually create internally?

When you write `<String, Object?>{'id': 1, 'name': 'alice', ...}` in Dart, you get a `LinkedHashMap` — the default `Map` implementation. It maintains a hash table for O(1) lookups and a linked list for insertion-order iteration. Under the hood, that means: the map object itself, an internal bucket array, linked list entry nodes, and key-value pair storage. For a 6-column row: roughly **8-10 internal heap objects per map**. For 20,000 rows: **160,000-200,000 internal objects** just for the map structure — before counting the actual values (strings, ints, doubles).

But database result rows are:
- **Immutable** — never modified after construction
- **Fixed schema** — all rows have identical keys, known upfront
- **Small** — typically 2-20 columns
- **Read-only** — `row['name']` lookups, iteration, serialization

None of these properties need a hash table. We were paying for `LinkedHashMap` machinery that our use case never exercises.

We replaced it with a single flat `List<Object?>` holding ALL rows' values contiguously:

```
values = [row0_col0, row0_col1, ..., row0_colN, row1_col0, row1_col1, ...]
```

A `Row` class implements Dart's `Map<String, Object?>` interface via `MapMixin`. Looking up `row['name']` does one hash lookup in a shared column-index map (6 entries, created once for the entire result set), then a direct index into the flat list. No per-row hash table, no per-row bucket array, no per-row linked list.

Then we made `Row` objects lazy — the `ResultSet` creates them on-demand when the caller accesses `result[i]`, not on the worker. Creating a `Row` is just assigning 3 fields (list reference, schema reference, offset integer) — nanoseconds. Critically, the actual values are already fully-decoded Dart objects sitting in the flat list, built on the worker. This isn't the expensive kind of lazy (byte-buffer decode on main). It's the trivial kind (object construction on main).

Now `Isolate.exit` transfers:
- 1 `ResultSet` (3 fields)
- 1 `RowSchema` (column names + index map)
- 1 `List<Object?>` (the flat value list)
- The actual value objects (strings, ints, doubles)

Zero `Row` objects. Zero `Map` internals. At 20,000 rows, the structural object count dropped from hundreds of thousands to **3**.

| Implementation (20k rows) | Wall | Main | vs sqlite3 |
|---|---|---|---|
| LinkedHashMap + Isolate.exit | 24.95 ms | 1.57 ms | +12% slower |
| Flat list + eager Row wrappers | 19.39 ms | 1.74 ms | -12% faster |
| **Flat list + lazy ResultSet** | **18.03 ms** | **2.52 ms** | **-13% faster** |

And main-isolate time stayed well under a frame budget at every size:

| Rows | resqlite main | sqlite3 main | sqlite_async main |
|---|---|---|---|
| 1,000 | **0.10 ms** | 0.79 ms | 0.17 ms |
| 5,000 | **0.47 ms** | 3.90 ms | 0.87 ms |
| 20,000 | **2.52 ms** | 20.65 ms | — |

At 5,000 rows — a large query for most Flutter apps — resqlite puts 0.47ms on main. The `sqlite3` package puts 3.90ms (it runs everything synchronously on the calling isolate). `sqlite_async` (PowerSync's library, which uses a Dart-side worker pool) puts 0.87ms.

## Connection Pool: Winning on Concurrency

One weakness remained. Each query spawned its own `Isolate.run`, and they all funneled into a single C connection behind a mutex. Concurrent reads serialized — query 2 waited for query 1 to finish.

SQLite in [WAL mode](https://sqlite.org/wal.html) (Write-Ahead Logging) supports multiple simultaneous readers. `sqlite_async` exploits this with a Dart-side connection pool — multiple worker isolates, each with its own connection.

We added a C-level reader pool — multiple `sqlite3*` handles opened in read-only mode, each with its own statement cache, coordinated by a `pthread_cond_t` (POSIX condition variable). When a query arrives, `resqlite_stmt_acquire()` grabs an idle reader; when it finishes, `resqlite_stmt_release()` returns it. Multiple Dart isolates can query truly in parallel, each on its own reader connection.

The key advantage over a Dart-side pool: thread synchronization in C (`pthread_mutex`, `pthread_cond_signal`) takes nanoseconds. Dart isolate coordination (sending messages between isolates, scheduling microtasks) takes microseconds.

| Concurrency | Before pool | After pool | sqlite_async |
|---|---|---|---|
| 4 parallel | 2.83 ms | **0.70 ms** | 0.80 ms |
| 8 parallel | 5.64 ms | **1.29 ms** | 1.58 ms |

## Where We Stood After Act One

Two read methods. Clean API. Competitive with every library in the ecosystem.

```dart
// Maps — flat-list Row wrappers, Isolate.exit zero-copy, near-zero main jank
final users = await db.select('SELECT * FROM users WHERE active = ?', [1]);
for (final user in users) {
  print('${user['name']} is ${user['age']}');
}

// Bytes — C-native JSON, zero Dart objects, zero main-isolate work
final bytes = await db.selectBytes('SELECT * FROM users');
return Response(200, body: bytes, headers: {'Content-Type': 'application/json'});
```

The caller sees standard Dart types — `List<Map<String, Object?>>` for maps, `Uint8List` for bytes. The `Row` type implements `Map` via `MapMixin`, so `row['name']`, `row.keys`, `row.forEach`, and `jsonEncode(row)` all work exactly as expected. The flat list, lazy construction, C connection pool, and `Isolate.exit` transfer are all invisible to the consumer.

### Wall time: maps

| Rows | resqlite | sqlite3 | sqlite_async |
|---|---|---|---|
| 1,000 | **0.59 ms** | 0.77 ms | 0.57 ms |
| 5,000 | **2.96 ms** | 3.83 ms | 2.83 ms |
| 20,000 | **18.03 ms** | 20.65 ms | 21.26 ms |

### Wall time: bytes (JSON for HTTP responses)

| Rows | resqlite | sqlite3 + jsonEncode | sqlite_async + jsonEncode |
|---|---|---|---|
| 5,000 | **3.80 ms** | 15.23 ms | 15.09 ms |
| 20,000 | **17.34 ms** | 62.14 ms | 67.67 ms |

4x faster. Zero main-isolate work.

### Main-isolate time (what Flutter developers feel)

| Rows | resqlite | sqlite3 | sqlite_async |
|---|---|---|---|
| 1,000 | **0.10 ms** | 0.79 ms | 0.17 ms |
| 5,000 | **0.47 ms** | 3.90 ms | 0.87 ms |

### Concurrent reads (1,000 rows, 8 parallel queries)

| Library | Total wall | Per query |
|---|---|---|
| **resqlite** | **1.29 ms** | **0.16 ms** |
| sqlite_async | 1.58 ms | 0.20 ms |

### Schema shapes (1,000 rows)

| Shape | resqlite | sqlite3 | sqlite_async |
|---|---|---|---|
| Narrow (2 cols) | **0.18 ms** | 0.24 ms | 0.30 ms |
| Wide (20 cols) | **1.44 ms** | 1.96 ms | 1.68 ms |
| Text-heavy | **0.89 ms** | 1.07 ms | 1.07 ms |
| Numeric-heavy | **0.47 ms** | 0.63 ms | 0.63 ms |

### Parameterized queries (100 queries × ~500 rows)

| Library | Wall |
|---|---|
| **resqlite** | **23.02 ms** |
| sqlite3 (cached) | 23.57 ms |
| sqlite_async | 25.68 ms |

## Act Two: The Reader Pool

The library worked. It was fast. But every `select()` call spawned a fresh isolate, did its work, and died via `Isolate.exit`. The spawn cost was ~100-200µs — negligible for large queries where execution dominates, but for point queries (single-row lookups), spawn time was the entire cost. We were paying the setup tax on every read.

The obvious fix: persistent worker isolates. A pool of 2-4 workers that stay alive between queries. Small results return via `SendPort.send` (fast, no spawn). Large results still use the `Isolate.exit` sacrifice path (zero-copy). The pool auto-respawns workers that sacrifice.

We'd rejected this idea in experiment 011 because `SendPort.send` copies the entire object graph — and with `List<Map<String, Object?>>`, that meant copying 30,000 string keys per 5K-row query. But the flat list + `RowSchema` from experiment 008 changed the equation. Now the copy is just primitives in a flat list. The string keys live in one shared `RowSchema`. The copy cost dropped from O(rows × columns × key_length) to O(rows × columns) of primitive values.

Point query throughput jumped from ~14K qps to ~45K qps overnight.

### The Sacrifice Race

The pool introduced a concurrency bug we didn't see for days. When a worker sacrifices (Isolate.exit for a large result), two event handlers fire on the main isolate: the replyPort handler (delivering the result) and the exitPort handler (marking the worker dead). Between those two handlers, microtasks run — including callers waiting for a free worker.

In that gap, the slot looks available (the replyPort handler set `_busy = false`, the exitPort handler hasn't fired yet). Another caller claims it and sends a query to a dead worker. The query vanishes. The caller hangs forever.

The fix: the worker wraps every reply as `(result, sacrificed, errorMessage)`. If `sacrificed` is true, the pool doesn't mark the slot as available — it waits for the exitPort handler to trigger respawn. A record instead of a list, a boolean instead of a length check.

### Dedicated Readers

Profiling against sqlite_reactive (which was beating us on point queries, 43K vs 30K qps) revealed that our C-level connection pool added ~10µs per query in mutex overhead. Two lock/unlock cycles per read (acquire + release), plus the pool scan to find an idle reader.

But with persistent Dart workers, the Dart pool already guarantees one-worker-per-reader. The C pool's mutex was redundant. We assigned each Dart worker a fixed C reader index at spawn time and added `resqlite_stmt_acquire_on()` — same function, no mutex. Point queries went from 30K to 50K+ qps.

### The Stream Engine

Reactive queries started as ~50 lines embedded in `database.dart`. By the time we added per-subscriber buffered controllers, write generation counters, an inverted index for O(1) table invalidation, and worker-side result hashing, it was a full subsystem. We extracted it into `StreamEngine` — 340 lines, fully self-contained.

The key insight was moving the result hash to the worker isolate. For stream re-queries where the data hasn't changed (common in fanout scenarios — many streams, one write), the worker computes a hash and compares against the last emission. If unchanged, it sends back a single integer instead of the full ResultSet. No SendPort copy, no main-isolate hash computation, no subscriber notification. Shared fanout (25 watchers, one query) improved 33%.

## Tuning the Last 30%

The big architectural wins were in. But profiling showed there was still performance left on the table — not from design changes, but from disciplined micro-optimization.

**Batch FFI (experiment 009).** Each row required ~16 individual FFI calls: `sqlite3_step`, then `sqlite3_column_type`, `sqlite3_column_text`, `sqlite3_column_bytes` for each column. FFI calls aren't free — each one involves a thread state transition. We wrote `resqlite_step_row()`: one C function call per row that reads all columns into a pre-allocated buffer. 9-21% improvement across every benchmark, just by reducing FFI boundary crossings.

**isLeaf annotations (experiment 013).** Dart's FFI system has a flag called `isLeaf` that tells the VM "this C function won't call back into Dart." When set, the VM skips safepoint checks and thread state transitions on every call. We audited all 33 `@ffi.Native` bindings and added `isLeaf: true` to every one. 12-19% improvement on small results, 5-9% across the board. Zero code changes to the C side — purely a Dart annotation.

**Static parameter binding (experiment 028).** When binding text and blob parameters, we were allocating fresh native memory for each query, copying the bytes, then freeing after execution. For queries that run thousands of times (parameterized workloads), this add up. We switched to `SQLITE_STATIC` binding — telling SQLite the memory is valid for the duration of the call, avoiding the copy. Measurable improvement on parameterized query benchmarks.

None of these changed the architecture. They're the kind of optimizations you only find by profiling with `dart:developer` timeline events and reading the Dart VM source code. Together they shaved another 15-20% off the baseline.

## The Write Path

Reads got most of our attention, but writes matter too. SQLite only allows one writer at a time — that's a fundamental constraint of the database engine. We tried three approaches:

1. **One-off `Isolate.run` per write** — works, but you can't hold transaction state across isolate deaths.
2. **Run on main isolate** — defeats the whole purpose.
3. **Persistent writer isolate** — a single long-lived background thread that owns the write connection.

Option 3 won. The writer isolate receives messages (execute, batch, begin transaction, commit, rollback), processes them sequentially, and sends back results with the list of tables that were modified. That last part — dirty table tracking — is critical for the stream engine.

**Dirty tables via preupdate hook.** SQLite has a [preupdate hook](https://sqlite.org/c3ref/preupdate_count.html) that fires before every row modification. We register a callback that records which table was touched. After a write completes, the accumulated set of dirty table names rides back to the main isolate alongside the write result. The stream engine checks those names against its inverted index and re-queries affected streams. No polling, no separate notification channel — the write response itself carries the invalidation signal.

**Periodic checkpointing (experiment 029).** In WAL mode, SQLite appends writes to a log file. Periodically, a "checkpoint" moves those changes back to the main database file. By default, this can happen at unpredictable times, causing p95/p99 write latency spikes. We added writer-side PASSIVE checkpointing on a schedule — the writer isolate checkpoints between messages when the WAL exceeds a threshold. Much smoother tail latency.

**Batch execution.** `executeBatch('INSERT INTO t(a,b) VALUES (?,?)', [[1,'x'],[2,'y']])` serializes all parameter sets into one contiguous native buffer, crosses the FFI boundary once, and the C side loops: prepare once, bind+step for each set, commit. 1,000 rows in 0.43ms. The main isolate just dispatches the message — all the work happens on the writer.

## The Final Push

Two more experiments closed the gap between "fast" and "fastest."

**Row Map facade (experiment 032).** Our flat-list `Row` type implemented Dart's `Map` interface via `MapMixin`, which provides default implementations for methods like `containsKey`, `forEach`, and `entries`. Those defaults work but they're not optimal — they allocate iterators and call through generic interfaces. We overrode the key methods with direct implementations that index into the flat list. Same external API, measurably faster on the main isolate where Row access actually happens.

**Event-port cleanup (experiment 040).** The reader pool used a complex protocol: workers would send results, then send a "done" signal, and the pool would track state across both messages. We simplified to a single-message protocol — result + metadata in one shot. Fewer event port registrations, fewer microtask hops. Point queries jumped from ~68K to 107K qps. Sometimes the biggest wins come from removing complexity, not adding it.

### Where It Landed

40+ documented experiments — 16 accepted, 14 rejected, the rest explored and set aside. 9 benchmark suites with 3-repeat medians. The numbers, measured on a 10-core M1 Pro:

| Metric | Wall time | Main isolate |
|---|---:|---:|
| Point query | 0.009ms (107K qps) | 0.009ms |
| 1,000-row select() | 0.40ms | 0.10ms |
| 10,000-row select() | 5.60ms | 1.01ms |
| Batch insert 1,000 rows | 0.43ms | 0.00ms |
| Stream invalidation | 0.05ms | 0.05ms |
| Concurrent 8× reads | 0.74ms | — |

1.8x faster wall-clock reads, 2.1x faster writes, and sub-millisecond main-isolate time at 1K rows — using the same APIs (`select`, `execute`) that every library shares. Batch inserts at 10K rows are essentially tied with sqlite3 (4.47ms vs 4.46ms) — the C-level batch runner doesn't have an advantage over sqlite3's already-efficient synchronous path at that scale.

**A note on peer libraries:** The sqlite3 package is excellent for what it does — synchronous, simple, minimal overhead. If you're writing a CLI tool or a server where you control the thread model, it's a great choice. sqlite_async (PowerSync) brings production-tested streaming with smart defaults like 30ms write throttling for battery life. resqlite is optimized for a specific use case: Flutter apps where main-isolate time is the critical constraint. Different libraries, different strengths.

The full experiment log — every accepted optimization and every rejected dead end — is available on the [experiments page](https://danreynolds.github.io/resqlite/experiments/), with interactive charts showing how each metric evolved over time.

## Act Three: After the Headlines

107K qps is a nice round number to wrap a blog post on, but it's a strange place for a library to actually be. The architectural budget was spent — connection pool, persistent workers, flat-list ResultSet, dedicated readers. Anywhere we looked at the read path, we'd already touched it. So we started looking elsewhere: the streaming engine, the write path, and the C internals we'd previously left alone.

### The Streaming Engine, Revisited

The reactive layer worked, but it was naive about repeated work. A single write that touched a popular table would re-query every subscriber, even if the resulting rows were identical to the last emission. For Flutter UIs with many widgets watching the same data, that's a lot of pointless decode work.

**Microtask invalidation coalescing (experiment 045)** was the easy win. Multiple writes inside the same synchronous block — common when an app applies a server sync — used to fire one re-query batch per write. We accumulated dirty tables across the microtask boundary and dispatched once at the end. Fan-out workloads dropped 46%.

The harder win was **native-buffered hashing (experiment 075)**. We moved query result hashing into C as `resqlite_query_hash`, called inline during the read loop on the worker. If the hash matches the last emitted hash for that subscriber, we skip the Dart decode entirely and signal "no change" to the main isolate with a single integer. Unchanged-fanout workloads — a canary write plus 10 watchers seeing identical results — improved 39%.

This led directly to **the cheap-check-first sweep (experiment 077)**: four small fast-rejects strung together. Skip work if no streams are registered. Stop hash folding the moment row counts diverge. Cache the bind-parameter count instead of recomputing. Reuse a persistent buffer for the dirty-table list. Each was below the noise floor on its own; together they were 13–23% across write benchmarks. None of them were clever — they were just things we hadn't bothered to do before because the read path was the only thing we were measuring.

### The Allocation Hunt

A pattern emerged across the next dozen experiments: build it once at startup, reuse it forever. Per-call `calloc`/`free` had been quietly costing us hundreds of nanoseconds on every hot path.

**Persistent dirty buffer (experiment 070)** allocated a 512-byte FFI scratch space at worker init instead of per write. **Cached transaction statements (experiment 101)** prepared `BEGIN`, `COMMIT`, and `ROLLBACK` once at `resqlite_open` instead of re-parsing them per transaction — SQLite's `sqlite3_exec` rebuilds the AST and bytecode every call, and that adds up. 13–14% on transaction-heavy benchmarks. **Inline-packed parameter buffer (experiment 109)** went further: instead of allocating native memory for each text or blob bind, the bytes pack inline at the tail of the persistent param buffer, with explicit length passed to SQLite (skipping its internal `strlen`). 10–16% on text-INSERT workloads.

None of these are exciting individually. The pattern is. After enough rounds of "remove the per-call allocation," you start to see them everywhere — and most of them have been hiding in plain sight since experiment 008.

### Two Rejections Worth Naming

Not every plausible idea worked, and two of the rejections in this stretch were instructive enough to remember.

**The hash optimization that wasn't running (experiment 099).** We added an 8-byte main loop to the FNV byte hasher — fold 8 bytes per multiply instead of 1, a textbook win for long inputs. It measured flat. The cause wasn't the implementation; the streaming benchmarks at the time only carried cells of 5–8 bytes (column names like `item_5`, ID strings, short metadata). The new main loop literally never executed. Before declaring an optimization dead, verify the workload exercises the path it targets.

We later built [the long-text streaming benchmark (experiment 110)](https://github.com/danReynolds/resqlite/pull/54) specifically to give this kind of work somewhere to land.

**More workers, more problems (experiment 105).** The reader pool sizes itself at `clamp(numProcessors - 1, 2, 4)`. We tried raising it to 8 on the theory that fan-out workloads were starving for parallelism. Writer throughput regressed about 31%. Profiling showed the bottleneck wasn't reader availability — it was completion-side microtask churn on the main isolate. Per-write wall closely matched `pool_round_trip × ⌈N/pool_size⌉ + ~30 µs flat`, which means adding workers only helps when there are enough concurrent reads to fill them. On writer-shaped fan-out, the extra workers cost more in scheduling than they saved in latency.

The takeaway is one we keep relearning: the architecture that's right at one scale becomes the bottleneck at the next. Pool sizing tuned for read concurrency wasn't the right size for write fan-out, and the symptom looked nothing like the cause.

### Process Catches Up With The Code

By experiment 100, the project had a problem that had nothing to do with code. We'd run enough experiments that "what should I try next" was a non-trivial question. Some directions had clear next signals (exp 099 *needed* a long-text benchmark before another hash-loop change was worth attempting). Others looked active but had been quietly exhausted. Others were genuinely speculative but indistinguishable from the exhausted ones to a fresh runner.

The fix wasn't a doc — it was a structured machine-readable map. [`experiments/signals.json`](https://github.com/danReynolds/resqlite/blob/main/experiments/signals.json) now carries per-direction state, evidence pointers, and explicit `nextSignals` actions attached to rejections. A CI validator (`benchmark/check_experiment_signals.dart`) closes the gap between "outcome class" and "what was actually written" so the data stays honest. The journal you're partway through reading sits next to it, holding the lessons that don't fit a structured field. And [`RUNNER_INSTRUCTIONS.md`](https://github.com/danReynolds/resqlite/blob/main/experiments/RUNNER_INSTRUCTIONS.md) is the playbook for any agent or human who picks up the next experiment cold.

The whole system was dogfooded by experiment 110, which both *resolved* exp 099's `nextSignals` ("representative long-text streaming benchmark") and *exposed* a hole in the validator's outcomeClass enum — a hole the same PR closed. That's the loop working as designed: process improvements arrive as outputs of running the process, not as separate planning work.

### The Numbers, Three Months Later

The same M1 Pro, the same benchmark suite, after experiments 041–110:

| Metric | Then (exp 040) | Now (exp 110) |
|---|---:|---:|
| Point query | 107K qps | 107K qps |
| Unchanged-fanout (10 watchers) | baseline | −39% |
| Fan-out invalidation (10 streams, batched) | baseline | −46% |
| Transaction-bracketed batch (1k rows) | baseline | −13% |
| Text-parameter inserts | baseline | −10–16% |

The headline ceiling didn't move — it was already at the floor of what the architecture allows. What moved is everything around it: the streaming engine wastes much less work, the write path allocates less per call, and the project now has a process that turns rejections into next experiments instead of dead ends.

## The Hang That Wasn't Ours

While Act Three was happening on the benchmarks, we were dogfooding resqlite in a real Flutter app. And in that app, we hit something we couldn't explain. Roughly one in five cold launches on macOS would freeze: black screen, beachball, no recovery. The logs always stopped at the same line — `Migrate DB started` — and never resumed.

The migration code was about as boring as code gets: read `PRAGMA user_version`, run schema DDL if needed, write the new version. It had run correctly thousands of times. But sometimes, on cold launch, it just... stopped.

Our first instinct was to suspect hot reload — maybe an old `Database` instance was leaving orphaned isolates around, deadlocking against the new writer's `BEGIN IMMEDIATE`. We added a close-before-reopen guard. Then we asked the question that saved us hours: do `sqflite`, `drift`, and `sqlite_async` have this same guard? Reading their source: none of them do. Either every comparable library was broken, or our diagnosis was wrong.

We backed up. Hot reload doesn't re-run `main()`. Hot restart resets the entire VM. There's no scenario where two `Database` instances exist simultaneously. The guard was harmless but pointless. We reverted it.

But the freeze was still real. And looking at the launch logs again, this was happening on **cold launch**, not hot anything. The first call after `init DB completed` was `_migrate()`, and the very first thing it did was `db.select('PRAGMA user_version')` — a single read through the reader pool.

### Following the Code Path

We traced the read path. `Database.select` waits for the reader pool to spawn its worker isolates, then dispatches a query. Both could plausibly hang. We instrumented every transition with prints: `[ReaderPool] reader X: Isolate.spawn done, awaiting SendPort...`, `[ReaderWorker] entrypoint started for reader X`.

The next reproduction was the smoking gun:

```
[ReaderPool] reader 0: Isolate.spawn done, awaiting SendPort...
[ReaderPool] reader 1: Isolate.spawn done, awaiting SendPort...
[ReaderPool] reader 2: Isolate.spawn done, awaiting SendPort...
[ReaderPool] reader 3: Isolate.spawn done, awaiting SendPort...
```

All four `Isolate.spawn` futures resolved. The Dart VM said "isolates created." But not a single entrypoint executed. Not one. Even a basic `Timer.periodic` we added to the main isolate never fired.

That last detail was the breakthrough: a timer not firing means **the event loop itself isn't running**. This wasn't an async hang. The main thread was synchronously stuck.

### sample(1) to the Rescue

When the Dart event loop is dead, the Flutter DevTools are dead too — they talk to the VM service, and the VM service hangs along with everything else. We needed to look at the threads natively. macOS ships a built-in tool, `sample`, that snapshots every thread's call stack. We pointed it at the hung process. The main thread was here:

```
dart::SafepointHandler::ExitSafepointLocked
  → dart::ConditionVariable::WaitMicros
    → _pthread_cond_wait
```

And reading further up the stack:

```
CGSDatagramReadStream::dispatchMainQueueDatagrams
  → NSNotificationCenter
    → FlutterAppLifecycleRegistrar.handleDidChangeOcclusionState
      → FlutterEngine setApplicationState
        → Dart_EnterIsolate
          → Thread::ExitSafepoint  ← BLOCKED
```

macOS had sent the app a `didChangeOcclusionState` notification — fired when the window changes visibility, which happens during cold launch when the window first appears on screen. Flutter's lifecycle handler tried to dispatch this into Dart by calling `Dart_EnterIsolate`. That call entered the VM's safepoint protocol, found that a safepoint operation was already in progress, and blocked waiting for it to finish. It never finished.

### A Theory, Then a Better One

Our first theory was clean. Flutter 3.33+ merges the platform thread and the UI thread on macOS. So system notifications and Dart code run on the same thread. If the VM is in a safepoint and a system notification arrives, the lifecycle handler tries to re-enter the isolate, but can't — deadlock.

We toggled `FLTEnableMergedPlatformUIThread = false` in `Info.plist`, the Flutter opt-out for merged threads. The hangs stopped. We had a workaround. We started drafting a Flutter issue.

But before filing, we wanted to understand the mechanism. We sent three research agents into the Dart VM and Flutter engine source code in parallel.

What came back changed the diagnosis. The full `sample` output had **21 threads**, and a closer look at the DartWorker pool revealed a four-thread circular dependency that had nothing to do with `Isolate.spawn`:

| Thread | Holds | Waiting for |
|---|---|---|
| DartWorker A | Deopt-level safepoint | All threads to park |
| DartWorker B | `PortMap::mutex_` | A `MessageHandler` monitor |
| DartWorker C, D | (in `HandleMessages`) | Safepoint to complete |
| Main thread | (just arrived) | Safepoint to complete |

The safepoint owner wasn't isolate spawning. It was `Debugger::RunWithStoppedDeoptimizedWorld` — the **Dart VM debugger setting a breakpoint**. Because we were running via `flutter run`, the IDE was attached to the VM service and was actively syncing breakpoints during the launch window.

The merged thread mode wasn't the root cause. It was the trigger that escalated a silent debugger deadlock into a visible app freeze. Without merged threads, the main thread wouldn't get pulled in — the app would render — but the VM debugger would still be stuck. The DartWorker pool deadlock existed regardless.

### Verifying the Verification

We pushed harder. Did `HandleMessages` actually hold its mutex during `BlockForSafepoint`, as we'd claimed? An agent went and read that exact code path.

The answer was no. The Dart VM team explicitly releases the `MessageHandler::monitor_` before calling `HandleMessage`, with a code comment saying the release is intentional to avoid exactly this kind of deadlock. Our circular dependency story was partially wrong. The mutex DartWorker B was blocked on **should have been free**, and the actual holder wasn't visible in any of the 21 sampled threads.

Some claims held up. `PortMap::PostMessage` does hold `PortMap::mutex_` for the entire call (RAII locker, confirmed in source). The `kCheckForReload` path that pulls isolate threads into the safepoint is `#if !defined(PRODUCT)` — debug builds only. GC-driven safepoints can't trigger this; concurrent markers bypass the safepoint protocol.

But the critical "who holds the mutex" question was beyond what we could answer from sample output alone. That needed lock instrumentation or thread sanitizer in the VM itself.

### Filing Upstream

We filed [flutter/flutter#185156](https://github.com/flutter/flutter/issues/185156) with the full thread analysis. Within hours, Vyacheslav Egorov (mraleph), a senior Dart VM engineer, responded with the exact question we'd flagged as our open gap: who holds the mutex?

We replied honestly: we don't know. The expected holders don't hold it (`HandleMessages` releases it). The remaining threads in the sample are all idle. Identifying the actual holder needs TSAN or VM-side instrumentation.

His next message was sharper. Our suggested fix — defer the Flutter lifecycle dispatch to avoid the inline `Dart_EnterIsolate` — didn't address the underlying VM bug. Even if we deferred dispatch, the VM-internal deadlock between debugger and worker threads would still exist. We'd just be unblocking the main thread while the debugger remained stuck. He was right. The fix we proposed only papered over a secondary symptom.

We tried building a standalone reproduction to make the VM team's investigation easier. We spawned a minimal Flutter app that opened a VM service connection to itself and flooded `addBreakpointWithScriptUri` calls during isolate spawning. 150+ launches, no deadlock. The timing window in our real app was opened by heavyweight FFI startup work (SQLCipher initialization, multi-connection setup) that gave the IDE time to send breakpoint requests during the spawn window. A minimal app spawns and finishes too fast.

### The Catch We Missed

The trail looked cold. Then Martin Kustermann, another Dart VM engineer, read the call path more carefully and spotted what we'd missed: `AcquiredQueues`.

We'd checked `HandleMessages` and correctly concluded that *it* releases `MessageHandler::monitor_` before running message work. But there's a second place the same monitor gets acquired — `Service::InvokeMethod` takes it via an `AcquiredQueues` scope so the service can dump the message queue as part of the `GetStack` reply. That scope was active on Thread 40797896 the entire time we were staring at it.

With the monitor already held, the thread runs Dart code (`MessageQueue::PrintJSON` triggers JIT compilation), which finishes inside a `~NoReloadScope` destructor, which sees another thread is requesting a safepoint, which posts an OOB "check-in for reload" message to its own port. That post acquires `PortMap::mutex_`, then tries to acquire the destination's `MessageHandler::monitor_` — the same one this thread already owns.

**A thread trying to lock a mutex it already holds.** That was the deadlock.

mraleph confirmed Martin's catch — "ah-ha! I have somehow overlooked the existence of `AcquiredQueues`" — and within hours had a fix up. The cleanest path turned out to be simpler than the diagnosis: nobody actually consumes the message-queue dump in the `GetStack` reply (Observatory used it; DevTools doesn't). [dart-lang/sdk@53ac68e](https://github.com/dart-lang/sdk/commit/53ac68e2dd750d988c676cce0ae79b385d1efeec) makes the VM always return an empty array for that field, removing the lock-and-then-run-Dart pattern entirely. The Flutter issue closed six days after we filed it, retitled to *"Dart vm-service GetStack method can deadlock by trying to lock the same MessageHandler monitor recursively."*

### What We Took Away

The deadlock was debug-mode only — release builds have no VM service, no breakpoint setting, no `kCheckForReload` path — and now it's fixed. We re-enabled merged threads. A specific class of intermittent macOS Flutter freeze that's been hitting people on the bleeding edge of merged threading is gone from the next Dart SDK roll.

A few things from this investigation worth remembering next time something inexplicable hangs:

**The pinwheel was the most important clue.** Async hangs leave the event loop alive — animations keep playing, timers fire, the cursor responds. A black screen with a beachball means the main thread is synchronously stuck. That distinction completely changed what we were looking for.

**`sample <pid>` is a superpower for hung macOS processes.** When the Dart VM is dead, no Flutter or Dart-level tooling works. But every Mac has `sample` built in. It dumped 21 thread stacks in a hundred milliseconds and showed exactly what was happening at the C/Objective-C layer. That output was also what made the upstream conversation possible — without it, there was nothing for the VM team to reason about.

**Push back when an explanation doesn't fit the pattern.** "Why don't sqflite, drift, and sqlite_async have this same hot-reload guard?" was a one-line question that saved hours. If your fix would imply that every comparable library has the same bug, your fix is probably wrong.

**Verify load-bearing claims, but know what you can't see.** We checked `HandleMessages` and correctly concluded the mutex *should* be free along that path. We just didn't realize there was another path — the `AcquiredQueues` scope in `Service::InvokeMethod` — taking the same lock somewhere else. Even careful verification has blind spots when you don't know which file to read. The cure isn't more rigor on what you have; it's pairing your analysis with someone who has different blind spots.

**An incomplete-but-honest report can still ship a fix.** We never identified the actual lock holder — that was Martin's catch, made in minutes of source reading because he had `AcquiredQueues` in his head. But the thread sample we provided, plus our explicit admission of "we don't know who holds this," was the artifact that let him make the catch at all. A confident misdiagnosis would have sent the conversation in the wrong direction. The framing that worked was: here is hard evidence, here is what we could rule out, here is exactly the gap we couldn't close. Then trust the experts to close it.

**Sometimes the bug isn't in your library — and reporting it carefully is real work.** Six hours of debugging later, the root cause was a recursive self-lock in the Dart VM service's stack-dumping code, escalated into a visible UI freeze by Flutter's merged-thread mode. The right action was a bug report, not a code change. Knowing when to stop digging into your own code is its own skill, and the report itself is the deliverable when you cross that line.

## What We'd Tell Our Past Selves

**Measure main-isolate time separately from wall time.** A library can look fast on wall time while putting all the work on the thread that renders your UI. These are different metrics and you need to optimize for both, but main-isolate time is what your users actually feel.

**The Dart VM's object graph walk is the hidden cost of `Isolate.exit`.** The documentation says "zero-copy" and "constant time." That's true for the transfer. The validation pass that precedes it is linear in heap object count. This single insight drove our most impactful optimization.

**Data structures matter more than algorithms here.** Replacing `LinkedHashMap` with a flat list was more impactful than writing C code, optimizing mutexes, or building connection pools. The 10x reduction in object count (200k → 3) translated directly to transfer performance because it reduced the `Isolate.exit` validation surface.

**Lazy doesn't always mean less work on main.** The byte-backed lazy approach deferred decode to main, which is the worst place for it in a Flutter app. The flat-list lazy approach defers only `Row` object creation (3 field assignments, nanoseconds). "Lazy" is only good if what you're deferring is cheap.

**You can't beat the Dart VM's serializer in Dart.** `TransferableTypedData` with manual encode/decode was 5-7x slower than `SendPort.send()`. The only way to win is to either avoid creating Dart objects entirely (C pipeline for bytes) or reduce the object count (flat list for maps).

**C connection pools beat Dart worker pools — until they don't.** Early on, `pthread_mutex` coordination was faster than Dart isolate dispatch. But once we had persistent workers with 1:1 reader assignment, the C mutex became pure overhead. Removing it (dedicated readers, experiment 030) gave us a 40% point query improvement. The architecture that's right at one scale becomes the bottleneck at the next.

**Tests find concurrency bugs that benchmarks hide.** The sacrifice race (replyPort fires before exitPort, callers claim a dead slot) never showed up in benchmarks — queries just silently hung. It took a stress test firing 8 concurrent large queries to expose it. Write concurrent tests before you think you need them.

**Single-run benchmarks lie.** We cited 65K point queries/sec for weeks before running 3-repeat measurements and discovering the real stable number was closer to 50-68K depending on thermal state. The first run of any benchmark is always the worst (cold JIT, cold caches). At minimum, run 3 times and take the median.

**The last 30% comes from micro-optimization, not architecture.** After the big wins (flat lists, connection pool, persistent workers), the remaining gains came from reducing FFI crossings, adding compiler hints, and simplifying protocols. These aren't exciting, but they compound — a dozen small experiments got us from 68K to 107K point queries/sec.

**Benchmark everything, believe nothing.** String interning sounded smart. Binary codecs sounded efficient. Lazy byte-backed maps sounded like the best of both worlds. All three were slower where it mattered. The ideas that actually worked — flat lists, lazy `Row` wrappers, per-query `NOMUTEX`, dedicated readers — weren't the ones we'd have bet on at the start.
