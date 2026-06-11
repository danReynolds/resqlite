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
| A11c baseline | 0 streams x 500 writes | 52.26 | 19502 | 500 | 0 | 0 | 32760 | 0 | 0 | 0 |
| A11c disjoint | 50 streams x 500 writes | 56.93 | 12224 | 500 | 14755 | 500 | 29950 | 0 | 0 | 0 |
| A11c overlap | 50 streams x 500 writes | 174.09 | 18645 | 500 | 19793 | 500 | 135652 | 0 | 0 | 78 |
| keyed PK subscriptions | 50 streams x 200 random writes | 31.76 | 6775 | 200 | 3701 | 200 | 21286 | 0 | 0 | 3 |

## Derived fractions

| workload | SQLite / wall | invalidation / wall | residual / wall | SQLite us/write | invalidation us/write | ns/intersection entry |
|---|---:|---:|---:|---:|---:|---:|
| A11c baseline | 37.32% | 0.00% | 62.68% | 39.00 | 0.00 | 0 |
| A11c disjoint | 21.47% | 25.92% | 52.61% | 24.45 | 29.51 | 170 |
| A11c overlap | 10.71% | 11.37% | 77.92% | 37.29 | 39.59 | 212 |
| keyed PK subscriptions | 21.33% | 11.65% | 67.02% | 33.88 | 18.50 | 105 |

## Reading the table

- `writer_sqlite_us` covers the SQLite-facing write call on the writer isolate: single-write execution or batch execution. Dirty-set harvest and reply send are outside this counter.
- `invalidate_us` is the main-isolate synchronous stream invalidation body already audited by exp 121.
- `residual_us` is the remaining local wall budget: writer isolate round-trip, dirty-set harvest, main-isolate await/reply scheduling, and any measurement overhead.
