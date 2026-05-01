# Experiment 115: Dispatcher park counters for ReaderPool

**Date:** 2026-05-01
**Status:** Accepted
**Direction:** `stream-rerun-dispatch`, `measurement-system`

## Problem

[Exp 105](105-reader-pool-sizing.md) (raise pool cap 4→8, rejected) and
[exp 114](114-fifo-waiter-queue.md) (FIFO waiter queue, rejected after the
exp 106 rebase) both targeted the parked-dispatcher path inside
`ReaderPool._dispatch`. Both rejections rested on indirect evidence: a
benchmark either didn't move (114) or moved in the wrong direction (105),
and we inferred *why* from architectural reasoning. Neither experiment
could check whether the parked-dispatcher path was even being exercised
by the workload that produced the wall-time number.

The signals.json next-signal list for entry 114 calls this gap out
explicitly:

> a profile-mode counter that records parked-dispatcher events per
> worker-free transition, so the wake-amplification cost can be measured
> directly without needing wall-time-visible workloads

Until that counter exists, every future dispatch-area experiment will
reproduce the exp 114 evaluation gap: a structurally sound change (e.g.
slot handoff, FIFO swap, late-dispatch generation stamp) whose acceptance
or rejection rests on a wall-time delta against a workload whose actual
parking behavior is unobserved. The closest analogue is
[exp 099](099-fnv-8byte-bytestream.md) — a structurally sound change that
measured flat because the benchmark didn't run the path it targeted, and
[exp 110](110-long-text-fnv-8byte.md) only became evaluable after the
missing benchmark shipped.

## Hypothesis

A small set of profile-mode counters around the `_workerAvailable`
park/wake path will make dispatcher contention directly observable
without changing dispatch behavior. Specifically, three counters will
suffice:

- **park count** — total times a dispatcher entered `await _workerAvailable.future`
- **wake-retry count** — total times a wake resumed but found no slot
  on the next scan and re-parked
- **max parked concurrent** — peak observed concurrency of parked
  dispatchers

The wake-retry / park ratio is the wake-amplification signal: with the
current shared-completer design, every worker-free event wakes every
parked dispatcher and exactly one wins, so under sustained parking the
ratio approaches `(N-1)/N`. A FIFO or slot-handoff design should drive
it toward zero. `max parked concurrent` reports whether a workload
sustains the parking precondition at all — a peak ≤ pool size means
dispatch-internal optimizations are benchmark-invisible regardless of
their structural merit.

Acceptance criteria:

- Counters added under `kProfileMode` so release builds tree-shake them
  to zero overhead (verified by running the harness with and without
  `-DRESQLITE_PROFILE=true`).
- A focused profile harness produces non-zero counter values on a
  workload that genuinely backpressures the pool, and zero values on
  workloads inside pool capacity.

## Approach

`lib/src/profile_counters.dart` — three new counters with snapshot/diff/
reset support, plus an internal `dispatcherCurrentParked` running gauge
used to maintain `dispatcherMaxParkedConcurrent`. All increments happen
on the main isolate where `ReaderPool._dispatch` runs, so static counter
state needs no cross-isolate protocol (same convention as the existing
`invalidateUs` / `intersectionUs` counters from the A11c profile work).

`lib/src/reader/reader_pool.dart` — `_dispatch` increments under
`if (kProfileMode)`:

- before the `await _workerAvailable!.future`: increment park-total,
  bump current-parked, update max-parked
- after the `await` (in `finally`): decrement current-parked
- on the next iteration of the outer `while`, before the park branch:
  if we previously parked once already, the scan that just failed was a
  spurious-wake retry — increment wake-retry-total

The `kProfileMode` const folds to `false` in normal builds, so the
compiler eliminates every increment. Verified by running the harness
without `-DRESQLITE_PROFILE=true`: every counter stays at zero across
all concurrency levels.

`benchmark/profile/dispatcher_park_profile.dart` — a small harness that
fans out `db.select` at increasing concurrency levels, snapshots the
counters per burst, and prints / writes a markdown table. Pool size is
the production default (`(numProcessors - 1).clamp(2, 4)` — see
[exp 105](105-reader-pool-sizing.md)).

## Results

Profile-mode harness output on a 4-worker pool, 5 bursts × 6 concurrency
levels (full table:
[`benchmark/profile/results/exp-115-dispatcher-park-aggregate.md`](../benchmark/profile/results/exp-115-dispatcher-park-aggregate.md)):

| concurrency | parked_total | wake_retry_total | max_parked | wall_ms |
|---:|---:|---:|---:|---:|
| 1 | 0 | 0 | 0 | 0.09 |
| 2 | 0 | 0 | 0 | 0.13 |
| 4 | 0 | 0 | 0 | 0.18 |
| 8 | 10 | 6 | 4 | 0.39 |
| 16 | 78 | 66 | 12 | 0.77 |
| 32 | 406 | 378 | 28 | 1.45 |

Three things confirmed:

1. **Park threshold matches pool size.** Concurrency ≤ 4 produces zero
   park events. Counters fire only when callers exceed the pool — the
   precondition for any reader-pool-internal dispatch optimization.
2. **`max_parked` matches `concurrency − pool_size`** at every level
   (4, 12, 28). The peak concurrency gauge tracks correctly.
3. **Wake-retry / park ratio approaches `(N-1)/N`** as concurrency
   grows: 60 % at c=8, 85 % at c=16, 93 % at c=32. This is the direct
   quantitative signal of the wake-amplification cost
   [exp 114](114-fifo-waiter-queue.md) targeted — a single
   `_notifyAvailable()` wakes every parked dispatcher, exactly one wins
   the freed slot, and the rest re-park. Each worker-free event under
   sustained parking now produces a measurable retry burst.

Release-build verification: running the harness without
`-DRESQLITE_PROFILE=true` produces all zeros at every concurrency level,
confirming the `if (kProfileMode)` gates tree-shake the increments out
of normal builds.

## Decision

**Accepted — measurement-only contribution.** The counters add no
production overhead and unblock the next round of dispatch-area
experiments by making the parked-dispatcher path directly observable.

What this changes for future dispatch experiments:

- **exp 114-style FIFO / slot-handoff.** A re-evaluation can now require
  `dispatcherWakeRetryTotal > 0` on the workload before claiming or
  rejecting a wall-time delta. If a benchmark has zero retries, the
  change cannot have produced a signal — same lesson as exp 099 / exp
  110, applied earlier in the loop.
- **exp 105-style pool sizing.** The `dispatcherMaxParkedConcurrent`
  gauge tells you whether a workload would benefit from more workers
  before you change the cap.
- **exp 083 pre-dispatch queue.** The retry counter quantifies the
  contention the pre-dispatch queue is meant to coalesce.

## Future Notes

The retry counter assumes the current shared-completer wake mechanism
in `ReaderPool._dispatch`. If a future experiment changes the wake
scheme (e.g. one-shot waiters, slot handoff) the increment site needs
to move with it — a change that drives `dispatcherWakeRetryTotal` to
zero by construction is exactly the win we want to measure. Keep the
counter; don't delete it when the implementation changes.

The harness (`benchmark/profile/dispatcher_park_profile.dart`) drives
synthetic burst loads. Real workloads (concurrent reads under a writer,
A11c stream fan-out post-exp-106 elision, etc.) should also be profiled
through this counter set before the next dispatch experiment chooses
its target.
