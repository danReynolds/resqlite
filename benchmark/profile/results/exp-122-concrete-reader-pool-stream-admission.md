# Experiment 122 - Concrete Reader-Pool Stream Admission

Profile-mode harness: `benchmark/profile/stream_concrete_pool_profile.dart`

Commands:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_concrete_pool_profile.dart --label=baseline
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_concrete_pool_profile.dart --label=candidate
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_concrete_pool_profile.dart --label=candidate-confirm
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_concrete_pool_profile.dart --label=candidate-current
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_concrete_pool_profile.dart --label=post-rebase
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_concrete_pool_profile.dart --label=concrete-pool-single-init
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

Concrete-pool single-initializer confirmation:

| workload | wall_ms | parked_total | wake_retry_total | max_parked |
|---|---:|---:|---:|---:|
| A11c baseline | 51.91 | 0 | 0 | 0 |
| A11c disjoint | 42.51 | 0 | 0 | 0 |
| A11c overlap | 100.17 | 0 | 0 | 0 |
| keyed PK subscriptions | 29.19 | 0 | 0 | 0 |

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
| A11c no-streams baseline | 29.38 ms | 27.64 ms | -5.9% | neutral/supportive; no stream flush path |
| A11c disjoint | 21.39 ms | 20.87 ms | -2.4% | neutral/supportive |
| A11c overlap | 56.39 ms | 55.73 ms | -1.2% | neutral |
| Keyed PK subscriptions | 230.82 ms | 226.45 ms | -1.9% | neutral |
| High-cardinality fan-out | 444.18 ms | 437.05 ms | -1.6% | neutral |

The first concrete-pool rebase briefly used two derived futures in the hot
write path (`(_writer, _streamEngine).wait`). A fresh A11c guardrail run caught
that overhead in the no-streams baseline. The final implementation awaits one
initialized runtime object per operation, matching the original one-await
writer path while still giving `StreamEngine` a concrete `ReaderPool`.

## Interpretation

The change hardens exp 120's bounded admission path without recreating exp
100's high-cardinality fan-out regression. The core mechanism is simpler than
the original PR: `Database` constructs `StreamEngine` with a concrete
`ReaderPool`, so `_flushQueue` can synchronously admit at most
`availableWorkerCount` entries and leave the rest queued until re-query
completion calls `_flushQueue()` again.
