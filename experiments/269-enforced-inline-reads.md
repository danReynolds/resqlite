# Experiment 269: bound the read, don't predict it

**Date:** 2026-08-11
**Status:** Accepted
**Category:** Moonshot
**Direction:** `result-transfer-shape`
**Benchmark Run:** Release headline suite at HEAD, 5-sample medians with the
  regression gate on — this change touches every `select()` and a SQLite build
  flag that affects every query, so the no-collateral-damage sweep matters more
  than usual here. The **decision** rests on the focused AOT A/B, because no
  release lane resolves a microsecond of per-read scheduling: three collections
  of four alternating-order lane-isolated passes of
  [`benchmark/experiments/select_inline_dispatch.dart`](../benchmark/experiments/select_inline_dispatch.dart),
  plus two auxiliary builds that isolate the SQLite build-flag change and the
  per-turn budget, all in
  [`benchmark/results/2026-08-11T06-00-00Z-exp269-focused-ab.md`](../benchmark/results/2026-08-11T06-00-00Z-exp269-focused-ab.md).

## Problem

[Exp 265](265-inline-main-isolate-select.md) removed the isolate round trip
from small reads and measured the win: on the canonical six-column point read
the hop is 6.3 us of an 8.4 us read. Then it rejected itself, and the rejection
is the reason this experiment exists.

It rejected itself because eligibility was a **prediction**. The pool already
keeps, per SQL string, the largest row count that statement has ever returned —
a buffer-sizing hint from exps [260](260-result-list-presize.md) and
[264](264-initial-alloc-size-memory.md) — and exp 265 read a routing decision
out of it: never returned more than 64 rows, so run it here. Rows returned
bounds neither of the two things that make a read expensive. One row can be a
5 MB image, and `SELECT * FROM photos WHERE id = ?` has a permanent high-water
mark of 1. A filtered count returns one row after reading the whole table. And
a third problem sat outside both: an inline read completes without an
event-loop turn, so an awaited chain of them drains as one uninterruptible
microtask block that a frame callback cannot interrupt.

Its own writeup named the fix and declined to make it, on the grounds that it
changes the thing being tested:

> The row cap is the part of this design that holds up, because it does not
> *predict* anything: it aborts mid-decode and falls back, and it is correct
> whether or not the hint was right. The fix is to make every safety property
> work that way — enforce rather than predict.

## Hypothesis

**Assumption challenged: that a read has to be *classified* as cheap before it
is allowed to run on the calling isolate.**

It does not. It has to be *stopped* if it turns out not to be. Those are
different designs and only the second one is sound, because the properties that
matter — how many rows, how many bytes, how much work — are all observable
while the query runs, and none of them is knowable from a statement's history.

So: keep exp 265's routing, throw away its safety argument, and replace it with
three caps enforced against what the query is producing, plus an answer to the
microtask problem. The pool's row-count memory survives, demoted to what it is
good at — avoiding *wasted* aborts — where being wrong costs speed and nothing
else.

Primary gate: the point-read wins survive enforcement, reproduced across order
flips. Kill conditions, all three of which are new and none of which exp 265
could see: a 5 MB blob reaching the calling isolate; a full scan running there;
or worst-case frame lateness getting worse than dispatch.

## Approach

Three enforcement points, one budget, and one demotion.

**Rows.** `decodeQuery` takes an `inlineRowCap` (64) and throws past it. This is
exp 265's, unchanged, and it was always the sound part.

**Bytes.** `decodeQuery` also takes an `inlineByteCap` (64 KB) and accumulates
TEXT and BLOB payload lengths against it. The length is read from the cell
buffer *before* the copy, so a 5 MB image is never copied — it is still sitting
in SQLite's memory when the decode gives up. The cap is required to be below
`BlobTransfer.cellThreshold` (256 KB), which is what makes the decoder's
`TransferableTypedData` wrap branch **unreachable** on the inline path rather
than skipped: a cell big enough to be worth wrapping for a hop always trips the
byte cap first and goes to a worker, which wraps it. Exp 265 skipped that branch
and left the copy unchecked, which is the bug that killed it.

**VM steps.** `resqlite_set_vm_step_budget` installs a SQLite progress handler
that aborts the statement with `SQLITE_INTERRUPT` after 10,000 VDBE opcodes.
This is the only one of the three that can see work happening *before* a row is
produced. Two things about it were not obvious:

- `SQLITE_OMIT_PROGRESS_CALLBACK` was in the build hook's define list, so the
  enforcement point exp 265 named did not exist in the shipped library. It is
  removed here. With no handler installed the VDBE compiles in one
  `nVmStep >= LARGEST_UINT64` compare at its jump-back opcodes — SQLite's own
  code is structured to keep this out of the per-opcode path — and a build that
  changes only this flag measures below the harness floor (see the receipt).
- The abort has to be decided in C. The handler fires inside `sqlite3_step`,
  which Dart enters through `resqlite_step_row` as an `isLeaf` call, and a leaf
  call cannot re-enter Dart: a `Pointer.fromFunction` callback traps the VM with
  *Cannot invoke native callback from a leaf call*. The C helper also resets
  `SQLITE_STMTSTATUS_VM_STEP`, because that counter accumulates over a cached
  statement's whole life and the handler fires on multiples of its interval — so
  without the reset a cheap statement would abort spuriously once every
  `budget / steps-per-execution` executions.

**The chain.** `ReaderPool` runs a stopwatch across the current event-loop turn,
started by the turn's first inline read and retired by a zero-duration `Timer`,
which by construction cannot fire until the microtask queue has drained. Past
1 ms the pool dispatches for the rest of the turn — and there dispatching is the
*point* rather than a fallback, because awaiting a worker parks on a message
from another isolate and hands the event loop back.

**The demotion.** The row high-water mark and a new `inlineDisqualified` latch
decide only whether an attempt is *worth making*. A statement that has aborted
once is never offered again, because none of the three caps fails for a reason
that is worth retrying: a filtered count costs the same opcodes every time, and
a table holding one 5 MB image holds others.

Scope is `select()`. `selectBytes` builds no Dart result and serialises in C;
`tx.select` runs on the writer connection. `Database.open` opens one reader
connection past the pool, reserved for the calling isolate — it cannot borrow a
worker's, because the connections are `SQLITE_OPEN_NOMUTEX` and the reply that
frees a worker slot is sent *before* the worker's `finally` releases its
connection.

## Results

Three collections, each four alternating-order lane-isolated passes, both arms
built as native-asset-aware AOT CLI bundles from an identical harness source.
Every verdict is `benchmark/ab_drift_check.dart` over two order-flipped passes,
so each lane below carries six independent verdicts. Full tables in the
[receipt](../benchmark/results/2026-08-11T06-00-00Z-exp269-focused-ab.md).

| lane | role | c1 | c2 | c3 | verdict |
|---|---|---:|---:|---:|---|
| `point1` | primary | −62.4% | −62.9% | −60.0% | reproduced ×6 |
| `point1-wide20` | primary | −64.7% | −64.7% | −64.9% | reproduced ×6 |
| `page20` | primary | −37.2% | −39.0% | −38.2% | reproduced ×6 |
| `page64` | primary | −25.1% | −22.2% | −24.0% | reproduced ×6 |
| `point-under-load` | primary | −89.3% | −90.4% | −89.5% | reproduced ×6 |
| `concurrent8` | guard | −68.3% | −68.2% | −69.8% | reproduced ×6 |
| `frame-jitter` | guard | −39.5% | −45.2% | −45.6% | reproduced ×6 |
| `cap-abort` | guard | +36.8% | +28.8% | +30.5% | reproduced ×6 |
| `blob1-5mb` | guard | −0.5% | +1.2% | +1.2% | neutral ×6 |
| `scan-count` | guard | +0.9% | +1.0% | +1.0% | neutral ×6 |
| `int20-10k` | control | −1.5% | −2.1% | −2.1% | neutral ×6 |
| `mixed6-1k` | control | +4.5% | +4.6% | +2.8% | mixed — see below |

A point read is **about two and a half times faster**, and a point read issued
while four large reads hold the whole pool is **ten times faster**, because a
read that never enters the queue does not wait behind it. The win decays with
result size exactly as the mechanism predicts — 64 rows is −24%, one row is
−62% — since what is removed is per-request, not per-row.

`concurrent8` was written by exp 265 as the lane that could kill the idea: four
workers run four point reads at once, where a caller that runs them itself runs
them one after another. It is −68%. Losing pool parallelism does not matter
when the parallelism is recovering an overhead larger than the work.

**The three guards exp 265 asked for.** `blob1-5mb` and `scan-count` are
neutral in all six verdicts, which is the result those lanes exist to produce:
both shapes are recognised and handed to a worker, so they cost what they cost
today. What makes them meaningful is the routing assertions in
`test/inline_read_routing_test.dart`, verified against a build with enforcement
removed — the byte cap aborts the 5 MB point read, and the VM-step cap aborts
both a filtered count and an unindexed sort. Exp 265's own canonical example
turns out to be wrong, incidentally: a bare `SELECT count(*)` is one `OP_Count`
opcode however large the table, so it is genuinely cheap and correctly runs
inline. The dangerous shape is a count with a predicate.

**Frame lateness, which had no cheap fix.** The candidate's worst 60 Hz frame
lateness is 1147 us against dispatch's 2381 us — the design is *better* than the
pool it bypasses, because the dispatch arm answers ~6,000 reads in the 50 ms
sample and every reply is a port message competing with the timer. A fourth
build with the budget raised out of reach measures **33,344 us**, two frame
intervals to within 10 us: with no budget the chain holds the event loop for the
entire sample and every deadline in it is missed. Exp 265's objection was
correct and severe; the budget removes it, for 2.8% of the throughput win.

**Costs.** `cap-abort` is +29% to +37%: a statement whose first two executions
returned one row and whose third returns 256 pays for the abandoned decode. That
is once per statement, because the abort latches. `mixed6-1k` is the one
unresolved lane — a 1,000-row control that cannot reach the changed path, which
nonetheless moved +4.5% in the first two collections. Replacing the cap checks'
`!= 0` guard with a sentinel, so the shared decode loop pays one unconditional
compare instead of a guarded one, took it to +2.8%; the residue sits at the 3%
floor and cannot be separated from binary layout, because the same lane reads
+34.9% in one pass of a comparison between two binaries that differ only by a
compile flag. `int20-10k`, which decodes ten times as much and is stable within
±2.1%, is the control to trust.

The fifth reader connection is the memory cost, and it is visible twice. Peak
RSS is +0.8 to +1.2 MB against a ~30 MB floor across all three collections. And
the release suite's `JSON buffer reclaim` guard — the exp 185 lane exp 266's
signal says to check early when changing anything about which connection serves
what — reads 80.0 KiB against the baseline's 64.0 KiB. That is exactly one more
connection's 16 KB initial `json_buf` (exp 183), it is well inside the lane's
512 KiB budget, and it is a floor rather than retention: `selectBytes` opts out
of inline routing entirely, so the reclaim path itself is untouched.

### The release-suite sweep, and one lesson about its anchor

The focused harness decides this experiment, but the release suite is the
no-collateral-damage check, and it matters more than usual here because the
SQLite build-flag change touches every query in the library rather than only
the reads being rerouted. Against a same-host `origin/main` baseline captured
minutes earlier
([`2026-08-11T07-54-12-baseline-for-exp269.md`](../benchmark/results/2026-08-11T07-54-12-baseline-for-exp269.md)),
5-sample medians with `--fail-on-regression`: **1 win, 0 regressions, 168
neutral**, and all six streaming-granularity re-emit counts neutral. The gate
exits zero.

The first attempt at that sweep did not, and the reason is worth recording. Run
against the newest artifact in `benchmark/results/` — exp 266's headline
refresh from two days and two merged experiments earlier — it flagged four
lanes: `selectBytes` large payload +15.4%, long-text unchanged fanout +53.1%,
batched write inside a transaction +23.0%, nested savepoints depth=5 +43.5%.
None of the four is reachable from this diff: `selectBytes` opts out of inline
routing entirely, the two write lanes run on the writer connection, and the
streaming lane is a `selectIfChanged` hash pass that decodes nothing. Repeating
the sweep against a baseline built from the actual parent commit on the actual
host cleared all four, which attributes them to the anchor — exp 267's merged
statement-cache change sits between the two — and to host drift, not to this
change.

The mechanical cause of picking the wrong anchor is worth naming too, because
the next runner will hit it: auto-compare takes the most recent file in
`benchmark/results/`, and a focused-harness receipt committed under the same
date sorts ahead of the release run. The receipt here is timestamped `T06` so
it cannot shadow a `T07`+ release artifact.

## Decision

**Accepted.** All three of exp 265's failure modes are enforced rather than
predicted, each verified by a test that fails when its mechanism is removed;
the microtask objection is answered by a budget that measures better than the
status quo; and the wins survive intact.

The property worth stating plainly: with this design, the pool's opinion about a
statement is never load-bearing. If every hint were wrong, the caps would abort
every attempt and the library would behave exactly as it does today, slower by
the wasted decode. That is what makes it shippable when exp 265 was not.

### What is still not bounded

Two things, both stated rather than fixed:

- **Statement preparation.** `resqlite_stmt_acquire_on` prepares a statement the
  first time the inline connection sees it, and preparation runs no VDBE
  opcodes, so no cap covers it. It is once per (statement, connection) and it is
  the same work a worker would have done, but it happens on the calling isolate.
- **The 1 ms budget is a whole-turn stopwatch**, not a sum of read times, so a
  turn that spends 1 ms on the application's own work stops inlining. That is
  the conservative direction — the turn is already long — but it means the
  budget is not a pure accounting of what this feature costs.

### Reopen conditions for the caps themselves

The three numbers (64 rows, 64 KB, 10,000 opcodes) are budgets for how long a
read may hold the isolate that paints frames, not measurements of where inline
stops being faster — it keeps winning well past all three. Raising them trades
worst-case frame latency for a wider inline envelope, and the harness can price
that: `frame-jitter` is the lane that moves. The byte cap has a hard ceiling at
`BlobTransfer.cellThreshold`, above which the wrap branch stops being
unreachable and the exp 265 bug comes back.

## Future work

- **`selectIfChanged` is the largest remaining hop** and exp 265 flagged it as
  not a shortcut around its rejection. That reasoning applied to a *predicted*
  design; under enforcement the objection is different, because an unchanged
  re-query is a C hash pass with no Dart decode and therefore has no rows or
  bytes to cap — only the VM-step budget would apply. Whether that is enough is
  a real question and the answer is not obvious.
- **The `mixed6-1k` residue.** A separate inline decode loop would remove the
  shared-loop compare entirely at the cost of duplicating ~80 lines. Worth it
  only if a future run can measure the compare above the layout floor, which
  this one could not.
