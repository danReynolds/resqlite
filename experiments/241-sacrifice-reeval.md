# Experiment 241: Re-evaluating Isolate.exit "sacrifice" for the flat ResultSet (rejected)

**Date:** 2026-07-22
**Status:** Rejected
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused. Self-contained transport check
  [`benchmark/experiments/native_vs_heap_send.dart`](../benchmark/experiments/native_vs_heap_send.dart)
  (ships); sacrifice A/B via a reverted `RESQLITE_SACRIFICE_THRESHOLD` compile
  define. Raw tables in
  [`benchmark/results/2026-07-22-exp241-sacrifice-reeval.md`](../benchmark/results/2026-07-22-exp241-sacrifice-reeval.md).

## Problem

For a large read result (`>= 256 KB` estimated), the reader pool uses
`Isolate.exit` **sacrifice**: a zero-copy transfer of the whole result heap to
the main isolate that *kills the worker*, trading a reader respawn for avoiding
the `SendPort.send` graph copy. The policy predates the current architecture,
and its founding measurement ([exp 082](082-message-graph-handoff.md):
`SendPort.send` 1.048 ms vs `Isolate.exit` 2.580 ms on a 10k mixed result) was
taken before two things that undercut the premise:

1. Since Dart 2.15 isolate groups, `SendPort.send` **shares** immutable leaves
   (strings, ints, canonical objects) across the hop and only *copies* the
   mutable structural graph — so send's cost tracks the structural slot count,
   not the total bytes, and text-heavy results barely copy at all.
2. The flat-list `ResultSet` (exp 008) is a shallow structural graph.

So two questions: **(a)** is sacrifice now retirable (send-always)? **(b)** if
not, should its trigger be **structural slot count** (rows × columns), which is
what send actually costs, rather than estimated bytes?

## Hypothesis

Send may now dominate across the practical range because it shares immutable
leaves, leaving sacrifice's respawn cost unjustified for the flat ResultSet. If
a crossover survives at all, it should live at a high *structural* slot count,
not a byte threshold.

## Approach

- **Transport model check** (`native_vs_heap_send.dart`, self-contained): send a
  heap `Uint8List` vs a native-backed view of the same size, to confirm the send
  cost model that the sacrifice decision rests on.
- **Sacrifice A/B** (`sacrifice_crossover.dart`, behind a
  `RESQLITE_SACRIFICE_THRESHOLD` compile define — **reverted**, one process per
  lane): sacrifice (default 256 KB) vs send-only (threshold set to 1 TiB) across
  structural slot counts, on a **numeric** lane (structure only, no shared-text
  confound) and a **text** lane (shared strings).
- A planned retire-A/B (`sacrifice_reeval_ab.dart`) is not shipped: its
  reader-spawn counter (`debugReaderSpawnCount`) was removed by exp 236's cleanup
  pass, stranding it. The crossover harness carries the signal instead.

The `RESQLITE_SACRIFICE_THRESHOLD` define is reverted; the policy is unchanged.

## Results

**Transport model** — median round-trip µs (`native_vs_heap_send.dart`):

| size | native-view send | heap send | ttd(native) |
|---:|---:|---:|---:|
| 142 KB | 18.0 | 13.2 | 13.5 |
| 512 KB | 22.7 | 203.7 | 20.1 |
| 731 KB | 43.7 | 271.5 | 28.5 |

Send cost tracks the **mutable** payload: a heap `Uint8List` copies in full and
blows up with size (203–272 µs), while a native/external-backed view sends
cheaply (23–44 µs). This is the model the sacrifice decision rests on — send is
only expensive to the extent the result graph is mutable, copyable structure.

**Sacrifice crossover** — median µs/select, numeric lane (4 cols; slots = rows×4):

| slots | sacrifice | send |
|---:|---:|---:|
| 2000  | 76.8 | 72.3 |
| 8000  | 238.6 | 226.3 |
| 20000 | 976.5 | 931.9 |
| 32000 | 1194.8 | 1233.8 |
| 48000 | 1856.3 | 1932.6 |

Text lane (200 B strings, 1 col):

| rows | sacrifice | send |
|---:|---:|---:|
| 1000 | 438.3 | 149.4 |
| 3000 | 486.9 | 405.5 |
| 8000 | 1201.6 | 1077.0 |

Send is faster or level across the entire practical numeric range and **wins
everywhere on text** — large, at 1000 rows (149 vs 438 µs), exactly because
strings are shared on send while sacrifice pays a respawn for a copy it never
needed to make. Sacrifice only appears ahead on the numeric lane above **~32k
structural slots**, by a noisy ~3–4%.

## The instrument is confounded — don't over-read the tail

This A/B alternates send and sacrifice within one long-lived pool, and that is
**not a clean comparison**. Sacrifice is a *state-changing treatment*: each fire
destroys a worker, starts a replacement, clears statement/schema caches, and
changes which slot serves the next request. So measurement *i* alters the
environment of measurement *i+1*, and the repeated respawns accumulate heap and
warmup state across the run. Critically, that accumulation biases **toward**
sacrifice (fresh readers keep young-gen heaps clean) — so the ~3–4% tail edge is
measured with the scale already tipped in sacrifice's favor, and its true size is
smaller, possibly zero. This experiment therefore **cannot** establish that
sacrifice has a real edge anywhere; it can only show that send is at least
competitive-to-better across the board and decisively better on text. Peer review
(2026-07-22) confirmed this: send-vs-exit is several distinct *estimands*
(intrinsic transfer, pool-replacement capacity, decode) and no single
through-the-pool harness can isolate them.

## A concrete lead: sacrifice's pool cost may be self-inflicted

While reviewing why sacrifice would ever cost pool throughput, a lifecycle
asymmetry surfaced in `ReaderPool._WorkerSlot`'s reply handler:

- the **non-sacrifice** branch calls `_notifyPool()` **before**
  `pending.complete(result)`, deliberately (its comment: make a worker available
  *before* the caller can request more work);
- the **sacrifice** branch does the opposite — `pending.complete(result)` first,
  `unawaited(spawn(...))` after. And `_pendingCompleter` is a `Completer.sync()`
  (see exp 136), so `complete()` runs the entire `_dispatch` / `_requery` /
  `entry.emit` / `_flushQueue` chain synchronously *before* the replacement spawn
  is even initiated.

So the replacement launch is delayed by arbitrary caller work — exactly the wrong
ordering when the concern is pool capacity, and the opposite of what the sibling
branch already does. If that ordering is the source of sacrifice's replacement-gap
cost, then "sacrifice hurts pool throughput" is an artifact of launch ordering,
not the transfer policy — fixable by an **eager respawn** (start the replacement
before completing the caller, with close/generation guards).

## Outcome

**Rejected — no policy change, but this is a status-quo hold under a confounded
instrument, not evidence that sacrifice earns its keep.** Both candidate changes
are declined *on this evidence*:

- **Retire sacrifice (send-always):** not adopted here — but only because ripping
  out a shipped mechanism on a confounded benchmark is unjustified, not because
  sacrifice was shown to help. The data leans toward retirement; it just isn't
  clean enough to act on yet.
- **Re-trigger on structural slot count:** declined — the crossover is noisy
  (~3–4% at the tail) and estimated bytes already tracks slot count for
  structural results.

Two things are **clean and actionable regardless** of the middle-numeric
question:

1. **Text/shared-leaf misroute** — sacrifice firing on a *byte* threshold for
   shared-string results is a measured ~2.9× loss (send shares the strings;
   sacrifice respawns for a copy that never happens). A routing guard that keeps
   shared-leaf-dominated results on send is a standalone win.
2. **Eager-respawn lifecycle fix** — the ordering lead above.

The clean resolution is a two-experiment split that measures the distinct
estimands separately (peer-recommended, 2026-07-22): **(A)** a prepared-result,
process-isolated handoff harness (result built *before* the timing barrier; one
fresh AOT process per observation; ABBA-matched) to isolate the intrinsic
send-vs-exit transfer; and **(B)** an 8-request / 4-worker barrier burst measuring
queue-wait for requests 5–8 across three lanes — send, sacrifice-current, and
sacrifice-eager-respawn — to isolate replacement-capacity loss. Conclude with
equivalence testing (TOST) against a pre-registered margin rather than waiting for
a noisy median to acquire a sign. Those become follow-up experiments; this run's
lasting contribution is the confound diagnosis, the text-misroute result, and the
eager-respawn lead.
