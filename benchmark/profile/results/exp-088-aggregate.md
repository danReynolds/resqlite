Running build hooks...Running build hooks...Baseline runs (5):
  benchmark/profile/results/baseline-exp088-run1.json
  benchmark/profile/results/baseline-exp088-run2.json
  benchmark/profile/results/baseline-exp088-run3.json
  benchmark/profile/results/baseline-exp088-run4.json
  benchmark/profile/results/baseline-exp088-run5.json
Candidate runs (5):
  benchmark/profile/results/exp-088-run1.json
  benchmark/profile/results/exp-088-run2.json
  benchmark/profile/results/exp-088-run3.json
  benchmark/profile/results/exp-088-run4.json
  benchmark/profile/results/exp-088-run5.json

# Multi-run medians of percentiles

Each cell: median across 5 runs on the baseline side, median across 5 runs on the candidate side.
CV (coefficient of variation) = stddev/mean of the per-run values on the baseline side — gives a sense of how noisy the metric itself is on this bench.

## merge_rounds · executeBatch

| metric | baseline median | candidate median | Δ | Δ% | baseline CV |
|---|---:|---:|---:|---:|---:|
| p50 | 105.0 μs | 109.0 μs | +4.0 μs | +3.8% | 0.9% |
| p90 | 121.0 μs | 141.0 μs | +20.0 μs | +16.5% | 5.5% |
| p99 | 294.0 μs | 381.0 μs | +87.0 μs | +29.6% | 17.4% |
| max | 759.0 μs | 980.0 μs | +221.0 μs | +29.1% | 18.8% |
| work | 95.0 μs | 97.0 μs | +2.0 μs | +2.1% | 1.2% |

Per-run values (baseline / candidate):

| metric | baseline runs | candidate runs |
|---|---|---|
| p50 | 105, 105, 105, 107, 107 | 109, 106, 109, 109, 106 |
| p90 | 121, 116, 120, 136, 123 | 145, 128, 179, 141, 120 |
| p99 | 308, 219, 237, 355, 294 | 381, 262, 962, 631, 216 |
| max | 759, 790, 655, 1102, 747 | 726, 1010, 2538, 980, 680 |
| work | 93, 95, 95, 96, 96 | 98, 94, 97, 98, 92 |

## noop · execute

| metric | baseline median | candidate median | Δ | Δ% | baseline CV |
|---|---:|---:|---:|---:|---:|
| p50 | 11.0 μs | 12.0 μs | +1.0 μs | +9.1% | 6.9% |
| p90 | 20.0 μs | 22.0 μs | +2.0 μs | +10.0% | 6.6% |
| p99 | 65.0 μs | 128.0 μs | +63.0 μs | +96.9% | 16.8% |
| max | 605.0 μs | 3807.0 μs | +3202.0 μs | +529.3% | 84.0% |

Per-run values (baseline / candidate):

| metric | baseline runs | candidate runs |
|---|---|---|
| p50 | 12, 10, 10, 11, 11 | 11, 12, 12, 11, 14 |
| p90 | 21, 20, 19, 20, 23 | 20, 21, 26, 22, 24 |
| p99 | 65, 76, 49, 54, 74 | 181, 74, 128, 72, 152 |
| max | 426, 3635, 605, 604, 2106 | 89669, 3807, 887, 681, 6901 |

## noop · select

| metric | baseline median | candidate median | Δ | Δ% | baseline CV |
|---|---:|---:|---:|---:|---:|
| p50 | 7.0 μs | 7.0 μs | +0.0 μs | +0.0% | 7.4% |
| p90 | 15.0 μs | 16.0 μs | +1.0 μs | +6.7% | 9.7% |
| p99 | 48.0 μs | 98.0 μs | +50.0 μs | +104.2% | 13.8% |
| max | 970.0 μs | 5757.0 μs | +4787.0 μs | +493.5% | 143.7% |

Per-run values (baseline / candidate):

| metric | baseline runs | candidate runs |
|---|---|---|
| p50 | 7, 6, 6, 7, 7 | 6, 7, 7, 6, 8 |
| p90 | 17, 15, 13, 15, 17 | 15, 16, 19, 16, 18 |
| p99 | 48, 57, 39, 44, 55 | 114, 64, 98, 50, 158 |
| max | 1247, 970, 325, 328, 9712 | 21544, 5757, 2477, 373, 25021 |

## point_query · select

| metric | baseline median | candidate median | Δ | Δ% | baseline CV |
|---|---:|---:|---:|---:|---:|
| p50 | 7.0 μs | 7.0 μs | +0.0 μs | +0.0% | 5.6% |
| p90 | 11.0 μs | 12.0 μs | +1.0 μs | +9.1% | 5.7% |
| p99 | 27.0 μs | 47.0 μs | +20.0 μs | +74.1% | 20.6% |
| max | 565.0 μs | 1944.0 μs | +1379.0 μs | +244.1% | 117.6% |
| work | 0.0 μs | 1.0 μs | +1.0 μs | +0.0% | 133.3% |

Per-run values (baseline / candidate):

| metric | baseline runs | candidate runs |
|---|---|---|
| p50 | 7, 8, 7, 7, 7 | 7, 7, 8, 7, 8 |
| p90 | 11, 11, 10, 11, 12 | 12, 10, 13, 12, 13 |
| p99 | 25, 27, 23, 30, 40 | 30, 26, 51, 53, 47 |
| max | 335, 373, 624, 565, 3832 | 642, 702, 5396, 11245, 1944 |
| work | 0, 2, 1, 0, 0 | 1, 0, 1, 1, 0 |

## single_insert · execute

| metric | baseline median | candidate median | Δ | Δ% | baseline CV |
|---|---:|---:|---:|---:|---:|
| p50 | 17.0 μs | 18.0 μs | +1.0 μs | +5.9% | 2.4% |
| p90 | 23.0 μs | 31.0 μs | +8.0 μs | +34.8% | 7.0% |
| p99 | 67.0 μs | 182.0 μs | +115.0 μs | +171.6% | 22.2% |
| max | 1246.0 μs | 3918.0 μs | +2672.0 μs | +214.4% | 22.8% |
| work | 6.0 μs | 6.0 μs | +0.0 μs | +0.0% | 14.9% |

Per-run values (baseline / candidate):

| metric | baseline runs | candidate runs |
|---|---|---|
| p50 | 17, 17, 17, 16, 17 | 17, 16, 18, 18, 19 |
| p90 | 25, 21, 24, 21, 23 | 22, 22, 31, 32, 31 |
| p99 | 94, 53, 77, 54, 67 | 55, 49, 382, 305, 182 |
| max | 1104, 1985, 1280, 1246, 1246 | 808, 1074, 9889, 14407, 3918 |
| work | 5, 7, 7, 5, 6 | 6, 4, 6, 7, 5 |

## noop_floors (dispatch baseline)

| metric | baseline median | candidate median | Δ |
|---|---:|---:|---:|
| reader_us | 7.0 μs | 7.0 μs | +0.0 μs |
| writer_us | 11.0 μs | 12.0 μs | +1.0 μs |
