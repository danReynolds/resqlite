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

Post-review rerun after resolving PR #101 feedback. The A/B summary above
remains the original baseline comparison; this detailed candidate table reflects
the corrected per-stream `stream_requery_await_us` accounting.

Profile-mode harness: `benchmark/profile/writer_wall_split_audit.dart`

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`)

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/writer_wall_split_audit.dart --repeats=3
```

## Counters

| pass | workload | shape | wall_ms | writer_requests | writer_roundtrip_us | writer_write_call_us | dirty_fetch_us | invalidate_us | invalidate_count |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | A11c baseline | 0 streams x 500 writes | 45.89 | 500 | 34882 | 22359 | 3440 | 0 | 0 |
| 1 | A11c disjoint | 50 streams x 500 writes | 38.36 | 500 | 20516 | 8632 | 2425 | 8154 | 500 |
| 1 | A11c overlap | 50 streams x 500 writes | 42.52 | 500 | 21432 | 7822 | 1978 | 11706 | 500 |
| 1 | keyed PK subscriptions | 50 streams x 200 random writes | 12.06 | 200 | 8478 | 4249 | 397 | 2290 | 200 |
| 1 | Wide batch insert | 10000 rows x 20 params | 36.62 | 1 | 36326 | 22516 | 13 | 0 | 0 |
| 2 | A11c baseline | 0 streams x 500 writes | 21.42 | 500 | 15904 | 8462 | 100 | 0 | 0 |
| 2 | A11c disjoint | 50 streams x 500 writes | 22.05 | 500 | 13277 | 6263 | 55 | 2620 | 500 |
| 2 | A11c overlap | 50 streams x 500 writes | 25.54 | 500 | 14818 | 6865 | 31 | 4350 | 500 |
| 2 | keyed PK subscriptions | 50 streams x 200 random writes | 9.73 | 200 | 6786 | 3527 | 40 | 1929 | 200 |
| 2 | Wide batch insert | 10000 rows x 20 params | 26.74 | 1 | 26666 | 17351 | 13 | 0 | 0 |
| 3 | A11c baseline | 0 streams x 500 writes | 19.93 | 500 | 15023 | 7589 | 33 | 0 | 0 |
| 3 | A11c disjoint | 50 streams x 500 writes | 20.78 | 500 | 12764 | 5835 | 29 | 2831 | 500 |
| 3 | A11c overlap | 50 streams x 500 writes | 25.26 | 500 | 15145 | 7176 | 73 | 4539 | 500 |
| 3 | keyed PK subscriptions | 50 streams x 200 random writes | 8.44 | 200 | 5901 | 3466 | 11 | 1683 | 200 |
| 3 | Wide batch insert | 10000 rows x 20 params | 21.60 | 1 | 21556 | 15084 | 6 | 0 | 0 |

## Derived split

| pass | workload | roundtrip / wall | write call / roundtrip | dirty fetch / roundtrip | residual / roundtrip | invalidate / wall | us per writer request |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | A11c baseline | 76.01% | 64.10% | 9.86% | 26.04% | 0.00% | 69.76 |
| 1 | A11c disjoint | 53.48% | 42.07% | 11.82% | 46.11% | 21.26% | 41.03 |
| 1 | A11c overlap | 50.40% | 36.50% | 9.23% | 54.27% | 27.53% | 42.86 |
| 1 | keyed PK subscriptions | 70.27% | 50.12% | 4.68% | 45.20% | 18.98% | 42.39 |
| 1 | Wide batch insert | 99.21% | 61.98% | 0.04% | 37.98% | 0.00% | 36326.00 |
| 2 | A11c baseline | 74.24% | 53.21% | 0.63% | 46.16% | 0.00% | 31.81 |
| 2 | A11c disjoint | 60.20% | 47.17% | 0.41% | 52.41% | 11.88% | 26.55 |
| 2 | A11c overlap | 58.03% | 46.33% | 0.21% | 53.46% | 17.03% | 29.64 |
| 2 | keyed PK subscriptions | 69.73% | 51.97% | 0.59% | 47.44% | 19.82% | 33.93 |
| 2 | Wide batch insert | 99.72% | 65.07% | 0.05% | 34.88% | 0.00% | 26666.00 |
| 3 | A11c baseline | 75.37% | 50.52% | 0.22% | 49.26% | 0.00% | 30.05 |
| 3 | A11c disjoint | 61.43% | 45.71% | 0.23% | 54.06% | 13.62% | 25.53 |
| 3 | A11c overlap | 59.95% | 47.38% | 0.48% | 52.14% | 17.97% | 30.29 |
| 3 | keyed PK subscriptions | 69.90% | 58.74% | 0.19% | 41.08% | 19.94% | 29.50 |
| 3 | Wide batch insert | 99.78% | 69.98% | 0.03% | 30.00% | 0.00% | 21556.00 |

## Stream completion and reader reply split

| pass | workload | requeries | changed / unchanged / discarded | requery_await_us / avg | dispatcher_parks | dispatch_wait_us / avg | reader_replies | reply_delivery_us / avg | stream_emits | emit_us / avg |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | A11c baseline | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |
| 1 | A11c disjoint | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |
| 1 | A11c overlap | 2150 | 5 / 45 / 2100 | 1980450 / 921.14 | 0 | 0 / 0.00 | 43 | 2366 / 55.02 | 5 | 10 / 2.00 |
| 1 | keyed PK subscriptions | 2050 | 3 / 47 / 2000 | 634800 / 309.66 | 0 | 0 / 0.00 | 41 | 1655 / 40.37 | 3 | 9 / 3.00 |
| 1 | Wide batch insert | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |
| 2 | A11c baseline | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |
| 2 | A11c disjoint | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |
| 2 | A11c overlap | 1550 | 5 / 45 / 1500 | 1289350 / 831.84 | 0 | 0 / 0.00 | 31 | 849 / 27.39 | 5 | 6 / 1.20 |
| 2 | keyed PK subscriptions | 2050 | 3 / 47 / 2000 | 458950 / 223.88 | 0 | 0 / 0.00 | 41 | 915 / 22.32 | 3 | 10 / 3.33 |
| 2 | Wide batch insert | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |
| 3 | A11c baseline | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |
| 3 | A11c disjoint | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |
| 3 | A11c overlap | 1500 | 5 / 45 / 1450 | 1277000 / 851.33 | 0 | 0 / 0.00 | 30 | 750 / 25.00 | 5 | 7 / 1.40 |
| 3 | keyed PK subscriptions | 2000 | 3 / 47 / 1950 | 416800 / 208.40 | 0 | 0 / 0.00 | 40 | 769 / 19.23 | 3 | 4 / 1.33 |
| 3 | Wide batch insert | 0 | 0 / 0 / 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 | 0 | 0 / 0.00 |

## Reading the table

- `writer_roundtrip_us` is measured on the main isolate around each writer request after the caller has entered the writer lock where applicable. It includes message copy/delivery, writer scheduling, worker execution, dirty-dependency fetch, and the reply.
- `writer_write_call_us` is measured on the writer isolate around `executeWrite` / `executeBatchWrite`. It includes Dart parameter packing plus the FFI/native write call.
- SQLite statement trace timing was researched for this experiment, but this build intentionally compiles SQLite with `SQLITE_OMIT_TRACE`. Changing that compile flag would alter the production SQLite build rather than adding a profile-only Dart counter.
- `residual / roundtrip` is the remainder after subtracting write-call and dirty-fetch wall from main-isolate roundtrip wall. Treat it as isolate messaging, event-loop scheduling, reply copy, and small measurement skew.
- `invalidate_us` is the existing `StreamEngine.onDependencyChanges` counter. It is outside writer roundtrip and is reported as a share of workload wall.
- `stream_requery_await_us` is accumulated per stream re-query, so overlapping re-queries can sum above workload wall. Use its average with `dispatcher_parks` / `dispatch_wait_us` to separate reader-pool queueing from tiny reply-delivery and controller-delivery costs.
- Stream completion counters are captured after the post-wall drain; `wall_ms` still stops immediately after the write loop.
