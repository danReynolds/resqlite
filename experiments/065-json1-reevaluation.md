# Experiment 065: JSON1 bulk shapes re-evaluation

**Date:** 2026-04-16
**Status:** Rejected (confirms experiment 031's original conclusion)

## Problem

Experiment 031 rejected SQLite's built-in `json_group_array(json_object(...))` approach for bulk JSON output as "mixed and workload-specific." That evaluation was against the pre-Ryu/pre-SWAR serializer which took ~5.70ms for 10k rows.

After experiments 041 (Ryu) and 043 (SWAR+LUT), our custom selectBytes path is 44% faster at ~3.07ms for 10k rows. This could change the comparison:
- If JSON1 was close-to-competitive before, the improved custom path may now make it strictly worse across all sizes.
- If JSON1 was faster for specific shapes, it might still win there.

This experiment re-measures the comparison with the updated custom path.

## Approach

Pure measurement, no code changes. Benchmark two paths for the same JSON output:

- **Custom:** `selectBytes('SELECT id, name, value, score FROM items LIMIT ?', [n])`
- **JSON1:** `select("SELECT json_group_array(json_object('id', id, ...)) FROM items WHERE id <= ?", [n])`

## Results

Consistent across 3 runs:

| Rows | Custom (selectBytes) | JSON1 (select) | Custom/JSON1 Ratio |
|---:|---:|---:|---:|
| 100 | 0.07ms | 0.10-0.11ms | 1.46-1.59x faster |
| 1,000 | 0.42-0.43ms | 0.43-0.48ms | 1.03-1.12x faster |
| 10,000 | 4.18-4.49ms | 4.18-4.44ms | 0.98-1.05x (tied) |

**Our custom path is strictly better or equal to JSON1 across all sizes.** No scenario where JSON1 wins meaningfully.

At small result sizes, the custom path wins by ~50% — FFI overhead dominates, and JSON1 doesn't save any crossings since the `select()` call still has to marshal a single-row result back.

At medium sizes (1k rows), the custom path is marginally faster by 3-12%.

At large sizes (10k rows), the two are essentially tied. SQLite's tight C loop for JSON building is efficient, but our SWAR+Ryu-optimized serializer matches it.

## Decision

**Rejected.** Round 1's optimizations widened the gap between our custom path and JSON1 to the point where JSON1 is never a win. Experiment 031's original rejection stands and is now even stronger.

This is a "negative result with conviction" — the path is closed. Future evaluations of custom vs JSON1 aren't needed unless SQLite's JSON1 implementation changes substantially or our custom path regresses.
