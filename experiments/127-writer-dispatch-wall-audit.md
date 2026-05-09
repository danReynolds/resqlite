# Experiment 127: Writer-isolate dispatch wall audit

**Date:** 2026-05-09
**Status:** In Review
**Direction:** `stream-rerun-dispatch`, `measurement-system`
**Benchmark Run:** None

## Problem

[Exp 121](121-invalidation-traversal-audit.md) closed the
invalidation-traversal question by showing
`StreamEngine.onDependencyChanges` is 10–15 % of A11c overlap burst
wall — at the *edge* of the wall-time noise floor, not a clear active
target. Its decision section left two named blocking measurements in
the [`stream-rerun-dispatch`](signals.json) direction:

- completion-side microtask scheduling cost
- **writer-isolate wall vs SQLite step wall split**

Both were `blockedOnMeasurement` in `signals.json`. Neither has a
counter on `main` yet, so any implementation experiment in the
direction is currently speculative.

This run ships the second one. Without a writer-side wall vs SQLite
wall breakdown, we cannot tell whether the remaining wall on A11c
overlap is dominated by the SQLite step itself, the writer isolate's
Dart-side dispatch path (param encoding, dirty-tables gather, IPC
framing, response construction), or main-isolate completion work. The
audit answers that question and either re-opens writer-side dispatch
as an active target or rules it out so the next runner can branch
toward completion-side scheduling.

## Hypothesis

After exp 120, exp 122, and exp 121, A11c overlap wall is dominated by
**main-isolate completion work** — stream re-query scheduling and the
mutex / IPC layer between `Database.execute` and the writer isolate —
not by the writer isolate's `_handle*` body. The synchronous body of
`_handleExecute` / `_handleBatch` should be a minority slice of the
overall burst wall on A11c overlap, with the SQLite step itself and
Dart-side dispatch each in the ~10 % band.

Accept this as a measurement experiment if:

- `parked_total` stays at zero on every workload, reproducing exp 120
  / exp 122 as a sanity check;
- the audit produces stable `writer_handle_us / wall_us` and
  `(writer_handle_us - writer_step_us) / wall_us` bands across
  repeated passes for A11c baseline, A11c disjoint, A11c overlap, and
  keyed-PK subscriptions;
- the result either resolves the `writer-isolate wall vs SQLite step
  wall split` `blockedOnMeasurement` entry by removing it, or
  identifies a workload that elevates writer-side dispatch into a
  named optimization candidate.

## Approach

Added one writer-isolate-local counter class and the round-trip
plumbing required to read it from the audit harness:

```text
lib/src/profile_counters.dart        WriterProfileCounters
lib/src/native/resqlite_bindings.dart writerStepUs increment
lib/src/writer/write_worker.dart     _handleExecute / _handleBatch wrap
                                     FetchWriterProfileRequest
                                     WriterProfileResponse
lib/src/writer/writer.dart           Writer.fetchProfileSnapshot()
lib/src/database.dart                Database.writerProfileCounters()
```

The new counters are:

- `writerHandleUs` — cumulative wall in the writer isolate's
  `_handleExecute` and `_handleBatch` body (param encoding, FFI call,
  `getDirtyTableDependencies`, response build).
- `writerStepUs` — cumulative wall specifically inside
  `resqlite_execute` / `resqlite_run_batch` / `resqlite_run_batch_nested`.
  The C side is not instrumented, so this is the closest approximation
  to "real SQLite step time" available without modifying the
  amalgamation.
- `writerHandleCount` — handler call count, used as the per-write
  denominator.

All three live in the writer isolate (top-level isolate state is not
shared across isolates), so the audit harness pulls a snapshot via
`Database.writerProfileCounters()` — a thin wrapper that round-trips
the new `FetchWriterProfileRequest` to the writer's reply port and
returns the snapshot map. Every increment is gated on `kProfileMode`,
so release builds keep the existing zero-cost contract.

Also extended `benchmark/profile/audit_workloads.dart` to capture the
writer snapshot before and after each scenario's burst, computing the
diff into a new `AuditScenarioResult.writerCounters` map. Existing
audits (exp 119, exp 121) ignore the field, so the only added cost is
one extra writer round-trip per scenario.

The new audit harness lives at
`benchmark/profile/writer_dispatch_audit.dart` and reuses the shared
A11c and keyed-PK runners from `audit_workloads.dart`. The
wall-measurement convention exp 121 established — stopwatch stops on
the last write, emission drains run after — is inherited unchanged.

## Results

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`).

Command:

```text
dart run -DRESQLITE_PROFILE=true \
  benchmark/profile/writer_dispatch_audit.dart --markdown
```

Four profile passes; values bracket the per-run band.

| workload                | wall_ms     | writer_handle_us | writer_step_us | handle / wall | step / wall | dispatch / wall |
|-------------------------|------------:|-----------------:|---------------:|--------------:|------------:|----------------:|
| A11c baseline           | 37 – 43     | 17.7k – 22.2k    |  8.7k – 12.5k  | 47% – 52%     | 23% – 29%   | 23% – 24%       |
| A11c disjoint           | 46 – 49     | 16.1k – 18.2k    |  7.2k –  9.3k  | 34% – 37%     | 16% – 19%   | 18% – 19%       |
| A11c overlap            | 99 – 112    | 24.1k – 25.2k    | 10.5k – 11.7k  | 22% – 24%     |  9% – 11%   | 12% – 14%       |
| keyed PK subscriptions  | 26 – 29     |  8.9k – 10.6k    |  5.4k –  6.6k  | 34% – 36%     | 21% – 23%   | 12% – 14%       |

Per-write costs:

| workload                | µs per write (handle) | µs per write (step) | µs per write (dispatch) |
|-------------------------|----------------------:|--------------------:|------------------------:|
| A11c baseline           |             35 – 44   |          17 – 25    |                18 – 20  |
| A11c disjoint           |             32 – 36   |          14 – 19    |                17 – 18  |
| A11c overlap            |             48 – 50   |          21 – 23    |                       27|
| keyed PK subscriptions  |             44 – 53   |          27 – 33    |                17 – 20  |

`parked_total` stays at zero on every workload across every run,
reproducing exp 120 / exp 122's acceptance signal as a sanity check.

The dominant signal: on A11c overlap (the workload exp 119 / 120 / 121
focused on), writer-isolate work is only 22–24 % of total burst wall.
The remaining ~76 % is main-isolate work — mutex acquisition, IPC
framing between `Database.execute` and the writer's reply port,
`StreamEngine.onDependencyChanges` (10–15 % per exp 121), and
completion-side stream re-query scheduling.

Within the writer-isolate slice on overlap:

- SQLite step (the FFI call itself): 9–11 % of wall (~10 ms total per
  500-write burst).
- Dart-side dispatch overhead (handle minus step): 12–14 % of wall
  (~14 ms per burst, ~27 µs per write).

Per-write dispatch cost is workload-shape-stable at ~17–27 µs and
covers `cachedSqlUtf8` + `allocateParams` + the result-buffer calloc
pair + `getDirtyTableDependencies` (two FFI calls per write to drain
the C-side dirty sets) + response construction + IPC framing.

A11c baseline — the no-streams reference — has the largest
*proportional* writer-handle share (47–52 %), simply because the
denominator drops once main-isolate stream work is gone. Absolute
per-write costs are flat across baseline / disjoint / overlap; what
changes is how much *other* wall is layered on top.

## Decision

**Accept for review — measurement.**

The audit answers the open `signals.json` question for the
`stream-rerun-dispatch` direction:

> writer-isolate wall vs SQLite wall split for overlap workloads

Writer-side Dart dispatch is at the **edge** of the wall-time noise
floor on A11c overlap, not a dominant target. At ~14 ms per 100 ms
burst, an experiment that fully eliminated `_handleExecute` / `_handleBatch`
Dart overhead — including `getDirtyTableDependencies` — would shave
roughly 12–14 % off overlap wall, measurable in the focused harness
but at the boundary of the per-benchmark decision threshold the
release suite uses, and only if the implementation surface stayed
small.

`signals.json` therefore removes the matching `blockedOnMeasurement`
entry and updates `notesForExperimenters` to reflect that the active
remaining target is **main-isolate completion-side scheduling** (the
other still-blocked candidate). On the four-run band, completion-side
work plus the mutex / IPC layer accounts for ~60 % of overlap wall —
the largest unaccounted slice — but no counter exists for it yet, so
that direction's `blockedOnMeasurement` stays open.

The measurement also re-confirms the structural invariant exp 120 /
exp 122 established: `parked_total` is zero on every measured
workload, including the one with the highest writer-isolate dispatch
cost. The dispatch-admission path is no longer a candidate target
under any current workload.

## Future Notes

- Reopen writer-side dispatch only with a workload that elevates
  `dispatch / wall` clearly above ~15 %. Most likely shapes: very
  wide-row writes (where `allocateParams` dominates), heavy
  invalidating writes against many dirty tables (where
  `getDirtyTableDependencies` walks longer table lists), or
  high-frequency small writes against an unloaded reader pool (where
  IPC framing has nothing to amortize against). On the current suite,
  none of those cross the threshold.
- The per-write Dart dispatch cost (~17–27 µs) is workload-shape-stable
  and dominated by the two FFI calls inside
  `getDirtyTableDependencies` plus the response-buffer allocator pair
  in `executeWrite`. If a future audit isolates `getDirtyTableDependencies`
  itself (e.g. via a third counter pair), it would attribute the
  dispatch slice between FFI cost and pure Dart cost more precisely.
- The remaining open candidate on the direction is **completion-side
  microtask scheduling cost**. After exp 127, that is the largest
  unaccounted slice of A11c overlap wall (~60 %), and the direction's
  only remaining `blockedOnMeasurement` entry. A natural next
  measurement-only run would build a counter that times the
  microtask-hop cost between `_request` resolving and the next write
  reaching the writer.
- The `writerCounters` field on `AuditScenarioResult` is now the
  shared place for any future audit that needs writer-isolate state.
  Existing audits (exp 119, exp 121) ignore it, so adding a counter
  there is structurally compatible with the broader audit family.
