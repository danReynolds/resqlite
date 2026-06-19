# Experiment 161: Concurrent standalone writes release coverage

**Date:** 2026-06-11
**Status:** In Review
**Direction:** `stream-rerun-dispatch`, `measurement-system`
**Benchmark Run:** none (release-suite coverage row only; the Single Inserts / Concurrent Single Inserts row pair it adds is exercised by downstream writer-scheduling experiments)

## Problem

Experiment 159 (writer request pipelining + persistent reply port) replaced
the per-request `RawReceivePort` with a single persistent reply port,
cached the worker `SendPort`, used `Completer.sync` for response
resolution, and — most importantly — released the writer lock at send
time on standalone writes so concurrent `db.execute(...)` calls pipeline
through the worker port's FIFO. The focused
`benchmark/experiments/writer_pipelining.dart` script measured a
`-36% to -45%` win on its 200 × 10 concurrent burst shape.

That focused script stays local. The release write suite still only
exercised **sequential** standalone writes (Single Inserts: 100
`await peer.execute(...)` calls in a serial loop). With no public
benchmark line that issues writes concurrently, exp 159's win — and any
future writer-scheduling change that depends on the same pipelining
shape — would land invisible on the release dashboard.

The pattern matches experiment 116, which promoted the wide batch
parameter shape from a focused harness into release coverage so future
parameter-encoding regressions would be visible without the focused
script.

## Hypothesis

Adding a single concurrent standalone writes row to `Write Performance`
will:

1. Make exp 159's send-gated writer-lock pipelining win visible on the
   public benchmark path on every release run.
2. Expose a sequential-vs-concurrent contrast for the **same 100-row
   write workload** as Single Inserts, so future writer-scheduling
   experiments have a paired baseline.
3. Add no production code change. The peer interface already supports
   `Future<void> execute(...)`; the new row only wraps it in
   `Future.wait` over a fixed burst size.

Accept if the workload runs across all four peers through the existing
`BenchmarkPeer.execute` path, uses identical schema and parameter values
to the adjacent Single Inserts row, and the resqlite concurrent median
is materially below the sequential median (otherwise the pipelining the
benchmark is meant to expose isn't engaging).

## Approach

`benchmark/suites/writes.dart` adds one new subsection right after
`Single Inserts`:

```text
Concurrent Single Inserts (100 concurrent)
```

Shape:

- 100 standalone `db.execute(...)` calls per iteration.
- Issued as a single `Future.wait` over the burst (no per-call
  `await`).
- Same schema, same insert SQL, same parameter shapes as `Single
  Inserts` (`['item_$i', i * 1.5]`).
- Same `defaultWarmup` / `defaultIterations` policy.
- `DELETE FROM t` between iterations to keep table size bounded.

No production source files are touched. The new constant
`_concurrentBurstSize = 100` and the section docstring explain why
the burst stays at 100 (matches the Single Inserts row count exactly
so the sequential and concurrent rows are directly comparable, and
fits the release-suite iteration budget).

The class-level docstring now lists seven sections (the concurrent row
plus the existing six the comment had been tracking before exp 111's
nested-tx section landed without doc updates).

## Results

Command (in this worktree, paired smoke runs):

```text
dart run benchmark/suites/writes.dart
```

Two paired runs (build cache warm, same machine, back-to-back):

| Subsection | resqlite wall med (run 1) | resqlite wall med (run 2) |
|---|---:|---:|
| Single Inserts (100 sequential) | 2.818 ms | 2.935 ms |
| Concurrent Single Inserts (100 concurrent) | **1.084 ms** | **1.218 ms** |

Concurrent-vs-sequential delta on the resqlite row: **−61% to −58%**
(`1.084 / 2.818` and `1.218 / 2.935`). The reduction lands in the same
band as exp 159's focused script (−36% to −45%) — slightly larger here
because the release row is a single 100-write burst (deeper
pipelining-to-overhead ratio) rather than ten 200-write bursts. The
absolute resqlite concurrent median is around 1 ms, which is the
expected scale for 100 pipelined writes through one writer worker.

Full subsection (run 1):

| Library | Wall med | Wall p90 |
|---|---:|---:|
| resqlite concurrent execute() | 1.084 ms | 1.580 ms |
| sqlite3 concurrent execute() | 0.966 ms | 1.607 ms |
| sqlite_async concurrent execute() | 3.422 ms | 4.549 ms |
| drift concurrent execute() | 2.192 ms | 3.231 ms |

The sqlite3 (sync) row drops from 1.538 ms (sequential) to 0.966 ms
(concurrent) — a side effect of `Future.wait` skipping the per-call
`await` microtask round-trip the sequential row spends; the sync peer
cannot actually pipeline, so this is the "no isolate boundary, no
queue policy" floor.

Adjacent sections (Single Inserts, Batch Insert × 3, Wide Batch
Insert, Interactive Transaction, Batched Write Inside Transaction,
Transaction Read, Nested Transactions) all execute normally in the
same run.

Validation:

```text
dart pub get
dart run build_runner build
dart analyze benchmark/suites/writes.dart  # No issues found!
dart run benchmark/suites/writes.dart       # full suite completes
```

## Decision

**In Review — measurement coverage.**

This experiment intentionally adds no production optimization. Its
value is that the release suite now tracks the exact workload
dimension experiment 159's send-gated writer-lock pipelining was
designed to improve. The concurrent and sequential rows share schema,
row count, and parameter shapes, so the sequential-vs-concurrent
delta is directly readable on every release run.

Two named decisions this row unlocks for future runners:

- **Confirm exp 159's win publicly.** The next release-suite A/B that
  rebuilds against pre-159 baseline can show the concurrent row
  moving while the sequential row stays neutral; today only the
  focused script can demonstrate this.
- **Gate future writer-scheduling experiments.** Any later attempt at
  the stream-rerun-dispatch direction's residual writer/request wall
  (exp 147 left this as the largest bucket on A11c overlap) needs a
  release lane that issues concurrent writes through the writer port
  FIFO. Without such a row, those candidates would land "neutral on
  release" the way exp 159 nearly did.

## Future Notes

- Do not add a sweep of burst sizes here. One row is enough to keep
  the public dashboard honest; focused sweeps stay in
  `benchmark/experiments/writer_pipelining.dart`.
- If a future writer-scheduling change moves the sequential row but
  not the concurrent row (or vice versa), that's a signal worth
  recording, not a calibration problem with this row.
- The sqlite3 sync peer's concurrent execute is included as the
  "no isolate boundary, no queue policy" floor. Future readers
  should not interpret its concurrent-vs-sequential delta as
  evidence of pipelining; it isn't.
