# Experiment 121: Invalidation traversal cost audit

**Date:** 2026-05-03
**Status:** Accepted
**Direction:** `stream-rerun-dispatch`, `measurement-system`
**Benchmark Run:** None

## Problem

[Exp 120](120-flush-admit-bound.md) closed the over-dispatch path inside
`StreamEngine._flushQueue` and dropped `dispatcherParkedTotal` and
`dispatcherMaxParkedConcurrent` to zero on every measured stream
workload. Its future-notes section listed three remaining wall-time
sources future dispatch work could plausibly target:

- completion-side microtask churn
- writer-side dispatch (writer wall vs SQLite step wall)
- invalidation traversal (`invalidateUs` / `intersectionUs`, already
  counted in profile mode but never audited as a fraction of overlap
  wall)

Of those, only invalidation traversal already has the counters in place
(`ProfileCounters.invalidateUs` and `ProfileCounters.intersectionUs`,
incremented inside `StreamEngine.onDependencyChanges`). The other two
are blocked on new measurement infrastructure. The natural next
measurement experiment is therefore: *what fraction of A11c overlap
wall is the synchronous body of `onDependencyChanges`?* If small,
future dispatch work should branch off invalidation and onto
completion-side or writer-side wall. If large, the candidate idea is
back on the table.

## Hypothesis

After exp 120, A11c overlap wall is dominated by writer SQLite step
time, completion-side scheduling, and reader-pool stream re-query work
— not by writer-side invalidation traversal. The synchronous body of
`onDependencyChanges` should be a small (sub-15%) slice of writer-side
burst wall, and the column-intersection sub-cost an even smaller slice.

Accept this as a measurement experiment if:

- `parked_total` stays at zero on every workload, reproducing exp 120
  as a sanity check;
- the audit produces stable `invalidate_us / wall_us` and
  `intersection_us / wall_us` bands across repeated passes for A11c
  disjoint, A11c overlap, and keyed-PK subscriptions;
- the result resolves the `signals.json` open candidate one way or the
  other, and updates `blockedOnMeasurement` accordingly.

## Approach

Added two profile-mode files:

```text
benchmark/profile/audit_workloads.dart            (shared)
benchmark/profile/invalidation_traversal_audit.dart  (this experiment)
```

`audit_workloads.dart` extracts the A11c (baseline / disjoint / overlap)
and keyed-PK scenario runners that exp 119's
`dispatch_pressure_audit.dart` previously inlined, so future workload
tweaks land in one place and the two reports stay directly comparable
as a structural property. Exp 119's harness is refactored to call into
the shared module — its committable aggregate is unchanged in shape.

Wall-clock convention used in both audits, established here:

- the stopwatch starts after subscriptions are warm and counters are
  reset;
- the stopwatch **stops on the last write** — not after a fixed drain
  sleep or quiet-window emission wait;
- emission counts are read after the stopwatch stops, so trailing
  stream emissions are still observed without padding the wall
  denominator with idle waiting.

The previous A11c runner included a fixed 50 ms drain sleep inside the
stopwatch range; the keyed-PK runner included up to 60 s of quiet-window
waiting. Both biased `invalidate_us / wall_us` downward by
non-deterministic idle time. Stopping on the last write makes
`wall_us` writer-side burst wall, which is the proper denominator for
"fraction of writer-side cost spent in invalidation traversal."

The harness reports `invalidate_us`, `intersection_us`,
`invalidate_count`, `intersection_entries`, `parked_total`, and
`max_parked` alongside `wall_ms`, plus derived per-write and
per-intersection-entry costs. Output is committed to
[`benchmark/profile/results/exp-121-invalidation-traversal-aggregate.md`](../benchmark/profile/results/exp-121-invalidation-traversal-aggregate.md).

## Results

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`).

Command:

```text
dart run -DRESQLITE_PROFILE=true \
  benchmark/profile/invalidation_traversal_audit.dart --markdown
```

Three profile passes; values bracket the per-run band.

| workload                | wall_ms     | invalidate_us | intersection_us | parked_total | invalidate / wall | intersection / wall |
|-------------------------|------------:|--------------:|----------------:|-------------:|------------------:|--------------------:|
| A11c baseline           | 33 – 35     |             0 |               0 |            0 | 0.00%             | 0.00%               |
| A11c disjoint           | 37 – 39     |  8.3k – 9.0k  |   3.2k – 3.4k   |            0 | 22.3% – 23.3%     | 8.6% – 9.0%         |
| A11c overlap            | 88 – 104    | 10.5k – 12.4k |   2.8k – 5.0k   |            0 | 10.1% – 15.3%     | 2.5% – 5.7%         |
| keyed PK subscriptions  | 19 – 20     |  2.7k – 2.8k  |   0.8k – 0.8k   |            0 | 13.5% – 13.9%     | 4.1% – 4.3%         |

Per-write and per-entry costs:

| workload                | µs per write inside `onDependencyChanges` | ns per intersection probe |
|-------------------------|------------------------------------------:|--------------------------:|
| A11c baseline           |                                       0.0 |                         0 |
| A11c disjoint           |                              16.5 – 17.9 |                  128 – 139 |
| A11c overlap            |                              21.2 – 27.1 |                    89 – 199 |
| keyed PK subscriptions  |                              13.6 – 13.9 |                    80 – 87 |

`parked_total` stays at zero on every workload, reproducing exp 120's
acceptance signal as a sanity check.

A11c disjoint shows the largest *fraction* (~22 – 23%) only because
column elision suppresses the dispatch / reader-pool denominator,
shrinking the wall — the absolute `invalidate_us` per write (16 – 18 µs)
is essentially the same as overlap. The observed per-write traversal
cost is workload-shape-stable; what changes between rows is how much
*other* wall is layered on top of it.

The per-entry intersection cost (~80 – 200 ns) sets a hard lower bound
on any "smarter dependency tracking" experiment: at 25,000 intersection
probes per overlap burst, the entire probe budget is 2 – 5 ms — well
under a tenth of overlap wall.

## Decision

**Accept for review — measurement.**

The audit answers the open `signals.json` question for the
`stream-rerun-dispatch` direction:

> audit invalidation traversal cost (`invalidateUs` /
> `intersectionUs`) as a fraction of overlap wall

Invalidation traversal is at the **edge** of the wall-time noise floor,
not a clear active target. On A11c overlap, the synchronous body of
`onDependencyChanges` is 10 – 15% of writer-side burst wall, and the
column-intersection sub-cost it would optimize is 2.5 – 5.7%. On
keyed-PK subscriptions the fraction is 13.5 – 13.9%, with intersection
~4%. On A11c disjoint the fraction is 22 – 23% only because reader-pool
work is fully elided upstream by column-level dependencies (exp 106).

Per-write absolute cost (~16 – 27 µs A11c, ~14 µs keyed-PK) means an
experiment that *eliminated all of `onDependencyChanges`* would shave
roughly 8 – 14 ms off the 88 – 104 ms overlap burst — measurable in the
focused harness, but at the boundary of the ±10% per-benchmark decision
threshold the release suite uses, and only if the implementation surface
were small.

The structural ceiling: column-set intersection is already an O(1)
bitset operation at 80 – 200 ns per probe; the rest of the traversal
is `_tableIndex` map lookup, dirtyEntries `Set.add`, and the
synchronous portion of `_flushQueue`. None of those are obvious
optimization targets without a redesign of the dependency model.

`signals.json` therefore removes the matching open candidate and
`blockedOnMeasurement` entry, and steers the next dispatch experiment
toward completion-side microtask scheduling cost or writer-isolate
wall vs SQLite step wall — both still blocked on new measurement
infrastructure.

## Future Notes

- Reopen if a new workload exposes invalidation as a larger share of
  wall — for instance, very many streams with overlapping but
  non-trivially-shaped dependency sets, where `_tableIndex` walking
  becomes hot.
- The two remaining candidate measurement signals are still blocked on
  new infrastructure: completion-side microtask scheduling cost
  counter, and writer-isolate wall vs SQLite step wall split. Either
  is a viable next measurement-only experiment.
- The shared `audit_workloads.dart` module is now the right place for
  any future audit that wants the same A11c / keyed-PK shapes. Adding
  a counter to the shared `AuditScenarioResult` is enough — callers
  only format their own table from the snapshot.
