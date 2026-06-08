# Exp 145 - Stream flush inline dequeue

Date: 2026-06-08
Branch: `exp-145-stream-flush-inline-dequeue`
Outcome: Rejected

## Candidate

The tested patch replaced two Dart collection-helper paths in stream
re-query admission:

- `ReaderPool.availableWorkerCount`: `_workers.where((e) => e.isAvailable).length`
  -> manual loop.
- `StreamEngine._flushQueue`: `_requeryQueue.take(...).toList()` -> direct
  bounded dequeue loop.

The patch was reverted after measurement. No runtime code from exp 145 is
kept.

## Commands

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_concrete_pool_profile.dart --label=exp145-baseline
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_concrete_pool_profile.dart --label=exp145-candidate
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_concrete_pool_profile.dart --label=exp145-baseline-repeat
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_concrete_pool_profile.dart --label=exp145-candidate-repeat
```

## Wall Time

| workload | baseline 1 ms | baseline 2 ms | baseline median ms | candidate 1 ms | candidate 2 ms | candidate median ms | delta |
|---|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 51.41 | 80.57 | 65.99 | 55.22 | 48.40 | 51.81 | -21.5% |
| A11c disjoint | 56.21 | 64.47 | 60.34 | 61.05 | 58.62 | 59.84 | -0.8% |
| A11c overlap | 116.18 | 147.79 | 131.99 | 111.64 | 125.62 | 118.63 | -10.1% |
| keyed PK subscriptions | 25.06 | 24.79 | 24.93 | 23.85 | 32.06 | 27.96 | +12.2% |

For two-run medians, the table averages the two values after sorting.

## Counters

All baseline and candidate passes reported:

| workload | parked_total | wake_retry_total | max_parked |
|---|---:|---:|---:|
| A11c baseline | 0 | 0 | 0 |
| A11c disjoint | 0 | 0 | 0 |
| A11c overlap | 0 | 0 | 0 |
| keyed PK subscriptions | 0 | 0 | 0 |

Other invariant counters stayed at the expected workload shapes:

| workload | invalidate_count | intersection_entries | observed_hits |
|---|---:|---:|---:|
| A11c baseline | 0 | 0 | 0 |
| A11c disjoint | 500 | 25000 | 0 |
| A11c overlap | 500 | 25000 | 0 |
| keyed PK subscriptions | 200 | 10000 | 3 |

## Decision Read

The only direct stream-admission counter gate was already clean before the
patch. Wall time did not move consistently enough to justify carrying the
private implementation change: overlap improved on the two-run median, disjoint
was flat, and keyed-PK moved worse. Treat `_flushQueue` helper allocation as
below current signal unless an allocation profile names it directly.
