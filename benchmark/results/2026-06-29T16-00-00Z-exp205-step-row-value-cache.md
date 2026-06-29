# Exp 205 — per-cell `sqlite3_column_value` reuse in `resqlite_step_row`

## Harness

[`benchmark/experiments/select_rows_step_row_ffi.dart`](../experiments/select_rows_step_row_ffi.dart)

- `rows = 10000`, `warmup = 30`, `iterations = 200`
- Each lane creates a fresh in-memory database, seeds the rows, warms the
  reader cache, then times `Database.select('SELECT * FROM items')` calls.
- Wall captures end-to-end Dart `select()` latency: FFI prepare + bind + per-row
  `resqlite_step_row` + Dart-side cell decode + Row/`ResultSet` construction.

## Pass 1 (baseline -> candidate)

### Baseline

| Lane | p50 (ms) | p90 (ms) |
|---|---:|---:|
| 10k × 8 INTEGER | 2.697 | 2.893 |
| 10k × 20 INTEGER | 6.454 | 6.680 |
| 10k × 20 short TEXT | 15.759 | 19.577 |
| 10k × 6 mixed (default) | 3.986 | 5.578 |

### Candidate

| Lane | p50 (ms) | p90 (ms) |
|---|---:|---:|
| 10k × 8 INTEGER | 2.567 | 2.733 |
| 10k × 20 INTEGER | 5.857 | 6.035 |
| 10k × 20 short TEXT | 14.718 | 18.743 |
| 10k × 6 mixed (default) | 3.540 | 5.807 |

## Pass 2 (candidate -> baseline; order flipped)

### Candidate

| Lane | p50 (ms) | p90 (ms) |
|---|---:|---:|
| 10k × 8 INTEGER | 2.593 | 3.233 |
| 10k × 20 INTEGER | 6.097 | 6.282 |
| 10k × 20 short TEXT | 14.770 | 18.733 |
| 10k × 6 mixed (default) | 3.745 | 5.598 |

### Baseline

| Lane | p50 (ms) | p90 (ms) |
|---|---:|---:|
| 10k × 8 INTEGER | 2.660 | 2.899 |
| 10k × 20 INTEGER | 6.145 | 6.243 |
| 10k × 20 short TEXT | 15.675 | 19.403 |
| 10k × 6 mixed (default) | 3.877 | 4.957 |

## Combined deltas (p50)

| Lane | Pass 1 Δ | Pass 2 Δ |
|---|---:|---:|
| 10k × 8 INTEGER | −4.8 % | −2.5 % |
| 10k × 20 INTEGER | −9.2 % | −0.8 % |
| 10k × 20 short TEXT | −6.6 % | −5.8 % |
| 10k × 6 mixed (default) | −11.2 % | −3.4 % |

Same-direction candidate-faster across the order flip on every lane. Per
JOURNAL `Phase-ordered A/B gates confound code deltas with time-correlated
drift`, sign preservation across order flip rules out the drift signature.

## resqlite tests

`dart test test/database_test.dart`: 53 / 53 pass on the candidate, including
every `selectBytes`, `select`, mixed-type, blob, and unicode case.
