# Experiment 135 - Writer Wall vs SQLite-Call Split

Profile-mode harness: `benchmark/profile/writer_sqlite_wall_audit.dart`

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`)
Passes: 1 discarded warmup, 3 measured passes per row; tables report medians.

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/writer_sqlite_wall_audit.dart --markdown
```

## Counters

| workload | shape | wall_ms | writer_request_ms | writer_sqlite_ms | dirty_drain_ms | invalidate_ms | writer_residual_ms | wall_residual_ms | writes | emissions | observed_hits |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 0 streams x 500 writes, median of 3 | 59.53 | 38.43 | 18.31 | 5.66 | 0.00 | 14.46 | 21.10 | 500 | 0 | 0 |
| A11c disjoint | 50 streams x 500 writes, median of 3 | 36.98 | 20.23 | 10.51 | 0.52 | 4.31 | 9.20 | 12.44 | 500 | 0 | 0 |
| A11c overlap | 50 streams x 500 writes, median of 3 | 97.76 | 61.95 | 20.03 | 0.57 | 11.62 | 41.35 | 24.18 | 500 | 16 | 0 |
| keyed PK subscriptions | 50 streams x 200 random writes, median of 3 | 71.00 | 62.97 | 41.70 | 0.51 | 4.84 | 20.77 | 3.18 | 200 | 3 | 3 |

## Derived fractions

| workload | writer_request / wall | sqlite / writer_request | dirty_drain / writer_request | invalidate / wall | avg_request_us | avg_sqlite_us | avg_dirty_us |
|---|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 64.55% | 47.65% | 14.73% | 0.00% | 76.9 | 36.6 | 11.3 |
| A11c disjoint | 54.71% | 51.94% | 2.58% | 11.65% | 40.5 | 21.0 | 1.0 |
| A11c overlap | 63.38% | 32.33% | 0.93% | 11.89% | 123.9 | 40.1 | 1.1 |
| keyed PK subscriptions | 88.70% | 66.21% | 0.81% | 6.82% | 314.9 | 208.5 | 2.5 |

## Reading the table

- `writer_request_ms` is measured on the main isolate around the writer request/response after the write mutex is held. It excludes `StreamEngine.onDependencyChanges`.
- `writer_sqlite_ms` is measured on the writer isolate around the native write call. It includes SQLite prepare/cache lookup, bind, step/commit, reset, and native result extraction.
- `dirty_drain_ms` is the writer-isolate drain of dirty table/column metadata after the native write completes.
- `writer_residual_ms` is writer request wall not explained by the native write call or dirty drain. It is the IPC / Dart request handling / response delivery bucket.
- `wall_residual_ms` is outer workload wall not explained by writer request or synchronous invalidation. On A11c rows this mainly captures the two zero-duration yields per write, where stream re-query completion and listener microtasks can run.

## Interpretation

See `experiments/135-writer-sqlite-wall-split.md` for the decision and follow-up notes attached to these numbers.
