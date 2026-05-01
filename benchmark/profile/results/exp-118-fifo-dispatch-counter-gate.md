# Experiment 118 - FIFO Dispatch Waiters

Profile-mode harness: `benchmark/profile/dispatcher_park_profile.dart`

Command:

```text
/Users/dan/Coding/flutter_arm64/bin/dart run -DRESQLITE_PROFILE=true benchmark/profile/dispatcher_park_profile.dart
```

Median of three full harness runs on a 4-worker reader pool:

| concurrency | baseline parked | FIFO parked | baseline retries | FIFO retries | baseline max parked | FIFO max parked | baseline wall | FIFO wall |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 8 | 10 | 4 | 6 | 0 | 4 | 4 | 0.34 ms | 0.32 ms |
| 16 | 78 | 12 | 66 | 0 | 12 | 12 | 0.78 ms | 0.60 ms |
| 32 | 406 | 28 | 378 | 0 | 28 | 28 | 1.20 ms | 1.28 ms |

Interpretation:

- `dispatcherWakeRetryTotal` drops to zero at every overloaded concurrency.
- `dispatcherParkedTotal` drops to the unavoidable `concurrency - pool_size`
  shape.
- `dispatcherMaxParkedConcurrent` stays unchanged, so the candidate still
  exercises the same parked-dispatcher depth.
