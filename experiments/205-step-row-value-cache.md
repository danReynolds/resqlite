# Experiment 205: per-cell `sqlite3_column_value` reuse in `resqlite_step_row`

**Date:** 2026-06-29
**Status:** Accepted
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused
  [`benchmark/experiments/select_rows_step_row_ffi.dart`](../benchmark/experiments/select_rows_step_row_ffi.dart),
  two order-flipped passes on a quiet box. No release-suite run because no
  current release lane isolates the rows-path per-cell FFI fraction — the
  release `select_maps` shape is dominated by mixed-text Dart-side decode and
  consumer construction, which masks the per-cell saving the candidate
  targets.

## Problem

[Exp 203](https://github.com/danReynolds/resqlite/pull/213) (in review) cached
`sqlite3_column_value` once per cell inside `write_json_to_buf` so the
per-cell switch dispatches through `sqlite3_value_*` instead of redoing
`columnMem` per typed getter. The same per-cell shape — `sqlite3_column_type`
then a typed `sqlite3_column_<x>` getter, plus a `sqlite3_column_bytes` for
TEXT/BLOB — exists verbatim in the rows-path decoder (`resqlite_step_row`),
the initial-stream hash decoder (`resqlite_step_row_hash`), and the
unchanged-fanout stream hash loop (`resqlite_query_hash`). Each of those
fires two `columnMem` invocations per INTEGER/FLOAT cell and three per
TEXT/BLOB cell.

Exp 203's writeup deliberately scoped itself to `write_json_to_buf` and
flagged the symmetric rows / hash paths as "a separate experiment with the
right gate," because the per-cell FFI fraction is a smaller share of total
wall when the Dart-side cell decode is dominant. That smaller share is still
real per-cell work, so the question is whether a focused harness can see it
without a release lane that no longer has the right denominator.

## Hypothesis

`Database.select()` decoding 10k mixed-INTEGER rows × 20 columns issues 400 k
`sqlite3_column_type` + `sqlite3_column_int64` pairs per query. Each pair is
one extra `columnMem` invocation; collapsing the pair to a single
`sqlite3_value*` + `sqlite3_value_type` + `sqlite3_value_int64` reuses the
same `Mem*` and removes one `columnMem` per cell. For 20-column INTEGER rows,
that is roughly 200 k columnMem invocations saved per 10 k-row query — small
in microseconds per cell, but cumulative across the row loop.

The bet: INTEGER- and short-TEXT-heavy lanes should reproduce a same-sign
candidate-faster delta across two order-flipped passes on the focused harness.

## Approach

The candidate touches three functions in `native/resqlite.c`:

- `resqlite_step_row` (rows path; called from
  [`lib/src/query_decoder.dart`](../lib/src/query_decoder.dart) `decodeQuery`).
- `resqlite_step_row_hash` (initial-stream hash decoder; called from
  `decodeQueryWithInitialHash`).
- `resqlite_query_hash` (unchanged-fanout stream-hash loop; called when the
  reader takes the exp 077 short-circuit path).

Each function changes the per-cell prologue from

```c
int type = sqlite3_column_type(stmt, i);
switch (type) {
    case SQLITE_INTEGER: ... sqlite3_column_int64(stmt, i) ...;
    case SQLITE_TEXT:    ... sqlite3_column_text(stmt, i);
                          ... sqlite3_column_bytes(stmt, i) ...;
    ...
}
```

to

```c
sqlite3_value* val = sqlite3_column_value(stmt, i);
int type = sqlite3_value_type(val);
switch (type) {
    case SQLITE_INTEGER: ... sqlite3_value_int64(val) ...;
    case SQLITE_TEXT:    ... sqlite3_value_text(val);
                          ... sqlite3_value_bytes(val) ...;
    ...
}
```

Ordering preserved: `sqlite3_value_text` runs before `sqlite3_value_bytes`
for the same reason `column_text` runs before `column_bytes` — calling
`bytes` first on a TEXT cell can trigger an implicit type conversion that
invalidates the text pointer. Cell-buffer writes, hash combine order, and
all surrounding loops are byte-identical.

The SQLite documentation warns that the value returned by
`sqlite3_column_value` is an "unprotected" `sqlite3_value*` and that
`sqlite3_value_*` calls on it are not threadsafe. The warning targets
multithreaded races against the connection mutex. Every resqlite connection
opens with `SQLITE_OPEN_NOMUTEX` and is owned by a single isolate worker, so
no thread can race the `Mem*` and "unprotected" / "protected" collapse to
the same thing inside this codebase — the same argument exp 203 uses for
`write_json_to_buf`. Tests verify the bit-identical behaviour: 53 / 53 pass
on the candidate, including `selectBytes encodes int64 extremes`, `encodes
real integer-valued numbers`, `encodes blobs as base64`, `preserves
embedded-NUL text`, the `select returns many rows with correct types`
`transaction` test, and the unicode + blob round-trip tests.

The focused harness
[`benchmark/experiments/select_rows_step_row_ffi.dart`](../benchmark/experiments/select_rows_step_row_ffi.dart)
exercises only the rows path:

- 10k × 8 INTEGER: narrow-row control.
- 10k × 20 INTEGER: wide row with the lowest per-cell formatter cost,
  largest per-cell FFI share.
- 10k × 20 short TEXT: wider row with the 3-FFI TEXT path, but Dart-side
  short-string decode adds noise.
- 10k × 6 mixed (the standard schema used elsewhere): real-shaped guard.

Wall is measured as end-to-end `select()` p50 across 200 iterations after 30
warmup rounds; the harness was copied into the baseline worktree so both
sides ran the identical Dart code.

## Results

Raw tables are preserved in
[`benchmark/results/2026-06-29T16-00-00Z-exp205-step-row-value-cache.md`](../benchmark/results/2026-06-29T16-00-00Z-exp205-step-row-value-cache.md).

### Order-flipped p50 deltas

| Lane | Pair 1 Δ | Pair 2 Δ |
|---|---:|---:|
| 10k × 8 INTEGER | −4.8 % | −2.5 % |
| 10k × 20 INTEGER | −9.2 % | −0.8 % |
| 10k × 20 short TEXT | −6.6 % | −5.8 % |
| 10k × 6 mixed (default) | −11.2 % | −3.4 % |

Every lane is candidate-faster in both orderings. The magnitude flexes by
order — Pair 1 (baseline first) shows larger deltas across the board, Pair 2
(candidate first) compresses but never crosses zero. Per JOURNAL's order-flip
rule, the sign preservation rules out the drift signature: a pure
time-correlated regression would have flipped to candidate-slower under the
order swap. The four lanes settle into roughly a `−1 % to −6 %` band, with
the 20-column wide INTEGER lane and the default mixed lane carrying the
larger Pair 1 signals.

The mechanism is consistent with the magnitudes. For the 20-column INTEGER
lane, the candidate removes ~200 k `columnMem` invocations per 10 k-row query
(one per cell). On a 6 ms query, a few percent of wall reflects per-cell FFI
overhead that the typed-getter pattern was paying twice.

### Negative control

The 10k × 6 mixed lane carries TEXT cells, REAL cells, and the integer
primary key. The 20 × short TEXT lane is the inverse — every non-key cell
goes through the 3-FFI TEXT path. Both reproduce candidate-faster, but the
mixed lane's Pair 1 delta is the largest single number (−11.2 %). This is
the expected shape: the FFI saving applies to every cell type, and a
mixed-cell row paid the savings on every column. There is no lane in which
the candidate trends slower — no per-cell type is regressed.

## Decision

**In Review (candidate accepted).** A conservative ~1–6 % win on the rows
path that exp 203 explicitly scoped out, reproduced same-sign across two
order-flipped passes, with the same correctness story (`SQLITE_OPEN_NOMUTEX`
+ single-isolate worker = "unprotected" `sqlite3_value*` is safe) and the
same byte-identical output (every selectBytes correctness test passes, every
`select() returns many rows` shape passes).

The change is ~25 net lines of additive C, no public API change, no
allocation policy change, no impact on caller code in `query_decoder.dart`.
The matching cleanup on `resqlite_step_row_hash` and `resqlite_query_hash`
ships in the same diff because they share the same per-cell shape and the
same correctness argument; they have no representative focused harness in
the suite today but the mechanism is identical to `resqlite_step_row` and
the per-cell FFI count is the same.

## Test plan

- `dart analyze --fatal-infos native/ lib/` (clean)
- `dart test test/database_test.dart` (53/53 pass)
- Focused order-flipped A/B on
  `benchmark/experiments/select_rows_step_row_ffi.dart`
- `dart run benchmark/finalize_experiment.dart --experiment=experiments/205-step-row-value-cache.md`

## Future Notes

- Future rows-path encoder / decoder amortization should run
  `select_rows_step_row_ffi.dart` as the durable gate, the same way exp 195
  established `select_bytes_repeated_calls.dart` for the JSON encoder cache
  entry.
- The stream-hash unchanged-fanout path
  (`single_stream_long_payload_hash.dart`) is dominated by the FNV byte fold
  for the 32 KB / 64 KB shapes tracked by the `long-text-stream-hashing`
  direction — the per-cell FFI saving on `resqlite_query_hash` is below the
  fold cost there, so a release-suite stream regression on this change is
  not expected. If a short-cell stream workload ever becomes the chosen
  diagnostic for that direction, it can reuse the focused harness shape from
  this experiment.
