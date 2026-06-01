# Experiment 135: Writer wall vs SQLite-call split

**Date:** 2026-06-01
**Status:** In Review
**Direction:** `stream-rerun-dispatch`, `measurement-system`
**Benchmark Run:** Profile harness only

## Problem

Exp 121 removed invalidation traversal as the clear next stream-dispatch
implementation target. On A11c overlap, `StreamEngine.onDependencyChanges`
was only 10-15% of writer-side burst wall, and the column-intersection subset
was smaller still. The remaining `signals.json` blocker was a split between
writer request wall and SQLite work:

- if SQLite stepping dominated the overlap workload, stream-dispatch work
  should not chase scheduler policy;
- if writer request wall was mostly outside the native write call, future work
  should look at response delivery, completion-side scheduling, or reader work.

Existing profile harnesses measured outer `db.execute()` wall and
`invalidate_us`, but not how much of the writer request was the native write
call versus isolate/message overhead.

## Hypothesis

A11c overlap wall is not dominated by SQLite stepping. The stream-added cost
should appear mostly in writer response delay and post-write completion/yield
work, while the native write-call proxy stays a minority of writer request
wall.

Accept this as a measurement experiment if:

- profile-mode counters separate writer request wall, native write-call wall,
  dirty-dependency drain, and invalidation wall;
- production response shapes remain unchanged when `RESQLITE_PROFILE=false`;
- the A11c and keyed-PK audit rows can decide whether the writer-vs-SQLite
  measurement blocker should stay in `signals.json`;
- focused tests and the profile harness pass.

## Approach

Added profile-only writer timing metadata:

```text
writer_request_us
writer_request_count
writer_sqlite_us
writer_dirty_drain_us
```

`Writer._request` measures main-isolate writer request/response wall after the
write mutex is already held. `WriteWorker` wraps successful responses in
`ProfiledWriterResponse` only when `kProfileMode` is true, carrying
writer-isolate timing for:

- the native write call (`executeWrite`, `executeBatchWrite`, transaction
  control SQL);
- dirty table/column dependency drain after the native write completes.

When `RESQLITE_PROFILE=false`, the worker sends the same response objects as
before. The profile wrapper is not part of the production message shape.

Added:

```text
benchmark/profile/writer_sqlite_wall_audit.dart
benchmark/profile/results/exp-135-writer-sqlite-wall-split.md
```

The harness reuses the shared A11c/keyed-PK workloads from
`benchmark/profile/audit_workloads.dart`. Each reported row uses one discarded
warmup pass and the median of three measured passes.

## Results

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/writer_sqlite_wall_audit.dart --markdown
```

Full aggregate:
[`benchmark/profile/results/exp-135-writer-sqlite-wall-split.md`](../benchmark/profile/results/exp-135-writer-sqlite-wall-split.md)

Median profile rows:

| workload | wall_ms | writer_request_ms | writer_sqlite_ms | dirty_drain_ms | invalidate_ms | writer_residual_ms | wall_residual_ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 59.53 | 38.43 | 18.31 | 5.66 | 0.00 | 14.46 | 21.10 |
| A11c disjoint | 36.98 | 20.23 | 10.51 | 0.52 | 4.31 | 9.20 | 12.44 |
| A11c overlap | 97.76 | 61.95 | 20.03 | 0.57 | 11.62 | 41.35 | 24.18 |
| keyed PK subscriptions | 71.00 | 62.97 | 41.70 | 0.51 | 4.84 | 20.77 | 3.18 |

Derived fractions:

| workload | writer_request / wall | sqlite / writer_request | dirty_drain / writer_request | invalidate / wall |
|---|---:|---:|---:|---:|
| A11c baseline | 64.55% | 47.65% | 14.73% | 0.00% |
| A11c disjoint | 54.71% | 51.94% | 2.58% | 11.65% |
| A11c overlap | 63.38% | 32.33% | 0.93% | 11.89% |
| keyed PK subscriptions | 88.70% | 66.21% | 0.81% | 6.82% |

The overlap row is the decision row. Native write work is 20.03 ms of
61.95 ms writer request wall, or 32.33%. Dirty drain is 0.57 ms. Synchronous
invalidation is 11.62 ms of the 97.76 ms outer wall. The largest buckets left
are writer request residual (41.35 ms) and wall residual (24.18 ms), which are
the response-delivery / Dart request handling bucket and post-write
yield/completion bucket respectively.

Compared with the no-stream baseline, A11c overlap adds ~38 ms outer wall.
Only ~1.7 ms of that is native write-call time. The stream-shaped delta is
mostly outside SQLite stepping.

## Decision

**Accept for review - measurement.**

The writer-vs-SQLite measurement blocker is resolved. On the current A11c
overlap workload, SQLite/native write work is not the active target. The
remaining stream-fanout wall sits in response-delivery and completion-side
scheduling pressure, with invalidation still present but already bounded by
exp 121.

`signals.json` removes the writer-isolate-vs-SQLite blocker and keeps the
completion-side scheduling counter as the remaining measurement gate before
another stream-dispatch implementation should be attempted.

## Future Notes

- Build a completion-side scheduling / response-delivery counter next. The
  current writer residual shows the pressure exists, but not which queue or
  callback family owns it.
- Use `writer_sqlite_us` and `writer_dirty_drain_us` as guardrails for future
  stream work. A claimed stream-dispatch win should not secretly be a native
  write regression.
- Do not pursue SQLite-step optimizations for A11c overlap unless a new
  workload makes `writer_sqlite_us` the dominant delta.
