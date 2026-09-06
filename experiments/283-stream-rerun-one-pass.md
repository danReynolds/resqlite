# Experiment 283: the second walk over the same rows

**Date:** 2026-09-06
**Status:** Rejected — the mechanism works and the reason it still loses is the finding
**Direction:** `stream-rerun-dispatch`, `result-transfer-shape`, `measurement-system`
**Archive:** [`archive/exp-283`](https://github.com/danReynolds/resqlite/tree/archive/exp-283)
  (runtime prototype), [`archive/exp-283-census`](https://github.com/danReynolds/resqlite/tree/archive/exp-283-census)
  (rerun census counter and its driver)
**Benchmark Run:** none — the runtime prototype is reverted and no code ships in
  `lib/`, `native/` or `hook/`. The decision evidence is the pass-price
  decomposition, eight order-flipped separate-binary A/B passes, and the release
  suite run that caught the trade-off (§6).

## Problem

A reactive stream re-runs its query whenever a write dirties one of the tables
or columns it depends on, and the engine has to decide whether the fresh result
is worth emitting. [Exp 075](075-native-hash-selectifchanged.md) made that
decision cheap for the common case: `resqlite_query_hash` steps the bound
statement to completion in C and folds every cell into an FNV digest, so an
unchanged stream costs one SQLite pass and no Dart objects at all (claim 075.1).

When the digest *does* move, the same statement is stepped a second time
through `decodeQuery` to build the result. That second walk has been there
since exp 075 and has never been measured. It is not obviously avoidable —
the point of hashing first is that you do not know whether you will need the
result until the hash is finished.

Except resqlite already has a decoder that does both in one pass.
[Exp 097](097-one-pass-initial-stream-hash.md) added
`resqlite_step_row_hash`, which fills the cell buffer *and* folds the same
masked-FNV accumulator, and `decodeQueryWithInitialHash`, which drives it. That
pair has shipped since April, but only on the initial-registration path: exp 097
deliberately left reruns on the hash-only path so an unchanged rerun could skip
Dart decoding entirely. [Exp 228](228-canonical-stream-hash.md) later hardened
the digest's contract and named this exact reopening — early rejection may be
revisited if "the changed-result decode can produce the canonical hash without
another full pass."

It can. The question this experiment asks is whether a stream can be told, in
advance, which of the two shapes its next rerun will be.

## Hypothesis

A stream's reruns do not change at random. A partition under active writes
changes on rerun after rerun; a stream nobody is writing to is unchanged for
thousands of reruns in a row. If that autocorrelation is strong, the previous
rerun's outcome is enough of a predictor: when it changed, decode during the
hash pass and skip the second walk; when it did not, keep today's behaviour.

For that to be worth anything, three things have to hold, and all three were
open questions before this run:

1. changed reruns have to be a real share of a representative stream workload;
2. the second walk has to be a real share of a changed rerun;
3. the previous outcome has to actually predict the next one.

A fourth condition went unstated, which is the one that ended up deciding the
experiment: the second walk has to be *only* a cost. It is not (§6).

## Approach

`lib/src/stream_engine.dart`, `lib/src/reader/reader_pool.dart` and
`lib/src/reader/read_worker.dart`. No native code, no public API change.

`StreamEntry` gains one `bool lastRerunChanged`, set from whether the rerun that
just completed returned rows. `ReaderPool.selectIfChanged` forwards it as
`SelectIfChangedRequest.decodeFirst`, and `executeQueryIfChanged` grows a second
arm: when the flag is set it calls `decodeQueryWithInitialHash` — exp 097's
decoder, unchanged — compares the digest it returns, and discards the built
result if the digest and row count both matched after all.

The flag lives on the main isolate for the reason
[exp 260](260-result-list-presize.md) established for the row hint: a reader
worker sees only the reruns routed to it and is destroyed outright by the
sacrifice path, so a worker-local memory of a stream's outcome sequence would be
sampled and periodically erased. The stream engine sees every rerun of every
stream it owns.

The predictor is deliberately the smallest one that can work. It arms on a
single changed rerun and disarms on a single unchanged one, so a stream that
alternates never arms, and the worst case for a stream in a run of changes is
one wasted decode at the end of the run.

Nothing else moves. The hash-only arm, the row-count guard, the canonical
digest stored in `lastResultHash`, and the sacrifice decision are all
unchanged, and the two arms are interchangeable at every point: the digest exp
097's decoder folds is the same value `resqlite_query_hash` returns for the same
rows, which is what keeps a baseline minted by one arm usable by the other.
`test/query_decoder_test.dart` asserts that directly, in both directions.

## Results

### 1. What a stream workload's reruns actually look like

Nothing had ever counted the reruns the release suite's three reactive lanes
issue, or what share of them change. A temporary counter in `_requery`
(preserved with its driver at
[`archive/exp-283-census`](https://github.com/danReynolds/resqlite/tree/archive/exp-283-census),
removed before merge) answered both, on scaled reproductions of each lane's
stream and write shape:

| lane | reruns | of a possible | changed |
|---|---:|---:|---:|
| high-cardinality fan-out — 100 streams × 100-row partitions, 200 writes | 847 | 20,000 | **56.4%** |
| keyed PK — 50 streams on one PK each, 200 random-PK writes over 10k rows | 1,071 | 10,000 | 0.28% |
| feed — one latest-50 stream, 100 like-count writes | 100 | 100 | 0% |

Two things in that table were not known. Per-stream coalescing is far more
effective than the suites' own docstrings assume — the fan-out lane issues 847
reruns where the arithmetic says 20,000, because a stream dirtied again while
its rerun is in flight reruns once more, not once per write. And the fan-out
lane's reruns are **not** overwhelmingly unchanged: 56% of them change. The
"99-of-100 unchanged" reading of that workload describes writes, not reruns.

The same run priced the fan-out tax: the identical 200-write burst costs
10.6 ms with nothing subscribed and 112.6 ms with the 100 streams attached.

### 2. What the second walk costs

`benchmark/experiments/stream_rerun_pass_price.dart`, no pool, no isolates, no
message hop — 15 samples × 400 iterations per arm, arm order rotated per sample:

| shape | hash | decode | hash+decode (today) | one pass | saved | miss tax |
|---|---:|---:|---:|---:|---:|---:|
| 100 rows × 2 cols | 4.54 | 6.17 | 10.72 | 6.50 | **−4.22 µs (−39.4%)** | +1.95 µs |
| 50 rows × 4 cols, TEXT | 4.33 | 6.93 | 11.27 | 7.36 | **−3.91 µs (−34.7%)** | +3.02 µs |
| 1 row × 3 cols | 1.02 | 1.13 | 2.16 | 1.19 | **−0.97 µs (−44.8%)** | +0.17 µs |
| 1,000 rows × 2 cols | 36.05 | 51.90 | 87.94 | 53.08 | **−34.86 µs (−39.6%)** | +17.03 µs |

Folding the digest into the decode costs 0.6–1.2 µs; the pass it removes costs
4.5–36 µs. A changed rerun's SQLite-and-decode work falls by roughly two fifths
at every width tried. The miss tax — a decode built and thrown away — is
17–70% of an unchanged rerun, so the predictor is not decoration.

Read this table with §6: the removed pass is not pure overhead. It re-reads the
database, and re-reading turns out to buy something.

### 3. Whether the predictor is right

Measured on the shipping candidate with a temporary hit/miss counter, under the
A/B harness's concurrent write bursts (13 bursts per lane):

| lane | reruns | changed | armed | hits | misses |
|---|---:|---:|---:|---:|---:|
| `fanout` | 2,699 | 59.8% | 1,534 | 880 | 654 |
| `fanout-wide` | 624 | 80.0% | 479 | 370 | 109 |
| `keyed-pk` | 1,424 | 2.6% | 36 | 16 | 20 |
| `feed` | 54 | 35.2% | 18 | 6 | 12 |

`feed` changes more often here than in §1 because the A/B harness ends every
burst with a sentinel write that must move the watched page; its 100 ordinary
writes still never do.

The two guard lanes arm 36 and 18 times across a whole collection — the
predictor is not merely wrong there, it is barely on, which is what makes them
inert rather than merely balanced. Where it is on, it is right 57% and 77% of
the time, against an exchange rate of roughly 2:1 in the saved pass's favour.

### 4. End to end

`benchmark/experiments/stream_rerun_one_pass_ab.dart`, two AOT bundles built
from separate worktrees (exp 249: never A/B stream dispatch with an in-process
toggle), one lane per process, 41 samples after 8 warmup, arm order flipped
between passes. Δ is candidate against baseline within each pass; **B**/**C**
marks which arm ran first.

| lane | 1 B | 2 C | 3 B | 4 C | median | pooled | drift verdict (3/4) |
|---|---:|---:|---:|---:|---:|---:|---|
| `fanout` — 100 streams × 100-row partitions | −2.4 | −3.6 | +5.2 | −5.1 | −3.0% | −1.7% | drift-suspected |
| `fanout-wide` — 20 streams × 1,000-row partitions | −10.8 | −11.7 | −11.5 | −9.2 | **−11.1%** | **−11.3%** | **reproduced** |
| `keyed-pk` (guard) | −1.5 | −11.6 | +2.8 | −1.5 | −1.5% | −4.2% | neutral |
| `feed` (guard) | −2.4 | +0.8 | −3.1 | −2.0 | −2.2% | −2.0% | neutral |
| `writes` (zero-ceiling control) | +16.5 | −2.7 | +6.0 | +1.4 | +3.7% | +5.6% | neutral |

Each sample issues its write burst concurrently and then times a sentinel write
through to the one stream it must change. Every rerun the burst scheduled —
including the unchanged majority, which emits nothing and cannot be waited on
directly — has to clear the queue before the sentinel's own rerun runs, so the
sentinel prices the backlog. An awaited write-by-write burst cannot: each rerun
overlaps the next write's latency and the wall reads as the write burst. That
was the first metric tried here: a 25-sample pass of the awaited variant put
`fanout` at +1.2% while the mechanism was worth 39% of a changed rerun, which is
why it was replaced rather than sampled harder.

**The sentinel has to watch a partition the burst cannot touch,** and the first
version of this harness did not. Its sentinel stream was an ordinary partition
that the burst also wrote to, and its completer was armed before the burst
started, so whichever of that stream's reruns fired first ended the sample —
measuring a random prefix of the backlog rather than the whole of it, biased
toward whichever arm finished changed reruns faster. That version reported
`fanout` at −12.5% pooled and `fanout-wide` at −5.7%; both figures are
withdrawn. The table above is from the corrected harness, which reserves
partition 1 for the sentinel, excludes it from the burst, and arms the completer
only after the burst has been issued. The defect was found in review of this
experiment's own PR, not by the collection.

The corrected reading is narrower and differently shaped. The lane that
reproduces is the **wide** one — 1,000-row partitions, where §2 prices the
removed pass at 34.86 µs — at a consistent −9% to −12% in all four passes.
The 100-row lane, where the same pass is worth 4.22 µs, does not clear the
collection's floor: the zero-ceiling control moved +16.5% in its worst pass, and
`fanout` reverses sign across the order flip. The mechanism scales with the
result size it re-walks, and at 100 rows there is not enough of it to see.

**Host caveat.** Load average ran 1.8–14.1 across the session — `mediaanalysisd`
held a core for much of it, and the corrected collection above was taken in the
quietest window available (1.8–4.1). The zero-ceiling `writes` control is the
collection's own floor: it moved +16.5% in its worst pass and +3.7% at the
median. That is why only `fanout-wide`, consistent at −9% to −12% in every pass
and classified reproduced, is read as an effect, and why `keyed-pk`'s single
−11.6% pass is read as the same floor rather than as a guard failure.

### 5. The win is smaller than the pass price predicts

With the corrected harness the arithmetic runs the ordinary way. `fanout-wide`
issues 48 reruns per burst, §3 counts 370 hits and 109 misses over 13 bursts,
and §2 prices those at 34.86 µs and 17.03 µs — a modelled **849 µs per burst**.
The measured saving is `3.564 − 3.163`, or **401 µs per burst**: the candidate
delivers about 47% of its isolated mechanism end to end, which is the usual fate
of a per-operation saving inside a pipeline that is not bound by that operation.

(An earlier draft of this section reported the opposite — a four-fold
*amplification* — and attributed it to queueing. That was the broken sentinel of
§4 measuring a prefix, not a queue effect. Nothing here supports the idea that
reader-side rerun savings compound; the honest statement is that they discount.)

## 6. What the release suite caught

The headline release run flagged
`High-Cardinality Stream Fan-out (v1) / 100 streams × 200 writes / resqlite` at
**+91.4%** (231.78 → 443.67 ms). The A/B above says that lane's shape is 12–25%
*faster*, so one of the two had to be wrong.

Neither was. The lane's wall is **quantized**: its settle loop waits a 200 ms
quiet window and stops at the first one with no new emission, so a run where the
measured iteration emits nothing costs one window and a run where it emits
anything costs two. The lane is therefore bimodal at ~246 ms and ~448 ms, and
+91.4% is exactly one settle window — not extra work.

What decides the mode is whether any emission lands in a measured iteration.
The suite re-seeds its PRNG per iteration, so iterations 2 and 3 rewrite the
values iteration 1 already wrote: the data does not change and the correct
emission count is zero. Running the lane 35 times per arm:

| arm | slow mode | rate |
|---|---:|---:|
| `origin/main` | 2 / 35 | 5.7% |
| candidate | 10 / 35 | **28.6%** |
| candidate with the decode-first arm compiled out | 1 / 14 | 7.1% |

The third row is the attribution: wiring the flag through the engine, the pool
and the request while the worker ignores it reproduces the baseline rate, so the
shift is the decoder, not the bookkeeping.

Instrumenting the harness to compare each post-baseline emission against what
that stream last emitted found **zero** same-content emissions on either arm.
The extra emissions are real changes — and the same instrumentation shows the
candidate makes more of them during the write burst itself: iteration 1's
post-baseline emissions are 91–101 on `origin/main` (six runs) and 102–115 on the
candidate (eight runs), about **+12%**.

### The second walk was not waste

That is the finding, and it inverts §2. The hash-first path's two passes do not
read the same database state. `resqlite_query_hash` **resets the statement on
exit**, so the decode pass that follows opens a *fresh* read transaction — a
newer WAL snapshot than the one the hash was computed over. During a burst,
the rows a stream emits are therefore fresher than the digest it stores, and the
stream converges in fewer emissions because each emission has skipped ahead.

The one-pass decoder takes exactly one snapshot, so hash and rows always agree —
which is the more defensible contract, and is what exp 228's invariant asks for
in spirit — but it gives up the free refresh. The stream needs one more rerun to
catch up, which is where the extra 12% of emissions and the extra settle window
come from.

So the second SQLite pass is not the pure overhead §2 prices it as. It costs
35–45% of a changed rerun and it buys emission freshness. Nobody knew it was
buying anything, which is why this looked like free money.

## Decision

**Rejected**, on two counts that compound. The mechanism is real and reproduced
— 35–45% off a changed rerun's SQLite-and-decode work, and a consistent −11% on
the wide fan-out lane where that pass is 35 µs — but it is narrower than the
first measurement claimed: on 100-row partitions, where the pass is 4 µs, the
effect does not clear the harness floor (§4). And what it does deliver, it
cannot pay for in the currency the library advertises. resqlite's reactive story
is that hash suppression keeps streams from re-emitting; trading roughly 12% more
emissions during a write burst for less wall time is a semantic-shaped trade, and this repo's record on those
(exps 197, 212, 213) is that a reproduced win does not settle them. That call
belongs to a maintainer, not to a scheduled run, so the runtime is archived
rather than shipped.

Three things would change the answer:

- **A design that keeps one snapshot per rerun and converges as fast.** The
  freshness the two-pass path buys is accidental, not designed. A one-pass
  rerun that re-checks cheaply — a row-count or version probe rather than a
  second full walk — would take the win without the trade. It would want to be
  gated on result size: §4 says the win only shows above a few hundred rows.
- **Evidence that emission count does not matter.** The cost here is more
  subscriber deliveries of correct intermediate data during a burst. If a
  downstream trace shows burst-time intermediate emissions are cheap or are
  coalesced by the UI layer anyway, the trade is one-sided and this ships.
- **A maintainer's ruling** that wall time on change-dense fan-out is worth
  ~12% more emissions.

What does not need re-deriving: §1's census (reruns are far fewer and far more
change-dense than the suites assume), §2's pass price, §3's predictor accuracy,
§4's harness rule about what a sentinel may watch, and §6's quantization and
freshness finding. Those are the run's lasting contribution and they hold
regardless of the verdict.

## Future work

- **The lane cannot resolve anything under 200 ms.** `high_cardinality_fanout`'s
  headline wall is one or two settle windows plus ~46 ms of actual work, and
  which one it is depends on a race. It has been the release suite's largest
  resqlite number for months and most of it is a sleep. Filed as
  [#318](https://github.com/danReynolds/resqlite/issues/318); any
  future stream candidate should be measured on
  `benchmark/experiments/stream_rerun_one_pass_ab.dart`'s drain metric instead.
- The fan-out tax has two very different readings and neither has been
  decomposed. Sequential awaited writes under JIT (§1) show 102 ms of tax over
  847 reruns — 120 µs of wall per rerun. Concurrent bursts under AOT (§4) show
  4.39 ms over 208 reruns — 21 µs per rerun, against roughly 8 µs of
  reader-side work. Whichever regime a real application is in, most of a
  rerun's wall is still unattributed.
- Whether the reader pool is the fan-out constraint at all is still open. §5
  says a per-rerun saving discounts to about 47% end to end on the wide lane and
  to nothing on the narrow one, which is what a pipeline bound by something else
  looks like. Sweeping the pool size across one drain burst would say what that
  something else is.
- The unchanged side of the walk is untouched. `resqlite_query_hash` steps every
  row to prove nothing moved, which §2 prices at 4.5–36 µs; exp 228's invariant
  (claim 228.1) constrains any early-reject shortcut to a non-cacheable
  sentinel. A cheap early-reject is also the shape the first bullet above needs.
