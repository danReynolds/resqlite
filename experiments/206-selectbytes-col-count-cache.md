# Experiment 206: selectBytes column-count cache

**Date:** 2026-06-30
**Status:** Rejected
**Direction:** `result-transfer-shape`
**Benchmark Run:** focused `benchmark/experiments/select_bytes_repeated_calls.dart`,
  three A/B pairs against `origin/main` at `efe9dea`; see Results.
**Archive:** [`archive/exp-206`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-206)

## Problem

Exp 195 moved `selectBytes()` column-name JSON tokens from per-query scratch
state onto the cached prepared-statement entry. Once those tokens are built,
the entry also carries the prepared statement's column count in
`json_name_tokens_col_count`.

`write_json_to_buf` still called `sqlite3_column_count(stmt)` at the start of
every `selectBytes()` execution. That is only one SQLite call per query, not one
per cell, but exp 195's `select_bytes_repeated_calls.dart` harness exists
exactly for this kind of repeated tiny-rowset setup cost. Exp 205's signal
entry also named remaining `sqlite3_column_count` / `sqlite3_column_bytes` calls
as the next place to test after the typed-getter pattern had been exhausted.

## Hypothesis

For hot repeated `selectBytes()` calls against the same prepared SQL, reuse
`entry->json_name_tokens_col_count` after exp 195 has built the token cache.
That should skip one `sqlite3_column_count(stmt)` call per `selectBytes()` call,
with the biggest chance of showing up on 1-row and 10-row repeated-call lanes
where query-level setup is a visible fraction of total wall.

Reject if the tiny-row lanes do not reproduce candidate-faster after a warmed
order flip, or if the result only appears during process/native build warmup.

## Approach

The archived prototype changed only the top of `write_json_to_buf`:

```c
int col_count = entry->json_name_tokens_col_count > 0
    ? entry->json_name_tokens_col_count
    : sqlite3_column_count(stmt);
```

First execution is unchanged because the token cache is not built yet.
Statements with no cached positive count keep the existing
`sqlite3_column_count` call. Normal cached `selectBytes()` re-executions skip
the call after `ensure_json_name_tokens` has populated the entry.

No public API changes, no output-format changes, no allocation changes. The
prototype passed the existing `selectBytes` correctness tests, then was reverted
before publication.

## Results

Raw tables are preserved in
[`benchmark/results/2026-06-30T10-08-41Z-exp206-selectbytes-col-count-cache.md`](../benchmark/results/2026-06-30T10-08-41Z-exp206-selectbytes-col-count-cache.md).

Candidate deltas below are median microseconds per call from
`select_bytes_repeated_calls.dart`. Negative is candidate faster.

| Lane | Pair 1 | Pair 2 | Warmed Pair 3 |
|---|---:|---:|---:|
| 1 row x 8 int cols | -0.2% | -15.1% | +8.8% |
| 1 row x 20 int cols | -5.2% | -10.0% | +9.6% |
| 1 row x 8 mixed cols | -6.8% | -5.0% | +10.9% |
| 10 rows x 8 int cols | -6.4% | -1.3% | +2.6% |
| 10 rows x 20 int cols | -2.7% | -2.0% | +0.9% |
| 100 rows x 8 int cols | -2.2% | -6.0% | +0.3% |
| 1000 rows x 8 int cols | -2.7% | -0.5% | -0.3% |

The first two pairs looked promising: every lane was candidate-faster, with the
largest deltas on the tiny rowsets where a query-level call should matter most.
The warmed third pair reversed the load-bearing lanes. The 1-row rows moved
candidate-slower by roughly 9% to 11%, and the 10-row x 8 lane moved +2.6%.
The wider 10-row lane and both larger guards were effectively flat.

That shape is not a reproduced optimization. It is consistent with process,
native-asset build, and VM warmup effects being larger than the skipped
`sqlite3_column_count` call. Once the harness is warm, the candidate does not
preserve the effect on the lanes it was meant to help.

An attempted AOT binary check was not usable in this package layout: the
compiled standalone executable could not resolve the package native asset, so
the decision rests on the `dart run` focused harness that existing
`selectBytes()` experiments use.

## Decision

**Rejected.** Do not keep the runtime branch.

Skipping one `sqlite3_column_count()` call per hot `selectBytes()` execution is
structurally plausible, but after exp 195 the remaining setup cost is below the
current repeated-call harness floor. The warmed pair fails exactly where the
candidate should be strongest, so the extra branch in `write_json_to_buf` is not
worth carrying.

This closes the cheap `sqlite3_column_count` follow-up for the JSON encoder.
Future work should not retest the same cached-count branch without a new
runtime or benchmark fact. Remaining `sqlite3_column_bytes` work is a different
question because TEXT/BLOB length lookup is per variable cell, not once per
query.

## Test plan

- `dart pub get` in candidate and baseline worktrees
- `dart analyze --fatal-infos native/`
- `dart test test/database_test.dart --plain-name selectBytes`
- Focused A/B pairs on `benchmark/experiments/select_bytes_repeated_calls.dart`

## Future Notes

- `archive/exp-206` preserves the measured prototype.
- Treat query-level `sqlite3_column_count` in `write_json_to_buf` as below the
  current signal bar. If a future repeated-call harness becomes more stable, the
  acceptance gate should still be the 1-row and 10-row lanes from
  `select_bytes_repeated_calls.dart`.
- Do not generalize this rejection to `sqlite3_column_bytes`: that call remains
  per TEXT/BLOB cell and can only be evaluated with a TEXT/BLOB-focused payload
  where length lookup, not string escaping/base64 work, is visible.

