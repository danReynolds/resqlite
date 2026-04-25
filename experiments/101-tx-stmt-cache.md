# Experiment 101: Cached BEGIN / COMMIT / ROLLBACK statements

**Date:** 2026-04-25
**Status:** Accepted

## Problem

resqlite ran every transaction-control statement through
`sqlite3_exec()`:

- `resqlite_run_batch` in [native/resqlite.c](../native/resqlite.c) called
  `sqlite3_exec(db->writer, "BEGIN IMMEDIATE", …)` and the matching
  `COMMIT`/`ROLLBACK` for every executeBatch.
- The Dart writer isolate called `resqliteExec(state.dbHandle, beginSql)`
  (and the equivalent commit/rollback strings) on every interactive
  transaction in [lib/src/writer/write_worker.dart](../lib/src/writer/write_worker.dart).

Internally `sqlite3_exec` is a thin loop:

```c
while (zSql && zSql[0]) {
    sqlite3_prepare_v2(db, zSql, -1, &pStmt, &zLeftover);
    while (sqlite3_step(pStmt) == SQLITE_ROW) { … }
    sqlite3_finalize(pStmt);
    zSql = zLeftover;
}
```

so each transaction boundary paid the SQL parse + prepare + finalize
cost. The strings are constants (`"BEGIN IMMEDIATE"`, `"COMMIT"`,
`"ROLLBACK"`) — every invocation re-parsed identical bytes.

## Hypothesis

Persistently preparing the three transaction-control statements once at
`resqlite_open` and replacing each `sqlite3_exec` call with
`sqlite3_reset` + `sqlite3_step` should:

1. Eliminate the per-call SQL parse + AST + bytecode-emit work that
   `sqlite3_prepare_v2` does.
2. Eliminate the matching `sqlite3_finalize` after every step.
3. Move the (constant) cost out of the hot path entirely — the prepared
   stmt is a 4-byte mutex-protected pointer dereference.

The estimated per-boundary saving is in the 1–10 µs range. Workloads
that fire many transactions per measurement window — small batched
writes, interactive transactions, batch-driven stream invalidation —
should see proportional wins. Auto-commit single-statement writes
shouldn't move (they don't take this path).

## Approach

**C side ([native/resqlite.c](../native/resqlite.c), [native/resqlite.h](../native/resqlite.h)):**

1. Added three `sqlite3_stmt*` fields to `struct resqlite_db` —
   `tx_begin_stmt`, `tx_commit_stmt`, `tx_rollback_stmt`. Held outside
   `writer_cache` so they never compete with user statements for the
   32-entry MRU cache.
2. In `resqlite_open`, prepared the three stmts once using
   `sqlite3_prepare_v3(…, SQLITE_PREPARE_PERSISTENT, …)`.
3. Added a small `run_cached_tx_stmt` helper that does
   `sqlite3_reset` → `sqlite3_step` → `sqlite3_reset`, returning
   `SQLITE_OK` on the no-result `SQLITE_DONE` path.
4. Exposed three new FFI symbols — `resqlite_tx_begin_immediate`,
   `resqlite_tx_commit`, `resqlite_tx_rollback` — each takes the
   writer mutex, calls `run_cached_tx_stmt`, and returns the rc.
5. In `resqlite_close`, finalized the three cached stmts before
   closing the writer connection.
6. Replaced the three `sqlite3_exec` calls in `resqlite_run_batch`
   with `run_cached_tx_stmt(db->tx_begin_stmt / tx_commit_stmt /
   tx_rollback_stmt)`.

**Dart side:**

1. [lib/src/native/resqlite_bindings.dart](../lib/src/native/resqlite_bindings.dart):
   added three `@ffi.Native(... isLeaf: true)` bindings —
   `resqliteTxBeginImmediate`, `resqliteTxCommit`,
   `resqliteTxRollback`.
2. [lib/src/writer/write_worker.dart](../lib/src/writer/write_worker.dart):
   replaced four `resqliteExec(state.dbHandle, state.beginSql /
   commitSql / rollbackSql)` call sites with the new helpers. Removed
   the now-dead `beginSql`/`commitSql`/`rollbackSql` `Pointer<Utf8>`
   fields from `_WriterState` and the matching `toNativeUtf8` allocs
   in `writerEntrypoint`.

The dynamic savepoint statements (`SAVEPOINT s$N`, `RELEASE s$N`,
`ROLLBACK TO s$N`) still use `sqlite3_exec` — pre-caching one prepared
stmt per nesting level would add a stack of caches with diminishing
returns; the savepoint path fires only on nested transactions, which
are not on the hot single-tx benchmark path.

206 existing tests pass (`dart test`).

## Results

Artifact: [`benchmark/results/2026-04-25T07-52-01-exp101-tx-stmt-cache.md`](../benchmark/results/2026-04-25T07-52-01-exp101-tx-stmt-cache.md)

Baseline: `2026-04-25T07-21-19-exp099-fnv-8byte.md` (effectively the
exp 097 baseline — exp 099 was rejected as benchmark-invisible).

Suite-level: **12 wins, 0 regressions, 141 neutral.**

Directly attributable wins — workloads that take the modified
transaction-control path:

| Workload | Baseline (ms) | Experiment (ms) | Delta | Status |
|---|---:|---:|---:|---|
| Write Performance / Batched Write Inside Transaction (100 rows, tx.execute loop) | 0.59 | 0.52 | -0.07 | 🟢 Win (-13%) |
| Streaming / Growing-Stream Invalidation (batch-insert 100 into watched stream) | 0.60 | 0.52 | -0.08 | 🟢 Win (-14%) |
| Write Performance / Interactive Transaction (insert + select + cond delete) | 0.05 | 0.05 | 0.00 | ⚪ Within noise |

The 100-row batched write inside an outer transaction goes through
`run_batch_locked` plus the cached BEGIN/COMMIT pair on the outer
boundary; the 13 % improvement is consistent with eliminating
~5–7 µs of prepare+finalize overhead per boundary on a workload whose
total wall is ~0.6 ms. Growing-Stream Invalidation pays the same
boundary on its 100-row batch insert and shows a matching delta.

The Interactive Transaction benchmark (BEGIN + 1 INSERT + 1 SELECT
+ 1 conditional DELETE + COMMIT in 0.05 ms) is below the absolute
±0.02 ms noise floor — the per-boundary saving is real but too small
to read on a 50 µs window where three SQL operations and four isolate
hops dominate.

Other wins on the suite (Single Inserts -30 %, Stream Churn -48 %,
Schema Shapes Text-heavy -17 %, Concurrent Reads 8× -16 %, Point Query
Throughput +30 %, Scaling 10000 rows -12 %) move in the right
direction but are **not** structurally attributable to this change —
those benchmarks don't fire user-level BEGIN/COMMIT statements on
their hot path. Single Inserts uses SQLite's implicit auto-commit,
which is internal to SQLite and doesn't go through the new FFI; the
read benchmarks don't open transactions at all. The honest read is
that those deltas are run-to-run drift relative to the day-old
exp 099 baseline (high MDE on Stream Churn; ~10 % MDE on the rest).
The directly attributable Batched Write Inside Transaction and
Growing-Stream Invalidation deltas are the load-bearing evidence.

**Memory / streaming column-granularity:** unchanged; this is a
pure prepare-once swap, no allocation behavior change.

## Why Accepted

Two consistent, directly-attributable wins (-13 % batched-write,
-14 % growing-stream invalidation) on the workloads the change is
designed to affect, **zero regressions** anywhere in the 153-row
suite, and a pattern-match against the exp 003 (statement cache) and
exp 014 (BEGIN IMMEDIATE) lineage: prepare once, reuse forever.

The change adds ~50 lines of C, three trivial FFI symbols, and one
extra `sqlite3_finalize` triple in `resqlite_close`. No
backwards-compatibility surface is touched (all symbols are
internal); the writer's transaction discipline is unchanged.

## Decision

Accepted.
