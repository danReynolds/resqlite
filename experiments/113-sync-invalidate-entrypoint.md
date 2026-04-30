# Experiment 113: Synchronous stream invalidation entrypoint

**Date:** 2026-04-30T10:35:00
**Status:** Rejected
**Direction:** `stream-rerun-dispatch`, `measurement-system`

## Problem

`Database.execute()` and `Database.executeBatch()` call
`StreamEngine.invalidate(...)` after the writer isolate returns dirty
tables. The method is declared `async`, but its body never awaits: it
does synchronous dirty-entry bookkeeping, kicks `_flushQueue()`, and the
callers do not await the returned `Future<void>`.

That made a small optimization look plausible: every write might be
paying a completed `Future` allocation even when no streams are active
and `invalidate` returns immediately.

Adjacent context:

- [Exp 045](045-microtask-invalidation-coalescing.md) established that
  invalidation scheduling can matter.
- [Exp 083](083-stream-rerun-pre-dispatch-queue.md),
  [084](084-late-dispatch-generation-stamp.md), and
  [100](100-bounded-stream-requery-scheduler.md) show that stream rerun
  dispatch changes need direct measurement because queueing effects are
  easy to misread.
- [Exp 105](105-reader-pool-sizing.md) found that A11c stream fan-out is
  shaped by completion-side scheduling, not simple parallelism.

## Hypothesis

Changing the internal entrypoint from:

```dart
Future<void> invalidate(List<String>? dirtyTables) async { ... }
```

to:

```dart
void invalidate(List<String>? dirtyTables) { ... }
```

should remove a per-write completed-Future allocation without changing
the public API. If the allocation is material, a tight sequential-write
benchmark should improve most clearly when no streams are active, where
the method returns at its first guard.

Accept if no-stream writes improve repeatably without hurting the
one-stream case. Reject if p50s overlap with baseline or one-stream
tail behavior worsens.

## Approach

Added a focused exploratory benchmark:

```text
dart run benchmark/experiments/sync_invalidate_entrypoint.dart \
  --runs=3 --iterations=3000 --warmup=500
```

The benchmark opens a fresh database for each sample run, seeds 1,000
rows, then measures sequential `UPDATE items SET value = ? WHERE id = ?`
calls. It reports two cases:

- `no_streams`: no reactive streams are registered, so `invalidate`
  returns at `_entries.isEmpty`.
- `one_stream`: one stream is registered and drained before timing, so
  the invalidation path is live without the broader A11c fan-out cost.

The candidate production change was exactly the `Future<void>` to `void`
signature change. It was reverted after measurement.

## Results

All values below are per-write microseconds. Each run reports p50/p90/p99
over 3,000 measured writes after 500 warmup writes.

Baseline pass 1:

| case | run p50s | median p50 | median p90 | median p99 |
|---|---:|---:|---:|---:|
| no_streams | 20, 14, 13 | 14 | 19 | 34 |
| one_stream | 25, 19, 18 | 19 | 31 | 80 |

Candidate (`void invalidate`):

| case | run p50s | median p50 | median p90 | median p99 |
|---|---:|---:|---:|---:|
| no_streams | 22, 14, 14 | 14 | 19 | 43 |
| one_stream | 24, 26, 18 | 24 | 43 | 93 |

Baseline pass 2 after reverting candidate:

| case | run p50s | median p50 | median p90 | median p99 |
|---|---:|---:|---:|---:|
| no_streams | 20, 14, 14 | 14 | 18 | 49 |
| one_stream | 25, 20, 18 | 20 | 37 | 75 |

The no-stream target did not move: both baseline passes and the
candidate had a 14 us median p50. The one-stream case was noisy, and
the candidate's median p50/p90/p99 were worse than the confirmation
baseline.

## Decision

**Rejected.**

The unawaited `async` entrypoint is theoretically wasteful, but the
allocation is below the current writer-round-trip noise floor. Replacing
it with `void` also changes how unexpected synchronous errors would
surface from `invalidate`, so there is no reason to keep the production
change without a clear measurement win.

The focused benchmark remains useful because it isolates the
`invalidate` entrypoint from full A11c fan-out. Future stream-dispatch
experiments can rerun it quickly before spending a full release-suite
pass on entrypoint-level changes.

## Future Notes

Do not revisit the `async`-to-`void` invalidation entrypoint cleanup by
itself. Reopen only if a profile shows completed-Future allocation in
`StreamEngine.invalidate` as a measurable per-write cost, or if a broader
stream-dispatch rewrite already changes the error-surfacing contract.

The more promising stream-rerun direction remains measurement around
queueing, reader-pool dispatch batches, and completion-side churn rather
than single-allocation cleanup at the invalidation boundary.
