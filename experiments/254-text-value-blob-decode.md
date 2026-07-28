# Experiment 254: TEXT decode via `sqlite3_value_blob` (skip NUL-termination copy)

**Date:** 2026-07-28
**Status:** Rejected (no measurable headroom — SQLite amortizes the copy)
**Direction:** `result-transfer-shape`
**Benchmark Run:** focused harness only
(`benchmark/experiments/text_value_blob_decode.dart`, same-binary A/B toggle);
no release-suite run because the runtime candidate was reverted.

## Problem

Every reader TEXT cell is read with `sqlite3_value_text(val)`. Unlike
`sqlite3_value_blob`, `value_text` guarantees a NUL-terminated C string: it
calls `sqlite3VdbeMemNulTerminate`, which for a value that is not already
terminated (`MEM_Term` unset) grows the `Mem` buffer and copies the whole cell
just to append a `\0`.

None of resqlite's four reader TEXT consumers read that terminator — they all
take an explicit byte length, the invariant
[exp 191](191-embedded-nul-public-api-audit.md) audited end-to-end:

- `write_json_to_buf` → `resqlite_json_write_string(b, text, text_len)`
- `resqlite_step_row` → `cells[i].len` (Dart `fastDecodeText` reads `len` bytes)
- `resqlite_step_row_hash` → same, plus FNV folds `len` bytes
- `resqlite_query_hash` → FNV folds `len` bytes

So if the cells are ephemeral page pointers, `value_text` looked like it was
paying a malloc + full-cell copy per TEXT cell for a `\0` we discard.
[Exp 203](203-cell-value-cache.md) / [exp 205](205-step-row-value-cache.md)
hoisted the per-cell `columnMem` *lookup* into one `sqlite3_column_value`, but
both deliberately kept `sqlite3_value_text` and never questioned the
materialization it forces.

## Hypothesis

For a UTF-8 connection (resqlite never sets a non-default encoding, so it is
always UTF-8), `sqlite3_value_blob` returns exactly the same stored UTF-8 bytes
as `value_text`, minus the terminator. Switching the four TEXT sites to
`value_blob` should therefore be byte-identical and skip the NUL-termination
copy. The saving should scale with bytes copied, so the win — if real — is
largest on long-text, text-column-heavy rowsets and absent on integer-only
rowsets.

Acceptance: a same-sign improvement across two order-flipped passes on
text-heavy lanes, exceeding the integer control lane's drift, with the win
growing with text length. If long-text lanes do not beat the control, the
materialization cost is not real on this read path and the candidate closes.

## Approach

Replaced `sqlite3_value_text(val)` with `sqlite3_value_blob(val)` at all four
sites (BLOB arms already used `value_blob`; empty-cell NULL-pointer/len-0 cases
are safe in every consumer). Correctness rests on the exp 191 explicit-length
invariant; the existing embedded-NUL, multibyte-UTF-8, and mixed-type tests
(`database_test.dart`, `stream_test.dart`) exercise every path and pass under
both `value_text` and `value_blob`.

Measurement used a **single-binary A/B toggle** (`RESQLITE_EXP254_TEXT=1`
selects the old `value_text` path; default is `value_blob`), removed before
merge. The first attempt compared two worktrees and was abandoned: the
integer control lane — which runs byte-identical code in both builds — moved
~-4.8% *consistently across both order-flipped passes*, i.e. a per-worktree
binary offset, not the change. The single-binary toggle eliminates that offset
so both modes run in the same process, back to back.

## Results

Same-binary A/B, medians over 6 order-flipped passes (candidate = `value_blob`,
baseline = `value_text`). `selectBytes` is the clean lane (pure C encode, no
Dart String/GC noise); `select` adds per-cell Dart String allocation.

| Lane | base p50 (ms) | cand p50 (ms) | Δ |
|---|---:|---:|---:|
| selectBytes / 5k×3 long TEXT (~200 B) | 1.230 | 1.223 | **−0.6%** |
| selectBytes / 10k×6 short TEXT (~12 B) | 2.141 | 2.192 | **+2.4%** |
| selectBytes / 10k×8 INTEGER (control) | 1.890 | 1.912 | **+1.2%** |
| select / 5k×3 long TEXT (~200 B) | 1.889 | 1.816 | −3.9% |
| select / 10k×6 short TEXT (~12 B) | 5.050 | 5.142 | +1.8% |
| select / 10k×8 INTEGER (control) | 2.603 | 2.583 | −0.8% |

XL spot check (2 KB × 3 cols × 5k rows ≈ 30 MB copied/query, 4 passes each):

| Lane | Δ |
|---|---:|
| selectBytes / 5k×3 XL TEXT (~2 KB) | −0.8% |
| select / 5k×3 XL TEXT (~2 KB) | −0.7% |

**Interpretation.** No consistent, control-exceeding, length-scaling win. On
the clean `selectBytes` path the text lanes (−0.6%, +2.4%) do not beat the
integer control (+1.2%); the decode-path long-TEXT −3.9% is contradicted by
the short-TEXT +1.8% and is the GC-noisiest lane (p90 ≈ 7 ms vs p50 ≈ 1.9 ms).
Decisively, pushing text to 2 KB — where an avoided per-cell copy would be
largest — still moves both paths only ~−0.7%, inside the noise band. The
materialization cost the hypothesis assumed is not there to save.

**Why.** `sqlite3VdbeMemGrow` reuses a `Mem`'s existing `zMalloc` buffer when
it is already large enough. Across a 10k-row scan each result column's `Mem`
allocates once (sized to its largest value) and every subsequent
`value_text` NUL-termination reuses that buffer — the cost is not a malloc per
cell but at most a cheap amortized memcpy, which sits below the harness floor.
`value_blob` avoids even that memcpy, but the saving is immaterial against the
~1–6 µs/row of surrounding step + encode/decode work.

## Outcome

**Rejected** — correct and zero-risk (byte-identical; exp 191 invariant; all
suites green under both modes), but performance-neutral. Runtime reverted; the
focused harness and this record are the contribution. Reopen only if a workload
appears where SQLite cannot reuse the result `Mem` buffer across rows (forcing
a real per-cell allocation), or if the per-row step/decode floor drops enough
that a single amortized memcpy becomes visible.

This also closes the "materialization cost" sibling of exp 205's guidance to
stop re-attacking the per-cell typed-getter pattern: not only is the FFI
*lookup* the same `Mem*`, the text *payload* is already materialized cheaply.

## Test plan

- [x] `dart test test/database_test.dart test/stream_test.dart` (93 tests) —
  green under default (`value_blob`) and `RESQLITE_EXP254_TEXT=1`
  (`value_text`), including embedded-NUL, multibyte-UTF-8, and mixed-type cases.
- [x] Same-binary order-flipped A/B (6 passes) + 2 KB XL spot check.
- [x] `dart analyze` on the focused harness.
- [x] `finalize_experiment.dart` green.

## Related Experiments

- [203](203-cell-value-cache.md), [205](205-step-row-value-cache.md) — hoisted
  the per-cell `columnMem` lookup but kept `value_text`; this tested the
  materialization they left untouched.
- [191](191-embedded-nul-public-api-audit.md) — established the explicit-length
  invariant that makes the `value_blob` switch safe.
- [174](174-selectbytes-view-transfer.md) — prior result-transfer-shape work on
  large byte reads.
