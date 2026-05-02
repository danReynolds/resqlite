# Experiment 120: Bounded `_flushQueue` admission

**Date:** 2026-05-02
**Status:** In Review
**Direction:** `stream-rerun-dispatch`

## Problem

Experiment 119 measured the post-FIFO dispatch-pressure surface and found
the surviving signal: A11c overlap creates 3,590 parked dispatchers per
500-write burst and reaches `max_parked = 46` parked dispatchers
concurrently, even though `dispatcherWakeRetryTotal` stays at 0. Keyed-PK
subscriptions show 1,198 parks and the same 46 max parked. Disjoint A11c
stays at zero because exp-106's column-level elision skips re-queries on
the writer side before they reach the reader pool.

The 46-deep parking peak is a structural ceiling: with a pool of 4 and 50
streams marked dirty per write, every overlap write puts the remaining 46
streams into `_dispatchWaiters`. Exp 119's "Future Notes" pointed at
making `_flushQueue` single-flight or otherwise preventing multiple flush
passes from racing beyond current reader availability.

The cause is over-dispatch inside a single `_flushQueue` call. The loop
checks `pool.hasAvailableWorker` synchronously, but `_requery`'s slot
reservation lives behind an `await _pool` hop in `ReaderPool._dispatch`.
Within the synchronous loop body, none of the fire-and-forget `_requery`
calls have claimed a slot yet, so `hasAvailableWorker` reports stale-true
on every iteration — `_flushQueue` empties the queue regardless of pool
capacity, and the resulting `_dispatch` microtasks pile up against
`_dispatchWaiters`.

## Hypothesis

Snapshotting the available-worker count once at the top of `_flushQueue`
and decrementing per pop will cap admission to actual capacity. Each
`_requery`'s `finally` already calls `_flushQueue()` again on completion,
so the remaining 46 streams are picked up in FIFO order through that
follow-on path instead of the parked-dispatcher path. The chain matches
the existing FIFO order exp 118 enforces in the pool.

Predicted effects:

- `dispatcherParkedTotal` and `dispatcherMaxParkedConcurrent` drop sharply
  on overlap and keyed-PK workloads.
- A11c disjoint stays at 0 parks (exp-106 elides those re-queries upstream
  — the change is invisible on disjoint, as it should be).
- The release suite stays neutral on high-cardinality fan-out (the
  workload that rejected exp 100, the prior bounded-admission attempt).
  The candidate keeps the same total work and FIFO order; it only removes
  the per-`_dispatch` park/wake microtask hop.

## Approach

Two small additions, no native changes:

1. `ReaderPool.availableWorkerCount` — a `int` getter that walks the slot
   list once and counts `isAvailable` slots. Used by the stream engine to
   bound admission. The existing `hasAvailableWorker` is preserved for
   external callers and tests.
2. `StreamEngine._flushQueue` — snapshot the count once and decrement per
   pop instead of re-checking `hasAvailableWorker` every iteration:

   ```dart
   var slots = pool.availableWorkerCount;
   while (_requeryQueue.isNotEmpty && slots > 0) {
     final entry = _requeryQueue.first;
     _requeryQueue.remove(entry);
     _requery(entry);
     slots--;
   }
   ```

Existing follow-up paths are unchanged: `_requery`'s `finally` already
calls `_flushQueue()` after each completion, so streams that exceed the
admission cap are picked up as workers free.

This is structurally different from the rejected exp 100 scheduler, which
deferred drains into a scheduled task and added latency between
invalidation and dispatch. Exp 120 keeps the synchronous, eager dispatch
shape — it only stops popping when the pool is provably full.

## Results

### Profile-mode dispatch pressure audit

3 passes per side using `benchmark/profile/dispatch_pressure_audit.dart`,
median values shown. Reader pool size = 4. Full per-run table is in
[`benchmark/profile/results/exp-120-flush-admit-bound-aggregate.md`](../benchmark/profile/results/exp-120-flush-admit-bound-aggregate.md).

| workload                | wall_ms (base → cand) | parked_total (base → cand) | max_parked (base → cand) |
|-------------------------|----------------------:|---------------------------:|-------------------------:|
| direct reads control    |       1.06 → 1.03 ms  |                 28 → 28    |                28 → 28   |
| A11c baseline           |      85.00 → 84.61 ms |                  0 → 0     |                 0 → 0    |
| A11c disjoint           |      90.15 → 89.09 ms |                  0 → 0     |                 0 → 0    |
| A11c overlap            |     138.30 → 131.09 ms|              **3590 → 0**  |             **46 → 0**   |
| keyed PK subscriptions  |     425.91 → 425.66 ms|              **1198 → 0**  |             **46 → 0**   |

`dispatcherWakeRetryTotal` stays at zero on every workload, both sides
(exp 118's FIFO waiters already eliminated wake amplification — that
result is preserved).

### Release suite (full A/B, 3 repeats per side)

Result files:

- `benchmark/results/2026-05-02T07-18-52-baseline-for-exp120.md`
- `benchmark/results/2026-05-02T07-25-17-exp120-flush-admit-bound.md`

Headline rows for the workloads exp 119 flagged and the workload that
rejected exp 100:

| Benchmark                                                              | Baseline | Candidate |    Delta | Threshold | Status |
|------------------------------------------------------------------------|---------:|----------:|---------:|-----------|--------|
| High-Cardinality Stream Fan-out / 100 streams × 200 writes / resqlite  | 238.59   | 241.96    |   +1.4%  | ±10%      | within noise |
| Keyed PK Subscriptions / 50 streams × 200 random-PK / resqlite         | 227.56   | 220.75    |   −3.0%  | ±10%      | within noise |
| Many-Streams Writer Throughput / disjoint / resqlite (wall)            | within noise across all rows |
| Reactive feed with 100 concurrent writes / resqlite                    | 112.06   | 111.49–112.08 |   ±0%   | ±10%      | within noise |

Comparator output:

- **Summary:** 9 wins, 0 regressions, 152 neutral.
- "✅ No regressions beyond noise."

The exp-100 killer (high-cardinality fan-out) is +1.4%, deep inside the
±10% threshold and within the run-to-run band visible in the per-pass
profile audit (single-run +1% on a sub-second benchmark is normal). The
prior rejection (+103%) does not reproduce. Keyed-PK trends 3% better.

### Validation

- `dart analyze` (whole package): clean.
- `dart test test/stream_test.dart test/stream_invalidation_coalescing_test.dart
  test/reader_pool_test.dart test/stream_dependency_shapes_test.dart
  test/stream_overflow_fallback_test.dart test/stream_cache_hit_reliability_test.dart
  test/stream_trigger_cascade_test.dart test/benchmark_pipeline_test.dart
  test/benchmark_generated_outputs_test.dart`: 73 passed, 0 failed.
- `dart test test/benchmark_many_streams_writer_throughput_test.dart`: passed.
- `dart run benchmark/check_generated_data.dart`: clean after
  `generate_devices.dart` + `generate_history.dart`.

## Decision

**Accept.** Exp 119's acceptance bar — "reduces
`dispatcherParkedTotal`/`dispatcherMaxParkedConcurrent` on A11c overlap or
keyed-PK without hurting disjoint writes" — is met:

- Overlap parking: 3590 → 0, max parked 46 → 0.
- Keyed-PK parking: 1198 → 0, max parked 46 → 0.
- Disjoint stays at 0 parks (exp-106 still elides upstream).
- Release suite: 9 wins, 0 regressions; high-cardinality fan-out neutral.

The wall-time delta on overlap is small but consistent (−5% across 3
passes); on keyed-PK it is flat (per-park work was a single FIFO microtask
hop on current main, not pool serialization). The durable signal is
removing a structurally noisy pattern: stream re-query admission is now
upper-bounded by the pool, not by the queue depth.

## Future Notes

This change makes the parked-dispatcher path on A11c overlap and keyed-PK
disappear, which in turn means future dispatch experiments need a new
direct counter to gate evaluation. The remaining stream re-query pressure
must show up somewhere else:

- Completion-side churn — measure via main-isolate microtask scheduling
  cost on overlap workloads.
- Write-side dispatch — measure via writer wall split (writer wallclock
  vs SQLite wallclock) when many streams are dirty.
- Invalidation traversal — already counted by
  `ProfileCounters.invalidateUs` / `intersectionUs`, but those have not
  been audited as a fraction of overlap wall.

The prior rejection (exp 100) was specifically a *bounded scheduler* with
deferred drain and added per-invalidation latency. The lesson preserved
in `JOURNAL.md` ("Re-running a rejected experiment requires the
rejection's reason to have changed") still applies: this is not the same
implementation. Exp 120 keeps eager dispatch, only swaps the synchronous
loop's stale `hasAvailableWorker` for an explicit count.
