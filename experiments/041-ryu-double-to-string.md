# Experiment 041: Ryu double-to-string for JSON serialization

**Date:** 2026-04-15 (originally accepted), 2026-04-16 (reverted)
**Status:** Rejected (minimal isolated benefit, high maintenance complexity)

## Problem

The `selectBytes` JSON serialization path uses `snprintf(num, sizeof(num), "%.17g", ...)` for float formatting. `snprintf` parses a format string and always emits 17 significant digits even when fewer would suffice for IEEE 754 round-trip fidelity.

## Hypothesis

Replace `snprintf` with the Ryu algorithm — a purpose-built double-to-string converter benchmarked at 20-30x faster than `sprintf` per call and used in Java/Swift/Rust standard libraries.

## Initial Approach

Vendored `d2s.c` and supporting headers from [github.com/ulfjack/ryu](https://github.com/ulfjack/ryu) (Apache-2.0 license, ~1500 lines of C including multiplication tables and intrinsics headers). Added to `hook/build.dart` as an additional source.

Replaced the single `snprintf` call with `d2s_buffered_n()`.

## Problem Discovered in PR Review

Copilot's PR review on `third_party/ryu/ryu.h:41` and `native/resqlite.c:1335` flagged that Ryu's `d2s_buffered_n` **always emits scientific notation**: `100.0` → `"1E2"`, `0.0` → `"0E0"`, `3.14` → `"3.14E0"`. This is a user-visible JSON output change that would break snapshot tests and any downstream consumer that relies on `%.17g`-style formatting.

A ~85-line C wrapper (`d2s_g_format`) was added to post-process Ryu's output into `%.17g`-compatible format (plain decimal for exponents in [-4, 16], scientific otherwise), verified against 12 representative values.

## Why Finally Rejected

Re-examining the benchmark results attributable to 041 alone (before 043 stacked on top):

| Benchmark | Baseline | 041 alone | Attributable to 041? |
|---|---|---|---|
| Text-heavy schema (1000 rows) | 0.67ms | 0.60ms | **-10% real** |
| selectBytes 1000 rows | 0.51ms | 0.48ms | within noise |
| selectBytes 10000 rows | 5.70ms | 5.66ms | within noise |
| Point query, fan-out, writes, etc. | — | apparent wins | **baseline noise** |

The non-selectBytes "wins" in the original 041 writeup (+44% point query, -38% fan-out, -26% batch insert, -44% interactive tx) appeared at similar magnitudes in every subsequent experiment that didn't touch float formatting (043, 044, 045, 067). Those were thermal-state noise against the baseline run, not attributable to Ryu.

**The only clean, attributable 041 win was -10% on text-heavy selectBytes at 1000 rows.** The selectBytes path itself (where Ryu lives) didn't move measurably at 1k or 10k rows.

The `-44%` selectBytes improvement that kept getting cited came from **041 + 043 combined**, where 043 (SWAR escape scanning + lookup table) did the actual work — confirmed by 043 alone showing -31% selectBytes at 1000 rows and -27% at 10000 rows.

### Cost-benefit

- **Cost:** ~1500 lines of vendored third-party code (`d2s.c` + headers + tables), ~85 lines of wrapper to un-do Ryu's scientific notation, a new `third_party/ryu/` directory to maintain, license tracking (Apache-2.0 + Boost dual), additional build complexity.
- **Benefit:** ~10% improvement on one benchmark (text-heavy 1k rows) where float formatting is a small fraction of total JSON work.

Not justified.

## Revert

Removed `third_party/ryu/` directory, removed the `d2s_g_format` wrapper, restored `snprintf(num, sizeof(num), "%.17g", ...)`, removed the Ryu source + include path from `hook/build.dart`. All 126 library tests pass after revert.

## Decision

**Rejected.** The isolated win is marginal and doesn't justify the vendored-dependency + format-compatibility-wrapper complexity. Experiment 043 (SWAR escape scanning + lookup table) captures the real JSON-serialization win with simpler, in-tree code.

## Lessons

1. **Attribute wins carefully.** The original 041 writeup double-counted thermal noise as Ryu wins. Subsequent experiments showed the same deltas without touching floats — that should have triggered re-examination sooner.
2. **Check upstream API contracts before vendoring.** Ryu's scientific-notation-only output is documented, but I missed it on first integration. Copilot's PR review caught the format regression.
3. **Real benefit must be attributable and significant.** A win that shows up in one benchmark at the noise floor, stacked with a much bigger win from another change, isn't enough to justify a 1500-line vendored dependency.
4. **Complexity budget matters.** Even when an optimization works, the code and dependency cost has to match the measurable benefit. ~1500 + 85 lines for -10% on one schema shape is well past the budget.
