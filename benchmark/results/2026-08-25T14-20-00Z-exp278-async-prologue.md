# Experiment 278 — the async read prologue, priced and then measured

Collected 2026-08-25 on arm64 macOS 26.2 (Apple M1 Pro, 10 cores, reader pool
= 4) with Dart 3.12.x. Baseline is `origin/main` at `720460a`; candidate is the
same tree with `Database.select`, `Database.selectBytes` and the first-scan half
of `ReaderPool._dispatch` made non-`async`, plus the `_resolvedRuntime` field
the write paths also read. Two native-asset-aware AOT CLI bundles built with
`dart build cli` from one unchanged harness source:

```console
dart build cli --target=bin/_exp278_dispatch_ab.dart --output=<arm>
<arm>/bundle/bin/_exp278_dispatch_ab --lane=<lane> --warmup=12 --samples=121
```

`bin/` held only a two-line forwarder, because that is where `dart build cli`
requires the entry point to live; the harness itself is
[`benchmark/experiments/reader_dispatch_stickiness.dart`](../experiments/reader_dispatch_stickiness.dart)
(exp 266's, byte-identical in both worktrees). Every lane is lane-isolated —
one fresh process per lane per arm — and passes alternate collection order (odd
baseline-first, even candidate-first).

## Part 1 — what the prologue costs, with no database in the picture

[`benchmark/experiments/async_prologue_price.dart`](../experiments/async_prologue_price.dart),
built with `dart compile exe`, five runs of 21 samples × 200,000 calls. No
SQLite, no isolates, no resqlite code: a sync completer resolved from a separate
microtask, reached through four different amounts of async plumbing. The
absolute figures include the completer allocation and the loop, so only the
differences mean anything.

| shape | ns/call (median of 5 runs) | spread across runs | Δ vs `direct` |
|---|---:|---|---:|
| `direct` — caller awaits the completer's future | 176.0 | 174.6–181.5 | — |
| `resolved` — one resolved future awaited first | 246.7 | 244.9–258.8 | **+70.7** |
| `frame1` — one `async` forwarder | 210.6 | 208.3–214.4 | **+34.6** |
| `frame3` — resolved await + three `async` forwarders | 318.7 | 312.6–336.4 | **+142.7** |

`frame3` is the shape `Database.select` → `ReaderPool.select` →
`ReaderPool._dispatch` → `_WorkerSlot.request` had; `frame1` is what the
candidate leaves. **The candidate removes ~108 ns per read**, and the whole
prologue including the resolved-future await is worth ~143 ns.

Divide by what it wraps:

| operation | wall per call | ceiling from 108 ns |
|---|---:|---:|
| `point1` — 1-row 6-column point read | ~5.4 us | **2.0%** |
| `mixed6-20` — 20-row page | ~9.9 us | 1.1% |
| `mixed6-1k` — 1,000-row read | ~227 us | 0.05% |
| `mixed6-10k` — 10,000-row read (sacrificed) | ~2,622 us | 0.004% |

Exp 171 put the `await _runtime` hop at "~1–2 us per call" and derived 6–12% of
headroom on a 2,000-call write burst from that figure. It measures **70.7 ns** —
14–28× smaller — so the headroom it went looking for was never there.

## Part 2 — end to end, twelve alternating-order passes

Twelve passes in two collections of six, 121 samples per lane per arm.
Collection 1 (passes 1–6) was taken at 76.7% CPU idle, load average 4.77 on ten
cores. Collection 2 (passes 7–12) started after a four-minute gap and ran into a
busier host — load average 8.64, 63.3% idle at the close, and per-lane CVs up to
100–290% against collection 1's 8–20%. Collection 1 is the one to read;
collection 2 is reported in full because suppressing it would be cherry-picking,
and because its drift is itself the calibration.

Percentages are candidate against baseline within the same pass.

| lane | c1p1 | c1p2 | c1p3 | c1p4 | c1p5 | c1p6 | c2p7 | c2p8 | c2p9 | c2p10 | c2p11 | c2p12 | median |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `point1` | +0.1% | -4.0% | +2.5% | +6.2% | -2.7% | -2.5% | -8.6% | -38.7% | +7.1% | -13.4% | +7.1% | -1.8% | **-2.1%** |
| `point1-wide20` | -6.8% | +1.6% | +1.1% | -0.3% | -0.1% | -8.8% | -2.4% | +12.9% | +3.3% | +24.3% | -3.5% | +2.4% | **+0.5%** |
| `mixed6-20` | +1.9% | +0.2% | +13.4% | -0.6% | +7.2% | +3.3% | -1.9% | -10.4% | -1.2% | -5.6% | -5.6% | +0.8% | **-0.2%** |
| `first4-newsql` | +13.9% | -11.6% | +0.0% | +5.4% | -7.3% | -7.5% | +8.1% | +4.8% | +7.7% | -20.0% | -7.3% | -11.9% | **-3.7%** |
| `first8-newsql` | -12.7% | +1.4% | +20.0% | -8.6% | +1.4% | +4.8% | -7.5% | -13.3% | -5.3% | -1.3% | +0.0% | -12.2% | **-3.3%** |
| `first32-newsql` | -11.1% | -11.1% | -15.5% | -0.5% | -10.9% | -5.2% | -14.1% | +3.3% | +8.9% | +22.2% | -11.1% | -8.9% | **-9.9%** |
| `alternating-sql` | -3.4% | -18.7% | -4.5% | -1.5% | -1.8% | -1.0% | -11.8% | +2.7% | +10.7% | -4.9% | -1.6% | +1.2% | **-1.7%** |
| `mixed6-1k` | +2.0% | +4.9% | +1.1% | +0.9% | +0.9% | -1.1% | -7.7% | +0.1% | +14.5% | +4.1% | +2.5% | -1.2% | **+1.0%** |
| `conc4` | -7.8% | +4.6% | +3.0% | -2.1% | -5.9% | -4.7% | +1.7% | -5.2% | -1.2% | +10.9% | -6.8% | -6.1% | **-3.4%** |
| `conc8` | -1.4% | -2.9% | +1.7% | +1.4% | -6.6% | -6.5% | -37.7% | -9.8% | -7.6% | -5.7% | +17.2% | +2.6% | **-4.3%** |
| `mixed6-10k` | +0.0% | -1.2% | -2.7% | -8.5% | -2.3% | -0.1% | +7.9% | +3.9% | -1.3% | +2.2% | -0.3% | -23.5% | **-0.8%** |
| `bytes-first8-newsql` | -3.5% | -2.5% | +9.2% | -8.4% | -3.8% | -1.3% | +3.8% | +1.1% | -1.2% | +7.7% | -10.3% | -2.5% | **-1.9%** |

### Absolute medians, all 12 passes pooled

| lane | base us | cand us | pooled Δ | base CV | cand CV | base peak RSS | cand peak RSS |
|---|---:|---:|---:|---:|---:|---:|---:|
| `point1` | 1080 | 1048 | -3.0% | 32.6% | 14.9% | 30.1 MB | 30.1 MB |
| `point1-wide20` | 1208 | 1193 | -1.2% | 21.2% | 61.9% | 24.2 MB | 23.8 MB |
| `mixed6-20` | 494 | 496 | +0.4% | 79.2% | 21.4% | 30.2 MB | 30.0 MB |
| `first4-newsql` | 40 | 39 | -2.5% | 235.3% | 157.1% | 27.2 MB | 26.8 MB |
| `first8-newsql` | 71 | 69 | -2.8% | 75.1% | 36.3% | 29.6 MB | 28.7 MB |
| `first32-newsql` | 210 | 198 | -5.5% | 31.4% | 45.8% | 30.6 MB | 30.7 MB |
| `alternating-sql` | 1584 | 1528 | -3.5% | 26.8% | 21.4% | 30.1 MB | 30.1 MB |
| `mixed6-1k` | 1134 | 1148 | +1.2% | 113.5% | 19.3% | 42.4 MB | 30.1 MB |
| `conc4` | 1486 | 1459 | -1.8% | 25.4% | 19.7% | 30.9 MB | 31.0 MB |
| `conc8` | 1525 | 1472 | -3.5% | 31.6% | 16.1% | 31.0 MB | 30.8 MB |
| `mixed6-10k` | 2622 | 2546 | -2.9% | 22.2% | 43.5% | 95.7 MB | 95.8 MB |
| `bytes-first8-newsql` | 82 | 81 | -1.2% | 38.3% | 34.6% | 28.4 MB | 27.5 MB |

Medians are per sample, not per read: `point1` and `point1-wide20` time 200
sequential reads, `mixed6-20` 50, `mixed6-1k` 5, `alternating-sql` 100 statement
pairs, `conc4` 50 groups of four, `conc8` 25 groups of eight, `first{4,8,32}` the
first N executions of a SQL string no worker has seen, and `mixed6-10k` one
60,000-slot read that crosses `sacrificeSlotThreshold` and ends its worker.

**`mixed6-10k` is the ruler.** One 108 ns prologue inside a 2,622 us sample is
0.004% — the candidate cannot move that lane. It reads -2.9% pooled. Every lane
in the pooled table sits between -3.5% and +1.2%, so a pooled movement of about
3% in this collection is the apparatus, not the code, and `point1`'s -3.0% is
the same number as the control's.

### `ab_drift_check.dart` verdicts, primary lanes

Each pass pair is one order-flipped scenario, its 121 per-sample values fed to
[`benchmark/ab_drift_check.dart`](../ab_drift_check.dart).

| scenario | verdict | pass 1 Δ | pass 2 Δ |
|---|---|---:|---:|
| `point1` c1 p1/p2 | inconclusive / neutral | +0.1% | -4.0% |
| `point1` c1 p3/p4 | inconclusive / neutral | +2.5% | +6.2% |
| `point1` c1 p5/p6 | inconclusive / neutral | -2.7% | -2.5% |
| `point1` c2 p7/p8 | drift-suspected | -8.6% | -38.7% |
| `point1` c2 p9/p10 | drift-suspected | +7.1% | -13.4% |
| `point1` c2 p11/p12 | inconclusive / neutral | +7.1% | -1.8% |
| `point1-wide20` c1 p1/p2 | inconclusive / neutral | -6.8% | +1.6% |
| `point1-wide20` c1 p3/p4 | inconclusive / neutral | +1.1% | -0.3% |
| `point1-wide20` c1 p5/p6 | inconclusive / neutral | -0.1% | -8.8% |
| `point1-wide20` c2 p9/p10 | REPRODUCED — **slower** | +3.3% | +24.3% |
| `mixed6-20` c1 p5/p6 | REPRODUCED — **slower** | +7.2% | +3.3% |
| `mixed6-20` (other five pairs) | inconclusive / neutral | — | — |

**No primary-lane pair reproduced a win in either collection.** Of the eighteen
primary-lane scenarios, fourteen classify neutral, two drift-suspected, and the
two that classify REPRODUCED point the wrong way. Across all twelve lanes the
scattered REPRODUCED verdicts land in both directions — `conc8` faster,
`mixed6-1k` and `mixed6-10k` slower, `first32-newsql` faster — which is what
drift looks like, not an effect.

`first32-newsql` is the one lane whose median (-9.9%, nine of twelve passes
negative) invites a second look, and the mechanism is what rules it out. That
lane times 32 executions at ~6.6 us each, so the prologue is worth the same ~2%
there as on `point1` — which read -2.1%. A real 10% on `first32` with `point1`
flat is not this change; its two collection-2 pairs also reverse sign, and its
CV runs 31–46% against `point1`'s 11–13%.

## Guards

- `conc4` / `conc8` — the parking loop moved to `_dispatchParked`; both read
  neutral-to-faster with sign flips, so fairness and wake ordering are intact.
  `test/reader_pool_test.dart` (four un-awaited reads must leave
  `availableWorkerCount` at zero) passes on the candidate.
- `mixed6-10k` — the sacrifice path is unchanged, and reads as the control it is.
- `bytes-first8-newsql` — `selectBytes` now wraps its reply through `then`
  instead of an `await`; -1.9% median, six passes each way.
- Peak RSS moves nowhere. `mixed6-1k`'s 42.4 vs 30.1 MB is a bimodal GC
  artefact, not an arm effect: both arms produce ~30 MB and ~55 MB samples
  across the twelve passes and the median lands on different modes.
- Full suite: 503 tests pass on the candidate.
