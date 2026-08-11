# Experiment 265: run a small read on the isolate that asked for it

**Date:** 2026-08-08
**Status:** Rejected
**Category:** Moonshot
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused AOT A/B, two collections of four
  alternating-order lane-isolated passes of
  [`benchmark/experiments/select_inline_dispatch.dart`](../benchmark/experiments/select_inline_dispatch.dart);
  receipt in
  [`benchmark/results/2026-08-08T18-30-00Z-exp265-inline-main-isolate-select.md`](../benchmark/results/2026-08-08T18-30-00Z-exp265-inline-main-isolate-select.md).
  No release-suite lane resolves a microsecond of per-read scheduling, so the
  focused harness was the gate.

> **Rejected after the measurements came in.** The wall-clock numbers below are
> real and reproduced, and they are the experiment's lasting contribution: they
> price the `select()` round trip, which four prior experiments closed
> candidates against without ever measuring. The idea is rejected because the
> *safety* argument does not hold — eligibility was decided by a prediction, and
> the row-count signal it predicts from cannot bound main-isolate work along
> three independent axes. The runtime prototype is preserved at
> `archive/exp-265`; the reopen conditions are at the bottom.

## Problem

Every read resqlite serves crosses to a reader isolate and back. The request is
copied to a worker, the worker steps SQLite and decodes the rows, and the result
is copied — or, past 32,768 slots, moved by ending the worker — back to the
caller. For a large result that hop is the cheapest part of the operation and
the pool is plainly earning its keep: the work is real, it is off the main
isolate, and the transfer has been optimised down the length of this direction.

For a point read there is almost nothing to transfer, and the hop is most of
what the caller waits for. The surrounding experiments have been saying so for
months without ever pricing it. [Exp 264](264-initial-alloc-size-memory.md) put
a point read at "about 5-8 us, most of which is the isolate round trip". [Exp
258](258-columnar-result-store.md) rejected a columnar result store partly
because its sub-threshold transfer saving was "below the round-trip floor". Exp
209 and [exp 239](239-select-overflow-batching.md) both went after that floor by
*amortising* the hop across several queries, and both were rejected because a
shared reply cannot complete independently. And exp 264's own handoff note names
what is left: "the next thing to attack on the small-read path is the isolate
round trip itself."

Nobody had tried removing it.

## Hypothesis

**Assumption challenged: that every read has to cross an isolate boundary.**

The pool exists so that SQLite work does not block the isolate that paints
frames. That is a proposition about *work*, and it is quantitative rather than
categorical — a read that costs two microseconds is not work worth protecting a
frame from, and today it is charged an isolate round trip for the protection.

So: when the caller already knows a statement returns a handful of rows, run it
on the calling isolate and skip the hop entirely. Not batched, not amortised,
not deferred — not run anywhere else at all.

The reason this looked attemptable now is that exps
[260](260-result-list-presize.md) and 264 built what seemed to be the missing
piece for a different purpose. `ReaderPool` keeps a per-SQL `RowSizeMemory` on
the main isolate, and it already holds a **high-water mark of every row count a
statement has ever returned**. That reads like the private cost signal exp 239's
rejection said would be needed to reopen read routing — arriving as a
buffer-sizing hint rather than a routing one.

It is not that signal. Recognising why is most of what this experiment produced,
and it is in [Why this is rejected](#why-this-is-rejected).

Primary gate: at least 25% faster median wall on point reads, reproduced across
the order flip, with the concurrency guard not regressing. Kill conditions: the
guard lane regresses, the mispredict cost is unbounded rather than one-off, or
any lane that cannot reach the changed path moves.

## Approach

`ReaderPool.select` consults the memory it already keeps, and when the statement
qualifies it runs the query itself:

```dart
if (memory.initialRows == 0 || memory.highWater > inlineRowMax) return null;
```

Two conditions, each inherited rather than invented. `initialRows == 0` until the
pool has watched a statement twice, which is exp 264's rule and is there because
one observation cannot tell a point read from the small leg of a `LIMIT ?`. And
the size test is against the **high-water mark**, not a recent count, for the
reason exp 264 had to discover: a window of length *k* is defeated by any burst
longer than *k*.

Everything downstream is the code the worker runs. `executeQueryInline` acquires
the statement through the same `resqlite_stmt_acquire_on` and decodes it through
the same `decodeQuery`; the result is the same `ResultSet` over the same flat
value list. What differs is three things:

- **Its own connection.** `Database.open` opens `readerCount + 1` reader
  connections and the pool reserves the last for the calling isolate. It cannot
  borrow an idle worker's: the connections are `SQLITE_OPEN_NOMUTEX`, and the
  reply that marks a worker slot free is sent *before* the worker's `finally`
  releases the connection, so "idle" on the main isolate is not yet "idle" in C.
- **A row cap.** `decodeQuery` takes an `inlineRowCap`, and past it throws
  `InlineRowCapExceeded`, which resets the statement and returns null so the
  caller dispatches to a worker as usual. The reset is load-bearing: a statement
  abandoned mid-iteration holds its connection's read transaction open, and every
  later read on that connection would be served from a stale snapshot.
- **No blob wrapping.** [Exp 236](236-blob-cell-transfer.md) wraps blob cells
  past 256 KB in `TransferableTypedData` to keep the payload off the sender's
  heap for the hop. There is no hop, so the wrap is suppressed and the cell
  decodes straight to a `Uint8List`. This turns out to matter — see below.

Scope was `select()` only. `selectBytes` builds no Dart result and serialises in
C; `tx.select` runs on the writer connection.

## Results

Two collections, each four alternating-order lane-isolated passes, both arms
built as native-asset-aware AOT CLI bundles from an identical harness source.
The table is the second collection (51 samples per lane per pass); the first
(41 samples) agrees on every lane and is in the receipt. Verdicts are
`benchmark/ab_drift_check.dart`'s.

| lane | role | p1 | p2 | p3 | p4 | mean | verdict |
|---|---|---:|---:|---:|---:|---:|---|
| `point1` | primary | −74.7% | −70.6% | −73.0% | −81.1% | **−74.8%** | reproduced |
| `point1-wide20` | primary | −74.4% | −72.1% | −76.6% | −60.8% | **−71.0%** | reproduced |
| `page20` | primary | −48.2% | −37.1% | −28.3% | −29.3% | **−35.7%** | reproduced |
| `page64` | primary | −27.1% | +44.8% | −29.9% | −20.7% | −8.2% | 1 of 2 pairs reproduced |
| `point-under-load` | primary | −92.1% | −94.5% | −96.2% | −96.7% | **−94.9%** | reproduced |
| `concurrent8` | guard | −67.2% | −78.6% | −77.9% | −57.2% | **−70.3%** | reproduced |
| `mixed6-1k` | control | +0.9% | +4.2% | −0.8% | −3.8% | +0.1% | neutral |
| `int20-10k` | control | −2.4% | −6.7% | +0.7% | +21.3% | +3.2% | neutral |
| `cap-abort` | guard | +26.4% | +15.3% | +48.1% | +9.0% | **+24.7%** | reproduced |

**A point read is roughly four times faster.** In absolute terms 8.4 us per read
becomes 2.1 us on the six-column canonical row, and the twenty-one-column row
behaves the same way — unlike exp 264's win, which scaled with projection width,
this one does not, because what it removes is per-*request* and not per-slot.
The effect decays with result size exactly as the mechanism predicts: −75% at one
row, −36% at twenty, and by sixty-four rows the decode is large enough that the
hop is no longer the dominant term and the lane stops resolving cleanly.

**A point read issued while the pool is busy is about nineteen times faster.**
Four outstanding 1,000-row reads occupy every worker, and a point read behind
them waits for one to finish: 533-1169 us across the passes, against 37-52 us
for a read that never enters the queue. The hop's cost to a caller is its own
latency plus the queue in front of it, and every prior transfer measurement in
this direction held the request population constant and so saw only the first
term.

**Losing the pool's parallelism costs nothing at these sizes.** Eight distinct
point reads issued together run four-wide across the pool and strictly one after
another on the calling isolate — and the serial version is 70% faster,
reproduced in both pairs. Four workers cannot make up a per-request overhead
larger than the request.

**Both controls are flat**, at +0.1% and +3.2%: they return far more rows than
the cap admits, so both arms execute the same machine code.

These numbers were collected against `4b963ad`, before
[exp 266](266-sticky-reader-dispatch.md) landed. Exp 266 attacks a different
component of the same overhead — a fixed per-(statement, worker) warmup, worth
−32.2% on a statement's first four executions and decaying to −1.6% by the
eight-thousandth (claim 266.1) — and every lane here runs 12 warmups plus tens to
hundreds of executions per sample, well past where that term matters. So the
pricing below should survive on current main, but it was not re-measured there.

### What the numbers are worth

The durable result is the denominator, not the candidate: **on the canonical
6-column point read the isolate round trip is 6.3 us of an 8.4 us read.** Four
experiments have closed candidates against a "round-trip floor" that nobody had
measured. It is now measured, and it was most of a small read — so anything
previously rejected as *below the round-trip floor* was compared against a
denominator four times larger than the work it was competing with. That stands
regardless of this experiment's disposition.

## Why this is rejected

The kill conditions the experiment set were all met — and they were the wrong
conditions. Every one of them tests whether the *hint* is wrong about row count,
which is the single failure mode the row cap already handles. None of them tests
whether row count is the right thing to predict from.

It is not. Rows-returned fails to bound main-isolate work along three
independent axes, and the design leans on it for safety in all three.

**One row can be arbitrarily large.** `SELECT * FROM photos WHERE id = ?`
returns exactly one row. Its high-water mark is 1, so it is admitted after two
executions and admitted permanently — and because there is no hop, exp 236's
blob wrapping is suppressed, so a 5 MB image is copied straight onto the calling
isolate. In the prototype the guarding branch reads
`inlineRowCap == 0 && blobLen >= BlobTransfer.cellThreshold`, so on the inline
path it is dead code and the blob is copied at any size, unchecked
(`archive/exp-265`, `lib/src/query_decoder.dart`). The most common point-read
shape in a real application is the
design's worst case, and the row cap does not see it. Worse, this is not even a
mispredict that a high-water mark corrects cheaply: cost varies per *execution*
of the same statement — `id=1` is a 2 KB thumbnail, `id=2` is a 20 MB raw — so
no history of the SQL string predicts the next parameter.

**Rows returned is not query cost.** `SELECT count(*) FROM huge_table` returns
one row forever; its high-water mark is 1; it is admitted forever; and every
execution scans the whole table on the calling isolate. The same holds for an
unindexed `ORDER BY ... LIMIT 10`: ten rows out, a full sort in. A result-shape
signal is structurally blind to this, because the work happens before the first
row is produced.

**Inline reads do not yield.** `_selectInline` returns a `List`, not a `Future`,
so an inline `select()` completes without a single event-loop turn. Today,
awaiting a worker reply parks on a message from another isolate and the event
loop runs in the gap — frame callbacks can fire between reads. Inline, a chain
of awaits drains entirely in microtasks, and microtasks drain to completion
before the event loop regains control. So N inline reads are not N interleavable
2 us slices; they are one uninterruptible N×2 us block. The `point1` lane is
unintentional evidence: 200 awaited inline reads at 427 us is a 0.43 ms stretch
with no opportunity to paint. This one has no cheap fix — it is inherent to
running synchronously, and the mitigation would be a per-drain time budget that
yields back to the event loop, which is a design question rather than a guard.

The writeup as first drafted claimed a bound of "~16 us per admitted read". That
was the bound for the shapes the harness measured — small integers, short TEXT,
cheap indexed lookups, a hot page cache — and it was stated as though it were
general. It is not, and none of the nine lanes could have caught any of the
three cases above.

### The structural fix, and why it is not a follow-up

The row cap is the part of this design that holds up, because it does not
*predict* anything: it aborts mid-decode and falls back, and it is correct
whether or not the hint was right. The fix is to make every safety property work
that way — enforce rather than predict — which needs two more enforcement points:

- **Bytes.** `sqlite3_column_bytes` gives a cell's size before anything is
  copied into Dart, and `blobLen` is already loaded at the very line where the
  wrap branch is skipped. A running byte total against a cap is one comparison
  on a value already in hand.
- **VM steps.** `sqlite3_progress_handler` interrupts every N steps, which
  bounds the `count(*)` and unindexed-sort cases that no result-shape signal can
  see.

With both, the high-water hint stops being load-bearing for safety and becomes
what it is actually good at: avoiding *wasted* aborts. That is a better design
than the one measured here.

It is not merged as a follow-up because it changes the thing being tested. The
guard set would have to be rebuilt around the failure modes rather than the
happy path — at minimum a one-row-with-5 MB-blob lane and a `count(*)`-over-a-
large-table lane, both of which fail against this prototype — and the third
problem (microtask coalescing) is untouched by either enforcement point and has
no obvious cheap answer. That is a new experiment with a different hypothesis,
not a patch to this one.

## Decision

**Rejected.** The performance result is real and reproduced; the safety
argument is not sound. Shipping a read path whose worst case is an unbounded
main-isolate blob copy, on the most common point-read shape there is, is not
worth 6 us on a 8 us read — and the library's whole positioning is that SQLite
work does not land on the calling isolate.

The measurement survives as the contribution: the round-trip floor is priced,
and `benchmark/experiments/select_inline_dispatch.dart` is kept as the gate for
any future read-routing work.

### Reopen conditions

Any of these changes the answer:

1. An enforcement-based design — byte cap and VM-step cap alongside the row cap
   — with a guard set built from the three failure modes above rather than from
   the happy path.
2. An answer to microtask coalescing: a per-drain budget that yields to the
   event loop, measured against a frame-shaped workload rather than a throughput
   one.
3. Evidence that the round trip's 6.3 us is worth more than it looks — a
   production profile or user report where small-read latency, not throughput,
   is the complaint. That would justify the extra machinery the first two
   conditions require.

The prototype is at `archive/exp-265` for cherry-pick.

## Why the earlier rejections still do not cover this

Recorded because the *reasoning* about prior art was sound even though the
candidate failed, and a future runner will hit the same question:

- **[Exp 063](063-select-one-fast-path.md) / [exp 066](066-transparent-fast-path.md)**
  attacked the point read from inside the worker and found the transparent share
  was 2-5%, below the noise floor. Neither touched where the query runs.
- **Exp 209 / [exp 239](239-select-overflow-batching.md)** attacked the round
  trip by making several queries share one. Exp 239's rejection is precise:
  queue depth cannot encode query cost, and members of a batch share an
  indivisible reply. Removing a hop for one query has neither problem.
  Note the irony: exp 239 was rejected partly because *queue depth cannot encode
  query cost*, and this experiment was rejected because *row count cannot encode
  query cost* either. The lesson generalises further than either rejection put
  it.
- **[Exp 197](197-true-group-commit-moonshot.md) / [212](212-lazy-nested-savepoint-moonshot.md) /
  [213](213-tx-body-write-coalescing.md)** are the moonshots that reproduced
  their numbers and were rejected anyway. This now joins them, for a reason none
  of them had: not shipped complexity, and not a semantic change, but a guard
  set that tested the wrong proposition.

## Future work

- **Stream reruns are the same shape**, and inherit all three problems above, so
  they are not a shortcut around this rejection. `selectIfChanged` on an
  unchanged small result is a C hash pass with no Dart decode — the cheapest
  thing the pool carries and so the largest relative hop — but an unchanged
  result is still produced by a query whose cost row count cannot predict.
- **The round-trip price is the reusable number.** 6.3 us of an 8.4 us read, on
  this hardware, for this shape. Any future candidate in this direction should
  be compared against 2.1 us of actual work, not against 8.4 us of read.
