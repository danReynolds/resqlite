# Experiment 197: True Group Commit Moonshot

**Date:** 2026-06-23T18:45:00-04:00
**Status:** Rejected
**Category:** Moonshot
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** focused `benchmark/experiments/writer_pipelining.dart`, order-flipped baseline/candidate pair
**Archive:** [`archive/exp-197`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-197)

## Problem

Exp 159 and exp 180 already attacked the standalone writer round-trip floor.
Exp 159 pipelined concurrent standalone writes through the writer port FIFO, and
exp 180 coalesced a burst into one `MultiExecuteRequest`. But exp 180
deliberately stopped short of true group commit: each statement still ran as an
independent SQLite autocommit so the public semantics stayed identical to N
separate `db.execute()` calls.

That leaves a large unresolved frontier. If the cost that remains on concurrent
standalone writes is mostly N SQLite transaction boundaries, then another
transport micro-optimization is the wrong target. The bolder question is whether
commit merging itself is the next ceiling.

## Hypothesis

Assumption challenged: standalone `db.execute()` calls must preserve independent
autocommit semantics even when the runtime has already coalesced them into one
writer request.

Prototype: change coalesced `MultiExecuteRequest` handling so the entire burst
shares one `BEGIN IMMEDIATE` / `COMMIT`, while each statement still reports its
own success or query error. The expected result is a large win on the concurrent
burst lane and no change to sequential writes or explicit transaction guardrails.

The risk budget is intentionally higher than an exploit experiment: this may not
be acceptable as hidden behavior. The point is to measure the ceiling and learn
whether a future explicit API or semantic mode is worth designing.

## Approach

The prototype changed only the writer-isolate `MultiExecuteRequest` handler:

- start one SQLite transaction for the coalesced group,
- run each statement with the existing `executeWrite` path,
- preserve per-statement `ResqliteException` outcomes where SQLite's default
  `ABORT` conflict behavior leaves the transaction usable,
- commit once at the end,
- attach the combined dirty-table/column dependencies to the last successful
  response so streams still invalidate after the burst.

The existing exp 180 tests passed unchanged, including correct per-call results,
per-statement failure isolation, and stream invalidation. The prototype was then
archived and reverted from the branch; no runtime code is kept in this PR.

## Results

Focused harness: `dart run benchmark/experiments/writer_pipelining.dart`.
Medians are from 7 rounds per side.

| Lane | Pass 1 baseline | Pass 1 candidate | Delta | Pass 2 baseline | Pass 2 candidate | Delta |
|---|---:|---:|---:|---:|---:|---:|
| sequential-awaited (2000 writes) | 61.577 ms | 63.715 ms | +3.5% | 66.486 ms | 65.836 ms | -1.0% |
| concurrent-burst (10 x 200 writes) | 49.999 ms | 5.931 ms | -88.1% | 44.919 ms | 5.717 ms | -87.3% |
| transaction-guardrail (50 tx x 10) | 8.545 ms | 7.475 ms | -12.5% | 7.678 ms | 7.686 ms | +0.1% |

The concurrent-burst result is the load-bearing finding: true commit merging
makes the focused burst roughly 8x faster in both pass orderings. Sequential
writes and explicit transaction guardrails are flat enough to treat as neutral.

Validation:

```bash
dart test test/write_coalescing_test.dart
dart run benchmark/experiments/writer_pipelining.dart  # candidate pass
dart run benchmark/experiments/writer_pipelining.dart  # baseline pass
```

## Decision

Rejected as a hidden default, but successful as a moonshot.

The performance ceiling is real and large. However, silently changing a
coalesced group of standalone writes from independent autocommits into one
transaction changes the contract in ways the existing API does not name:

- concurrent readers may observe none of the burst until the shared commit,
  whereas independent autocommits can become visible statement-by-statement,
- crash-window durability changes because all coalesced writes commit together,
- failure and constraint behavior depends on SQLite statement conflict policy
  more than the current per-call mental model suggests.

The right follow-up is not to hide this behind `db.execute()`. The direction is
worth reopening only as an explicit semantic surface: an opt-in group-commit
batch, a write-session API, or another named mode where callers knowingly trade
independent autocommit visibility for throughput.

## Future Notes

- Treat true commit merging as a design/API problem, not a writer micro-path
  cleanup. The ceiling is now measured.
- Use `benchmark/experiments/writer_pipelining.dart` as the fast focused gate
  for group-commit prototypes; the concurrent-burst row is sensitive enough.
- Any future implementation must state failure atomicity, read visibility, and
  crash-window semantics before chasing the 8x focused win.
