# Experiment 266: send the read back to the worker that ran the last one

**Date:** 2026-08-09
**Status:** Accepted
**Direction:** `result-transfer-shape`, `stream-rerun-dispatch`
**Benchmark Run:** Release headline suite re-captured at HEAD on 2026-08-09
  (5-sample medians,
  [`benchmark/results/2026-08-09T20-36-47-exp266-headline-refresh.md`](../benchmark/results/2026-08-09T20-36-47-exp266-headline-refresh.md)),
  mapped to this experiment as the newest accepted milestone — the first
  completed release run since exp 229, unblocked by `--skip-memory` and the
  A11b `sqlite_async` arm exclusion (the exp 262 peer regression). The
  decision itself rested on the focused AOT A/B: twenty-four
  alternating-order lane-isolated passes in two collections of twelve, of
  [`benchmark/experiments/reader_dispatch_stickiness.dart`](../benchmark/experiments/reader_dispatch_stickiness.dart);
  full per-pass tables, drift verdicts and RSS in
  [`benchmark/results/2026-08-09T10-40-00Z-exp266-sticky-reader-dispatch.md`](../benchmark/results/2026-08-09T10-40-00Z-exp266-sticky-reader-dispatch.md).

## Problem

`ReaderPool._dispatch` picks a worker by scanning the slot list from a cursor it
advances on **every attempt**, including the successful one. That is a
round-robin: two reads issued back to back go to two different workers, and on
the default four-worker pool a sequentially awaited read loop visits all four
before it comes back to the first.

Rotating is the obvious policy when workers are interchangeable. They are not.
A reader worker is an isolate, and every piece of warm state a read builds is
private to it: its SQLite connection's page cache, that connection's prepared
statement in the C statement cache, the per-isolate `schemaCache` entry holding
the decoded column names, the cell buffer sized by `ensureCellBuffer`, its Dart
heap, and the OS thread the VM runs it on. Nothing is shared. So round-robin
does not spread work across four equivalent resources — it makes each of the
four independently pay for state the first one already built.

That cost is fixed per (statement, worker) pair, which means it is invisible to
every benchmark the repo has: they execute one statement thousands of times, and
by the hundredth execution all four workers are warm and the policy no longer
matters. It is very visible to an application, which opens a screen, runs a
query four or five times, and moves on.

## Hypothesis and decision rule

Start the scan at the slot that served the *previous* read instead of the next
one. When it is free the read goes back to the same isolate; when it is busy the
scan walks forward exactly as it does today, so a saturated pool spreads over
every worker unchanged.

Declared before measuring, with the shape of the prediction as the gate rather
than a single number: **if the mechanism is warm-state duplication, the win must
decay monotonically with how many times a statement has been executed** — large
at four executions, smaller at eight, smaller again at thirty-two, and absent in
steady state. A win that did not decay would mean something else was happening
and would not license the change. Kill conditions: any concurrency lane
regresses, the sacrifice lane regresses, or peak RSS rises.

## Approach

Three lines in `ReaderPool`. The cursor is renamed `_preferred` and no longer
advances past a slot it successfully used:

```dart
final index = (_preferred + attempt) % count;
final slot = _workers[index];
if (slot.isAvailable) {
  _preferred = index;
  return slot.request(request);
}
```

Everything else about dispatch is untouched — the same scan bound, the same
`isAvailable` test, the same `_dispatchWaiters` park when nothing is free, the
same wake ordering. Under concurrency the behaviour is self-spreading rather
than sticky: caller A takes slot 0 and leaves `_preferred` there, caller B finds
0 busy and takes 1, caller C takes 2. A worker that sacrifices itself on a large
result has no `_sendPort` until it respawns, so a preferred slot that keeps
dying is simply skipped.

`selectBytes` opts out and keeps the old rotation — `_dispatch` takes a `sticky`
flag and the bytes path passes false, advancing the cursor past the slot it used.
That is not a hedge; it is a requirement the release guard found, and the
Results section below explains what it is.

`preferredWorkerIndex` is exposed for tests, alongside the existing
`rowSizeHintFor` and `rowSizeMemoryLength`, because which worker ran a query is
not observable from any other surface. Three tests in `test/reader_pool_test.dart`
pin the invariants: that sequential reads stay on one worker, that four
concurrent reads still leave `availableWorkerCount` at zero — the property that
makes stickiness safe — and that four sequential `selectBytes` calls visit four
distinct slots.

## Results

Twenty-four alternating-order lane-isolated passes in two collections of twelve,
121 samples each. Deltas are medians of the per-pass deltas; `point1`'s mean is
quoted beside it because a single pass on that lane hit a host blip at +45.2%
against a ~3% within-run CV, and every other lane's mean and median agree to
within a point.

| lane | role | Δ (median of passes) | passes faster |
|---|---|---:|---:|
| `first4-newsql` | primary | **−32.2%** | 24/24 |
| `first8-newsql` | primary | **−21.8%** | 24/24 |
| `first32-newsql` | primary | **−13.2%** | 22/24 |
| `point1-wide20` | secondary | −3.5% | 23/24 |
| `mixed6-20` | secondary | −3.4% | 22/24 |
| `point1` (steady state) | control | −1.6% (mean +1.2%) | 18/24 |
| `mixed6-1k` | control | −0.7% | 17/24 |
| `alternating-sql` | control | +0.0% | 10/24 |
| `bytes-first8-newsql` | guard | −1.2% | 7/12 |
| `conc4` | guard | +1.3% | 8/24 |
| `conc8` | guard | +0.2% | 10/24 |
| `mixed6-10k` | guard | −0.4% | 13/24 |

**A statement's first four executions cost a third less.** In absolute terms 58
us becomes 39 us for four sequential point reads — 14.5 us per read against 9.8.
The saving is dominated by a term paid *once per statement*, not by a per-read
rate: ~19 us across the first four executions, ~22 us across the first eight,
~30 us across the first thirty-two. Round-robin makes all four reader
connections prepare the statement, build its schema and warm its pages; the
candidate makes one do it, so three cycles of roughly 6-9 us each are what the
percentages divide by an increasing execution count.

The prediction the experiment was gated on is the actual result: the effect
decays monotonically across `first4` → `first8` → `first32` → steady state, and
by the eight-thousandth execution of one statement (`point1`) it is gone.
`first4` and `first8` are faster in all 24 passes; `first32` is faster in 22 of
24. In collection 2, all six pass-pairs for each of `first4` and `first8`
classify as REPRODUCED; four of six `first32` pairs reproduce and two reverse
sign across the order flip, so the drift checker marks those two
drift-suspected. Nothing about the per-read path changed, and the steady-state
lanes say so.

The two secondary lanes are the same mechanism at its floor: `mixed6-20` and
`point1-wide20` run thousands of executions of one statement, so the fixed
warm-up is amortised almost to nothing, and they read −3.4% and −3.5%. Real but
small, and not what the change is for.

**The guards are clean and this is the part that had to hold.** Four concurrent
reads, eight against a four-worker pool so dispatch parks, and a 60,000-slot
result that ends its worker on every sample are all neutral, sign-flipping
between collections (`conc4` reads −1.4% in one and +1.5% in the other).
Stickiness costs concurrency nothing because a busy preferred slot behaves
exactly as round-robin did.

Peak RSS falls where the win is and holds everywhere else — 27.0 → 26.0 MB on
`first4-newsql`, 29.5 → 28.2 on `first8-newsql`, 95.8 → 96.0 on the sacrificing
lane. That is the same mechanism read from the other side: four workers each
holding a prepared statement, a schema cache entry and warmed pages for the same
SQL is four copies of state one worker now holds once.

### What the release guard caught, and why `selectBytes` opts out

The first version made *every* read sticky, and
`benchmark/suites/sqlite_diagnostics.dart`'s `JSON buffer reclaim` guard (exp
185) failed: `Diagnostics.readerJsonBufHighWaterBytes` settled at 6.2 MB against
a 512 KB budget. The guard was right and the interaction is real.

`selectBytes` serialises into a `json_buf` owned by the reader *connection*, and
[exp 183](183-json-buf-retention-audit.md)'s reclaim path shrinks that buffer
when a later, **smaller** read arrives on the same connection. The diagnostic
workload issues a concurrent burst of large byte reads — which spreads over all
four workers and grows all four buffers — and then a long run of small
sequential ones to settle them. Under round-robin those settle reads rotate and
reclaim every buffer. Under stickiness they all return to one worker, and the
three the burst left large are never visited again.

So the bytes path keeps the pre-266 rotation: `_dispatch` takes a `sticky` flag
and `selectBytes` passes false, which advances the cursor past the slot it used.
The boundary is principled rather than expedient — the bytes path retains a
per-connection buffer whose reclaim is *driven by traffic*, and the rows path
retains nothing per connection — and it is now pinned two ways: a
`selectBytes keeps rotating` unit test asserting four sequential byte reads visit
four distinct slots, and the `bytes-first8-newsql` lane, which reads −1.2% (7 of
12 passes faster) exactly as an unchanged path should.

The one rows lane worth naming as a caveat is `alternating-sql`, which runs two
statements against one another in steady state and is where concentrating both
onto one connection could in principle cost something. It reads +0.0% over 24
passes.

## Outcome

**Accepted.** A statement's first four executions are ~33% faster and its first
eight ~21%, with steady state, concurrency, sacrifice and peak RSS all unmoved.
The change is three lines and adds no public API.

The honest scope is narrow and worth stating plainly: this removes a *fixed*
cost per (statement, worker) pair, so its value to a caller is inversely
proportional to how many times that caller runs the statement. An application
that opens a screen, runs a handful of queries and moves on gets most of it; a
tight loop over one statement gets almost none. That the repo's whole benchmark
suite sits at the second extreme is why the cost survived 265 experiments.

Would reopen the policy — in the other direction — if a workload appears where
one worker's connection holding the union of several hot statements' pages
measurably beats four connections each holding a subset. `alternating-sql`
exists to catch that and did not.

### The stream guard that ran after the fact

The focused harness had concurrency, sacrifice and bytes guards but no *stream*
lane, and `stream-rerun-dispatch` is a direction where dispatch-adjacent changes
have a history of looking clean and then failing on fan-out (exps 148, 151,
170). Stream reruns go through `_dispatch` with `sticky = true`, so the
integrated Tracelite A/B was run post-hoc on that direction's preset against a
fresh `origin/main` baseline.

No regression; the movement is the other way:

| scenario | baseline | candidate | Δ | p |
|---|---:|---:|---:|---:|
| `high-cardinality-fanout` | 411ms | 367ms | −10.7% | 0.10 |
| `keyed-pk-subscriptions` | 337ms | 268ms | −20.5% | <0.001 |
| `many-streams-writer-throughput` | 619ms | 572ms | −7.5% | 0.005 |

The harness itself exits `inconclusive` because this preset's expectation is
`improvement` against a 43.5% primary threshold — it is built to *accept* stream
wins, and no such win is claimed here. Read as a regression guard, every lane is
faster or neutral and none is slower. The `warmup_elapsed_ns` guardrails are too
noisy to classify (CV 57–98%) but all three point down 36–53%, which is the
mechanism reading itself back: warm-up is where stickiness pays, and a stream
rerun re-executes the same SQL sequentially, so it lands on a warm worker like
any other sequential caller. The keyed-PK −20.5% at p≈1e-5 is suggestive of a
real carry-over benefit but is not claimed as a win — that would need the full
moonshot-grade pass this guard run was not.

### One more thing CI caught

The three dispatch tests originally spawned a four-worker `ReaderPool`. That
passed on a ten-core dev machine and failed on CI's two-core runner, because
`Database.open` sizes the pool as `clamp(numberOfProcessors - 1, 2, 4)` and C
allocates exactly that many reader connections — `resqlite_stmt_acquire_on`
returns NULL for `reader_id >= db->reader_count`, which surfaces as
`ResqliteQueryException: not an error` (no SQLite error was ever set) and, on the
bytes path, `resqlite_query_bytes failed with code 5`. The tests now use two
workers, the floor of that clamp and what every pre-existing pool test in the
file already used. Two still discriminates: one busy slot out of two is the
difference between spreading and serializing.

## Test plan

- `dart analyze --fatal-infos` on the harness and `lib/` — clean
- `dart test test/reader_pool_test.dart` — 29 tests, including the three new
  `dispatch stickiness` guards
- `dart test test/benchmark_sqlite_diagnostics_test.dart` — the exp 185 `JSON
  buffer reclaim` release guard, which rejected the first version of the change
- Twenty-four alternating-order lane-isolated AOT passes, 121 samples per lane
  per arm, in two collections of twelve
- `dart run benchmark/ab_drift_check.dart` over all 72 pass-pairs
- `dart run benchmark/finalize_experiment.dart --experiment=experiments/266-sticky-reader-dispatch.md`
