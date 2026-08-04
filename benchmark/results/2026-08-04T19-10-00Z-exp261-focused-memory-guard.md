# Experiment 261: focused-harness memory guard + historical trend

Collected 2026-08-04 on arm64 macOS 26.2 (Apple M1 Pro) with Dart 3.12.2.

Instrument: `benchmark/shared/memory_probe.dart`, wired into
[`benchmark/experiments/select_rows_presize.dart`](../experiments/select_rows_presize.dart).
Every figure in the **guard and sweep tables** is `maxRss` (`ProcessInfo.maxRss`)
with **one process per lane** (`--lane=<name>`), since `maxRss` is a
process-lifetime high-water and a shared process would let each lane inherit the
previous lane's watermark. The instrument-validation section below is the
exception and says so: repeatability is reported on the sampled `rss_peak_mb`,
because the point of that table is to show how stable the *sampled* reading is
next to the high-water it disagrees with.

```console
dart build cli --target=bin/presize_ab.dart --output=<checkpoint>
<checkpoint>/bundle/bin/presize_ab --lane=<name> --samples=21
```

## Why maxRss and not sampled currentRss

Same lane, same change, two readings, opposite verdicts:

| reading | pre-260 | post-260 | Δ |
|---|---:|---:|---:|
| sampled `currentRss` peak | 36.6 MB | 64.0 MB | +75% |
| `maxRss` high-water | 65.9 MB | 64.8 MB | -1.7% |

`maxRss` is the true high-water. A sampled `currentRss` curve reports how much
is resident at the instants sampled, which is a retention signal — and retention
moves when reader isolates are sacrificed and return their pages.

## Instrument validation

Repeatability, five runs per arm, isolated processes, `rss_peak_mb`:

| arm | runs |
|---|---|
| pre-260 `int20-10k` | 36.0, 36.6, 36.5, 36.5, 36.5 |
| post-260 `int20-10k` | 63.9, 63.8, 63.9, 63.9, 63.9 |
| pre-260 `mixed6-200` (inert) | 23.4, 23.8, 23.3, 23.3, 23.4 |
| post-260 `mixed6-200` (inert) | 22.8, 23.3, 23.7, 23.7, 23.4 |

Sampling perturbation, same binary with and without `--no-memory`, median us:

| arm | sampling on | sampling off | Δ |
|---|---:|---:|---:|
| pre-260 `int20-10k` | 6155 | 6075 | +1.3% |
| post-260 `int20-10k` | 4680 | 4570 | +2.4% |

Both inside the 3% effect floor.

## Historical sweep

Eight checkpoints, harness source held constant, `dart pub get` + `dart build cli`
per checkpoint. v0.3.0 resolves, builds and runs the current harness unmodified.

### maxRss (MB)

| checkpoint | date | int20-10k | mixed6-10k | int4-5k | point1 |
|---|---|---:|---:|---:|---:|
| v0.3.0 | 2026-05-03 | 65.8 | 108.0 | 44.2 | 29.7 |
| exp 159 | 2026-06-09 | 65.7 | 107.9 | 44.2 | 29.7 |
| v0.5.0 | 2026-06-16 | 65.8 | 108.0 | 43.9 | 29.8 |
| v0.7.0 | 2026-06-30 | 65.5 | 108.0 | 43.8 | 29.6 |
| exp 236 | 2026-07-21 | 65.3 | 107.8 | 43.9 | 29.6 |
| exp 246 | 2026-07-23 | 65.5 | 108.0 | 43.9 | 29.7 |
| exp 259 | 2026-08-03 | 65.6 | 108.2 | 43.9 | 29.7 |
| main (post-260) | 2026-08-04 | 64.2 | 95.8 | 31.6 | 29.6 |

### median wall (us), same runs

One 21-sample run per checkpoint — indicative context for the memory table, not
a rigorous perf comparison (no order flip, no repeats).

| checkpoint | date | int20-10k | mixed6-10k | int4-5k | point1 |
|---|---|---:|---:|---:|---:|
| v0.3.0 | 2026-05-03 | 6694 | 4052 | 801 | 1381 |
| exp 159 | 2026-06-09 | 6700 | 4443 | 802 | 1693 |
| v0.5.0 | 2026-06-16 | 6565 | 4135 | 802 | 1292 |
| v0.7.0 | 2026-06-30 | 6141 | 3817 | 761 | 1097 |
| exp 236 | 2026-07-21 | 6255 | 3796 | 776 | 1150 |
| exp 246 | 2026-07-23 | 6697 | 4130 | 826 | 1860 |
| exp 259 | 2026-08-03 | 6094 | 3066 | 770 | 1456 |
| main (post-260) | 2026-08-04 | 4626 | 2535 | 540 | 1322 |

### Post-warmup resident vs peak, mixed6-10k and int4-5k

`rss_start_mb` is taken after seeding and warmup, so the gap to `rss_peak_mb` is
what the measured reads add.

| checkpoint | mixed6 start | mixed6 peak | int4 start | int4 peak |
|---|---:|---:|---:|---:|
| v0.3.0 | 89.4 | 107.5 | 30.3 | 44.2 |
| exp 159 | 89.3 | 107.5 | 30.3 | 44.2 |
| v0.5.0 | 89.5 | 107.6 | 30.0 | 43.9 |
| v0.7.0 | 89.5 | 107.6 | 30.0 | 43.8 |
| exp 236 | 89.2 | 107.4 | 30.0 | 43.9 |
| exp 246 | 89.5 | 107.6 | 30.1 | 43.9 |
| exp 259 | 82.6 | 108.2 | 30.0 | 43.9 |
| main | 66.6 | 95.2 | 25.3 | 31.6 |

Exp 259 drops post-warmup resident by ~7 MB without moving peak — consistent
with removing a per-cell `ExternalTypedData` view. Exp 260 drops both.
