# Experiment 121: Invalidation traversal cost audit

**Date:** 2026-05-03
**Status:** In Review
**Direction:** `stream-rerun-dispatch`, `measurement-system`

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
`onDependencyChanges` should be a small (sub-10%) slice of overlap
wall, and the column-intersection sub-cost an even smaller slice.

Accept this as a measurement experiment if:

- `parked_total` stays at zero on every workload, reproducing exp 120
  as a sanity check;
- the audit produces a stable `invalidate_us / wall_us` figure across
  repeated passes for A11c disjoint, A11c overlap, and keyed-PK
  subscriptions;
- the result removes one open candidate from `signals.json`'s
  `stream-rerun-dispatch` direction one way or the other.

## Approach

Added a resqlite-only profile harness:

```text
benchmark/profile/invalidation_traversal_audit.dart
```

The harness reuses exp 119's stream workload shapes (A11c baseline /
disjoint / overlap, plus 50-stream keyed-PK subscriptions) so the
two reports are directly comparable, and reports `invalidate_us`,
`intersection_us`, `invalidate_count`, `intersection_entries`,
`parked_total`, and `max_parked` alongside total burst wall time.

Derived fields computed per workload:

- `invalidate_us / wall_us` — invalidation traversal as a fraction of
  total burst wall time;
- `intersection_us / wall_us` — column-set intersection as a fraction
  of total burst wall time;
- average µs per write inside `onDependencyChanges`;
- average ns per (stream × write) intersection probe.

The harness is committed alongside its aggregate markdown output under
`benchmark/profile/results/exp-121-invalidation-traversal-aggregate.md`.

## Results

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`).

Command:

```text
dart run -DRESQLITE_PROFILE=true \
  benchmark/profile/invalidation_traversal_audit.dart --markdown
```

Two profile passes; values bracket the per-run band. Full per-run
table is in
[`benchmark/profile/results/exp-121-invalidation-traversal-aggregate.md`](../benchmark/profile/results/exp-121-invalidation-traversal-aggregate.md).

| workload                | wall_ms     | invalidate_us | intersection_us | parked_total | invalidate / wall | intersection / wall |
|-------------------------|------------:|--------------:|----------------:|-------------:|------------------:|--------------------:|
| A11c baseline           | 92 – 93     |             0 |               0 |            0 | 0.00%             | 0.00%               |
| A11c disjoint           | 92 – 97     |  8.9k – 9.9k  |   3.2k – 3.7k   |            0 | 9.7% – 10.2%      | 3.5% – 3.9%         |
| A11c overlap            | 139 – 144   |  9.7k – 10.5k |   2.2k – 2.7k   |            0 | 7.0% – 7.3%       | 1.6% – 1.9%         |
| keyed PK subscriptions  | 223 – 225   |  2.0k – 2.3k  |   0.4k – 0.5k   |            0 | 0.9% – 1.0%       | 0.2% – 0.2%         |

Per-write and per-entry costs:

| workload                | µs per write inside `onDependencyChanges` | ns per intersection probe |
|-------------------------|------------------------------------------:|--------------------------:|
| A11c baseline           |                                       0.0 |                         0 |
| A11c disjoint           |                              17.8 – 19.8 |                  130 – 150 |
| A11c overlap            |                              19.4 – 21.0 |                   89 – 106 |
| keyed PK subscriptions  |                              10.1 – 11.3 |                    44 – 51 |

`parked_total` stays at zero on every workload, reproducing exp 120's
acceptance signal as a sanity check.

## Decision

**Accept for review — measurement.**

The audit answers the open `signals.json` question for the
`stream-rerun-dispatch` direction:

> audit invalidation traversal cost (`invalidateUs` /
> `intersectionUs`) as a fraction of overlap wall

Invalidation traversal is **not** a meaningful wall-time target on
current main. On A11c overlap — the workload exp 119 / 120 flagged as
the source of remaining stream-fanout pressure — the synchronous body
of `onDependencyChanges` is ≈ 7% of total burst wall, and the
column-intersection sub-cost it would optimize is only ≈ 1.6 – 1.9%.
On keyed-PK subscriptions the fraction collapses to ~1% / ~0.2%
because the stream's column set short-circuits the intersection probe
quickly.

A11c disjoint shows the largest *fraction* (~10%) only because column
elision suppresses the dispatch / reader-pool wall, shrinking the
denominator. The absolute `invalidate_us` per write is essentially
the same as overlap (≈ 18 – 21 µs across both shapes), confirming the
underlying traversal cost is workload-shape-stable; what changes is
how much *other* wall is layered on top of it.

The per-entry intersection cost (~50 – 150 ns) sets a hard ceiling on
any "smarter dependency tracking" experiment in this area: at 25,000
intersection probes per overlap burst, the entire probe budget is
under 3 ms, less than a single SQLite step on a wide INSERT.

## Future Notes

This run removes "audit invalidation traversal cost" from
`signals.json`'s `stream-rerun-dispatch` `blockedOnMeasurement` list
and downgrades the related `openCandidates` entry: invalidation
traversal is structurally not where overlap wall lives.

The two remaining candidate measurement signals are still blocked on
new infrastructure:

- completion-side microtask scheduling cost — needs a counter that
  attributes main-isolate scheduler hops to a workload phase;
- writer-isolate wall vs SQLite step wall split — needs a profile-mode
  split inside `WriteWorker`.

Either is a viable next measurement-only experiment. Whichever one
shows nonzero headroom (analogous to exp 119's parked-dispatcher
finding) becomes the entry point for the next dispatch implementation
candidate. Until one does, there is no observable counter signal on
top of `dispatcherParkedTotal == 0` and `dispatcherWakeRetryTotal == 0`
to gate dispatch-area work, and a runner picking up this direction
should expect to build measurement before changing code.
