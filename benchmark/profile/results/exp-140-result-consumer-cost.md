=== Result Consumer Cost Benchmark ===

Runtime: JIT/profile-debug
Warmup: 5
Iterations: 20
Rows: 100, 1000, 10000
Datasets: numeric, mixed
Consumers: length only, id key per row, forEach all cells, Map copy

Measures SQLite-backed `db.select()` wall separately from main-isolate row consumption.

## numeric / 100 rows

| Consumer | select p50 | consume p50 | total p50 | total p90 | consume % |
|---|---:|---:|---:|---:|---:|
| length only | 0.114 ms | 0.000 ms | 0.114 ms | 0.135 ms | 0.0% |
| id key per row | 0.097 ms | 0.049 ms | 0.147 ms | 0.178 ms | 33.3% |
| forEach all cells | 0.050 ms | 0.061 ms | 0.118 ms | 0.226 ms | 51.7% |
| Map copy | 0.048 ms | 0.101 ms | 0.152 ms | 0.323 ms | 66.4% |

## numeric / 1000 rows

| Consumer | select p50 | consume p50 | total p50 | total p90 | consume % |
|---|---:|---:|---:|---:|---:|
| length only | 0.246 ms | 0.000 ms | 0.246 ms | 0.254 ms | 0.0% |
| id key per row | 0.275 ms | 0.033 ms | 0.309 ms | 0.353 ms | 10.7% |
| forEach all cells | 0.244 ms | 0.046 ms | 0.290 ms | 0.299 ms | 15.9% |
| Map copy | 0.237 ms | 0.491 ms | 0.729 ms | 0.797 ms | 67.4% |

## numeric / 10000 rows

| Consumer | select p50 | consume p50 | total p50 | total p90 | consume % |
|---|---:|---:|---:|---:|---:|
| length only | 3.716 ms | 0.000 ms | 3.716 ms | 6.303 ms | 0.0% |
| id key per row | 3.522 ms | 0.167 ms | 3.732 ms | 4.976 ms | 4.5% |
| forEach all cells | 3.254 ms | 0.448 ms | 3.794 ms | 5.335 ms | 11.8% |
| Map copy | 3.298 ms | 4.946 ms | 9.074 ms | 10.577 ms | 54.5% |

## mixed / 100 rows

| Consumer | select p50 | consume p50 | total p50 | total p90 | consume % |
|---|---:|---:|---:|---:|---:|
| length only | 0.233 ms | 0.000 ms | 0.233 ms | 0.253 ms | 0.0% |
| id key per row | 0.076 ms | 0.023 ms | 0.099 ms | 0.262 ms | 23.2% |
| forEach all cells | 0.072 ms | 0.057 ms | 0.130 ms | 0.203 ms | 43.8% |
| Map copy | 0.060 ms | 0.082 ms | 0.143 ms | 0.158 ms | 57.3% |

## mixed / 1000 rows

| Consumer | select p50 | consume p50 | total p50 | total p90 | consume % |
|---|---:|---:|---:|---:|---:|
| length only | 0.325 ms | 0.000 ms | 0.325 ms | 0.330 ms | 0.0% |
| id key per row | 0.337 ms | 0.033 ms | 0.370 ms | 0.508 ms | 8.9% |
| forEach all cells | 0.320 ms | 0.043 ms | 0.364 ms | 0.377 ms | 11.8% |
| Map copy | 0.328 ms | 0.291 ms | 0.620 ms | 0.662 ms | 46.9% |

## mixed / 10000 rows

| Consumer | select p50 | consume p50 | total p50 | total p90 | consume % |
|---|---:|---:|---:|---:|---:|
| length only | 3.998 ms | 0.000 ms | 3.998 ms | 9.390 ms | 0.0% |
| id key per row | 4.034 ms | 0.163 ms | 4.197 ms | 5.173 ms | 3.9% |
| forEach all cells | 4.242 ms | 0.386 ms | 4.615 ms | 5.130 ms | 8.4% |
| Map copy | 3.563 ms | 3.388 ms | 7.092 ms | 8.591 ms | 47.8% |
