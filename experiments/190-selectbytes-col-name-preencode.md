# Experiment 190: selectBytes column-name token pre-encoding

**Date:** 2026-06-20
**Status:** Accepted
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused
  [`benchmark/experiments/select_bytes_wide_cols.dart`](../benchmark/experiments/select_bytes_wide_cols.dart)
  order-flipped pair plus the existing
  [`benchmark/experiments/large_bytes_transfer.dart`](../benchmark/experiments/large_bytes_transfer.dart)
  guard; no release-suite run because the changed path is the C-side JSON
  encoder reached only via `selectBytes()` and the focused harness directly
  exercises the wide-many-row and large-payload shapes that compound the
  per-row, per-column savings.

## Problem

`write_json_to_buf` in `native/resqlite.c` is the encoder behind
[`Database.selectBytes()`](../lib/src/database.dart). For each row it writes
`{"col0":VALUE,"col1":VALUE,…}` by calling, per column:

1. `buf_write_char(',')` — separator for columns 1+.
2. `json_write_string(col_names[i], col_name_lens[i])` — a SWAR scan
   over the name (8 bytes at a time, then a per-byte escape walk) wrapped
   in opening and closing `"`.
3. `buf_write_char(':')` — key/value delimiter.

For a query returning *N* rows × *M* columns those four `buf_write*` calls
fire *N × M* times even though `col_names[i]` is invariant across rows. The
SWAR loop is fast (`json_write_string` is `RESQLITE_HOT`), but it still pays
the loop entry, the byte-loop fallback over short identifiers (typical SQLite
column names are 5–12 bytes — below the SWAR step of 8), and the four
`buf_ensure` + `memcpy` pairs for the per-row character writes. None of it
depends on the row.

This pattern — repeating identical work per row that could be amortized at
first-row time — is the same shape exp 034 caught at the Dart layer
(per-worker `RowSchema` cache) and exp 037 caught at the JSON-buffer layer
(persistent `json_buf`). The C-side column-name emission was left running
per row.

## Hypothesis

Pre-build each column's emitted token (`"col0":` for column 0, `,"col1":`
for columns 1+) once at first-row time into a per-query scratch buffer, then
emit each column on subsequent rows with a single `buf_write` instead of
four `buf_write*` calls. The collapse should be measurable on wide-many-row
`selectBytes()` shapes where the column-name share of total output bytes is
material, and stay neutral on tiny rowsets where the per-query pre-encode
overhead (one `buf_init` + the same per-column writes that already happen
on row 0) has nothing to amortize against.

## Approach

In `write_json_to_buf` (`native/resqlite.c:1923`):

- Add stack-sized arrays for per-column token offsets/lengths (≤ 64 cols),
  with a heap fallback for wider schemas, alongside the existing
  `col_names`/`col_name_lens` arrays.
- At first-row time, after capturing `col_names` and `col_name_lens`,
  initialize a scratch `resqlite_buf tokens_buf` (conservative capacity
  `name_len * 6 + 4` per column — worst case every byte escapes to
  `\uXXXX`) and walk every column writing into it: leading `,` for column
  1+, the existing `json_write_string` of the name, and the trailing `:`.
  Record `(offset, len)` per column.
- Replace the per-row inner-loop sequence with a single
  `buf_write(b, tokens_buf.data + token_offsets[i], token_lens[i])`.
- Extend the cleanup block to `free(tokens_buf.data)` unconditionally
  (`free(NULL)` is safe when `buf_init` was never reached, e.g. an empty
  rowset) and to free the new heap allocations only on the `> 64` columns
  path. `free(NULL)` guards the partial-malloc-failure cleanup the way the
  original two-array allocations already did.

The pre-encoding intentionally reuses `json_write_string` so column names
with characters the SWAR loop would escape (quotes, backslashes, control
bytes, or even `\uXXXX` controls) still produce identical bytes — the
candidate is a pure work-amortization change, not a behavior change.

Empty result sets allocate nothing extra: the first-row branch never fires,
`tokens_buf.data` stays `NULL`, and the unconditional `free(NULL)` in
cleanup is a no-op.

## Results

Focused [`benchmark/experiments/select_bytes_wide_cols.dart`](../benchmark/experiments/select_bytes_wide_cols.dart)
(5 calls/sample, 11 samples per shape), two order-flipped passes against
fresh `origin/main`:

| Shape | Pass 1 baseline (ms) | Pass 1 candidate (ms) | Pass 1 Δ | Pass 2 baseline (ms) | Pass 2 candidate (ms) | Pass 2 Δ |
|---|---:|---:|---:|---:|---:|---:|
| 10k rows × 8 int cols   | 2.556 | 2.442 | −4.5% | 2.739 | 2.547 | −7.0% |
| 10k rows × 20 int cols  | 6.168 | 5.866 | −4.9% | 6.570 | 5.829 | −11.3% |
| 10k rows × 8 mixed cols | 2.747 | 2.640 | −3.9% | 2.865 | 2.621 | −8.5% |
| 10k rows × 20 mixed cols| 6.823 | 6.252 | −8.4% | 6.763 | 6.256 | −7.5% |
| 10k rows × 2 int cols   | 0.764 | 0.738 | −3.4% | 0.766 | 0.766 | 0% |
| 1 row × 5 mixed cols    | 0.018 | 0.018 | 0% (16–25 us spread) | 0.020 | 0.019 | −5% (16–29 us spread) |
| 100 rows × 5 mixed cols | 0.035 | 0.033 | −5.7% | 0.036 | 0.037 | +2.8% (sub-µs absolute) |

Pass 1 is candidate-then-baseline, pass 2 is baseline-then-candidate.
Each side ran in its own worktree (`resqlite-exp-190` vs
`resqlite-baseline-exp190`) so the native rebuild was fresh on both sides
and the runs interleaved over similar wall time.

All five 10k-row shapes move same-direction across both orderings, with the
larger compound shapes (20 cols) showing the largest deltas (−5% to −11%).
The two regression-guard shapes (1 row, 100 rows) sit at the sub-µs noise
floor — the absolute deltas (~0–2 µs) are smaller than the per-sample
spread of either side, and the pass-to-pass signs do not agree, which is
the classic noise-floor signature documented in
[exp 177](177-ab-drift-discriminator.md).

Existing [`benchmark/experiments/large_bytes_transfer.dart`](../benchmark/experiments/large_bytes_transfer.dart)
([exp 174](174-selectbytes-view-transfer.md)'s focused guard, run once per
side):

| Lane | Baseline us/query | Candidate us/query | Δ |
|---|---:|---:|---:|
| large-bytes (>256KB) — 651781 B × 150 | 288 | 263 | −8.7% |
| small-bytes (<256KB) — 64781 B × 2000 | 97  | 89  | −8.2% |

So the change also moves the existing public-lane-adjacent
`large_bytes_transfer.dart` workload, where each call returns ~650 KB
across enough rows that the per-row column emission compounds.

## Decision

In Review. The encoder savings reproduce in both order-flipped passes on
the wide-many-row shapes the change targets, the per-query overhead is
absorbed at row 0, and the regression guards stay inside the focused
harness noise floor. The change is local to the C-side JSON encoder, fully
behavior-preserving, and reuses the existing escape machinery rather than
re-implementing it.

The opt-out `**Benchmark Run:** none` is justified by the same logic
[exp 187](187-single-row-utf8-bind-encoder.md) used for its
single-row UTF-8 encoder: the public release suite's `selectBytes()` lanes
(`select_bytes.dart` 1K-row standard, `scaling.dart` rows, and the exp 175
`Large payload (~650KB) / resqlite selectBytes()` row) do not isolate the
wide-many-row shape the change targets. The focused harness above is the
representative workload — modeled after the existing focused harness
templates ([exp 186](186-single-row-large-text-bind-encoder.md),
[exp 173](173-long-text-32kb-fnv16.md)) — and the
`large_bytes_transfer.dart` lane already on exp 174's guard list confirms
the change does not regress the established large-bytes path. Future
runners should reach for `select_bytes_wide_cols.dart` before changing the
column-name emission path again.

## Future notes

- If a UTF-8-heavy column-name workload (CJK / mixed-script identifier
  schemas) becomes interesting, the pre-encoded token already captures
  the escape-correct bytes — the candidate inherits the existing
  `json_write_string` SWAR/escape behavior by reuse. No follow-up change
  is required there.
- If a future selectBytes change wants to amortize *more* across rows
  (e.g. pre-encoded value templates for constant-type integer columns),
  the token-buffer pattern in this experiment is the natural insertion
  point: the same `tokens_buf` + `token_offsets`/`token_lens` arrays
  could carry per-column value-prefix metadata.
- The `resqlite_cached_stmt` already holds per-stmt metadata (param
  count, dep tables/columns); promoting `token_offsets`/`token_lens`
  into the cached entry would let the first-row pre-encode pass go away
  on cache hits. That is a strictly-larger change (cache lifetime, FFI
  surface) and only worth pursuing if a workload shows repeated small
  `selectBytes()` calls dominating wall time — `select_bytes_wide_cols.dart`'s
  1-row regression guard already shows the per-query overhead is at
  noise on the smallest shape.
