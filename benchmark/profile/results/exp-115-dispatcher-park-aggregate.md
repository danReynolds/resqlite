# Experiment 115 — Dispatcher Park Counters

Profile-mode harness: `benchmark/profile/dispatcher_park_profile.dart`

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`)
Bursts per concurrency level: 5 (after 2 warmup)

Workload: `SELECT v FROM items WHERE v >= ? AND v < ?` fanned out at the listed concurrency. Each burst awaits all queries; counters are reset between bursts and the median for each reported column is taken across bursts.

| concurrency | parked_total | wake_retry_total | max_parked | wall_ms |
|---:|---:|---:|---:|---:|
| 1 | 0 | 0 | 0 | 0.17 |
| 2 | 0 | 0 | 0 | 0.13 |
| 4 | 0 | 0 | 0 | 0.19 |
| 8 | 10 | 6 | 4 | 0.33 |
| 16 | 78 | 66 | 12 | 0.62 |
| 32 | 406 | 378 | 28 | 1.35 |

## Reading the table

- `parked_total` increments each time `_dispatch` awaits `_workerAvailable` after finding no worker currently available for dispatch.
- `wake_retry_total` increments when the dispatcher resumes from `await` but finds no slot on the next scan and re-parks. With the current shared-completer wakeup, a single worker-free event wakes every parked dispatcher; exactly one wins the slot and the rest re-park, so this counter is the wake-amplification signal.
- `max_parked` is the peak observed concurrency of parked dispatchers across the burst. A peak above the pool size is the precondition for any reader-pool-internal dispatch optimization (exp 114-style FIFO swap, slot handoff) to be measurable.

## What this enables

Future dispatch-area experiments (exp 114 archive, exp 083 pre-dispatch queue, slot-handoff variants) can now be evaluated against direct evidence that the parked-dispatcher path was exercised, instead of inferring it from a wall-time delta on a workload that may not even reach `_workerAvailable`.
