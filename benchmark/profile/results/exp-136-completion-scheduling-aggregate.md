# Experiment 136 - Completion-side Scheduling Audit

Profile-mode harness: `benchmark/profile/completion_scheduling_audit.dart`

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`)

Wall-clock convention: `wall_ms` is writer-side burst wall — the stopwatch stops on the last write (same convention as exp 121). `drain_ms` is the post-burst drain (quiet-window) during which reader-pool replies finish landing on the main isolate. The completion-side counters are snapshotted AFTER the drain finishes — most reader-completion wall fires in the drain, not inside the burst.

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/completion_scheduling_audit.dart --markdown
```

## Counters

| workload | shape | wall_ms | drain_ms | total_ms | completion_us | completion_count | emit_us | emit_count | invalidate_us | parked_total | max_parked | emissions |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 0 streams x 500 writes | 71.16 | 0.00 | 71.16 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| A11c disjoint | 50 streams x 500 writes | 71.82 | 56.56 | 128.38 | 0 | 0 | 0 | 0 | 17816 | 0 | 0 | 0 |
| A11c overlap | 50 streams x 500 writes | 159.19 | 107.37 | 266.56 | 76154 | 4228 | 266 | 29 | 25724 | 0 | 0 | 29 |
| keyed PK subscriptions | 50 streams x 200 random writes | 37.44 | 407.17 | 444.60 | 18807 | 1108 | 59 | 3 | 5752 | 0 | 0 | 3 |

## Derived fractions

| workload | completion_us / burst | completion_us / total | emit_us / total | emit_us / completion_us | us per completion | us per emit | invalidate_us / burst |
|---|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 0.00% | 0.00% | 0.00% | 0.00% | 0.00 | 0.00 | 0.00% |
| A11c disjoint | 0.00% | 0.00% | 0.00% | 0.00% | 0.00 | 0.00 | 24.81% |
| A11c overlap | 47.84% | 28.57% | 0.10% | 0.35% | 18.01 | 9.17 | 16.16% |
| keyed PK subscriptions | 50.24% | 4.23% | 0.01% | 0.31% | 16.97 | 19.67 | 15.37% |

## Reading the table

- `completion_us` is the cumulative wall-clock microseconds spent in the main-isolate reader worker port handler synchronous body. Because `_WorkerSlot.request` uses `Completer<Object?>.sync()`, this captures the entire downstream `_dispatch` resume / `_requery` continuation / `entry.emit` / `_flushQueue` chain that runs synchronously inside the handler. Most of it fires in the post-burst drain, so the counter is snapshotted AFTER the quiet-window drain completes.
- `emit_us` is the sub-fraction spent inside `StreamEntry.emit` — the subscriber controller fanout loop. `emit_us / completion_us` reveals whether reader-completion wall is dominated by subscriber delivery (higher fraction = batching subscriber notifications is the candidate) or by hashing/dispatch (lower fraction = reader completion batching would not help much).
- `completion_us / burst` is the fraction of writer-side burst wall spent in main-isolate reader-completion handling that fires *inside* the burst. Compare to exp 121's `invalidate_us / wall_us` (writer-side, runs inside the writer-reply handler chain) — together they bound the observable in-burst main-isolate cost.
- `completion_us / total` is the fraction of total wall (burst + drain) spent in reader-completion handling. This is the proper denominator for "is reader-completion work a realistic optimization target?" — it asks how much of the main-isolate budget the completion-side path actually consumes.
- `us per completion` is the average synchronous wall added per reader-reply handler invocation. On stream workloads each re-query reply runs the chain once.
- `parked_total` and `max_parked` should both stay at zero post-exp-120, reproducing exp 120's acceptance signal as a sanity check.

## Interpretation

See `experiments/136-completion-microtask-counter.md` for the decision and follow-up notes attached to these numbers.
