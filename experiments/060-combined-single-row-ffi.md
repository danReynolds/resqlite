# Experiment 060: Combined single-row FFI call

**Date:** 2026-04-16
**Status:** Rejected (blocked by text pointer lifetime; predecessor of 063)

## Problem

Point queries (`SELECT * WHERE id = ?`) cross the FFI boundary four times:

1. `resqlite_stmt_acquire_on` — acquire + bind
2. `sqlite3_column_count` — get column count
3. `resqlite_step_row` returning SQLITE_ROW
4. `resqlite_step_row` returning SQLITE_DONE

Combining these into one FFI call could eliminate 3 crossings per query.

## Hypothesis

A single `resqlite_query_single_row` function that acquires, binds, steps once, reads cells, and resets — all in one C function call.

## Approach

Added function to `resqlite.c`:

```c
int resqlite_query_single_row(
    resqlite_db* db, int reader_id,
    const char* sql,
    const resqlite_param* params, int param_count,
    resqlite_cell* cells
);
```

Does acquire + bind + step + fill cells + reset in one call. Returns col_count on success, 0 if no rows, -1 on error.

## Why It Failed

After `sqlite3_reset`, the text pointers returned by `sqlite3_column_text` are **invalidated**. The combined function resets the statement before returning, so by the time Dart tries to read text data via the cell's `p` pointer, it points to freed SQLite memory.

This is a fundamental constraint of SQLite's zero-copy text model: `sqlite3_column_text` returns a pointer into the statement's internal buffer, valid only until the next step/reset/finalize.

```
Timeline:
  [FFI enter]
  acquire + bind + step → SQLITE_ROW
  fill cells: cells[i].p = sqlite3_column_text(...)  // pointer into SQLite buffer
  reset stmt                                          // INVALIDATES pointers
  [FFI return]
  Dart reads cells[i].p → reads freed memory
```

## Decision

**Rejected as designed**, but the idea evolved into experiment 063 which added inline text/blob copy before the reset, storing offsets (not pointers) in the cell buffer. That worked — 063 showed 28-48% point query improvement. This failed attempt directly led to the successful 063 design.

**Key lesson:** any "combined FFI" function that resets the statement must copy text/blob data out before the reset. Raw pointers don't survive reset.
