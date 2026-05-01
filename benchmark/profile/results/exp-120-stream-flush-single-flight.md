# Experiment 120 - Stream Flush Single-Flight

Profile-mode harness: `benchmark/profile/stream_flush_single_flight_profile.dart`

Commands:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_flush_single_flight_profile.dart --label=baseline
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_flush_single_flight_profile.dart --label=candidate
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_flush_single_flight_profile.dart --label=candidate-confirm
```

## Profile Counter A/B

| workload | baseline wall_ms | candidate wall_ms | baseline parked | candidate parked | baseline max_parked | candidate max_parked | baseline retries | candidate retries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 135.32 | 95.94 | 0 | 0 | 0 | 0 | 0 | 0 |
| A11c disjoint | 125.29 | 106.72 | 0 | 0 | 0 | 0 | 0 | 0 |
| A11c overlap | 281.82 | 139.95 | 3084 | 0 | 46 | 0 | 0 | 0 |
| keyed PK subscriptions | 283.39 | 225.62 | 1106 | 0 | 46 | 0 | 0 | 0 |

Candidate confirmation pass:

| workload | wall_ms | parked_total | wake_retry_total | max_parked |
|---|---:|---:|---:|---:|
| A11c baseline | 88.80 | 0 | 0 | 0 |
| A11c disjoint | 95.00 | 0 | 0 | 0 |
| A11c overlap | 159.21 | 0 | 0 | 0 |
| keyed PK subscriptions | 427.66 | 0 | 0 | 0 |

The wall time on the keyed-PK profile row is noisy because the harness waits
for a quiet stream-emission window, but the counter signal is stable: both
candidate passes keep `dispatcherParkedTotal`, `dispatcherWakeRetryTotal`, and
`dispatcherMaxParkedConcurrent` at zero for the workloads that previously
parked.

## Release Guardrails

Commands:

```text
dart run benchmark/suites/many_streams_writer_throughput.dart
dart run benchmark/suites/keyed_pk_subscriptions.dart
dart run benchmark/suites/high_cardinality_fanout.dart
```

| workload | baseline | candidate | delta | read |
|---|---:|---:|---:|---|
| A11c no-streams baseline | 27.41 ms | 30.46 ms | +11.1% | noise/control; no stream flush path |
| A11c disjoint | 22.00 ms | 20.23 ms | -8.0% | supportive |
| A11c overlap | 54.40 ms | 47.69 ms | -12.3% | win |
| Keyed PK subscriptions | 222.46 ms | 222.71 ms | +0.1% | neutral |
| High-cardinality fan-out | 240.19 ms | 237.31 ms | -1.2% | neutral |

## Interpretation

The change removes the remaining profile-visible stream dispatch pressure
without recreating exp 100's high-cardinality fan-out regression. The core
mechanism is admission accuracy: `_flushQueue` now uses a single active flush
pass and passes the already-resolved `ReaderPool` into `_requery`, so each
admitted re-query consumes an available worker before the flush loop checks
availability again.
