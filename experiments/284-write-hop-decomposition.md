# Experiment 284: The isolate, not the library

**Date:** 2026-09-07
**Status:** Rejected
**Direction:** `stream-rerun-dispatch`, `measurement-system`
**Benchmark Run:** focused decomposition, five passes × fifteen samples × four
  hundred sequential awaited writes; full tables in
  [`benchmark/results/2026-09-07T11-30-00Z-exp284-write-hop-decomposition.md`](../benchmark/results/2026-09-07T11-30-00Z-exp284-write-hop-decomposition.md)
**Archive:** [`archive/exp-284`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-284)

## Problem

There is exactly one row in the public release suite where resqlite loses to a
peer. `Single Inserts (100 sequential)` reads 1.577 ms for resqlite against
0.934 ms for raw `sqlite3` — 15.8 µs per write against 9.3 µs — on the same
schema, the same statement, the same journal mode and the same `synchronous`
setting (`benchmark/SCOPE.md`). Sequential single writes are about as common as
a database call gets: insert the message, update the row, mark the item read.

Ten experiments have proposed a mechanism for that 6.4 µs. Exp 159 pipelined
the writer request path and was accepted. Exp 151 resolved the writer response
synchronously; exp 170 replaced the writer mutex with `tryLock` and made
`Writer.execute` non-`async`; exp 171 cached the resolved runtime to skip a
microtask hop; exp 182 turned off dependency tracking when no streams are
registered; exp 197 wrapped coalesced writes in one real transaction; exp 214
read the write result struct through direct pointer loads; exp 215 gave
`executeWrite` a persistent result buffer; exp 257 moved independent
autocommits into a native interpreter; exp 271 polled a native completion
mailbox to catch the writer before its port event. All nine were rejected.

Nine rejections in one family is a pattern, and the pattern is that nobody
measured the 6.4 µs before proposing a mechanism for it. Exp 282 made exactly
that mistake visible on the *read* hop three days ago, and its parting
instruction was explicit: when a synthetic harness and an A/B disagree, put a
Stopwatch in the real path in both worktrees. This run is that instrument
pointed at the write path — and one lane more.

## Hypothesis

The 6.4 µs contains a slice worth collecting, and the reason nine experiments
failed to collect it is that each attacked a different small piece without
knowing which piece was large. Measure all of them at once, in the shipping
code path, then implement against whichever is biggest.

The predeclared rule, written before any code: a slice worth ≥ 1.5 µs
(≈ 10% of a write) that can be removed without a semantic or public-API change
gets implemented and gated at ≥ 5% reproduced in both orders. If no such slice
exists, the decomposition closes the family under the **premise refuted**
escape and the priced breakdown is the deliverable.

## Approach

Three instruments, all AOT, all lane-alternating inside one process.

**In-situ probes.** Eleven `Stopwatch` marks in the shipping path — five on the
main isolate around `Writer.execute`, the writer mutex, the request build, the
`SendPort.send` and the reply, and five inside the writer isolate around the
handler entry, `blobTransfer.unwrapParams`, `executeWrite`,
`getDirtyTableDependencies` and the reply send. Nothing forks logic; the marks
only read a clock. They lived in `lib/` for the length of the run and are
preserved at `archive/exp-284`.

**An `inline` reference.** The same insert run on the calling isolate through
the same native entry point the writer uses, against a second handle on the
same file. `hop = writer − inline`, the shape exp 282 used for the read.

**A `floor` lane** — the piece the previous nine experiments did not have. The
same insert through a hand-rolled isolate writer that has *none* of resqlite's
machinery: no coalescing pump, no writer mutex, no blob wrapping, no dirty
dependency harvest, no response object, no completer queue, not even the SQL on
the wire. Send a two-slot parameter list, call `executeWrite` on the other
side, send an `int` back. Subtracting `inline` from resqlite charges resqlite
for the isolate architecture it exists to provide. Subtracting `inline` from
the *floor* prices that architecture on its own, and what is left over is the
only part any experiment could ever collect.

## Results

### The hop has a floor under it, and the floor is most of the hop

| lane | µs per write |
|---|---:|
| `writer` — `await db.execute(...)` | 13.895 |
| `floor-hop` — hand-rolled isolate writer | 12.915 |
| `inline` — identical `executeWrite`, calling isolate | 7.612 |
| **hop** (`writer − inline`) | **6.283** |
| **the isolate boundary** (`floor − inline`) | **5.303** |
| **everything resqlite does** (`writer − floor`) | **0.980** |

**84% of the gap between resqlite and raw `sqlite3` on a sequential write is
the cost of not running SQLite on the calling isolate.** It is not resqlite's
to collect; it is the thing resqlite is for. Everything the library actually
does on a write — coalescing pump, mutex, request construction, blob wrapping,
dependency harvest, response graph, completer queue, stream-invalidation
dispatch — adds up to about one microsecond, 7% of a write.

The in-situ decomposition agrees, from the other direction:

| slice | side | µs |
|---|---|---:|
| `executeWrite` (SQLite, param arena, result buffer) | writer | 8.455 |
| `ExecuteResponse` build + `replyPort.send` | writer | 1.640 |
| `SendPort.send` of the `ExecuteRequest` | main | 1.481 |
| transport + scheduling residual | — | 0.945 |
| `_onReply` → `Database.execute` returns | main | 0.348 |
| `Writer.execute` entry → writer mutex held | main | 0.307 |
| `getDirtyTableDependencies` | writer | 0.288 |
| `blobTransfer.unwrapParams` | writer | 0.192 |
| `ExecuteRequest` build (incl. `wrapParams`) | main | 0.074 |

The five rows resqlite owns sum to **1.209 µs** against the floor lane's
independent **0.980 µs** — two instruments, built on different principles,
landing a fifth of a microsecond apart. The largest single item resqlite owns
is 0.348 µs, 2.5% of a write. There is no 1.5 µs slice. There is no 0.5 µs
slice.

### What the boundary is actually made of

It is not the object-graph copy, which is the thing everyone assumes. Sending
a message shaped like a write request costs 0.272 µs to a port in the sending
isolate, 0.445 µs to an isolate already draining a backlog, and 0.737 µs to one
parked waiting for it.

And the wake does not stop when `send` returns. The floor worker times its own
`executeWrite`: the identical C call, the identical statement and parameters,
costs 7.612 µs inline on a running isolate and **9.380 µs on a worker that was
parked until the message arrived**. About 1.8 µs of the boundary is simply the
woken side running cold.

That is a real correction to a load-bearing number. Claim 279.1 prices an
awaited Dart isolate round trip at 1.46 µs, measured with an echo isolate that
does nothing between messages and never goes cold. When both sides park for
ten microseconds and the woken side then touches a page cache and a statement
cache, the same boundary costs 5.30 µs. 1.46 µs is the floor for a tight
ping-pong, not the price in a workload.

### The candidate, run and rejected

The decomposition named one: every writer request carries a `SendPort
replyPort`, even though the main isolate has had a single persistent reply port
since exp 159, so each message pays the VM to carry a port handle the worker
could simply have kept. The prototype removes the field from all eight request
types and hands the port over once in the spawn arguments — internal only, no
public API change, and it makes eight message types smaller.

| build | in-situ `send` slice, µs |
|---|---:|
| baseline (port on every request) | 1.469 / 1.485 / 1.521 |
| candidate (port handed over once) | 1.471 / 1.483 / 1.484 |

The slice it targets does not move at all, and §2's mechanism says why: `send`
is buying a thread wake, and a port field is not measurable next to one.
Rejected, and reverted.

## Decision

**Rejected**, under the measurement rule's *premise refuted* escape. The
premise — that a standalone write carries a collectible resqlite-side residual
— is false. The residual is 1.0–1.2 µs of a 13.9 µs write, spread across five
items none of which exceeds 0.35 µs. The candidate the decomposition named was
implemented, measured against the mechanism it targets, and rejected.

The nine prior rejections in this family now have one explanation instead of
nine. Each was chasing a share of about a microsecond on a fourteen-microsecond
operation, and the harness each used could not tell the difference between a
share of that microsecond and drift. Exp 182 is the clearest case: it correctly
measured 3.8–5.3% for removing *all* dependency tracking, which is entirely
consistent with the 0.288 µs harvest slice plus the C-side hook — a real
mechanism, but one whose whole ceiling is below the noise of the workloads that
would have to justify it.

**Would reopen if** a candidate attacks the *boundary* rather than the
bookkeeping — something that changes how often a sequential write pays a pair
of isolate wakes, not what rides on the message when it does. Exps 271 and 279
have both already been rejected there, from the completion side and the
transport side respectively, so a third attempt needs a mechanism neither of
them had.

The actionable finding is not an optimization, it is advice the library can
already give. The row directly beneath the losing one in the release suite is
the same hundred inserts issued concurrently: resqlite 0.819 ms against
`sqlite3`'s 0.858 ms. The coalescing pump exp 180 built amortises the boundary
across the group, and concurrent writes already beat the synchronous peer. An
application that awaits each write in turn is paying two isolate wakes per row
by choice.

## Future Notes

- `benchmark/experiments/write_hop_decomposition.dart` is retained. Its
  `--part=floor` lane is the durable gate: any future write-path candidate
  should be sized against the floor before it is built, because the floor is
  what the candidate is actually competing with. `--part=e2e` reproduces the
  release suite's losing row inside one process in about a minute.
- The `--part=wake` lane generalises past this experiment. Any proposal that
  moves work across an isolate boundary should price the boundary in the shape
  it will actually run in — parked, not ping-ponging.
- `archive/exp-284` keeps the in-situ probes. They are eleven lines of
  `Stopwatch` and cost 0.2 µs a write; if a future run needs the same
  breakdown, cherry-pick them rather than rebuilding a synthetic ladder.
