Running build hooks...Running build hooks...Baseline runs (3):
  benchmark/profile/results/baseline-exp093-run1.json
  benchmark/profile/results/baseline-exp093-run2.json
  benchmark/profile/results/baseline-exp093-run3.json
Candidate runs (3):
  benchmark/profile/results/exp-093-run1.json
  benchmark/profile/results/exp-093-run2.json
  benchmark/profile/results/exp-093-run3.json

# Multi-run medians of percentiles

Each cell: median across 3 runs on the baseline side, median across 3 runs on the candidate side.
CV (coefficient of variation) = stddev/mean of the per-run values on the baseline side — gives a sense of how noisy the metric itself is on this bench.

## merge_rounds · executeBatch

| metric | baseline median | candidate median | Δ | Δ% | baseline CV |
|---|---:|---:|---:|---:|---:|
| p50 | 106.0 μs | 109.0 μs | +3.0 μs | +2.8% | 2.4% |
| p90 | 120.0 μs | 158.0 μs | +38.0 μs | +31.7% | 10.5% |
| p99 | 280.0 μs | 615.0 μs | +335.0 μs | +119.6% | 30.1% |
| max | 816.0 μs | 1726.0 μs | +910.0 μs | +111.5% | 7.0% |
| work | 95.0 μs | 98.0 μs | +3.0 μs | +3.2% | 2.3% |

Per-run values (baseline / candidate):

| metric | baseline runs | candidate runs |
|---|---|---|
| p50 | 105, 106, 111 | 109, 106, 109 |
| p90 | 120, 120, 149 | 169, 117, 158 |
| p99 | 253, 280, 481 | 684, 275, 615 |
| max | 884, 744, 816 | 1726, 810, 1934 |
| work | 94, 95, 99 | 98, 95, 98 |

## noop · execute

| metric | baseline median | candidate median | Δ | Δ% | baseline CV |
|---|---:|---:|---:|---:|---:|
| p50 | 11.0 μs | 11.0 μs | +0.0 μs | +0.0% | 4.2% |
| p90 | 22.0 μs | 22.0 μs | +0.0 μs | +0.0% | 8.0% |
| p99 | 69.0 μs | 96.0 μs | +27.0 μs | +39.1% | 14.5% |
| max | 569.0 μs | 936.0 μs | +367.0 μs | +64.5% | 16.4% |

Per-run values (baseline / candidate):

| metric | baseline runs | candidate runs |
|---|---|---|
| p50 | 11, 11, 12 | 11, 11, 11 |
| p90 | 22, 19, 23 | 22, 22, 26 |
| p99 | 69, 62, 87 | 85, 96, 144 |
| max | 569, 484, 718 | 936, 896, 3046 |

## noop · select

| metric | baseline median | candidate median | Δ | Δ% | baseline CV |
|---|---:|---:|---:|---:|---:|
| p50 | 7.0 μs | 7.0 μs | +0.0 μs | +0.0% | 7.1% |
| p90 | 15.0 μs | 17.0 μs | +2.0 μs | +13.3% | 11.5% |
| p99 | 53.0 μs | 71.0 μs | +18.0 μs | +34.0% | 19.3% |
| max | 610.0 μs | 1193.0 μs | +583.0 μs | +95.6% | 44.3% |

Per-run values (baseline / candidate):

| metric | baseline runs | candidate runs |
|---|---|---|
| p50 | 6, 7, 7 | 7, 7, 7 |
| p90 | 15, 15, 19 | 17, 17, 18 |
| p99 | 53, 46, 72 | 63, 71, 98 |
| max | 262, 610, 904 | 678, 1193, 1302 |

## point_query · select

| metric | baseline median | candidate median | Δ | Δ% | baseline CV |
|---|---:|---:|---:|---:|---:|
| p50 | 7.0 μs | 7.0 μs | +0.0 μs | +0.0% | 0.0% |
| p90 | 11.0 μs | 12.0 μs | +1.0 μs | +9.1% | 8.1% |
| p99 | 33.0 μs | 38.0 μs | +5.0 μs | +15.2% | 14.6% |
| max | 1179.0 μs | 2732.0 μs | +1553.0 μs | +131.7% | 92.7% |
| work | 0.0 μs | 0.0 μs | +0.0 μs | +0.0% | 141.4% |

Per-run values (baseline / candidate):

| metric | baseline runs | candidate runs |
|---|---|---|
| p50 | 7, 7, 7 | 8, 7, 7 |
| p90 | 11, 11, 13 | 13, 12, 12 |
| p99 | 33, 30, 42 | 41, 37, 38 |
| max | 4831, 321, 1179 | 3772, 592, 2732 |
| work | 1, 0, 0 | 1, 0, 0 |

## single_insert · execute

| metric | baseline median | candidate median | Δ | Δ% | baseline CV |
|---|---:|---:|---:|---:|---:|
| p50 | 18.0 μs | 18.0 μs | +0.0 μs | +0.0% | 4.5% |
| p90 | 25.0 μs | 27.0 μs | +2.0 μs | +8.0% | 5.1% |
| p99 | 77.0 μs | 130.0 μs | +53.0 μs | +68.8% | 14.4% |
| max | 1379.0 μs | 1612.0 μs | +233.0 μs | +16.9% | 13.4% |
| work | 7.0 μs | 7.0 μs | +0.0 μs | +0.0% | 18.7% |

Per-run values (baseline / candidate):

| metric | baseline runs | candidate runs |
|---|---|---|
| p50 | 19, 18, 17 | 19, 18, 18 |
| p90 | 26, 25, 23 | 29, 24, 27 |
| p99 | 90, 77, 63 | 137, 96, 130 |
| max | 1379, 1246, 1708 | 2721, 1455, 1612 |
| work | 8, 7, 5 | 8, 7, 7 |

## noop_floors (dispatch baseline)

| metric | baseline median | candidate median | Δ |
|---|---:|---:|---:|
| reader_us | 7.0 μs | 7.0 μs | +0.0 μs |
| writer_us | 11.0 μs | 11.0 μs | +0.0 μs |
