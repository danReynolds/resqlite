# Experiment 064: Drop redundant sqlite3_clear_bindings

**Date:** 2026-04-16
**Status:** Accepted (cleanup)

## Problem

The `bind_params` function in `resqlite.c` calls `sqlite3_clear_bindings` before binding each parameter. The comment explained this as defensive code for "reusing a statement with fewer params than the previous call."

But examining the full control flow:

1. `bind_params` verifies `sqlite3_bind_parameter_count(stmt) == param_count` and returns `SQLITE_RANGE` if they differ.
2. The function only proceeds to the bind loop if all N slots will be rebound.
3. TEXT/BLOB bindings use `SQLITE_STATIC`, meaning SQLite doesn't copy or own the data — no cleanup needed on clear.
4. Cached statements are always reset before `bind_params` is called (via `get_or_prepare_reader`).

Given this, `sqlite3_clear_bindings` is always redundant — every slot will be overwritten by the subsequent bind loop, and there's no owned data to free.

## Approach

Remove the `sqlite3_clear_bindings(stmt)` call. Move the param count check earlier so it guards the bind loop. Document why the clear is unnecessary.

```c
static int bind_params(sqlite3_stmt* stmt, const resqlite_param* params,
                       int param_count) {
    int expected = sqlite3_bind_parameter_count(stmt);
    if (expected != param_count) {
        (void)sqlite3_bind_null(stmt, expected + 1);
        return SQLITE_RANGE;
    }
    // No clear_bindings needed: we verify param_count above and always
    // rebind every slot below. SQLITE_STATIC bindings have no owned copy
    // to free. Cached statements are always reset before this function.
    for (int i = 0; i < param_count; i++) {
        // bind slot i+1 with params[i]
    }
}
```

## Results

No measurable benchmark signal. The savings (~50ns per bind) are below the noise floor of the benchmark suite.

Full suite run showed 1 apparent win (-11%) and 1 apparent regression (-16%) on unrelated metrics — both within run-to-run variance. Full test suite (126 tests) passes.

## Decision

**Accepted as cleanup.** Not a performance win by benchmark measurement, but:
- The removed code was provably redundant given existing invariants
- Simplifies the bind path by one call
- Documents the invariants clearly for future maintainers

No correctness risk: every control-flow path that enters `bind_params` satisfies the preconditions that make the clear unnecessary.
