# Experiment 102: Cached SAVEPOINT / RELEASE / ROLLBACK TO strings

**Date:** 2026-04-25
**Status:** Rejected

## Problem

Exp 101 cached the three transaction-control statements
(`BEGIN IMMEDIATE`, `COMMIT`, `ROLLBACK`) as persistent prepared
stmts, but it explicitly excluded the dynamic savepoint statements:

```dart
// _handleBegin
final sp = 'SAVEPOINT s${state.txDepth}'.toNativeUtf8();
try {
  resqliteExec(state.dbHandle, sp);
} finally {
  calloc.free(sp);
}

// _handleCommit / _handleRollback (nested branch)
final rollbackSp = 'ROLLBACK TO s$newDepth'.toNativeUtf8();
final releaseSp  = 'RELEASE s$newDepth'.toNativeUtf8();
resqliteExec(state.dbHandle, rollbackSp);
resqliteExec(state.dbHandle, releaseSp);
calloc.free(rollbackSp);
calloc.free(releaseSp);
```

Exp 101 noted: *"Pre-caching one prepared stmt per nesting level
would add a stack of caches with diminishing returns; the savepoint
path fires only on nested transactions, which are not on the hot
single-tx benchmark path."*

This experiment tests whether even the **string-side** caching —
keeping the `'SAVEPOINT sN'.toNativeUtf8()` allocations alive across
calls — moves anything measurable.

## Hypothesis

A per-depth `List<Pointer<Utf8>>` on `_WriterState` that grows
lazily should let nested transactions reuse the native UTF-8 bytes
without re-encoding + reallocating on every BEGIN/COMMIT/ROLLBACK
boundary. Each unique depth pays one `toNativeUtf8` once at first
use, then every subsequent visit at that depth is a list lookup.
Total native footprint: `~12 × maxDepth` bytes (typically ≤ 5
levels in practice, so ~60 bytes for the writer's lifetime).

## Approach

Added three lazy-growing pointer caches to `_WriterState`:

```dart
final List<ffi.Pointer<Utf8>> _savepointEnter = [];
final List<ffi.Pointer<Utf8>> _savepointRelease = [];
final List<ffi.Pointer<Utf8>> _savepointRollbackTo = [];

ffi.Pointer<Utf8> savepointEnter(int depth) =>
    _cachedSavepoint(_savepointEnter, depth, 'SAVEPOINT s');
// + savepointRelease, savepointRollbackTo

static ffi.Pointer<Utf8> _cachedSavepoint(
  List<ffi.Pointer<Utf8>> cache,
  int depth,
  String prefix,
) {
  while (cache.length <= depth) {
    cache.add('$prefix${cache.length}'.toNativeUtf8());
  }
  return cache[depth];
}
```

Replaced the six `'…'.toNativeUtf8()` + `calloc.free` call sites in
`_handleBegin`, `_handleCommit`, and `_handleRollback` with the new
helpers. The cached pointers persist for the writer isolate's
lifetime — when the isolate dies the OS reclaims the pages, no
explicit teardown needed.

206 existing tests pass.

## Results

Artifacts:

- [`benchmark/results/2026-04-25T08-41-54-exp102-savepoint-cache.md`](../benchmark/results/2026-04-25T08-41-54-exp102-savepoint-cache.md)
- [`benchmark/results/2026-04-25T08-41-54-exp102-savepoint-cache.json`](../benchmark/results/2026-04-25T08-41-54-exp102-savepoint-cache.json)

Baseline: `2026-04-25T07-52-01-exp101-tx-stmt-cache.md`.

Suite-level: **6 wins, 0 regressions, 147 neutral.**

The 6 wins are on workloads that **don't fire user-level
SAVEPOINT/RELEASE statements at all** — Concurrent Reads (no
transaction boundary), Stream Fan-out (10 streams, single-level
hash-comparison setup), Stream Churn (subscription churn, no nested
tx). All run-to-run drift relative to the same-day exp 101
baseline; pattern matches the "background variance on read paths"
class of suite movement.

The benchmark suite has **no nested-transaction workload**. The
single Interactive Transaction benchmark uses a top-level
BEGIN/COMMIT only, which goes through exp 101's cached prepared
stmts and never hits the savepoint code path.

That leaves no directly attributable signal: the modified branch
isn't covered by the suite, and the suite-level drift goes the
right way but isn't structurally pointing at this change.

## Decision

Rejected.

The allocation is theoretically removable, but with no
nested-transaction benchmark in the suite there is no signal to
justify adding state to `_WriterState` (3 List fields, 4 helper
methods). The savepoint path fires only when the caller composes
nested `transaction()` blocks — a real but rare pattern that the
release-mode comparison can't see.

If a future benchmark adds a deeply-nested transaction workload and
shows the savepoint allocations as a measurable cost, the
implementation pattern is documented above for cherry-pick. Until
then this stays out — pattern-matches exp 095's "theoretically
removable, practically below noise" rejection.

This pairs with exp 101 to leave the entire transaction-control
path either persistently prepared (BEGIN/COMMIT/ROLLBACK at depth
0) or honestly out-of-scope-for-the-suite (savepoints at depth 1+).
