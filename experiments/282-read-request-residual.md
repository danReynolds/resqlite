# Experiment 282: the missing half of the hop

**Date:** 2026-09-05
**Status:** Rejected
**Direction:** `result-transfer-shape`, `measurement-system`
**Archive:** [`archive/exp-282`](https://github.com/danReynolds/resqlite/tree/archive/exp-282)
**Benchmark Run:** none — the runtime prototype is reverted and no code ships
  in `lib/`, `native/` or `hook/`. The decision evidence is the decomposition
  plus four order-flipped, separate-binary A/B passes in
  [`benchmark/results/2026-09-05T11-30-00Z-exp282-read-request-residual.md`](../benchmark/results/2026-09-05T11-30-00Z-exp282-read-request-residual.md).

## Problem

[Exp 265](265-inline-main-isolate-select.md) measured `select()`'s isolate
round trip at 6.3 µs (claim 265.1), and four experiments since have tried to
collect it by removing the worker — [269](269-enforced-inline-reads.md),
[270](270-read-result-cache.md), [275](275-cost-aware-read-admission.md) — or
by replacing it — [279](279-native-thread-dispatch.md). Exp 279 priced the
messages that carry a point read at 3.22 µs and drew the conclusion this
experiment starts from: the other ~3.1 µs is "resqlite's own per-request work
on the two sides of it" (claim 279.3). It named seven items — the row-hint
lookup and stamping, request construction, the worker's `setBusy` bracket and
request dispatch, `_WorkerSlot`'s completion handler chain, `_record`, and
`blobTransfer.materializeCells` — observed that none had ever been measured
individually, and said the next step was a decomposition rather than a
candidate.

A residual is a subtraction, and a subtraction is only as good as both of its
operands. Nobody had checked either one. Claim 265.1's 6.3 µs was measured
before exps [260](260-result-list-presize.md),
[264](264-initial-alloc-size-memory.md),
[266](266-sticky-reader-dispatch.md), [267](267-stmt-cache-capacity.md) and
[278](278-sync-read-prologue.md) landed; the 3.22 µs came from an echo-isolate
harness that had never been checked against the shipping path.

## Hypothesis

Measure the named items directly, re-measure the hop on current `main`, and
implement whatever the decomposition names. The prediction going in was the
ordinary one: the seven items would turn out to be worth a few hundred
nanoseconds each, one of them would dominate, and that one would be the
candidate.

Decision rule set before building:

- **Accept** an implementation candidate if the end-to-end A/B reproduces its
  predicted saving in both orders with the controls at the collection floor.
- **Reject** if the predicted saving does not appear, and in that case say
  which instrument was wrong, not merely that the lanes were flat.

## Approach

Two harnesses, both retained.

[`benchmark/experiments/read_request_residual.dart`](../benchmark/experiments/read_request_residual.dart)
has three parts. `--part=items` prices the nine per-request items on their own,
batched 20,000 deep because several were expected in the tens of nanoseconds.
`--part=e2e` re-measures the hop as `pool − inline` on a real database, where
the inline arm runs `executeQuery` + `toResultSet` + `materializeCells` on the
calling isolate. `--part=reply` is the transport ladder: one echo isolate, and
lanes that walk from an int-for-int round trip up to the object graph
`_WorkerSlot` actually receives, plus `busy-Nu` lanes where the worker burns a
calibrated amount of time before replying, so the caller parks exactly as it
does while a reader steps SQLite.

[`benchmark/experiments/reader_reply_envelope_ab.dart`](../benchmark/experiments/reader_reply_envelope_ab.dart)
is the end-to-end A/B for the candidate the ladder produced: point, wide,
20-row, 1,000-row and 10,000-row reads, `selectBytes` at one and a thousand
rows, a stream-rerun lane for the `selectIfChanged` path, and a write lane as a
zero-ceiling control. Both arms are separate AOT bundles built with
`dart build cli` from separate worktrees, one lane per process.

## Results

### The seven items are worth 79 nanoseconds

All nine measurable per-request costs, AOT, 20,000 iterations per sample:

| item | ns |
|---|---:|
| `_WorkerSlot.request`'s sync completer | 38.6 |
| `_rowHints[sql]` lookup | 9.6 |
| the `setBusy` bracket (two leaf FFI calls) | 5.9 |
| `RowSizeMemory.record` | 5.2 |
| `blobTransfer.materializeCells` (no wrapped cells) | 4.8 |
| the reply envelope's construction and destructure | 4.7 |
| `_dispatch`'s worker scan | 4.7 |
| `SelectRequest` construction and hint stamping | 2.6 |
| `RawQueryResult.toResultSet` | 2.6 |
| **total** | **78.8** |

Every one of them. Claim 279.3 put "~3.1 µs" of per-request work in the hop;
the work it named is worth **79 nanoseconds**, and the largest single item is a
`Completer.sync()` at 39 ns.

### The hop is half what claim 265.1 says

| lane | µs per read |
|---|---:|
| `db.select()` through the pool | 4.625 |
| the same read inline on the calling isolate | 1.355 |
| **hop** | **3.270** |

Claim 265.1's 6.3 µs is stale by roughly a factor of two. The inline arm here
is *cheaper* than exp 265's — it skips the async prologue, the `_runtime` hop
and the hint bookkeeping that exp 265's inline routing kept — so 3.27 µs is an
over-estimate of what the worker path adds, which makes the gap against 6.3 µs
a floor rather than a point estimate.

Put the two together and the residual claim 279.3 named does not exist: a
3.27 µs hop, 79 ns of per-request work, and 3.18 µs of what the transport
ladder calls transport leaves nothing over.

### Parking the caller is free

The `busy-Nu` lanes leave the caller with nothing to do for a calibrated
interval before the reply arrives, which is what a real read does while SQLite
steps. Subtracting the measured spin cost:

| lane | round trip µs | spin µs | overhead µs |
|---|---:|---:|---:|
| `busy-0u` | 3.165 | 0 | 3.17 |
| `busy-4u` | 4.896 | 2.25 | 2.64 |
| `busy-8u` | 7.217 | 4.51 | 2.71 |
| `busy-20u` | 14.358 | 11.27 | 3.09 |

Flat. Waiting longer does not cost more, so there is no parking or wake premium
hiding in the hop — which also means the ladder's short, tight round trips are
not cheating by keeping the caller hot.

### The candidate the ladder produced

Walking the reply ladder turned up something that looked like a large,
unconditional win. Every lane whose message contained a **record** cost about a
microsecond more than the same message built from ordinary objects:

| reply shape | µs | |
|---|---:|---|
| `reply-echo` — an int | 1.631 | floor |
| `reply-one` — a 1-slot `List` | 1.953 | |
| `reply-list3` — `<Object?>[1, false, null]` | 1.919 | |
| `reply-triple` — `(1, false, null)` | 3.002 | **the same three values as a record** |
| `reply-pair` — `(1, false)` | 3.004 | not per field |
| `reply-nest-list` — a list inside a list | 2.025 | |
| `reply-nest-rec` — a record inside a record | 3.025 | not per record either |
| `reply-bare` — the real `ResultSet`, no envelope | 2.287 | |
| `reply-real` — the same inside the envelope record | 3.096 | what main sends |

A `List` and a record holding identical values differ by 1.08 µs, the penalty
does not scale with field count, and a second record in the same message is
free. `reply-bare` against `reply-real` prices the envelope alone at 0.81 µs on
a reply that is otherwise the real object graph.

Every reader reply travelled in a `(result, sacrificed, error)` record, and
three of the four request types nested a second record inside it —
`selectBytes` a named `({bytes, rowCount})`, `selectIfChanged` a
`(rows, hash, rowCount)`, `selectWithDeps` a four-field one. Against a 4.6 µs
point read, removing them predicted **−17% to −27%**, with `selectBytes` — the
path carrying two — expected to win most.

The candidate replaces all four with small `final` classes and rebuilds the
public record shapes on the main isolate, so no signature changes. It is at
[`archive/exp-282`](https://github.com/danReynolds/resqlite/tree/archive/exp-282);
the whole library's tests pass on it.

The prediction was hardened against every artifact that could have produced it
before the A/B was run, and it survived all of them:

| pair | record µs | class µs | Δ |
|---|---:|---:|---:|
| pre-built and re-sent | 3.096 | 2.287 (`reply-bare`) | +0.81 |
| built fresh per message | 3.632 | 2.042 | +1.59 |
| fresh, with non-canonical TEXT cells | 3.872 | 3.015 | +0.86 |
| fresh, with a non-canonical schema too | 3.916 | 3.062 | +0.85 |
| all of that, worker busy ~2.3 µs first | 5.957 | 4.704 | +1.25 |

### End to end it is worth nothing

Four order-flipped passes, two AOT bundles from separate worktrees, one lane
per process, 41 samples after 8 warmup:

| lane | four passes (Δ%) | median |
|---|---|---:|
| `point1` | +0.3 −1.2 −0.7 −1.0 | **−0.84%** |
| `point1-wide20` | +0.8 −2.3 −0.7 −0.9 | −0.76% |
| `bytes1` | +1.2 +2.3 +0.0 +1.3 | **+1.24%** |
| `bytes1k` | −0.3 −0.4 +2.9 −2.7 | −0.36% |
| `rows20` | +12.1 +0.0 −0.7 +3.0 | +1.49% |
| `rows1k` | −0.8 −0.2 +3.9 −2.9 | −0.51% |
| `stream-rerun` | +1.3 +2.2 −7.2 +3.5 | +1.75% |
| `rows10k` (guard) | −10.6 −3.5 +1.6 −0.9 | −2.18% |
| `writes` (control) | −2.7 −0.1 −0.4 −0.4 | −0.42% |

A predicted −17% to −27% arrives as −0.84%, inside what the zero-ceiling write
control does. `bytes1` settles it: it is the lane that lost *two* records, so
it should have moved most of all, and it is the only primary lane that came out
positive. A separate six-pass collection of `point1` alone, taken earlier, read
−0.1 −0.1 −1.1 −3.6 +0.3 −3.1 against a control of +0.8 +0.1 +6.0 −1.1 −0.7
+1.6 — the same answer.

### Where the microsecond went

The gap is not a resolution problem — 17% is ten times what this collection's
control spans — so one of the two instruments is wrong about the shipping path.
A temporary `Stopwatch` around the real worker's own `eventPort.send`, in both
arms, over 5,800 point reads each, says which:

| arm | what it sends | ns per `send` |
|---|---|---:|
| base | `(result, false, null)` — a record | 1416.8 |
| candidate | `ReadReply(result)` — a class | 1457.3 |

**In the shipping path a record costs nothing.** The same operation the ladder
prices at a microsecond apart measures identical, in the wrong direction by 3%.
The instrumentation was removed after the reading; it exists only in this
record.

The ladder's own numbers point at the same conclusion from the other side. Its
most faithful reply lane, `real-rec` at 3.92 µs, is *larger than the entire
measured hop* of 3.27 µs — and that lane carries only the reply, with an `int`
going the other way. An echo harness that reports a one-way message costing
more than the whole round trip it models is over-stating, and the record lanes
are where the over-statement lives.

Five variations failed to remove it: pre-built versus freshly-allocated
payloads, canonical versus freshly-decoded strings, a canonical versus a
run-time-built schema, a nested record versus a nested list, and an
instantly-replying versus a busy worker. Whatever the echo harness is
measuring, it is robust inside that harness and absent from the library. This
record does not claim to know the VM-level cause; it claims, with two
independent measurements, that the cause is not present in a resqlite read.

## Decision

**Rejected — below signal.** The candidate works, breaks nothing, and is worth
nothing: the largest reproducible move is −0.84% on the smallest read in the
library, and the lane that should have won most came out positive. Runtime
reverted; the prototype is at `archive/exp-282`. Both harnesses are kept.

Three findings outlive the rejection.

**Claim 279.3 is refuted, and the direction it opened is closed.** The seven
items it named are worth 79 ns of a 3.27 µs hop — 2.4%. There is no residual to
attack, and a future runner should not spend a pass looking for one. The hop
that residual was subtracted from is itself half what claim 265.1 records.

**`isolate_transport_price.dart` is not a ruler for the reply path.** Exp 279
left it as "the ruler for anything that changes what crosses the isolate
boundary", and it produced a 17% prediction that the library does not have.
Its lanes remain good for *relative* questions inside the harness — exp 279's
4.8× backing result and exp 281's schema-index numbers both look sound, and
both were confirmed end to end. What it cannot do is price a shipping message
in absolute terms.

**A temporary counter in the real path answered in one run what four
harness variations could not.** It is 20 lines and it can be added to any
question of the form "does this shape cost more".

## Reopen conditions

The candidate reopens only on a Dart SDK where a `SendPort` message containing
a record measurably costs more *in situ* — measured with the temporary counter
above, not with an echo harness. Re-run
`reader_reply_envelope_ab.dart --lane=bytes1` against `archive/exp-282` first:
that lane removes two records and is the most sensitive test there is.

Claim 279.3's residual reopens only if the `--part=e2e` hop and the
`--part=items` total stop adding up — that is, if the hop grows without any
named item growing with it. Both are one command.
