# Exp 244 — pool-burst replacement capacity + eager respawn (rejected)

Harness: `benchmark/experiments/pool_burst_eager_respawn.dart`. Apple M1 Pro.
Production 4-worker pool; 8 identical large (sacrificing) selects behind a
barrier per burst; queue-wait = assignedAt − enqueuedAt from
`ReaderPool.debugDispatchTimings` (decode-free). Pool reset (DB reopened) between
bursts. 40 bursts × 3 reps per lane.

Lanes: `send` = `-DRESQLITE_SACRIFICE_THRESHOLD=1099511627776`;
`sacrifice-current` = default; `sacrifice-eager` = eager-respawn prototype
(reverted — re-apply the reorder in `_WorkerSlot`'s sacrifice branch to reproduce).

Parked (requests 5–8) queue-wait, median µs per rep:

| lane | rep1 | rep2 | rep3 | median |
|---|---:|---:|---:|---:|
| send | 3175 | 3243 | 3044 | 3175 |
| sacrifice-current | 2456 | 2738 | 2652 | 2652 |
| sacrifice-eager | 2753 | 2684 | 2393 | 2684 |

Parked p95 / p99 (representative, µs): current ~7.3k / ~20–22k; send ~5–8k /
~19–23k; eager ~4.6–8.7k / ~22–45k (noisier tail). Immediate (unparked) queue-wait
~0 in every burst (confirms the 4-worker barrier).

Burst makespan, median µs: send ~7362 (noisy), sacrifice-current ~6732,
sacrifice-eager ~6522.

Findings: (1) `send` has the HIGHEST parked queue-wait in all 3 reps (~+500 µs /
+19% over sacrifice) — the large-result graph copy blocks the worker longer than
Isolate.exit + overlapped respawn, so sacrifice is neutral-to-favorable at pool-4;
(2) sacrifice-eager ≡ sacrifice-current (~1%, within margin) — eager respawn buys
nothing. Rejected — see `experiments/244-pool-burst-eager-respawn.md`.
