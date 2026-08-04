# Experiment 261: A memory guard for focused experiments, and four months of trend

**Date:** 2026-08-04
**Status:** Accepted
**Category:** Measurement
**Direction:** `measurement-system`, `result-transfer-shape`
**Benchmark Run:** none — focused AOT harness plus a historical sweep;
  [`benchmark/shared/memory_probe.dart`](../benchmark/shared/memory_probe.dart)
  wired into
  [`benchmark/experiments/select_rows_presize.dart`](../benchmark/experiments/select_rows_presize.dart),
  full tables in
  [`benchmark/results/2026-08-04T19-10-00Z-exp261-focused-memory-guard.md`](../benchmark/results/2026-08-04T19-10-00Z-exp261-focused-memory-guard.md)

## Problem

Focused AOT A/B harnesses are where experiments are actually decided now — exps
251, 254, 258, 259 and 260 were all settled by one — and they measure wall time
and nothing else. A candidate could halve a lane's latency and double its memory
without anything noticing.

The release suite does have a Memory suite (`benchmark/suites/memory.dart`, RSS
deltas over four workloads, feeding `rssDeltaMedMB` into `history.json`), but it
is not where decisions get made, nothing ever *fails* on it, and it is currently
unreachable: it runs at stage `[15/16]`, which is exactly where the sqlite_async
peer segfaults (see exp 260's test plan). `signals.json` has carried an
unclaimed candidate for "memory profiling harness with per-benchmark RSS
acceptance criteria" since 2026-05-02.

[Exp 260](260-result-list-presize.md) made the gap concrete. It shipped a memory
paragraph derived from arithmetic on the allocation path, because no instrument
existed to check it — and that paragraph was wrong twice over, first overstating
a win and then, once corrected, predicting a possible regression that
measurement has now refuted.

## Hypothesis

A per-lane memory reading, in the mode focused harnesses already run in, is
enough to catch gross regressions — and running it over the project's history
will show whether memory has drifted while nobody was looking.

## Approach

### What was available

The instrument was chosen by elimination, not preference:

- **An AOT binary has no VM service.** `Service.getInfo()` returns null and
  `--enable-vm-service` is rejected outright ("Unrecognized flags"). So heap
  statistics and allocation profiles are unavailable, and running the candidate
  under JIT to obtain them would change the thing being measured — exp 193
  requires AOT for any decode-path result.
- That leaves `ProcessInfo.currentRss` / `maxRss`. A `currentRss` read costs
  ~700 ns, so it has to stay outside the stopwatch.

### The instrument

`benchmark/shared/memory_probe.dart` is a `MemoryProbe` a harness starts after
seeding and warmup, samples between timed iterations, and finishes into a
`MemoryReading` printed as `key=value` fields beside the existing
`shape=... median_us=...` line.

The load-bearing discovery is **which reading to gate on**. On a lane whose
results cross `sacrificeSlotThreshold`, the two disagreed by 76 percentage
points about the same change:

| reading | pre-260 | post-260 |
|---|---:|---:|
| sampled `currentRss` peak | 36.6 MB | 64.0 MB (**+75%**) |
| `maxRss` high-water | 65.9 MB | 64.8 MB (**−1.7%**) |

Both are honest. `maxRss` is the true high-water; a sampled `currentRss` curve
says how much is resident at the instants you looked, which is a *retention*
signal — and retention moves when reader isolates are sacrificed and hand their
pages back. Within a single isolate the VM keeps pages after GC, so a candidate
that frees more of its own garbage reads as "no change"; a whole isolate exiting
does return memory, which is why a sacrificing lane's `currentRss` falls and a
non-sacrificing one's does not. **Gate on `maxRss`.** Because `maxRss` is a
process-lifetime high-water, a per-lane figure requires one process per lane —
`--lane=<name>` — and the reading records `lane_isolated` so a contaminated
number cannot be mistaken for a clean one.

### Validation

- **Repeatability**: five runs per arm, isolated processes. `int20-10k` gave
  36.0/36.6/36.5/36.5/36.5 against 63.9/63.8/63.9/63.9/63.9 — spread ≤0.6 MB.
- **Inert controls**: the two lanes that return fewer rows than the initial
  buffer holds read identically across arms (23.4/1.6 MB both).
- **No perturbation**: the same binary with `--no-memory` moved wall time 4680 →
  4570 µs and 6155 → 6075 µs, both inside the 3% effect floor.

## Results

### The guard, applied to exp 260

Measured `maxRss`, one process per lane. This is the measurement exp 260's claim
260.4 could only reason about:

| lane | exp 259 (pre) | main (post-260) | Δ |
|---|---:|---:|---:|
| `int20-10k` | 65.6 MB | 64.2 MB | −2.1% |
| `mixed6-10k` | 108.2 MB | 95.8 MB | **−11.5%** |
| `int4-5k` | 43.9 MB | 31.6 MB | **−28.0%** |
| `point1` (control) | 29.7 MB | 29.6 MB | −0.3% |

Exp 260 **reduced** peak memory on every lane. Its own arithmetic had predicted
peak capacity could rise 22-25% on results landing just under a doubling
boundary; measured peak RSS falls everywhere. The arithmetic was not wrong about
capacity — it was measuring the wrong thing, because the buffer is a small part
of what a read holds and the doubling sequence's retained intermediate arrays
are a larger one.

### Four months of trend

The same harness, built and run at eight checkpoints from v0.3.0 to today.
`maxRss`, MB:

| checkpoint | date | `int20-10k` | `mixed6-10k` | `int4-5k` | `point1` |
|---|---|---:|---:|---:|---:|
| v0.3.0 | 2026-05-03 | 65.8 | 108.0 | 44.2 | 29.7 |
| exp 159 | 2026-06-09 | 65.7 | 107.9 | 44.2 | 29.7 |
| v0.5.0 | 2026-06-16 | 65.8 | 108.0 | 43.9 | 29.8 |
| v0.7.0 | 2026-06-30 | 65.5 | 108.0 | 43.8 | 29.6 |
| exp 236 | 2026-07-21 | 65.3 | 107.8 | 43.9 | 29.6 |
| exp 246 | 2026-07-23 | 65.5 | 108.0 | 43.9 | 29.7 |
| exp 259 | 2026-08-03 | 65.6 | 108.2 | 43.9 | 29.7 |
| main | 2026-08-04 | **64.2** | **95.8** | **31.6** | 29.6 |

**Peak read-path memory did not move for three months.** From v0.3.0 through
exp 259 — across roughly forty merged experiments including the whole
transfer-shape arc (exps 174, 234, 236, 243, 244, 245, 246) — every lane stays
within ~1 MB. Wall time over the same window fell substantially (`mixed6-10k`
4052 → 3066 µs, `int20-10k` 6694 → 6094 µs), so the flatness is not the harness
failing to see the library change.

The only movement in the observed window is the last two experiments, both
downward. Exp 259 drops `mixed6-10k`'s post-warmup resident from 89.5 to 82.6 MB
(the per-cell `ExternalTypedData` word view it removed) while leaving peak
unchanged; exp 260 drops peak itself.

## Outcome

**Accepted**, as measurement infrastructure with a completed first use.

No memory regression exists to fix — which is the answer to "have we been
trending in the wrong way", and it is worth having established rather than
assumed. Three things the sweep surfaced that are worth a future runner's time:

1. **The guard is coarse, and the numbers say how coarse.** Four months of
   experiments that moved wall time 25-40% moved peak RSS by under 1%. This is a
   tripwire for a doubling, not an instrument for a 5% drift. Anything finer
   needs allocation counters at specific sites, not process RSS.
2. **Seeding dominates the number being gated.** `mixed6-10k` sits at 89.5 MB
   before the measured reads even start, and the reads add ~18 MB. Gating a lane
   on `maxRss` therefore mostly gates its setup, which is identical in both arms
   — the guard is real but diluted, and a lane designed for memory should seed
   as little as it can.
3. **`select()` costs far more than its payload.** `mixed6-10k` reads a table
   holding roughly 1.5 MB of actual data and peaks at 95 MB. Some of that is
   `List<Map<String, Object?>>` overhead the API commits to, but a ~60× ratio has
   never been decomposed, and exps 008/032's lazy and facade shapes were assessed
   against wall time rather than this.

Would revisit the choice of instrument if AOT gains a service protocol, or if a
future experiment's *subject* is memory rather than its guard — in which case a
direct allocation counter beats RSS at any granularity.

## Test plan

- `dart analyze --fatal-infos` on the probe and the harness — clean
- Repeatability, inert-control and no-perturbation checks above
- Historical sweep built and run at eight checkpoints; v0.3.0 (2026-05-03)
  resolves, builds and runs the current harness unmodified
