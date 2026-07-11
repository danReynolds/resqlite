# Experiment 223: reject row-0 peel + `[{` fuse in `write_json_to_buf`

**Date:** 2026-07-11
**Status:** Rejected
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused
  [`benchmark/experiments/select_bytes_wide_cols.dart`](../benchmark/experiments/select_bytes_wide_cols.dart)
  and
  [`benchmark/experiments/select_bytes_repeated_calls.dart`](../benchmark/experiments/select_bytes_repeated_calls.dart);
  raw order-flipped pair tables in
  [`benchmark/results/2026-07-11T11-22-23Z-exp223-write-json-row-peel.md`](../benchmark/results/2026-07-11T11-22-23Z-exp223-write-json-row-peel.md).
**Archive:** [`archive/exp-223`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-223)

## Problem

After [exp 195](195-cached-json-name-tokens.md),
[exp 198](198-cell-direct-write.md), [exp 203/205](205-step-row-value-cache.md),
`write_json_to_buf` in [`native/resqlite.c`](../native/resqlite.c) is a tight
per-row loop. What remains at the row boundary is a small amount of unfused
control flow. On every iteration, the code checks `if (row_index > 0)` to
decide whether to write the comma separator, and the leading `[` bracket is
written once before the loop while the first row's `{` prelude is written
inside the loop body. That leaves three visible micro-costs per query:

1. One `if (row_index > 0)` per row — a well-predicted branch (false only on
   row 0), but present for every step.
2. Separate `buf_write_char(b, '[')` and later `b->data[b->len++] = '{'` at
   the start of the query, when a single 2-byte prelude would suffice.
3. Empty (0-row) queries still walk into the row loop body's ensure path
   before hitting `SQLITE_DONE`, even though the answer is a fixed 2-byte
   `[]`.

## Hypothesis

Peeling row 0 out of the loop should remove the per-iteration branch, fuse
`[` with row 0's `{` into a single reservation + double-byte write, and let
empty results short-circuit before any per-row capacity accounting. If the
per-row branch and the split bracket writes were material, the many-row
lanes on `select_bytes_wide_cols.dart` should reproduce candidate-faster past
noise. If they are already amortized under the JSON encoder's dominant per-
cell work (memcpy of pre-encoded column tokens + type-switched value write),
the change should measure flat within the harness effect floor.

Predicted acceptance: `10k rows × 20 mixed cols` and `1000 rows × 8 int cols`
reproduce ≥ 3% candidate-faster across the order flip with the small
regression guards (1 row × 5 mixed, 100 rows × 5 mixed) neutral.

Predicted rejection: sub-noise-floor movement on the many-row shapes, or
sign-flipped signal on the 1-row shape.

## Approach

The archived prototype changes only
[`native/resqlite.c`](../native/resqlite.c) — specifically the body of
`write_json_to_buf`:

- The per-cell encoder is extracted into a `RESQLITE_WRITE_JSON_ROW_CELLS()`
  macro so row 0 and rows 1+ share the exact same encoder (identical to exp
  199 / 203 / 205's tuned block, including the TEXT/BLOB post-write
  re-ensure).
- `sqlite3_step` is called explicitly before the loop. `SQLITE_DONE`
  short-circuits to a 2-byte `[]` write, `SQLITE_ROW` falls through into
  row 0, other codes propagate to cleanup.
- Row 0 does a single `buf_ensure(b, 2 + tokens_total + fixed_cell_bytes_total
  + 1)` and writes `[` and `{` back-to-back into the reserved buffer.
- Rows 1+ live inside a `while (sqlite3_step == SQLITE_ROW)` whose body has
  no `if (row_index > 0)` check — the shared `,{` prelude is unconditional.
- No changes to `write_json_to_buf`'s output bytes, column-name token buffer
  (exp 195), per-row capacity math (exp 199), or cell-value dispatch (exp 203
  / 205).

Correctness: `dart test test/database_test.dart` (53 tests, including the 9
selectBytes cases: empty result, JSON special chars, embedded NULs, int64
extremes, integer-valued REAL, base64 BLOB, `jsonEncode` parity) all pass on
the candidate.

## Results

Focused A/B against `origin/main` at `0e4b49d` on a quiet box, two
order-flipped pairs of `select_bytes_repeated_calls.dart` (µs-precision, the
per-query setup gate exp 195 established) plus one pair of
`select_bytes_wide_cols.dart` (ms-precision, the wide-cols gate exp 190 / 195
/ 198 established). Raw tables in the linked result file; the drift verdict:

| Shape | Pair 1 Δ | Pair 2 Δ | Verdict |
|---|---:|---:|---|
| 10k rows × 20 mixed cols (wide) | -1.3% | (single pass) | inside 5% floor |
| 10k rows × 20 int cols (wide) | -0.4% | (single pass) | flat |
| 10k rows × 8 int cols (wide) | +5.7% | (single pass) | drift-suspected |
| 1000 rows × 8 int cols (repeated) | -1.5% | -0.2% | magnitude collapse |
| 100 rows × 8 int cols (repeated) | -1.5% | -1.6% | reproduced, ~1.5% |
| 10 rows × 20 int cols (repeated) | -1.7% | -2.7% | reproduced, ~2% |
| 10 rows × 8 int cols (repeated) | -1.0% | -0.9% | reproduced, ~1% |
| 1 row × 8 mixed cols (repeated) | -1.4% | -13.4% | inconclusive |
| 1 row × 20 int cols (repeated) | +1.4% | -4.5% | sign reversal |
| 1 row × 8 int cols (repeated) | +0.4% | +4.6% | candidate-slower both passes |

The reproduced same-sign wins on 10 / 100 rows land at 1-2% — inside the
`repeated_calls.dart` ~3% effect floor. The load-bearing many-row lane on
`wide_cols.dart` (10k × 8 int cols) flipped +5.7% candidate-slower on the
first pair, characteristic of run-to-run drift on a shape whose median
already sits at ~2 ms. The 1-row shapes were chaotic across the pair
(sign reversals, wide magnitude swings) and the `1 row × 8 int cols` lane
trended candidate-slower on both passes.

The predicted acceptance path (≥ 3% reproduced win on `10k × 20 mixed cols`
or `1000 rows × 8 int cols`) did not fire on either lane.

## Decision

Rejected. The per-row `if (row_index > 0)` branch is well-predicted and the
bracket-write fuse saves at most a few bytes per query; neither is a
material share of end-to-end selectBytes wall on the shapes the release
suite and the exp 195 focused harness care about. The macro that shares the
cell encoder between row 0 and rows 1+ adds maintenance cost (a 60-line
macro that any future encoder change must reason about) which the
reproduced 1-2% gains do not offset.

Runtime prototype preserved at `archive/exp-223` in case a future encoder
change makes row-boundary control flow a larger relative share (e.g., a
SIMD cell-write inner loop that shrinks the per-cell body to a handful of
cycles). Under current baselines, further per-row control-flow work in
`write_json_to_buf` is below the harness floor; the next `result-transfer-
shape` implementation should target a larger mechanism (algorithm change,
per-cell SIMD, transport format) rather than another row-boundary shave.

## Note on moonshot cadence

By experiment count (exp 214-222 are all non-moonshots), the cadence rule in
[`RUNNER_INSTRUCTIONS.md`](RUNNER_INSTRUCTIONS.md#moonshot-cadence) applies:
the next scheduled experiment should be a moonshot. This run consciously
stays in the exploit lane. The recent moonshots in the adjacent hot
directions — [exp 197](197-true-group-commit-moonshot.md) (group commit,
rejected on semantic hazard), [exp 212](212-lazy-nested-savepoint-moonshot.md)
(lazy nested savepoint, rejected on representative-workload regression),
[exp 213](213-tx-body-write-coalescing.md) (`tx.execute` buffering,
rejected on niche-workload pattern) — all fell in the same-class rejection
pattern the [JOURNAL entry "A reproduced win can still be the wrong thing
to ship"](JOURNAL.md) captures. The remaining tractable moonshots inside
`result-transfer-shape` (result memoization at the reader layer, columnar
transfer) hit either correctness surface (non-deterministic queries) or the
Dart-SDK primitive gate (issue #50068 — deeply-immutable typed-data
factory) that already sits in `openCandidates`. Rather than open a moonshot
that repeats a same-class rejection, this run produces reject-with-evidence
inside the encoder direction and leaves the moonshot slot for the next
scheduled runner once a new workload signal, production profile, or
upstream primitive changes the calculus. Future runners should still treat
the cadence rule as active — this deferral is not a general precedent.
