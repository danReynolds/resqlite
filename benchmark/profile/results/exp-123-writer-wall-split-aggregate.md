# Experiment 123 - Writer Wall Split Audit

Profile-mode harness: `benchmark/profile/writer_wall_split_audit.dart`

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`)

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/writer_wall_split_audit.dart --markdown --repeats=3
```

## Counters

| pass | workload | shape | wall_ms | writer_requests | writer_roundtrip_us | writer_write_call_us | dirty_fetch_us | invalidate_us | invalidate_count |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | A11c baseline | 0 streams x 500 writes | 33.30 | 500 | 23125 | 10757 | 3165 | 0 | 0 |
| 1 | A11c disjoint | 50 streams x 500 writes | 39.61 | 500 | 21178 | 7910 | 2643 | 9056 | 500 |
| 1 | A11c overlap | 50 streams x 500 writes | 90.41 | 500 | 46739 | 12960 | 3859 | 12011 | 500 |
| 1 | keyed PK subscriptions | 50 streams x 200 random writes | 21.59 | 200 | 16608 | 5011 | 457 | 3215 | 200 |
| 1 | Wide batch insert | 10000 rows x 20 params | 43.14 | 1 | 42844 | 33033 | 15 | 0 | 0 |
| 2 | A11c baseline | 0 streams x 500 writes | 20.02 | 500 | 15201 | 8600 | 95 | 0 | 0 |
| 2 | A11c disjoint | 50 streams x 500 writes | 22.50 | 500 | 13828 | 6537 | 36 | 2967 | 500 |
| 2 | A11c overlap | 50 streams x 500 writes | 54.60 | 500 | 28950 | 8415 | 184 | 4681 | 500 |
| 2 | keyed PK subscriptions | 50 streams x 200 random writes | 16.59 | 200 | 13128 | 3734 | 53 | 1949 | 200 |
| 2 | Wide batch insert | 10000 rows x 20 params | 33.29 | 1 | 33218 | 25015 | 28 | 0 | 0 |
| 3 | A11c baseline | 0 streams x 500 writes | 18.35 | 500 | 14092 | 7496 | 9 | 0 | 0 |
| 3 | A11c disjoint | 50 streams x 500 writes | 21.05 | 500 | 13882 | 6254 | 35 | 2715 | 500 |
| 3 | A11c overlap | 50 streams x 500 writes | 48.96 | 500 | 29421 | 8202 | 135 | 5430 | 500 |
| 3 | keyed PK subscriptions | 50 streams x 200 random writes | 16.66 | 200 | 13339 | 4170 | 81 | 2091 | 200 |
| 3 | Wide batch insert | 10000 rows x 20 params | 37.37 | 1 | 37317 | 12708 | 13 | 0 | 0 |

## Derived split

| pass | workload | roundtrip / wall | write call / roundtrip | dirty fetch / roundtrip | residual / roundtrip | invalidate / wall | us per writer request |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | A11c baseline | 69.45% | 46.52% | 13.69% | 39.80% | 0.00% | 46.25 |
| 1 | A11c disjoint | 53.47% | 37.35% | 12.48% | 50.17% | 22.87% | 42.36 |
| 1 | A11c overlap | 51.70% | 27.73% | 8.26% | 64.02% | 13.29% | 93.48 |
| 1 | keyed PK subscriptions | 76.94% | 30.17% | 2.75% | 67.08% | 14.89% | 83.04 |
| 1 | Wide batch insert | 99.32% | 77.10% | 0.04% | 22.86% | 0.00% | 42844.00 |
| 2 | A11c baseline | 75.92% | 56.58% | 0.62% | 42.80% | 0.00% | 30.40 |
| 2 | A11c disjoint | 61.46% | 47.27% | 0.26% | 52.47% | 13.19% | 27.66 |
| 2 | A11c overlap | 53.02% | 29.07% | 0.64% | 70.30% | 8.57% | 57.90 |
| 2 | keyed PK subscriptions | 79.14% | 28.44% | 0.40% | 71.15% | 11.75% | 65.64 |
| 2 | Wide batch insert | 99.80% | 75.31% | 0.08% | 24.61% | 0.00% | 33218.00 |
| 3 | A11c baseline | 76.79% | 53.19% | 0.06% | 46.74% | 0.00% | 28.18 |
| 3 | A11c disjoint | 65.95% | 45.05% | 0.25% | 54.70% | 12.90% | 27.76 |
| 3 | A11c overlap | 60.10% | 27.88% | 0.46% | 71.66% | 11.09% | 58.84 |
| 3 | keyed PK subscriptions | 80.05% | 31.26% | 0.61% | 68.13% | 12.55% | 66.69 |
| 3 | Wide batch insert | 99.87% | 34.05% | 0.03% | 65.91% | 0.00% | 37317.00 |

## Reading the table

- `writer_roundtrip_us` is measured on the main isolate around each writer request after the caller has entered the writer lock where applicable. It includes message copy/delivery, writer scheduling, worker execution, dirty-dependency fetch, and the reply.
- `writer_write_call_us` is measured on the writer isolate around `executeWrite` / `executeBatchWrite`. It includes Dart parameter packing plus the FFI/native write call.
- SQLite statement trace timing was researched for this experiment, but this build intentionally compiles SQLite with `SQLITE_OMIT_TRACE`. Changing that compile flag would alter the production SQLite build rather than adding a profile-only Dart counter.
- `residual / roundtrip` is the remainder after subtracting write-call and dirty-fetch wall from main-isolate roundtrip wall. Treat it as isolate messaging, event-loop scheduling, reply copy, and small measurement skew.
- `invalidate_us` is the existing `StreamEngine.onDependencyChanges` counter. It is outside writer roundtrip and is reported as a share of workload wall.
