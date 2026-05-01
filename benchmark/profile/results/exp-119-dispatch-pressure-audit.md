# Experiment 119 - Dispatch Pressure Audit

Profile-mode harness: `benchmark/profile/dispatch_pressure_audit.dart`

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`)

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/dispatch_pressure_audit.dart --markdown
```

| workload | shape | wall_ms | parked_total | wake_retry_total | max_parked | invalidate_count | intersection_entries | emissions | observed_hits |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| direct reads control | 32 concurrent selects, median burst | 1.18 | 28 | 0 | 28 | 0 | 0 | 0 | 0 |
| A11c baseline | 0 streams x 500 writes | 98.37 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| A11c disjoint | 50 streams x 500 writes | 105.59 | 0 | 0 | 0 | 500 | 25000 | 0 | 0 |
| A11c overlap | 50 streams x 500 writes | 149.54 | 3590 | 0 | 46 | 500 | 25000 | 7 | 0 |
| keyed PK subscriptions | 50 streams x 200 random writes | 431.56 | 1152 | 0 | 46 | 200 | 10000 | 3 | 3 |

## Reading the table

- `direct reads control` intentionally overloads the reader pool. It should still park, but FIFO dispatch should keep `wake_retry_total` at zero.
- A11c rows use the same 50-stream, 20-column shape as the release many-streams writer-throughput workload. Disjoint writes update `c`; overlap writes update `a`, which every stream projects.
- `keyed PK subscriptions` mirrors the release keyed-PK miss-path: 50 streams watch fixed primary keys while 200 deterministic writes target random rows.

## Interpretation

The post-FIFO signal is not wake amplification: `wake_retry_total` is zero in every workload. The remaining dispatch pressure is admission/completion shaped. Overlap and keyed-PK stream workloads still create parked dispatchers even though visible emissions are heavily coalesced or hash-suppressed.

A follow-up dispatch experiment should therefore target stream re-query admission or completion-side scheduling. Another ReaderPool wake-policy change needs a new nonzero retry signal before it is worth trying.
