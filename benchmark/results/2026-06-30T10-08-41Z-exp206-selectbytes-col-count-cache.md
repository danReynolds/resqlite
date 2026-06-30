# Exp 206 - selectBytes column-count cache

Focused `benchmark/experiments/select_bytes_repeated_calls.dart` A/B against
`origin/main` at `efe9dea`. Candidate prototype archived at `archive/exp-206`.

The prototype reused `entry->json_name_tokens_col_count` after exp 195's cached
JSON column-name tokens were built, skipping one `sqlite3_column_count(stmt)`
call per hot `selectBytes()` re-execution. The runtime change was reverted after
measurement.

Harness: 1000 `selectBytes()` calls per sample, 11 samples per lane, median
microseconds per call. Lower is better.

## Pair 1 - baseline then candidate

### Baseline

| Shape | Median us/call | Min | Max | Bytes |
|---|---:|---:|---:|---:|
| 1 row x 8 int cols | 8.214 | 5.868 | 20.813 | 59 |
| 1 row x 20 int cols | 6.345 | 5.988 | 6.636 | 163 |
| 1 row x 8 mixed cols | 6.105 | 5.688 | 6.881 | 74 |
| 10 rows x 8 int cols | 7.761 | 7.216 | 8.177 | 797 |
| 10 rows x 20 int cols | 10.345 | 10.025 | 11.279 | 2071 |
| 100 rows x 8 int cols | 27.525 | 26.618 | 28.776 | 8897 |
| 1000 rows x 8 int cols | 213.103 | 211.836 | 216.031 | 97097 |

### Candidate

| Shape | Median us/call | Min | Max | Bytes |
|---|---:|---:|---:|---:|
| 1 row x 8 int cols | 8.200 | 5.882 | 21.393 | 59 |
| 1 row x 20 int cols | 6.017 | 5.543 | 8.342 | 163 |
| 1 row x 8 mixed cols | 5.690 | 5.539 | 6.654 | 74 |
| 10 rows x 8 int cols | 7.261 | 7.141 | 7.726 | 797 |
| 10 rows x 20 int cols | 10.064 | 9.945 | 11.009 | 2071 |
| 100 rows x 8 int cols | 26.916 | 26.566 | 28.401 | 8897 |
| 1000 rows x 8 int cols | 207.387 | 206.961 | 209.470 | 97097 |

## Pair 2 - candidate then baseline

### Candidate

| Shape | Median us/call | Min | Max | Bytes |
|---|---:|---:|---:|---:|
| 1 row x 8 int cols | 7.120 | 5.823 | 19.278 | 59 |
| 1 row x 20 int cols | 6.158 | 5.816 | 7.183 | 163 |
| 1 row x 8 mixed cols | 5.647 | 5.493 | 7.103 | 74 |
| 10 rows x 8 int cols | 7.286 | 7.156 | 8.230 | 797 |
| 10 rows x 20 int cols | 10.108 | 9.988 | 11.576 | 2071 |
| 100 rows x 8 int cols | 26.873 | 26.239 | 28.441 | 8897 |
| 1000 rows x 8 int cols | 207.376 | 206.601 | 214.700 | 97097 |

### Baseline

| Shape | Median us/call | Min | Max | Bytes |
|---|---:|---:|---:|---:|
| 1 row x 8 int cols | 8.389 | 7.049 | 23.726 | 59 |
| 1 row x 20 int cols | 6.841 | 5.509 | 8.199 | 163 |
| 1 row x 8 mixed cols | 5.943 | 5.569 | 8.254 | 74 |
| 10 rows x 8 int cols | 7.382 | 7.157 | 8.304 | 797 |
| 10 rows x 20 int cols | 10.318 | 10.082 | 11.243 | 2071 |
| 100 rows x 8 int cols | 28.583 | 28.044 | 29.637 | 8897 |
| 1000 rows x 8 int cols | 208.364 | 207.532 | 221.657 | 97097 |

## Pair 3 - warmed baseline then candidate

### Baseline

| Shape | Median us/call | Min | Max | Bytes |
|---|---:|---:|---:|---:|
| 1 row x 8 int cols | 7.251 | 5.831 | 21.546 | 59 |
| 1 row x 20 int cols | 5.995 | 5.523 | 6.205 | 163 |
| 1 row x 8 mixed cols | 5.578 | 5.477 | 5.901 | 74 |
| 10 rows x 8 int cols | 7.257 | 7.103 | 7.430 | 797 |
| 10 rows x 20 int cols | 10.008 | 9.832 | 11.242 | 2071 |
| 100 rows x 8 int cols | 26.607 | 26.240 | 28.660 | 8897 |
| 1000 rows x 8 int cols | 207.617 | 206.492 | 211.946 | 97097 |

### Candidate

| Shape | Median us/call | Min | Max | Bytes |
|---|---:|---:|---:|---:|
| 1 row x 8 int cols | 7.887 | 6.041 | 21.193 | 59 |
| 1 row x 20 int cols | 6.568 | 6.024 | 7.061 | 163 |
| 1 row x 8 mixed cols | 6.184 | 5.593 | 7.193 | 74 |
| 10 rows x 8 int cols | 7.447 | 7.205 | 7.799 | 797 |
| 10 rows x 20 int cols | 10.095 | 9.833 | 10.561 | 2071 |
| 100 rows x 8 int cols | 26.685 | 26.103 | 28.084 | 8897 |
| 1000 rows x 8 int cols | 206.981 | 205.937 | 207.813 | 97097 |

## Delta summary

Candidate deltas vs matching baseline. Negative is candidate faster.

| Lane | Pair 1 | Pair 2 | Pair 3 |
|---|---:|---:|---:|
| 1 row x 8 int cols | -0.2% | -15.1% | +8.8% |
| 1 row x 20 int cols | -5.2% | -10.0% | +9.6% |
| 1 row x 8 mixed cols | -6.8% | -5.0% | +10.9% |
| 10 rows x 8 int cols | -6.4% | -1.3% | +2.6% |
| 10 rows x 20 int cols | -2.7% | -2.0% | +0.9% |
| 100 rows x 8 int cols | -2.2% | -6.0% | +0.3% |
| 1000 rows x 8 int cols | -2.7% | -0.5% | -0.3% |

## Read

The first two pairs looked candidate-faster, but the warmed third pair killed
the claim: the tiny rowsets that should be most sensitive to a query-level
`sqlite3_column_count()` skip flipped candidate-slower by 2.6% to 10.9%, while
100-row and 1000-row guards were effectively flat.

The likely conclusion is that the skipped SQLite call is below the harness
floor after exp 195's cached token work. Keeping the branch would be a tiny
branch in a hot encoder for no reproduced product-level win.

