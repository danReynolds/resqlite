# Experiment 249: invalidation-batched stream rerun dispatch (moonshot)

**Date:** 2026-07-26
**Status:** Rejected
**Direction:** `stream-rerun-dispatch`
**Category:** Moonshot
**Benchmark Run:** focused
**Archive:** [`archive/exp-249`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-249)

## Problem

Reactive streams are resqlite's primary use case, and the reactive fan-out
shape is unforgiving: because stream invalidation is table/column-level (exp 134
proved row-level precision wins but rejected its SQL-text recognizer), a single
`UPDATE items SET value = ?` dirties *every* stream that projects `value`. In
the `high_cardinality_fanout` workload that is 100 streams re-queried per write,
of which one has actually changed and 99 re-hash to the same result and suppress
their emission.

Each of those reruns is dispatched as its own isolate message to a reader
worker via `ReaderPool.selectIfChanged` → one `SelectIfChangedRequest`. Exp 136
measured the reader worker port handler at 28.57% of A11c-overlap wall (~18 µs
per call across 4,228 calls/burst), and the reader pool clamps to 4 workers
(`(numberOfProcessors - 1).clamp(2, 4)`), so 100 reruns drain in ~25 waves of
per-message round trips. The message-passing overhead — not the native hash
check — looked like removable cost.

## Hypothesis

**Assumption challenged:** *each dirtied stream must re-query via its own reader
round-trip.* A single write's dirtied set is a natural batch: same trigger,
consumed together, dominated by unchanged members that transfer nothing. Packing
those reruns into one message per worker should cut the per-rerun message count
25:1 (100 reruns → 4 messages) for free, because each reader worker owns one
SQLite connection and can only step one query at a time — the members run
serially on the worker either way, so batching removes only isolate-scheduling
overhead, not any parallelism.

The bet: fan-out rerun processing gets cheaper, and — since the reruns that
matter (the changed ones) are a tiny minority whose batch-mates are cheap
unchanged hashes — user-visible emission latency stays flat or improves.

## Approach

Added, all internal (no public API change):

- `SelectIfChangedBatchRequest` + a worker loop in `read_worker.dart` that runs N
  `executeQueryIfChanged` members serially on the reader connection and returns
  one reply of per-member `(rows?, hash, rowCount, error?)`. Unchanged members
  carry a null `rows` (nothing to transfer); errors are isolated per member.
- `ReaderPool.selectBatchIfChanged` dispatching that request to one worker.
- A batched `StreamEngine._flushQueue`: below pool size, dispatch each rerun
  individually (byte-identical to the pre-249 path, so the common 1–few-stream
  case is untouched); above pool size, split the dirty set into one batched
  message per available worker via `_requeryBatch`, which mirrors `_requery`'s
  in-flight / re-dirty / hash-baseline / emit bookkeeping.
- A **cost gate** (`_batchRowCountCap = 256`): a batched reply is indivisible,
  so a member expensive to re-hash (a large result) would delay delivery of the
  small members sharing its message. Streams whose `lastRowCount` exceeds the
  cap (or have no baseline yet) are dispatched individually instead. This uses
  the private per-entry cost signal exp 239 explicitly named as its reopen
  condition ("reopen only with a reliable private cost signal").

## Results

Two measurement methods were used, and they disagreed — which is itself the most
important result.

**Method A — in-process A/B toggle** (a temporary `batchRerunsEnabled` static
flipped between the two dispatch paths inside one long-lived process; order-
flipped; classified by `ab_drift_check.dart`). This reported an apparent win:

| scenario | pass 1 Δ | pass 2 Δ | verdict |
|---|---:|---:|---|
| homogeneous emit latency (100 small partitions) | −25.8% | −27.9% | REPRODUCED |
| heterogeneous emit latency (10 large + 90 small) | +14.8% | +0.8% | neutral |

**Method B — cross-worktree A/B** (baseline `origin/main` vs candidate, two
separate binaries, alternated over 3 rounds, warm/sustained-burst regime). This
reversed the sign entirely — the batched path is **slower across the board**:

| scenario (median of 3 rounds) | baseline | candidate | Δ |
|---|---:|---:|---:|
| homogeneous emit latency p50 (ms) | 0.66 | 0.81 | **+22%** |
| homogeneous emit latency p95 (ms) | 0.91 | 1.44 | **+59%** |
| heterogeneous emit latency p50 (ms) | 0.90 | 1.50 | **+66%** |
| heterogeneous emit latency p95 (ms) | 1.38 | 2.09 | **+52%** |

The cross-worktree numbers are consistent across all three rounds and both
scenarios, and they are the trustworthy comparison: separate processes share no
warm JIT, isolate, or reader-pool state between the two arms. The in-process
toggle result was an artifact (see *Why It Was Rejected*).

## Why It Was Rejected

**A batched reply is indivisible, and that penalty falls on exactly the result
that matters.** For a single write that dirties 100 streams with one change, the
changed stream lands in a batch of ~25 cheap small partitions; its fresh result
is only delivered when the *whole* batch finishes, so it waits behind ~24 other
re-hashes before its message is sent. The per-message overhead the batch saves
is smaller than the batch-completion wait it adds for the one rerun a subscriber
is waiting on. The cost gate keeps a *large* partition off that critical path,
but the common fan-out case is many *small* partitions, and the target still
waits for its cheap batch-mates. This is the same trade exp 148 rejected
(reduced completion callbacks, regressed measured elapsed) and exp 239 rejected
(members share an indivisible reply) — reproduced a third time for stream
reruns.

**The in-process toggle manufactured a false win.** Flipping a hot-path branch
inside one warm, long-lived process — with both arms sharing JIT/inline-cache
state, a still-spinning main isolate (the drain probe busy-polled every 1 ms),
and warm reader connections — produced a −27% delta that `ab_drift_check`
classified REPRODUCED across an order flip, yet a clean two-binary comparison
showed a +22% to +66% regression. Order-flipping controlled for cross-*phase*
ordering but not for the shared warm state the toggle rode on. The lesson (now
in `JOURNAL.md`): **for dispatch/scheduling changes, an in-process A/B toggle is
untrustworthy; use a cross-worktree or two-root comparison.**

## Decision

**Rejected.** Invalidation-grouped rerun batching regresses single-write
emission latency (the user-visible metric for reactive streams) by 20–65% in
clean cross-worktree measurement, because the batched reply delays the one
changed result behind its unchanged batch-mates. Message-count amortization is
real but is the wrong lever: this workload is latency-bound, not throughput-
bound. The runtime prototype is reverted; the mechanism is preserved at
`archive/exp-249`.

**Would reopen if** a genuinely *throughput-bound* stream workload emerges —
one where total rerun drain under a sustained multi-write backlog dominates and
per-emission latency is provably not the binding constraint (e.g. batch-oriented
materialized-view refresh rather than interactive list views). Even then the
batch would need to preserve independent completion, e.g. the worker streaming
each member's result back as it finishes rather than one reply per batch — which
removes most of the message-amortization the idea rests on.

## Future Notes

`benchmark/experiments/stream_rerun_latency.dart` is kept as the durable
single-write fan-out emission-latency gate (homogeneous + heterogeneous
partitions; A/B it across baseline/candidate worktrees). Any future stream-
dispatch change should confirm it does not regress this metric — it is the lane
that exposed this rejection and would have hidden it under an emission-count or
total-drain summary (the existing `high_cardinality_fanout` settle returns after
a fixed quiet window and never waits for suppressed reruns to drain).
