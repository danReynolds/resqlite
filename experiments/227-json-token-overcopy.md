# Experiment 227: Inline 16-byte over-copy for JSON column-name tokens

**Date:** 2026-07-13
**Status:** Accepted
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused
  [`benchmark/experiments/select_bytes_wide_cols.dart`](../benchmark/experiments/select_bytes_wide_cols.dart)
  and
  [`benchmark/experiments/select_bytes_repeated_calls.dart`](../benchmark/experiments/select_bytes_repeated_calls.dart);
  raw pass tables in
  [`benchmark/results/2026-07-13T11-15-52Z-exp227-json-token-overcopy.md`](../benchmark/results/2026-07-13T11-15-52Z-exp227-json-token-overcopy.md).

## Problem

[Exp 195](195-stmt-cache-name-tokens.md) caches each column's JSON name token
(`"name":` or `,"name":`) on the prepared-statement entry so a re-executed
`selectBytes()` never repeats exp 190's per-query pre-encode walk. Every row
of every query then writes each token with:

```c
memcpy(b->data + b->len, tokens_data + token_offsets[i], token_lens[i]);
b->len += token_lens[i];
```

`token_lens[i]` is a runtime value the compiler cannot bound, so it lowers
to a libc `memcpy` call rather than an inline SIMD copy. On a 10k rows x
20 int columns workload that's ~200 000 variable-length copies per query,
each of them a `bl _memcpy` on ARM64 (or the equivalent on x86) with the
function-call round-trip dominating a 5–20-byte copy.

The typical column-name token is short: SQLite column names are usually
under 16 bytes and the JSON-encoded token adds `"..":` (5 bytes of framing).
Nearly every token in production schemas fits in one 16-byte word.

## Hypothesis

If the tokens buffer carries 16 bytes of trailing padding, the row loop can
issue a compile-time-constant `memcpy(dst, src, 16)` for the common
short-token case — which clang / gcc lower to a single 128-bit load-store
pair on ARM64 NEON and x86 SSE — while still advancing `b->len` by the real
`token_lens[i]`. Tokens longer than 16 bytes stay on the runtime-length
`memcpy` fallback.

The row-start `buf_ensure` already reserves `col_count * cell_max` bytes
(33 per cell) for cell payloads, so writing 16 bytes past `b->len` sits
inside the reservation. The 16-byte tail past the actual token length is
overwritten by the cell that follows the token, so no observable output
byte changes.

Accept only if 10k rows x 20 int cols reproduces same-sign
candidate-faster of at least 3% across an order-flipped pair. Reject if
narrower shapes or the repeated-calls single-row guards show a reproduced
regression that outweighs the wide-row win.

## Approach

The change touches only [`native/resqlite.c`](../native/resqlite.c):

- `ensure_json_name_tokens` calls `buf_ensure(&tokens, 16)` once after the
  per-column token build loop and `memset`s those 16 tail bytes to zero, so a
  16-byte load from any valid `token_offsets[i]` never reads past initialised
  memory. `tokens.len` still tracks the real logical length; the padding
  simply lives inside the same allocation.
- `write_json_to_buf`'s row loop keeps the same per-cell dispatch but writes
  the token via `memcpy(dst, src, 16)` when `RESQLITE_LIKELY(token_len <= 16)`,
  falling back to the original `memcpy(dst, src, (size_t)token_len)` for the
  rare long-name case. `b->len += token_len` still advances by the real
  length; the trailing over-written bytes are covered by the row-start
  cell-payload reservation and are overwritten by the very next cell.

No public API changes. No stmt-cache shape changes beyond the 16-byte tail
padding on the tokens buffer, which is a private field.

## Results

Full tables are in the linked result artifact. Decision rows:

| Workload | Pass 1 | Pass 2 | Read |
|---|---:|---:|---|
| wide-cols 10k x 20 int | -3.0% | -3.3% | mechanism reproduced |
| wide-cols 10k x 20 mixed | -5.4% | -2.1% | mechanism reproduced |
| wide-cols 10k x 8 int | -2.2% | -2.0% | reproduced same-sign |
| repeated 10 x 20 int | -3.1% | -2.1% | reproduced same-sign |
| repeated 1000 x 8 int | -2.5% | -3.2% | reproduced same-sign |
| repeated 1 x 20 int | +1.2% | +0.2% | flat — no per-row amortisation |

The primary target lane (10k rows x 20 int cols, most token writes per row)
reproduces -3.0% / -3.3% end-to-end wall on the wide-cols harness. Other
multi-row shapes move in the same direction across the flip. Single-row
shapes have exactly one token loop per query, so no amortisation to claim,
and they stay in noise — including the tiny `1 row x 8 int cols` P1 outlier
whose own P2 comes back to +4.3%.

## Decision

**Accepted.**

The tokens loop is the single hottest per-column write in the JSON encoder
after exp 195 removed the per-query pre-encode. A constant-width 16-byte
copy is the smallest possible change that lets the compiler emit a single
NEON / SSE load-store per token; the reproduced -2 to -3% on every 10k-row
shape and the reproduced -3% on the repeated-calls 1000-row guard clears the
decision bar. The output stays byte-identical because only `token_len` bytes
are counted as valid; the trailing over-written bytes always get overwritten
by the immediately following cell payload.

## Future Notes

- The 16-byte upper bound covers realistic column-name lengths (`"created_at":`
  = 13 bytes, `,"updated_at":` = 14 bytes). Schemas with column names beyond
  ~10 chars still land inside the 16-byte window; only extremely long names
  (>10 unquoted chars per column) fall to the runtime-length fallback, and
  those workloads pay the current per-token cost either way.
- The trailing zero padding on the tokens buffer is a private layout detail.
  Any future stmt-cache reshape (e.g. packing tokens into a shared arena)
  must keep the 16-byte tail guarantee or drop the constant-width copy.
- Do not widen the constant beyond 16 bytes speculatively — every extra
  byte of over-write eats into the row-start `col_count * cell_max`
  reservation. The current 16 leaves ~17 bytes of headroom before the next
  cell's own writes even for `RESQLITE_JSON_FLOAT_MAX`.

## Validation

- `dart pub get`
- `dart analyze --fatal-infos native/resqlite.c lib/`
- `dart test test/database_test.dart --name selectBytes` (all 9 pass)
- order-flipped focused A/B with
  `benchmark/experiments/select_bytes_wide_cols.dart` (two pairs)
- order-flipped focused A/B with
  `benchmark/experiments/select_bytes_repeated_calls.dart` (two pairs)
- `dart run benchmark/finalize_experiment.dart --experiment=experiments/227-json-token-overcopy.md`
