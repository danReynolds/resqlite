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
| A11c baseline | 0 streams x 500 writes | 84.04 | 23605 | 500 | 0 | 0 | 60432 | 0 | 0 | 0 |
| A11c disjoint | 50 streams x 500 writes | 93.99 | 18339 | 500 | 25527 | 500 | 50128 | 0 | 0 | 0 |
| A11c overlap | 50 streams x 500 writes | 223.20 | 26469 | 500 | 41638 | 500 | 155095 | 0 | 0 | 29 |
| keyed PK subscriptions | 50 streams x 200 random writes | 43.69 | 7364 | 200 | 8141 | 200 | 28186 | 0 | 0 | 3 |

## Derived fractions

| workload | SQLite / wall | invalidation / wall | residual / wall | SQLite us/write | invalidation us/write | ns/intersection entry |
|---|---:|---:|---:|---:|---:|---:|
| A11c baseline | 28.09% | 0.00% | 71.91% | 47.21 | 0.00 | 0 |
| A11c disjoint | 19.51% | 27.16% | 53.33% | 36.68 | 51.05 | 353 |
| A11c overlap | 11.86% | 18.65% | 69.49% | 52.94 | 83.28 | 416 |
| keyed PK subscriptions | 16.85% | 18.63% | 64.51% | 36.82 | 40.70 | 297 |

## Reading the table

- `writer_sqlite_us` covers SQLite-facing work on the writer isolate: single-write execution, batch execution, transaction reads, and transaction commit/release control. Dirty-set harvest and reply send are outside this counter.
- `invalidate_us` is the main-isolate synchronous stream invalidation body already audited by exp 121.
- `residual_us` is the remaining local wall budget: writer isolate round-trip, dirty-set harvest, main-isolate await/reply scheduling, and any measurement overhead.
