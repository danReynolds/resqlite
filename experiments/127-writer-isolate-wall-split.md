# Experiment 127: Writer-isolate wall vs SQLite step wall split

**Date:** 2026-05-08
**Status:** In Review
**Direction:** `stream-rerun-dispatch`, `measurement-system`
**Benchmark Run:** None (measurement-only)

## Problem

[Exp 121](121-invalidation-traversal-audit.md) closed the invalidation
traversal slot in the writer-side burst-wall accounting. Its decision
note pointed at two remaining missing measurements before any further
dispatch implementation experiment is worth running, both also
flagged on the `stream-rerun-dispatch` and `measurement-system`
directions in [`signals.json`](signals.json) as
`blockedOnMeasurement`:

1. completion-side microtask scheduling cost
2. *writer-isolate dispatch wall vs SQLite step wall split* on overlap
   workloads

This experiment builds the second one.

The relevant question is: **of the writer-side burst wall on A11c
overlap and keyed-PK, how much does the writer isolate spend in
Dart-side dispatch (request decode, dirty-table read, response build,
reply send) versus inside the FFI write helpers themselves?** If the
writer is already spending almost all of its busy time in SQLite
proper, then writer-internal dispatch optimization is ceiling-bound and
future dispatch work should branch off the writer entirely. If a
material slice is Dart-side, that slice is a credible target for a
follow-up implementation experiment.

The existing `ProfileCounters` are populated from the main isolate,
documented as such, and have no cross-isolate visibility:

> Counters that require worker-isolate visibility (per-SQLite-type
> breakdowns) are NOT captured here yet. Adding them requires a
> round-trip request to each worker to snapshot its local state, which
> is a meaningful protocol addition — deferred to the experiment that
> actually needs it.
> — [`profile_counters.dart`](../lib/src/profile_counters.dart)

This is that experiment.

## Hypothesis

After exp 120 / exp 121, the writer-side burst wall on A11c overlap is
dominated by SQLite step time and writer idle time (waiting for the
next request from the main isolate), not by writer-side Dart dispatch.
The handler hot path on every measured workload should report
`sqlite_us` as the majority of `handler_us`, leaving a Dart-side slice
small enough to take writer-internal dispatch off the active candidate
list.

Accept this as a measurement experiment if:

- `parked_total` stays at zero on every workload, reproducing exp 120
  / exp 121 as a sanity check;
- the audit produces stable bands across repeated passes for A11c
  baseline / disjoint / overlap and keyed-PK;
- the result resolves the `signals.json` `blockedOnMeasurement` entry
  on `stream-rerun-dispatch` and `measurement-system` one way or the
  other, and updates `keyPriors` / `currentRead` accordingly.

## Approach

Added a profile-mode-only cross-isolate counter protocol and a
matching audit harness:

```text
lib/src/writer/write_worker.dart                    (writer state + protocol)
lib/src/writer/writer.dart                          (Writer.profileSnapshotCounters)
lib/src/database.dart                               (Database.profileSnapshotWriterCounters)
benchmark/profile/audit_workloads.dart              (resets + snapshots writer counters)
benchmark/profile/writer_isolate_audit.dart         (this experiment)
benchmark/profile/results/exp-127-writer-isolate-wall-aggregate.md
```

`_WriterState` now carries a long-running monotonic `Stopwatch` plus
three `int` accumulators: `handlerUs`, `sqliteUs`, `handlerCount`. The
writer dispatch loop wraps every non-snapshot `WriterRequest` with a
`ticker.elapsedMicroseconds` pair and accumulates into `handlerUs`;
inside `_handleExecute` and `_handleBatch`, a second pair wraps the
FFI write helper (`executeWrite` / `executeBatchWrite` /
`executeNestedBatchWrite`) and accumulates into `sqliteUs`. Both
accumulators are gated behind `if (kProfileMode)` so AOT release builds
tree-shake the instrumentation — only the `_WriterState` field
allocation is unconditional, and that is one extra `Stopwatch` per
writer isolate, paid once at spawn.

A new sealed-hierarchy member, `WriterCountersSnapshotRequest`, is
handled inline at the top of the dispatch loop **before** the timing
block — handling the snapshot itself does not contribute to
`handlerUs`. The matching `WriterCountersSnapshotResponse` carries
the three accumulators; when the request's `reset` flag is true, the
writer zeroes them after sending the response.

`Database.profileSnapshotWriterCounters({bool reset})` exposes the
round-trip through the public `Database` surface so audits never need
private writer access. In release builds the response carries zeros
(the writer never increments).

Audit workloads (`audit_workloads.dart`) reset writer counters inside
the same warm-up window where they reset `ProfileCounters`, then read
them after the workload-scoped stopwatch stops. The wall convention is
unchanged from exp 121: stopwatch stops on the last write; emission
drains run after the stopwatch.

## Results

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`).

Command:

```text
dart run -DRESQLITE_PROFILE=true \
  benchmark/profile/writer_isolate_audit.dart --markdown
```

Five profile passes; values bracket the per-run band.

| workload                | wall_ms     | handler_us / wall | sqlite_us / wall | dart_us / wall | sqlite_us / handler | µs per handler call | µs per sqlite call |
|-------------------------|------------:|-------------------:|------------------:|---------------:|--------------------:|--------------------:|-------------------:|
| A11c baseline           | 36 – 38     | 51 – 56%          | 34 – 39%         | 16 – 18%      | 66 – 71%           | 34 – 42             | 22 – 30           |
| A11c disjoint           | 38 – 44     | 35 – 39%          | 21 – 24%         | 14 – 16%      | 60 – 64%           | 28 – 33             | 17 – 20           |
| A11c overlap            | 86 – 96     | 24 – 26%          | 13 – 15%         | 11 – 12%      | 52 – 59%           | 43 – 50             | 22 – 29           |
| keyed PK subscriptions  | 19 – 21     | 34 – 41%          | 23 – 28%         | 11 – 12%      | 68 – 70%           | 32 – 43             | 22 – 30           |

`parked_total` and `max_parked` stayed at zero on every workload across
every pass — the exp 120 / exp 121 sanity check holds.

A latest pass committed verbatim to
[`benchmark/profile/results/exp-127-writer-isolate-wall-aggregate.md`](../benchmark/profile/results/exp-127-writer-isolate-wall-aggregate.md).

### Interpretation

The numbers split writer-side burst wall into three buckets:

1. **`sqlite_us / wall`** — wall the writer spent inside the FFI write
   helpers. Floor on what writer-side dispatch optimization could
   leave: this is *not* removable.
2. **`dart_us / wall`** — wall the writer spent in its Dart-side
   prologue/epilogue (request decode, dirty-table read, response
   build, reply send). The writer-internal dispatch optimization
   ceiling.
3. **`(wall - handler) / wall`** — wall the writer was idle, waiting
   for the main isolate to send the next request. Lives outside the
   writer entirely.

On A11c overlap the writer-internal Dart bucket is **11 – 12% of
wall**, ~14 – 21 µs per call. Eliminating it entirely would shave
roughly **10 – 11 ms off a 90 ms overlap burst** — at the per-benchmark
decision threshold edge, the same shape as the exp 121 invalidation
traversal ceiling.

The biggest single bucket on A11c overlap is the *idle* slice: the
writer is busy only 24 – 26% of the burst wall. The remaining ~75% is
not inside the writer at all — it's the time between
`WriteResponse` arrival on the main isolate and the next
`ExecuteRequest` reaching the writer. That maps directly to the
other still-blocked measurement on the dispatch direction:
completion-side microtask scheduling cost.

The shape repeats on keyed-PK (writer busy 34 – 41%, Dart 11 – 12%)
and is even tighter on the no-stream A11c baseline (writer busy 51 –
56%, Dart 16 – 18%) where the main isolate has no stream emission
work to do between writes.

`sqlite_us / handler_us` is **52 – 71%** across workloads. The writer
spends a clear majority of its busy time in SQLite proper but the
Dart-side fraction is not negligible — it just isn't the largest
remaining slice on the workloads exp 120 / exp 121 flagged as the next
dispatch target.

### Per-call cost shape

| workload      | µs per handler call | µs per sqlite call | µs per Dart slice |
|---------------|--------------------:|-------------------:|------------------:|
| A11c baseline | 34 – 42             | 22 – 30           | ~12 – 14          |
| A11c disjoint | 28 – 33             | 17 – 20           | ~10 – 13          |
| A11c overlap  | 43 – 50             | 22 – 29           | ~14 – 21          |
| keyed PK      | 32 – 43             | 22 – 30           | ~10 – 13          |

A11c overlap's per-call wall is materially higher than disjoint
despite an identical SQL shape — the difference shows up in both
buckets (sqlite, dart). The most likely driver is the dirty-table /
column read after every write being heavier when more streams have
overlapping column projections, but exp 127 does not split the dart
bucket finer than that. A finer-grained breakdown (`dirty_us`,
`response_us`) is left to a follow-up audit if the bucket ever moves
above the ceiling implied here.

## Decision

**Accept for review — measurement.**

The audit answers the open `signals.json` question on the
`stream-rerun-dispatch` and `measurement-system` directions:

> writer-isolate wall vs SQLite wall split for overlap workloads

The writer-side **Dart bucket is small** (11 – 18% of wall, ~10 – 21 µs
per call across workloads). Removing the entire path would save ~10 ms
on a 90 ms A11c overlap burst — the per-benchmark decision threshold
edge, roughly the same magnitude as the exp 121 invalidation traversal
ceiling, and the same conclusion: a writer-internal dispatch experiment
that fully eliminated this bucket would only just cross the release
suite's decision threshold under best-case shape assumptions.

The **biggest remaining bucket is wall the writer is idle** waiting for
the next request from the main isolate (~75% of A11c overlap wall).
That bucket lives on the main isolate, not in the writer, and maps
directly to the other still-blocked measurement: completion-side
microtask scheduling cost. Future dispatch implementation experiments
should branch off the writer-internal path and onto that signal once
its counter exists.

`signals.json` therefore:

- removes `writer-isolate wall vs SQLite wall split for overlap
  workloads` from the `stream-rerun-dispatch` direction's
  `blockedOnMeasurement` list,
- removes the matching `writer dispatch wall counter (dart wall - SQLite step wall)` from the `measurement-system` direction's
  `openCandidates`,
- adds 127 to the `keyPriors` of `stream-rerun-dispatch` and
  `measurement-system` so future runners read this audit before
  proposing a writer-internal dispatch change.

## Future Notes

- The remaining blocked measurement on the dispatch direction is
  **completion-side microtask scheduling cost**. A natural follow-up
  experiment builds that counter and re-audits A11c overlap. If
  completion-side wall is large, dispatch experiments should target it
  next; if small, dispatch is no longer the active direction at all.
- The writer-side Dart bucket *is* a credible (if bounded) target for a
  later implementation experiment. The most plausible removable
  sub-slices are (in rough order of expected size on A11c overlap):
  - dirty-table dependency read (`getDirtyTableDependencies`),
  - response object construction and `replyPort.send`,
  - per-message `Timeline.startSync` / `finishSync` (already gated on
    `kProfileMode`, so this is only a profile-mode cost — but worth
    confirming under `dart --observe` before rejecting).
  None of these is worth a bounded pass without a workload that
  shows the bucket above its current ~10 – 21 µs per call envelope.
- The writer counter protocol added here is reusable. Adding a
  finer-grained breakdown — `dirty_us`, `response_us`, per-request-type
  `handler_us` — is a small extension to `_WriterState` and the
  snapshot response, not a new protocol. Future audits that need that
  breakdown should extend in place rather than introducing a parallel
  channel.
- The writer-isolate `Stopwatch` field is allocated unconditionally
  (per writer isolate, once at spawn). If a future review wants the
  field gated behind `kProfileMode`, the harness contract is that
  `profileSnapshotCounters` returns zeros in release; the field can
  be lifted into a `kProfileMode ? ... : null` lazy without changing
  callers.
