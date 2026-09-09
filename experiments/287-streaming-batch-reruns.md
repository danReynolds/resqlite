# Experiment 287: the reply exp 249 never sent

**Date:** 2026-09-09
**Status:** Rejected
**Category:** Moonshot
**Direction:** `stream-rerun-dispatch`, `result-transfer-shape`
**Benchmark Run:** none — the runtime prototype is reverted and no code ships in
  `lib/`, `native/` or `hook/`. The decision evidence is four order-flipped
  separate-binary drain passes with a zero-ceiling control, eight latency-gate
  passes across two collections, and a 120-trial distribution read, in
  [`benchmark/results/2026-09-09T11-30-00Z-exp287-streaming-batch-reruns.md`](../benchmark/results/2026-09-09T11-30-00Z-exp287-streaming-batch-reruns.md)
**Archive:** [`archive/exp-287`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-287)

## Problem

A write that touches a column many streams project dirties all of them at once.
Stream invalidation is table- and column-level — [exp 134](134-keyed-pk-dirty-elision.md)
proved row-level precision wins and its SQL-text recognizer was rejected — so
`UPDATE items SET value = ?` re-queries every stream that reads `value`. In the
fan-out shape that is a hundred reruns per write, and each one is dispatched as
its own message to a reader worker, executed, and replied to individually.

[Exp 249](249-invalidation-batched-rerun.md) packed those reruns into one
message per worker and was rejected: cross-worktree, single-write emission
latency got 22% worse on homogeneous partitions and 66% worse on heterogeneous
ones. Its decision names the cause precisely. *A batched reply is indivisible.*
The one stream a subscriber is waiting on lands in a batch of twenty-five, and
its fresh result is only delivered when the whole batch finishes — so it waits
behind two dozen re-hashes it has nothing to do with. That is the same trade
[exp 148](148-reader-reply-batching.md) and [exp 239](239-select-overflow-batching.md)
were rejected for.

Exp 249's decision also names the fix, in one clause, and dismisses it in the
same breath:

> Even then the batch would need to preserve independent completion, e.g. the
> worker streaming each member's result back as it finishes rather than one
> reply per batch — **which removes most of the message-amortization the idea
> rests on.**

That clause is the thing this experiment is about, and by 2026 it is checkable
rather than arguable.

## Hypothesis

**Assumption challenged: that batching a group of isolate requests and batching
their replies are the same decision.** They are not, and exp 249's own
arithmetic says its rejection came entirely from the second one.

Take exp 249's latency scenario: one write dirties 100 streams, one changes.
Unbatched, with four workers pulling a FIFO, the changed stream's rerun begins
after roughly `p/4` predecessors. Batched into four chunks of twenty-five, it
begins after roughly `p mod 25`. Those are the same wait. Nothing exp 249
measured was scheduling. What it measured was the gap between a member
finishing and its batch finishing — a term that exists only because the reply
was indivisible.

And the dismissal is refuted by measurements taken after exp 249 ran. The
amortization does not live in the reply:

- [Exp 284](284-write-hop-decomposition.md) priced a message to an isolate
  *parked* waiting for it at 0.737 µs against 0.445 µs to one already draining
  a backlog, and found the woken side then runs cold — 1.8 µs, refined by
  [exp 285](285-worker-keep-warm.md) to 0.63–0.88 µs of recoverable thread
  residency. A batch wakes its worker once, not N times.
- [Exp 136](136-completion-microtask-counter.md) measured the main-isolate
  reader port handler at ~18 µs per completion, 28.57% of A11c-overlap wall.
- [Exp 283](283-stream-rerun-one-pass.md)'s census found 44% of the fan-out
  lane's reruns and 99.7% of the keyed-PK lane's are *unchanged*. An unchanged
  member's entire reply says "the hash still matches" — information the main
  isolate can equally well read from the member's silence.

So a batch whose changed members reply individually and whose unchanged members
reply not at all keeps every one of those savings and gives up only the one
term that hurt. If exp 249's rejection was really about reply indivisibility,
the sign should flip; if the fan-out drain is bound by per-rerun dispatch, it
should fall.

**Predeclared rule**, written before any code. The gate is
`stream_rerun_latency.dart` — the harness exp 249 was killed by and which was
kept for exactly this purpose — and it must be neutral or better. The win
condition is exp 283's drain sentinel reproducing ≥5% better in both orders
with the zero-ceiling control inside the noise. If the gate passes and drain is
flat, the finding is that per-rerun message overhead is not the fan-out
constraint — which answers exp 283's open question about whether the reader
pool is the constraint at all.

## Approach

The batching *policy* is held byte-identical to exp 249 — dispatch individually
below pool size, otherwise one group per free worker, 64-member cap, 256-row
cost gate — so the reply protocol is the only variable under test.

`SelectIfChangedStreamingBatchRequest` carries N members. The worker runs them
serially on its one connection (it has no other option) and, for each member
whose hash moved, sends a `BatchRerunPartial` immediately. Unchanged members
send nothing. A terminator reply carries per-member errors and releases the
worker. `_WorkerSlot` grew an optional partial sink: a partial neither resolves
the request's completer nor frees the slot, because the worker is still
stepping the rest of its batch. Batched replies never take the sacrifice
(`Isolate.exit`) path — a worker that exits cannot finish its batch — which is
what the row-count cost gate is for.

One deviation from exp 249 was forced by the first collection and is reported
as such in §3 below: exp 249's flush dispatched the un-batchable large entries
scalar *first*, consuming every free worker before the cheap majority was
batched. Since the dirty set is enumerated in stream-registration order, a
handful of large partitions registered early starved the other ninety. The
candidate splits the free workers between the two classes instead.

## Results

Full tables in the [receipt](../benchmark/results/2026-09-09T11-30-00Z-exp287-streaming-batch-reruns.md).

### 1. The mechanism does what it was built to do

A temporary counter, over one whole 26-burst fan-out collection:

| | |
|---|---:|
| rerun members dispatched | 10,400 |
| batched messages carrying them | 432 |
| members that changed (one reply each) | 2,495 (24.0%) |
| members that sent no reply at all | 7,905 (76.0%) |

Ten thousand four hundred request sends became four hundred and thirty-two, and
three quarters of the replies stopped existing. Whatever per-rerun dispatch
costs, this candidate is not paying it.

### 2. And the backlog does not notice

Exp 283's drain sentinel — a stream on a partition the burst never touches,
armed after the burst is issued, so its emission prices the whole backlog
rather than a prefix of it:

| pass | first | baseline | candidate | Δ |
|---|---|---:|---:|---:|
| 1 | B | 5.517 ms | 6.132 ms | +11.1% |
| 2 | C | 6.302 ms | 6.115 ms | −3.0% |
| 3 | B | 5.949 ms | 6.168 ms | +3.7% |
| 4 | C | 6.364 ms | 6.206 ms | −2.5% |
| pooled | | 6.033 ms | 6.155 ms | **+2.0%** |

The sign flips with arm order. The zero-ceiling control — the identical write
burst with nothing subscribed — reads −5.2% and +0.7%, so the collection's own
floor is about ±5% and every fan-out delta sits inside it.

**This is the run's finding.** A 24:1 cut in request messages and a 4:1 cut in
replies is worth nothing on fan-out drain. Exp 283 left open whether the reader
pool is the fan-out constraint at all; for the message half of it, the answer
is no, and the bound is tight because the intervention was so large. The
control also sizes what is left: the write burst alone is 1.75 ms of the
6.03 ms, and the remainder is the readers' own SQLite work plus something
serial that removing 96% of the messaging does not touch.

### 3. Exp 249's diagnosis of exp 249 was right

The gate, four order-flipped passes per collection, Δ candidate against
baseline within each pass:

| metric | exp 249 | exp 287, collection 2 |
|---|---:|---|
| homogeneous p50 | **+22%** | −45.9%, −45.2%, +9.4%, (+237% warmup outlier) |
| heterogeneous p50 | **+66%** | −52.2%, −52.0%, −13.2%, −9.3% |

Making the reply divisible reverses the sign of the metric that rejected exp
249. That is a clean confirmation of a rejection's stated cause, which is rarer
than it should be — most rejections name a mechanism and never get to test it.

The first collection put heterogeneous p50 at +74% to +90%, reproduced 4/4.
That was the flush-policy defect described in §Approach, not the reply
protocol; splitting the free workers between the batchable and un-batchable
classes reversed it to the 4/4 win above. It is reported because a runner who
reuses exp 249's flush code will hit it.

### 4. The tail did not resolve

p95 moved positive in 11 of 16 pass-deltas, which looks like the tail cost you
would predict from static assignment — a member at the end of a long chunk
cannot be picked up by a worker that has gone idle, which a FIFO always allows.
But the two collections disagree on the homogeneous scenario (+29/+52/+24, then
+89/+196/−54/−51), and a 120-trial single-shot read of the whole distribution
does not separate the arms at p90 or p95 in either scenario. One candidate
sample reached 14.1 ms against a baseline maximum of 4.2 ms, which is the shape
of a static-assignment tail, and one sample is not evidence.

Recorded as unresolved. The verdict does not rest on it.

### 5. Two correctness hazards that are properties of the protocol, not of this code

Splitting one logical completion across several turns re-opens invariants the
scalar path holds by construction, because its bookkeeping all runs in one
synchronous turn inside the port handler.

- **An unchanged member re-dirtied mid-batch is invisible.** It sends no
  partial, and `onDependencyChanges` skips queueing anything already
  `inFlight`, so nothing ever notices it. The stream stays stale until some
  later write happens to dirty it again. A convergence test written against
  overlapping write waves reproduces it as a hang; the fix is to re-queue dirty
  members when the batch's terminator releases them.
- **Re-queueing from inside a partial handler double-dispatches.** An entry
  that is simultaneously queued and `inFlight` can be picked up by a concurrent
  write's `_flushQueue` while the worker still holds it, racing two reruns over
  one hash baseline. The scalar path never opens that window; the batch does,
  for the length of the batch.

Both were found before measurement, and the second only because the first was.

## Decision

**Rejected**, on the predeclared win condition. The candidate removes 96% of
the fan-out's rerun request messages and three quarters of its replies and
moves backlog drain by +2.0% pooled, sign-flipping, inside a ±5% control floor.
There is no throughput win to weigh against the tail risk of §4 or the
protocol hazards of §5, so there is nothing to ship.

What the run establishes is stronger than exp 249's rejection, because exp 249
never measured throughput at all — it measured latency and inferred. The
batching family now closes from both ends: the indivisible reply really was
what hurt exp 249 (§3), and with it removed there was never a throughput win
underneath (§2).

**Would reopen if** a fan-out workload appears where reruns are *cheap* enough
per member that dispatch is a materially larger share than it is here — the
lane measured has ~100-row partitions, and exp 283 prices a 100-row hash pass
at 4.54 µs against roughly 8 µs of reader-side work per rerun. A workload of
one-row streams would shift that ratio. Absent that, the fan-out constraint is
somewhere else and §2 is the evidence for looking there instead.

**Do not reopen** by making the batch smarter — adaptive sizing, work stealing,
a cheaper terminator, per-member priorities. §2 measures the entire ceiling
those would compete for, and it is zero. This is the third rejection in the
batching family and the first one that priced the prize rather than the
mechanism.

## Future Notes

- The instrument generalises past this experiment. To find out whether X is a
  system's constraint, the cheapest measurement is often not to instrument X
  but to build the version with almost none of it and watch the wall not move.
  A 24:1 message reduction that changes nothing bounds dispatch overhead more
  tightly than any counter would have, and it took one afternoon.
- `benchmark/experiments/stream_rerun_latency.dart` did its job twice: it
  killed exp 249 and it caught this candidate's flush-policy defect in the
  first collection. Any stream-dispatch change should still run it.
- The fan-out drain is still mostly unattributed, and §2 removes one candidate
  explanation for good. The write burst is 1.75 ms of 6.03 ms; the readers'
  SQLite work is most of the rest; whatever remains is not messaging. Exp 283's
  suggestion — sweep the pool size across one drain burst — is now the obvious
  next probe, and it is cheap.
- Any future multi-reply worker protocol inherits §5. The scalar path's safety
  comes from running its whole completion in one synchronous turn; a protocol
  that splits the completion has to re-establish every invariant that turn was
  holding, and the one that bites is the entry that is both queued and
  in-flight.
