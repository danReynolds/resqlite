# Experiment 147 - Writer SQLite Wall Split Audit

Profile-mode harness: `benchmark/profile/writer_sqlite_wall_audit.dart`

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`)

`wall_us` is writer-side burst wall; the stopwatch stops on the last write. `writer_sqlite_us` is measured inside the writer isolate around the SQLite-facing write call and carried back in the write response. `residual_us = wall_us - writer_sqlite_us - invalidate_us`.

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/writer_sqlite_wall_audit.dart --markdown
```

## Counters

| workload | shape | wall_ms | writer_sqlite_us | writer_sqlite_count | invalidate_us | invalidate_count | residual_us | parked_total | max_parked | emissions |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 0 streams x 500 writes | 55.32 | 18370 | 500 | 0 | 0 | 36953 | 0 | 0 | 0 |
| A11c disjoint | 50 streams x 500 writes | 86.32 | 14234 | 500 | 11393 | 500 | 60695 | 0 | 0 | 0 |
| A11c overlap | 50 streams x 500 writes | 93.86 | 16032 | 500 | 35049 | 500 | 42780 | 0 | 0 | 500 |
| keyed PK subscriptions | 50 streams x 200 random writes | 23.93 | 3989 | 200 | 10130 | 200 | 9806 | 0 | 0 | 3 |

## Derived fractions

| workload | SQLite / wall | invalidation / wall | residual / wall | SQLite us/write | invalidation us/write | ns/intersection entry |
|---|---:|---:|---:|---:|---:|---:|
| A11c baseline | 33.20% | 0.00% | 66.80% | 36.74 | 0.00 | 0 |
| A11c disjoint | 16.49% | 13.20% | 70.31% | 28.47 | 22.79 | 166 |
| A11c overlap | 17.08% | 37.34% | 45.58% | 32.06 | 70.10 | 136 |
| keyed PK subscriptions | 16.67% | 42.34% | 40.99% | 19.95 | 50.65 | 56 |

## Reading the table

- `writer_sqlite_us` covers the SQLite-facing write call on the writer isolate: single-write execution or batch execution. Dirty-set harvest and reply send are outside this counter.
- `invalidate_us` is the main-isolate synchronous stream invalidation body already audited by exp 121.
- `residual_us` is the remaining local wall budget: writer isolate round-trip, dirty-set harvest, main-isolate await/reply scheduling, and any measurement overhead.
