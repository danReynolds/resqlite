Baseline runs (3):
  /tmp/resqlite-exp104-baseline/benchmark/profile/results/exp104-baseline-r4.json
  /tmp/resqlite-exp104-baseline/benchmark/profile/results/exp104-baseline-r5.json
  /tmp/resqlite-exp104-baseline/benchmark/profile/results/exp104-baseline-r6.json
Candidate runs (3):
  benchmark/profile/results/exp104-candidate-r7.json
  benchmark/profile/results/exp104-candidate-r8.json
  benchmark/profile/results/exp104-candidate-r9.json

# Multi-run medians of percentiles

Each cell: median across 3 runs on the baseline side, median across 3 runs on the candidate side.
CV (coefficient of variation) = stddev/mean of the per-run values on the baseline side — gives a sense of how noisy the metric itself is on this bench.

## merge_rounds · executeBatch

| metric | baseline median | candidate median | Δ | Δ% | baseline CV |
|---|---:|---:|---:|---:|---:|
| p50 | 100.0 μs | 103.0 μs | +3.0 μs | +3.0% | 1.2% |
| p90 | 112.0 μs | 124.0 μs | +12.0 μs | +10.7% | 3.4% |
| p99 | 204.0 μs | 339.0 μs | +135.0 μs | +66.2% | 4.8% |
| max | 781.0 μs | 877.0 μs | +96.0 μs | +12.3% | 8.1% |
| work | 91.0 μs | 94.0 μs | +3.0 μs | +3.3% | 0.9% |

Per-run values (baseline / candidate):

| metric | baseline runs | candidate runs |
|---|---|---|
| p50 | 102, 100, 99 | 106, 101, 103 |
| p90 | 115, 112, 106 | 124, 111, 125 |
| p99 | 203, 225, 204 | 339, 249, 464 |
| max | 902, 781, 749 | 885, 806, 877 |
| work | 92, 91, 90 | 97, 92, 94 |

## noop · execute

| metric | baseline median | candidate median | Δ | Δ% | baseline CV |
|---|---:|---:|---:|---:|---:|
| p50 | 9.0 μs | 9.0 μs | +0.0 μs | +0.0% | 5.1% |
| p90 | 20.0 μs | 16.0 μs | -4.0 μs | -20.0% | 8.2% |
| p99 | 99.0 μs | 36.0 μs | -63.0 μs | -63.6% | 17.9% |
| max | 1118.0 μs | 264.0 μs | -854.0 μs | -76.4% | 80.9% |

Per-run values (baseline / candidate):

| metric | baseline runs | candidate runs |
|---|---|---|
| p50 | 10, 9, 9 | 9, 9, 9 |
| p90 | 23, 19, 20 | 16, 15, 16 |
| p99 | 123, 79, 99 | 35, 36, 37 |
| max | 1118, 5516, 1083 | 264, 293, 260 |

## noop · select

| metric | baseline median | candidate median | Δ | Δ% | baseline CV |
|---|---:|---:|---:|---:|---:|
| p50 | 6.0 μs | 5.0 μs | -1.0 μs | -16.7% | 8.3% |
| p90 | 14.0 μs | 10.0 μs | -4.0 μs | -28.6% | 11.6% |
| p99 | 83.0 μs | 20.0 μs | -63.0 μs | -75.9% | 15.9% |
| max | 655.0 μs | 273.0 μs | -382.0 μs | -58.3% | 31.1% |

Per-run values (baseline / candidate):

| metric | baseline runs | candidate runs |
|---|---|---|
| p50 | 6, 6, 5 | 5, 5, 5 |
| p90 | 17, 13, 14 | 10, 10, 10 |
| p99 | 86, 59, 83 | 23, 20, 20 |
| max | 655, 1105, 554 | 298, 268, 273 |

## point_query · select

| metric | baseline median | candidate median | Δ | Δ% | baseline CV |
|---|---:|---:|---:|---:|---:|
| p50 | 7.0 μs | 6.0 μs | -1.0 μs | -14.3% | 7.1% |
| p90 | 8.0 μs | 9.0 μs | +1.0 μs | +12.5% | 5.7% |
| p99 | 25.0 μs | 13.0 μs | -12.0 μs | -48.0% | 8.3% |
| max | 7952.0 μs | 376.0 μs | -7576.0 μs | -95.3% | 56.1% |
| work | 1.0 μs | 1.0 μs | +0.0 μs | +0.0% | 81.6% |

Per-run values (baseline / candidate):

| metric | baseline runs | candidate runs |
|---|---|---|
| p50 | 7, 6, 7 | 8, 6, 6 |
| p90 | 8, 8, 9 | 10, 9, 8 |
| p99 | 22, 25, 27 | 23, 13, 12 |
| max | 10333, 7952, 1554 | 8032, 376, 320 |
| work | 1, 0, 2 | 3, 1, 1 |

## single_insert · execute

| metric | baseline median | candidate median | Δ | Δ% | baseline CV |
|---|---:|---:|---:|---:|---:|
| p50 | 16.0 μs | 16.0 μs | +0.0 μs | +0.0% | 3.0% |
| p90 | 19.0 μs | 20.0 μs | +1.0 μs | +5.3% | 2.4% |
| p99 | 31.0 μs | 37.0 μs | +6.0 μs | +19.4% | 27.8% |
| max | 1111.0 μs | 3855.0 μs | +2744.0 μs | +247.0% | 73.3% |
| work | 6.0 μs | 7.0 μs | +1.0 μs | +16.7% | 7.4% |

Per-run values (baseline / candidate):

| metric | baseline runs | candidate runs |
|---|---|---|
| p50 | 16, 15, 16 | 16, 16, 16 |
| p90 | 20, 19, 19 | 21, 20, 19 |
| p99 | 51, 31, 28 | 43, 37, 32 |
| max | 1111, 760, 3923 | 1814, 13907, 3855 |
| work | 6, 6, 7 | 7, 7, 7 |

## noop_floors (dispatch baseline)

| metric | baseline median | candidate median | Δ |
|---|---:|---:|---:|
| reader_us | 6.0 μs | 5.0 μs | -1.0 μs |
| writer_us | 9.0 μs | 9.0 μs | +0.0 μs |
