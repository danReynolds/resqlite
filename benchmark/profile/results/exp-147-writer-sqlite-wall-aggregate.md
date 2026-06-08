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
| A11c baseline | 0 streams x 500 writes | 86.88 | 23071 | 500 | 0 | 0 | 63810 | 0 | 0 | 0 |
| A11c disjoint | 50 streams x 500 writes | 92.78 | 17738 | 500 | 23833 | 500 | 51205 | 0 | 0 | 0 |
| A11c overlap | 50 streams x 500 writes | 166.75 | 15678 | 500 | 31389 | 500 | 119679 | 0 | 0 | 35 |
| keyed PK subscriptions | 50 streams x 200 random writes | 36.95 | 6679 | 200 | 6897 | 200 | 23370 | 0 | 0 | 3 |

## Derived fractions

| workload | SQLite / wall | invalidation / wall | residual / wall | SQLite us/write | invalidation us/write | ns/intersection entry |
|---|---:|---:|---:|---:|---:|---:|
| A11c baseline | 26.55% | 0.00% | 73.45% | 46.14 | 0.00 | 0 |
| A11c disjoint | 19.12% | 25.69% | 55.19% | 35.48 | 47.67 | 328 |
| A11c overlap | 9.40% | 18.82% | 71.77% | 31.36 | 62.78 | 231 |
| keyed PK subscriptions | 18.08% | 18.67% | 63.25% | 33.40 | 34.48 | 246 |

## Reading the table

- `writer_sqlite_us` covers the SQLite-facing write call on the writer isolate: single-write execution or batch execution. Dirty-set harvest and reply send are outside this counter.
- `invalidate_us` is the main-isolate synchronous stream invalidation body already audited by exp 121.
- `residual_us` is the remaining local wall budget: writer isolate round-trip, dirty-set harvest, main-isolate await/reply scheduling, and any measurement overhead.
