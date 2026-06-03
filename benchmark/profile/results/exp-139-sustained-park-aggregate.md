# Experiment 139 — Sustained concurrent-reads parking

Profile-mode harness: `benchmark/profile/sustained_concurrent_reads_profile.dart`

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`)
Passes per concurrency level: 5 (after 2 warmup), sustained 1000 ms each

Workload: each of `concurrency` lanes runs `while (deadline not reached) await select();`. Even-indexed lanes fire a 1k-row range scan; odd-indexed lanes fire a single-row point query. As one query completes the same lane awaits the next, so the pool waiter queue is continuously refilled instead of barriering through `Future.wait` between bursts.

| concurrency | parked_total | wake_retry_total | max_parked | completed | wall_ms |
|---:|---:|---:|---:|---:|---:|
| 4 | 0 | 0 | 0 | 121071 | 1000.05 |
| 8 | 96953 | 0 | 4 | 96957 | 1000.10 |
| 16 | 88539 | 0 | 12 | 88543 | 1000.20 |
| 32 | 84293 | 0 | 28 | 84297 | 1000.36 |

## Reading the table

- `parked_total` accumulates over the whole sustained pass, so absolute values are durationMs-dependent. Compare ratios and growth shape across concurrency rather than raw counts.
- `wake_retry_total` is the load-bearing column. Exp 118 (FIFO one-shot waiters) drove this to zero on short bursts; the open question for exp 139 was whether the invariant survives continuously-refilled waiter queues and out-of-order slot release. Any non-zero value here would surface a leak the short-burst exp 115 harness cannot see.
- `max_parked` is the peak observed parking depth. With the lane pattern, in-flight count is bounded by `concurrency`; at concurrency above the pool size the steady-state queue depth is roughly `concurrency - readerCount`.
- `completed` is total queries finished during the pass; it is a throughput proxy that scales with concurrency up to the pool size, then plateaus (SQLite serializes work across the worker pool).

## What this enables

Closes the `long-running concurrent-reads workload that sustains parked dispatchers past pool size` open candidate in `signals.json#stream-rerun-dispatch`. If a future reader-pool dispatch idea (slot handoff, work-stealing, exp 114-style reawakening) needs to show measurable headroom, run it against this harness and compare `parked_total`, `wake_retry_total`, and wall_ms — the short-burst exp 115 harness will not surface sustained-pressure regressions.
