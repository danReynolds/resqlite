# Experiment 169 Tracelite Workload Insight Aggregate

Date: 2026-06-14

Command:

```text
dart run benchmark/profile/run_tracelite_profile.dart \
  --tracelite-root=/Users/dan/Coding/tracelite \
  --tracelite-revision=11159638962f5176678f02551a78180f5b9d3bba \
  --label=exp-169-tracelite-workload-insights \
  --out-dir=build/tracelite-profile/exp-169-tracelite-workload-insights \
  --no-graph-data
```

Environment:

- Resqlite branch: `exp-169-tracelite-workload-insights`
- Tracelite root: `/Users/dan/Coding/tracelite`
- Tracelite revision: `11159638962f5176678f02551a78180f5b9d3bba`
- Tracelite dirty: false
- Runtime: `/Users/dan/Coding/tracelite/build/libtracelite_runtime.dylib`

## Operation Summary

Noop floors:

| floor | value |
|---|---:|
| reader | 8 us |
| writer | 11 us |

Workload operation rows:

| workload | op | count | p50 us | p90 us | p99 us | max us | work us | rss delta MB | wal delta B | rows decoded | cells decoded |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| noop | select | 10000 | 8 | 14 | 41 | 301 | - | 5.907 | 0 | 10000 | 10000 |
| noop | execute | 10000 | 11 | 19 | 49 | 268 | - | 5.907 | 0 | 10000 | 10000 |
| single_insert | execute | 10000 | 16 | 22 | 48 | 647 | 5 | 23.093 | 1713920 | 0 | 0 |
| point_query | select | 50000 | 8 | 13 | 33 | 1817 | 0 | 22.110 | 0 | 50000 | 300000 |
| merge_rounds | executeBatch | 1000 | 80 | 110 | 505 | 749 | 69 | -1.985 | 8240 | 0 | 0 |

## Insight IDs

`tracelite explain` produced the workload-summary insight IDs expected by the
profile wrapper:

| id | headline |
|---|---|
| `workload_tail_spread` | single-run tails are much wider than medians |
| `workload_allocation_signal` | point_query decoded 50,000 rows / 300,000 cells |
| `workload_dispatch_bound` | point_query/select has 0 us floor-subtracted work over 8 us median |
| `workload_rss_signal` | single_insert and point_query show visible RSS movement |
| `workload_wal_signal` | single_insert and merge_rounds record WAL growth |
| `workload_work_bound` | merge_rounds/executeBatch has 69 us work over 80 us median |
| `workload_dispatch_floors` | reader and writer noop floors are available |
| `workload_loaded` | four workload summaries loaded |

The new Resqlite-side guard validates the stable interpretation contract:
dispatch floors, work-bound, tail-spread, RSS, allocation, and WAL insight IDs
must be present. `workload_dispatch_bound` is intentionally treated as a useful
output rather than a hard guard because the upstream rule is threshold-based and
can disappear when point-query floor-subtracted work lands slightly above the
near-zero band on a particular machine.

## Conclusion

The exp 143 interpretation gap is consumed for the profile path. The Tracelite
profile artifact now explains the same dispatch/work/memory/tail shape that exp
143 previously required manual JSON inspection to recover, and
`benchmark/profile/run_tracelite_profile.dart` fails if those substantive
workload-summary insights regress to a thin "loaded only" output.
