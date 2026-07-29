---
component: writer
title: Writer · binding & batching
kicker: worker isolate
zone: workers
diagram: writer
directions: [parameter-encoding-and-binding]
feeds: [tx, native]
section: architecture
---

SQLite permits one writer at a time. Rather than fight that with locking schemes, resqlite embraces it: every write in the process routes through a single persistent writer isolate that owns the write connection, processes messages sequentially, and holds transaction state across them. Serialization is not a bottleneck imposed on the design — it is the design, and the optimization work happens *inside* the serial path rather than trying to escape it.

Three public shapes reach it. `execute` sends one statement. `executeBatch` sends one statement with many parameter sets and runs the entire matrix inside C. `transaction` opens an interactive session where the callback runs on main and each statement round-trips.

## Binding without allocating

Parameter encoding is where most of the writer's measured wins live, and they share one shape: remove an intermediate Dart allocation by writing UTF-8 payloads straight into the native arena.

The batch path went first. A guarded ASCII fast path removed a per-string allocation across wide batches [[125.1]], and the follow-up extended the same treatment to non-ASCII by writing UTF-8 directly with private surrogate-pair handling — worth 13.5% on Unicode and 27.8% on emoji at 10k×20 [[126.1]]. Embedded NULs survive correctly because byte lengths are preserved through the bind rather than inferred.

The single-row path followed once a workload existed to show it mattered. Below tens of kilobytes the difference is noise; from 16 KB upward it is 15–32% for ASCII [[186.1]] and 31–39% for CJK [[187.1]]. That gap between "the encoder is faster" and "the workload notices" is worth naming — an earlier version of this change was rejected precisely because only a micro-benchmark could see it, and it was reopened when the right workload was built.

## Blobs, aliasing, and coalescing

Large blob parameters take the boundary's wrap route: one copy into external memory, then an ownership move instead of a graph copy [[234.1]].

Wrapping is identity-keyed, and that detail is load-bearing rather than an optimization. The graph copier preserves object identity — pass the same buffer to two positions and it is copied once and aliased twice. Naive per-occurrence wrapping broke that property, duplicating one buffer into N external copies and making the wrapped path *worse* than the copy it replaced. Keying wrappers by buffer identity across the whole message envelope restores it, so a blob reused across the writes of a coalesced group crosses exactly once [[243.1]].

Concurrent standalone writes coalesce into a single envelope per round trip. That is why the identity table has to span the envelope rather than a single statement — the reuse case it exists for is precisely a caller looping `execute` with the same buffer.

Batch blobs deliberately do **not** wrap. Measured on a blob-heavy `executeBatch`, wrapping regressed: the win depends on many independent round-trips each parking a fresh allocation while the writer is mid-step, and a batch has one round trip [[237.1]]. The absence of wrapping there is a decision with evidence behind it, not an oversight.

## Dirty tracking rides along

The writer connection installs SQLite's preupdate hook, so every insert, update, and delete records its table into a deduplicated set that returns *with the write response*. There is no separate notification channel and no polling — stream invalidation is a field on a reply the caller was already waiting for. Inside a transaction the set accumulates and returns at commit; a rollback discards it without waking anything.
