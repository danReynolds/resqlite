# Experiment 180: Cross-call write request batching (group commit)

**Date:** 2026-06-17
**Status:** Accepted
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** Release-suite A/B (5 repeats/side) + order-flipped confirmation + focused `writer_pipelining.dart`; see Results.

## Problem

Every standalone `db.execute()` is a full isolate round-trip: the main isolate
sends an `ExecuteRequest` to the writer isolate, the writer runs it, and a reply
comes back. Exp 147 split a write burst and found SQLite itself is only ~9.4% of
the writer-side wall, invalidation ~19%, and the **writer/request scheduling
residual ~72%** — i.e. for small writes the dominant cost is the plumbing of
getting each write to the isolate and back, not the database work.

Exp 159 attacked this structurally (persistent reply port, cached SendPort, sync
FIFO completion, release-the-lock-at-send pipelining) and landed −36% to −45% on
concurrent writes — but it still sends **N separate messages for N writes**, so
each write keeps paying its own round-trip. Exp 159's own Future Note named the
next lever:

> Further reduction needs request batching across calls (group commit) or a
> different transport (shared memory, when the Dart SDK allows it).

## Hypothesis

When standalone writes pile up faster than the writer round-trip can drain them
(concurrent bursts), coalescing them into **one** `MultiExecuteRequest` collapses
N round-trips toward ~1, removing most of the per-message residual for that
burst. "Group commit" here means batching the *transport*, not merging SQLite
commits — commits are only ~9% of wall, and merging them would also change
failure atomicity.

Acceptance criterion (set before running): the release-suite **Concurrent Single
Inserts** lane (exp 161's lane) moves outside the run-to-run noise band, with no
real regression on the sequential lane or transaction guardrails.

## Approach

- **Worker** ([write_worker.dart](../lib/src/writer/write_worker.dart)) — new
  `MultiExecuteRequest` (a list of `(sql, params)`) and `MultiExecuteResponse` (a
  per-statement list of `ExecuteResponse`-or-`ResqliteException`). The handler
  runs each statement as **its own autocommit** (the main-isolate mutex
  guarantees a coalesced group is only ever sent at `txDepth 0`), harvesting
  per-statement dirty tables — `resqlite_get_dirty_tables` resets the set on
  read, so outcome *i* carries exactly statement *i*'s modifications, identical
  to a standalone `ExecuteRequest`. A statement error is captured as that
  statement's outcome and the loop continues, so one caller's failure never
  affects another's.
- **Main isolate** ([writer.dart](../lib/src/writer/writer.dart)) — a buffer
  drained by `_pumpExecGroup` under **backpressure**: an idle pump sends the
  first write immediately as a plain `ExecuteRequest` (no added latency), then
  *awaits its reply*; writes that arrive during that await coalesce into one
  `MultiExecuteRequest` on the next pass. A tight sequential `await db.execute()`
  loop keeps exactly one write in flight, so it pays only the baseline's single
  lock hop and never batches. The lock is held only across each send (ordering
  the group against any concurrent transaction/batch via the worker FIFO) and
  released before the reply. Profile mode keeps the per-call send so Tracelite
  correlation ids stay intact.

An earlier microtask-coalescing variant (flush scheduled on every `execute()`)
also won on concurrency but taxed *every* write one microtask hop (~+3% on the
sequential lane); the backpressure trigger removes that tax — the coalescing
window is time the caller was already spending awaiting the in-flight reply.

**Semantics:** per-call success/failure is unchanged (each statement is its own
autocommit; no group transaction). The one behavior change: a buffered group
racing `db.close()` is now atomic — it either all flushes before close takes the
lock or all cleanly rejects with `ResqliteConnectionException`, never the old
lock-order-dependent partial outcome. It never hangs (the property the close
test guards). Covered by `test/write_coalescing_test.dart` (burst correctness,
per-statement error isolation, stream invalidation) and an updated
`transaction_test.dart` close-race test. Full suite: **306 passed**.

## Results

Release suite, 5 repeats/side. Concurrent inserts measured in **both run
orderings** (exp 177 drift control):

| Lane | Baseline-first (cand) | Candidate-first (cand) | Verdict |
|---|---|---|---|
| Concurrent Single Inserts (100) | 1.139 → 0.812 ms (**−26%**) | 1.350 → 0.912 ms (**−32%**) | win, reproduced |
| Single Inserts (100 sequential) | 1.558 → 1.451 ms (−7%) | 1.808 → 1.680 ms (−7%) | neutral/faster |
| Nested Transactions x50 (savepoints) | 0.801 → 0.964 ms (+20%) | 1.129 → 0.880 ms (**−22%**) | **drift (sign-flip)** |

The concurrent win reproduces in both orderings (−26% / −32%). The sequential
lane is neutral-to-faster both ways — the backpressure trigger leaves isolated
writes at baseline cost.

### The nested-tx flag is noise, three ways

A single-pass run flagged Nested Transactions x50 as +20%. It is not real:

1. **No mechanism.** Every timed `execute` in that lane is `inner.execute`
   (`Transaction.execute` → `executeInTransaction`, sent under the already-held
   lock). It never enters the coalescing pump — the changed code is dead during
   the measured region.
2. **Sign-flip across orderings** (+20% baseline-first, −22% candidate-first):
   the penalty follows whichever side runs second, the signature of
   time-correlated drift, not a code effect.
3. **Overlapping distributions.** The lane's own per-repeat spread is ~45%
   (baseline repeats 0.665–0.979 ms; candidate 0.789–0.990 ms) — the two medians
   differ by less than each group's internal spread. The sibling `depth=5`
   sub-lane was correctly auto-classified "within noise" (20.7% CV).

## Decision

**Accepted.** A reproduced −26% to −32% on the public Concurrent Single Inserts
lane (exp 161's writer-scheduling lane), with the sequential lane neutral and the
only flagged regression proven to be drift on an untouched code path. This is the
"cross-call request batching" lever exp 159 named, capturing the per-round-trip
residual (exp 147's ~72%) that pipelining alone left on the table, while keeping
per-call autocommit semantics intact.

## Future Notes

- This batches transport, not commits. Wrapping a group in one `BEGIN…COMMIT`
  (true fsync-merging group commit) is a possible follow-up, but it buys only the
  ~9% SQLite slice and changes failure atomicity (one statement's error would
  roll back the group) — not worth it without a workload where commit/fsync
  dominates.
- Backpressure coalesces a 100-write burst into ~2 round-trips (first goes alone,
  rest batch). A same-turn microtask pre-pass could get it to ~1, but only by
  re-taxing isolated writes — rejected here for that reason.
- The remaining transport floor is the shared-memory transport exp 159 named;
  still gated on Dart SDK support.
