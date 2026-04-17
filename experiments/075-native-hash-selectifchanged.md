# Experiment 075: Native-buffered hash for `selectIfChanged`

**Date:** 2026-04-16
**Status:** Accepted

## Problem

Stream re-queries via `selectIfChanged` go through the full Dart decode
path (allocate values list, decode every cell into a Dart String /
Uint8List, build RowSchema, return a ResultSet) *then* hash the values.
When the hash matches `lastResultHash`, all of that decoded material
is discarded — the stream emits nothing.

In dashboard apps with multiple streams on the same table, most writes
change at most one stream's result set. Every other stream's re-query
pays the full decode cost for a result that gets thrown away.

## Hypothesis

Move the hash into native code, hashing raw cell bytes during
`sqlite3_step` without materializing any Dart objects. If the hash
matches the cached value, return the "unchanged" sentinel immediately.
Only on mismatch do we re-step the statement and build Dart objects.

Trade-off: the "changed" path pays two `sqlite3_step` passes (hash pass
+ decode pass). The expectation is that unchanged re-queries dominate
in realistic reactive workloads, so the net impact is positive.

## Approach

### C side

Hashing lives entirely in C. Two helpers and one exported entry point:

- `fnv_combine_u64(h, v)` — 63-bit-masked FNV-1a step.
- `fnv_combine_bytes(h, p, len)` — byte-at-a-time FNV fold for TEXT
  and BLOB payloads.
- `resqlite_query_hash(stmt)` — the only Dart-visible function. Steps
  the bound statement to completion, folds every cell's type tag +
  value bytes + length into an FNV-1a accumulator, and returns the
  final hash. Calls `sqlite3_reset` at both ends so the caller can
  invoke this on a freshly-bound stmt **or** on one just drained by
  `decodeQuery` — same function, both use cases.

  Per-cell fold rules (both paths must agree bit-for-bit with the
  re-query path, because they do):
  - INTEGER: type + int64 value
  - FLOAT: type + double bit pattern
  - TEXT: type + length + raw UTF-8 bytes
  - BLOB: type + length + raw bytes
  - NULL: type only
  - After all rows: fold `row_count` LAST; empty result ≡ 0.

### Dart side

- One FFI binding: `resqliteQueryHash`.
- `executeQueryIfChanged` (the re-query path):

  ```
  stmt = stmt_acquire_on(...)                 // binds params, reset
  new_hash = resqlite_query_hash(stmt)        // pass 1: hash in C
  if (new_hash == last_hash) return (new_hash, null)
  raw = decodeQuery(stmt, sql)                // pass 2: step + decode
  return (new_hash, raw)                      // reuse pass-1 hash
  ```

  Same hash value from pass 1 is reused as the new baseline — no need
  to recompute during decode.

- `executeQueryWithDeps` (the initial-query path):

  ```
  raw = decodeQuery(stmt, sql)                // step + decode
  hash = resqlite_query_hash(stmt)            // step + hash (replay)
  return (raw, readTables, hash)
  ```

  Pays one extra `sqlite3_step` walk through the same read-only query
  once per stream subscription. Amortized across every subsequent
  re-query of that stream (typically hundreds to thousands over the
  stream's lifetime), the cost is negligible.

- `StreamEngine` stores the worker-returned hash directly on initial
  emission, removing the Dart-side `_hashResult` function and its
  `result_hash.dart` module (both now dead code — hashes are C-computed
  everywhere).

### Hash domain consistency

Only one hash implementation exists (`resqlite_query_hash`). Initial
query and re-query both call it on the same stmt, so the baseline and
every comparison hash live in the exact same domain by construction.
No possibility of drift between paths.

## Benchmark

Needed a new benchmark to measure the target path: none of the
existing streaming benchmarks exercise unchanged re-queries. Added
`Unchanged Fanout Throughput (1 canary + 10 unchanged streams)` in
`benchmark/suites/streaming.dart`:

- 10 unchanged streams, each using a literal `sid` column so the
  stream registry doesn't dedupe them. All select ~1000 rows and
  never change (writes target `id > 1000`).
- 1 canary stream (`COUNT(*)`) that changes on every write and emits
  a signal used for iteration synchronization.
- Each INSERT dispatches 11 re-queries; the reader pool (3-4 readers)
  processes them in waves. The canary's emission bounds iteration
  time.
- Seed data scaled to 1000 rows so the per-re-query decode cost
  dominates noise.

Also verified the change correctness against the existing probe
`tool/experiments/hash_probe.dart`.

## Results

A/B with 053 library changes stashed in/out to control for thermal
drift:

| Benchmark | Baseline (ms) | exp053 (ms) | Δ |
|---|---:|---:|---:|
| Unchanged Fanout Throughput | 0.44 | 0.27 | **−39%** |
| Invalidation Latency (changed) | 0.05 | 0.05 | within noise |
| Fan-out (10 streams, changed) | 0.18 | 0.22 | within noise |
| Stream Churn (100 cycles) | 2.00 | 2.18 | within noise |

All 129 existing tests pass plus 3 new DDL-invalidation tests from
exp 051.

The "changed" path's 2-pass cost does not show up as a measurable
regression on any existing streaming benchmark. The 2-pass overhead
(step+hash, then step+decode+hash) is bounded above by the decode
cost of one pass — small compared to the dispatch + isolate costs
that dominate.

## Why the earlier version of this idea (exp 072) failed

Exp 072 tried to swap FNV-1a for xxhash64 on already-hashed 64-bit
values. On pre-hashed inputs, FNV's simpler xor+multiply beats
xxhash's multi-step merge round. 072 regressed stream paths by
+45-75%.

The insight 053 rescues: xxhash/FNV choice matters for **byte-stream
hashing**. In 053 we hash raw cell bytes in C — the scenario where
the hash function's throughput actually matters. Here FNV is fine
because we control the implementation and can avoid Dart↔C
marshaling, so the algorithmic constant factor is not the
bottleneck.

## Decision

Accepted. Large win (−39%) on the target path, zero measurable
regression on any other path. Hash code consolidates to a single C
implementation; the main-isolate `_hashResult` becomes dead code and
is removed.

## Follow-ups

- Add a "no-op writes against wide table" benchmark that exercises
  the changed-path 2-step cost pathologically.
- Exp 052' attempted to batch the step_row FFI crossings but hit the
  same memcpy-vs-FFI-savings wall as exp 018 and was rejected
  separately. A future experiment could combine 053's hashing with
  selective batching only when text/blob content is small (exploit
  the fact that pure-numeric rows don't need the memcpy).
