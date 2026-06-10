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
| A11c baseline | 0 streams x 500 writes | 72.65 | 22637 | 500 | 0 | 0 | 50012 | 0 | 0 | 0 |
| A11c disjoint | 50 streams x 500 writes | 114.21 | 20228 | 500 | 26671 | 500 | 67315 | 0 | 0 | 0 |
| A11c overlap | 50 streams x 500 writes | 206.36 | 19671 | 500 | 137389 | 500 | 49298 | 0 | 0 | 500 |
| keyed PK subscriptions | 50 streams x 200 random writes | 48.06 | 5918 | 200 | 21862 | 200 | 20285 | 0 | 0 | 3 |

## Derived fractions

| workload | SQLite / wall | invalidation / wall | residual / wall | SQLite us/write | invalidation us/write | ns/intersection entry |
|---|---:|---:|---:|---:|---:|---:|
| A11c baseline | 31.16% | 0.00% | 68.84% | 45.27 | 0.00 | 0 |
| A11c disjoint | 17.71% | 23.35% | 58.94% | 40.46 | 53.34 | 339 |
| A11c overlap | 9.53% | 66.58% | 23.89% | 39.34 | 274.78 | 233 |
| keyed PK subscriptions | 12.31% | 45.48% | 42.20% | 29.59 | 109.31 | 356 |

## Reading the table

- `writer_sqlite_us` covers the SQLite-facing write call on the writer isolate: single-write execution or batch execution. Dirty-set harvest and reply send are outside this counter.
- `invalidate_us` is the main-isolate synchronous stream invalidation body already audited by exp 121.
- `residual_us` is the remaining local wall budget: writer isolate round-trip, dirty-set harvest, main-isolate await/reply scheduling, and any measurement overhead.
