# Experiment 264: size the initial result buffer from what the SQL has ever returned

**Date:** 2026-08-06
**Status:** Accepted
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused AOT A/B, four alternating-order lane-isolated
  passes of
  [`benchmark/experiments/select_rows_presize.dart`](../benchmark/experiments/select_rows_presize.dart)
  at 61 samples per lane per pass; receipt in
  [`benchmark/results/2026-08-06T11-40-00Z-exp264-initial-alloc-size-memory.md`](../benchmark/results/2026-08-06T11-40-00Z-exp264-initial-alloc-size-memory.md).
  No release-suite lane resolves a sub-microsecond per-read allocation, so the
  focused harness is the durable gate.

## Problem

`decodeQuery` opens every read by allocating
`List<Object?>.filled(colCount * 256, null, growable: true)` — room for 256 rows,
whatever the statement is about to return. A point read then writes one row into
it and truncates. On the repo's canonical six-column product row that is 1,536
slots allocated and zero-filled to keep 6; on a twenty-column row it is 5,376 to
keep 21.

[Exp 067](067-shrink-initial-allocation.md) tried to shrink the constant in 2026
and was rejected. It changed `colCount * 256` to `colCount * 4` for *every*
query, so any result larger than four rows had to double its way up from there,
and four small-query workloads regressed 40-44%. Its stated mechanism was that
the VM has a zero-fill fast path making one large null-filled list *cheaper per
slot* than a small one, and that the constant was therefore "well-tuned."

Two things make that conclusion worth re-testing now. The per-slot claim is true
and decision-irrelevant — a standalone AOT reproduction of the allocation shape
measures 1,536 slots at 0.28 ns/slot against 12 slots at 1.8 ns/slot, so the
large allocation is indeed cheaper per slot and 20x more expensive in total.
And [exp 260](260-result-list-presize.md) has since given the decoder something
exp 067 did not have: a per-SQL memory of how many rows each statement returns.
Shrinking no longer has to be a guess applied to every query.

This is the same defect class exp 260 found in [exp 059](059-row-count-hint.md):
a mechanism claim that is locally true, measured against an unconditional change,
closing a direction that a *conditional* change reopens.

## Hypothesis

Size the initial allocation from the per-SQL row-size memory instead of a
constant — but only ever *downward*, clamped at the existing 256 rows. A
statement that has shown it returns few rows allocates for few rows; a statement
that has returned more, or that the pool has no opinion about yet, allocates
exactly what it allocates today.

The clamp is what separates this from what exp 260 explicitly rejected. Exp 260
tried applying its hint to the initial allocation and measured a `LIMIT ?`
statement's 50-row leg going 2.8x slower (68 → 198 us) once the hint saturated
at the large leg: zero-filling 60,000 unused slots costs more than the doubling
it removes. A hint that can only shrink cannot do that — the worst it can do is
make a result double its way back up.

Primary gate: at least 10% faster median wall on point reads, reproduced in both
collection orders. Kill conditions: any lane whose result is larger than the
initial buffer regresses outside the harness floor, or the cost of a statement
whose row count jumps from small to large is not bounded and one-off.

## Approach

`RowSizeMemory` — exp 260's two-execution record of a SQL's result size — gains a
second output. The two ends of the buffer's life want opposite statistics, and
each takes the one whose mistakes are cheap:

- `hint` (exp 260, unchanged) steers **growth** and takes the *smaller* of the
  last two row counts. Over-sizing is the expensive mistake there.
- `initialRows` (new) sizes the **initial allocation** and takes the *largest row
  count ever seen*, plus 25% headroom, clamped into `1 ..= 256` rows.
  Under-sizing is the expensive mistake here.

`decodeQuery` and `decodeQueryWithInitialHash` take an `initialRowHint`, and the
value comes from the **main isolate**: `ReaderPool` already keeps a
`RowSizeMemory` per SQL and stamps exp 260's growth hint onto each request, so
this rides along beside it. `ReaderPool._record` now creates an entry for small
results too — exp 260 skipped those because a small result cannot reach the
growth path, and it now has a consumer only small results can reach. The writer
isolate, which no pool serves, keeps using its own schema-cache memory.

Everything else stays on the old path. A statement in its first two executions,
one whose entry has been evicted from the pool's 32-entry memory, and every
`selectBytes` call (which builds no Dart buffer at all) allocate exactly what
they allocate today.

### Two rules, and the order they were found in

The first implementation had neither of the two rules that make this safe, and
one guard lane produced both — the first time by being misread.

The lane is `undershoot-mid`: a `LIMIT ?` statement returning 3,300 rows behind a
burst of eight 20-row executions. Against the first implementation — which sized
the initial allocation from the larger of the *last two* row counts, by symmetry
with exp 260's smaller-of-two — it measured **+40% in all four order-flipped
passes**.

**A pool worker must not answer this question about itself.** This was the first
diagnosis, and it was reasoned rather than measured: the first implementation read
the *worker-local* memory, on the argument that exp 260 only needed the main
isolate because `Isolate.exit` destroys the worker that decodes a large result,
which cannot happen to a mark about small ones. That argument is sound as far as
it goes and it misses two others. A high-water mark is only worth the observations
feeding it: a four-worker pool hands each worker a sample, so three of four can
still believe a statement is small after the fourth has decoded a large result,
and a worker that *does* decode a large result is destroyed and its replacement
starts over. So the mark moved to the main isolate, which sees every execution and
outlives every worker.

That was the right change and it did not move the lane at all — still +40%, all
four passes. The move fixed a real defect that was not the one being measured.

**The statistic must be a high-water mark, not a sliding window.** The actual
cause is independent of where the memory lives. A window of length two is defeated
by any burst longer than two: wherever it is kept, the two observations before the
large execution are both 20 rows, so the large result is sized for 20 rows and
doubles its way up — *every time*, not once. Only the statistic could fix that.
A high-water mark cannot repeat: the first large result raises it for good, and
every later one is sized from the fixed default. What it gives up is a statement
that was once large and is now permanently small, which keeps today's allocation
forever — no win, but no tax either. With that change the lane reads −1.3%.

## Results

Four alternating-order passes (baseline-first, candidate-first, baseline-first,
candidate-first), lane-isolated, 61 samples per lane per pass. Both arms are
native-asset-aware AOT CLI bundles built from the same harness source, per exp
193's requirement for any decode-path result.

| lane | role | p1 (B1) | p2 (C1) | p3 (B1) | p4 (C1) | verdict |
|---|---|---:|---:|---:|---:|---|
| `point1-wide20` | primary | −30.4% | −26.1% | −26.7% | −26.5% | **reproduced** |
| `point1` | primary | −9.3% | −4.0% | −7.7% | −8.4% | **reproduced** |
| `mixed6-20` | primary | +10.2% | −6.8% | +4.2% | −8.5% | drift-suspected |
| `mixed6-200` | control | −2.7% | −6.1% | −2.8% | −4.9% | neutral |
| `mixed6-1k` | control | +1.8% | −2.3% | −1.8% | +2.3% | neutral |
| `mixed6-10k` | control | −0.8% | +3.9% | −3.4% | +0.8% | neutral |
| `int4-5k` | control | −1.3% | −0.2% | −3.0% | −0.4% | neutral |
| `int20-10k` | control | +2.1% | −3.3% | −2.6% | −2.7% | neutral |
| `mispredict-shrink` | guard | +1.4% | +7.5% | +10.3% | +5.7% | drift-suspected (CV 91%) |
| `mispredict-mid` | guard | −4.4% | +2.7% | −6.1% | +0.9% | neutral |
| `undershoot-jump` | guard | −2.4% | −1.8% | −0.4% | +0.9% | neutral |
| `undershoot-mid` | guard | −1.6% | −4.0% | −0.1% | +0.6% | neutral |

Verdicts are `benchmark/ab_drift_check.dart`'s, not eyeballed.

**Point reads get 7-27% faster, and the win scales with projection width.** The
six-column point read moves −7.4% on average and the twenty-one-column one
−27.4% — the ratio the mechanism predicts, because what a one-row result wastes
is `colCount * 255` slots. In absolute terms that is roughly 0.5 us and 2.2 us of
worker time per read. This is a real fraction of a point read: the whole
operation is about 5-8 us, most of which is the isolate round trip, so the
allocation was one of the larger single items left in it.

**Every lane whose result outgrows the initial buffer is neutral**, which is what
the clamp guarantees rather than something the measurement had to discover: all
five control lanes size to 256 rows in both arms and read the harness floor
(±4%). `mixed6-20` should win by the same mechanism and does not resolve — its
per-read cost is dominated by 80 String allocations, and the sign flips across
the order flip, so it is reported as drift-suspected rather than as a small win.

**The cost of a first jump from small to large is +1.6%, once.** With the
high-water rule the `undershoot-mid` lane goes inert after its first sample, so
the one-time cost was measured separately: 50 fresh processes per arm,
`--warmup=0 --samples=1`, so the timed 3,300-row read is the first large
execution the pool has ever seen. Median 927.5 us baseline against 942.5 us
candidate — about 15 us, well inside the p10–p90 spread of either arm, and
consistent with an arithmetic account of the extra doublings (four more growths,
15,200 more slot copies, 13,800 more slots zero-filled). It is paid once per
statement per pool-memory lifetime.

**Peak RSS is flat on every lane that holds one read live** — within about 1 MB
across all four passes, including 24.0 → 23.8 MB on `point1-wide20`. Dart
releases a truncated growable list's backing store, so the fixed allocation was
never *retained*; this removes transient allocation work and garbage, not
footprint, which is the same conclusion exp 263 reached about `select`'s row
representation from the other direction. The two lanes that issue their poison
through `Future.wait` carry no memory signal in either arm — `mispredict-shrink`'s
baseline alone reads 99-252 MB across the four passes, set by how many 8,000-row
reads are live together. `undershoot-mid` is up 2.3-2.9 MB in two of four passes,
which is the one-time mispredict chain showing up in a process-lifetime
high-water.

**A release-suite run reaches scenario 14 of 16 and then dies in the peer.** The
suite runs cleanly through Select→Maps, Select→Bytes, Schema Shapes, Scaling,
Concurrent Reads, Point Query, Parameterized, Writes, both Streaming groups, and
the four app-shaped workloads, then aborts inside the sqlite_async peer at
`[15/16] Memory` — the pre-existing #282 crash that also stopped exps 260 and 261,
and which additionally wedges the parent process rather than exiting. Nothing in
this experiment's diff is linked into that library.

Exp 262's per-scenario persistence did its job: the killed run still wrote an
artifact with 14 scenarios and 169 metrics, correctly self-marked
`partial: true`, `scenariosCompleted: 14`, `repeatCount: 0`. It is the first time
that mechanism has actually preserved anything, since exps 260 and 261 were killed
inside repeat 1 before it existed.

It is **not committed**, and it is not evidence for this experiment. `repeatCount:
0` is the repo's own marker for a single-sample run, which the trend charts drop
by design, and there is no paired baseline. What it is good for is a sanity check
that nothing broke: point-query throughput 160,798 qps, 1,000-row `select()` 0.349
ms, batch insert of 1,000 rows 0.389 ms, stream invalidation latency 0.058 ms —
all at or better than the figures published in `README.md`, none regressed.

### The change put exp 260's hint at risk, and the fix is capacity, not order

Removing exp 260's `rowCount <= initialResultRows` insert guard is what lets a
small statement be remembered at all — and it also lets every point read take one
of the pool's 32 `_rowHints` slots. Exp 260 had those slots to itself: only a
statement that had returned more rows than the initial buffer holds was ever
inserted, so nothing competed with the large-result statements its growth hint
serves. After exp 264 a report query that runs constantly is evicted by point-read
churn and loses its hint.

Nothing in the suite could see this, because every existing lane uses a handful of
SQL strings. Two new lanes fix that gap by running never-before-seen statements
between timed reads:

| lane | pre-264 | exp 264 | + LRU promotion | + small-victim eviction |
|---|---:|---:|---:|---:|
| `hint-thrash-overflows` (40 one-offs) | 597 | 826 | 976 | **565** |
| `hint-thrash-fits` (20 one-offs) | 592 | 579 | 597 | 566 |

The regression is real and systematic — on the overflow lane the slower arm's
*fastest* sample beat the faster arm's *slowest*, so it is not a tail effect.

**Least-recently-used promotion does not fix it.** That was the first fix
attempted, on the reasoning that a hot statement should not be aged out; it
measured no improvement, and it costs the main isolate a map remove-and-reinsert
on every read. The problem is capacity, not order: once more distinct hot
statements are in play than the map holds, no ordering keeps the one that matters.
Raising `_rowHintMax` to 128 does fix it (620 us), which is what identified the
mechanism.

What shipped instead is an eviction preference: on overflow, drop an entry whose
`highWater` has never exceeded the initial buffer before dropping one that has.
That restores exp 260's exclusive tenure without picking a new magic capacity,
small statements still use whatever slots are left, and the O(32) scan runs only
on an overflowing miss — never on the per-read path, so it cannot erode the point
read this experiment exists to speed up. When every entry has proven large it
falls back to insertion order, which is exactly the pre-264 behaviour.

The property is gated in `test/reader_pool_test.dart`, not in the lane. Whether a
hint is still armed is a deterministic consequence of the eviction policy, and the
test fails against insertion-order eviction and passes with the preference — a
cleaner signal than a benchmark that needed three passes to read. Note that
*presence* is the wrong assertion: an evicted statement is re-inserted the next
time it runs, so a membership check passes under any policy. What eviction costs is
the learned hint.

### Re-measured on a quieter host

Everything above was collected while the machine was saturated (see below), so the
whole comparison was re-run once it freed up — 52-61% CPU idle, four alternating
passes, lane-isolated, 61 samples per lane, three arms: `origin/main`, exp 264
without the eviction fix, and exp 264 as it ships. The controls are tight here
(±1.7%, against ±4% before), so these are the numbers to quote.

**Exp 264 (final) against `origin/main`:**

| lane | role | pass 1 | pass 2 | pass 3 | pass 4 | mean | verdict |
|---|---|---:|---:|---:|---:|---:|---|
| `point1` | primary | -10.3% | -15.2% | -19.9% | -8.5% | -13.5% | **reproduced** |
| `point1-wide20` | primary | -26.3% | -19.5% | -29.5% | -33.1% | -27.1% | **reproduced** |
| `int20-10k` | control | -0.5% | +0.4% | +1.3% | -0.2% | +0.3% | neutral |
| `mixed6-10k` | control | +0.1% | +0.8% | -0.7% | -1.7% | -0.4% | neutral |
| `hint-thrash-overflows` | guard | -1.3% | +0.9% | -2.6% | +2.2% | -0.2% | neutral |

**Cost of the eviction fix — exp 264 with it against exp 264 without:**

| lane | role | pass 1 | pass 2 | pass 3 | pass 4 | mean | verdict |
|---|---|---:|---:|---:|---:|---:|---|
| `point1` | primary | -6.8% | -5.6% | -6.9% | +3.3% | -4.0% | sign-flips |
| `point1-wide20` | primary | -1.7% | +24.5% | -2.2% | +1.5% | +5.5% | sign-flips |
| `int20-10k` | control | +0.3% | +0.4% | -0.8% | +0.3% | +0.0% | neutral |
| `mixed6-10k` | control | -0.5% | +0.0% | +1.5% | -0.6% | +0.1% | neutral |
| `hint-thrash-overflows` | guard | -30.3% | -28.8% | -30.1% | -28.8% | -29.5% | **reproduced** |

The win holds and the narrow point read is *better* than the saturated run
suggested — −13.5% against the −7.4% first measured, while the wide lane reproduces
almost exactly (−27.1% against −27.4%). The earlier figure was the host, not the
code.

The eviction fix costs nothing on the hot path, which is what the structure
predicts: `_evictionVictim` is only reachable when the memory overflows its 32
entries, and a lane running one statement never gets there. Both `point1` lanes
sign-flip across the order flip and both controls sit at ±0.1%, while the thrash
guard moves −29.5% in all four passes. And `hint-thrash-overflows` is now level with
`origin/main` (−0.2%), so exp 260's reach is fully restored rather than merely
improved: without the fix that same lane runs +41.6% slower than pre-264.

### The host was saturated for the first pass, which is how the figures moved

The twelve-lane table and the guard measurements above were collected on a machine
at **0.0% CPU idle** —
`top` reported 57% user / 43% sys with an unrelated Virtualization.framework VM at
190% CPU, FSEvents at 57%, and other Dart processes at 100% and 44%. The same host
had under 500 MB free on a 460 GB volume, and six `run_release.dart` processes from
earlier sessions were resident, wedged 1-4 days at 0.0% CPU.

The direction and mechanism survive that: the design is order-flipped over four
passes, the controls held to ±2%, the two primaries reproduced 4/4 with the
column-count scaling the mechanism predicts, and a standalone allocation probe with
no isolates and no SQLite measures the same effect at 423 ns against 21.5 ns per
call — independent corroboration of both sign and magnitude. The precise
percentages do not survive it. A per-read microsecond measurement on a saturated
host is dominated by reader-isolate scheduling latency, and the confirmation pass
that exposed the problem read +50.6% on `int20-10k`, a lane the candidate cannot
reach.

That is why the three-arm re-measurement above exists, and it is the authoritative
one wherever the two overlap. The four-pass twelve-lane table is retained because it
is the only pass covering the guards and the full lane set, and its verdicts —
which lanes reproduce and which flip — held up.

The episode is a gap in the tooling rather than bad luck: `run_release.dart`
stamps `gitDirty` and the charts drop untrusted runs, but a focused AOT harness
records nothing about its host, so there was nothing to notice until an inert lane
moved by 50%.

## Decision

**Accepted.** Point reads are a reproduced **13.5% faster on the canonical
six-column row and 27.1% on a twenty-one-column one**, measured on a quiet host
across four alternating passes with controls inside ±1.7%. The two properties that
make the change safe are structural rather than tuned: the clamp means a result
larger than 256 rows runs today's code, and the high-water mark means a mispredict
is one-off rather than periodic.

The change also required a fix to the pool's eviction preference, without which it
silently narrows exp 260's reach by 40-46% on any application with more than 32
distinct hot statements. That fix ships here rather than as a follow-up, because
this experiment is what creates the need for it.

Exp 067's rejection stands for what it tested — an unconditional shrink is still
wrong, and its regressed workloads would still regress. What it got wrong was the
generalisation: it read a true per-slot fact as evidence that the constant was
well-tuned, when the constant was only well-tuned in the absence of any
per-statement knowledge. Exp 260 supplied that knowledge and this consumes it.

Would reopen if the pool's 32-entry memory turns out to thrash on a real
application's statement mix, since an evicted entry loses the mark and pays the
first-jump cost again. The discriminating measurement is cheap: count distinct
SQL strings per second in a representative app trace against `_rowHintMax`.

## Test plan

- [x] `dart run build_runner build --delete-conflicting-outputs` — required in a
      fresh worktree; `benchmark/drift/*.g.dart` is gitignored and CI generates it
      before analyze and test
- [x] `dart analyze --fatal-infos` — no issues
- [x] `dart test --timeout 60s` — 450 tests, all passing
- [x] `dart test test/result_buffer_sizing_test.dart` — 21 tests, including the
      high-water rule, the caller-over-local precedence, a statement that jumps
      from tiny to large, and an empty result that then grows
- [x] focused AOT A/B, four alternating orders, 61 samples per lane, lane-isolated;
      verdicts from `benchmark/ab_drift_check.dart`
- [x] 50-process first-jump measurement for the one-time mispredict cost
- [x] `dart run benchmark/finalize_experiment.dart` — green
- [x] `dart run benchmark/check_knowledge_links.dart` — clean (79 claims);
      `check_experiment_dispositions.dart` — no stranded in-review
- [x] CI green on PR #289. The first run aborted (SIGABRT) inside the sqlite_async
      peer's `ConnectionLease.notifyUpdates` while
      `benchmark_keyed_pk_subscriptions_test.dart` was running; re-running the
      identical commit passed, and six local repetitions of the same three peer
      workload tests passed. This is the #282 peer-instability family surfacing in
      the test job rather than the benchmark run.
- [x] Post-merge CI green at merge SHA `4cef478` in
      [run 31127102881](https://github.com/danReynolds/resqlite/actions/runs/31127102881),
      including tests, analysis, encoder differential fuzzing, Tracelite smoke,
      generated-source validation, and knowledge checks.
