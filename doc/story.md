# How We Built the Fastest SQLite Library for Dart

Every SQLite library in the Dart ecosystem has the same bottleneck: getting data from SQLite's C engine to your Dart code without blocking the UI. We spent a day trying to solve this and ended up building something that beats every existing library on every benchmark that matters. Here's the story of how we got there — including the dead ends.

**The bottom line:** resqlite reads 1,000 rows in 0.40ms (1.8x faster than the next best library), writes in 1.78ms (2.1x faster), and keeps main-isolate time under 1ms for 10,000-row queries. Point query throughput is 107K queries/sec. Every optimization is documented — including the ones that failed.

## The Problem We Were Trying to Solve

We were building an HTTP endpoint backed by [SQLite](https://sqlite.org/) — the embedded database that runs on basically everything. SQLite is written in C and runs in-process, so there's no network overhead. The bottleneck isn't the database — it's getting the results into Dart.

The code was simple:

```dart
final rows = await db.select('SELECT * FROM items');
return Response(200, body: jsonEncode(rows));
```

But profiling told a different story. For 5,000 rows, 8.6ms of the 15ms total was happening on the main isolate — half a frame budget in Flutter. Here's why:

If you're not familiar with Dart: your application runs on the "main isolate" — a single thread that handles UI rendering, user input, and your application logic. Think of it like JavaScript's main thread, but stricter. [Isolates](https://dart.dev/language/isolates) are Dart's concurrency primitive: independent threads with their own memory that communicate by passing messages (no shared memory, no locks). [FFI](https://dart.dev/interop/c-interop) (Foreign Function Interface) is how Dart calls C code — each call has a small overhead. Most SQLite libraries use a background isolate to run queries, then send results back to the main isolate.

The data path looked like this:

```
SQLite C engine
  → sqlite3 package reads each cell via FFI (30,000 FFI calls for 5k × 6 columns)
  → Dart Map objects created on the worker isolate
  → SendPort.send() deep-copies every map to the main isolate
  → Main isolate jsonEncode()s the maps
  → utf8.encode() to bytes
  → Hand to shelf (Dart's HTTP server)
```

Three intermediate representations (Dart maps, JSON string, UTF-8 bytes) for what should be a straight pipeline from database to socket. And the main isolate was doing the heaviest work — the JSON serialization.

We set ourselves a principle: **minimize main-isolate work above all else.** In Flutter, the main isolate runs your UI at 60fps — that's a 16ms budget per frame. Every millisecond spent on database work there is a millisecond that could cause dropped frames, stuttery scrolling, or unresponsive touch handling. Total wall time matters, but main-isolate time is what users feel.

## Attempt 1: Move the JSON Encoding Off Main

We built `db.compute()` — spawn a one-off isolate, JSON-encode there, return bytes. Dart's `Isolate.run()` uses `Isolate.exit()` under the hood, which transfers the return value to the receiving isolate **without copying**. This is different from `SendPort.send()`, which deep-copies everything. The trade-off: `Isolate.exit()` kills the sending isolate, so it only works for one-off workers.

For a `Uint8List` (Dart's byte array type, backed by a contiguous block of memory), this transfer is essentially O(1) — one object, instant ownership reassignment.

```dart
final bytes = await db.compute((db) {
  final rows = db.select('SELECT * FROM items');
  return utf8.encode(jsonEncode(rows)) as Uint8List;
});
```

We measured wall time and main-isolate time separately:

| Path (5,000 rows) | Wall | Main |
|---|---|---|
| Worker pool + jsonEncode on main | 15.30 ms | **8.64 ms** |
| `compute()` → `Uint8List` bytes | 16.03 ms | **0.00 ms** |
| `compute()` → `List<Map>` | 15.15 ms | **7.84 ms** |

Returning bytes: 0.00ms on main. Returning maps: still ~8ms on main. The maps arrived via `Isolate.exit()` without copying, but `jsonEncode` still ran on main after they arrived.

**Lesson:** Moving work off main only helps if the result arrives in a form the main isolate doesn't need to process further.

This got us thinking — what if the JSON encoding happened in C?

## Attempt 2: A New Library, Raw FFI, C-Native JSON

We started resqlite from scratch. No dependency on the existing `sqlite3` Dart package. Raw [FFI](https://dart.dev/interop/c-interop) (Foreign Function Interface) bindings to SQLite's C API — Dart can call C functions directly with ~100ns overhead per call. We bundled the SQLite amalgamation (the entire database engine as a single C file) and compiled it as part of our build.

We wrote a C function that reads SQLite columns and writes JSON directly into a `malloc`'d buffer — zero Dart objects involved:

```c
int resqlite_query_to_bytes(sqlite3_stmt* stmt, unsigned char** out_buf, int* out_len) {
    // Steps through rows in C, reads column values, writes JSON.
    // Handles string escaping, number formatting, null literals.
    // One tight loop, no FFI boundary crossings for result data.
}
```

At 5,000 rows:

| Path | Wall |
|---|---|
| resqlite `selectBytes()` | **4.35 ms** |
| sqlite3 + jsonEncode | 15.02 ms |

**3.5x faster.** The C function did everything in one pass — read columns, escape strings, format numbers. Zero Dart objects for the result data. The `Uint8List` containing the JSON transferred to the main isolate via `Isolate.exit()` at effectively zero cost.

For maps though, the story was different. We also wrote a C function that packed results into a compact binary buffer, then decoded it to maps in Dart. This was only ~7% faster than the `sqlite3` package's per-cell FFI approach. The Dart object allocation cost (creating `Map`, `String`, etc.) was the floor that everyone hits regardless of how they read the data.

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

Zero `Row` objects. Zero `Map` internals. The structural object count dropped from ~200,000 to **3**.

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

## The Final Numbers

Two methods. Clean API. Fastest in the ecosystem.

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

### Where It Landed

41 documented experiments. 85 tests. 9 benchmark suites. The numbers, measured honestly with 3-repeat medians:

| Metric | Wall time | Main isolate |
|---|---:|---:|
| Point query | 0.016ms (65K qps) | 0.016ms |
| 5,000-row read | 3.5ms | 0.7ms |
| 20,000-row read | 19ms | 3ms |
| Stream invalidation | 0.1ms | — |
| Batch 1,000 rows | 0.8ms | — |

Against async peer libraries (sqlite_reactive, sqlite_async), resqlite wins 9 of 12 benchmark cases. The two losses are batch write (we wrap in a transaction for atomicity — they don't) and unique fanout (they pin streams to readers — we dispatch through the pool).

## What We'd Tell Our Past Selves

**Measure main-isolate time separately from wall time.** A library can look fast on wall time while putting all the work on the thread that renders your UI. These are different metrics and you need to optimize for both, but main-isolate time is what your users actually feel.

**The Dart VM's object graph walk is the hidden cost of `Isolate.exit`.** The documentation says "zero-copy" and "constant time." That's true for the transfer. The validation pass that precedes it is linear in heap object count. This single insight drove our most impactful optimization.

**Data structures matter more than algorithms here.** Replacing `LinkedHashMap` with a flat list was more impactful than writing C code, optimizing mutexes, or building connection pools. The 10x reduction in object count (200k → 3) translated directly to transfer performance because it reduced the `Isolate.exit` validation surface.

**Lazy doesn't always mean less work on main.** The byte-backed lazy approach deferred decode to main, which is the worst place for it in a Flutter app. The flat-list lazy approach defers only `Row` object creation (3 field assignments, nanoseconds). "Lazy" is only good if what you're deferring is cheap.

**You can't beat the Dart VM's serializer in Dart.** `TransferableTypedData` with manual encode/decode was 5-7x slower than `SendPort.send()`. The only way to win is to either avoid creating Dart objects entirely (C pipeline for bytes) or reduce the object count (flat list for maps).

**C connection pools beat Dart worker pools — until they don't.** Early on, `pthread_mutex` coordination was faster than Dart isolate dispatch. But once we had persistent workers with 1:1 reader assignment, the C mutex became pure overhead. Removing it (dedicated readers, experiment 030) gave us a 40% point query improvement. The architecture that's right at one scale becomes the bottleneck at the next.

**Tests find concurrency bugs that benchmarks hide.** The sacrifice race (replyPort fires before exitPort, callers claim a dead slot) never showed up in benchmarks — queries just silently hung. It took a stress test firing 8 concurrent large queries to expose it. Write concurrent tests before you think you need them.

**Single-run benchmarks lie.** We cited 65K point queries/sec for weeks before running 3-repeat measurements and discovering the real stable number was closer to 50-68K depending on thermal state. The first run of any benchmark is always the worst (cold JIT, cold caches). At minimum, run 3 times and take the median.

**Benchmark everything, believe nothing.** String interning sounded smart. Binary codecs sounded efficient. Lazy byte-backed maps sounded like the best of both worlds. All three were slower where it mattered. The ideas that actually worked — flat lists, lazy `Row` wrappers, per-query `NOMUTEX`, dedicated readers — weren't the ones we'd have bet on at the start.
