# Experiment 043: SWAR escape scanning + escape lookup table

**Date:** 2026-04-15
**Status:** Accepted

## Problem

`json_write_string` in `resqlite.c` scans each byte individually through 8 if/else if comparisons to check for JSON-escapable characters (`"`, `\`, `\b`, `\f`, `\n`, `\r`, `\t`, control chars < 0x20). For the overwhelmingly common case where no escape is needed, this is 8 branches per byte — 8000 branches per 1000-character string.

## Hypothesis

Two complementary optimizations:

1. **SWAR (SIMD Within A Register):** Load 8 bytes into a `uint64_t` and check all escape conditions with ~10 bitwise ops. If the result is zero, skip all 8 bytes at once. This eliminates branch overhead for the common no-escape case (most strings contain no special characters).

2. **Escape lookup table:** Replace the 8-way if/else chain with a 256-byte static lookup table indexed by character value. Maps each byte to its escape length (0 = safe, 2 = named escape, 6 = `\uXXXX`). Reduces the per-escape-character branch chain from 8 comparisons to a single table lookup.

These stack naturally: SWAR handles bulk safe spans, the lookup table handles the rare escape characters efficiently.

## Approach

```c
// SWAR: check 8 bytes at once for escape-needing characters.
while (i + 8 <= len) {
    uint64_t word;
    memcpy(&word, s + i, 8);
    // Check for bytes < 0x20 (control chars)
    uint64_t below_space = (word - 0x2020202020202020ULL) & ~word & 0x8080808080808080ULL;
    // Check for '"' (0x22) and '\\' (0x5C) via XOR + zero-detect
    uint64_t has_quote = ...;
    uint64_t has_bslash = ...;
    if ((below_space | has_quote | has_bslash) == 0) { i += 8; continue; }
    break; // Fall through to byte-by-byte
}

// Byte-by-byte with lookup table
for (; i < len; i++) {
    unsigned char elen = json_esc_len[c]; // 0, 2, or 6
    if (__builtin_expect(elen == 0, 1)) continue;
    // ... flush span, write escape
}
```

The SWAR technique is inspired by simdjson but uses no SIMD intrinsics — pure portable C that works on all platforms (ARM, x86, etc.).

## Results

**22 wins, 0 regressions** — the strongest result of any experiment in this batch.

| Benchmark | Baseline (ms) | SWAR+LUT (ms) | Delta |
|---|---|---|---|
| selectBytes 1000 rows | 0.51 | 0.35 | **-31%** |
| selectBytes 10000 rows | 5.70 | 4.14 | **-27%** |
| Text-heavy schema (1000 rows) | 0.67 | 0.58 | -13% |
| Concurrent reads 8x | 0.77 | 0.68 | -12% |
| Parameterized queries | 15.89 | 13.90 | -13% |

The selectBytes improvements are the direct signal — 27-31% faster JSON serialization at scale. The SWAR fast-path eliminates branch overhead for the vast majority of string bytes (typical text has no JSON-special characters), while the lookup table makes the rare escape case branchless.

## Decision

**Accepted.** 22 wins, zero regressions, and a 27-31% improvement on the targeted path (selectBytes at scale). The code is pure portable C with no platform-specific intrinsics. The SWAR approach is well-established (simdjson, yyjson) and the lookup table is a standard optimization.

Combined with experiment 041 (Ryu), these two changes halve selectBytes time: 5.70ms → 3.19ms at 10k rows (-44%).
