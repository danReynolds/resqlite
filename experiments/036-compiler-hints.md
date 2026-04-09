# Experiment 036: Compiler Hints (Dart + C)

**Date:** 2026-04-09
**Status:** Accepted

## Changes

**Dart:**
- `@pragma('vm:prefer-inline')` on `_fastDecodeText` (hot text decode path)

**C:**
- `__attribute__((hot))` on 6 hot functions: `buf_write`, `buf_ensure`,
  `json_write_string`, `write_json_to_buf`, `resqlite_step_row`, `fast_i64_to_str`
- `__restrict` on `buf_write` and `json_write_string` parameters
- `__builtin_expect` on `buf_ensure` capacity check (likely) and
  `resqlite_step_row` exit check (unlikely)

## Results

No isolated signal — these are compiler optimization hints that affect code
generation quality. The Dart pragma primarily helps AOT (Flutter release builds)
rather than JIT benchmarks.

## Decision

**Accepted** — zero-risk annotations. No behavioral changes. The `__restrict`
qualifier helps the C compiler eliminate redundant loads in the JSON buffer
write path. The `__builtin_expect` hints align branch prediction with the
actual hot path (buffer has capacity, step returns SQLITE_ROW).
