# Experiment 147: Writer SQLite wall split

**Date:** 2026-06-08
**Status:** In Review
**Direction:** `stream-rerun-dispatch`, `measurement-system`
**Benchmark Run:** None

## Problem

The `stream-rerun-dispatch` signal map still had two measurement blockers after
exp 120 / 121 / 122: completion-side scheduling cost and writer-isolate wall vs
SQLite wall on overlap workloads. Without that split, a future implementation
runner could still spend a pass tuning SQLite stepping, dirty-set harvest, or
writer request mechanics without knowing which part of the writer-side wall was
material.

The bounded question for this run was: *on the existing A11c and keyed-PK stream
workloads, how much of writer-side burst wall is the actual SQLite-facing write
call, how much is stream invalidation, and how much remains as writer/request
residual?*

## Hypothesis

SQLite stepping is not the dominant remaining stream-fanout cost on current
main. After exp 120/122 removed reader-pool admission parking and exp 121 sized
invalidation traversal, the remaining A11c overlap wall should mostly sit in
writer/request scheduling, dirty-set harvest, stream completion, and reply
coordination rather than inside the SQLite write call itself.

This measurement is useful if it makes the next dispatch-area decision sharper:
either future work should target SQLite/dirty-set internals because
`writer_sqlite_us` is large, or it should stop treating SQLite as the active
stream bottleneck because the residual budget dominates.

## Approach

Added a profile-only writer SQLite timing path:

- `ExecuteResponse`, `BatchResponse`, and transaction `QueryResponse` now carry
  `writerSqliteUs`.
- Writer handlers measure the SQLite-facing call with `Stopwatch` only when
  `kProfileMode` is true.
- `Database` and `Transaction` aggregate that per-request value into
  `ProfileCounters.writerSqliteUs` / `writerSqliteCount` on the main isolate.
- `TraceliteProfile.profileCounters(...)` maps the new counters so future
  trace-backed profile runs preserve them.

Then added
[`benchmark/profile/writer_sqlite_wall_audit.dart`](../benchmark/profile/writer_sqlite_wall_audit.dart),
which reuses the existing shared A11c/keyed-PK workload runners from
[`benchmark/profile/audit_workloads.dart`](../benchmark/profile/audit_workloads.dart).
The wall convention matches exp 121: subscriptions warm first, counters reset,
the stopwatch stops on the last write, and emission drains happen after wall
capture.

The aggregate report is committed at
[`benchmark/profile/results/exp-147-writer-sqlite-wall-aggregate.md`](../benchmark/profile/results/exp-147-writer-sqlite-wall-aggregate.md).

## Results

Command:

```text
dart run -DRESQLITE_PROFILE=true \
  benchmark/profile/writer_sqlite_wall_audit.dart --markdown
```

Single local pass on current main:

| workload | wall_ms | writer_sqlite_us | invalidate_us | residual_us | SQLite / wall | invalidation / wall | residual / wall |
|---|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 84.04 | 23,605 | 0 | 60,432 | 28.09% | 0.00% | 71.91% |
| A11c disjoint | 93.99 | 18,339 | 25,527 | 50,128 | 19.51% | 27.16% | 53.33% |
| A11c overlap | 223.20 | 26,469 | 41,638 | 155,095 | 11.86% | 18.65% | 69.49% |
| keyed PK subscriptions | 43.69 | 7,364 | 8,141 | 28,186 | 16.85% | 18.63% | 64.51% |

Per-write averages from this pass:

| workload | SQLite us/write | invalidation us/write | parked_total | max_parked |
|---|---:|---:|---:|---:|
| A11c baseline | 47.21 | 0.00 | 0 | 0 |
| A11c disjoint | 36.68 | 51.05 | 0 | 0 |
| A11c overlap | 52.94 | 83.28 | 0 | 0 |
| keyed PK subscriptions | 36.82 | 40.70 | 0 | 0 |

`parked_total` and `max_parked` stayed zero on every row, preserving the exp
120/122 admission result while this audit looked at a different slice.

## Decision

**Accept for review - measurement.**

The result consumes the writer-wall-vs-SQLite-wall blocker in `signals.json`.
On the active stream workloads, SQLite-facing write work is a minority of
writer-side burst wall: about 12% on A11c overlap and 17% on keyed-PK. Even
when invalidation is included, the residual local wall budget remains 65-69% on
the two overlap-shaped rows.

Future stream-dispatch implementation work should not start with SQLite-step
tuning for these workloads. The next useful measurement is completion-side
scheduling / reply coordination, because this run leaves the largest bucket as
residual writer/request wall rather than SQLite wall.

## Future Notes

The current counter deliberately excludes dirty-set harvest and reply send from
`writer_sqlite_us`. That is the right first split: it answers whether SQLite
stepping itself is the active target. If a future experiment wants to separate
dirty-set harvest from reply scheduling, add a narrower writer-side counter
instead of overloading `writer_sqlite_us`.

Run more than one pass before making a p99/tail claim. This experiment is a
directional blocker-clearing measurement, not a release regression gate.

## Validation

- `dart format lib/src/profile_counters.dart lib/src/tracelite_profile.dart lib/src/database.dart lib/src/transaction.dart lib/src/writer/writer.dart lib/src/writer/write_worker.dart benchmark/profile/audit_workloads.dart benchmark/profile/writer_sqlite_wall_audit.dart`
- `dart analyze lib/src/profile_counters.dart lib/src/tracelite_profile.dart lib/src/database.dart lib/src/transaction.dart lib/src/writer/writer.dart lib/src/writer/write_worker.dart benchmark/profile/audit_workloads.dart benchmark/profile/writer_sqlite_wall_audit.dart`
- `dart test test/database_test.dart test/transaction_test.dart`
- `dart run -DRESQLITE_PROFILE=true benchmark/profile/writer_sqlite_wall_audit.dart --markdown`
- `dart run benchmark/finalize_experiment.dart --experiment=experiments/147-writer-sqlite-wall-split.md`
