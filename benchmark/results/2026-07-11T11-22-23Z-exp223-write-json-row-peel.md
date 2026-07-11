# Exp 223 - row-peel `[{` fuse + empty-shortcut in `write_json_to_buf`

Focused A/B against `origin/main` at `0e4b49d`. The candidate refactors
`write_json_to_buf` in [`native/resqlite.c`](../../native/resqlite.c):

- Row 0 encoding is peeled out of the loop; the leading `[` fuses with row 0's
  `{` into a single 2-byte prelude (one `buf_ensure` covers the whole row).
- Rows 1+ live in a `while (sqlite3_step == SQLITE_ROW)` whose body never
  branches on `row_index` — the shared `,{` prelude is unconditional.
- Empty (0-row) results short-circuit to a direct `[]` write without entering
  the row loop or reserving row-shaped capacity.
- The per-cell encoder body is unchanged (exp 199 / 203 / 205 layout preserved
  via `RESQLITE_WRITE_JSON_ROW_CELLS()` macro shared between row 0 and rows 1+).

Two focused harnesses cover the hot shapes:

- `benchmark/experiments/select_bytes_wide_cols.dart` — 10k-row × N-col
  end-to-end wall (the exp 190 / 195 / 198 wide-cols gate).
- `benchmark/experiments/select_bytes_repeated_calls.dart` — 1000 tight-loop
  calls per sample, µs precision (the exp 195 repeated-calls gate; catches
  per-query setup wins that the millisecond harness cannot see).

## `select_bytes_wide_cols.dart`

### Pair 1 - baseline then candidate

| Shape | Baseline ms/call | Candidate ms/call | Delta |
|---|---:|---:|---:|
| 10k rows × 8 int cols | 2.052 | 2.170 | +5.7% |
| 10k rows × 20 int cols | 4.781 | 4.761 | -0.4% |
| 10k rows × 8 mixed cols | 2.271 | 2.246 | -1.1% |
| 10k rows × 20 mixed cols | 5.392 | 5.320 | -1.3% |
| 10k rows × 2 int cols | 0.613 | 0.618 | +0.8% |
| 1 row × 5 mixed cols | 0.014 | 0.014 | flat |
| 100 rows × 5 mixed cols | 0.029 | 0.030 | +3.4% |

## `select_bytes_repeated_calls.dart`

### Pair 1 - baseline then candidate

| Shape | Baseline µs/call | Candidate µs/call | Delta |
|---|---:|---:|---:|
| 1 row × 8 int cols | 7.058 | 7.084 | +0.4% |
| 1 row × 20 int cols | 5.775 | 5.855 | +1.4% |
| 1 row × 8 mixed cols | 5.555 | 5.480 | -1.4% |
| 10 rows × 8 int cols | 7.289 | 7.215 | -1.0% |
| 10 rows × 20 int cols | 10.233 | 10.062 | -1.7% |
| 100 rows × 8 int cols | 27.013 | 26.601 | -1.5% |
| 1000 rows × 8 int cols | 210.075 | 206.993 | -1.5% |

### Pair 2 - candidate then baseline (order-flipped)

| Shape | Candidate µs/call | Baseline µs/call | Delta (cand vs base) |
|---|---:|---:|---:|
| 1 row × 8 int cols | 8.816 | 8.431 | +4.6% |
| 1 row × 20 int cols | 5.916 | 6.195 | -4.5% |
| 1 row × 8 mixed cols | 5.605 | 6.470 | -13.4% |
| 10 rows × 8 int cols | 7.327 | 7.397 | -0.9% |
| 10 rows × 20 int cols | 10.066 | 10.348 | -2.7% |
| 100 rows × 8 int cols | 26.702 | 27.135 | -1.6% |
| 1000 rows × 8 int cols | 206.890 | 207.377 | -0.2% |

## Drift-classifier summary

Reproduced same-sign small candidate-faster (magnitudes ≤ 3%):

- `10 rows × 8 int cols`: -1.0% / -0.9%
- `10 rows × 20 int cols`: -1.7% / -2.7%
- `100 rows × 8 int cols`: -1.5% / -1.6%

Inconclusive / drift-suspected:

- `1 row × 8 int cols`: +0.4% / +4.6% (candidate trends slower on both;
  µs-scale first-cell shape dominated by SendPort dispatch noise).
- `1 row × 20 int cols`: +1.4% / -4.5% (sign reversal → inconclusive).
- `1 row × 8 mixed cols`: -1.4% / -13.4% (magnitude swing too large).
- `1000 rows × 8 int cols`: -1.5% / -0.2% (magnitude collapse in the
  order-flipped pass → drift-suspected).

The reproduced same-sign wins are all inside `select_bytes_repeated_calls.dart`
between 10 and 100 rows and inside the harness's ~3% effect floor. The
`wide_cols.dart` millisecond harness shows the same directional pattern (10k
mixed-col and 20-col shapes trend candidate-faster by 0.4-1.3%) but no lane
reproduces past the noise floor, and the 10k × 8 int lane trended +5.7%
candidate-slower on pair 1 — a sign of run-to-run drift, not a real regression.

## Verdict

Rejected. The per-row `if (row_index > 0)` branch that this refactor removes
is already well predicted by the CPU; the observed candidate wins are inside
the effect floor of both harnesses (~1-3% on `repeated_calls.dart`, ~5% on
`wide_cols.dart`). The 1-row shapes trending candidate-slower on pair 1 for
the fast-turnover `1 row × 8 int` and `1 row × 20 int` lanes rules out the
tiny 1-row fast-path saving as a real win. The macro that shares the cell
encoder between row 0 and rows 1+ adds duplication cost the reproduced 1-2%
gains do not justify.
