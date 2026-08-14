# Experiment 271: catch the writer before the port

**Date:** 2026-08-14
**Status:** Rejected
**Category:** Moonshot
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** Focused AOT B-A-A-B in
  [`benchmark/results/2026-08-14T14-57-54Z-exp271-writer-completion-catch.md`](../benchmark/results/2026-08-14T14-57-54Z-exp271-writer-completion-catch.md),
  with complete samples in the adjacent
  [JSON artifact](../benchmark/results/2026-08-14T14-57-54Z-exp271-writer-completion-catch.json).

> **Rejected.** The shared-memory signal works, but waiting for it does not.
> A 24 us bounded poll caught about 70% of eligible completions in a focused
> diagnostic, yet the decisive AOT comparison reproduced an 84%/63% regression
> on no-op writes and a 205%/368% regression on errors. Point updates and
> inserts each won in only one order. The exact prototype is preserved at
> `archive/exp-271` (`cbc6a7f`); all runtime changes are reverted from the
> publication branch.

## Problem

[Exp 159](159-writer-pipelining.md) removed per-write port allocation and
pipelined concurrent standalone writes.
[Exp 180](180-group-commit-request-batching.md) then amortised concurrent
bursts without changing their independent commits.
[Exp 184](184-writer-residual-resplit.md) re-measured the remaining sequential
path and attributed 55-70% of representative writer wall to residual
request/round-trip time. It named shared memory as the remaining structural
lever.

That conclusion had not been tested. Native pointers already cross Dart
isolates as integer addresses, and resqlite already relies on C11 atomics. A
worker can therefore publish a completed scalar result into process-visible
memory without moving SQLite onto the caller isolate — avoiding exp 265/269's
unbounded-caller-work failure. The open question was whether briefly waiting for
that publication costs less than letting Dart deliver the reply-port event.

## Hypothesis

**Assumption challenged: a successful sequential write must wait for its
writer-isolate reply event after SQLite and dependency harvesting have already
finished.**

The candidate would be accepted only if it improved sequential no-stream writes
by at least 15% in both run orders. A bounded per-turn budget had to prevent a
chain of caught futures from monopolising the main isolate, and every miss,
error, transaction, batch, concurrent group, stream, profile, and close path had
to retain existing semantics.

## Approach

The prototype allocated one native completion slot per `Writer`. The slot held
an atomic ready flag, affected-row count, last insert ID, and profile time. A
single eligible `ExecuteRequest` carried its address to the writer isolate.

After SQLite returned and native dirty dependencies were drained, the worker
release-published the scalar payload, then sent the same canonical
`ExecuteResponse` as main. The main isolate synchronously acquire-polled the slot
for at most 24 us per attempt, 48 us and two attempts per event-loop turn. A hit
completed the caller with empty dependencies — eligibility required no active
streams — and left its already-completed completer in the FIFO. The later port
reply removed that tombstone. A miss simply awaited the canonical reply.

The scope was intentionally narrow:

- SQLite and dependency harvesting stayed exclusively on the writer isolate;
- active streams, profile mode, transactions, batches, and coalesced groups
  bypassed the slot;
- errors never published and used the canonical typed error reply;
- the worker constructed the canonical Dart response before publishing, so no
  fallible allocation remained after success became visible;
- mailbox reuse occurred only after an acquire-read hit or the matching
  canonical reply, making one ready bit sufficient without an epoch;
- close waited for the FIFO `CloseRequest` reply before freeing native memory.

The archived tests exercise scalar result fidelity, caught-reply tombstones,
constraint failure and recovery, active-stream bypass, a stream registered
after a slow scalar miss, close, profile bypass, and 50,000 cross-isolate
release/acquire payload generations. Adversarial review also identified a
completion-order question for an earlier canonical-only batch followed by a
later caught scalar; the prototype was rejected before expanding its protocol
to promise that ordering.

## Results

### The signal can be caught

A 5,000-write diagnostic at the default budget attempted 3,818 polls and caught
2,669 completions: a **69.9% catch rate**, with 17.8 us mean polling time. In
that candidate-only comparison, polling improved 38.33 to 35.14 us per write
versus compiling the same runtime with polling disabled — an 8.3% mechanism
effect, below the 15% product gate.

This is the useful distinction: observing a native completion early is
possible; doing useful work by busy-waiting for it is not established by the hit
rate.

### End-to-end AOT rejects it

Native-asset-aware AOT bundles ran baseline B1, candidate A1, candidate A2, then
baseline B2. Medians are microseconds per operation; each delta is paired to its
adjacent order baseline.

| lane | B1 -> A1 | delta | A2 -> B2 | delta |
|---|---:|---:|---:|---:|
| no-op update | 5.921 -> 10.900 | **+84.1%** | 16.615 -> 10.213 | **+62.7%** |
| point update | 16.917 -> 19.453 | +15.0% | 25.585 -> 31.515 | -18.8% |
| small insert | 16.052 -> 17.225 | +7.3% | 19.538 -> 21.935 | -10.9% |
| constraint error | 11.823 -> 36.073 | **+205.1%** | 40.010 -> 8.542 | **+368.4%** |

No target win reproduced. The two favorable point/insert observations occur in
only the host's slower second baseline and reverse sign in the first order.
No-op and error regressions reproduce without relying on that noisy pass.

Continuous-write throughput tells the same story: 53,204 -> 18,314 writes/s in
the first pair (-65.6%) and 45,892 -> 28,757 in the second (-37.3%). Bounded
polling still consumed wall and CPU.

The timer callback stream stayed live throughout. The requested 16,667 us
period was truncated by this Dart VM to an effective 16 ms heartbeat: A1
delivered 278 of 279 effective deadlines (one missed), while A2 delivered
279/279. Their p99/max gaps were 21.094/33.609 ms and 19.803/25.729 ms. The
original `missed_frames` counter is discarded because it divided elapsed time
by the requested rather than effective period; later callbacks may also arrive
less than one period apart, so aggregate count can hide an earlier long gap.
These runs rule out prolonged heartbeat starvation, not individual misses. The
retained harness now requests 16 ms explicitly and reports complete callback
gaps plus a conservative long-gap lower bound.

Every tested correctness guard passed: the active stream reached its final
value, 672 constraint errors retained SQLite code, SQL, and parameters, and the
writer recovered. Those receipts cover the tested paths; they neither redeem
the cost nor resolve the documented earlier-batch/later-catch completion-order
question.

### A longer catch window is worse

A complete 32 us AOT arm measured 21.702 us no-op, 37.214 us point update,
34.617 us insert, and 44.833 us constraint error — worse than both baselines on
every decision lane. Its timer callback p99/max gaps were 16.861/19.945 ms; a
corrected effective-deadline count was 279/279. A bounded longer spin merely
buys more opportunities to pay for waiting.

The error result explains why tuning cannot repair the general shape. A failed
statement never publishes, so it burns the complete polling budget before the
canonical error arrives. A success predictor or per-SQL error latch would add
policy, state, and new failure modes to rescue a design already losing its
cheapest success lane.

## Decision

**Rejected.** Exp 271 updates exp 184's interpretation: a large *percentage* of
writer wall being residual does not imply that active waiting can remove it.
The current AOT reply-port path completes the cheapest write in 5.9-10.2 us,
below the candidate's 24 us window. Shared-memory readiness is not itself a
wakeup primitive, and a catch percentage is not an end-to-end value metric.

No native ABI, build-hook, writer, worker, diagnostic, or test-only runtime
change is kept. The public-API harness remains as the durable sequential-write,
error, and heartbeat-timer gate. The exact prototype remains at
`archive/exp-271` for inspection, not as a shipping base.

### Reopen conditions

Do not retry a longer spin, a larger per-turn budget, or an error predictor.
Reopen only if one of these changes the architecture:

1. a completion primitive can wake or park the caller without burning its
   isolate time;
2. Dart exposes cross-isolate shared state with a wait/notify operation whose
   overhead is measured below current port delivery; or
3. representative downstream evidence shows a sequential writer floor far
   above the 6-32 us AOT range measured here.

Any successor must retain both-order AOT comparison, constraint-error fidelity
and latency, continuous 16 ms heartbeat delivery, active-stream semantics,
transactions, coalesced groups, slow misses, and close/free ordering.
