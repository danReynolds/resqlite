# Experiment 265: run a small read on the isolate that asked for it

**Date:** 2026-08-08
**Status:** Accepted
**Category:** Moonshot
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused AOT A/B, two collections of four
  alternating-order lane-isolated passes of
  [`benchmark/experiments/select_inline_dispatch.dart`](../benchmark/experiments/select_inline_dispatch.dart);
  receipt in
  [`benchmark/results/2026-08-08T18-30-00Z-exp265-inline-main-isolate-select.md`](../benchmark/results/2026-08-08T18-30-00Z-exp265-inline-main-isolate-select.md).
  No release-suite lane resolves a microsecond of per-read scheduling, so the
  focused harness is the durable gate.

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
because its sub-threshold transfer saving was "below the round-trip floor". Exp 209 and
[exp 239](239-select-overflow-batching.md) both went after that floor by *amortising*
the hop across several queries, and both were rejected because a shared reply
cannot complete independently. And exp 264's own handoff note names what is left:
"the next thing to attack on the small-read path is the isolate round trip
itself."

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

The reason this is attemptable now and was not before is that exps
[260](260-result-list-presize.md) and 264 built the missing piece for a different
purpose. `ReaderPool` keeps a per-SQL `RowSizeMemory` on the main isolate, and it
already holds a **high-water mark of every row count a statement has ever
returned**. That is exactly the private cost signal exp 239's rejection said
would be needed to reopen read routing — it just arrived as a buffer-sizing hint
rather than as a routing one.

Primary gate: at least 25% faster median wall on point reads, reproduced across
the order flip, with the concurrency guard not regressing. Kill conditions: the
guard lane regresses (a caller running eight reads itself loses the pool's
parallelism), the mispredict cost is unbounded rather than one-off, or any lane
that cannot reach the changed path moves.

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
longer than *k*, so a statement that alternates would be re-admitted forever.

Everything downstream is the code the worker runs. `executeQueryInline` acquires
the statement through the same `resqlite_stmt_acquire_on` and decodes it through
the same `decodeQuery`; the result is the same `ResultSet` over the same flat
value list. What differs is three things:

- **Its own connection.** `Database.open` now opens `readerCount + 1` reader
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
  heap for the hop. There is no hop, so the cap also suppresses the wrap and the
  cell decodes straight to a `Uint8List`.

The failure path is deliberately silent. `executeQueryInline` returns null on
*any* exception rather than reporting one, so an error surfaces from the pool
exactly as it does today. It costs one duplicate execution, which is free of
consequence because reader connections are `SQLITE_OPEN_READONLY`.

Scope is `select()` only. `selectBytes` builds no Dart result and serialises in
C; `tx.select` runs on the writer connection; stream reruns are the obvious next
candidate and are not in this experiment.

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
This is the lane that matters most for an application and the one a
transfer-shaped analysis would never find, because the hop's cost is not only its
own latency but the queue in front of it. Four outstanding 1,000-row reads occupy
every worker, and today a point read behind them waits for one to finish: 533-1169
us across the passes, against 37-52 us for a read that never enters the queue. A
list refresh and a tap landing in the same frame is not an exotic shape.

**Losing the pool's parallelism costs nothing; it pays.** The guard lane was
written to kill the idea. Eight distinct point reads issued together run four-wide
across the pool today and strictly one after another on the calling isolate — and
the serial version is 70% faster, reproduced in both pairs. Four workers cannot
make up a per-request overhead that is larger than the request; running eight
2-us reads back to back beats running four 8-us round trips twice.

**Both controls are flat.** `mixed6-1k` and `int20-10k` return far more rows than
the cap admits, so both arms execute the same machine code and the lanes read the
cross-worktree binary offset directly (the exp 254 trap). They come in at +0.1%
and +3.2% mean, and the one comparison this change adds to the shared decode
loop — `inlineRowCap != 0`, false on every worker call — is not visible in a
10,000-row decode.

**The mispredict costs one execution about 25%.** `cap-abort` arms a
never-before-seen statement with two one-row executions and then makes it return
400 rows, so the decode starts inline, gives up past row 64 and re-runs on a
worker: 129 us against 163 us, reproduced in both pairs. It is once per statement,
not once per swing — the high-water mark rises with the large result and the
statement is never admitted again, which the routing test asserts directly rather
than through the lane. Every sample of that lane uses a fresh SQL string for the
same reason: measured any other way it goes inert after its first sample.

**Peak RSS moves by the size of one SQLite connection.** The extra reader costs
+0.1 to +1.7 MB of `maxRss` across the lanes, with two lanes reading slightly
*down*, so it is at the edge of what exp 261's guard resolves. That is the
expected shape: a connection's page cache is demand-filled, and the inline
connection reads the same pages the workers already have resident.

### What this costs the main isolate, stated plainly

The win *is* the main isolate doing the work. An inline point read occupies it
for about 2 us of uninterruptible time, and the cap bounds the worst admitted
case at about 16 us (a 64-row six-column decode, from `page64`'s candidate
median). Against a 16 ms frame that is 0.1%, and a hundred such reads in one
frame is 1.6 ms — where the same hundred reads cost 3 ms of *wall* today with the
isolate idle-waiting through it.

That is the trade, and it is a judgment rather than a measurement: resqlite's
headline is that SQLite runs off the calling isolate, and this makes that untrue
for statements it has watched twice and never seen return more than 64 rows.
`RESQLITE_INLINE_ROW_MAX` is the knob, and setting it to 0 restores the previous
behaviour exactly. What would flip the decision is evidence that a real
application's read mix admits far more work than this bounds — a statement that
returns 64 rows of 400-byte TEXT is a different proposition from 64 rows of six
integers, and the cap counts rows, not bytes.

## Decision

**Accepted.** The primary gate asked for 25% on point reads and got 75%,
reproduced in both collections and all four passes of each, with both mechanically
inert controls flat and the kill-condition guard lane moving the other way. The
two costs are bounded and measured: one execution per statement at +25%, and up
to ~16 us of main-isolate time per admitted read.

Held for human review rather than auto-merged, because it ships runtime code and
because the paragraph above is a positioning decision as much as a performance
one.

## Why the earlier rejections do not cover this

- **[Exp 063](063-select-one-fast-path.md) / [exp 066](066-transparent-fast-path.md)**
  attacked the same shape — the point read — from inside the worker: fewer FFI
  crossings, a right-sized allocation, a `Map` instead of a `List<Map>`. Exp 066
  concluded that the transparent share of that was 2-5% and below the noise
  floor, and it was right. Neither touched where the query runs.
- **Exp 209 / [exp 239](239-select-overflow-batching.md)** did attack the round
  trip, by making several queries share one. Exp 239's rejection is precise: queue
  depth cannot encode query cost, and members of a batch share an indivisible
  reply. Removing a hop for one query has neither problem — nothing is shared, and
  the cost question is answered by a per-statement high-water mark rather than by
  queue depth.
- **[Exp 197](197-true-group-commit-moonshot.md) / [212](212-lazy-nested-savepoint-moonshot.md) /
  [213](213-tx-body-write-coalescing.md)** are the moonshots that reproduced their
  numbers and were rejected anyway, and they are the right precedent to check
  against. Exp 197 changed read visibility and crash-window durability; exps 212
  and 213 put load-bearing guards on the writer hot path for a workload the
  library does not steer users toward. This changes no visibility, durability or
  atomicity semantics — a read on a fifth read-only connection sees what a read on
  the other four sees — and its workload is the most common one there is.

## Future work

- **Stream reruns are the same shape and are not done here.** `selectIfChanged`
  on an unchanged small result is a hash pass with no decode at all, which is the
  cheapest thing the pool carries and therefore the one paying the largest
  relative hop. Exp 136 measured the reader worker port handler at 28.6% of A11c
  overlap wall. The gate for that work is
  `benchmark/experiments/stream_rerun_latency.dart`, not this harness, and exp
  249's cross-worktree rule applies.
- **The cap counts rows.** Sixty-four rows of six integers and sixty-four rows of
  400-byte TEXT are an order of magnitude apart in decode time. A slot- or
  byte-aware cap is the obvious refinement, and exp 246's routing rule already
  says which unit to reach for.
- **`_rowHintMax` now gates a third consumer.** Exp 264 left the pool's 32-entry
  memory unmeasured against a real application's statement churn; an evicted entry
  now loses inline eligibility as well as both buffer hints.
