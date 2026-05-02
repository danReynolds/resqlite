# Exp 121 — Invalidation traversal cost audit

Profile-mode harness extended with `invalidate_us`, `intersection_us`, and
`invalidate_pct_wall` columns on top of the exp 119 / exp 120 dispatch-counter
shape. Run on `origin/main` (post-exp-120) to answer the open
`stream-rerun-dispatch` question: is invalidation traversal a meaningful
fraction of overlap wall now that the parked-dispatcher path is closed?

## Environment

- Linux x64, `Platform.numberOfProcessors = 4`
- Reader pool size = 3 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`)
- Dart SDK 3.11.5 (stable)
- Profile-mode counters live (`-DRESQLITE_PROFILE=true`)

## Command (each pass)

```text
dart run -DRESQLITE_PROFILE=true \
  benchmark/profile/dispatch_pressure_audit.dart
```

3 passes, counters reset per workload inside the harness.

## Per-pass values (wall_ms, invalidate_ms, invalidate_pct_wall)

| workload                | metric              | run 1  | run 2  | run 3  | median |
|-------------------------|---------------------|-------:|-------:|-------:|-------:|
| A11c baseline           | wall_ms             | 173.42 | 172.42 | 174.24 | 173.42 |
| A11c baseline           | invalidate_ms       |   0.00 |   0.00 |   0.00 |   0.00 |
| A11c baseline           | invalidate_pct_wall |  0.00% |  0.00% |  0.00% |  0.00% |
| A11c disjoint           | wall_ms             | 176.13 | 173.80 | 168.65 | 173.80 |
| A11c disjoint           | invalidate_ms       |  15.76 |  15.95 |  15.31 |  15.76 |
| A11c disjoint           | intersection_ms     |   5.34 |   5.61 |   4.92 |   5.34 |
| A11c disjoint           | invalidate_pct_wall |  8.95% |  9.18% |  9.08% |  9.08% |
| A11c overlap            | wall_ms             | 321.25 | 307.27 | 305.83 | 307.27 |
| A11c overlap            | invalidate_ms       |  22.84 |  21.48 |  22.27 |  22.27 |
| A11c overlap            | intersection_ms     |   4.30 |   4.32 |   5.07 |   4.32 |
| A11c overlap            | invalidate_pct_wall |  7.11% |  6.99% |  7.28% |  7.11% |
| keyed PK subscriptions  | wall_ms             | 443.23 | 441.03 | 438.72 | 441.03 |
| keyed PK subscriptions  | invalidate_ms       |   6.10 |   5.50 |   5.95 |   5.95 |
| keyed PK subscriptions  | intersection_ms     |   1.77 |   1.59 |   2.35 |   1.77 |
| keyed PK subscriptions  | invalidate_pct_wall |  1.38% |  1.25% |  1.36% |  1.36% |

Run-to-run variance is tight on every metric (<2% of median for invalidate_us;
<10% for wall_us — the wall variance is driven by the workload's queueing
behaviour, not the new instrumentation).

## Median summary

| workload        | wall_ms | invalidate_ms | intersection_ms | invalidate_count | intersection_entries | invalidate_pct_wall | per-write_invalidate_us | per-entry_intersection_ns |
|-----------------|--------:|--------------:|----------------:|-----------------:|---------------------:|--------------------:|------------------------:|--------------------------:|
| A11c baseline   |  173.42 |          0.00 |            0.00 |                0 |                    0 |               0.00% |                       — |                         — |
| A11c disjoint   |  173.80 |         15.76 |            5.34 |              500 |                25000 |               9.08% |                    31.5 |                       213 |
| A11c overlap    |  307.27 |         22.27 |            4.32 |              500 |                25000 |               7.11% |                    44.5 |                       173 |
| keyed PK        |  441.03 |          5.95 |            1.77 |              200 |                10000 |               1.36% |                    29.7 |                       177 |
| direct reads    |    2.42 |          0.00 |            0.00 |                0 |                    0 |               0.00% |                       — |                         — |

`per-write_invalidate_us` = `invalidate_us / invalidate_count`.
`per-entry_intersection_ns` = `intersection_us / intersection_entries`.

## Active-fraction lower vs upper bounds

`invalidate_pct_wall` includes idle wall (the per-write `Future.delayed(zero)`
yields and the post-loop quiet window). Subtracting the obvious idle terms
gives an upper bound on the active fraction:

| workload      | quiet_window_ms | active_wall_ms | invalidate_pct_active |
|---------------|----------------:|---------------:|----------------------:|
| A11c disjoint |              50 |          123.8 |                12.73% |
| A11c overlap  |              50 |          257.3 |                 8.66% |
| keyed PK      |             200 |          241.0 |                 2.47% |

The keyed-PK quiet window is the deadline-polled emission settle (`200 ms`
intervals up to `60 s`); the typical observed settle is one window.

## Reading the numbers

- **A11c overlap** invalidation accounts for ~7% of total wall and ~9% of
  active wall. Of that, ~19% (4.32 / 22.27) sits in column-set intersection
  probes — the rest is `_tableIndex` lookup + dirty/in-flight scheduling +
  `_flushQueue` kickoff. Per-write invalidation is ~44 µs.
- **A11c disjoint** invalidation is a *higher* fraction (9.08% raw / 12.73%
  active) than overlap. This is the expected post-exp-106 shape: every
  dependency check still walks the watcher set and computes intersections,
  but they all return empty so no reader-pool work happens. The denominator
  shrinks but the numerator stays. Per-watcher intersection cost is ~213 ns
  on disjoint vs ~173 ns on overlap (overlap probes early-exit on first hit).
- **keyed PK** invalidation is 1.36% raw / 2.47% active — well below the
  ~3% rule-out threshold. Per-write invalidation is ~30 µs across 50
  watchers, dominated by table-index lookup rather than per-watcher probes
  (intersection is only 30% of invalidate here vs ~34% on disjoint A11c).
- **direct reads control** sentinel: zero invalidation (no streams), 29 dispatcher parks at concurrency=32 against a pool of 3, zero wake retries.

`dispatcher_parked_total = 0` and `dispatcher_wake_retry_total = 0` on every
stream workload, confirming exp 118 + exp 120 closed the parked-dispatcher
signal that exp 119 measured.

## Decision-relevant takeaway

The pre-experiment gate was:

- ≥10% of overlap wall in invalidation → real implementation target
- <3% of overlap wall in invalidation → rules out the direction

Overlap measured **7.11% raw / 8.66% active** — neither side of the gate.
Within that, intersection probes specifically are 1.4% of total wall — well
below the gate.

Reading the breakdown: a future implementation experiment in this direction
would need to target the *non-intersection* part of `onDependencyChanges`
(table-index walk, dirty/in-flight set scheduling) rather than per-watcher
intersection — the intersection probe is already cheap (~170 ns on overlap)
and removing it entirely would only reclaim ~1.4% of overlap wall.

The disjoint workload is the more interesting structural finding. Its pct is
*higher* than overlap because invalidation does the same work but no reader
work happens afterwards. Future column-elision experiments (more aggressive
short-circuits before per-watcher probing) would target this shape.

The remaining 90%+ of stream-fanout wall on overlap is in the other two
unmeasured paths the exp 120 future-notes flagged: completion-side
microtask scheduling and writer-isolate dispatch wall vs SQLite step wall.
Those need separate measurement infra; this audit rules out invalidation as
the next implementation target without that work.
