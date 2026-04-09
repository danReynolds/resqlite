# Experiment 015: Cell Buffer Union (48 → 16 bytes)

**Date:** 2026-04-07
**Status:** Accepted (simplicity win, performance neutral)
**Commit:** [`52f1e4b`](https://github.com/danReynolds/dune/commit/52f1e4b)

## Hypothesis

Shrinking `resqlite_cell` from 48 bytes to 16 bytes using a C union would improve cache locality for the per-row cell buffer, especially for wide schemas and large result sets.

## Changes

Previous layout (48 bytes):
```c
typedef struct {
    int type;              // 4 bytes + 4 padding
    long long int_val;     // 8 bytes
    double double_val;     // 8 bytes
    const char* text_ptr;  // 8 bytes
    int text_len;          // 4 bytes + 4 padding
    const void* blob_ptr;  // 8 bytes
} resqlite_cell;
```

New layout (16 bytes):
```c
typedef struct {
    int type;        // 4 bytes
    int len;         // 4 bytes (text/blob length)
    union {
        long long i; // 8 bytes
        double d;    // 8 bytes
        const void* p; // 8 bytes (text/blob pointer)
    };
} resqlite_cell;
```

The Dart side was also simplified — 3 offset constants instead of 7, and all value types read from the same union offset.

## Results

Compared against writer-tuning baseline: **0 meaningful wins, 0 meaningful regressions.** All benchmarks within noise.

The buffer size reduction doesn't show up because even with the old 48-byte layout, a 10-column × 1-row buffer is only 480 bytes — well within L1 cache. The benefit would appear at much larger working sets (50k+ rows × 20+ columns).

## Decision

**Accepted** — not for performance (neutral), but for code quality:
- Simpler C struct (union makes the mutual exclusivity explicit)
- Fewer Dart offset constants (3 instead of 7)
- All value types at the same offset (simpler reading loop)
- 3x less memory allocation per query (nice-to-have)
