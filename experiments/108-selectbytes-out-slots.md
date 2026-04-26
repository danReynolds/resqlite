# Experiment 108: Persistent selectBytes out-parameter slots

**Date:** 2026-04-26
**Status:** Rejected
**Archive:** [`archive/exp-108`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-108)

## Problem

`queryBytes()` allocates two tiny native out-parameter boxes on every
`selectBytes()` call:

```dart
final pBuf = calloc<Pointer<Uint8>>();
final pLen = calloc<Int>();
```

The C side writes the JSON buffer pointer and length into those slots. The
buffer itself is owned by the reader connection and must not be freed by Dart,
but the two out-parameter boxes are pure Dart FFI overhead.

Recent experiments made this worth checking, but also set a high bar:

- Exp 070 accepted a zero-row short-circuit plus persistent dirty buffer.
- Exp 095 rejected a persistent writer result buffer because the removable
  16-byte allocation pair did not produce reliable write-path wins.
- Exp 102 rejected cached savepoint strings because the affected path had no
  directly attributable benchmark signal.

This experiment tests whether the `selectBytes()` path is different enough to
justify the same persistent-scratch pattern.

## Research Notes

Online review before implementing did not identify a new low-risk external
primitive that should supersede this path:

- Dart 3.11 is tooling-focused and has no new language updates, so there is no
  new isolate/FFI feature to exploit directly:
  <https://dart.dev/blog/announcing-dart-3-11>.
- `sqlite_async` remains the most relevant Dart peer: async by default,
  WAL-backed concurrent reads and writes, and direct SQL access:
  <https://pub.dev/packages/sqlite_async>. That matches resqlite's current
  benchmark comparison shape rather than suggesting a new API.
- Node's `node:sqlite` added `SQLTagStore`, an LRU prepared-statement cache
  keyed by SQL template text:
  <https://nodejs.org/api/sqlite.html#class-sqltagstore>. Resqlite already
  has C-level statement caches, and exp 071 showed cache lookup tweaks are
  invisible with the current small-SQL benchmark mix.
- SQLite 3.53.0 added planner and C API work, including carray-related API
  changes and floating-point conversion changes:
  <https://sqlite.org/releaselog/3_53_0.html>. Resqlite currently vendors
  sqlite3mc 2.3.2 / SQLite 3.51.3.
- SQLite's built-in `carray()` can bind C arrays into SQL queries when compiled
  with `SQLITE_ENABLE_CARRAY`, but it introduces array-parameter semantics and
  special binding ownership rules:
  <https://www.sqlite.org/carray.html>. That is a possible future API decision,
  not a transparent performance optimization under the current lean API.

Given those constraints, the smallest viable no-API experiment was to remove
the remaining per-call native out-parameter allocation in `queryBytes()`.

## Hypothesis

A pair of per-isolate scratch slots:

```dart
final Pointer<Pointer<Uint8>> _queryBytesOutBuf = calloc<Pointer<Uint8>>();
final Pointer<Int> _queryBytesOutLen = calloc<Int>();
```

should be reusable for every reader-worker `selectBytes()` call because reader
workers process one request at a time. The C function writes the result pointer
and length synchronously before returning, so the Dart helper can copy the two
slot values into the returned record immediately.

Expected upside: remove two `calloc` calls and two `calloc.free` calls per
`selectBytes()` query, with no public API change.

Expected risk: introduce permanent native scratch state and rely on the current
single-message-at-a-time reader-worker execution model.

## Approach

Changed `lib/src/native/resqlite_bindings.dart` so `queryBytes()` reused two
top-level scratch pointers instead of allocating out-parameter boxes per call.
The slots were reset to `nullptr` and `0` before each native call:

```dart
_queryBytesOutBuf.value = nullptr;
_queryBytesOutLen.value = 0;
```

The query result still pointed at the reader's persistent C-owned JSON buffer;
only the out-parameter boxes changed ownership/lifetime.

Validation before benchmarking:

```text
dart analyze lib/src/native/resqlite_bindings.dart lib/src/reader/read_worker.dart test/reader_pool_test.dart test/database_test.dart
dart test test/reader_pool_test.dart test/database_test.dart
```

Both passed.

## Results

Artifacts:

- [`benchmark/results/2026-04-26T06-40-07-exp108-selectbytes-out-slots.md`](../benchmark/results/2026-04-26T06-40-07-exp108-selectbytes-out-slots.md)
- [`benchmark/results/2026-04-26T06-40-07-exp108-selectbytes-out-slots.json`](../benchmark/results/2026-04-26T06-40-07-exp108-selectbytes-out-slots.json)

Baseline: `benchmark/results/2026-04-25T07-52-01-exp101-tx-stmt-cache.md`.

Command:

```text
dart run benchmark/run_release.dart exp108-selectbytes-out-slots --repeat=5 --compare-to=benchmark/results/2026-04-25T07-52-01-exp101-tx-stmt-cache.md
```

Suite-level: **5 wins, 8 regressions, 140 neutral.**

The wins were unrelated to the modified path (`Point Query Throughput`, stream
churn, and one transaction-loop write case). The regressions were also not
structurally attributable to `selectBytes()` out-parameter slots, but they
remove any argument for carrying extra native lifetime state when the target
path is neutral.

Target `selectBytes()` rows:

| Benchmark | Baseline ms | Current ms | Delta | Threshold | Decision |
|---|---:|---:|---:|---:|---|
| Select JSON Bytes / 10 rows / `resqlite selectBytes()` | 0.01 | 0.01 | +0.00 | +/-0.02 ms | Within noise |
| Select JSON Bytes / 100 rows / `resqlite selectBytes()` | 0.04 | 0.04 | +0.00 | +/-0.02 ms | Within noise |
| Select JSON Bytes / 1000 rows / `resqlite selectBytes()` | 0.36 | 0.36 | -0.01 | +/-0.04 ms | Within noise |
| Select JSON Bytes / 10000 rows / `resqlite selectBytes()` | 4.01 | 3.85 | -0.16 | +/-0.46 ms | Within noise |
| Scaling / 500 rows / `resqlite selectBytes()` | 0.18 | 0.18 | +0.00 | +/-0.02 ms | Within noise |
| Scaling / 5000 rows / `resqlite selectBytes()` | 1.81 | 1.81 | -0.00 | +/-0.31 ms | Within noise |
| Scaling / 20000 rows / `resqlite selectBytes()` | 8.68 | 8.11 | -0.57 | +/-2.19 ms | Within noise |

Memory comparison reported **2 wins, 2 regressions, 11 neutral**, including a
flagged RSS regression on `Memory / Select 10k rows -> JSON Bytes / resqlite
selectBytes()` (+6.00 MB, MDE +/-3.01 MB). The RSS harness is conservative and
the VM retains heap pages, but a memory flag on the target path is enough to
rule out the experiment when wall-clock results are neutral.

## Decision

Rejected.

The implementation is correct and passed tests, but the benchmark signal is
neutral exactly where the change should have helped. Keeping permanent native
scratch slots would add lifetime/concurrency assumptions to the hot binding
file for a savings ceiling that the release suite cannot measure.

This pattern-matches exp 095: a theoretically removable tiny allocation pair
is not automatically worth carrying. The implementation is archived under
`archive/exp-108` for future comparison if a focused allocator-profile harness
ever shows this call site as material.

Follow-up ideas:

- Add a focused `selectBytes()` microbenchmark/profile mode before trying more
  sub-microsecond allocation removals on this path.
- Revisit SQLite carray only if resqlite decides to expose array parameters; it
  is not compatible with the current no-new-read/write-API scope.
- Re-check sqlite3mc once a newer stable release beyond SQLite 3.53.0 has aged
  enough and contains planner or conversion changes relevant to resqlite's
  benchmark mix.
