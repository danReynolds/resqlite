# Experiment 147: Writer SQLite wall split

**Date:** 2026-06-08
**Status:** Accepted
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

Fresh current-branch pass after merging exp136:

| workload | wall_ms | writer_sqlite_us | invalidate_us | residual_us | SQLite / wall | invalidation / wall | residual / wall |
|---|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 86.88 | 23,071 | 0 | 63,810 | 26.55% | 0.00% | 73.45% |
| A11c disjoint | 92.78 | 17,738 | 23,833 | 51,205 | 19.12% | 25.69% | 55.19% |
| A11c overlap | 166.75 | 15,678 | 31,389 | 119,679 | 9.40% | 18.82% | 71.77% |
| keyed PK subscriptions | 36.95 | 6,679 | 6,897 | 23,370 | 18.08% | 18.67% | 63.25% |

Per-write averages from this pass:

| workload | SQLite us/write | invalidation us/write | parked_total | max_parked |
|---|---:|---:|---:|---:|
| A11c baseline | 46.14 | 0.00 | 0 | 0 |
| A11c disjoint | 35.48 | 47.67 | 0 | 0 |
| A11c overlap | 31.36 | 62.78 | 0 | 0 |
| keyed PK subscriptions | 33.40 | 34.48 | 0 | 0 |

`parked_total` and `max_parked` stayed zero on every row, preserving the exp
120/122 admission result while this audit looked at a different slice.

## Decision

**Accept for review - measurement.**

The result consumes the writer-wall-vs-SQLite-wall blocker in `signals.json`.
On the active stream workloads, SQLite-facing write work is a minority of
writer-side burst wall: about 9% on A11c overlap and 18% on keyed-PK. Even
when invalidation is included, the residual local wall budget remains 63-72% on
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
