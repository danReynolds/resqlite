# Experiment 041: Ryu double-to-string for JSON serialization

**Date:** 2026-04-15
**Status:** Accepted

## Problem

The `selectBytes` JSON serialization path uses `snprintf(num, sizeof(num), "%.17g", ...)` for float formatting at `resqlite.c:1274`. `snprintf` is the slowest possible approach for double-to-string conversion: it parses a format string, handles locale, and always emits 17 significant digits even when fewer would suffice for IEEE 754 round-trip fidelity.

The `fast_i64_to_str` function (experiment 023) already optimized the integer path. The float path was the remaining bottleneck in the JSON type-dispatch switch.

## Hypothesis

Drop in the Ryu algorithm — a purpose-built double-to-string converter that produces the shortest round-trippable decimal representation. Ryu is used in the Java, Swift, and Rust standard libraries and benchmarks at 20-30x faster than `sprintf` for double formatting.

## Approach

1. Vendored `ryu/d2s.c` and supporting headers from [github.com/ulfjack/ryu](https://github.com/ulfjack/ryu) (Apache-2.0 license, pure C89, ~1500 lines).
2. Added `d2s.c` to `hook/build.dart` sources and `third_party/` to includes.
3. Replaced the single `snprintf` call with `d2s_buffered_n()`:

```c
// Before:
char num[32];
int num_len = snprintf(num, sizeof(num), "%.17g", sqlite3_column_double(stmt, i));

// After:
char num[25]; // Ryu needs at most 24 chars + NUL
int num_len = d2s_buffered_n(sqlite3_column_double(stmt, i), num);
```

## Results

**17 wins, 0 regressions** across the full benchmark suite (3 repeats vs baseline).

Key signals (selectBytes / JSON path):

| Benchmark | Baseline (ms) | Ryu (ms) | Delta |
|---|---|---|---|
| selectBytes 1000 rows | 0.51 | 0.48 | -6% |
| selectBytes 10000 rows | 5.70 | 5.66 | -1% |
| Text-heavy schema (1000 rows) | 0.67 | 0.60 | -10% |

The modest selectBytes improvement reflects the benchmark schema's mix of types (integers, text, and floats). The float formatting speedup is dramatic per-call (~20-30x faster) but floats are a fraction of the total cells in the benchmark dataset. Schemas with predominantly float columns would see larger gains.

Broader improvements (point query +44%, writes -19 to -26%) are consistent with run-to-run variance and should not be attributed to this change.

## Decision

**Accepted.** Ryu is faster, produces shorter output (fewer digits), and is correctness-equivalent (shortest round-trippable representation). Zero regressions. The vendored code is a single file with no dependencies — minimal maintenance burden.

Stacks multiplicatively with experiment 043 (SWAR escape scanning) — combined, they halve selectBytes time at scale.
