---
component: readers
title: Reader pool
kicker: worker isolates
zone: workers
order: 3
directions: []
extraClaims: [120.1, 239.1, 244.1, 246.1, 236.1, 183.1]
---

Reads run on up to four persistent worker isolates, each owning its own SQLite read connection against the shared WAL. Dispatch is round-robin with busy tracking; callers park only when every worker is occupied, and a worker that hands off a large result via Isolate.exit is replaced in the background.

## Why the lifecycle is safe

The pool’s design question was always whether sacrifice starves it. Measured at production size with a barrier burst, the opposite holds: the lane with sacrifice disabled queued longest, because send’s per-slot copy occupies a worker longer than an exit plus an overlapped respawn — and starting the respawn earlier changes nothing, since it is off the parked caller’s critical path [[244.1]]. Admission itself is clean; the historical parking signal was upstream over-dispatch, not pool pressure [[120.1]]. Memory is bounded and observable: each reader’s native JSON buffer reclaims above a high-water cap, exposed through diagnostics [[183.1]].

One real opportunity stays on the shelf: batching parked point-reads into pool-sharded envelopes measured ~25–30% on bursts of twenty, but ships complexity the API does not yet need [[239.1]].
