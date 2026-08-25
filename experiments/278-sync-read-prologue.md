# Experiment 278: hand the read straight to the pool

**Date:** 2026-08-25
**Status:** Rejected
**Direction:** `result-transfer-shape`, `stream-rerun-dispatch`, `measurement-system`
**Benchmark Run:** none — no runtime code ships. The decision evidence is the
  mechanism price plus twelve alternating-order lane-isolated AOT passes of
  [`benchmark/experiments/reader_dispatch_stickiness.dart`](../benchmark/experiments/reader_dispatch_stickiness.dart),
  both in
  [`benchmark/results/2026-08-25T14-20-00Z-exp278-async-prologue.md`](../benchmark/results/2026-08-25T14-20-00Z-exp278-async-prologue.md).

## Problem

Every `db.select()` on an open database walks three `async` functions before a
single byte reaches a reader isolate, and each of them costs a suspension that
nothing is actually waiting for.

`Database.select` is `async` and opens with `final ... = await _runtime;`.
`_runtime` is the one-shot future that completes when the reader pool, stream
engine and writer have spawned; after `Database.open` returns it is resolved
forever, so that line is an `await` on an already-resolved future — which still
suspends the function and resumes it through the microtask queue. It then
`return`s another future from inside an `async` body, which costs the caller a
second one.

`ReaderPool.select` is `async` and awaits `_dispatch`. `_dispatch` is `async`
too, and its whole reason for being a coroutine is the parking loop it runs when
every worker is busy — `await waiter.future` on a `_dispatchWaiters` entry.
[Exp 275](275-cost-aware-read-admission.md) counted how often that loop is
reached: one `run_release.dart` pass over the whole suite issued **335,221**
reader dispatches, of which **312** parked at all (claim 275.1). Better than 99.9%
of reads pay for an async frame and a suspension to reach a `return` on the
first scan.

None of this is where a read's time goes — claim 265.1 puts 6.3 us of an 8.4 us
canonical point read in the isolate round trip itself. But it is per-call
overhead on the one operation applications issue most, and it is paid whether
the read returns one row or ten thousand, so it is largest exactly where reads
are smallest.

[Exp 171](171-resolved-runtime-cache.md) tried the `_runtime` half of this in
June and rejected it below the noise floor. Two things have changed. Its
measurement was `writer_pipelining.dart` — a **write** harness, 2,000 sequential
`execute()` calls at ~15 us each summed into a ~32 ms median, whose per-round
spread swallowed the effect; it never measured a read. And its own reopen
condition asked for "a measurement system that can resolve sub-1us per-call
deltas", which exps 264, 266 and 275 then built: lane-isolated AOT bundles, one
process per lane per arm, alternating collection order, `ab_drift_check.dart`
verdicts. That apparatus resolved -13.5% on a 1-row 6-column point read
(claim 264.1) and separated a 20 us effect from a 300 us one (claim 275.4).

## Hypothesis and decision rule

Give the open-database read path no async frame of its own: `Database.select`
returns the reader pool's own future, and `ReaderPool._dispatch` returns the
worker's own future when the first scan finds a free slot. The caller's single
`await` then attaches, through one ordinary future, to the sync completer the
worker's reply port resolves.

Declared before measuring, with the *shape* as the gate rather than a single
number, because a fixed per-call saving has a signature:

- **Primary lanes** are the steady-state small reads, where a fixed cost is the
  largest fraction of the read: `point1` (200 sequential point reads per
  sample), `point1-wide20` (the same, 21 columns), `mixed6-20` (a 20-row page).
- **Shape prediction.** The saving must **decay monotonically with result
  size** — largest on `point1`, smaller on `mixed6-20`, near zero on
  `mixed6-1k`, absent on `mixed6-10k`. A "win" that did not decay would not be
  this mechanism and would not license the change.
- **Accept** only if the primary lanes reproduce at or above **5%** faster in
  both order-flipped pairs of both collections. Below that the change is not
  worth carrying a split dispatch method for, however clean the mechanism.
- **Kill conditions.** `conc4` or `conc8` regresses (the parking loop moved to
  `_dispatchParked` and fairness or wake ordering broke), `mixed6-10k`
  regresses (the sacrifice path), `bytes-first8-newsql` regresses (`selectBytes`
  now wraps its result through `then` instead of an `await`), or peak RSS rises.

## Approach

No public API change, no new semantics, no new state. Three edits:

1. `Database` gains `_DatabaseRuntime? _resolvedRuntime`, assigned inside the
   same `Future.sync` body that completes `_runtime` — so no caller can observe
   a partially built runtime through it. This is exp 171's field, kept because
   the rest of the change needs a synchronously readable runtime to exist.
2. `Database.select` and `Database.selectBytes` stop being `async`. On an open
   database with a resolved runtime they call the pool directly; `select`
   returns the pool's future unchanged, and `selectBytes` keeps a single `then`
   because it still has to wrap the reply in a `BytesResult`. Every other
   case — runtime not yet resolved, database closed, `selectBytes` called
   inside a transaction, Tracelite profile mode — routes to a private `async`
   sibling that keeps the original body verbatim. That is deliberate: those
   paths deliver their failures as *failed futures*, not synchronous throws,
   and moving the throw into the caller's stack would be an API change wearing
   a performance costume.
3. `ReaderPool._dispatch` stops being `async`. It keeps the first scan and
   returns `slot.request(request)` directly; when no slot is free it hands off
   to `_dispatchParked`, which owns the `while (true)` parking loop, the
   `_dispatchWaiters` completer, the profile counters and the post-wake
   `_closed` re-check unchanged. The closed-pool rejection becomes an explicit
   `Future.error` so it stays asynchronous.

`execute`, `executeBatch` and `transaction` read `_resolvedRuntime` instead of
awaiting `_runtime`, which is exactly exp 171's change and nothing more; the
write path keeps its `async` frames because it has real post-reply work
(dirty-set harvest, stream invalidation) to do.

## Results

### The prologue prices at ~108 ns, and that settles it

Before the A/B, a new harness —
[`benchmark/experiments/async_prologue_price.dart`](../benchmark/experiments/async_prologue_price.dart),
no SQLite, no isolates, no resqlite code — timed a sync completer resolved from
a separate microtask, reached through four different amounts of async plumbing.
Five AOT runs of 21 samples × 200,000 calls; the absolute figures carry the
completer allocation and the loop, so only the differences are meaningful.

| shape | ns/call | Δ vs `direct` |
|---|---:|---:|
| `direct` — the completer's future, nothing between | 176.0 | — |
| `resolved` — one already-resolved future awaited first | 246.7 | **+70.7** |
| `frame1` — one `async` forwarder | 210.6 | **+34.6** |
| `frame3` — resolved await + three `async` forwarders | 318.7 | **+142.7** |

`frame3` is the shape the read path had; `frame1` is what the candidate leaves.
**The candidate removes about 108 ns per read.** Against the repo's canonical
point read at ~5.4 us that is a ceiling of **2.0%**; against a 20-row page 1.1%,
against a 1,000-row read 0.05%. The decision gate declared above is 5%. No
implementation of this idea can reach it, because the thing being removed is not
big enough — and that is knowable in ten minutes, before any candidate exists.

The same probe corrects exp 171's arithmetic. It estimated the `await _runtime`
hop at "~1–2 us per call" and derived 6–12% of headroom on a 2,000-call
sequential write burst from that estimate. The hop measures **70.7 ns** — 14–28×
smaller. Exp 171's empty result was the right answer to a question whose
headroom never existed; it just could not tell the difference between "the
saving is below my floor" and "the saving is a twentieth of what I assumed".

### End to end, the lanes agree by being flat

Twelve alternating-order lane-isolated AOT passes, 121 samples per lane per arm,
in two collections of six; full tables, per-pass deltas, CVs, peak RSS and
`ab_drift_check.dart` verdicts in
[`benchmark/results/2026-08-25T14-20-00Z-exp278-async-prologue.md`](../benchmark/results/2026-08-25T14-20-00Z-exp278-async-prologue.md).
Collection 1 ran at 76.7% CPU idle and load 4.77; collection 2 ran into a busier
host (load 8.64, per-lane CVs to 100–290%) and is reported in full rather than
dropped.

| lane | role | collection-1 passes | 12-pass median |
|---|---|---|---:|
| `point1` | primary | +0.1 / -4.0 / +2.5 / +6.2 / -2.7 / -2.5 | -2.1% |
| `point1-wide20` | primary | -6.8 / +1.6 / +1.1 / -0.3 / -0.1 / -8.8 | +0.5% |
| `mixed6-20` | primary | +1.9 / +0.2 / +13.4 / -0.6 / +7.2 / +3.3 | -0.2% |
| `mixed6-1k` | control (effect ≈ 0.05%) | +2.0 / +4.9 / +1.1 / +0.9 / +0.9 / -1.1 | +1.0% |
| `mixed6-10k` | control (effect ≈ 0.004%) | +0.0 / -1.2 / -2.7 / -8.5 / -2.3 / -0.1 | -0.8% |
| `conc4` | guard (parking split) | -7.8 / +4.6 / +3.0 / -2.1 / -5.9 / -4.7 | -3.4% |
| `conc8` | guard (parking split) | -1.4 / -2.9 / +1.7 / +1.4 / -6.6 / -6.5 | -4.3% |
| `bytes-first8-newsql` | guard (`selectBytes` `then`) | -3.5 / -2.5 / +9.2 / -8.4 / -3.8 / -1.3 | -1.9% |

Not one primary-lane pass pair reproduced a win: fourteen of the eighteen
primary scenarios classify neutral, two drift-suspected, and the two that
classify REPRODUCED point the *wrong* way. Pooled across all twelve passes every
lane lands between -3.5% and +1.2% — **including `mixed6-10k` at -2.9%, where
the candidate's ceiling is 0.004%**. That control is the ruler: roughly 3% of
apparent movement in this collection is apparatus, and `point1`'s pooled -3.0%
is the same number as the lane that cannot have changed.

The shape prediction is also unmet, which matters more than any single figure. A
fixed per-call saving has to shrink as the read grows, and here `mixed6-20`
(+0.4% pooled) is not smaller than `point1` (-3.0%) in any ordered way —
everything is flat and everything sign-flips.

`first32-newsql` is the only lane that looks like something, at -9.9% median
with nine of twelve passes negative. The mechanism rules it out rather than the
statistics: that lane times 32 executions at ~6.6 us each, so the prologue is
worth the same ~2% there as on `point1`, which read -2.1%. A genuine 10% on
`first32` with `point1` flat is not this change. Its two collection-2 pairs also
reverse sign, and its CV runs 31–46% against `point1`'s 11–13%.

### The guards are clean

The restructure itself costs nothing. `conc4` and `conc8` — which exist to catch
a broken `_dispatchParked` hand-off — read neutral-to-faster with sign flips,
and `test/reader_pool_test.dart`'s deterministic assertion (four un-awaited
reads must leave `availableWorkerCount` at zero) passes. `mixed6-10k` exercises
the sacrifice path unchanged. `bytes-first8-newsql` covers `selectBytes`'s new
`then` wrapper. Peak RSS moves nowhere; `mixed6-1k`'s 42.4 vs 30.1 MB median is
a bimodal GC artefact both arms produce. All 503 tests pass, `dart analyze` is
clean.

## Decision

**Rejected — below signal, and below it by a knowable margin.** The candidate
works: it removes three async frames and a resolved-future await from every
open-database `select()`, keeps every failure path asynchronous, and breaks
nothing. It is worth ~108 ns per read, which is 2.0% of the smallest read the
repo can measure and 0.004% of the largest, against a 5% gate. The end-to-end
lanes confirm that by being indistinguishable from their own controls.

All runtime code is reverted. What is kept is the price:
`benchmark/experiments/async_prologue_price.dart` is ~110 lines with no
dependency on resqlite, and it is the instrument that would have closed both
exp 171 and this experiment before either wrote a line of `lib/`. That earns its
place — the async-overhead-removal family (exps 145, 148, 151, 159, 171, 278) is
the most frequently revisited dead end in the signal map, and it has been costed
by intuition every time.

The exact prototype is preserved at
[`archive/exp-278`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-278)
so a future runner can cherry-pick it rather than rewrite it.

### Reopen conditions

Not on a new harness or a quieter host — the ceiling is arithmetic, not
measurement. Reopen only if one of the terms changes:

- **The numerator.** A Dart SDK release that makes an `async` frame materially
  more expensive, or a resqlite change that adds layers rather than removing
  them. Re-run `async_prologue_price.dart` on the new SDK; if `frame3 - frame1`
  crosses ~300 ns the arithmetic changes.
- **The denominator.** A read path an order of magnitude cheaper than today's
  5.4 us point read — which means the isolate round trip is gone, not trimmed.
  Exps 265, 269 and 271 all failed to remove it; if one ever succeeds, the
  prologue becomes a much larger share of what remains and should be revisited
  in the same run.

Do **not** reopen this as "retry with a better harness". Two experiments have
now spent a run each on this family; the third should start with the probe.
