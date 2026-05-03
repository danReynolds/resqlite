# Experiment 121 - Invalidation Traversal Audit

Profile-mode harness: `benchmark/profile/invalidation_traversal_audit.dart`

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`)

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/invalidation_traversal_audit.dart --markdown
```

## Counters

| workload | shape | wall_ms | invalidate_us | invalidate_count | intersection_us | intersection_entries | parked_total | max_parked | emissions |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 0 streams x 500 writes | 92.40 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| A11c disjoint | 50 streams x 500 writes | 91.97 | 8913 | 500 | 3249 | 25000 | 0 | 0 | 0 |
| A11c overlap | 50 streams x 500 writes | 139.21 | 9693 | 500 | 2226 | 25000 | 0 | 0 | 24 |
| keyed PK subscriptions | 50 streams x 200 random writes | 224.74 | 2014 | 200 | 510 | 10000 | 0 | 0 | 3 |

## Derived fractions

| workload | invalidate_us / wall_ms | intersection_us / wall_ms | us per write | ns per intersection entry |
|---|---:|---:|---:|---:|
| A11c baseline | 0.00% | 0.00% | 0.00 | 0 |
| A11c disjoint | 9.69% | 3.53% | 17.83 | 130 |
| A11c overlap | 6.96% | 1.60% | 19.39 | 89 |
| keyed PK subscriptions | 0.90% | 0.23% | 10.07 | 51 |

## Reading the table

- `invalidate_us` is the cumulative wall-clock microseconds spent in the synchronous body of `StreamEngine.onDependencyChanges` — `_tableIndex` lookup, per-entry column intersection probes, dirty/in-flight scheduling, and the synchronous portion of `_flushQueue` that admits stream re-queries before any await hop.
- `intersection_us` is the subset spent specifically inside `entryCols.intersects(changedCols)` calls. Their ratio (intersection_us / invalidate_us) shows how much of invalidation cost is column-set intersection versus the rest of the traversal (lookup, scheduling, flush bookkeeping).
- `invalidate_us / wall_ms` is the fraction of total workload wall attributable to writer-side invalidation traversal. A11c overlap is the workload exp 119/120 flagged as the next signal source; if that fraction is small, future dispatch work should branch off invalidation and toward completion-side or writer-side wall.
- `parked_total` and `max_parked` should both stay at zero post-exp-120, reproducing exp 120's acceptance signal as a sanity check.

## Interpretation

See `experiments/121-invalidation-traversal-audit.md` for the decision and follow-up notes attached to these numbers.
