# Experiment 136: Completion-side scheduling cost counter

**Date:** 2026-05-14
**Status:** In Review
**Direction:** `stream-rerun-dispatch`, `measurement-system`
**Benchmark Run:** none (profile-mode counter gated by `kProfileMode`; deliverable is the new `completion_handler_us / stream_emit_us` reading on the A11c overlap audit, not a release-suite delta)

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

The writer-isolate split is addressed by exp 147 in this culmination branch.
This experiment ships the second counter.

Both measurements are needed because exp 121 / exp 147 left the
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
(unlike the writer-side counters in exp 147).

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
exp 121 / exp 147 also consume.

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

Fresh current-branch pass after rebasing with exp 147:

| workload | wall_ms | drain_ms | total_ms | completion_us | completion_count | emit_us | emit_count | invalidate_us | parked_total | max_parked | emissions |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline (0 streams x 500) | 71.16 | 0.00 | 71.16 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| A11c disjoint (50 streams x 500) | 71.82 | 56.56 | 128.38 | 0 | 0 | 0 | 0 | 17,816 | 0 | 0 | 0 |
| A11c overlap (50 streams x 500) | 159.19 | 107.37 | 266.56 | 76,154 | 4,228 | 266 | 29 | 25,724 | 0 | 0 | 29 |
| keyed PK (50 streams x 200 random) | 37.44 | 407.17 | 444.60 | 18,807 | 1,108 | 59 | 3 | 5,752 | 0 | 0 | 3 |

Derived fractions:

| workload | completion / burst | completion / total | emit / total | emit / completion | us / completion | invalidate / burst |
|---|---:|---:|---:|---:|---:|---:|
| A11c baseline | 0.00% | 0.00% | 0.00% | 0.00% | 0.00 | 0.00% |
| A11c disjoint | 0.00% | 0.00% | 0.00% | 0.00% | 0.00 | 24.81% |
| A11c overlap | 47.84% | 28.57% | 0.10% | 0.35% | 18.01 | 16.16% |
| keyed PK | 50.24% | 4.23% | 0.01% | 0.31% | 16.97 | 15.37% |

`emit_us` remains negligible: 0.35% of `completion_us` on A11c overlap and
0.31% on keyed-PK.

Sanity: `dispatcher_parked_total = 0`, `dispatcher_wake_retry_total =
0`, and `dispatcher_max_parked_concurrent = 0` on every workload —
exp 120 / exp 122 still hold post-instrumentation.

**A11c overlap completion-side reading.**
The reader worker port handler accounts for 28.57% of total A11c
overlap wall (burst + drain). With 4,228 completions per burst and
~18 µs/call, the handler is doing meaningful per-reply work while
actual subscriber emits stay rare (29 emits in this pass). The
per-call cost is therefore "handler bootstrap + Future
resolution + selectIfChanged short-circuit + flushQueue admit/dispatch
of the next rerun", not subscriber delivery.

**A11c disjoint reading.**
Column-level dependency tracking (exp 106) elides every re-query on
the writer side before it ever reaches the reader pool, so the
completion-side counters stay at zero — confirming the counters are
correctly attributed to reader-reply chains, not background traffic.

**Keyed-PK reading.**
Completion is 4.23% of total wall. With 50 streams watching
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
That entry can drop; exp 147 closes the writer-isolate wall split, so
`stream-rerun-dispatch.blockedOnMeasurement` is fully empty.

The audit's headline reading is that **reader-completion handling IS
a meaningful slice of A11c overlap wall** (28.57% of total wall, ~18 µs
per call across 4,228 calls per burst). Two specific shape findings:

- **Subscriber emit is not the cost.** Per `stream_emit_us` <
  1% of `completion_us`, batching `controller.add` calls or compressing
  the subscriber loop will not move overlap wall.
- **Per-call cost is bootstrap-shaped, not work-shaped.** Most reader
  replies on A11c overlap short-circuit via `selectIfChanged`'s hash
  comparison; the ~18 µs/call is mostly handler entry, Future
  resolution, hash check, and the recursive `_flushQueue` admit step,
  not real query result work.

That makes **reader-reply batching** the natural candidate worth a
focused implementation experiment: collapse N short-circuited replies
into a single handler invocation by either (a) merging consecutive
`_flushQueue` admits before re-entering `_dispatch`, or (b) extending
the reader-worker protocol to return multiple per-stream `unchanged`
acknowledgements in one message. Either change targets the 28.57% of
overlap total wall captured here. A 50% reduction in per-call cost (from
~18 µs down to ~9 µs) would save ~14% of total overlap wall — at the
per-benchmark release-suite decision threshold edge, but materially
larger than exp 121's invalidation-traversal ceiling.

On keyed-PK (4.23% of total wall) and disjoint (0%) the same change
would not move the needle. So a future reader-completion-batching
experiment must accept on A11c overlap *and* stay neutral on disjoint
and keyed-PK; otherwise the win is at best workload-specific and
overall release-suite-neutral.

## Future Notes

- After this experiment lands together with exp 147, the
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
