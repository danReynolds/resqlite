# Experiment 128 - Batched Stream Re-queries

Candidate profile-mode harness: `benchmark/profile/writer_wall_split_audit.dart`

Baseline is PR #100 head `9a46228` (exp 127 writer/completion counters).
Candidate is exp 128 batched `selectIfChanged` stream re-queries.

## Fresh A/B summary

| workload | baseline wall_ms | candidate wall_ms | baseline reader replies | candidate reader replies |
|---|---:|---:|---:|---:|
| A11c overlap pass 2 | 71.16 | 57.03 | 2266 | 35 |
| A11c overlap pass 3 | 56.27 | 37.28 | 3168 | 31 |
| keyed PK pass 2 | 19.17 | 22.00 | 1097 | 41 |
| keyed PK pass 3 | 21.34 | 14.06 | 1057 | 41 |

Standalone release-shape guardrails:

| suite | metric | baseline | candidate | delta |
|---|---|---:|---:|---:|
| Many-Streams overlap | wall med | 65.90 ms | 24.57 ms | -62.7% |
| Many-Streams overlap | writes/sec | 7587 | 20347 | +168.2% |
| Many-Streams disjoint | wall med | 25.42 ms | 22.86 ms | -10.1% |
| Many-Streams ratio | overlap/disjoint | 0.386 | 0.930 | +0.544 |
| Keyed PK subscriptions | wall med | 226.20 ms | 218.29 ms | -3.5% |

## Candidate Profile Output

Profile-mode harness: `benchmark/profile/writer_wall_split_audit.dart`

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`)

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/writer_wall_split_audit.dart --markdown --repeats=3
```

## Counters

| pass | workload | shape | wall_ms | writer_requests | writer_roundtrip_us | writer_write_call_us | dirty_fetch_us | invalidate_us | invalidate_count |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | A11c baseline | 0 streams x 500 writes | 61.87 | 500 | 46022 | 22425 | 6147 | 0 | 0 |
| 1 | A11c disjoint | 50 streams x 500 writes | 54.18 | 500 | 31543 | 12067 | 4083 | 9154 | 500 |
| 1 | A11c overlap | 50 streams x 500 writes | 67.59 | 500 | 39868 | 16057 | 3973 | 12888 | 500 |
| 1 | keyed PK subscriptions | 50 streams x 200 random writes | 17.33 | 200 | 11734 | 5543 | 770 | 3900 | 200 |
| 1 | Wide batch insert | 10000 rows x 20 params | 53.24 | 1 | 52448 | 28499 | 16 | 0 | 0 |
| 2 | A11c baseline | 0 streams x 500 writes | 45.41 | 500 | 36272 | 20494 | 929 | 0 | 0 |
| 2 | A11c disjoint | 50 streams x 500 writes | 36.05 | 500 | 21015 | 10535 | 328 | 4937 | 500 |
| 2 | A11c overlap | 50 streams x 500 writes | 57.03 | 500 | 38383 | 17966 | 645 | 7263 | 500 |
| 2 | keyed PK subscriptions | 50 streams x 200 random writes | 22.00 | 200 | 16755 | 6208 | 146 | 2808 | 200 |
| 2 | Wide batch insert | 10000 rows x 20 params | 29.77 | 1 | 29698 | 18799 | 15 | 0 | 0 |
| 3 | A11c baseline | 0 streams x 500 writes | 29.09 | 500 | 23203 | 14650 | 114 | 0 | 0 |
| 3 | A11c disjoint | 50 streams x 500 writes | 24.08 | 500 | 15750 | 7146 | 100 | 3219 | 500 |
| 3 | A11c overlap | 50 streams x 500 writes | 37.28 | 500 | 20861 | 8547 | 125 | 5963 | 500 |
| 3 | keyed PK subscriptions | 50 streams x 200 random writes | 14.06 | 200 | 11236 | 8255 | 38 | 1858 | 200 |
| 3 | Wide batch insert | 10000 rows x 20 params | 16.03 | 1 | 15984 | 12361 | 11 | 0 | 0 |

## Derived split

| pass | workload | roundtrip / wall | write call / roundtrip | dirty fetch / roundtrip | residual / roundtrip | invalidate / wall | us per writer request |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | A11c baseline | 74.38% | 48.73% | 13.36% | 37.92% | 0.00% | 92.04 |
| 1 | A11c disjoint | 58.22% | 38.26% | 12.94% | 48.80% | 16.89% | 63.09 |
| 1 | A11c overlap | 58.98% | 40.28% | 9.97% | 49.76% | 19.07% | 79.74 |
| 1 | keyed PK subscriptions | 67.72% | 47.24% | 6.56% | 46.20% | 22.51% | 58.67 |
| 1 | Wide batch insert | 98.50% | 54.34% | 0.03% | 45.63% | 0.00% | 52448.00 |
| 2 | A11c baseline | 79.88% | 56.50% | 2.56% | 40.94% | 0.00% | 72.54 |
| 2 | A11c disjoint | 58.29% | 50.13% | 1.56% | 48.31% | 13.69% | 42.03 |
| 2 | A11c overlap | 67.31% | 46.81% | 1.68% | 51.51% | 12.74% | 76.77 |
| 2 | keyed PK subscriptions | 76.16% | 37.05% | 0.87% | 62.08% | 12.76% | 83.78 |
| 2 | Wide batch insert | 99.75% | 63.30% | 0.05% | 36.65% | 0.00% | 29698.00 |
| 3 | A11c baseline | 79.76% | 63.14% | 0.49% | 36.37% | 0.00% | 46.41 |
| 3 | A11c disjoint | 65.41% | 45.37% | 0.63% | 53.99% | 13.37% | 31.50 |
| 3 | A11c overlap | 55.96% | 40.97% | 0.60% | 58.43% | 16.00% | 41.72 |
| 3 | keyed PK subscriptions | 79.90% | 73.47% | 0.34% | 26.19% | 13.21% | 56.18 |
| 3 | Wide batch insert | 99.72% | 77.33% | 0.07% | 22.60% | 0.00% | 15984.00 |

## Stream completion and reader reply split

| pass | workload | requeries | changed / unchanged / discarded | requery_await_us / avg | dispatcher_parks | dispatch_wait_us / avg | reader_replies | reply_delivery_us / avg | stream_emits | emit_us / avg |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | A11c baseline | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |
| 1 | A11c disjoint | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |
| 1 | A11c overlap | 2750 | 5 / 45 / 2700 | 63370 / 23.04 | 0 | 0 / 0.00 | 55 | 6229 / 113.25 | 5 | 12 / 2.40 |
| 1 | keyed PK subscriptions | 2450 | 3 / 47 / 2400 | 16947 / 6.92 | 0 | 0 / 0.00 | 49 | 2358 / 48.12 | 3 | 12 / 4.00 |
| 1 | Wide batch insert | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |
| 2 | A11c baseline | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |
| 2 | A11c disjoint | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |
| 2 | A11c overlap | 1750 | 9 / 241 / 1500 | 59302 / 33.89 | 0 | 0 / 0.00 | 35 | 1546 / 44.17 | 9 | 58 / 6.44 |
| 2 | keyed PK subscriptions | 2050 | 3 / 297 / 1750 | 21081 / 10.28 | 0 | 0 / 0.00 | 41 | 1370 / 33.41 | 3 | 11 / 3.67 |
| 2 | Wide batch insert | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |
| 3 | A11c baseline | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |
| 3 | A11c disjoint | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |
| 3 | A11c overlap | 1550 | 7 / 143 / 1400 | 36880 / 23.79 | 0 | 0 / 0.00 | 31 | 1128 / 36.39 | 7 | 46 / 6.57 |
| 3 | keyed PK subscriptions | 2050 | 3 / 47 / 2000 | 11193 / 5.46 | 0 | 0 / 0.00 | 41 | 897 / 21.88 | 3 | 12 / 4.00 |
| 3 | Wide batch insert | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |

## Reading the table

- `writer_roundtrip_us` is measured on the main isolate around each writer request after the caller has entered the writer lock where applicable. It includes message copy/delivery, writer scheduling, worker execution, dirty-dependency fetch, and the reply.
- `writer_write_call_us` is measured on the writer isolate around `executeWrite` / `executeBatchWrite`. It includes Dart parameter packing plus the FFI/native write call.
- SQLite statement trace timing was researched for this experiment, but this build intentionally compiles SQLite with `SQLITE_OMIT_TRACE`. Changing that compile flag would alter the production SQLite build rather than adding a profile-only Dart counter.
- `residual / roundtrip` is the remainder after subtracting write-call and dirty-fetch wall from main-isolate roundtrip wall. Treat it as isolate messaging, event-loop scheduling, reply copy, and small measurement skew.
- `invalidate_us` is the existing `StreamEngine.onDependencyChanges` counter. It is outside writer roundtrip and is reported as a share of workload wall.
- `stream_requery_await_us` is accumulated per stream re-query, so overlapping re-queries can sum above workload wall. Use its average with `dispatcher_parks` / `dispatch_wait_us` to separate reader-pool queueing from tiny reply-delivery and controller-delivery costs.
- Stream completion counters are captured after the post-wall drain; `wall_ms` still stops immediately after the write loop.
