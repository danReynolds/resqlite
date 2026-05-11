# Experiment 136: Stream completion-side wall audit

**Date:** 2026-05-11
**Status:** In Review
**Direction:** `stream-rerun-dispatch`, `measurement-system`

## Problem

[Exp 135](135-writer-step-wall-audit.md) split the writer-isolate
handler wall into Dart dispatch and SQLite step time and read the
fractions against the exp 119 / 121 wall convention. On A11c overlap
the writer-isolate handler turned out to be only ~22-25% of writer-
side burst wall — the remaining ~75% lives on the main isolate, in
stream emission delivery, dirty-table propagation, and microtask
scheduling. Exp 135 explicitly named the next gating measurement:

> The remaining `completion-side microtask scheduling cost counter`
> open candidate is the next gating measurement for stream-rerun-
> dispatch implementation work.

That measurement is what `signals.json#stream-rerun-dispatch.blockedOnMeasurement`
still listed. Without it, any A11c-overlap implementation experiment
that targeted the main-isolate share would be guessing whether the
target cost is large enough to clear the per-benchmark decision
threshold — the same shape that bit exp 121 (invalidation traversal,
~10-15% ceiling) and exp 135 (writer-side Dart dispatch, ~9-11%
ceiling). The runner instructions are explicit that another writer-
side or dispatch implementation experiment should not be tried
without a directly observable signal first.

## Hypothesis

After exp 120 / 122 closed the upstream over-dispatch path, the main-
isolate share of A11c overlap burst wall splits roughly into:

- `onDependencyChanges` synchronous work (already measured as
  `invalidate_us` by exp 121, ~10-15% of wall),
- the synchronous post-`await` body of `StreamEngine._requery` —
  dirty/in-flight bookkeeping, hash-changed shortcut, `entry.emit`,
  and the trailing `_flushQueue` re-entry,
- `StreamController.add` fan-out inside `StreamEntry.emit`,
- framework microtask scheduling, async/await chaining, reader-pool
  internals, and subscriber callbacks the counters cannot reach.

Adding two new main-isolate counters (`stream_complete_us`,
`stream_emit_us`, plus their counts) makes the first three
quantifiable and lets `accounted / wall = (invalidate_us +
stream_complete_us) / wall_us` express the share of wall that the
synchronous main-isolate stream-engine code covers.

Accept this as a measurement experiment if:

- `dispatcher_parked_total` and `dispatcher_wake_retry_total` stay at
  zero on every measured workload, reproducing exp 120 / 122 as a
  sanity check on top of the new counters;
- the audit produces stable `complete / wall`, `emit / complete`, and
  `accounted / wall` bands across repeated passes for A11c baseline /
  disjoint / overlap and keyed-PK subscriptions;
- the result resolves the `completion-side microtask scheduling cost
  counter` open candidate one way or the other, and updates
  `blockedOnMeasurement` accordingly.

## Approach

Two-part change.

**Profile counters.** `ProfileCounters` gains four main-isolate
fields:

- `streamCompleteUs` — cumulative wall inside the post-`await` body
  of `StreamEngine._requery`. Stopwatch is started right after
  `selectIfChanged` resolves, captured inside the existing `finally`,
  and recorded after the `_flushQueue` re-entry runs. Profile-mode-
  gated, so release builds keep `completeSw` null and tree-shake the
  recording.
- `streamCompleteCount` — one increment per resolved re-query,
  including completions where the hash-changed shortcut suppressed
  emission. Those completions still execute bookkeeping and
  `_flushQueue`, so they belong in the per-completion denominator.
- `streamEmitUs` / `streamEmitCount` — wall inside `StreamEntry.emit`'s
  for-loop only. `streamEmitUs` is a strict subset of
  `streamCompleteUs` because every emit during fanout runs inside the
  completion wall.

The existing main-isolate snapshot/diff/reset machinery picks up the
new keys without an RPC. The writer counters from exp 135 still come
through the snapshot RPC.

**Audit harness.** A new file `benchmark/profile/stream_completion_audit.dart`
reuses the `audit_workloads.dart` scenarios exp 119 / 121 / 135 share
(A11c baseline / disjoint / overlap and keyed-PK subscriptions) and
formats the new counters alongside `invalidate_us`. Header and
"Reading the table" sections call out that `emit_us` is a subset of
`complete_us` and that `accounted / wall` is the synchronous main-
isolate share.

## Results

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`).

Command:

```text
dart run -DRESQLITE_PROFILE=true \
  benchmark/profile/stream_completion_audit.dart --markdown
```

Four repeated passes (a/b/c/d) — d is the saved aggregate:

| workload | wall_ms (a/b/c/d) | complete / wall | invalidate / wall | accounted / wall | us per complete |
|---|---:|---:|---:|---:|---:|
| A11c baseline (0 streams x 500) | 37.4 / 32.8 / 32.8 / 32.4 | 0 / 0 / 0 / 0 % | 0 / 0 / 0 / 0 % | 0 / 0 / 0 / 0 % | n/a |
| A11c disjoint (50 streams x 500) | 42.3 / 38.8 / 37.6 / 37.3 | 0 / 0 / 0 / 0 % | 18.9 / 21.7 / 21.0 / 21.1 % | 18.9 / 21.7 / 21.0 / 21.1 % | n/a |
| A11c overlap (50 streams x 500) | 89.5 / 87.4 / 86.3 / 91.7 | 29.8 / 29.5 / 29.8 / 31.7 % | 15.1 / 14.7 / 15.0 / 14.9 % | 44.9 / 44.2 / 44.8 / 46.7 % | 7.1 / 6.9 / 6.8 / 7.4 µs |
| keyed PK subs (50 streams x 200) | 20.1 / 19.4 / 19.4 / 23.7 | 21.6 / 20.8 / 22.2 / 19.5 % | 15.3 / 15.5 / 15.2 / 13.9 % | 36.9 / 36.3 / 37.3 / 33.5 % | 4.1 / 3.8 / 4.1 / 4.1 µs |

Sanity: `dispatcher_parked_total = 0`, `dispatcher_wake_retry_total =
0`, and `dispatcher_max_parked_concurrent = 0` on every workload —
exp 120 / 122 still hold post-instrumentation.

The full counter table for the saved pass lives at
`benchmark/profile/results/exp-136-stream-completion-aggregate.md`.

Aggregate readings:

- **A11c overlap.** `complete_us` is a stable ~29.5-31.7% of writer-
  burst wall across four passes. Combined with the exp 121
  `invalidate_us` band (~15%), the synchronous main-isolate stream-
  engine code accounts for ~44-47% of wall. Per-handler completion is
  ~6.8-7.4 µs, dominated by the trailing `_flushQueue` re-entry plus
  dirty/in-flight bookkeeping — only ~21 emissions land in a 500-write
  burst (hash-suppressed), so `emit_us` is < 0.3% of wall. There are
  ~3,750 completions per burst because every column-overlapping write
  re-dirties every stream and the `_flushQueue` finally re-entry pulls
  more entries through the same path.
- **A11c disjoint.** `complete_us = 0`: column-level elision (exp 106)
  filters every re-query out of `_flushQueue` at invalidation time, so
  `_requery` never fires. `invalidate_us` alone covers ~19-21% of
  wall, the disjoint denominator's known shape (the column-intersection
  probes happen but the resulting `dirtyEntries` set is empty).
- **A11c baseline (no streams).** All stream counters at zero, as
  expected — the workload has no stream entries to dirty.
- **Keyed-PK subscriptions.** `complete_us` is ~20-22% of wall and
  `invalidate_us` ~14-15%, totaling ~33-37% accounted. Per-handler
  completion is ~4 µs across all four passes — half the A11c overlap
  per-handler figure, consistent with single-row keyed-PK projections
  having less bookkeeping per completion than the 20-column wide
  selects.

The unaccounted band on A11c overlap is ~53-55% of wall. This is the
combined cost of:

- async/await framework scheduling between writer reply → reader
  dispatch → completion delivery,
- reader-pool internal main-isolate work (already monitored by exp
  115/118 dispatcher counters but not summed against wall),
- subscriber callback dispatch through `StreamController.add` event
  loop scheduling,
- microtask churn between every `await` resolution in `_flushQueue`
  / `_requery`.

The structural ceiling for "remove all synchronous main-isolate
stream-engine work" on A11c overlap is therefore ~45% of wall. The
narrower target — eliminating just the `_requery` post-await body — is
~30% of wall and is the directly addressable share of the audit. Per-
handler dispatch is small (~7 µs) but accumulates across ~3,750
completions per overlap burst; halving it would save ~15% of wall,
past the per-benchmark decision threshold.

## Decision

**Accept for review — measurement.**

Exp 136 ships the main-isolate stream completion counter and answers
the `completion-side microtask scheduling cost counter` open
candidate. `signals.json#stream-rerun-dispatch.blockedOnMeasurement`
drops this entry and is now empty.

The audit's headline reading is that **the synchronous main-isolate
stream-engine code accounts for ~45% of A11c overlap wall** —
`complete_us` ~30% (the post-`await` body of `_requery`) plus
`invalidate_us` ~15% (the synchronous body of
`onDependencyChanges`). The remaining ~55% lives in framework
microtask scheduling, async/await chaining, reader-pool internals,
and subscriber callback dispatch — none of which the counters can
reach without further instrumentation.

This sets a clear bar for the next implementation experiment in
`stream-rerun-dispatch`: a change that targets the `_requery` post-
await body needs to clear the structural ~30%-of-wall ceiling on
A11c overlap. Per-handler completion is ~7 µs across ~3,750
handlers per burst, so a per-handler optimization needs to show
itself at the per-handler level even when wall-time deltas are
noisy.

The audit also confirms `dispatcher_parked_total = 0` and
`dispatcher_wake_retry_total = 0` across every measured workload —
exp 120 / 122 still hold. The new counters are tree-shakeable
(release builds keep `completeSw` null and skip the recording
branch), so the public benchmark path retains zero diagnostic cost.

## Future Notes

Exp 135 / 136 between them close both entries in
`stream-rerun-dispatch.blockedOnMeasurement`. The next dispatch-area
implementation experiment should:

- Target either the per-handler `_requery` completion path (~30% of
  A11c overlap wall, ~7 µs per of ~3,750 handlers) or the unaccounted
  ~55% (framework / microtask / subscriber callback) — the former is
  directly measurable here, the latter would need a finer-grained
  counter or `Timeline` events around the async boundaries before
  acceptance.
- Accept only if `complete_us` per handler on A11c overlap drops
  reproducibly across a 5-run release suite *and* the wall-time delta
  is past the per-benchmark decision threshold — exp 135 showed how
  easily a structurally real change can sit at the threshold edge.
- Reproduce `dispatcher_parked_total = 0` on every workload as a
  sanity check, the same pattern exp 122 / 135 use.

The harness reuses the shared `audit_workloads.dart` scenarios, so
future audits that need per-completion or per-emit cost across new
workloads get the counters for free.

Speculative candidates that the new counter now lets a future runner
evaluate quickly:

- collapsing the `_flushQueue` re-entry inside the `finally` of
  `_requery` (~7 µs / handler today) into a microtask hop or
  cooperative scheduler — would expect `complete_us` to drop without
  changing `invalidate_us`,
- splitting the per-completion bookkeeping (dirty/inFlight/hash) from
  the emit fan-out to give the emit path its own micro-fast-path on
  the hash-suppressed completion (>99% of A11c overlap completions),
- batching small `_requery` completions to amortize the synchronous
  post-await tail across multiple resolved re-queries.

None of these are committed candidates; the audit's job is to give
the next runner the gate signal, not to choose the implementation.
