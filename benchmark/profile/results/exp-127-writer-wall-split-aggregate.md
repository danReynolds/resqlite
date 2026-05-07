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
| 1 | A11c baseline | 0 streams x 500 writes | 50.25 | 500 | 36969 | 18734 | 4714 | 0 | 0 |
| 1 | A11c disjoint | 50 streams x 500 writes | 57.81 | 500 | 32958 | 11820 | 4990 | 10856 | 500 |
| 1 | A11c overlap | 50 streams x 500 writes | 154.61 | 500 | 101516 | 27694 | 7172 | 16273 | 500 |
| 1 | keyed PK subscriptions | 50 streams x 200 random writes | 31.70 | 200 | 25554 | 8432 | 902 | 4017 | 200 |
| 1 | Wide batch insert | 10000 rows x 20 params | 27.66 | 1 | 27450 | 20137 | 27 | 0 | 0 |
| 2 | A11c baseline | 0 streams x 500 writes | 29.14 | 500 | 18680 | 9686 | 250 | 0 | 0 |
| 2 | A11c disjoint | 50 streams x 500 writes | 24.12 | 500 | 15041 | 6928 | 125 | 2750 | 500 |
| 2 | A11c overlap | 50 streams x 500 writes | 73.37 | 500 | 45804 | 11565 | 425 | 6368 | 500 |
| 2 | keyed PK subscriptions | 50 streams x 200 random writes | 25.23 | 200 | 20563 | 7567 | 213 | 2559 | 200 |
| 2 | Wide batch insert | 10000 rows x 20 params | 16.39 | 1 | 16359 | 12189 | 12 | 0 | 0 |
| 3 | A11c baseline | 0 streams x 500 writes | 24.63 | 500 | 19219 | 8516 | 122 | 0 | 0 |
| 3 | A11c disjoint | 50 streams x 500 writes | 23.18 | 500 | 14623 | 6624 | 84 | 2863 | 500 |
| 3 | A11c overlap | 50 streams x 500 writes | 63.52 | 500 | 39827 | 13220 | 976 | 5788 | 500 |
| 3 | keyed PK subscriptions | 50 streams x 200 random writes | 17.14 | 200 | 13645 | 4184 | 44 | 2234 | 200 |
| 3 | Wide batch insert | 10000 rows x 20 params | 15.05 | 1 | 14894 | 10620 | 10 | 0 | 0 |

## Derived split

| pass | workload | roundtrip / wall | write call / roundtrip | dirty fetch / roundtrip | residual / roundtrip | invalidate / wall | us per writer request |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | A11c baseline | 73.57% | 50.67% | 12.75% | 36.57% | 0.00% | 73.94 |
| 1 | A11c disjoint | 57.01% | 35.86% | 15.14% | 49.00% | 18.78% | 65.92 |
| 1 | A11c overlap | 65.66% | 27.28% | 7.06% | 65.65% | 10.53% | 203.03 |
| 1 | keyed PK subscriptions | 80.61% | 33.00% | 3.53% | 63.47% | 12.67% | 127.77 |
| 1 | Wide batch insert | 99.26% | 73.36% | 0.10% | 26.54% | 0.00% | 27450.00 |
| 2 | A11c baseline | 64.09% | 51.85% | 1.34% | 46.81% | 0.00% | 37.36 |
| 2 | A11c disjoint | 62.36% | 46.06% | 0.83% | 53.11% | 11.40% | 30.08 |
| 2 | A11c overlap | 62.43% | 25.25% | 0.93% | 73.82% | 8.68% | 91.61 |
| 2 | keyed PK subscriptions | 81.49% | 36.80% | 1.04% | 62.17% | 10.14% | 102.81 |
| 2 | Wide batch insert | 99.80% | 74.51% | 0.07% | 25.42% | 0.00% | 16359.00 |
| 3 | A11c baseline | 78.03% | 44.31% | 0.63% | 55.05% | 0.00% | 38.44 |
| 3 | A11c disjoint | 63.07% | 45.30% | 0.57% | 54.13% | 12.35% | 29.25 |
| 3 | A11c overlap | 62.70% | 33.19% | 2.45% | 64.36% | 9.11% | 79.65 |
| 3 | keyed PK subscriptions | 79.60% | 30.66% | 0.32% | 69.01% | 13.03% | 68.22 |
| 3 | Wide batch insert | 98.98% | 71.30% | 0.07% | 28.63% | 0.00% | 14894.00 |

## Stream completion and reader reply split

| pass | workload | requeries | changed / unchanged / discarded | requery_await_us / avg | dispatcher_parks | dispatch_wait_us / avg | reader_replies | reply_delivery_us / avg | stream_emits | emit_us / avg |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | A11c baseline | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |
| 1 | A11c disjoint | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |
| 1 | A11c overlap | 3223 | 27 / 1498 / 1698 | 599466 / 186.00 | 0 | 0 / 0.00 | 3223 | 56929 / 17.66 | 27 | 359 / 13.30 |
| 1 | keyed PK subscriptions | 1202 | 3 / 428 / 771 | 131265 / 109.21 | 0 | 0 / 0.00 | 1202 | 12938 / 10.76 | 3 | 40 / 13.33 |
| 1 | Wide batch insert | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |
| 2 | A11c baseline | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |
| 2 | A11c disjoint | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |
| 2 | A11c overlap | 3311 | 21 / 1446 / 1844 | 289722 / 87.50 | 0 | 0 / 0.00 | 3311 | 26486 / 8.00 | 21 | 246 / 11.71 |
| 2 | keyed PK subscriptions | 1162 | 3 / 382 / 777 | 98227 / 84.53 | 0 | 0 / 0.00 | 1162 | 7827 / 6.74 | 3 | 40 / 13.33 |
| 2 | Wide batch insert | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |
| 3 | A11c baseline | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |
| 3 | A11c disjoint | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |
| 3 | A11c overlap | 3105 | 27 / 1299 / 1779 | 247693 / 79.77 | 0 | 0 / 0.00 | 3105 | 24700 / 7.95 | 27 | 176 / 6.52 |
| 3 | keyed PK subscriptions | 1115 | 3 / 322 / 790 | 69027 / 61.91 | 0 | 0 / 0.00 | 1115 | 8113 / 7.28 | 3 | 19 / 6.33 |
| 3 | Wide batch insert | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |

## Reading the table

- `writer_roundtrip_us` is measured on the main isolate around each writer request after the caller has entered the writer lock where applicable. It includes message copy/delivery, writer scheduling, worker execution, dirty-dependency fetch, and the reply.
- `writer_write_call_us` is measured on the writer isolate around `executeWrite` / `executeBatchWrite`. It includes Dart parameter packing plus the FFI/native write call.
- SQLite statement trace timing was researched for this experiment, but this build intentionally compiles SQLite with `SQLITE_OMIT_TRACE`. Changing that compile flag would alter the production SQLite build rather than adding a profile-only Dart counter.
- `residual / roundtrip` is the remainder after subtracting write-call and dirty-fetch wall from main-isolate roundtrip wall. Treat it as isolate messaging, event-loop scheduling, reply copy, and small measurement skew.
- `invalidate_us` is the existing `StreamEngine.onDependencyChanges` counter. It is outside writer roundtrip and is reported as a share of workload wall.
- `stream_requery_await_us` is accumulated per stream re-query, so overlapping re-queries can sum above workload wall. Use its average with `dispatcher_parks` / `dispatch_wait_us` to separate reader-pool queueing from tiny reply-delivery and controller-delivery costs.
- Stream completion counters are captured after the post-wall drain; `wall_ms` still stops immediately after the write loop.
