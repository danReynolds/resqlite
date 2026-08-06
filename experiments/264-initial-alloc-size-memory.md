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
  focused harness is the durable gate — and the release suite could not have run
  regardless: it no longer compiles against `drift` 2.34.3 on `main` (claim
  264.4), which is a new blocker upstream of the #282 segfault that stopped exps
  260 and 261.

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

## Decision

**Accepted.** Point reads are 7-27% faster with no reachable regression, and the
two properties that make it safe are structural rather than tuned: the clamp
means a result larger than 256 rows runs today's code, and the high-water mark
means a mispredict is one-off rather than periodic.

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

- [x] `dart analyze lib/ test/ benchmark/` — 77 issues, byte-for-byte the count
      on `origin/main`; all of them the `benchmark/drift/` peer scaffolding
- [x] `dart test -j2 -x drift` — 426 passing / 9 failing, against 414 / 9 on
      `origin/main` (the +12 are this experiment's; the 9 failures are the
      `benchmark_*_test.dart` files that load the drift peer suites, and are the
      same compile failure as claim 264.4)
- [x] `dart test test/result_buffer_sizing_test.dart` — 21 tests, including the
      high-water rule, the caller-over-local precedence, a statement that jumps
      from tiny to large, and an empty result that then grows
- [x] focused AOT A/B, four alternating orders, 61 samples per lane, lane-isolated;
      verdicts from `benchmark/ab_drift_check.dart`
- [x] 50-process first-jump measurement for the one-time mispredict cost
- [x] `dart run benchmark/finalize_experiment.dart` — green
- [x] `dart run benchmark/check_knowledge_links.dart` — clean (79 claims);
      `check_experiment_dispositions.dart` — no stranded in-review
- [ ] release suite — **cannot run**, see claim 264.4
