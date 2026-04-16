# Experiment 070: Zero-row-change commit short-circuit + persistent dirty buffer

**Date:** 2026-04-16
**Status:** Accepted (cleanup + minor allocation elimination)

## Problem

Every write went through `getDirtyTables(dbHandle)`, which:

1. Allocated a fresh `calloc(64 * 8 = 512 bytes)` buffer for C out-pointers
2. Made an FFI call to `resqlite_get_dirty_tables`
3. Allocated a new `<String>[]` and populated it with the returned table names
4. Freed the 512-byte buffer

On writes where the preupdate hook didn't fire (no-op UPDATEs, DDL without
row changes) the function returned 0 and we still paid for all four steps.

## Approach

Two changes, both zero-risk:

### 1. Persistent FFI out-buffer per worker

Allocate the 512-byte `Pointer<Pointer<Utf8>>` buffer **once** (file-level
`final`) and reuse it across every call. Eliminates the
`calloc(512)` / `calloc.free` pair on every single write.

### 2. Empty-set short-circuit

When `resqlite_get_dirty_tables` returns `count == 0`, return
`const <String>[]` immediately. Skips the `List<String>.filled` allocation
for the common no-dirty-table case (rare in row-touching writes, frequent
for DDL-only transactions and the commit-after-rollback cleanup paths that
drain the dirty set).

Also changed the populated-case allocation from `<String>[].add()` to
`List<String>.filled(count, '')..[i] = ...`, avoiding growth reallocs.

## Results

**0 wins, 0 regressions on the 63-benchmark suite** (5 repeats vs baseline).

The per-write savings (~200-400ns: one calloc/free pair + the occasional
list allocation) are below the benchmark noise floor. The change is
accepted as a quality improvement, not a performance win:

- Removes per-write heap churn (one less allocation pair)
- Simplifies the happy path (no `try/finally` wrapper)
- Tightens the unchanged-set case to a const return

All 128 tests pass.

## Decision

**Accepted as cleanup.** The code is strictly simpler and marginally less
allocation-heavy. Not a measurable win on its own; pairs with experiment
068 (the DDL watchdog) which also called `getDirtyTables` on each commit —
this reduces the shared cost of both.

## Related

- Experiment 035 (cell buffer reuse) — same pattern applied to the reader
  cell buffer
- Experiment 037 (persistent JSON buffer) — same pattern for C-side output
- Experiment 068 (DDL watchdog) — companion change that increased the
  frequency of `getDirtyTables` calls; this offsets the added cost.
