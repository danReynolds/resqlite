# Experiment 285: The worker that never sleeps

**Date:** 2026-09-08
**Status:** Rejected
**Category:** Moonshot
**Direction:** `stream-rerun-dispatch`, `result-transfer-shape`
**Benchmark Run:** none (rejected; no runtime code ships) — focused evidence in
  [`benchmark/results/2026-09-08T07-20-00Z-exp285-worker-keep-warm.md`](../benchmark/results/2026-09-08T07-20-00Z-exp285-worker-keep-warm.md)
**Archive:** [`archive/exp-285`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-285)

## Problem

Exp 284 measured the write hop instead of guessing at it, and the answer
closed nine experiments at once: of the 6.28 µs between `await db.execute()`
and the identical insert run inline, 5.30 µs is the isolate boundary and
0.98 µs is everything resqlite does (claim 284.1). Its rejection came with an
explicit reopen condition — a candidate that attacks *the boundary* rather
than the bookkeeping.

Inside that boundary it left one number unexplained. The same `executeWrite`
call, same statement, same parameters, same handle, costs 7.612 µs on a
running isolate and 9.380 µs on a worker that was parked until the message
arrived (claim 284.3). About 1.8 µs of every write is the woken side running
cold, and nobody had asked whether it has to be.

## Hypothesis

**Assumption challenged: an idle worker isolate should idle.** Every resqlite
worker — the writer and each reader — handles its message, returns to its
event loop, and lets the VM park its thread until the next one. That is the
obvious thing to do and no experiment has ever questioned it. If the 1.8 µs is
the VM releasing and re-acquiring the worker's thread, then a worker that
never runs out of work never pays it, and the boundary is partly a scheduling
artifact rather than a transport cost.

The frontier this attacks is the one exp 284 named. It changes neither what
rides on the message nor who runs SQLite — only the state of the receiver when
the message lands. Exps 271 and 279 were rejected attacking the same boundary
from the completion side and the transport side; neither had this mechanism.

The risk budget allowed for the prototype, stated before any code: a worker
that stays runnable burns a core, which is a real cost in a library that ships
to phones. A win had to be priced in CPU as well as wall time.

## Approach

Dart gives a library exactly one way to keep an isolate from going idle: leave
something in its event loop. Microtasks are disqualified — a microtask loop
starves the receive port, so the request it is waiting for is never delivered.
That leaves two primitives, and the harness measures both.

`benchmark/experiments/worker_keep_warm.dart` extends exp 284's floor writer —
a hand-rolled isolate writer with none of resqlite's machinery, so the isolate
architecture is priced on its own — with four lanes:

- **`cold`** — the worker as exp 284 left it. Handle, reply, park.
- **`timer`** — a zero-duration `Timer` that reschedules itself for a bounded
  window after each request.
- **`self`** — the same idea through a cheaper primitive: the worker sends a
  token to its own receive port. Tokens and requests share one FIFO queue, so
  a request arriving mid-spin waits behind at most one token turn.
- **`both`** — `self` on the worker *and* the same loop on the calling
  isolate, which parks awaiting the reply exactly as the worker parks awaiting
  the request. Two parked sides means two wakes per write, so this is the lane
  that prices the whole boundary as scheduling.

Each worker times its own `executeWrite` calls, so the cold tax is read inside
the C call rather than inferred from a round trip. Process CPU is read through
`getrusage` around every block, because the entire question for a keep-warm
lane is what the wall-clock saving costs in burnt core.

The shippable half was then built into the real writer isolate — a token loop
on `writerEntrypoint`'s own receive port, with the window handed in through
the spawn arguments — and A/B'd through `await db.execute(...)`. That lane
needed a temporary window field on `Writer`, so it lives at `archive/exp-285`
rather than in the retained harness.

## Results

Full tables in the [receipt](../benchmark/results/2026-09-08T07-20-00Z-exp285-worker-keep-warm.md).

### The cold tax is real, and it is recoverable

The identical C call on a worker that never stopped being runnable, medians of
three passes over 6,400 writes each:

| worker | `executeWrite` µs | Δ |
|---|---:|---:|
| `cold` | 9.606 | — |
| `self` | 8.974 | **−6.6%** |
| `self` (inside `both`) | 8.724 | **−9.2%** |

So the answer to the question is yes: 0.63–0.88 µs of what a parked worker
spends inside SQLite is thread residency, and keeping the isolate scheduled
gets it back. That is smaller than exp 284's 1.8 µs, which was measured
against a single alternating pair rather than a continuously running lane, and
claim 285.1 refines it accordingly.

### Recovering it costs more than it is worth

| lane | µs/write | Δ vs `cold` | CPU µs/write | Δ CPU |
|---|---:|---:|---:|---:|
| `cold` | 12.970 | — | 14.76 | — |
| `timer` | 16.218 | **+25.0%** | 23.35 | +58% |
| `self` | 13.710 | **+5.7%** | 16.69 | +13% |
| `both` | 12.078 | **−6.9%** | 21.80 | +48% |

Warming the worker alone is a net loss at every window tested (5, 15, 40 and
200 µs) and in four independent passes. The tax it recovers inside SQLite is
smaller than the delivery latency it adds: a request that arrives mid-spin
waits behind a token turn, and the spinning worker contends for the core the
caller needs. `timer` loses much worse because its turns cost 6.50 µs against
the self-sent message's 1.85 µs.

The same loop inside resqlite's real writer agrees, and by a wider margin —
**+9.6% at a 15 µs window, +9.0% at 40 µs, +6.2% in a third collection**, with
CPU up 13–17%. A control at a 5 µs window, where the round trip outlasts the
window so the loop exits on its first turn and never engages (`spins=0`),
reads flat: 14.567 against 14.523. The cost and the tax both come from the
loop actually running.

### The win is real and it belongs to the caller

`both` is the only lane that beats `cold`, and it beats it by 6.9% (12.0% in
the fourth pass). Against the `inline` reference it cuts the isolate boundary
from 5.117 µs to 4.225 µs — **17% of the thing claim 284.1 prices at 5.30 µs**.
The boundary really is substantially scheduling rather than transport.

But the half that wins is the caller's, and resqlite may not have it. The
calling isolate in a Flutter application is the UI isolate. A token loop in
its event loop is a continuous stream of events between the framework and its
frames — precisely the main-isolate blocking exp 280 rejected a candidate for
(claim 280.2), in a library whose contract is that database work does not touch
the UI isolate. There is no version of this that ships.

### The corollary is the useful part

`cold`'s caller parks between writes because the benchmark gives it nothing
else to do, and about a sixth of the boundary it pays is its own wake. A real
application's isolate has frames, gestures and futures pending; it is closer
to `both`'s caller than to `cold`'s.

That is a caveat on the one public row where resqlite loses to a peer. The
release suite's `Single Inserts (100 sequential)` lane awaits each write in
turn and does nothing in between, so it charges resqlite for a caller-side
wake that an application issuing the same hundred writes from a live isolate
would not pay. The row is a fair worst case; it is not the typical one.

## Decision

**Rejected.** The mechanism works — a worker kept runnable executes SQLite
6.6% faster, and a boundary with neither side parked is 17% cheaper — and no
form of it can be shipped. Worker-side keep-warm, the only half a database
library controls, is 6–10% slower and 13–17% more expensive in CPU in the
shipping path, reproduced across three windows and nine passes. The half that
wins requires spinning the application's own isolate.

Runtime reverted; prototype and the `e2e` lane at `archive/exp-285`; the four
floor lanes retained as `benchmark/experiments/worker_keep_warm.dart`.

**Would reopen if** the VM offers a way to keep an isolate's thread hot
without keeping the isolate runnable — a spin-before-park window in the
isolate scheduler, or thread affinity for a long-lived isolate. That is a Dart
SDK-shaped change, not a library-shaped one, and this run is the evidence for
what it would be worth: roughly 0.9 µs per request on the worker side, plus
whatever the caller's wake costs an application that is genuinely idle. Short
of that, the boundary is not collectible from inside a package.

**Do not reopen** by making the window adaptive, the token cheaper, or the
loop smarter. The window sweep already covers 5 µs to 200 µs and the shape is
flat: `self` is above `cold` everywhere. The self-sent port message is already
the cheapest keep-alive Dart exposes at 1.85 µs a turn, and the tax it is
buying back is 0.9 µs.

## Future Notes

- `worker_keep_warm.dart --part=both` is the durable instrument. Any future
  proposal about the isolate boundary should run it first, because it
  separates the boundary's two wakes and shows how much of a benchmark's hop
  is the benchmark's own idle caller.
- The keep-alive primitive costs are worth reusing: a self-sent port message
  turn is 1.85 µs on a busy isolate and 0.65 µs on an idle one, a
  zero-duration `Timer.run` turn is 6.50 µs. Anything that proposes to keep a
  Dart event loop occupied is paying one of those.
- A writer isolate spawns on a database's first write, not in
  `Database.open`. The `e2e` lane's first result was inverted by assuming
  otherwise, and the two lanes' spawn order is only visible with a print
  inside the entrypoint. Worth knowing for any future A/B that configures a
  worker at spawn time.
