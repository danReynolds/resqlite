# Experiment 124: Stream completion scheduling cost counter

**Date:** 2026-05-05
**Status:** In Review
**Direction:** `stream-rerun-dispatch`, `measurement-system`

## Problem

[Exp 121](121-invalidation-traversal-audit.md) ruled invalidation
traversal out as a wall-time target on writer-side burst path: 10–15%
of A11c overlap wall, ~14% of keyed-PK wall, with column-set
intersection ~3% — already O(1) bitset. Its future-notes section listed
the two remaining candidate measurement signals from
[exp 120](120-flush-admit-bound.md):

- completion-side microtask scheduling cost counter
- writer-isolate wall vs SQLite step wall split

Both sat in the `signals.json` `blockedOnMeasurement` list for
`stream-rerun-dispatch` and the `openCandidates` list for
`measurement-system`. Without one of them, every future dispatch-area
implementation experiment would face the exp 099 / exp 110 evaluation
gap: a structurally plausible change measured against a workload whose
actual completion-side cost is unobserved.

[Exp 123](123-writer-dispatch-step-split.md) (in flight on PR #90)
fills the writer-isolate vs native split. This experiment fills the
matching main-isolate completion-side counter on the same A11c / keyed-
PK shapes the previous audits established as canonical, so future
dispatch work has both denominators directly observable.

## Hypothesis

After exp 120 / exp 121, A11c overlap writer-side burst wall is
dominated by writer SQLite step time and the synchronous portion of
`StreamEngine._requery` that runs *after* the reader-pool `await`
returns — the result-change check, `entry.emit(rows)` to subscribers,
and the trailing `_flushQueue` kickoff. That work is pinned to the
main isolate event loop (every requery completes there before the
next dispatch fires) and currently has no counter, so we can't tell
whether it is a meaningful share of overlap wall or noise.

Accept this as a measurement experiment if:

- `parked_total` stays at zero on every workload, reproducing exp 120
  as a sanity check;
- the audit produces a stable `completion_us / wall_us` band across
  repeated passes for A11c (baseline / disjoint / overlap) and
  keyed-PK subscriptions;
- the result resolves the `signals.json` open candidate one way or the
  other, and updates `blockedOnMeasurement` accordingly.

## Approach

Two new profile-mode counters in `lib/src/profile_counters.dart`:

```text
streamCompletionUs      // cumulative microseconds in the post-await
                        // synchronous body of _requery / _createStream
streamCompletionCount   // one increment per resumed body
```

Increments are gated behind `kProfileMode` (compile-time const) so AOT
release builds tree-shake them away — same pattern as
[exp 115](115-dispatcher-park-counters.md) /
[exp 121](121-invalidation-traversal-audit.md) counters.

`lib/src/stream_engine.dart` — both `_requery` and the inner
`Future.sync` body inside `_createStream` allocate a nullable
`Stopwatch?` outside the `try`, start it when the relevant `await`
returns, and stop + accumulate inside the matching `finally`. The
timed segment includes:

- the `entry.dirty` short-circuit and result-change check;
- `entry.emit(rows)` (or `emit(initialRows)` in `_createStream`);
- in `_requery`, the trailing `_flushQueue()` that admits the next
  dequeue.

Excluding it from the catch block matches exp 123's "only count when
the work actually ran" convention: an `await` that throws never
reached the post-await sync work and shouldn't deflate the
`us / count` average. The error path itself is rare and visible via
the existing exception handling.

The audit harness reuses `audit_workloads.dart` (the shared module
[exp 121](121-invalidation-traversal-audit.md) extracted), so this run
is structurally comparable to exp 119 / exp 121:

```text
benchmark/profile/stream_completion_audit.dart
```

The wall-measurement convention is inherited unchanged: stopwatch
stops on the last write, emission drains run after the stopwatch.

Output is committed to
[`benchmark/profile/results/exp-124-stream-completion-aggregate.md`](../benchmark/profile/results/exp-124-stream-completion-aggregate.md).

## Results

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`).

Command:

```text
dart run -DRESQLITE_PROFILE=true \
  benchmark/profile/stream_completion_audit.dart --markdown
```

Four profile passes; values bracket the per-run band.

| workload                | wall_ms     | completion_us  | completion_count | parked_total | completion / wall | invalidate / wall |
|-------------------------|------------:|---------------:|-----------------:|-------------:|------------------:|------------------:|
| A11c baseline           | 33 – 36     |              0 |                0 |            0 | 0.00%             | 0.00%             |
| A11c disjoint           | 38 – 41     |              0 |                0 |            0 | 0.00%             | 21 – 24%          |
| A11c overlap            | 86 – 109    |   25k – 31k    |  3,588 – 3,885   |            0 | 25 – 34%          | 13 – 17%          |
| keyed PK subscriptions  | 21 – 28     |  4.3k – 7.9k   |    999 – 1,118   |            0 | 21 – 32%          | 13 – 16%          |

Per-completion and per-write derived costs:

| workload                | µs per completion | completions per write | µs per write (completion) |
|-------------------------|------------------:|----------------------:|---------------------------:|
| A11c baseline           |               0.0 |                   0.0 |                        0.0 |
| A11c disjoint           |               0.0 |                   0.0 |                        0.0 |
| A11c overlap            |        6.8 – 8.0  |          7.2 – 7.8    |                  50 – 62  |
| keyed PK subscriptions  |        4.1 – 7.1  |          5.0 – 5.6    |                  22 – 40  |

Three things confirmed:

1. **Sanity check passes.** `parked_total` and `max_parked` stay at
   zero across all workloads, reproducing exp 120's acceptance signal.
2. **Disjoint elision still holds.** A11c disjoint reports zero
   completions across all four passes — exp 106's column-level
   dependency tracking elides every re-query upstream, so `_requery`
   never runs and the new counter correctly stays at zero. Only
   invalidation traversal is exercised on disjoint, matching exp 121.
3. **Completion-side is a real wall-time target on overlap and
   keyed-PK.** A11c overlap spends ~25–34% of writer-side burst wall
   in the post-await body of `_requery` — roughly twice the
   invalidation-traversal share exp 121 measured (13–17%). Keyed-PK
   shows the same pattern at smaller absolute size: ~21–32%
   completion vs ~13–16% invalidation.

Per-completion absolute cost (~7 µs A11c, ~4–7 µs keyed-PK) is
dominated by `entry.emit(rows)` to a single subscriber plus the
trailing `_flushQueue` kickoff; the result-change short-circuit
itself is C-side and accounts for a few hundred ns. Per-write
completion cost on overlap (~50–62 µs / write across ~7.5
completions / write) puts completion ahead of invalidation on every
overlap burst.

## Decision

**Accept for review — measurement.**

The audit answers the open `signals.json` question for the
`stream-rerun-dispatch` direction:

> profile completion-side microtask scheduling cost on A11c overlap

Completion-side scheduling is the **larger** of the two known wall-time
fractions on writer-side burst path on overlap-shaped workloads:

- A11c overlap: ~25–34% completion vs ~13–17% invalidation
- keyed-PK:    ~21–32% completion vs ~13–16% invalidation
- A11c disjoint: 0% completion (exp 106 elision), ~21–24% invalidation
- A11c baseline: 0/0 (no streams)

That makes completion-side the next plausible dispatch experiment
target on overlap-shaped streams. The natural follow-up directions
have non-trivial implementation surface but are now evaluable:

- **batched emit.** `_flushQueue` currently dequeues
  `_pool.availableWorkerCount` entries per call; each completion
  calls `emit(rows)` on its subscribers individually. Coalescing
  emits across one dequeue cycle could amortize subscriber-side
  microtask scheduling.
- **completion fast-path on unchanged result.** `selectIfChanged`
  returns `null` rows when the hash matched, but the post-await body
  still runs the dirty check and falls through to `_flushQueue`. A
  short-circuit before stopwatch start is benchmark-invisible (already
  counted), but a short-circuit before the await would land in
  `ReaderPool` rather than `StreamEngine` — separate experiment.
- **subscriber-side delivery batching.** Across one dependency-changes
  cycle, the same write triggers up to N completions (one per
  matching stream); each emits to its subscribers individually. A
  per-burst flush could reduce per-emit overhead.

`signals.json` removes the matching open candidate and
`blockedOnMeasurement` entry, and steers the next dispatch experiment
toward implementation work that targets completion-side wall.

## Future Notes

- **Re-audit if the per-completion shape changes.** The current ~7 µs
  number is an average across single-subscriber streams. Multi-
  subscriber streams or larger result sets would push it up; the
  counter's per-completion average gives a direct way to detect that
  before claiming an implementation win.
- **The four-pass band is wide on keyed-PK** (21–32%, ~4–7 µs per
  completion) because the workload runs only 200 writes and ~1k
  completions — small denominators amplify per-pass jitter. A11c
  overlap with 500 writes and ~3.6k completions is the more reliable
  reference until/unless a larger keyed-PK shape is added to the
  audit.
- **Combined coverage with exp 123.** Exp 123 reports the
  writer-isolate vs native split; this experiment reports the
  main-isolate completion split. Adding the two fractions plus exp 121
  invalidation gives an end-to-end accounting of where overlap-burst
  wall sits — useful as a single dashboard once both PRs land.
- **Adding a counter to `audit_workloads.dart` is enough** to extend
  this audit to other shapes — the shared module captures the full
  `ProfileCounters.snapshot()` per scenario, and harnesses pick the
  fields they care about.
