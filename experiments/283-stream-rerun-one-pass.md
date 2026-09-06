# Experiment 283: the second walk over the same rows

**Date:** 2026-09-06
**Status:** Accepted (in review)
**Direction:** `stream-rerun-dispatch`, `result-transfer-shape`
**Benchmark Run:** PLACEHOLDER

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

| lane | 1 B | 2 C | 3 B | 4 C | 5 B | 6 C | 7 B | 8 C | median | pooled 3–8 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `fanout` | −23.5 | −8.1 | −23.8 | −4.2 | −1.8 | +8.5 | −25.5 | −23.5 | **−15.8%** | **−12.5%** |
| `fanout-wide` | −7.4 | −0.1 | +6.8 | +3.9 | −15.0 | −7.1 | −15.4 | −5.1 | **−6.1%** | **−5.7%** |
| `keyed-pk` (guard) | +0.9 | +8.7 | −2.3 | +0.7 | +1.2 | +3.5 | −4.9 | −2.7 | +0.8% | −1.2% |
| `feed` (guard) | +0.3 | −1.7 | −2.5 | −0.4 | −9.7 | −2.8 | −7.2 | −0.3 | −1.1% | −4.1% |
| `writes` (control) | −2.4 | −1.2 | −0.9 | −4.0 | +7.8 | +4.1 | +6.0 | −4.5 | −1.1% | +0.6% |

Each sample issues its write burst concurrently and then times a sentinel write
through to the one stream it must change. Every rerun the burst scheduled —
including the unchanged majority, which emits nothing and cannot be waited on
directly — has to clear the queue before the sentinel's own rerun runs, so the
sentinel prices the backlog. An awaited write-by-write burst cannot: each rerun
overlaps the next write's latency and the wall reads as the write burst. That
was the first metric tried here and it resolved nothing.

`benchmark/ab_drift_check.dart` on the freshest order-flipped pair (7/8):

| lane | verdict | pass 1 | pass 2 |
|---|---|---:|---:|
| `fanout` | **reproduced** | −25.5% | −23.5% |
| `fanout-wide` | **reproduced** | −15.4% | −5.1% |
| `keyed-pk` | neutral | −4.9% | −2.7% |
| `feed` | neutral | −7.2% | −0.3% |
| `writes` | drift-suspected | +6.0% | −4.5% |

### 5. The win is larger than the pass price predicts

Worth stating plainly, because it is the one number here that does not
reconcile. The `fanout` lane issues 208 reruns per burst; §3's hit and miss
counts and §2's per-shape figures put the reader-side saving at
`880 × 4.22 − 654 × 1.95` over 13 bursts, or **188 µs per burst**. The measured
end-to-end saving is `6.170 − 5.400`, or **770 µs per burst** — four times as
much.

The direction of the discrepancy rules out the obvious explanations: the second
pass in the real worker follows the first over the same rows, so it is warmer
than the tight loop §2 measured, and the model should therefore over-predict.
What it does not model is queueing. The sentinel metric prices a backlog draining
through four workers, and shortening each rerun's service time shortens every
later rerun's wait as well, so a fifth off the service time buys more than a
fifth off the drain. Reader-side work also stops being ~8 µs of a ~21 µs
per-rerun wall in this shape and starts being the part that sets the queue's
service rate. That is a hypothesis, not a measurement — the honest statement is
that the mechanism's size is established by §2 and the win's size by §4, and
the amplification between them is not yet accounted for.

**Host caveat.** Load average ran 4.3–14.1 across the session — `mediaanalysisd`
held a core for most of it. The zero-ceiling `writes` control is the collection's
own floor and it swings ±8% in the worst pass and ±2% typically, which is why
the verdict rests on eight order-flipped passes and a pooled figure rather than
on any single pass. Passes 5 and 6 are the two where the control moved most and
they are also the two where `fanout` reads weakest; they are reported rather
than dropped.

## Decision

**Accepted (in review).** Stream fan-out where reruns change is 12–16% faster
end to end, reproduced across order flips and confirmed by the drift
classifier; the two lanes whose reruns do not change are neutral because the
predictor is structurally off in them, not because two effects cancel.

The mechanism is bounded and the code is small: one bool on `StreamEntry`, one
field on the request, one branch in `executeQueryIfChanged`, and a decoder that
has been shipping since exp 097. It adds no native code, no public API, and no
new semantics — the digest stored as a stream's baseline is the same canonical
value on both arms, which is the invariant exp 228 was written to protect.

What would reopen this: a workload whose streams change on isolated single
reruns rather than in runs. A change run of length 1 is the predictor's pure
loss — no hit, one miss — and the exchange rate that makes the arithmetic work
(≈2:1) is not so large that a workload of length-1 runs would survive it. The
`keyed-pk` and `feed` guards do not test that case; they test the case where the
predictor never arms at all. `benchmark/experiments/stream_rerun_one_pass_ab.dart`
is the durable gate.

## Future work

- The fan-out tax has two very different readings and neither has been
  decomposed. Sequential awaited writes under JIT (§1) show 102 ms of tax over
  847 reruns — 120 µs of wall per rerun. Concurrent bursts under AOT (§4) show
  4.39 ms over 208 reruns — 21 µs per rerun, against roughly 8 µs of
  reader-side work. Whichever regime a real application is in, most of a
  rerun's wall is still unattributed, and these are the library's largest
  benchmark lanes.
- §5's four-fold amplification is the first evidence in this direction that
  rerun service time and rerun *wall* are related by more than one-to-one.
  If that is queueing, it is a lever: it would mean any reduction in reader-side
  rerun work pays back multiplied on a saturated fan-out, and the current
  practice of sizing stream candidates against per-rerun cost understates them.
  A burst with the pool size swept would settle it.
- The same one-pass idea has an unexamined sibling on the *unchanged* side.
  `resqlite_query_hash` walks every cell of every row to prove nothing moved;
  a row-count or per-row digest checkpoint that could reject early would be a
  different mechanism against the same 4.5–36 µs, but exp 228's invariant means
  any such shortcut must produce a non-cacheable sentinel.
