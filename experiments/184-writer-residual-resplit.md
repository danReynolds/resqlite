# Experiment 184: Writer residual re-split (post-159/180)

**Date:** 2026-06-17
**Status:** Accepted
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** none — profile-mode audit only (`writer_sqlite_wall_audit.dart`); no release-suite metric.

## Problem

Exp 147's writer-burst breakdown (SQLite 9.4% / invalidation 18.8% / residual
71.8% on A11c overlap) is what *directed* exp 159 (pipelining) and exp 180
(group commit). Both have since landed. Before picking the next writer target,
the breakdown needed re-measuring — coalescing could have shifted which bucket
now dominates.

## What We Built

Re-ran exp 147's harness (`benchmark/profile/writer_sqlite_wall_audit.dart`,
`-DRESQLITE_PROFILE=true`) on current `main`. No new code — this is a
measurement to re-rank candidates.

## Results

| workload | SQLite/wall | invalidation/wall | residual/wall | exp 147 residual |
|---|---:|---:|---:|---:|
| A11c baseline (0 streams) | 38.0% | 0.0% | 62.0% | — |
| A11c disjoint | 23.7% | 21.6% | 54.7% | ~54.7% |
| A11c overlap | 13.6% | 16.0% | 70.3% | 71.8% |
| keyed PK | 23.7% | 14.4% | 61.9% | 63.3% |

The breakdown is essentially unchanged from exp 147. The audit issues writes
**sequentially** (`audit_workloads.dart:167`), and exp 180 coalesces only
*concurrent* bursts — so the sequential writer path it measures is, correctly,
unmoved. (exp 180's win is on the concurrent release lane, validated separately.)
Full numbers: `benchmark/profile/results/exp-184-writer-residual-resplit-aggregate.md`.

## Decision

**Accepted (measurement).** Retire writer-residual micro-optimization from the
active candidate list. The residual (55–70%) is the per-write isolate round-trip,
which for sequential writes is the SDK-gated floor — the only lever left there is
a shared-memory transport. The cleanly-attackable buckets are smaller and either
spoken for or hard:

- **Invalidation / re-query precision (14–22%)** — the real lever (exp 134
  halved keyed-PK wall), but the traversal is at its floor (exp 121) and the
  re-query-count reduction is what the in-flight **exp 160** (incremental view
  maintenance, [#155](https://github.com/danReynolds/resqlite/pull/155))
  implements. Don't duplicate it.
- **Dirty-table harvest (~4–6%, exp 182)** — small; exp 182 showed gating it
  regresses the with-streams path.
- **SQLite (14–38%)** — sqlite3mc compile/config, mined (exp 016/044/144).

Next reactive-engine win = exp 160; next sequential-write reduction needs the
shared-memory transport when the Dart SDK allows it.
