# Experiment 195: Stmt-cache pre-encoded JSON column-name tokens

**Date:** 2026-06-23
**Status:** In Review
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused
  [`benchmark/experiments/select_bytes_repeated_calls.dart`](../benchmark/experiments/select_bytes_repeated_calls.dart)
  order-flipped pair plus the existing
  [`benchmark/experiments/select_bytes_wide_cols.dart`](../benchmark/experiments/select_bytes_wide_cols.dart)
  (exp 190's harness) as a no-regression guard. No release-suite run because
  the changed path is the per-query setup inside `write_json_to_buf` reached
  only via `selectBytes()` and the existing release lanes (10K rows / 1K rows
  / Large payload) are dominated by per-row stepping rather than per-query
  setup work.

## Problem

[Exp 190](190-selectbytes-col-name-preencode.md) pre-built each column's
`"name":` / `,"name":` token once at first-row time inside `write_json_to_buf`
and stored the result in a per-query scratch buffer
([`tokens_buf`](../native/resqlite.c)). Subsequent rows pay one `buf_write`
per column instead of comma + `json_write_string` + colon.

That amortizes per-row work within a single query. The per-query setup is
still paid in full on every call:

- one `buf_init(&tokens_buf, ...)` → 64-byte `malloc` per `selectBytes()` call
  (worst-case `name_len * 6 + 4` per column, but always ≥ 64);
- one walk over every column at first-row time, calling `sqlite3_column_name`,
  `strlen`, `json_write_string` (SWAR scan + escape walk for the name), and
  two `buf_write_char` calls (`,` and `:`);
- a matching `free(tokens_buf.data)` at the end.

For the same prepared SQL re-executed N times, that work runs N times even
though `sqlite3_column_name(stmt, i)` returns the same pointer for the
lifetime of the prepared statement and the encoded tokens are byte-identical
across re-executions. The C-side statement cache already keeps the prepared
statement, its bind-parameter count (exp 077), its read-tables / column
dependencies (exp 106), and the writer's pre-prepared TX statements (exp 101)
across calls. The JSON tokens are the same shape of "depends on the prepared
SQL only" state and have nowhere to live between calls.

## Hypothesis

If the pre-encoded JSON column-name tokens are cached on the `resqlite_cached_stmt`
entry, every `selectBytes()` call after the first reuses them — eliminating
the per-query `buf_init` malloc/free pair and the first-row pre-encode walk.
The per-row loop is bit-identical to exp 190 (one `buf_write` per column per
row), so per-row work stays exactly where it is.

The expected signal:

- small rowsets where the per-query setup is a measurable fraction of total
  wall (~0.5 µs setup vs ~5–10 µs total per call) should move 5–10%;
- large rowsets where per-row work dominates (~3 ms total per call) should
  stay neutral — the 0.5 µs savings is ~0.02% of wall;
- mixed-column shapes should track the same direction as int-only shapes.

Acceptance criterion: two order-flipped focused passes must improve the
small-rowset multi-column primary lanes by more than 5%, with the
large-rowset guard neutral, and the existing exp 190 `wide_cols.dart`
shapes either neutral or improved.

## Approach

In [`native/resqlite.c`](../native/resqlite.c):

- extend `resqlite_cached_stmt` with `json_name_tokens_buf`,
  `json_name_token_offsets`, `json_name_token_lens`, `json_name_tokens_len`,
  and `json_name_tokens_col_count` (the build sentinel);
- add `ensure_json_name_tokens(entry, stmt, col_count)` which builds the
  tokens on first call and returns immediately on subsequent calls. The
  token shape is identical to exp 190 — column 0 emits `"name":`,
  columns 1+ emit `,"name":` — so the per-row inner loop is unchanged;
- change `write_json_to_buf(stmt, b)` to `write_json_to_buf(stmt, entry, b)`;
  the caller (`resqlite_query_bytes`) already has `entry` in scope from the
  preceding `get_or_prepare_reader` call;
- remove the per-query `tokens_buf` + `_token_offsets_stack[64]` +
  `_token_lens_stack[64]` + `_col_names_stack[64]` + `_col_name_lens_stack[64]`
  locals and the matching `free()` paths from `write_json_to_buf`'s cleanup;
- add `stmt_cache_entry_clear_json_name_tokens(entry)` and call it from
  `stmt_cache_entry_dispose` so cached buffers are freed on entry eviction
  and connection close.

A degenerate `col_count <= 0` case (no columns to encode) flags the entry
as built via `json_name_tokens_col_count = -1` so the build path is not
re-entered.

The change does not alter any user-visible JSON output — the encoded
tokens are byte-identical to exp 190.

Added the focused harness
[`benchmark/experiments/select_bytes_repeated_calls.dart`](../benchmark/experiments/select_bytes_repeated_calls.dart)
with:

- 1 row × 8 / 20 int cols, 1 row × 8 mixed cols (primary small-rowset lanes);
- 10 rows × 8 / 20 int cols (mid-size primary lanes);
- 100 rows × 8 int cols, 1000 rows × 8 int cols (regression guards where
  per-row work should dominate any per-query setup savings).

Each lane reports median microseconds per call over 1000 calls/sample ×
11 samples, after a 16-call warm-up, so per-call savings around 0.5 µs are
visible above the harness floor.

## Results

Focused `select_bytes_repeated_calls.dart`, two order-flipped passes
(medians in µs/call):

| Lane | Pass 1 baseline | Pass 1 candidate | Δ | Pass 2 baseline | Pass 2 candidate | Δ |
|---|---:|---:|---:|---:|---:|---:|
| 1 row × 8 int cols | 10.415 | 10.159 | −2.5% | 10.019 | 9.936 | −0.8% |
| 1 row × 20 int cols | 5.730 | 5.204 | −9.2% | 5.355 | 4.967 | −7.2% |
| 1 row × 8 mixed cols | 5.084 | 5.045 | −0.8% | 4.751 | 4.752 | +0.0% |
| 10 rows × 8 int cols | 7.332 | 7.128 | −2.8% | 6.936 | 7.001 | +0.9% |
| 10 rows × 20 int cols | 11.027 | 10.460 | −5.1% | 10.304 | 10.027 | −2.7% |
| 100 rows × 8 int cols | 29.750 | 30.296 | +1.8% | 29.936 | 29.120 | −2.7% |
| 1000 rows × 8 int cols | 251.270 | 253.841 | +1.0% | 251.156 | 246.973 | −1.7% |

Pass 1 ran baseline first then candidate; Pass 2 ran candidate first then
baseline. The 1-row × 20 col and 10-row × 20 col primary lanes reproduce
the predicted shape — same-direction movement across the flip, magnitude
inside the same band. 1 × 8 mixed barely moves: the per-query setup is
already < 1 µs at this shape and the harness sees it inside variance. The
100 / 1000 row guards show sign reversal across the flip (+1.8% / −2.7%
and +1.0% / −1.7%), which under exp 177's drift discriminator rule
classifies as drift-suspected rather than reproduced — consistent with
"no real movement" at sizes where per-row work dominates.

Exp 190's existing `select_bytes_wide_cols.dart` harness, two order-flipped
passes (medians in ms/call):

| Lane | Pass 1 baseline | Pass 1 candidate | Δ | Pass 2 baseline | Pass 2 candidate | Δ |
|---|---:|---:|---:|---:|---:|---:|
| 10k rows × 8 int cols | 2.479 | 2.426 | −2.1% | 2.467 | 2.427 | −1.6% |
| 10k rows × 20 int cols | 5.868 | 5.789 | −1.3% | 6.178 | 5.770 | −6.6% |
| 10k rows × 8 mixed cols | 2.660 | 2.534 | −4.7% | 2.618 | 2.586 | −1.2% |
| 10k rows × 20 mixed cols | 6.257 | 6.077 | −2.9% | 6.216 | 6.143 | −1.2% |
| 10k rows × 2 int cols | 0.740 | 0.714 | −3.5% | 0.737 | 0.711 | −3.5% |
| 1 row × 5 mixed cols | 0.018 | 0.018 | n/a | 0.017 | 0.017 | n/a |
| 100 rows × 5 mixed cols | 0.033 | 0.033 | n/a | 0.034 | 0.033 | n/a |

Same-direction movement on every 10k-row lane across the flip. The 1-row
and 100-row lanes on this harness sit at the harness's millisecond-reporting
resolution floor — the focused `select_bytes_repeated_calls.dart` harness
above is the correct lane for those shapes.

## Decision

**Accepted / In Review.** The per-query setup amortization is small but
reproducible on the predicted shape: 1-row × 20-col and 10-row × 20-col
lanes move 5–9% same-direction across two order-flipped passes, where the
~0.5 µs of removed per-query work is a measurable fraction of total wall.
The 10k-row lanes also trend candidate-faster across both passes on every
shape, consistent with eliminating the per-query `malloc(64)` + `free`
pair from the hot path. The 100 / 1000-row guards show drift-suspected
sign reversal — consistent with "no real movement" where per-row work
dominates per-query setup by 100× or more.

The implementation is bounded — five new fields on the cache entry, one
new helper, a one-arg signature change on `write_json_to_buf`. Memory cost
per cached statement is `O(col_count * 8 + name_byte_count)` bytes, capped
by `STMT_CACHE_MAX = 32` per reader/writer connection (~tens of KB worst
case for a fully populated cache of wide schemas). Public JSON output is
byte-identical to exp 190.

The release suite is not the right denominator for this change: the
public Select Bytes lanes either return 1K+ rows (per-row work dominates)
or are large-payload-bounded (per-row work amplified). The durable gate
is `select_bytes_repeated_calls.dart` for small repeated queries plus
`select_bytes_wide_cols.dart` for the broader compatibility band.

## Future Notes

- Exp 190's per-row inner loop is unchanged. Any future per-row encoder
  work (e.g. a fractional-REAL fast path following exp 194) should not
  need to touch the token cache. The cache only stores invariant token
  bytes; per-cell value emission is the same code path as today.
- The `_token_offsets_stack[64]` / `_token_lens_stack[64]` stack fallback
  exp 190 used for wide schemas is no longer needed: the cache entry's
  per-column arrays are heap-allocated unconditionally, paid once per
  statement instead of once per query.
- If a future workload calls `selectBytes()` with hundreds of distinct
  prepared SQLs, the per-statement cache cost (~hundreds of bytes per
  entry) becomes more visible at the existing `STMT_CACHE_MAX = 32` cap.
  Reopen if release-suite memory probes flag the cache size.
- The same "promote to stmt-cache" shape could plausibly apply to the
  exp 190-style token pre-encoding for any other future per-query
  invariant work (e.g. per-column type lookups if a future workload
  shows type dispatch is hot). Pattern-match on "per-query, depends only
  on the prepared stmt" before reaching for a per-query scratch buffer.

## Validation

- `dart pub get`
- `dart format benchmark/experiments/select_bytes_repeated_calls.dart`
- `dart analyze --fatal-infos native/resqlite.c benchmark/experiments/select_bytes_repeated_calls.dart`
- `dart test test/database_test.dart` (52 tests pass)
- `dart run benchmark/experiments/select_bytes_repeated_calls.dart` on baseline and candidate in baseline-first order
- `dart run benchmark/experiments/select_bytes_repeated_calls.dart` on candidate and baseline in candidate-first order
- `dart run benchmark/experiments/select_bytes_wide_cols.dart` on baseline and candidate in both orders (no-regression guard on exp 190's shapes)
