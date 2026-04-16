# Experiment 066: Transparent single-row fast path in select()

**Date:** 2026-04-16
**Status:** Rejected (insufficient transparent headroom)

## Problem

Experiment 063 added a `selectOne(sql, params)` API that was 28-48% faster than `select()` for point queries. User feedback: the API-surface cost wasn't worth it, but the methodology was sound. Could we capture the same wins **transparently inside `select()`** — so consumers see the speedup without any API change?

## Hypothesis

Detect the single-row case automatically. Combine acquire + bind + first step + "peek next step" into a single FFI call that reports:
- 0: no rows (stmt reset)
- 1: exactly one row (data inline-copied into buffer, stmt reset)
- 2: multiple rows (row 1 inline-copied, stmt left in row-2 state for caller to continue)

On return, decode row 1 from the buffer; if probe=1, return immediately; if probe=2, read row 2 and continue stepping normally.

## Approach

Added C functions:
- `resqlite_select_probe(...)` — combined acquire + step + peek + conditionally-reset
- `resqlite_fill_cells(stmt, col_count, cells)` — read current row's cells without stepping (needed for row 2 in the multi-row case)

Added Dart `decodeQueryFast` in `query_decoder.dart` that tries the probe path when the schema is cached, falling back to the existing `decodeQuery` otherwise. Wired into `_executeQueryImpl` before the normal acquire+decode path.

Critically: **no API change**. `select()` signature unchanged. Users get the speedup for free on subsequent queries of each SQL (first call warms the schema cache).

## Results

Measurements showed essentially no improvement over baseline — within thermal noise:

| Configuration | Median QPS (20-trial median) |
|---|---:|
| Main (cold) | 148,225 |
| Round 4 + 066 | 139,063 |
| Main (warm) | 114,449 |

The back-to-back variation between consecutive runs (~30%) is larger than any measurable effect from the change.

## Why the Transparent Path Has Limited Headroom

Decomposing experiment 063's 28-48% win shows three sources:

1. **Returning `Map` directly** instead of `List<Map>` — avoids wrapper allocation, simpler isolate transfer payload
2. **Skipping the `RawQueryResult` / `ResultSet` wrappers** — multi-row machinery that's dead weight for single rows
3. **Right-sized values allocation** (colCount slots, not colCount × 256)

**Sources 1 and 2 are fundamentally API-shape changes.** The transparent path must return `List<Map<String, Object?>>` to preserve the `select()` contract, so it can't skip the list wrapper or `ResultSet`. These contribute the bulk of 063's win.

Source 3 is the only piece available to the transparent path — and experiment 067 showed that shrinking the initial allocation actually **regresses** performance because Dart's VM has a fast path for `List<Object?>.filled` that bypasses the bump allocator in some cases.

That leaves the transparent path with maybe 2-5% theoretical improvement from saved FFI crossings, which is below the benchmark noise floor.

## Additional Issue: Per-Call Allocation Overhead

First implementation allocated the probe function's out-pointers (`outColCount`, `outStmt`) per call via `calloc<Int32>()` / `calloc<Pointer<Void>>()`. This added 2 native mallocs + 2 frees per query — roughly 200-800ns of overhead, wiping out the FFI savings.

Fixing this required per-worker persistent out-pointers. Even with the fix, the measured improvement remained within noise.

## Decision

**Rejected.** The transparent constraint fundamentally limits the achievable gain. The bulk of 063's improvement comes from API-shape changes that can't be replicated transparently. The remaining FFI-crossing savings are too small to clear the benchmark noise floor.

**Lesson:** Not every optimization that works in a specialized API can be retrofit transparently. The `select()` contract — returning `List<Map<String, Object?>>` — is itself a performance ceiling for single-row queries. Breaking that ceiling requires either a new API (063) or a different benchmark that measures a different thing (e.g., memory or GC pressure, where columnar would win).

## Related Experiments

- 060 — earlier attempt at combined single-row FFI, failed on text pointer lifetime
- 063 — successful explicit API for the same optimization (rejected for API-surface reasons)
- 067 — attempted to capture just the "right-sized allocation" piece transparently; regressed
