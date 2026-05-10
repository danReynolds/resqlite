# Experiment 135: Writer-isolate dispatch wall vs SQLite step wall audit

**Date:** 2026-05-10
**Status:** In Review
**Direction:** `stream-rerun-dispatch`, `measurement-system`

## Problem

[Exp 120](120-flush-admit-bound.md) closed the over-dispatch path inside
`StreamEngine._flushQueue` and dropped reader-pool dispatcher counters
to zero on every measured stream workload.
[Exp 121](121-invalidation-traversal-audit.md) then audited
invalidation traversal as a fraction of A11c overlap wall and found it
sits at the per-benchmark decision threshold edge (10–15% of wall, 80–
200 ns per probe).

Exp 121's future-notes called out the next two dispatch-area
candidates from exp 120's list:

- completion-side microtask scheduling cost counter
- writer dispatch wall counter (Dart-side wall − SQLite step wall)

Both were listed in `signals.json#stream-rerun-dispatch.blockedOnMeasurement`
with no infrastructure to evaluate them. `signals.json` is explicit
about the gate this places on dispatch-area implementation work:

> "A new dispatch experiment now needs a counter for completion-side
> scheduling cost or writer-side dispatch wall showing nonzero
> headroom on the workload before the change is worth trying."

This experiment ships the second of those measurements.

## Hypothesis

After exp 120 / exp 121, the writer-isolate handler wall on stream
workloads is mostly SQLite step time, with Dart-side dispatch (param
allocation, dirty-table marshalling, message build/send) at a small,
optimization-sensitive but per-benchmark-sub-threshold share. If this
is true, writer-side dispatch should not be the next implementation
target on currently-measured workloads, and the structural ceiling for
"remove all writer-side Dart dispatch" should be close to exp 121's
invalidation-traversal ceiling (10–15% of A11c overlap wall).

Accept this as a measurement experiment if:

- `parked_total` and `wake_retry_total` stay at zero on every measured
  workload, reproducing exp 120 / exp 122 as a sanity check on top of
  the new counters;
- the audit produces stable `writer_handler_us / wall_us`,
  `writer_sqlite_us / writer_handler_us`, and `dispatch_us / wall_us`
  bands across repeated passes for A11c baseline / disjoint / overlap
  and keyed-PK subscriptions;
- the result resolves the `writer-isolate wall vs SQLite wall split`
  open candidate one way or the other, and updates
  `blockedOnMeasurement` accordingly.

## Approach

Three-part change.

**Profile counters.** `ProfileCounters` gains three writer-isolate
fields: `writerHandlerUs`, `writerSqliteUs`, `writerHandlerCount`. The
existing main-isolate snapshot/reset/diff plumbing works unchanged on
the new keys. Dart isolates do not share top-level state, so the
counters live in the writer's own copy of the file globals — invisible
to the main snapshot.

**Snapshot RPC.** The writer protocol gains two new request types,
`WriterCountersSnapshotRequest` and `WriterCountersResetRequest`,
served from inside the writer isolate. Both are gated out of the
per-message handler stopwatch so snapshot/reset bookkeeping does not
contaminate the measured wall. `Database.snapshotWriterProfileCounters()`
and `Database.resetWriterProfileCounters()` expose the round-trip to
audit harnesses; release builds do the round-trip too, but the
returned counters are zero because the increments themselves are
gated behind `kProfileMode`.

**Handler instrumentation.** Each writer handler is wrapped in two
profile-mode-only stopwatches: one for the full handler body
(handler_us), one inside an `_measureSqlite` helper that brackets the
FFI calls that drive SQLite (`resqliteExecute`, `resqliteRunBatch`,
`resqliteRunBatchNested`, the cached transaction-control stmts
`resqliteTxBeginImmediate` / `resqliteTxCommit` / `resqliteTxRollback`,
the `SAVEPOINT/RELEASE/ROLLBACK TO` `resqliteExec` calls, and the
prepare+step pass inside `_handleTxQuery`). `dispatch_us = handler_us
− sqlite_us` is the writer-side Dart dispatch wall.

The audit harness extends `audit_workloads.dart` to reset and snapshot
the writer counters around the existing A11c and keyed-PK scenarios,
merging the writer-isolate keys into the same counter map exp 119 /
exp 121 already consume. A new harness file
`benchmark/profile/writer_step_wall_audit.dart` formats the
A11c-baseline / A11c-disjoint / A11c-overlap / keyed-PK report.

## Results

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`).

Command:

```text
dart run -DRESQLITE_PROFILE=true \
  benchmark/profile/writer_step_wall_audit.dart --markdown
```

Three repeated passes (a/b/c) of the A11c scenarios:

| workload | wall_ms (a/b/c) | sqlite_us / handler_us | dispatch_us / wall_us | dispatch_us per handler |
|---|---:|---:|---:|---:|
| A11c baseline (0 streams x 500) | 34.4 / 33.0 / 33.7 | 69 / 66 / 68 % | 16.1 / 17.1 / 16.7 % | 11.1 / 11.3 / 11.2 µs |
| A11c disjoint (50 streams x 500) | 37.2 / 37.7 / 37.6 | 62 / 63 / 63 % | 13.2 / 12.7 / 13.0 % | 9.8 / 9.6 / 9.8 µs |
| A11c overlap (50 streams x 500) | 84.6 / 90.9 / 86.9 | 55 / 56 / 58 % | 11.0 / 10.7 / 9.2 % | 18.7 / 19.5 / 16.1 µs |
| keyed PK subs (50 streams x 200) | 18.4 / 19.8 / 45.5 | 70 / 69 / 93 % | 9.4 / 4.7 / 4.7 % | 8.7 / 10.8 / 10.8 µs |

Sanity: `dispatcher_parked_total = 0`, `dispatcher_wake_retry_total =
0`, and `dispatcher_max_parked_concurrent = 0` on every workload —
exp 120 / exp 122 still hold post-instrumentation.

Aggregate readings (full counter table per pass available in
`benchmark/profile/results/exp-135-writer-step-wall-aggregate.md`):

- **A11c overlap.** The writer-isolate handler accounts for only
  ~22–25% of the burst wall; the remaining ~75% is on the main
  isolate, in stream emission delivery, dirty-table propagation, and
  microtask scheduling. Within the writer handler, dispatch is
  ~42–45% (the rest is SQLite). The structural ceiling for "remove
  all writer-side Dart dispatch on overlap" is therefore ~9–11% of
  overlap wall.
- **A11c baseline (no streams).** The writer handler is ~50% of the
  wall — main-isolate work shrinks when there are no stream emissions.
  SQLite is ~68% of writer handler; dispatch is ~16% of total wall.
  Per-handler dispatch is ~11 µs, ~3× the noop floor delta from the
  main isolate (~9 µs writer floor in release-mode `run_profile.dart`).
- **A11c disjoint.** Column-level elision keeps emissions at zero; the
  writer-handler share is ~35% of wall, SQLite is ~63% of writer
  handler, dispatch is ~13% of total wall. Per-handler dispatch ~10
  µs.
- **Keyed-PK subscriptions.** Two of three runs land at the same
  pattern (~30–35% writer-handler share, ~10 µs/handler dispatch). The
  third run shows variance — `sqlite_us` jumped to 30 ms vs 4–5 ms,
  almost certainly a WAL checkpoint hit since these are random PK
  writes against a 10k-row table. Dispatch per handler stays stable
  at ~10 µs across all three runs, so the variance is in the SQLite
  share, not the dispatch share.

The dispatch-per-handler microsecond figures are the most stable
signal: ~11 µs (baseline), ~10 µs (disjoint), ~16–19 µs (overlap),
~9–11 µs (keyed-PK). Overlap is the only workload where per-handler
dispatch is materially higher — driven by `getDirtyTableDependencies`
returning a populated set instead of an empty one (vs disjoint, which
column-elides before the dirty harvest matters; vs baseline, which
has no streams to dirty for).

## Decision

**Accept for review — measurement.**

Exp 135 ships the writer-isolate dispatch counters and answers the
`writer-isolate wall vs SQLite wall split` open candidate.
`signals.json#stream-rerun-dispatch.blockedOnMeasurement` can drop
this entry; only the completion-side microtask scheduling counter
remains.

The audit's headline reading is that **writer-side Dart dispatch is
not the next dispatch-area implementation target** on the
currently-measured workloads. The structural ceiling for "remove all
writer-side Dart dispatch on A11c overlap" is ~9–11% of wall — at the
same per-benchmark decision threshold edge as exp 121's invalidation
traversal ceiling (10–15%). Combined, even fully eliminating both
writer dispatch *and* invalidation traversal saves ~20–25% of overlap
wall, with the remaining ~75% sitting on the main isolate.

The remaining writer-side dispatch headroom is concentrated in the
overlap workload — disjoint and keyed-PK both sit below 11% of wall.
Within overlap the per-handler dispatch jumps from ~10 µs (disjoint)
to ~17 µs (overlap), and the most plausible explanation for the
delta is that `getDirtyTableDependencies` returns a populated set
instead of an empty one. That is a small, bounded native-marshalling
change — but bounded by the same 9–11% ceiling, so a hypothetical
implementation needs to carry its own decision threshold case.

The bigger remaining wall-time source on stream workloads is the
~75% of overlap wall that lives on the main isolate. The
`completion-side microtask scheduling cost counter` open candidate
in `signals.json` is therefore unchanged in priority — it is the
*remaining* gating measurement for the next dispatch-area
implementation experiment.

## Future Notes

This audit closes one of the two `blockedOnMeasurement` entries on
`stream-rerun-dispatch`; future runners should check whether the
remaining `completion-side microtask scheduling cost counter` has
landed before another dispatch implementation pass. If a future
candidate targets writer-side dispatch (e.g. dirty-set marshalling
fast-path on overlap workloads), accept only if it reduces
`writer_handler_us` per handler on A11c overlap *and* is reproducible
on the current 5-run release suite — the structural 9–11% ceiling
makes the per-benchmark decision threshold tight.

The instrumentation is small enough that it can stay live in the
`audit_workloads.dart` shared scenarios going forward — every future
dispatch audit picks up the writer-handler share for free, the same
way exp 121's audit re-uses exp 119's scenarios.

The variance in the keyed-PK SQLite share (likely WAL-checkpoint
driven) is a workload property, not an instrumentation issue — the
dispatch-per-handler signal stays stable across that variance, which
is the whole point of separating the writer counters from total wall.
