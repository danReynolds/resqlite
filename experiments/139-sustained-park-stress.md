# Experiment 139: Sustained concurrent-reads parking stress

**Date:** 2026-06-03
**Status:** In Review
**Direction:** `stream-rerun-dispatch` `measurement-system`

## Problem

After [exp 118](118-fifo-dispatch-counter-gate.md) replaced the shared
`_workerAvailable` completer with a FIFO one-shot waiter queue,
[exp 115](115-dispatcher-park-counters.md)'s short-burst harness showed
`dispatcherWakeRetryTotal` drop to 0 at concurrency 8/16/32 (previously
6/66/378). [Exp 119](119-dispatch-pressure-audit.md) confirmed the same
on app-shaped streaming workloads, and [exp 120](120-flush-admit-bound.md)
+ [exp 122](122-concrete-reader-pool-stream-admission.md) drove
`dispatcherParkedTotal` to 0 on every measured stream workload by
fixing upstream over-dispatch.

`signals.json#stream-rerun-dispatch.openCandidates` carried one
remaining open question against this body of work (added 2026-04-30,
addedAfter exp 115): a **long-running concurrent-reads workload that
sustains parked dispatchers past pool size**. Exp 114's archive
future-notes asked the same thing: dispatch-internal optimization can
only be re-evaluated against a workload that exercises the parked-
dispatcher path. The short-burst exp 115 harness fires `concurrency`
queries, awaits all of them through `Future.wait`, then resets counters
between bursts — it cannot distinguish "FIFO holds for one burst" from
"FIFO holds when the waiter queue is continuously refilled across many
wake/admit cycles while late lanes overlap early lanes' completions."

## Hypothesis

If FIFO's one-shot waiter invariant has a leak that only surfaces with
sustained refill — for example, a missed handoff when slot release
order does not match the lane launch order — then `wake_retry_total`
will become non-zero under continuous pressure, even though it stays
at 0 for short bursts. If the invariant holds, `wake_retry_total`
stays at 0 across a full pass and the open candidate is closed.

## Approach

New profile harness
`benchmark/profile/sustained_concurrent_reads_profile.dart`. For each
sweep concurrency `N`, run `N` lanes, each looping:

```
while (sw.elapsedMilliseconds < durationMs) await db.select(...);
```

As one lane's query completes, the same lane awaits the next one. At
any instant ~`N` queries are in flight; the pool's FIFO waiter queue
is continuously refilled rather than barriering through `Future.wait`.

Half the lanes run a 1k-row range scan (`SELECT v FROM items WHERE
v >= 0 AND v < 1000`), the other half run a single-row point query
(`SELECT id FROM items WHERE id = ?`). The two query costs differ by
~15× so worker slot release order does not match lane launch order —
the ordering condition FIFO has to handle correctly.

5 passes per concurrency level after 2 warmup passes; default
`durationMs = 1000`, sweep `concurrencies = [4, 8, 16, 32]` against a
reader pool of 4.

## Results

Two repeated passes; medians across the per-pass 5-pass medians shown.
Reader pool: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`).

| concurrency | parked_total | wake_retry_total | max_parked | completed | wall_ms |
|---:|---:|---:|---:|---:|---:|
| 4 | 0 | 0 | 0 | 118k–121k | 1000 |
| 8 | 96k–97k | **0** | 4 | 96k–97k | 1000 |
| 16 | 88k–89k | **0** | 12 | 88k–88k | 1000 |
| 32 | 84k | **0** | 28 | 84k | 1000 |

Full per-pass aggregate at
[`benchmark/profile/results/exp-139-sustained-park-aggregate.md`](../benchmark/profile/results/exp-139-sustained-park-aggregate.md).

Key readings:

- **`wake_retry_total = 0` at every concurrency**, across 80k–97k park
  events per pass at sustained pressure. FIFO's one-shot waiter
  invariant holds under continuously-refilled queues and out-of-order
  slot release.
- **`max_parked = concurrency - pool_size`** exactly: 4 / 12 / 28 for
  concurrency 8 / 16 / 32. Steady-state queue depth is determined by
  the overflow, not by any wake amplification or scheduling thrash.
- **`parked_total` scales linearly with overflow throughput**, not
  superlinearly with concurrency — every overflow query parks exactly
  once before being admitted.
- **Completed throughput is bounded by the pool**, dropping slightly
  from concurrency 8 (~96k) to 32 (~84k) as per-query park/admit work
  becomes a larger fraction of the wall.

## Decision

**In Review — measurement.** The open candidate
"long-running concurrent-reads workload that sustains parked
dispatchers past pool size" is closed. FIFO from exp 118 holds under
sustained pressure with the same `wake_retry_total = 0` signal the
short-burst harness reported.

The harness is the durable contribution: future reader-pool dispatch
ideas (slot handoff, work-stealing, exp 114-style reawakening) must
show measurable headroom against it, because the short-burst exp 115
harness will not surface a sustained-pressure regression on its own.

## Future Notes

A dispatch-internal optimization is worth implementing only if a
workload appears where:

- `dispatcherWakeRetryTotal > 0` on either exp 115 (short burst) or
  exp 139 (sustained), or
- `dispatcherMaxParkedConcurrent` materially exceeds `concurrency -
  readerCount`, signalling a leak in the in-flight bookkeeping, or
- this harness shows a wall-time regression under FIFO that an
  alternative dispatch policy reverses without changing
  `parked_total` magnitude.

Without one of those signals, the parked-dispatcher path is not the
active target. Exp 134's note about row-level keyed-PK precision (and
its rejection because of fragile SQL recognition) still stands as the
adjacent next direction inside `stream-rerun-dispatch`.
