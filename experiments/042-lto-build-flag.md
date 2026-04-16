# Experiment 042: Link-Time Optimization (LTO)

**Date:** 2026-04-15
**Status:** Rejected

## Problem

The SQLite amalgamation and `resqlite.c` are compiled as separate translation units. The compiler cannot inline `sqlite3_column_int64`, `sqlite3_column_text`, `sqlite3_column_double`, etc. across the boundary into `resqlite_step_row`'s tight inner loop. Each call requires a function call/return with associated overhead.

## Hypothesis

Adding `-flto` to the build flags enables the linker to perform whole-program optimization, inlining hot SQLite functions into the resqlite query paths. This should benefit the per-cell decode loop most (the objects path), since it makes many small FFI-like calls per row.

## Approach

Single-line change in `hook/build.dart`:

```dart
flags: [
  '-flto', // LTO: enable link-time optimization for cross-unit inlining.
  ...
],
```

The `native_toolchain_c` package already uses `-O3` by default.

## Results

### Round 1: `-flto` alone

**17 wins, 2 regressions** (3 repeats vs baseline).

| Benchmark | Baseline (ms) | LTO (ms) | Delta | Status |
|---|---|---|---|---|
| Point query (qps) | 60,161 | 119,417 | +98% | Win |
| Parameterized queries | 15.89 | 14.00 | -12% | Win |
| Text-heavy schema | 0.67 | 0.57 | -15% | Win |
| Transaction read 1000 | 0.20 | 0.17 | -15% | Win |
| **selectBytes 1000 rows** | **0.51** | **0.58** | **+14%** | **Regression** |
| **selectBytes 10000 rows** | **5.70** | **6.62** | **+16%** | **Regression** |

LTO helps the objects path but hurts the bytes/JSON path — likely icache pressure from inlining sqlite3_column_* into the already-large `write_json_to_buf`.

### Round 2: `-flto` + `__attribute__((noinline))` on `write_json_to_buf`

**15 wins, 4 regressions.** Worse — `noinline` prevents the function from being inlined *into its caller*, but LTO still inlines callees *into its body*. The selectBytes regression persisted (+18-20%), and stream churn regressed (+19%).

### Round 3: `-flto` stacked with experiments 041+043 (Ryu + SWAR)

Compared against 041+043 without LTO: **0 wins, 7 regressions.** LTO was strictly harmful on top of the optimized bytes path. Point query -17%, fan-out +21%, interactive transaction +40%. The Ryu+SWAR changes reduced the bytes-path workload enough that icache wasn't the bottleneck, but LTO's code layout changes hurt other paths.

### Round 4: `-flto=thin` stacked with 041+043

**2 wins, 4 regressions.** ThinLTO was less destructive than full LTO but still net negative. Fan-out +21%, batched write tx +21%.

## Decision

**Rejected.** Four rounds of testing showed no configuration where LTO is net positive:

- Alone: helps objects, hurts bytes
- With noinline: still hurts bytes, adds new regressions
- Stacked with 041+043: strictly harmful (0 wins, 7 regressions)
- ThinLTO: still net negative

The root cause is that `native_toolchain_c` already uses `-O3`, which performs aggressive intra-unit optimization. The cross-unit inlining from LTO causes code size bloat that degrades icache behavior. The SQLite amalgamation is already a single ~250k-line translation unit with its own internal inlining — adding resqlite.c into the optimization scope creates too much code for the instruction cache to handle efficiently.

The objects-path wins from the initial test were real but misleading — they were offset by regressions in other paths, and the "wins" on unrelated metrics (point query, writes) were baseline noise that appeared across all experiments regardless of what was changed.
