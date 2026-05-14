# Experiment 136: Completion-side scheduling cost counter

**Date:** 2026-05-14
**Status:** In Review
**Direction:** `stream-rerun-dispatch`, `measurement-system`

## Problem

[Exp 120](120-flush-admit-bound.md) closed the over-dispatch path inside
`StreamEngine._flushQueue` and dropped `dispatcherParkedTotal` /
`dispatcherMaxParkedConcurrent` to zero on every measured stream
workload. [Exp 121](121-invalidation-traversal-audit.md) then audited
invalidation traversal under the writer-side burst wall convention and
found it sits at the per-benchmark decision threshold edge — 10–15% of
A11c overlap wall, with column intersection 2.5–5.7%.

Exp 120 and exp 121 left two named gating measurements in
[`signals.json#stream-rerun-dispatch.blockedOnMeasurement`](signals.json):

- writer-isolate wall vs SQLite step wall split
- **completion-side microtask scheduling cost counter**

The first is addressed in a parallel PR (exp 135 writer-handler /
SQLite-step counters). This experiment ships the second.

Both measurements are needed because exp 121 / exp 135 left the
remaining stream-fanout wall sitting on the main isolate — emission
delivery, microtask scheduling, and reader-pool completion handling —
with no counter on any of those paths. Until one of them shows nonzero
headroom on a measurable workload, dispatch-area implementation
experiments stay on hold (per `signals.json#stream-rerun-dispatch.notesForExperimenters`).

## Hypothesis

After exp 120 / 121, the bulk of A11c overlap main-isolate wall is in
reader-pool completion: every stream re-query reply lands on the main
isolate inside the worker port handler, which then runs the entire
`_dispatch` resume / `_requery` continuation / `entry.emit` /
`_flushQueue` chain synchronously (because `_WorkerSlot.request` uses
`Completer<Object?>.sync()`).

If reader-completion wall is a small slice of total fanout wall (< 10%),
future dispatch work should branch off reader-completion entirely.
If it is large (≥ 15%), reader completion batching / coalescing
becomes a bounded implementation candidate worth a focused experiment.

Accept this as a measurement experiment if:

- `parked_total` and `wake_retry_total` stay at zero on every measured
  workload, reproducing exp 120 / exp 122 as a sanity check;
- the audit produces stable `completion_us / total_us`,
  `emit_us / completion_us`, and `us per completion` bands across
  repeated passes for A11c baseline / disjoint / overlap and keyed-PK
  subscriptions;
- the result resolves the
  [`signals.json#stream-rerun-dispatch.blockedOnMeasurement`](signals.json)
  `completion-side microtask scheduling cost counter` entry one way or
  the other, and updates `blockedOnMeasurement` accordingly.

## Approach

Two-part change.

**Profile counters.** `ProfileCounters` gains four main-isolate fields:

- `completionHandlerUs` — cumulative wall-clock microseconds in the
  reader worker port handler synchronous body. The handler is the
  ground-floor entry point for reader replies on the main isolate;
  because `_WorkerSlot.request` uses `Completer<Object?>.sync()`, the
  full `await _pool.selectIfChanged(...)` continuation in
  `StreamEngine._requery` (hash compare, `entry.emit`, `_flushQueue`)
  runs synchronously inside the handler. So one stopwatch captures the
  whole completion-side wall per reply, including the recursive
  `_flushQueue` dispatch of the next batched rerun.
- `completionHandlerCount` — count of reader-reply completions handled.
- `streamEmitUs` — sub-counter spent inside `StreamEntry.emit`'s
  subscriber-fanout loop (per-subscriber `controller.add`). A subset
  of `completionHandlerUs` when emit is driven by a reader reply.
- `streamEmitCount` — count of `emit` calls.

All four live on the main isolate, so no snapshot RPC is needed
(unlike the writer-side counters in exp 135).

**Handler instrumentation.** The reader worker port handler at
`lib/src/reader/reader_pool.dart` wraps the normal-reply branch in a
profile-mode-only stopwatch. Startup-handshake and onExit branches are
excluded. Sacrifice replies are counted because they still drive the
same `pending.complete(result)` chain.

`StreamEntry.emit` in `lib/src/stream_engine.dart` wraps the
subscriber-fanout loop in a second profile-mode-only stopwatch.

**Audit harness.** A new harness file
`benchmark/profile/completion_scheduling_audit.dart` formats the
A11c-baseline / A11c-disjoint / A11c-overlap / keyed-PK report,
reusing the shared `audit_workloads.dart` scenarios that exp 119 /
exp 121 / exp 135 also consume.

Two changes were needed in `audit_workloads.dart` because most
reader-completion work fires AFTER the writer-burst wall ends (most
reader replies arrive during the drain, not inside the burst):

1. `AuditScenarioResult` gains an optional `countersAfterDrain`
   snapshot taken after the drain finishes. Existing exp 119 / exp 121
   consumers ignore it and continue using `counters` (snapshotted at
   burst-end). Writer-side counters stop incrementing once writes
   stop, so the two snapshots agree on those fields by construction.
2. The A11c drain switched from a fixed 50 ms wait to the same
   quiet-window pattern keyed-PK already uses (50 ms quiet window,
   60 s deadline). The drain wall is reported separately as
   `drain_us`; `wall_us` continues to be writer-side burst wall.

This keeps exp 121's denominator stable (burst wall) while the new
completion counter snapshot captures all reader-side work that the
scenario produced.

## Results

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`).

Command:

```text
dart run -DRESQLITE_PROFILE=true \
  benchmark/profile/completion_scheduling_audit.dart --markdown
```

Four repeated passes (a/b/c/d). The committed aggregate
([`exp-136-completion-scheduling-aggregate.md`](../benchmark/profile/results/exp-136-completion-scheduling-aggregate.md))
shows pass d; the other three passes match the same band.

| workload | wall_ms (a/b/c/d) | drain_ms (d) | total_ms (d) | completion_us (d) | completion / total (a/b/c/d) | us / completion (a/b/c/d) |
|---|---:|---:|---:|---:|---:|---:|
| A11c baseline (0 streams x 500) | 50.7 / 47 / 44.9 / 53.1 | 0 | 53.1 | 0 | — | — |
| A11c disjoint (50 streams x 500) | 37.9 / 41 / 40.0 / 42.1 | 54.0 | 96.2 | 0 | 0% / 0% / 0% / 0% | — |
| A11c overlap (50 streams x 500) | 90.3 / 95.0 / 93.5 / 107.1 | 102.6 | 209.7 | 57,424 | 21.9% / 23.0% / 20.9% / 27.4% | 11.9 / 11.6 / 10.9 / 14.8 µs |
| keyed PK (50 streams x 200 random) | 23.3 / 31.7 / 23.4 / 24.6 | 203.5 | 228.1 | 11,161 | 4.7% / 4.2% / 4.7% / 4.9% | 8.9 / 7.6 / 8.5 / 9.3 µs |

`emit_us` is negligible on every workload: 12–412 µs across the four
passes on A11c overlap (≤ 0.7% of `completion_us`), 12–17 µs on
keyed-PK (≤ 0.2% of `completion_us`).

Sanity: `dispatcher_parked_total = 0`, `dispatcher_wake_retry_total =
0`, and `dispatcher_max_parked_concurrent = 0` on every workload —
exp 120 / exp 122 still hold post-instrumentation.

**A11c overlap completion-side reading.**
The reader worker port handler accounts for 22–27% of total A11c
overlap wall (burst + drain). With 3,700–3,870 completions per burst
and ~12 µs/call, the handler is doing meaningful per-reply work but
99.2% of those replies are short-circuited by `selectIfChanged`'s
hash comparison (3,870 completions → 28–31 actual subscriber emits per
burst). The per-call cost is therefore "handler bootstrap + Future
resolution + selectIfChanged short-circuit + flushQueue admit/dispatch
of the next rerun", not subscriber delivery.

**A11c disjoint reading.**
Column-level dependency tracking (exp 106) elides every re-query on
the writer side before it ever reaches the reader pool, so the
completion-side counters stay at zero — confirming the counters are
correctly attributed to reader-reply chains, not background traffic.

**Keyed-PK reading.**
Completion is 4.2–4.9% of total wall. With 50 streams watching
random PKs and only ~3 watched-row hits per 200-write burst, almost
all re-queries short-circuit on hash; absolute completion wall is an
order of magnitude smaller than A11c overlap.

**Emit cost.**
`stream_emit_us` is sub-1% of `completion_us` on every workload. The
subscriber-fanout loop is not the optimization target — even if
subscriber count grew, the dominant per-call cost is the chain
bootstrap, not the controller add.

## Decision

**Accept for review — measurement.**

The audit ships the
`completion-side microtask scheduling cost counter` named in
[`signals.json#stream-rerun-dispatch.blockedOnMeasurement`](signals.json).
That entry can drop; the parallel in-flight exp 135 closes the writer-
isolate wall split, after which `stream-rerun-dispatch.blockedOnMeasurement`
is fully empty.

The audit's headline reading is that **reader-completion handling IS
a meaningful slice of A11c overlap wall** (22–27% of total wall, ~12 µs
per call across ~3,800 calls per burst). Two specific shape findings:

- **Subscriber emit is not the cost.** Per `stream_emit_us` <
  1% of `completion_us`, batching `controller.add` calls or compressing
  the subscriber loop will not move overlap wall.
- **Per-call cost is bootstrap-shaped, not work-shaped.** 99.2% of
  reader replies on A11c overlap short-circuit via `selectIfChanged`'s
  hash comparison; the ~12 µs/call is mostly handler entry, Future
  resolution, hash check, and the recursive `_flushQueue` admit step,
  not real query result work.

That makes **reader-reply batching** the natural candidate worth a
focused implementation experiment: collapse N short-circuited replies
into a single handler invocation by either (a) merging consecutive
`_flushQueue` admits before re-entering `_dispatch`, or (b) extending
the reader-worker protocol to return multiple per-stream `unchanged`
acknowledgements in one message. Either change targets the 22–27% of
overlap wall captured here. A 50% reduction in per-call cost (from
~12 µs down to ~6 µs) would save ~10% of total overlap wall — at the
per-benchmark release-suite decision threshold edge, but materially
larger than exp 121's invalidation-traversal ceiling.

On keyed-PK (~5% of total wall) and disjoint (0%) the same change
would not move the needle. So a future reader-completion-batching
experiment must accept on A11c overlap *and* stay neutral on disjoint
and keyed-PK; otherwise the win is at best workload-specific and
overall release-suite-neutral.

## Future Notes

- After this experiment lands together with exp 135, the
  `stream-rerun-dispatch.blockedOnMeasurement` array is empty. The
  remaining open candidates that named blockers will need to be
  re-evaluated against the new counter evidence rather than against
  "we haven't measured it yet."
- A future reader-reply-batching implementation experiment should be
  evaluated against this audit: `completion_us / total_us` must drop
  on A11c overlap, *and* per-call `us per completion` must drop, *and*
  `dispatcher_parked_total` must stay at zero. Any one of those
  failing means the change isn't doing what its name says.
- The `emit_us` counter is low-signal on the current suite but is
  cheap to leave in place. A future workload with very many
  subscribers per stream (single stream, hundreds of listeners) would
  light it up; until then, treat it as evidence-of-absence for
  subscriber-fanout-optimization candidates.
- The quiet-window drain pattern is now shared between A11c and
  keyed-PK scenarios. If a future audit needs a different stop
  condition, push the change into `audit_workloads.dart` so every
  consumer stays directly comparable, the same way exp 121's wall
  convention propagated.
