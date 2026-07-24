# Experiment 244: Pool-burst measurement of sacrifice replacement capacity, and eager respawn (rejected)

**Date:** 2026-07-22
**Status:** Rejected
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused pool-burst harness
  [`benchmark/experiments/pool_burst_eager_respawn.dart`](../benchmark/experiments/pool_burst_eager_respawn.dart);
  raw table in
  [`benchmark/results/2026-07-22-exp244-pool-burst.md`](../benchmark/results/2026-07-22-exp244-pool-burst.md).

## Problem

[Exp 241](241-sacrifice-reeval.md) tried to resolve send-vs-sacrifice with one
through-the-pool A/B and got a confounded, sign-unstable result. Peer review
(2026-07-22) diagnosed the cause — send-vs-exit is several distinct *estimands*
(intrinsic transfer, pool-replacement capacity, decode) that no single harness
can isolate — and recommended splitting the question. **This is Experiment B of
that split: the pool-replacement-capacity estimand.** Does sacrifice's reader
respawn temporarily remove too much service capacity, and if so, is that a
fixable lifecycle-ordering artifact?

A **confirmed code asymmetry** motivated a specific fix candidate. In
`ReaderPool._WorkerSlot`'s reply handler, the non-sacrifice branch calls
`_notifyPool()` **before** `pending.complete(result)` (deliberately — make
capacity available before the caller asks for more), but the sacrifice branch
does the opposite: it completes first and starts the replacement
(`unawaited(spawn(...))`) after. Because `_pendingCompleter` is a
`Completer.sync()`, `complete()` runs the whole `_dispatch`/`_requery`/
`entry.emit`/`_flushQueue` chain synchronously *before* the replacement is even
initiated. So the replacement launch is delayed by arbitrary caller work — an
**eager respawn** (spawn before completing) might close whatever capacity gap
that opens.

## Hypothesis

If the respawn gap depletes pool capacity, parked requests should see higher
**dispatch queue-wait** under sacrifice than under send, and eager respawn should
recover it.

## Approach

The pool has a clean observable the peer identified — **dispatch queue-wait**
(`workerAssignedAt - requestEnqueuedAt`) — that SQLite decode cannot contaminate.
A benchmark-only `ReaderPool.debugDispatchTimings` collector (null in production;
`_dispatch` appends `[enqueuedAtUs, assignedAtUs]` per request) exposes it.

The decisive test (peer-designed): a production **4-worker** pool; per burst,
fire **8** identical large (sacrificing) selects behind a barrier — requests 1–4
grab the four workers, 5–8 park — and measure queue-wait for the parked four. The
first four do equivalent decode work; the difference the parked four see is almost
entirely whether their predecessor's slot became reusable immediately (send) or
after a respawn gap (sacrifice). The pool is **reset (DB reopened) between
bursts**, so the treatment unit is a fresh pool lifecycle, not an individual query
in a mutating pool (exp 241's confound). 40 bursts × 3 reps per lane.

Three lanes, one process each:

- **send** — `RESQLITE_SACRIFICE_THRESHOLD` set above every result (never
  sacrifices): the no-replacement baseline.
- **sacrifice-current** — shipped behavior.
- **sacrifice-eager** — the eager-respawn prototype (start the replacement before
  the synchronous completion chain, with a `_closed`/generation recheck so a
  replacement in flight when the pool closes retires itself). **Reverted** on this
  branch; its numbers are recorded here.

## Results

Parked queue-wait, median µs per rep (40 bursts each), Apple M1 Pro:

| lane | rep1 | rep2 | rep3 | median | vs send |
|---|---:|---:|---:|---:|---:|
| send (no sacrifice) | 3175 | 3243 | 3044 | **3175** | — |
| sacrifice-current | 2456 | 2738 | 2652 | **2652** | −16% |
| sacrifice-eager | 2753 | 2684 | 2393 | **2684** | −15% |

Makespan (whole 8-request burst), median µs: send ~7362 (noisy), current ~6732,
eager ~6522 — same ordering. The four "immediate" (unparked) requests measured
~0 µs queue-wait in every burst, confirming the 4-worker barrier.

Two reproducible findings, both counter to the hypothesis:

1. **No capacity hole — sacrifice is mildly *favorable* at pool-4.** The **send**
   lane has the *highest* parked queue-wait (highest in all three reps, ~+500 µs /
   +19% over the sacrifice lanes). Forcing no-sacrifice means a large result's
   `SendPort` graph copy runs on the worker before it can take the next request,
   and that blocks the slot *longer* than `Isolate.exit` plus an overlapped
   respawn. So at the production pool size, sacrifice does not deplete capacity; it
   frees the slot sooner than the alternative.

2. **Eager respawn buys nothing.** sacrifice-eager (2684) and sacrifice-current
   (2652) are equivalent — a 32 µs / ~1% difference, well inside any
   pre-registered margin (±5% / ±100 µs), on both queue-wait and makespan. At
   pool-4 the respawn overlaps other workers' in-flight queries and is not on the
   parked request's critical path, so moving the spawn a few synchronous lines
   earlier changes nothing observable. The lifecycle asymmetry is real in the
   code; its effect on pool capacity is not.

**Caveat.** Pool-4 overlap dilutes the per-sacrifice respawn gap (a parked request
waits on some busy worker's ~ms query completion regardless of lane, and the
respawn hides within that). The peer's pool-size-1 "diagnostic ceiling" would
expose the raw gap, but `Database.open` clamps `readerCount` to a minimum of 2,
so it isn't reachable through the public API. Pool-4 is the regime the production
decision rests on, and the direction there is unambiguous.

## Outcome

**Rejected: eager respawn.** It provides no measurable benefit at the production
pool size, so the lifecycle-ordering asymmetry — though real — is not worth a
reorder plus the close/generation-safety surface it would add. More importantly,
this **falsifies the suspected pool-capacity penalty** that motivated
re-examining sacrifice: at pool-4, sacrifice is neutral-to-favorable, not harmful.
That removes pool capacity from the send-vs-sacrifice debate and turns exp 241's
hand-wavy "keep sacrifice" into a measured result for the pool regime.

Kept: the reusable `debugDispatchTimings` queue-wait instrument (benchmark-only,
null in production) and the `RESQLITE_SACRIFICE_THRESHOLD` knob — both reused by
this harness and future pool experiments. Still open from the exp 241 split:
**Experiment A** (prepared-result, process-isolated handoff) for the *intrinsic*
transfer estimand, and the **text/shared-leaf misroute** guard. Would revisit
eager respawn only if a future change made the completion chain heavy enough to
matter, or if a pool-size-1 path exposed a raw respawn gap the pool-4 overlap
hides here.
