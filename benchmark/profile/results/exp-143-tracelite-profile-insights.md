# Experiment 143 Tracelite Profile Aggregate

Date: 2026-06-08

Commands:

```text
/Users/dan/Coding/flutter_arm64/bin/cache/dart-sdk/bin/dart run \
  benchmark/profile/run_tracelite_profile.dart \
  --tracelite-root=/Users/dan/Coding/tracelite \
  --dart=/Users/dan/Coding/flutter_arm64/bin/cache/dart-sdk/bin/dart \
  --label=exp-143-profile-baseline \
  --out-dir=build/tracelite-profile/exp-143-profile-baseline

/Users/dan/Coding/flutter_arm64/bin/cache/dart-sdk/bin/dart run \
  benchmark/profile/run_tracelite_profile.dart \
  --tracelite-root=/Users/dan/Coding/tracelite \
  --dart=/Users/dan/Coding/flutter_arm64/bin/cache/dart-sdk/bin/dart \
  --label=exp-143-profile-repeat \
  --out-dir=build/tracelite-profile/exp-143-profile-repeat \
  --no-graph-data
```

Environment:

- Resqlite branch: `exp-143-tracelite-profile-insights`
- Resqlite base: `09633b8`
- Tracelite root: `/Users/dan/Coding/tracelite`
- Tracelite revision: `2e1cd54087aaef7bd7f130c2bde2fca64fc48d8a`
- Tracelite dirty: false
- Dart: `/Users/dan/Coding/flutter_arm64/bin/cache/dart-sdk/bin/dart`
- Dart version: `3.11.5 stable macos_arm64`
- Runtime: `/Users/dan/Coding/tracelite/build/libtracelite_runtime.dylib`

## Workload Operation Results

| run | workload | op | p50 us | p90 us | p99 us | max us | work us | rss delta MB | page cache delta B | stmt delta B | wal delta B | rows decoded | cells decoded |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | noop | select | 12 | 27 | 93 | 459 | - | 1.531 | 0 | 8144 | 0 | 10000 | 10000 |
| baseline | single_insert | execute | 20 | 31 | 170 | 7829 | 4 | 14.547 | 0 | 0 | 1713920 | 0 | 0 |
| baseline | point_query | select | 11 | 22 | 78 | 2048 | 0 | 18.297 | -17408 | 0 | 0 | 50000 | 300000 |
| baseline | merge_rounds | executeBatch | 93 | 203 | 890 | 4136 | 77 | 0.485 | 21760 | 2096 | 8240 | 0 | 0 |
| repeat | noop | select | 12 | 30 | 103 | 1416 | - | 2.907 | 0 | 8144 | 0 | 10000 | 10000 |
| repeat | single_insert | execute | 21 | 29 | 106 | 4455 | 5 | 12.391 | 0 | 0 | 1713920 | 0 | 0 |
| repeat | point_query | select | 13 | 19 | 50 | 1402 | 1 | 20.281 | -17408 | 0 | 0 | 50000 | 300000 |
| repeat | merge_rounds | executeBatch | 93 | 139 | 510 | 912 | 77 | 0.079 | 21760 | 2096 | 8240 | 0 | 0 |

Noop floors:

| run | reader floor us | writer floor us |
|---|---:|---:|
| baseline | 12 | 16 |
| repeat | 12 | 16 |

## Tracelite Artifact Coverage

The full baseline run exported and validated graph data:

| dataset | rows |
|---|---:|
| `workload_summary` | 4 |
| `workload_operations` | 41 |
| `workload_memory` | 132 |
| `workload_fanout` | 0 |
| `scenario_series` | 0 |
| `peer_summary` | 0 |
| `decision_summary` | 0 |
| `decision_comparisons` | 0 |

The `workload_fanout` dataset is empty because the current canonical
Tracelite profile workload driver does not exercise stream subscriptions.

The generated `insights.md` was intentionally much thinner than the structured
data: it only reported that four workload summaries loaded. Human analysis still
had to infer dispatch-bound, work-bound, and memory-heavy characteristics from
`workload-summary.json` and `graph-data/workload-operations.json`.

## Interpretation

- Point query is dispatch-bound under this profile build. Its p50 is at or just
  above the 12 us reader floor, and floor-subtracted work is 0-1 us. Another
  point-query micro-optimization needs a dispatch mechanism change, not more SQL
  work reduction.
- Merge rounds are work-bound relative to writer dispatch. p50 is stable at
  93 us, and floor-subtracted work is 77 us in both runs. This is the workload
  where parameter packing, SQLite stepping, and batch encoding work should be
  investigated.
- Single inserts are mostly writer-dispatch-bound at the median: 20-21 us p50
  against a 16 us writer floor. They still have heavy storage side effects:
  WAL growth is stable at 1,713,920 bytes across runs.
- Point query has a visible allocation/memory signature even though wall time is
  dispatch-bound: 50,000 rows and 300,000 cells decoded, with RSS delta around
  18-20 MB. That is useful evidence for allocation-oriented experiments where
  wall time alone would say "nothing to do."
- Tail latency is noisy in these single-pass traces. p99 and max moved
  materially between baseline and repeat while p50/work stayed stable, so this
  profile mode should use repeated runs before making p99 claims.

## Conclusion

Tracelite already demonstrates value for experiment work by collecting operation
percentiles, dispatch-floor-subtracted work, memory counters, allocation
counters, source provenance, and dashboard-ready graph data in one pinned run.

The remaining gap is interpretation. The `explain` stage should graduate from
"workloads loaded" to workload-summary rules that identify dispatch-bound,
work-bound, memory-heavy, and tail-noisy workloads directly from the structured
data.
