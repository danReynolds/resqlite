# Experiment 127 - Writer Wall Split Audit

Profile-mode harness: `benchmark/profile/writer_wall_split_audit.dart`

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`)

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/writer_wall_split_audit.dart --markdown --repeats=3
```

## Counters

| pass | workload | shape | wall_ms | writer_requests | writer_roundtrip_us | writer_write_call_us | dirty_fetch_us | invalidate_us | invalidate_count |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | A11c baseline | 0 streams x 500 writes | 33.96 | 500 | 23315 | 10747 | 3385 | 0 | 0 |
| 1 | A11c disjoint | 50 streams x 500 writes | 40.44 | 500 | 21697 | 8542 | 3092 | 8915 | 500 |
| 1 | A11c overlap | 50 streams x 500 writes | 109.61 | 500 | 53838 | 14930 | 4953 | 14776 | 500 |
| 1 | keyed PK subscriptions | 50 streams x 200 random writes | 20.67 | 200 | 16141 | 4768 | 497 | 2942 | 200 |
| 1 | Wide batch insert | 10000 rows x 20 params | 33.56 | 1 | 33136 | 22853 | 8 | 0 | 0 |
| 2 | A11c baseline | 0 streams x 500 writes | 20.46 | 500 | 15237 | 8568 | 106 | 0 | 0 |
| 2 | A11c disjoint | 50 streams x 500 writes | 23.82 | 500 | 15024 | 7190 | 50 | 2713 | 500 |
| 2 | A11c overlap | 50 streams x 500 writes | 57.15 | 500 | 35391 | 8313 | 253 | 4613 | 500 |
| 2 | keyed PK subscriptions | 50 streams x 200 random writes | 15.95 | 200 | 12627 | 3983 | 75 | 2028 | 200 |
| 2 | Wide batch insert | 10000 rows x 20 params | 24.50 | 1 | 24446 | 16691 | 9 | 0 | 0 |
| 3 | A11c baseline | 0 streams x 500 writes | 19.97 | 500 | 15377 | 8490 | 39 | 0 | 0 |
| 3 | A11c disjoint | 50 streams x 500 writes | 20.17 | 500 | 12635 | 5937 | 21 | 3055 | 500 |
| 3 | A11c overlap | 50 streams x 500 writes | 50.06 | 500 | 30433 | 9545 | 176 | 5087 | 500 |
| 3 | keyed PK subscriptions | 50 streams x 200 random writes | 14.24 | 200 | 11287 | 3449 | 45 | 1995 | 200 |
| 3 | Wide batch insert | 10000 rows x 20 params | 21.08 | 1 | 21009 | 14667 | 9 | 0 | 0 |

## Derived split

| pass | workload | roundtrip / wall | write call / roundtrip | dirty fetch / roundtrip | residual / roundtrip | invalidate / wall | us per writer request |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | A11c baseline | 68.66% | 46.09% | 14.52% | 39.39% | 0.00% | 46.63 |
| 1 | A11c disjoint | 53.66% | 39.37% | 14.25% | 46.38% | 22.05% | 43.39 |
| 1 | A11c overlap | 49.12% | 27.73% | 9.20% | 63.07% | 13.48% | 107.68 |
| 1 | keyed PK subscriptions | 78.08% | 29.54% | 3.08% | 67.38% | 14.23% | 80.70 |
| 1 | Wide batch insert | 98.74% | 68.97% | 0.02% | 31.01% | 0.00% | 33136.00 |
| 2 | A11c baseline | 74.45% | 56.23% | 0.70% | 43.07% | 0.00% | 30.47 |
| 2 | A11c disjoint | 63.09% | 47.86% | 0.33% | 51.81% | 11.39% | 30.05 |
| 2 | A11c overlap | 61.92% | 23.49% | 0.71% | 75.80% | 8.07% | 70.78 |
| 2 | keyed PK subscriptions | 79.18% | 31.54% | 0.59% | 67.86% | 12.72% | 63.13 |
| 2 | Wide batch insert | 99.77% | 68.28% | 0.04% | 31.69% | 0.00% | 24446.00 |
| 3 | A11c baseline | 77.01% | 55.21% | 0.25% | 44.53% | 0.00% | 30.75 |
| 3 | A11c disjoint | 62.65% | 46.99% | 0.17% | 52.85% | 15.15% | 25.27 |
| 3 | A11c overlap | 60.79% | 31.36% | 0.58% | 68.06% | 10.16% | 60.87 |
| 3 | keyed PK subscriptions | 79.25% | 30.56% | 0.40% | 69.04% | 14.01% | 56.44 |
| 3 | Wide batch insert | 99.64% | 69.81% | 0.04% | 30.14% | 0.00% | 21009.00 |

## Reading the table

- `writer_roundtrip_us` is measured on the main isolate around each writer request after the caller has entered the writer lock where applicable. It includes message copy/delivery, writer scheduling, worker execution, dirty-dependency fetch, and the reply.
- `writer_write_call_us` is measured on the writer isolate around `executeWrite` / `executeBatchWrite`. It includes Dart parameter packing plus the FFI/native write call.
- SQLite statement trace timing was researched for this experiment, but this build intentionally compiles SQLite with `SQLITE_OMIT_TRACE`. Changing that compile flag would alter the production SQLite build rather than adding a profile-only Dart counter.
- `residual / roundtrip` is the remainder after subtracting write-call and dirty-fetch wall from main-isolate roundtrip wall. Treat it as isolate messaging, event-loop scheduling, reply copy, and small measurement skew.
- `invalidate_us` is the existing `StreamEngine.onDependencyChanges` counter. It is outside writer roundtrip and is reported as a share of workload wall.
