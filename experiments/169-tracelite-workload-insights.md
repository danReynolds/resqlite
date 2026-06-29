# Experiment 169: Tracelite workload-summary insight guard

**Date:** 2026-06-14
**Status:** Accepted
**Direction:** `measurement-system`
**Benchmark Run:** Tracelite profile, `exp-169-tracelite-workload-insights`

## Problem

[Exp 143](143-tracelite-profile-insights.md) found that the pinned Tracelite
profile workflow was collecting decision-useful structured evidence, but the
generated `insights.md` was too thin. It loaded the workload summary without
calling out the conclusions a scheduled Resqlite experimenter needs first:
dispatch floors, dispatch-bound point queries, work-bound merge rounds, memory
and allocation signal, WAL side effects, and single-run tail spread.

Since then, the Tracelite revision Resqlite can run against has gained
workload-summary insight rules. The remaining Resqlite gap was not another
profile harness. It was a guard that proves the canonical profile workflow is
actually consuming those rules instead of silently falling back to "workloads
loaded" coverage.

## Hypothesis

Adding a Resqlite-side validation step after `tracelite explain` will turn exp
143's manual interpretation requirement into an artifact contract. The profile
wrapper should fail if the workload-summary source lacks the substantive
insight IDs for dispatch floors, work-bound operations, tail spread, RSS,
allocation, and WAL movement.

Accept this as measurement-system work if:

- the profile wrapper still delegates summary and insight generation to
  Tracelite;
- a thin `insights.json` fixture fails locally;
- the real Tracelite profile run produces the expected workload insight layer;
- no runtime Resqlite API or hot-path behavior changes.

## Approach

`benchmark/profile/run_tracelite_profile.dart` now validates
`insights.json` after the existing `explain tracelite workload summary` step.
It finds the `tracelite.workload_summary.v1` source in the
`tracelite.insights.v1` envelope and requires these stable IDs:

```text
workload_dispatch_floors
workload_work_bound
workload_tail_spread
workload_rss_signal
workload_allocation_signal
workload_wal_signal
```

The guard deliberately does not require `workload_dispatch_bound`. That rule is
valuable when emitted, and the final run did emit it for point queries, but it
is threshold-based: on one earlier local pass point-query floor-subtracted work
was 2 us over a 9 us median, so Tracelite correctly skipped the near-zero-work
classification. Requiring it would make the wrapper brittle across machines.

`test/tracelite_profile_workflow_test.dart` adds two fixture-driven tests:

- a complete insights artifact passes and writes the normal manifest;
- a thin artifact containing only `workload_loaded` exits 65 and reports the
  missing IDs.

No production Resqlite runtime code changed.

## Results

Focused wrapper tests:

```text
dart test test/tracelite_profile_workflow_test.dart
```

Result: 3 tests passed.

Real profile validation:

```text
dart run benchmark/profile/run_tracelite_profile.dart \
  --tracelite-root=/Users/dan/Coding/tracelite \
  --tracelite-revision=11159638962f5176678f02551a78180f5b9d3bba \
  --label=exp-169-tracelite-workload-insights \
  --out-dir=build/tracelite-profile/exp-169-tracelite-workload-insights \
  --no-graph-data
```

The wrapper completed and printed:

```text
validated workload-summary insights: 8 ids
```

The committed aggregate is
[`benchmark/profile/results/exp-169-tracelite-workload-insights.md`](../benchmark/profile/results/exp-169-tracelite-workload-insights.md).

Headline profile rows:

| workload | op | p50 us | p99 us | max us | work us | rss delta MB | wal delta B | decoded |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| noop | select | 8 | 41 | 301 | - | 5.907 | 0 | 10000 rows / 10000 cells |
| single_insert | execute | 16 | 48 | 647 | 5 | 23.093 | 1713920 | 0 rows / 0 cells |
| point_query | select | 8 | 33 | 1817 | 0 | 22.110 | 0 | 50000 rows / 300000 cells |
| merge_rounds | executeBatch | 80 | 505 | 749 | 69 | -1.985 | 8240 | 0 rows / 0 cells |

Generated insight IDs:

| id | signal |
|---|---|
| `workload_dispatch_floors` | reader 8 us and writer 11 us noop floors |
| `workload_dispatch_bound` | point_query/select at 0 us floor-subtracted work |
| `workload_work_bound` | merge_rounds/executeBatch has 69 us work over 80 us median |
| `workload_tail_spread` | single-run p99/max tails are much wider than medians |
| `workload_rss_signal` | single_insert and point_query show visible RSS deltas |
| `workload_allocation_signal` | point_query decodes 50,000 rows / 300,000 cells |
| `workload_wal_signal` | single_insert and merge_rounds record WAL growth |
| `workload_loaded` | four workload summaries loaded |

## Decision

**In Review - measurement-system guardrail.**

The exp 143 follow-up is now consumed for Resqlite's profile workflow. Future
experimenters no longer have to manually inspect `workload-summary.json` to see
the profile's basic interpretation layer, and the wrapper will fail if
Tracelite regresses to a thin coverage-only explanation.

This is intentionally not a runtime optimization. It is accepted support work
because it protects the profile workflow used to decide future optimizations:
merge-round parameter work, point-query dispatch work, memory/allocation work,
and tail-noise claims are now surfaced directly in the generated insights.

## Future Notes

- Keep raw profile regions and workload JSON under `build/`; commit only compact
  aggregates unless graph data is feeding Pages.
- If a future profile workload changes shape enough that one required stable ID
  disappears, update the guard and this signal map in the same experiment rather
  than weakening it silently.
- `workload_dispatch_bound` remains a useful insight, but do not hard-require it
  unless the canonical profile workload makes its near-zero-work threshold
  stable across machines.
