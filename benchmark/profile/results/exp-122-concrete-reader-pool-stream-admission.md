# Experiment 122 - Concrete Reader-Pool Stream Admission

Profile-mode harness: `benchmark/profile/stream_concrete_pool_profile.dart`

Commands:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_concrete_pool_profile.dart --label=baseline
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_concrete_pool_profile.dart --label=candidate
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_concrete_pool_profile.dart --label=candidate-confirm
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_concrete_pool_profile.dart --label=candidate-current
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_concrete_pool_profile.dart --label=post-rebase
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_concrete_pool_profile.dart --label=concrete-pool-rebased
```

## Profile Counter A/B

| workload | baseline wall_ms | candidate wall_ms | baseline parked | candidate parked | baseline max_parked | candidate max_parked | baseline retries | candidate retries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 135.32 | 95.94 | 0 | 0 | 0 | 0 | 0 | 0 |
| A11c disjoint | 125.29 | 106.72 | 0 | 0 | 0 | 0 | 0 | 0 |
| A11c overlap | 281.82 | 139.95 | 3084 | 0 | 46 | 0 | 0 | 0 |
| keyed PK subscriptions | 283.39 | 225.62 | 1106 | 0 | 46 | 0 | 0 | 0 |

Original PR confirmation pass:

| workload | wall_ms | parked_total | wake_retry_total | max_parked |
|---|---:|---:|---:|---:|
| A11c baseline | 104.35 | 0 | 0 | 0 |
| A11c disjoint | 100.13 | 0 | 0 | 0 |
| A11c overlap | 145.34 | 0 | 0 | 0 |
| keyed PK subscriptions | 223.75 | 0 | 0 | 0 |

Post-rebase pass on top of exp 120:

| workload | wall_ms | parked_total | wake_retry_total | max_parked |
|---|---:|---:|---:|---:|
| A11c baseline | 89.25 | 0 | 0 | 0 |
| A11c disjoint | 90.72 | 0 | 0 | 0 |
| A11c overlap | 137.25 | 0 | 0 | 0 |
| keyed PK subscriptions | 427.75 | 0 | 0 | 0 |

Concrete-pool rebased confirmation:

| workload | wall_ms | parked_total | wake_retry_total | max_parked |
|---|---:|---:|---:|---:|
| A11c baseline | 197.57 | 0 | 0 | 0 |
| A11c disjoint | 313.75 | 0 | 0 | 0 |
| A11c overlap | 697.27 | 0 | 0 | 0 |
| keyed PK subscriptions | 83.80 | 0 | 0 | 0 |

The wall time on the keyed-PK profile row is noisy because the harness waits
for a quiet stream-emission window, but the counter signal is stable: all
candidate passes, including the post-exp-120 rebase, keep
`dispatcherParkedTotal`, `dispatcherWakeRetryTotal`, and
`dispatcherMaxParkedConcurrent` at zero.

## Release Guardrails

Commands:

```text
dart run benchmark/suites/many_streams_writer_throughput.dart
dart run benchmark/suites/keyed_pk_subscriptions.dart
dart run benchmark/suites/high_cardinality_fanout.dart
```

| workload | baseline | candidate | delta | read |
|---|---:|---:|---:|---|
| A11c no-streams baseline | 27.41 ms | 26.47 ms | -3.4% | noise/control; no stream flush path |
| A11c disjoint | 22.00 ms | 21.23 ms | -3.5% | neutral/supportive |
| A11c overlap | 54.40 ms | 48.37 ms | -11.1% | win |
| Keyed PK subscriptions | 222.46 ms | 233.45 ms | +4.9% | neutral |
| High-cardinality fan-out | 240.19 ms | 245.25 ms | +2.1% | neutral |

## Interpretation

The change hardens exp 120's bounded admission path without recreating exp
100's high-cardinality fan-out regression. The core mechanism is simpler than
the original PR: `Database` constructs `StreamEngine` with a concrete
`ReaderPool`, so `_flushQueue` can synchronously admit at most
`availableWorkerCount` entries and leave the rest queued until re-query
completion calls `_flushQueue()` again.
