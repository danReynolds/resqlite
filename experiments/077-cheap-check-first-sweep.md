# Experiment 077: Cheap-check-first sweep (four small wins)

**Date:** 2026-04-16
**Status:** Accepted (one real win + three defensible cleanups)

## Problem

Continuing the "don't do work when a cheaper check will do" theme from
experiments 068–076, an audit of the hot paths turned up four places
that pay a fixed cost on every call even when the eventual answer is
"nothing to do":

1. **`StreamEngine.handleDirtyTables`** — every write schedules a
   microtask and iterates the accumulated dirty-tables set through the
   inverted index, even when no stream has registered any dependency
   yet. The preupdate hook fires on every row-touching write regardless
   of whether any reactive query exists.

2. **`resqlite_query_hash` (pass 1 of selectIfChanged)** — on a changed
   result, every cell is still hashed before the mismatch is declared.
   If the row count has already diverged from the cached baseline, the
   hashes can't match — but the function folded every remaining cell
   byte anyway.

3. **`bind_params` on every write / read** — calls
   `sqlite3_bind_parameter_count(stmt)` inline to validate the caller's
   binding count. `sqlite3_bind_parameter_count` is a C function that
   walks the statement's bytecode to find the highest placeholder index.
   Same stmt + same SQL = same count, every time.

4. **`getReadTables`** — each stream subscription allocates a
   512-byte `Pointer<Pointer<Utf8>>` buffer, makes the FFI call,
   populates a `<String>[]`, then frees the buffer. Mirror of
   experiment 070's persistent dirty-tables buffer, but on the reader
   side.

Each fix is small. Grouped here because they share a methodology:
**check the cheap short-circuit condition before you pay for the work,
and move invariants out of the hot path.**

## Hypothesis

Piece 1 should reduce write overhead in apps that don't use streams
(or write before any stream registers). Pieces 2–4 are tiny
per-call savings on specific hot paths — each below the benchmark
noise floor individually, but directionally consistent.

## Approach

### Piece A — `handleDirtyTables` no-streams fast-reject

`_tableToKeys` is populated by `_updateReadTables`, which only runs
after a stream's initial query returns. If it's empty:

- Either there are no streams at all (e.g. apps using only
  `select()`), OR
- Every active stream is still mid-initial-query — in which case
  those streams rely on the `_writeGeneration != generationBefore`
  race-detection path in `_createStream`, not on the dirty-tables
  pipeline.

Either way, accumulating + scheduling + flushing is pure waste. The
increment of `_writeGeneration` stays (initial-query race detection
still needs it); everything after is gated on a non-empty inverted
index.

```dart
void handleDirtyTables(List<String> dirtyTables) {
  if (dirtyTables.isEmpty) return;
  _writeGeneration++;
  if (_tableToKeys.isEmpty) return;  // NEW
  // … accumulate + scheduleMicrotask …
}
```

### Piece B — row-count short-circuit in `resqlite_query_hash`

The function now accepts a `last_row_count` argument (-1 on the
initial-query path) and an out-pointer. When the fresh step count
exceeds the cached value, further cell hashing stops — we still drain
the remaining rows to report the accurate count but skip the
per-cell byte fold.

```c
while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
    row_count++;
    if (!skip_hash && last_row_count >= 0 && row_count > last_row_count) {
        skip_hash = 1;   // NEW
    }
    if (skip_hash) continue;
    for (int i = 0; i < col_count; i++) {
        // … existing per-cell hashing …
    }
}
*out_row_count = row_count;
```

The Dart side stores the row count on `StreamEntry.lastRowCount` and
passes it into `selectIfChanged`. Changed the return tuple from
`(hash, rows?)` to `(hash, rowCount, rows?)`.

### Piece C — cached `sqlite3_bind_parameter_count` in the stmt cache

The C-level prepared statement cache (see experiment 003) now stores
`int param_count` alongside the `sqlite3_stmt*`. Populated once at
`stmt_cache_insert` via `sqlite3_bind_parameter_count(stmt)` — a value
that never changes for a prepared SQL. `bind_params` takes
`param_count` as an argument instead of calling the FFI-internal
function on every bind.

```c
typedef struct {
    char* sql;
    sqlite3_stmt* stmt;
    int param_count;  // NEW
    // …
} resqlite_cached_stmt;
```

All call sites in `resqlite_stmt_acquire_writer`,
`resqlite_stmt_acquire_on`, `run_batch_locked`, and
`resqlite_query_bytes` now pass the cached value.

### Piece D — persistent `_readTablesBuf` for `getReadTables`

Same pattern as experiment 070's dirty-tables buffer: one
`calloc(64 * sizeof(Pointer<Utf8>))` at file scope, reused across every
subscription. Zero-table case short-circuits to `const <String>[]`.

```dart
final ffi.Pointer<ffi.Pointer<Utf8>> _readTablesBuf =
    calloc<ffi.Pointer<Utf8>>(64);

List<String> getReadTables(ffi.Pointer<ffi.Void> dbHandle, int readerId) {
  final count = resqliteGetReadTables(dbHandle, readerId, _readTablesBuf, 64);
  if (count == 0) return const <String>[];
  final tables = List<String>.filled(count, '', growable: false);
  for (var i = 0; i < count; i++) {
    tables[i] = _readTablesBuf[i].toDartString();
  }
  return tables;
}
```

## Benchmarks added

Three new benchmarks in `benchmark/suites/streaming.dart` target
the specific paths:

1. **No-Streams Write Throughput (200 inserts, no active streams)** —
   for Piece A. Writes into an isolated DB with no streams attached.
2. **Growing-Stream Invalidation (batch-insert 100 into 500-row stream)** —
   for Piece B. Each iteration adds 100 rows to a watched query, so the
   row-count short-circuit should fire on pass 1 of every re-query.
3. **Stream Subscription Rate (500 subscribe+cancel cycles)** —
   for Piece D. Tight loop of `db.stream(...).listen(...)` → `cancel()`
   to stress the `getReadTables` call site.

Piece C gets exercised by the existing **Single Inserts** and **Batched
Write Inside Transaction** benchmarks, which already stress the
`bind_params` path.

## Results

5-repeat A/B vs `origin/main`, same session (to defeat thermal drift):

### Wins on existing benchmarks

| Benchmark | Baseline (ms) | Experiment (ms) | Delta |
|---|---:|---:|---:|
| Streaming / Fan-out (10 streams) | 0.26 | 0.22 | **−15%** |
| Single Inserts (100 sequential) | 1.81 | 1.58 | **−13%** |
| Batched Write in Transaction (100 × 100 items) | 0.82 | 0.63 | **−23%** |
| Batched Write in Transaction (100 × 1000 items) | 7.04 | 5.99 | **−15%** |

The **−13% to −23% write wins are attributable to Piece C** — every
bind path now skips one FFI-internal call. The **Fan-out −15%** is
attributable to Piece A (streams register and fire invalidations in
tight succession; when the inverted index is briefly empty the
fast-reject avoids a microtask).

### New targeted benchmarks (within noise)

| Benchmark | Baseline (ms) | Experiment (ms) | Delta |
|---|---:|---:|---:|
| No-Streams Write Throughput (200 inserts) | 3.57 | 3.44 | −0.13 ms |
| Growing-Stream Invalidation (batch-insert 100 into 500-row stream) | 0.53 | 0.55 | +0.02 ms |
| Stream Subscription Rate (500 subscribe+cancel) | 6.66 | 7.41 | +0.75 ms (±26% noisy) |

Pieces B and D's per-call savings are below the measurement floor on
these targeted benchmarks. They're directionally consistent with the
hypothesis on the No-Streams Write benchmark; the subscription-rate
benchmark is too noisy to draw a conclusion either way.

### Overall

**8 wins, 0 regressions, 63 neutral** on the 71-benchmark suite
(5 repeats, stable-MAD comparison).

All 126 tests pass. Analyzer clean.

## Decision

**Accepted.** Piece C alone justifies the change — four double-digit-%
write wins from a five-line C patch. Pieces A, B, and D are
correctness-neutral improvements that encode the cheap-check-first
discipline for future maintainers.

## Related

- Experiment 003 (C-level stmt cache) — Piece C extends the cache
  entry.
- Experiment 045 (microtask coalescing) — Piece A gates its entry
  point.
- Experiment 070 (zero-row-change short-circuit + persistent dirty
  buffer) — Piece D is the reader-side mirror.
- Experiment 075 (native-buffered hash for `selectIfChanged`) —
  Piece B extends the hash pass.

## Baseline / experiment results

- Baseline: `benchmark/results/2026-04-16T22-34-27-077-080-baseline.md`
- Experiment: `benchmark/results/2026-04-16T22-45-20-077-080-exp-v2.md`
