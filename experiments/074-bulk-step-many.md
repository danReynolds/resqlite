# Experiment 074: Bulk `step_many` for the non-streaming read path

**Date:** 2026-04-16
**Status:** Rejected (memcpy cost exceeds FFI-crossing savings — same wall as exp 018)

## Problem

The read-worker hot path issues one FFI call per row via
`resqlite_step_row`. At ~60-80 ns per `isLeaf` FFI crossing, a
10,000-row scan pays ~0.8 ms just in crossings — ~15 % of the
measured 5.6 ms wall time.

Exp 018 ("multi-row step, 64 rows per FFI") rejected a similar idea
because SQLite's `sqlite3_column_text` pointers are only valid until
the next `sqlite3_step` on the same statement, forcing a byte-copy
into our own buffer to safely batch rows — copy cost exceeded the
FFI savings.

## Hypothesis (the reshape)

Dart already copies text/blob content via `fastDecodeText` and
`Uint8List.fromList`. If we move the copy to C during the batched
step loop, the *copy work* stays roughly the same, but we save
(N-1) FFI crossings per query. Net win when FFI cost > any
overhead added by doing the copy in C instead of Dart.

## Approach

### C side

- `struct resqlite_bytes_buf` — persistent per-reader arena holding
  text/blob content copied out of SQLite's transient buffers.
- `resqlite_bytes_buf_create/_free` — lifecycle helpers.
- `resqlite_step_many(stmt, col_count, max_rows, cells, bytes,
  *out_bytes_ptr, *out_n_rows)` — steps up to `max_rows` rows in a
  single FFI call. For each row:
  - INT/FLOAT: inline into cell (same as step_row).
  - TEXT/BLOB: memcpy content into `bytes` arena; cell stores the
    offset (during the loop) reinterpreted to a pointer (in a
    post-loop fixup pass) once `bytes->data` is stable.
  - Return SQLITE_ROW if batch filled (caller calls again) or
    SQLITE_DONE / error otherwise.

The offset-then-fixup approach is the non-obvious correctness fix —
`bytes_buf_reserve` can realloc and move the buffer mid-loop, so
writing `cell->p = bytes->data + len` directly would dangle all
earlier cells' pointers. Storing offsets during the loop and
resolving in one pass at the end sidesteps the realloc race.

### Dart side

- FFI binding `resqliteStepMany` + lifecycle bindings for the bytes
  buffer.
- `decodeQueryBulk(stmt, sql)` — parallel to `decodeQuery`, calls
  `resqliteStepMany` in a while-loop with a 128-row batch. Cell
  decoding in Dart is identical to the single-row path (same cell
  layout, same `fastDecodeText`).
- Wired into `_executeQueryImpl` for the non-streaming `select()`
  path (the streaming / hashing path still uses `step_row_h` since
  per-row hashing doesn't compose cleanly with batching).

All 129 tests pass after fixing two bugs found during bring-up:
1. Inverted SQLITE_ROW / SQLITE_DONE rc codes caused an infinite
   loop — fixed by using the existing `sqliteRow = 100` constant.
2. Stale text pointers after `realloc` — fixed by offset-then-fixup
   (see above).

## Results

A/B with 052' library changes stashed in/out of the post-053
baseline, `--repeat=5`:

### Regressions

| Benchmark | Baseline (ms) | exp052' (ms) | Δ |
|---|---:|---:|---:|
| Schema Shapes (Text-heavy 4 long TEXT cols, 1000 rows) | 0.65 | 0.90 | **+38%** |
| Concurrent Reads (1000 rows, 4× concurrent) | 0.70 | 0.79 | **+13%** |
| Concurrent Reads (1000 rows, 2× concurrent) | 0.37 | 0.42 | **+14%** |

### Neutral

| Benchmark | Baseline (ms) | exp052' (ms) | Verdict |
|---|---:|---:|---|
| Select → Maps / 1000 rows | 0.38 | 0.41 | within noise |
| Select → Maps / 10000 rows | 5.29 | 5.90 | within noise (±11%) |
| Point Query Throughput (qps) | 115,075 | 122,339 | within noise |

No measurable wins on any benchmark; clear regressions on text-heavy
paths.

## Why It Didn't Work (same as 018, now quantified)

The "save N FFI crossings, pay N memcpy's" trade looks balanced on
paper. In practice the memcpy is worse:

1. **Dart's existing path doesn't actually memcpy text during the
   row loop.** `fastDecodeText(textPtr, textLen)` reads bytes
   directly from SQLite's internal buffer to construct a Dart
   `String` — the allocation + utf8 decode IS the "copy", but it
   happens once and produces a Dart-native object.
2. **052' memcpies first into the arena, THEN Dart reads from the
   arena to build a Dart `String`.** That's two passes over the
   text bytes.
3. **FFI crossings with isLeaf are cheaper than I estimated.** The
   60-80 ns figure is the isolate-boundary cost; for a same-isolate
   `@ffi.Native(isLeaf: true)` call the marginal overhead is closer
   to 20-30 ns once JIT is warm. For a 10k-row scan that's ~0.3 ms
   of savings, not 0.8 ms.

The net math: save ~0.3 ms of FFI, add ~0.5-1 ms of extra memcpy on
text-heavy results. Regression.

Numeric-only or very small text results MAY benefit, but the
existing benchmark suite's typical mix (`items` table with id, name,
value columns — text + int) shows this is not the common case.

## Decision

Rejected. Same conclusion as exp 018, now confirmed with the
"reshape" that was supposed to make it work. The copy cost is
fundamental — you can move it around but you can't make it free.

## What this rules out for Round 3

Do not attempt:
- More aggressive batch sizes (128 vs. 64 — not the bottleneck).
- Different arena strategies (per-batch-estimate preallocation,
  ring buffers) — the memcpy itself is the cost, not its
  bookkeeping.
- Combining with exp 075's hashing — the hashing already walks the
  cell bytes in C, but it doesn't copy them; combining would just
  add the same memcpy cost.

What remains plausible:
- A **pure-numeric fast path** that uses step_many when the column
  types are all INT/FLOAT, falling back to step_row otherwise.
  Gated on declared column types via `sqlite3_column_decltype`.
  Worth a spike if numeric-only workloads are common enough to
  justify the dual-path complexity.
- Eliminating FFI crossings further up the stack — e.g. combining
  `stmt_acquire_on` + first `step_row` + `column_count` into one
  FFI. Saves only 2 crossings per query, so only measurable on
  point-query throughput.
