---
component: api
title: Public API & streams
kicker: main isolate
zone: main
diagram: api
directions: [stream-rerun-dispatch, long-text-stream-hashing]
feeds: [boundary]
section: architecture
---

resqlite's public surface is deliberately small — `select`, `selectBytes`, `execute`, `executeBatch`, `transaction`, `stream` — and every call is exactly one message to a worker isolate. The design principle behind the whole library is visible in that sentence: the main isolate is a Flutter app's render thread with a 16 ms frame budget, so the API's job is to hand work away and get out of the way.

Two read shapes exist because two different consumers exist. `select` returns Dart maps for code that inspects rows. `selectBytes` returns JSON bytes encoded entirely in C, for code that forwards a response or writes a file and never needs Dart objects at all — at 5,000 rows it costs slightly more wall time than `select` but **zero** main-isolate time.

## The result shape is a transfer decision

`select` does not return a list of maps. It returns a `ResultSet` over a single flat `List<Object?>` laid out row-major, with lightweight `Row` views created lazily on indexing. Callers get ordinary map ergonomics; the boundary gets a graph with almost no structural objects in it.

That choice was made for transfer, not ergonomics. `Isolate.exit` validates the object graph it hands over, and a 20,000-row result built from per-row maps reaches hundreds of thousands of internal objects — measured at roughly 38% of total query time. The flat list collapses that to the values array, one schema, and a wrapper. The same property later became the basis of the sacrifice trigger itself: slot count is both what `send` copies and what the exit walk visits.

## Streams: hashing, dispatch, and elision

`stream()` turns a query into a live data source. It emits immediately, then re-emits when a write touches data the query can observe. That first emission is a guarantee rather than a timing accident: a stream resolves to a value or an error, never to silence ([[test:test/stream_test.dart#always emits its initial result@z31i]]). When a write lands while the initial query is still in flight, the rows already known to be superseded are withheld and the corrected re-query becomes the subscriber's first frame [[255.1]]. Three SQLite hooks make that possible without parsing SQL: authorizer callbacks on readers record which tables and columns a query actually read; authorizer callbacks on prepared writes record what a statement may modify; and the preupdate hook on the writer records what actually changed. Joins, views, CTEs, triggers, and cascades all work because SQLite is the one reporting.

Re-runs go through `selectIfChanged`, which compares a hash of the fresh result against the last emission and skips the decode entirely when nothing changed. That hash is computed in C inside the step loop — a −39% win over hashing in Dart, with no regression anywhere else [[075.1]]. The fold has resisted every attempt to improve it since: a wider 16-byte body is below noise at 4 KB cells, at 32 KB, and even on a single-stream 64 KB payload with pool parallelism removed to expose it [[110.1]] [[173.1]] [[181.1]]. That question is closed.

Dispatch had one real pathology and it was not where it appeared to be. A large parked-dispatcher signal looked like reader-pool starvation; it was over-dispatch upstream in the stream engine's flush queue, fixed by snapshotting worker availability once per flush and decrementing per pop [[120.1]]. After that, every measured stream workload reports zero parking.

What remains on the main isolate is worth naming precisely, because it is the next target if streams ever need more: the reader-reply port handler accounts for roughly 28% of burst wall on the heaviest overlap workload, while subscriber fan-out — the intuitive suspect — is under 1% [[136.1]]. On the writer side, SQLite-facing calls are a minority of burst wall; the residual request/response handling dominates [[147.1]].

Column-level dependency intersection is what makes wide-table streams viable: writing to a column no stream watches skips the re-query dispatch entirely, which shows up as a 3× throughput spread between disjoint and overlapping writes on a 50-stream benchmark.

## Held in reserve

Two mechanisms work and are deliberately unshipped.

Row-level dirty precision eliminated the keyed-primary-key miss path in prototype — intersection entries dropped from 10,000 to 3 and writer-burst wall halved — but it adds per-row state to the invalidation path for a benefit only that access shape sees [[134.1]].

Off-writer checkpointing showed a 53–64% improvement in first-crossing latency once its trigger policy was fixed; the storm that killed an earlier attempt turned out to be a re-arming bug rather than anything inherent to moving the work [[250.1]].

Both are recorded with their mechanisms intact, waiting for a workload that justifies the complexity rather than for someone to rediscover them.
