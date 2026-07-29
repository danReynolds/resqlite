---
component: readers
title: Reader pool
kicker: worker isolates
zone: workers
diagram: readers
directions: []
extraClaims: [120.1, 239.1, 244.1, 246.1, 236.1, 183.1, 174.1]
feeds: [native]
section: architecture
---

Reads run on a pool of two to four persistent worker isolates, each bound to its own read-only SQLite connection against the shared WAL. The pool exists to avoid a cost that is invisible until you look for it: spawning an isolate per query costs about 0.08 ms, which on small reads is most of the query. Keeping workers alive amortizes that to zero, and keeping the *C* state alive — connections, prepared-statement caches — means even a worker's death does not throw away the expensive parts.

Pool size is measured, not guessed: throughput plateaus at four workers, and going wider actively regresses stream-heavy workloads because each completed re-query queues another microtask ahead of pending writes.

## Dispatch, parking, and the lifecycle

Dispatch is round-robin with busy tracking. A worker is available when it is alive, has published its command port, and has no query in flight. When every worker is busy the caller parks on a FIFO waiter, and each worker-free event wakes exactly one — not a shared future every parked dispatcher observes, which is how a wake storm starts.

The interesting part of the lifecycle is what happens when a result is large enough to sacrifice. The worker calls `Isolate.exit` with the result, and its slot goes unavailable until a replacement isolate spawns, opens its connection, and publishes a new port. Both the payload and the exit notification arrive on the same port, so FIFO ordering guarantees the result is processed before the death is — which is what makes the whole scheme race-free rather than merely usually-correct.

## Why the respawn is affordable

The obvious worry is that sacrifice starves the pool: kill a quarter of your read capacity on every large result and queueing should get worse. It does not, and the measurement that settles it is a barrier burst — eight identical large reads released simultaneously against four workers, so four run and four park, with the pool torn down and rebuilt between bursts to keep each measurement independent.

The lane with sacrifice *disabled* had the highest parked queue-wait, roughly 19% worse [[244.1]]. The reason is mechanical: without sacrifice, the worker performs a full per-slot copy of the result before it can accept the next request, and that copy occupies the slot longer than an exit plus a respawn that overlaps with three other workers still serving. An eager-respawn variant — starting the replacement before completing the caller — measured inert, because the respawn was never on the parked caller's critical path.

Admission itself is clean. The historical parking signal that looked like pool pressure was over-dispatch upstream in the stream engine [[120.1]], and after that fix every measured workload reports zero parking.

## Memory, and the buffer that outlives the query

`selectBytes` writes its JSON into a per-reader native buffer that persists across queries — which is what makes the result a view rather than a copy [[174.1]]. That buffer only ever grew, so a single 8 MB read left 8 MB pinned per reader for the life of the connection, and a concurrent burst could pin 32 MB across the pool permanently.

The fix is a reclaim policy with an observable signal: buffers above a 1 MB cap shrink after a query whose result was small, and `Diagnostics.readerJsonBufHighWaterBytes` exposes the aggregate so any downstream user or benchmark can see it [[183.1]]. Tuning should raise the trigger before touching the guard — the guard is what prevents thrash under alternating large and small reads.

Large blob *cells* take the boundary's wrap route rather than the copy route, which is what stopped blob-heavy reads from sacrificing a reader on every call [[236.1]], and the sacrifice trigger itself now keys on slot count so text-heavy results stop misrouting into needless respawns [[246.1]].

## The opportunity we are not taking

Batching parked point-reads into pool-sharded envelopes measured 26–33% on bursts of twenty small reads, and sharding across the pool avoided the one-worker collapse that killed an earlier version of the idea [[239.1]]. It is not shipped. The gain is real but the mechanism adds a second dispatch path with its own capping and fairness rules, and the public API offers no way to ask for it — the honest position is that it waits for a workload that demands it rather than being adopted because it is available.
