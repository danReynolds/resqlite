# Exp 224 - dynamic numeric-row batching for `select()`

Focused order-flipped A/B against `origin/main` at `e1310a9` using
[`benchmark/experiments/select_rows_step_row_ffi.dart`](../experiments/select_rows_step_row_ffi.dart).
The candidate adds `resqlite_step_rows` / `resqlite_step_rows_hash`, which
fill a bounded row-major cell buffer with up to 64 contiguous numeric/NULL
rows per leaf FFI call. A row containing TEXT or BLOB is included as the last
row of the batch and returned immediately, so its borrowed SQLite pointers are
decoded in Dart before the next `sqlite3_step()`.

Each harness process used 30 warmups and 200 measured iterations over 10,000
rows. Values below are milliseconds per `Database.select()` call.

## Pair 1 - baseline then candidate

| Lane | Baseline p50 | Candidate p50 | Delta | Baseline p90 | Candidate p90 |
|---|---:|---:|---:|---:|---:|
| 10k x 8 INTEGER | 2.499 | 2.547 | +1.9% | 2.691 | 2.733 |
| 10k x 20 INTEGER | 5.873 | 6.146 | +4.6% | 6.083 | 6.887 |
| 10k x 20 short TEXT | 14.724 | 15.688 | +6.5% | 18.875 | 20.124 |
| 10k x 6 mixed (default) | 3.647 | 3.563 | -2.3% | 5.200 | 5.289 |

## Pair 2 - candidate then baseline

| Lane | Candidate p50 | Baseline p50 | Delta | Candidate p90 | Baseline p90 |
|---|---:|---:|---:|---:|---:|
| 10k x 8 INTEGER | 2.561 | 2.549 | +0.5% | 2.846 | 2.717 |
| 10k x 20 INTEGER | 5.856 | 5.888 | -0.5% | 6.179 | 6.072 |
| 10k x 20 short TEXT | 15.624 | 14.836 | +5.3% | 20.193 | 18.873 |
| 10k x 6 mixed (default) | 3.651 | 3.788 | -3.6% | 5.262 | 4.839 |

## Verdict

Rejected. Neither numeric lane reproduces candidate-faster: 8-column INTEGER
is candidate-slower in both orderings (+1.9% / +0.5%), while 20-column INTEGER
flips from +4.6% slower to -0.5% faster. The TEXT guard path reproduces a
material regression (+6.5% / +5.3%). Collapsing as many as 64 row steps into
one leaf FFI call does not offset the combined batch-shaped decoder. The exact
prototype is archived at
`archive/exp-224`; no runtime code is kept.
