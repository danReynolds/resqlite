# Experiment 143: Tracelite profile insight audit

**Date:** 2026-06-08
**Status:** Accepted
**Direction:** `measurement-system`
**Benchmark Run:** None

## Problem

Resqlite now routes its preferred profile workflow through Tracelite, but a
scheduled experimenter still needs to know whether that path produces more than
a trace file. The useful question for this pass was not "can Tracelite run?" It
was whether the current Tracelite artifacts make performance characteristics
clear enough to guide future optimization work.

## Hypothesis

A pinned Tracelite profile run should provide decision-useful structure that a
release peer comparison does not: dispatch floors, floor-subtracted work,
operation tails, memory deltas, SQLite diagnostics, allocation counters, source
provenance, and graph data. If the generated insight layer is strong enough, a
future runner should be able to read `insights.md` before opening raw JSON.

## Approach

Ran the canonical profile wrapper twice on current `origin/main` with the pinned
Tracelite checkout and ARM64 Dart runtime:

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

The first run exported graph data and validated it. The repeat skipped graph
export and was used only to check whether the decomposition was stable.

Raw trace regions remain in `build/` and are not committed. The aggregate record
is committed at
[`benchmark/profile/results/exp-143-tracelite-profile-insights.md`](../benchmark/profile/results/exp-143-tracelite-profile-insights.md).

## Results

Tracelite profile artifacts:

- `build/tracelite-profile/exp-143-profile-baseline/workload-summary.md`
- `build/tracelite-profile/exp-143-profile-baseline/insights.md`
- `build/tracelite-profile/exp-143-profile-baseline/graph-data/`
- `build/tracelite-profile/exp-143-profile-repeat/workload-summary.md`
- `build/tracelite-profile/exp-143-profile-repeat/insights.md`

The full baseline graph export validated successfully and produced:

| dataset | rows |
|---|---:|
| `workload_summary` | 4 |
| `workload_operations` | 41 |
| `workload_memory` | 132 |
| `workload_fanout` | 0 |

The headline profile numbers:

| run | workload | op | p50 us | p99 us | max us | work us | rss delta MB | wal delta B | rows decoded | cells decoded |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | noop | select | 12 | 93 | 459 | - | 1.531 | 0 | 10000 | 10000 |
| baseline | single_insert | execute | 20 | 170 | 7829 | 4 | 14.547 | 1713920 | 0 | 0 |
| baseline | point_query | select | 11 | 78 | 2048 | 0 | 18.297 | 0 | 50000 | 300000 |
| baseline | merge_rounds | executeBatch | 93 | 890 | 4136 | 77 | 0.485 | 8240 | 0 | 0 |
| repeat | noop | select | 12 | 103 | 1416 | - | 2.907 | 0 | 10000 | 10000 |
| repeat | single_insert | execute | 21 | 106 | 4455 | 5 | 12.391 | 1713920 | 0 | 0 |
| repeat | point_query | select | 13 | 50 | 1402 | 1 | 20.281 | 0 | 50000 | 300000 |
| repeat | merge_rounds | executeBatch | 93 | 510 | 912 | 77 | 0.079 | 8240 | 0 | 0 |

Noop floors were stable in both runs:

| run | reader floor us | writer floor us |
|---|---:|---:|
| baseline | 12 | 16 |
| repeat | 12 | 16 |

`insights.md` was much thinner than the structured data. It reported only:

| severity | finding | detail |
|---|---|---|
| `good` | Workload summaries loaded | 4 workload(s) are available for inspection. |

## Analysis

Tracelite did demonstrate value, but most of that value is currently in the
structured artifacts rather than the generated prose.

The dispatch-floor split is immediately useful. Point queries are at or barely
above the 12 us reader floor, with 0-1 us of floor-subtracted work. That argues
against more point-query SQL or decode micro-optimization as the next target;
the remaining median cost is dispatch shaped.

Merge rounds show the opposite shape. Their p50 is stable at 93 us, with 77 us
of floor-subtracted work in both runs. That is the clearest current target for
batch encoding, parameter packing, or SQLite step-path analysis.

Single inserts sit near the writer floor at the median: 20-21 us p50 against a
16 us writer floor. Tracelite also surfaces the storage side effect that wall
time alone would hide: WAL growth is stable at 1,713,920 bytes across runs.

Point queries show why memory diagnostics matter. The median wall time says
"dispatch-bound," but the profile still records 50,000 rows and 300,000 cells
decoded plus roughly 18-20 MB RSS delta. That is useful signal for future
allocation-focused work where time alone would miss the cost.

The repeat also confirms a known methodology caveat: tails are noisy. p99 and
max moved substantially between the two runs while p50, dispatch floors, and
work medians stayed stable. A future p99 claim should use a multi-run A/B.

## Decision

**Accept for review - measurement.**

The Tracelite profile workflow is worth keeping as the default experiment path.
It captures the right low-level facts in one pinned, provenance-recorded run and
exports graph data that can feed the docs/dashboard path.

The follow-up is not another legacy profile harness. It is a Tracelite
interpretation improvement: `tracelite explain` should emit workload-summary
rules for dispatch-bound, work-bound, memory-heavy, and tail-noisy workloads so
future runners do not need to reverse-engineer those conclusions from JSON.

## Validation

- Ran pinned Tracelite profile workflow with graph export and validation.
- Ran one repeat pinned Tracelite profile workflow without graph export.
- Verified the first run produced 4 workload summary rows, 41 operation metric rows, 132 memory metric rows, and valid graph data.
