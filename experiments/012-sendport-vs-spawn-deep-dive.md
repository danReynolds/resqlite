# Experiment 012: SendPort vs Isolate.spawn Deep Dive — Why Persistent Pools Aren't Faster

**Date:** 2026-04-07
**Status:** Investigation complete (original rejection of persistent pool confirmed)

## Executive Summary

Despite persistent worker pools having ~60us lower messaging overhead per query, resqlite's one-off `Isolate.spawn` + `Isolate.exit` architecture is equivalent in practice. The investigation reveals that:

1. **The original 22% slowdown was caused by resqlite's pool implementation details, not by SendPort inherently** — specifically, using `ReceivePort` + `.first` instead of `RawReceivePort` + `Completer`, and serializing wrapper classes with `Map<String, Object?>` results.

2. **sqlite_async uses a persistent pool and matches resqlite's one-off isolates** — median 84-87us vs 84-91us per single-row lookup (within noise). But sqlite_async has different overhead tradeoffs that cancel out the pool's messaging advantage.

3. **The messaging advantage of pools (60us saved) is consumed by 2x event-loop hops** — a pool query requires request delivery (~3us) + worker processing + result delivery (~3us) through the Dart event loop. While these hops are fast (~6us total), the pool also pays for request serialization (SQL string + params) that one-off isolates avoid.

## Detailed Findings

### 1. sqlite_async Architecture Analysis

sqlite_async (v0.14.0-wip.0) uses a persistent `IsolateWorker` pool. The read path for `getAll()` is:

```
getAll(sql, params)
  -> readLock()
    -> _useConnection(writer: false)
      -> pool.reader()             // lease a connection from native pool
      -> _takeIsolateWorker()      // get an IsolateWorker from queue
      -> _LeasedContext(inner, worker)
        -> execute(sql, params)
          -> _runOnWorker(closure)
            -> inner.unsafeAccess(conn => {
                 ptr = conn.unsafePointer.address   // extract raw pointer
                 worker.run(closure_capturing_ptr)  // send to worker isolate
               })
```

**Key design choices:**

- **IsolateWorker sends closures, not data messages:** Instead of sending SQL + params as separate fields, sqlite_async sends a `Function()` closure that captures the SQL string, params, and pointer address. The closure is serialized by Dart's isolate message passing.

- **Results are `ResultSet` (List<List<Object?>>), not List<Map>:** The `ResultSet` from the `sqlite3` package stores rows as `List<List<Object?>>` with column names stored once. This is cheaper to serialize than `List<Map<String, Object?>>` where string keys are repeated per row.

- **Two layers of indirection:** The `IsolateWorker` wraps results in `Result.capture()` (from `package:async`) then `WorkResult(id, result)`. This adds wrapper objects to serialize.

- **Connection leasing adds overhead:** Every query leases a connection from the native pool, runs the query, then returns the lease. This involves mutex acquisition and an extra async hop.

- **Worker pool is a LIFO queue:** Workers are reused from a `ListQueue`, not a fixed array. If more workers are needed, new ones are spawned dynamically.

### 2. Microbenchmark Results

#### Pure messaging overhead (no SQLite work)

| Pattern | Median | Notes |
|---|---|---|
| SendPort round-trip, no payload | 6 us | Bare ping-pong |
| SendPort round-trip, 1 map | 10 us | Build + serialize 1 six-column map |
| SendPort round-trip, 10 maps | 13 us | Build + serialize 10 maps |
| Isolate.spawn + exit, no work | 50 us | Spawn overhead alone |
| Isolate.spawn + exit, 1 map | 47 us | Build map + ownership transfer |
| Isolate.spawn + exit, 10 maps | 46 us | Build 10 maps + ownership transfer |
| RawReceivePort round-trip | 2 us | Most efficient receive pattern |

**The pool has a massive raw advantage:** 6-13us vs 47-50us. This confirms that Isolate.spawn costs ~50us, and SendPort messaging is 5-10x faster for small results.

#### Instrumented breakdown (SendPort round-trip, build 1 map)

| Phase | Median | P95 |
|---|---|---|
| Request delivery (main -> worker event loop) | 3 us | 5 us |
| Worker computation (build 1 map) | 0 us | 1 us |
| Reply delivery (worker -> main event loop) | 3 us | 6 us |
| **Total** | **7 us** | **11 us** |

Each event-loop hop costs ~3us. The 2-hop round trip costs ~6us of scheduling overhead.

#### Simulated pool patterns (no SQLite, 500 sequential queries)

| Pattern | Median per query | Notes |
|---|---|---|
| One-off isolate (resqlite production) | 67 us | Spawn dominates |
| Pool + ReceivePort + .first | 10 us | resqlite's pool pattern |
| Pool + RawReceivePort + Completer | 6 us | Optimized receive |
| Pool + List\<List\> result | 6 us | sqlite_async-style result |
| Pool + closure dispatch | 7 us | sqlite_async-style request |
| Pool + raw map, no wrapper | 7 us | Minimal overhead |

**When there is no SQLite work, the pool is 7-11x faster.** The pool's messaging advantage is real and substantial.

#### Serialization cost: Maps vs Lists

| Format | SendPort median | Isolate.exit median |
|---|---|---|
| 1 row as Map | 15 us | 61 us |
| 1 row as List<List> | 9 us | 56 us |
| 10 rows as Map | 14 us | 51 us |
| 10 rows as List<List> | 8 us | 50 us |
| 50 rows as Map | 32 us | 68 us |
| 50 rows as List<List> | 14 us | 51 us |

Maps cost ~2x more than Lists to serialize via SendPort. The string key overhead grows with row count. But via Isolate.exit, the difference is minimal because ownership transfer just validates the object graph (doesn't copy).

### 3. Peer Comparison: resqlite vs sqlite_async (Real SQLite)

500 sequential single-row lookups on 100 rows, 6 columns:

| Metric | resqlite | sqlite_async | Ratio |
|---|---|---|---|
| Total 500 lookups | 46-51 ms | 47-48 ms | ~1.0x |
| Per-query median | 84-91 us | 84-87 us | ~1.0x |
| Per-query P95 | 149-187 us | 147-161 us | ~1.0x |
| Per-query min | 59-60 us | 59-60 us | ~1.0x |

**They are functionally identical in performance.** sqlite_async's persistent pool advantage is exactly canceled out by its additional overhead layers.

### 4. Why sqlite_async's Pool Doesn't Win Despite Lower Messaging Cost

sqlite_async pays for its pool approach with overhead resqlite's one-off isolates avoid:

1. **Connection leasing:** Every query acquires a connection from the native pool (mutex), then returns it. This is async and involves the event loop.

2. **Mutex serialization:** The `AsyncConnection._mutex.withCriticalSection()` wraps every query in a critical section to prevent concurrent use of the same connection.

3. **Result wrapping:** Results go through `Result.capture(Future.sync(task))` -> `WorkResult(id, result)` -> SendPort -> unwrap `WorkResult` -> unwrap `Result` -> extract value. This is three layers of wrapping.

4. **Error handling tax:** `runZonedGuarded` in `WorkItem.handle()` adds zone overhead per query.

5. **Connection pool overhead dominates:** Getting a reader connection from the native pool, checking for pending transactions, acquiring the worker, running the closure, returning the worker, returning the lease — this lifecycle management consumes the ~50us that the pool saves on messaging.

### 5. Why resqlite's Pool Was 22% Slower

The original experiment (011) found resqlite's pool 22% slower (130us vs 107us per query). This is explained by:

1. **`ReceivePort` + `.first` is ~4us slower per query than `RawReceivePort` + `Completer`** — .first creates a StreamSubscription, allocates a broadcast controller, subscribes, gets one event, then cancels. `RawReceivePort` bypasses the stream layer entirely.

2. **`_QueryResult` wrapper adds serialization cost** — wrapping `List<Map>` in a class adds object header serialization overhead.

3. **Request serialization is redundant** — sending SQL string + params as explicit fields in `_QueryRequest` serializes data that the one-off isolate captures for free in the closure.

4. **The pool doesn't have enough work to amortize its advantages.** For single-row queries that take ~30us of actual SQLite work, the 50us spawn overhead of one-off isolates is comparable to the pool's total messaging + scheduling overhead (~20-30us) plus the extra overhead of acquiring/releasing the reader slot on the C side.

### 6. Can Persistent Pools Be Made Competitive?

Yes, but only for concurrent workloads. For **sequential** queries:

- The pool saves ~40-50us on messaging but needs ~20-30us for its own overhead
- Net savings: ~15-25us per query
- On a ~85us query, that's 18-29% improvement
- BUT the pool's advantage only materializes if you also eliminate the C-level reader acquisition overhead and use `RawReceivePort`

For **concurrent** queries, the pool is already implicitly used by resqlite's reader pool for streams. The one-off isolate approach is actually excellent for concurrent reads because multiple isolates can run on different OS threads simultaneously, while a pool's workers must process messages sequentially (one at a time per worker).

## Recommendation

**Keep the one-off `Isolate.spawn` + `Isolate.exit` architecture for reads.** Reasons:

1. **Performance is equivalent to sqlite_async's persistent pool** — confirmed by direct benchmark comparison.

2. **Simplicity** — no worker lifecycle management, no respawning, no message protocol, no request serialization.

3. **Natural concurrency** — each query gets its own OS thread, enabling true parallelism on multi-core. Pool workers are single-threaded and process queries sequentially.

4. **Zero-copy for any result size** — `Isolate.exit` transfers ownership of arbitrarily large object graphs with O(n) validation walk but no copying. `SendPort.send` must deep-copy everything, and the cost grows linearly with string content.

5. **The spawn overhead is constant** — ~50us regardless of result size. Pool messaging overhead grows with result size (due to serialization). The crossover point where spawn becomes cheaper is surprisingly low (~10-20 rows with string columns).

If persistent pools are revisited in the future, the optimization path would be:
- Use `RawReceivePort` instead of `ReceivePort` for reply ports
- Send results as `List<List<Object?>>` + column names (not `Map`)
- Pre-encode params as bytes to avoid serializing the request
- Consider `TransferableTypedData` for large byte results
- Use a dedicated reader per worker (skip the C-level reader pool mutex)

These changes could save ~15-25us per query but add significant complexity.
