# Experiment 264: initial result-buffer sizing

Collected 2026-08-06 on arm64 macOS 26.2 (Apple M1 Pro) with Dart 3.12.2.
Baseline is `origin/main` at `c351422`; candidate is the same tree plus the
initial-allocation high-water mark on `RowSizeMemory`, the `initialRowHint` field
on `ReadRequest`, and the two new harness lanes. Both arms were built as
native-asset-aware AOT CLI bundles so the decode path is AOT-compiled (exp 193's
requirement for any `Row`/decode change):

```console
dart build cli --target=bin/select_rows_presize.dart --output=<arm>
<arm>/bundle/bin/select_rows_presize --lane=<lane> --warmup=12 --samples=61
```

The harness source is
[`benchmark/experiments/select_rows_presize.dart`](../experiments/select_rows_presize.dart);
`bin/` is only where `dart build cli` requires the entry point to live. The
baseline arm was built from the candidate's copy of the harness, so the source is
identical in both arms and only `lib/` differs.

Every lane is **lane-isolated** — one fresh process per lane per arm — and four
passes were collected in alternating collection order (baseline-first,
candidate-first, baseline-first, candidate-first) rather than the usual two, because
the first two passes disagreed on `mixed6-20` and two orderings could not tell a
small effect from drift. Values are microseconds; `point1` and `point1-wide20`
time 200 executions per sample and `mixed6-200` times 20, so their medians are per
sample, not per execution.

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

## Lanes

| lane | shape | role for exp 264 |
|---|---|---|
| `point1` | `WHERE id = ?` on the canonical 6-column row, 1 row | primary — the shape the fixed allocation wastes most of |
| `point1-wide20` | `WHERE id = ?` on a 21-column INTEGER row, 1 row | primary — widest projection, so the largest waste |
| `mixed6-20` | `LIMIT 20` on the canonical row | primary — a paged list view |
| `mixed6-200` | 200 rows of the canonical row | control — sizes to 250 rows against 256, effectively inert |
| `mixed6-1k` / `mixed6-10k` / `int4-5k` / `int20-10k` | exp 260's primaries | control — all clamp to the 256-row default, so the initial allocation is unchanged |
| `mispredict-shrink` | 50 rows timed behind six 8,000-row executions | guard — a statement that swings must not be sized down |
| `mispredict-mid` | 300 rows alternating with 8,000 | guard — same, where the growth hint is also consulted |
| `undershoot-jump` | 5,000 rows behind eight 20-row executions | guard — favourable doubling alignment |
| `undershoot-mid` | 3,300 rows behind eight 20-row executions | guard — **adverse** doubling alignment; the lane that rejected the sliding-window rule |

## Timing

| lane | pass | baseline median | candidate median | Δ | baseline CV | candidate CV |
|---|---|---:|---:|---:|---:|---:|
| `int20-10k` | 1 (baseline first) | 4457 | 4549 | +2.1% | 2.4% | 3.3% |
| `int20-10k` | 2 (candidate first) | 4611 | 4459 | -3.3% | 3.6% | 2.6% |
| `int20-10k` | 3 (baseline first) | 4565 | 4448 | -2.6% | 2.7% | 2.4% |
| `int20-10k` | 4 (candidate first) | 4536 | 4412 | -2.7% | 3.9% | 2.4% |
| `int4-5k` | 1 (baseline first) | 546 | 539 | -1.3% | 7.0% | 11.9% |
| `int4-5k` | 2 (candidate first) | 522 | 521 | -0.2% | 9.2% | 8.2% |
| `int4-5k` | 3 (baseline first) | 534 | 518 | -3.0% | 9.9% | 8.3% |
| `int4-5k` | 4 (candidate first) | 522 | 520 | -0.4% | 8.8% | 9.3% |
| `mixed6-10k` | 1 (baseline first) | 2501 | 2482 | -0.8% | 17.8% | 15.6% |
| `mixed6-10k` | 2 (candidate first) | 2390 | 2483 | +3.9% | 17.4% | 16.0% |
| `mixed6-10k` | 3 (baseline first) | 2475 | 2390 | -3.4% | 16.7% | 15.9% |
| `mixed6-10k` | 4 (candidate first) | 2405 | 2424 | +0.8% | 17.9% | 14.7% |
| `mixed6-1k` | 1 (baseline first) | 219 | 223 | +1.8% | 13.7% | 14.6% |
| `mixed6-1k` | 2 (candidate first) | 218 | 213 | -2.3% | 14.8% | 14.4% |
| `mixed6-1k` | 3 (baseline first) | 219 | 215 | -1.8% | 16.3% | 16.6% |
| `mixed6-1k` | 4 (candidate first) | 214 | 219 | +2.3% | 17.7% | 13.6% |
| `mixed6-200` | 1 (baseline first) | 1001 | 974 | -2.7% | 5.2% | 9.7% |
| `mixed6-200` | 2 (candidate first) | 1057 | 992 | -6.1% | 4.9% | 5.5% |
| `mixed6-200` | 3 (baseline first) | 997 | 969 | -2.8% | 5.4% | 6.2% |
| `mixed6-200` | 4 (candidate first) | 1052 | 1000 | -4.9% | 3.9% | 6.3% |
| `point1` | 1 (baseline first) | 1103 | 1000 | -9.3% | 19.1% | 15.9% |
| `point1` | 2 (candidate first) | 1103 | 1059 | -4.0% | 17.7% | 16.4% |
| `point1` | 3 (baseline first) | 1094 | 1010 | -7.7% | 16.1% | 15.9% |
| `point1` | 4 (candidate first) | 1106 | 1013 | -8.4% | 16.8% | 18.3% |
| `point1-wide20` | 1 (baseline first) | 1593 | 1109 | -30.4% | 11.3% | 16.2% |
| `point1-wide20` | 2 (candidate first) | 1525 | 1127 | -26.1% | 11.9% | 13.3% |
| `point1-wide20` | 3 (baseline first) | 1515 | 1111 | -26.7% | 10.1% | 13.7% |
| `point1-wide20` | 4 (candidate first) | 1505 | 1106 | -26.5% | 9.9% | 13.7% |
| `mixed6-20` | 1 (baseline first) | 488 | 538 | +10.2% | 16.1% | 14.8% |
| `mixed6-20` | 2 (candidate first) | 497 | 463 | -6.8% | 15.8% | 16.2% |
| `mixed6-20` | 3 (baseline first) | 569 | 593 | +4.2% | 15.0% | 11.2% |
| `mixed6-20` | 4 (candidate first) | 508 | 465 | -8.5% | 15.7% | 15.5% |
| `mispredict-shrink` | 1 (baseline first) | 74 | 75 | +1.4% | 17.8% | 120.5% |
| `mispredict-shrink` | 2 (candidate first) | 67 | 72 | +7.5% | 22.5% | 17.1% |
| `mispredict-shrink` | 3 (baseline first) | 68 | 75 | +10.3% | 15.8% | 17.1% |
| `mispredict-shrink` | 4 (candidate first) | 70 | 74 | +5.7% | 20.8% | 25.5% |
| `mispredict-mid` | 1 (baseline first) | 113 | 108 | -4.4% | 21.3% | 10.7% |
| `mispredict-mid` | 2 (candidate first) | 113 | 116 | +2.7% | 13.3% | 9.2% |
| `mispredict-mid` | 3 (baseline first) | 114 | 107 | -6.1% | 17.3% | 9.9% |
| `mispredict-mid` | 4 (candidate first) | 117 | 118 | +0.9% | 14.1% | 11.9% |
| `undershoot-jump` | 1 (baseline first) | 1559 | 1521 | -2.4% | 48.1% | 47.7% |
| `undershoot-jump` | 2 (candidate first) | 1524 | 1496 | -1.8% | 48.9% | 54.4% |
| `undershoot-jump` | 3 (baseline first) | 1542 | 1536 | -0.4% | 22.8% | 49.3% |
| `undershoot-jump` | 4 (candidate first) | 1541 | 1555 | +0.9% | 55.5% | 51.7% |
| `undershoot-mid` | 1 (baseline first) | 762 | 750 | -1.6% | 9.8% | 9.7% |
| `undershoot-mid` | 2 (candidate first) | 784 | 753 | -4.0% | 10.2% | 8.5% |
| `undershoot-mid` | 3 (baseline first) | 762 | 761 | -0.1% | 8.3% | 9.5% |
| `undershoot-mid` | 4 (candidate first) | 773 | 778 | +0.6% | 10.3% | 9.9% |

## Re-measurement on a quieter host

The timing table above was collected while the host sat at 0.0% CPU idle (see
*Environment* below). The comparison was re-run once it freed up — 52-61% idle,
four alternating passes, lane-isolated, 61 samples per lane, three arms:

```console
pre    = origin/main (c351422)
fifo   = exp 264 without the eviction fix (f87584d)
victim = exp 264 as it ships
```

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

Controls tighten to ±1.7% here from ±4%, so these supersede the twelve-lane table
wherever the two overlap. Absolute medians, pass 1 (us): `point1` 1305 / 1255 /
1170, `point1-wide20` 1722 / 1291 / 1269, `hint-thrash-overflows` 551 / 780 / 544.

## Environment

Every figure in the twelve-lane table was collected on a host at **0.0% CPU idle**:
`top` reported 57% user / 43% sys, with an unrelated Virtualization.framework VM at
190% CPU, `fseventsd` at 57%, and other Dart processes at 100% and 44%; load average
33/39/50 on ten cores; under 500 MB free on a 460 GB volume; and six
`run_release.dart` processes from earlier sessions resident, wedged 1-4 days at 0.0%
CPU. It surfaced when a confirmation pass read +50.6% on `int20-10k`, a lane the
candidate cannot reach.

The re-measurement above ran at 52-61% idle with the VM gone (`fseventsd` and
`triald_system` still active, so not pristine). Comparing the two passes bounds what
the saturation cost: six points on the narrow point read (-7.4% → -13.5%), nothing
on the wide one (-27.4% → -27.1%).

## Verdicts

`dart run benchmark/ab_drift_check.dart --input=... --markdown`, pooling passes
1+3 as pass 1 and passes 2+4 as pass 2:

| scenario | verdict | pass 1 Δ | pass 2 Δ | worst flagged CV |
|---|---|---:|---:|---:|
| `int20-10k` | inconclusive / neutral | 0.0% | −2.8% | 3.7% |
| `int4-5k` | inconclusive / neutral | −4.2% | −0.4% | 8.9% |
| `mixed6-10k` | inconclusive / neutral | −1.8% | +2.2% | 17.2% |
| `mixed6-1k` | inconclusive / neutral | 0.0% | −0.7% | 16.2% |
| `mixed6-200` | inconclusive / neutral | −2.9% | −5.4% | 5.3% |
| `point1` | **REPRODUCED (real effect)** | −8.7% | −5.8% | 17.7% |
| `point1-wide20` | **REPRODUCED (real effect)** | −28.3% | −26.7% | 10.9% |
| `mixed6-20` | drift-suspected | +10.3% | −7.7% | 15.6% |
| `mispredict-shrink` | drift-suspected | +4.2% | +4.3% | 91.1% |
| `mispredict-mid` | inconclusive / neutral | −5.3% | +1.3% | 19.2% |
| `undershoot-jump` | inconclusive / neutral | −1.8% | −0.5% | 51.9% |
| `undershoot-mid` | inconclusive / neutral | −1.0% | −0.8% | 10.2% |

## First-jump cost

With the high-water rule, `undershoot-mid` raises the mark during warmup and is
inert for every timed sample, so the one-time cost of a statement's first large
execution had to be measured in fresh processes:

```console
<arm>/bundle/bin/select_rows_presize --lane=undershoot-mid --warmup=0 --samples=1 --no-memory
```

50 processes per arm, halves collected in each order. The single timed sample is
the first 3,300-row execution the pool has ever seen, behind eight 20-row
executions that have already set the mark to 20.

| arm | median | p10 | p90 |
|---|---:|---:|---:|
| baseline | 927.5 us | 883 | 1064 |
| candidate | 942.5 us | 872 | 1066 |

**+1.6%**, about 15 us, inside the p10–p90 spread of either arm. Arithmetic
account: four more growths, ~15,200 more slot copies, ~13,800 more slots
zero-filled.

## Peak RSS

`ProcessInfo.maxRss` per lane-isolated process (exp 261's instrument), all four
passes, baseline/candidate:

| lane | pass 1 | pass 2 | pass 3 | pass 4 |
|---|---:|---:|---:|---:|
| `int20-10k` | 64.6 / 64.5 | 64.8 / 64.5 | 64.7 / 64.6 | 64.4 / 64.7 |
| `int4-5k` | 48.2 / 40.5 | 40.9 / 40.9 | 40.7 / 40.7 | 40.8 / 40.7 |
| `mixed6-10k` | 95.5 / 95.6 | 95.6 / 95.6 | 97.5 / 95.7 | 95.5 / 95.5 |
| `mixed6-1k` | 29.6 / 29.7 | 29.7 / 29.6 | 29.7 / 29.6 | 29.4 / 29.7 |
| `mixed6-200` | 24.6 / 29.5 | 25.0 / 23.5 | 24.3 / 23.5 | 24.9 / 23.5 |
| `point1` | 29.5 / 29.6 | 29.5 / 29.8 | 29.6 / 29.7 | 29.7 / 29.3 |
| `point1-wide20` | 24.0 / 23.8 | 23.7 / 23.7 | 23.6 / 23.9 | 23.7 / 23.8 |
| `mixed6-20` | 29.6 / 29.5 | 29.7 / 29.7 | 29.6 / 29.8 | 29.5 / 29.8 |
| `mispredict-shrink` | 185.3 / 101.8 | 220.3 / 228.9 | 99.3 / 99.4 | 251.8 / 207.9 |
| `mispredict-mid` | 106.6 / 106.8 | 106.8 / 106.8 | 106.9 / 106.8 | 106.7 / 106.8 |
| `undershoot-jump` | 105.8 / 92.8 | 105.7 / 105.6 | 90.3 / 105.9 | 105.8 / 105.8 |
| `undershoot-mid` | 55.7 / 56.1 | 55.4 / 55.5 | 55.1 / 57.8 | 55.5 / 58.4 |

Every lane that holds one read live at a time is flat within about 1 MB, and
that is the expected reading rather than a surprise: Dart releases a truncated
growable list's backing store, so the fixed allocation was never *retained*. This
change removes transient allocation work and garbage, not footprint — the same
conclusion exp 263 reached about the row representation from the other direction.

Two lanes carry no memory signal at all and should not be read as one.
`mispredict-shrink` and `undershoot-jump` issue their poison through
`Future.wait`, so peak RSS is set by how many 8,000-row reads happen to be live
together; `mispredict-shrink`'s **baseline** alone reads 185.3, 220.3, 99.3 and
251.8 MB across the four passes. Any candidate-vs-baseline difference on those two
is scheduling, not allocation.

`undershoot-mid` is up 2.3-2.9 MB in two of four passes. `maxRss` is a
process-lifetime high-water and includes warmup, where the candidate pays its
one-time doubling chain to a 38,400-slot buffer against the baseline's 24,576 —
about 110 KB of extra live buffer plus its transient predecessors. It is the
mispredict showing up in memory as well as in time, once per process.
