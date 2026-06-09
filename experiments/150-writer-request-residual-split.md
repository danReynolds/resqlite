# Experiment 150: Writer request residual split

**Date:** 2026-06-09
**Status:** In Review
**Direction:** `stream-rerun-dispatch`, `measurement-system`
**Benchmark Run:** None

## Problem

Exp 147 split stream write-loop wall into SQLite-facing writer calls,
stream invalidation, and a large residual writer/request bucket. Exp 148 then
tested the obvious completion-side implementation follow-up, reader-reply
batching, and rejected it: the candidate reduced completion callback counters
but failed the formal Tracelite measured-elapsed gate.

Before trying another stream implementation, the remaining residual bucket
needed a narrower split. The active question was whether the next target should
be dirty-set harvest, writer reply/request scheduling, main-isolate request
resolution, or drain/write-loop coordination.

## Hypothesis

Dirty-set harvest is not the dominant residual cost on current A11c and
keyed-PK workloads. The larger buckets should be request transfer/resolution
and write-loop/drain coordination. If true, future implementation work should
not start by optimizing `getDirtyTableDependencies`; it should either produce a
measured-elapsed win by changing request/coordination behavior or add an even
narrower queueing trace.

## Approach

Added profile-only counters that preserve release behavior:

- `writer_request_us` / `writer_request_count`: main-isolate writer request
  round trip, from `SendPort.send` to reply handler.
- `writer_handler_us` / `writer_handler_count`: writer-isolate handler wall,
  stopping just before the response is sent.
- `writer_dirty_harvest_us` / `writer_dirty_harvest_count`: dirty table/column
  harvest after successful writes or outer commits.

The existing `writer_sqlite_us`, invalidation, dispatcher, and completion
counters stay unchanged. The new counters are also mapped through
`TraceliteProfile.profileCounters(...)`.

Added
[`benchmark/profile/writer_request_residual_audit.dart`](../benchmark/profile/writer_request_residual_audit.dart),
which reuses the shared A11c/keyed-PK workload runners from
[`benchmark/profile/audit_workloads.dart`](../benchmark/profile/audit_workloads.dart).
The wall convention matches exp 121/136/147: `wall_ms` stops on the last write;
`drain_ms` is the post-burst quiet-window drain; writer counters use the
burst-end snapshot; completion counters use the post-drain snapshot.

The aggregate report is committed at
[`benchmark/profile/results/exp-150-writer-request-residual-aggregate.md`](../benchmark/profile/results/exp-150-writer-request-residual-aggregate.md).

## Results

Command:

```text
dart run -DRESQLITE_PROFILE=true \
  benchmark/profile/writer_request_residual_audit.dart --markdown
```

Primary pass:

| workload | wall_ms | request / wall | handler / wall | SQLite / wall | dirty harvest / wall | transfer+resolution / wall | invalidation / wall | coordination / wall | completion / total |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 35.14 | 61.42% | 44.19% | 32.94% | 9.74% | 17.23% | 0.00% | 38.58% | 0.00% |
| A11c disjoint | 39.30 | 46.67% | 28.54% | 20.63% | 6.68% | 18.14% | 20.19% | 33.14% | 0.00% |
| A11c overlap | 89.91 | 45.39% | 18.21% | 13.02% | 4.70% | 27.17% | 15.41% | 39.20% | 20.63% |
| keyed PK subscriptions | 24.47 | 72.29% | 27.12% | 23.58% | 2.83% | 45.18% | 13.46% | 14.25% | 3.92% |

Repeat pass, same branch:

| workload | wall_ms | request / wall | handler / wall | SQLite / wall | dirty harvest / wall | transfer+resolution / wall | invalidation / wall | coordination / wall | completion / total |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 33.04 | 60.82% | 43.30% | 31.83% | 10.04% | 17.53% | 0.00% | 39.18% | 0.00% |
| A11c disjoint | 37.84 | 45.77% | 29.61% | 22.25% | 6.28% | 16.16% | 21.97% | 32.27% | 0.00% |
| A11c overlap | 87.70 | 45.69% | 19.02% | 14.19% | 4.25% | 26.67% | 15.69% | 38.62% | 21.19% |
| keyed PK subscriptions | 21.75 | 68.65% | 25.33% | 22.47% | 2.12% | 43.32% | 15.91% | 15.44% | 2.03% |

Per-event costs from the primary pass:

| workload | request_us/op | handler_us/op | dirty_harvest_us/op | completion_us/callback |
|---|---:|---:|---:|---:|
| A11c baseline | 43.17 | 31.06 | 6.85 | 0.00 |
| A11c disjoint | 36.68 | 22.43 | 5.25 | 0.00 |
| A11c overlap | 81.62 | 32.75 | 8.45 | 10.54 |
| keyed PK subscriptions | 88.46 | 33.18 | 3.46 | 7.91 |

`dispatcher_parked_total` and `dispatcher_max_parked_concurrent` stayed zero
on every row, preserving the exp 120/122 admission result while this audit
looked at a different slice.

## Decision

**Accept for review - measurement.**

The dirty harvest path is too small to be the next standalone implementation
target: 4.25-4.70% of A11c overlap wall and 2.12-2.83% of keyed-PK wall across the
two passes. Writer-local non-SQLite/non-harvest handler work is also tiny:
roughly 0.5 ms per A11c burst.

The larger buckets are:

- transfer/request resolution: ~26-27% of A11c overlap wall and ~43-44% of
  keyed-PK wall;
- write-loop coordination: ~39% of A11c overlap wall, including the deliberate
  microtask yields between writes in the audit harness;
- completion after drain: ~20% of A11c total wall, but exp 148 already showed
  that plain reader-reply batching does not turn that counter reduction into a
  measured-elapsed win.

Future stream-dispatch work should not start with SQLite-step tuning or
dirty-set harvest. The next implementation attempt needs direct
measured-elapsed evidence around request/coordination behavior, or a narrower
queueing trace that splits writer queue wait, reply send/copy, main-isolate
request resolution, and the audit's deliberate inter-write yields.

## Future Notes

- If a future candidate targets dirty-set harvest, require a new workload where
  `writer_dirty_harvest_us / wall_us` is materially larger than the A11c/keyed
  rows measured here.
- `transfer_resolution_us` is still a composite bucket. It includes request
  transfer, writer queueing, reply send/copy, and main-isolate response
  scheduling. Split that bucket before proposing another protocol change.
- `coordination_us` is partly a workload convention in A11c because the audit
  yields between writes to defeat invalidation coalescing. A candidate that
  claims to reduce coordination should be evaluated in the integrated
  Tracelite stream-dispatch suite, not just this profile harness.

## Validation

- `dart pub get`
- `dart format lib/src/profile_counters.dart lib/src/tracelite_profile.dart lib/src/database.dart lib/src/transaction.dart lib/src/writer/writer.dart lib/src/writer/write_worker.dart benchmark/profile/audit_workloads.dart benchmark/profile/writer_request_residual_audit.dart test/profile_counters_test.dart`
- `dart analyze lib/src/profile_counters.dart lib/src/tracelite_profile.dart lib/src/database.dart lib/src/transaction.dart lib/src/writer/writer.dart lib/src/writer/write_worker.dart benchmark/profile/audit_workloads.dart benchmark/profile/writer_request_residual_audit.dart test/profile_counters_test.dart`
- `dart test test/profile_counters_test.dart`
- `dart run -DRESQLITE_PROFILE=true benchmark/profile/writer_request_residual_audit.dart --markdown`
- `dart run -DRESQLITE_PROFILE=true benchmark/profile/writer_request_residual_audit.dart`
