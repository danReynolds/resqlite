# Experiment 199: Row-level capacity reservation in `write_json_to_buf`

**Date:** 2026-06-25
**Status:** In Review
**Direction:** `result-transfer-shape`
**Benchmark Run:** Focused A/B
(`benchmark/experiments/select_bytes_int_heavy.dart`,
`benchmark/experiments/select_bytes_real_int_fastpath.dart`,
`benchmark/experiments/select_bytes_wide_cols.dart`), order-flipped pair on a
quiet box; release-suite single-pass A/B captured as a no-regression smoke.

## Problem

After [exp 195](195-stmt-cache-name-tokens.md) cached the column-name tokens
on the prepared-statement entry and [exp 198](198-direct-buf-int-float-json.md)
collapsed the per-cell integer/float formatter through to a direct write, the
inner per-cell loop of `write_json_to_buf` still pays one `buf_ensure` per
write:

```c
JSON_CHECK(buf_write(b, tokens_data + token_offsets[i], token_lens[i])); // ensure(N)
int type = sqlite3_column_type(stmt, i);
switch (type) {
    case SQLITE_INTEGER:
        JSON_CHECK(buf_write_int_json(b, sqlite3_column_int64(stmt, i)));  // ensure(24)
        break;
    case SQLITE_FLOAT:
        JSON_CHECK(buf_write_double_json(b, sqlite3_column_double(stmt, i))); // ensure(33)
        break;
    ...
}
```

Plus `buf_write_char(b, '{')` / `buf_write_char(b, '}')` / `buf_write_char(b,
',')` for braces and the row separator. On a 10k row × 20 column INTEGER
SELECT that is roughly `2N + 2 ≈ 42` `buf_ensure` calls per row, all checking
the same `b->len + n <= b->cap` invariant against a `json_buf` that has long
since grown well past the row's working set. Each check is small (one
predicted branch) but the cumulative cost shows up at the bottom of the
encoder profile — every other cell-formatter cost above it (digit loop,
SWAR escape scan, column-name token expansion) has been amortized in
prior experiments.

## Hypothesis

For rows whose cells are all NULL / INTEGER / FLOAT, total row size has a
fixed upper bound (`tokens_total + N × 33 + 2`). A single row-level
`buf_ensure` covers the entire row, after which every NULL / INTEGER / FLOAT
cell can write directly into `b->data + b->len` without a per-cell ensure.
TEXT / BLOB cells stay on their existing helpers (`json_write_string`,
`json_write_base64`) — both internally do their own `buf_ensure`, so we
just re-ensure remaining headroom after they return.

The signal should reproduce most strongly on the wider int-heavy lanes
exp 192/198 already use as their gate, and stay flat on mixed and
fractional-real lanes where the saved `buf_ensure` is a small fraction of
per-cell work.

## Approach

In [`native/resqlite.c`](../native/resqlite.c) `write_json_to_buf`:

- Hoist the per-row prelude (`'{'`, optional `','`), all column-name
  tokens, the per-cell fixed-size upper bound (`col_count × (RESQLITE_JSON_FLOAT_MAX + 1)`,
  which dominates the INT and "null" sizes), and the trailing `'}'` into a
  single `buf_ensure` at row start. The 33-byte FLOAT bound is used for
  every fixed cell so the calc stays a single multiply.
- Inside the per-column loop, write tokens via `memcpy` against
  `b->data + b->len` directly. NULL / INTEGER / FLOAT branches write
  the formatted bytes through `fast_i64_to_str` /
  `fast_double_to_json_num` / `memcpy("null", 4)` straight to
  `b->data + b->len`, advancing `b->len` directly. No per-cell
  `buf_ensure`.
- TEXT / BLOB branches keep their existing helpers (which manage their
  own ensure), then re-ensure `remaining_tokens + remaining_cells + 1`
  (`+ '}'`) so subsequent direct writes stay in-bounds even if the
  helper grew the buffer past our row-start reservation.
- The opening `'['` and closing `']'` for the JSON array stay on
  `buf_write_char` — they fire twice per query regardless of row shape,
  so the row-level reservation cannot subsume them.

The result is bit-identical JSON: the same formatters, the same token
bytes, the same TEXT / BLOB helpers. No new const data; one removed
`JSON_CHECK(buf_write_char(b, '{'))` / `'}'` / `','` per row, one
removed `JSON_CHECK(buf_write(...))` per column-name token, and
(NULL / INTEGER / FLOAT) one removed `buf_write_str` / `buf_write_int_json`
/ `buf_write_double_json` indirection per fixed cell. No public API
change.

## Results

Two order-flipped passes on each focused harness, median of 6 rounds
per lane. Same-machine quiet box (Apple Silicon, Dart 3.x AOT).

### `select_bytes_int_heavy.dart` (exp 192's harness)

| Lane | Pass 1 base | Pass 1 cand | Δ P1 | Pass 2 base | Pass 2 cand | Δ P2 |
|---|---:|---:|---:|---:|---:|---:|
| 10k × 8 small ints | 2796 | 2751 | **−1.6 %** | 2800 | 2689 | **−4.0 %** |
| 10k × 20 small ints | 6674 | 6218 | **−6.8 %** | 6411 | 6233 | **−2.8 %** |
| 10k × 20 big ints (~18 digits) | 7359 | 7233 | **−1.7 %** | 7459 | 7236 | **−3.0 %** |
| 10k × 8 mixed (4 int + 2 text + 2 real) | 8833 | 8782 | −0.6 % | 8846 | 8794 | −0.6 % |
| 1k × 2 ints | 105 | 101 | **−3.8 %** | 104 | 102 | **−1.9 %** |

All values µs/query median. Every int-heavy lane reproduces the same
direction (candidate faster) across the order flip; magnitudes spread
from −1.6 % to −6.8 % across the per-lane noise. The mixed-row guard
(4 int + 2 text + 2 real) stays flat at −0.6 % both passes — the TEXT
re-ensure inside the candidate's row loop balances the saved per-cell
ensures on the same row, exactly as expected.

### `select_bytes_real_int_fastpath.dart` (exp 194's harness)

| Lane | Pass 1 base | Pass 1 cand | Δ P1 | Pass 2 base | Pass 2 cand | Δ P2 |
|---|---:|---:|---:|---:|---:|---:|
| 10k × 8 integral reals | 2988 | 2994 | +0.2 % | 3012 | 3005 | −0.2 % |
| 10k × 20 integral reals | 6627 | 6613 | −0.2 % | 6618 | 6659 | +0.6 % |
| 10k × 20 fractional reals | 68147 | 68124 | 0.0 % | 68174 | 68181 | 0.0 % |
| 10k × 8 mixed (4 int-real + 2 frac-real + 2 text) | 9301 | 9353 | +0.6 % | 9308 | 9379 | +0.8 % |
| 1k × 2 integral reals | 110 | 109 | −0.9 % | 109 | 109 | 0.0 % |

All real lanes sit inside ±1 %. The fractional REAL lane stays exactly
flat: `fast_double_to_json_num`'s `snprintf("%.17g")` dwarfs the saved
per-cell ensures by 2–3 orders of magnitude, so the saving is
arithmetically invisible. The mixed real lane shows a reproduced
+0.6 % / +0.8 % — the per-cell ensures saved by the candidate are
spent (and slightly exceeded) by the TEXT re-ensure on the same row —
which is below the per-benchmark decision threshold.

### `select_bytes_wide_cols.dart` (exp 190 / 195's harness)

| Shape | Base | Cand | Δ |
|---|---:|---:|---:|
| 10k × 8 int cols | 2.208 | 2.125 | **−3.8 %** |
| 10k × 20 int cols | 5.184 | 5.059 | **−2.4 %** |
| 10k × 8 mixed cols | 2.412 | 2.435 | +1.0 % |
| 10k × 20 mixed cols | 5.739 | 5.667 | −1.3 % |
| 10k × 2 int cols | 0.642 | 0.634 | −1.2 % |
| 1 row × 5 mixed cols | 0.014 | 0.017 | (µs-scale guard) |
| 100 rows × 5 mixed cols | 0.030 | 0.032 | (µs-scale guard) |

All values ms/call median. The two int-only lanes reproduce the focused
win (`−2.4 %` / `−3.8 %`); mixed and small-row lanes are at the noise
floor (the 1-row and 100-row shapes are µs-scale and below the
harness's resolution). No regression on the mixed lanes.

### Release-suite single-pass A/B

Baseline: [`benchmark/results/2026-06-25T07-44-46-baseline-for-exp199.md`](../benchmark/results/2026-06-25T07-44-46-baseline-for-exp199.md).
Candidate: [`benchmark/results/2026-06-25T07-33-46-exp199-row-level-buf-ensure.md`](../benchmark/results/2026-06-25T07-33-46-exp199-row-level-buf-ensure.md).

`resqlite` wall-median deltas vs the baseline: **14 wins (< −5 %)**,
**13 regressions (> +5 %)**, **128 neutral**, single-pass.

Most flagged rows live on writer / streaming paths that this candidate
cannot mechanically touch:

- Several `Chat Sim` write rows (−20 % to −29 %), `Batched Write Inside
  Transaction (100 rows)` (−34 %), `Nested Transactions (savepoints)`
  (+12 %), `Batched Write Inside Transaction (1000 rows)` (+9 %),
  `Initial Emission` (+11 %) — write paths and stream-dispatch lanes.
  The candidate touches only `write_json_to_buf`, which is the read /
  `selectBytes` JSON encoder; these lanes do not call it.
- `Streaming / Long-Payload Unchanged Fanout (8 streams, 64 rows × 32 KB
  TEXT + 32 KB BLOB)` +22 % — the unchanged-fanout path calls
  `resqlite_query_hash` (FNV hash over raw cell bytes), not
  `write_json_to_buf`. This is the canonical exp 159 / exp 177 single-pass
  drift signature on a sub-ms metric.
- `Batched Write Inside Transaction` shows a +9 %/−34 % sign-flip between
  the 1000-row and 100-row sibling lanes — the JOURNAL's "sign reversal
  across sibling tests" drift signature exp 177's classifier flags.

The release-suite lane that does mechanically touch this change —
`Select → JSON Bytes / Large payload (~650 KB) / resqlite selectBytes()`
— moves **−12.7 %**, in the predicted direction. `Streaming /
Unchanged Fanout Throughput (1 canary + 10 unchanged streams)` also
moves −5.5 %, consistent with the encoder-side saving on the initial
emission path (the unchanged short-circuit then hits the hash path).

The focused order-flipped pair on `select_bytes_int_heavy.dart` is the
load-bearing evidence here; the release-suite single-pass A/B is a
no-regression smoke against the canonical baseline, with the flagged
rows interpreted under the standard JOURNAL drift discriminator.

## Decision

**In Review (candidate-accepted at the local level).** The focused
order-flipped pair on `select_bytes_int_heavy.dart` reproduces a
same-direction candidate-faster effect on all five integer-heavy lanes
(`−1.6 % / −4.0 %`, `−6.8 % / −2.8 %`, `−1.7 % / −3.0 %`, `−0.6 % / −0.6 %`,
`−3.8 % / −1.9 %`). The integer-real and fractional-real lanes stay
inside ±1 %; the wide-cols int lanes carry the same direction; no
release-suite hot-path lane regresses in both directions of the
single-pass A/B. Bit-identical JSON; `dart test
test/database_test.dart test/select_bytes_transfer_test.dart
test/query_decoder_test.dart test/stream_test.dart` all pass against
the candidate.

The magnitude is smaller than [exp 192](192-two-digit-itoa.md) /
[exp 198](198-direct-buf-int-float-json.md) (−7 % to −9 % on the
same lanes) because those experiments removed a multi-byte
formatter / a non-trivial `memcpy`; what's left for this hoist is the
per-cell `buf_ensure` branch itself, already compiled down to one
predicted comparison. The win is real but small — the natural last
collapse of the per-cell ensure stack the prior experiments left in
place.

## Why kept

The savings are structurally what the diff predicts: zero per-cell
ensures on the fixed-size fast path, identical formatter output, and
the TEXT / BLOB recovery path is a single re-ensure call per
variable-size cell. The change is ~50 net lines of additive C, no
new const data, no new public API surface, and no new allocation.

The fixed-size fast path is also the entry point any future
encoder-side change (per-cell type prediction, schema-driven row
prelude, prepared-statement type cache across rows) would need: it
exposes "this row's fixed-size cells" as a single hoisted reservation
instead of a per-cell scatter.

## What this leaves on the table

The remaining per-row cost is dominated by:

- `sqlite3_column_type` + `sqlite3_column_int64` / `column_double` —
  one cross-boundary call per cell, the floor any future fixed-cell
  encoder will hit. A `decltype`-driven type cache on the cached
  statement would skip the column_type call, but SQLite type affinity
  can vary per row in the general case and the audit cost is real.
- The `'['` / `']'` per-query brackets and the column-name token
  `memcpy`s, both already on direct-write paths.
- `snprintf("%.17g")` on the fractional REAL path (out of scope here;
  see exp 198's "what this leaves on the table").

## Operational notes

- No public API change.
- ~50 net additional lines of C in `native/resqlite.c`; the existing
  slow path is now the variable-cell path, gated by per-cell type.
- Existing int-extremes (`LLONG_MIN`, `LLONG_MAX`), real-integer-valued,
  fractional-REAL, embedded-NUL text, and base64 BLOB `selectBytes`
  tests all pass unchanged against the candidate; no test changes
  were necessary.
- Builds clean against current sqlite3mc; no compiler-version
  dependence (uses only standard C library `memcpy`).
