# Experiment 275: which read gets the next free worker

**Date:** 2026-08-19
**Status:** Rejected
**Category:** Moonshot
**Direction:** `stream-rerun-dispatch`, `result-transfer-shape`
**Archive:** [`archive/exp-275`](https://github.com/danReynolds/resqlite/tree/archive/exp-275)
**Benchmark Run:** none — the final branch ships no runtime code. The decision
  evidence is the focused AOT A/B and the release-suite incidence probe in
  [`benchmark/results/2026-08-19T07-40-00Z-exp275-admission-ab.md`](../benchmark/results/2026-08-19T07-40-00Z-exp275-admission-ab.md).

## Problem

[Exp 265](265-inline-main-isolate-select.md) priced the isolate round trip and
found something bigger sitting beside it. On the canonical six-column point
read the hop is 6.3 µs of an 8.4 µs read; but a point read *issued while four
1,000-row reads hold the pool* took 533–1169 µs against 37–52 µs for the same
read run inline (claim 265.2). That second number is not transfer cost. It is
**admission** cost — the time a read spends waiting for a worker — and exp 265
said so explicitly, calling it "the half exps 244/245/246 held constant by
design."

Three experiments have now attacked that headroom and all three were rejected
for reasons that have nothing to do with admission. Exp 265 ran the statement on
the calling isolate and could not bound its work. [Exp 269](269-enforced-inline-reads.md)
added row, byte and VM-step caps and still could not, because one SQLite
operation can consume 26–28 ms below every cap. [Exp 270](270-read-result-cache.md)
answered the read from memory and could not keep it fresh against a second
connection. Every one of them tried to remove the *wait* by removing the
*worker*. None of them asked whether the wait itself is scheduled well.

It is not scheduled at all. [`ReaderPool._dispatch`](../lib/src/reader/reader_pool.dart)
takes the first free worker and otherwise parks the caller on one FIFO queue,
and `_notifyAvailable` hands each freed worker to whoever arrived first. Nothing
in that path knows that one parked request will return one row in 8 µs and the
one in front of it will return ten thousand in a millisecond.

## Hypothesis

**Assumption challenged: reader workers are interchangeable capacity and
arrival order is the right way to ration them.**

The pool has never had a reason to believe otherwise, because it has never had a
cost signal. It does now, and it was built for something else entirely. Exps
[260](260-result-list-presize.md) and [264](264-initial-alloc-size-memory.md)
gave `ReaderPool` a per-SQL `RowSizeMemory` — a main-isolate record of how many
rows every statement has ever returned — so a worker could size its result
buffer in one shot. `_dispatch` already reads that entry, one line before it
picks a worker, and throws away everything in it except the two sizing hints.

`highWater` is a cost oracle sitting on the dispatch fast path. Exp 239's
rejection asked for exactly this and could not have it: *"reopen only with a
reliable private cost signal or independently completable batch members."* The
signal arrived two experiments later, in a different direction, for a different
purpose.

So: classify each read as cheap or costly before dispatch and let that decide
who waits. Two arms, deliberately separated because they cost different things:

- **candA — priority waiter queues.** Split the park queue in two and wake a
  cheap waiter ahead of costly ones. This withholds nothing: the worker is being
  handed back either way, and the only question is who receives it. A cheap read
  finishes in microseconds, so a costly waiter passed over loses almost nothing.
  `maxCheapSkips = 8` bounds how many times in a row that can happen.
- **candB — last-free-worker reservation.** Refuse a costly read the pool's
  *last* free worker while cheap reads are recent, so a point read arriving into
  a large-read burst finds a slot instead of a queue. This does withhold
  capacity, and the experiment's job is to find out what that costs.

Accept an arm if its primary lane reproduces across order-flipped AOT pairs in
two collections **and** the guards stay inside the effect floor **and** the
release-suite incidence probe shows the shape it improves actually occurs.

## Approach

Both arms are internal to `ReaderPool`; no public API changes, and neither arm
can change what a query returns — only when it runs.

A statement is **cheap** when the pool has watched it at least once and it has
never returned more than `cheapRowCap = 64` rows. That is exp 265's cap, chosen
so the two experiments classify the same statements the same way. A statement
the pool has never seen is costly: the alternative is to let an unbounded first
execution jump the queue.

**candA** replaces `Queue<Completer<void>> _dispatchWaiters` with
`_cheapWaiters` and `_costlyWaiters`. `_notifyAvailable` prefers the cheap
queue, counts how many times in a row it has done so, and wakes the head costly
waiter unconditionally once that count reaches `maxCheapSkips`.

**candB** adds the reservation on top. Its whole safety argument is one
condition: a costly read is refused a slot **only when that slot is the last
free one**, which by definition means another worker is busy. So a worker-free
event is always still coming, and the refused request is admitted the moment two
workers are free, because then no single slot is the last. A costly read can be
held behind a busy pool; it can never be held behind an idle one. That invariant
is what let the first version's per-request denial cap be deleted — and deleting
it mattered, because with the cap in place the reservation collapsed after two
wakes and the prototype measured a near-neutral 13% on its own primary lane.

A `reserveWindow = 32` hysteresis disarms the reservation on a pool that has
served 32 consecutive costly reads without a cheap one, so a connection that
only ever issues large reads eventually uses all four workers. The counter
starts *disarmed*, so a pool that has never served a cheap read never reserves.

`reserveLastWorker` is a temporary compile-time constant that separates the two
arms into two binaries. It exists only in `archive/exp-275`.

### Measurement

`benchmark/experiments/reader_admission_priority.dart` is new, and it is the
first harness in the repo that measures what a read *waits* for rather than what
it costs. Eight lanes: two primaries (`point-under-load`, `mixed-queue`), the
load-bearing price guard (`bulk4-mixed`), a hysteresis control (`bulk4-cold`), a
starvation guard (`costly-latency`), and three inert controls.

One correction to exp 265's methodology is load-bearing here. Its
`point-under-load` lane timed ten point reads and reported their sum, which was
right for a candidate that took all ten off the pool. It is wrong for this one:
sticky dispatch ([exp 266](266-sticky-reader-dispatch.md)) parks the whole
sequential run on whichever worker frees first, so a direct probe shows the
first read costing 300–956 µs and reads two through ten costing ~20 µs in
*both* arms. Summing ten dilutes the one read that waits by nine that do not,
and it is why the first measurement of this candidate read −13% instead of
−75%. This harness times the first read only.

Three native-asset-aware AOT bundles (base, candA, candB) built with
`dart build cli` from one harness source, each lane in its own process, 41
samples after 10 warmup, two collections of order-flipped pairs. Cross-worktree
and cross-binary throughout — exp 249's in-process toggle reported a false −27%.

## Results

Full tables in the [receipt](../benchmark/results/2026-08-19T07-40-00Z-exp275-admission-ab.md).
Percentages are candidate against base within the same pass; the four columns
are collection 1 pass 1 / pass 2, collection 2 pass 1 / pass 2.

### The mechanism works, and both halves of it are real

| lane | role | candA | candB |
|---|---|---|---|
| `point-under-load` | primary | +1.9 / −3.4 / −1.6 / −5.0 | **−86.1 / −75.6 / −75.0 / −75.2** |
| `mixed-queue` | primary | **−39.3 / −38.6 / −42.4 / −37.0** | **−79.7 / −79.2 / −80.4 / −80.6** |
| `bulk4-mixed` | guard (price) | +2.6 / +3.6 / +7.9 / −13.1 | **+63.1 / +58.7 / +58.6 / +46.6** |
| `costly-latency` | guard (starvation) | −3.4 / −7.2 / −8.8 / −7.0 | −2.1 / +2.1 / −2.1 / −3.0 |
| `bulk4-cold` | control | +9.4 / +7.8 / +7.7 / −1.3 | +10.1 / +4.6 / −13.8 / −3.0 |
| `point1` | control | +2.3 / +5.3 / +0.6 / +1.6 | −1.3 / +2.2 / +1.6 / −0.2 |
| `int20-10k` | control | −0.6 / +0.6 / +1.1 / +0.7 | −0.3 / −0.0 / +0.7 / +1.3 |
| `concurrent8-cheap` | control | +2.4 / +1.3 / −1.6 / +6.6 | +3.7 / +4.2 / −1.6 / −0.2 |

**A point read into a saturated pool is about four times faster under the
reservation** — 256–374 µs becomes 52–65 µs, against ~20 µs for the same read
on an idle pool. That is most of the way to exp 265's inline number without
running any SQLite on the calling isolate, which is the thing exps 265 and 269
were rejected for. It is the clearest evidence yet that the admission half of
the round trip is separable from the transport half and can be attacked on its
own.

**Eight point reads queued behind eight large ones finish 37–42% sooner from
reordering alone**, and 80% sooner when the reservation is added. Reordering is
also the half that is nearly free: `costly-latency`, the lane written to catch
the large read being starved by the cheap ones jumping it, came out *reproducibly
faster* (−3 to −9%) rather than slower. Serving the short jobs first empties the
queue sooner and the long job is not made to wait for it. `maxCheapSkips` never
had to fire.

**The reservation is not free, and its price reproduced in every pass.** Four
concurrent 1,000-row reads on a pool with recent cheap traffic are 47–63%
slower, because only three of the four workers will take them. `bulk4-cold` —
the identical burst with no cheap read anywhere in the lane — did not move
consistently in either direction, confirming that `reserveWindow` disarms as
designed and that the cost is confined to genuinely mixed workloads. Every
non-parking control is neutral in both arms, so the classification work added to
the dispatch fast path is below the floor.

### The incidence probe closes it

Both arms improve reads that park behind reads of a different cost. So: how
often does that happen? A temporary unguarded counter in `_dispatch` (since
removed), one `run_release.dart --repeat=1` pass over the whole release suite —
chat sim, feed paging, concurrent reads 4×/8×, streaming fan-out, keyed-PK
subscriptions, the diagnostics and memory scenarios — read at every
`Database.close()`:

| dispatches | cheap | cheap that parked at all | cheap that parked behind a costly waiter |
|---:|---:|---:|---:|
| 335,221 | 325,909 (97.2%) | 312 (0.096% of cheap) | **0** |

**The reader pool essentially never queues.** Ninety-seven percent of the
suite's reads are cheap by this classifier; three in every thousand of them ever
wait for a worker at all; and not one of the 335,221 dispatches was a cheap read
parked behind a costly one — the entire population candA reorders. The probe
build ran with the reservation *on*, which parks costly requests more often than
main does, so the zero is an upper bound taken under the condition most likely
to produce a non-zero.

This is not a surprise in hindsight, and it explains something older. Exps 118
and 120 both reported `dispatcherParkedTotal` at zero on every measured stream
workload and the parked-dispatcher signal has been off the candidate list ever
since. This probe puts a number on the general case: it is not that streams stop
parking the dispatcher, it is that four workers are more than the repo's
workloads ever ask for at once.

The stronger evidence would be a downstream application trace, which is what
[exp 272](272-sql-utf8-cache-incidence.md) used for the same kind of question
four days ago. It is not available: the sibling checkout exp 272 traced through
`dependency_overrides` is, on this host, an empty Flutter scaffold with no
`lib/` and no resqlite dependency. The release suite is the best denominator
this run could reach, and it answers zero.

## Decision

**Rejected — both arms, on incidence rather than mechanism.**

The frontier is real. Admission is a genuinely separable half of exp 265's
round-trip price, and the reservation collects about four fifths of it with no
public API change, no SQLite on the calling isolate, no staleness contract, and
no starvation — the four things that killed exps 265, 269, 270 and would have
killed this one. That is the useful result, and it is worth more than the
runtime would have been.

But a scheduling policy is only worth what it schedules, and the measurement
says this one schedules nothing:

- **candA** reorders a population that occurred **zero** times in 335,221
  dispatches across every workload the repo can run. Its −37 to −42% is a real
  effect on a shape the release suite never produces. Under the value gate,
  `operation frequency × eligible share × per-hit saving` has a zero in it.
- **candB** buys a large win on that same absent shape by making four
  concurrent large reads 47–63% slower whenever cheap reads are recent — a
  reproduced, load-bearing regression on a shape the suite *does* run. It is
  also hidden policy of exactly the kind this repo has now rejected four times
  (exps 197, 213, 239, 249): it decides, invisibly and with no way to opt out,
  that one caller's latency outranks another's throughput. Exp 239 was rejected
  for silently converting neighbouring query cost into head-of-line latency;
  candB does the mirror image, and the mirror image is not better.

No runtime code ships. The prototype is preserved at `archive/exp-275`, where
162 focused tests pass against it, and the focused harness is retained.

## Future Notes

**What would reopen this.** One thing only: a workload where cheap reads
actually queue behind costly ones. That means more than four concurrent reads of
genuinely mixed cost on one `Database` — a screen firing a paged list query and
several small lookups in the same frame is the obvious candidate, and no
benchmark in this repo builds one. A downstream trace showing a non-zero
`cheapParkedBehindCostly` is the gate, and `reader_admission_priority.dart` is
already the harness that would judge the candidate. Adopt candA only if that
trace shows the shape at material frequency; candA is the *only* arm worth
reopening, because it withholds nothing and its starvation guard came out
faster.

**What would not.** Do not reopen candB on `point-under-load` alone. Its win is
real and its price is real and they are the same trade exps 197/213/239/249
were each rejected for. If the reservation is ever wanted it belongs behind an
explicit caller-visible mode, which the near-frozen public API does not have
room for.

**A methodology note worth more than the experiment.** Exp 265's
`point-under-load` lane sums ten reads where only the first waits. Sticky
dispatch makes reads two through ten land on an already-free worker, so nine
identical measurements dilute the one that carries the signal. Any future lane
that saturates the pool and then reads must time the first read alone; measured
the other way, this candidate read −13% instead of −75% and would have been
closed as noise.

**The bound this leaves behind.** A four-worker pool serving the repo's whole
representative workload set parks a cheap read three times in a thousand. Before
proposing any further work on *when* a read is admitted — priority, cost
classes, sharding, reservation, work stealing — measure the queue first. There
usually isn't one.
