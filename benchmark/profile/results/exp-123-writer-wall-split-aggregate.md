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
| 1 | A11c baseline | 0 streams x 500 writes | 55.53 | 500 | 44216 | 24640 | 4468 | 0 | 0 |
| 1 | A11c disjoint | 50 streams x 500 writes | 52.01 | 500 | 31423 | 11586 | 3456 | 9647 | 500 |
| 1 | A11c overlap | 50 streams x 500 writes | 99.91 | 500 | 53614 | 16365 | 4141 | 14358 | 500 |
| 1 | keyed PK subscriptions | 50 streams x 200 random writes | 33.57 | 200 | 27953 | 13859 | 783 | 3505 | 200 |
| 1 | Wide batch insert | 10000 rows x 20 params | 45.53 | 1 | 45502 | 34736 | 15 | 0 | 0 |
| 2 | A11c baseline | 0 streams x 500 writes | 32.69 | 500 | 27444 | 19248 | 164 | 0 | 0 |
| 2 | A11c disjoint | 50 streams x 500 writes | 24.68 | 500 | 16508 | 7702 | 99 | 2742 | 500 |
| 2 | A11c overlap | 50 streams x 500 writes | 64.80 | 500 | 38954 | 10619 | 321 | 5518 | 500 |
| 2 | keyed PK subscriptions | 50 streams x 200 random writes | 20.00 | 200 | 16677 | 7098 | 133 | 2093 | 200 |
| 2 | Wide batch insert | 10000 rows x 20 params | 28.73 | 1 | 28709 | 23867 | 29 | 0 | 0 |
| 3 | A11c baseline | 0 streams x 500 writes | 34.68 | 500 | 30191 | 21740 | 95 | 0 | 0 |
| 3 | A11c disjoint | 50 streams x 500 writes | 25.84 | 500 | 18847 | 7648 | 94 | 2553 | 500 |
| 3 | A11c overlap | 50 streams x 500 writes | 57.95 | 500 | 35445 | 11189 | 297 | 6228 | 500 |
| 3 | keyed PK subscriptions | 50 streams x 200 random writes | 24.98 | 200 | 21319 | 11236 | 165 | 2634 | 200 |
| 3 | Wide batch insert | 10000 rows x 20 params | 40.45 | 1 | 40440 | 33688 | 37 | 0 | 0 |

## Derived split

| pass | workload | roundtrip / wall | write call / roundtrip | dirty fetch / roundtrip | residual / roundtrip | invalidate / wall | us per writer request |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | A11c baseline | 79.63% | 55.73% | 10.10% | 34.17% | 0.00% | 88.43 |
| 1 | A11c disjoint | 60.42% | 36.87% | 11.00% | 52.13% | 18.55% | 62.85 |
| 1 | A11c overlap | 53.66% | 30.52% | 7.72% | 61.75% | 14.37% | 107.23 |
| 1 | keyed PK subscriptions | 83.27% | 49.58% | 2.80% | 47.62% | 10.44% | 139.76 |
| 1 | Wide batch insert | 99.94% | 76.34% | 0.03% | 23.63% | 0.00% | 45502.00 |
| 2 | A11c baseline | 83.95% | 70.14% | 0.60% | 29.27% | 0.00% | 54.89 |
| 2 | A11c disjoint | 66.87% | 46.66% | 0.60% | 52.74% | 11.11% | 33.02 |
| 2 | A11c overlap | 60.12% | 27.26% | 0.82% | 71.92% | 8.52% | 77.91 |
| 2 | keyed PK subscriptions | 83.36% | 42.56% | 0.80% | 56.64% | 10.46% | 83.39 |
| 2 | Wide batch insert | 99.94% | 83.13% | 0.10% | 16.76% | 0.00% | 28709.00 |
| 3 | A11c baseline | 87.06% | 72.01% | 0.31% | 27.68% | 0.00% | 60.38 |
| 3 | A11c disjoint | 72.93% | 40.58% | 0.50% | 58.92% | 9.88% | 37.69 |
| 3 | A11c overlap | 61.16% | 31.57% | 0.84% | 67.59% | 10.75% | 70.89 |
| 3 | keyed PK subscriptions | 85.34% | 52.70% | 0.77% | 46.52% | 10.54% | 106.59 |
| 3 | Wide batch insert | 99.97% | 83.30% | 0.09% | 16.60% | 0.00% | 40440.00 |

## Reading the table

- `writer_roundtrip_us` is measured on the main isolate around the locked writer request. It includes message copy/delivery, writer scheduling, worker execution, dirty-dependency fetch, and the reply.
- `writer_write_call_us` is measured on the writer isolate around `executeWrite` / `executeBatchWrite`. It includes Dart parameter packing plus the FFI/native write call.
- SQLite statement trace timing was researched for this experiment, but this build intentionally compiles SQLite with `SQLITE_OMIT_TRACE`. Changing that compile flag would alter the production SQLite build rather than adding a profile-only Dart counter.
- `residual / roundtrip` is the remainder after subtracting write-call and dirty-fetch wall from main-isolate roundtrip wall. Treat it as isolate messaging, event-loop scheduling, reply copy, and small measurement skew.
- `invalidate_us` is the existing `StreamEngine.onDependencyChanges` counter. It is outside writer roundtrip and is reported as a share of workload wall.
