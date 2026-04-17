# Experiment 057: Preupdate hook batching for batch inserts

**Date:** 2026-04-16
**Status:** Rejected (savings below measurement precision after re-evaluation)
**Archive:** [`archive/exp-057`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-057)

## Problem

The preupdate hook fires per-row during batch inserts. For `executeBatch` with 10,000 rows into one table, that's 10,000 calls to `dirty_set_add`, each doing a linear dedup scan over the set contents — all resolving to the same table name. This is wasted work.

## Hypothesis

Add a `batch_suppress_hook` flag to the `resqlite_db` struct. When set, the preupdate hook skips `dirty_set_add` after the first capture. Set the flag before `run_batch_locked`, clear it after. The table name is captured on the first row and not redundantly re-added 9,999 times.

## Approach

```c
struct resqlite_db {
    // ...
    int batch_suppress_hook;  // New: skip hook after first capture during batch
};

static void preupdate_hook(...) {
    // ...
    if (sdb->batch_suppress_hook && sdb->dirty_tables.count > 0) return;
    dirty_set_add(&sdb->dirty_tables, table_name);
}

int resqlite_run_batch(...) {
    // ... BEGIN IMMEDIATE ...
    db->batch_suppress_hook = 1;
    rc = run_batch_locked(...);
    db->batch_suppress_hook = 0;
    // ... COMMIT ...
}
```

## Results

**0 wins, 1 regression, 62 neutral** (3 repeats vs baseline).

The batch insert 10k rows benchmark was essentially unchanged: 4.75ms → 4.64ms (within noise threshold of ±0.48ms).

Analysis: `dirty_set_add` with 1-3 existing entries does ~3-10ns of strcmp + return-early-on-match. At 10k rows, that's ~30-100μs of total preupdate hook overhead — 2-6% of a 4.75ms batch. Real but below the benchmark noise floor of ±10%.

## Decision

**Rejected.** The optimization is correct in principle (and could be accepted as a cleanup), but the performance win is too small to measure and too small to justify the added complexity of a new struct field with flag-flip semantics around the batch call site.

The preupdate hook's `dirty_set_add` is already well-optimized (linear scan of a ~3-entry set is cache-resident). The remaining overhead is fundamental: SQLite calls the hook once per row, and we must accept that.

## Re-evaluation (post benchmark-harness-extensions, 2026-04-16)

After the new benchmark harness landed (PR #6: CI-based MDE, memory suite, 5-repeat machinery), this experiment was a natural candidate to re-check. The original rejection cited "below noise floor" where the floor was ±10% — the new harness should tighten that bound considerably.

### What I re-implemented

Full implementation this round, not the sketch above. Key addition vs the original pseudocode: a `batch_base_count` sentinel so the batch's first row still captures its table even if earlier writes left entries in the dirty set. Without that guard, a back-to-back pattern of `execute(INSERT INTO A)` → `executeBatch(INSERT INTO B, ...)` would silently drop B's invalidation. Implementation preserved in the archive tag. Tests: 126/126 pass, no regression.

### New measurements (5 repeats each side)

Batch Insert 10k rows, `resqlite executeBatch()`:

| Metric | Baseline (main) | Exp 057 | Delta |
|---|---:|---:|---:|
| Wall-time median (ms) | 4.63 | 4.44 | **−4.1%** |
| Wall MAD% | 1.4% | 1.4% | — |
| 3× MAD threshold | 4.2% | 4.2% | — |
| RSS delta median (MB) | 0.69 | 1.44 | +0.75 MB |
| RSS delta MDE (MB) | ±0.88 | ±2.61 | — |

Smaller batch sizes (100 and 1000 rows) showed no measurable change.

### Sign flipped between 3 and 5 repeats

Classic sub-MDE signature. At 3 repeats, the wall-time delta was **+4.6% (slower)**; at 5 repeats it was **−4.1% (faster)**. Both within ±10% and within 3× MAD. The memory axis flipped the same way: 3 repeats showed exp 057 with lower RSS delta, 5 repeats showed it higher. When the sign is that fragile at the noise boundary, the honest answer is that the real effect is below ±1-2% — consistent with the original analysis (~30-100μs savings in a 4.75ms batch = ~1%).

### Why the memory suite didn't surface anything new

This is a correction to my earlier reasoning. Looking at the code, `dirty_set_add` already short-circuits on duplicate table names via `strcmp`. For a 10k-row batch into one table, only the **first row** allocates (one `strdup`). Rows 2..N hit the dedup and return without allocation. The optimization skips ~10k strcmp calls — pure CPU, no allocation delta. The memory suite correctly registers no signal because there's no allocation to eliminate.

### Updated decision: still rejected, now with better evidence

The writeup's original conclusion stands. Rejection reasons:

1. **Effect is ≤2% on the time axis** — below the new harness's practical write-suite MDE (~4-5% at 5 repeats).
2. **Zero memory signal** — the `dirty_set_add` dedup already gives O(1) allocations per batch.
3. **Complexity cost unchanged** — new struct fields and flag management around two batch entry points.
4. **Correctness risk added** — the `batch_base_count` sentinel is necessary for correctness in the back-to-back-writes case. Any future code that changes the dirty-set lifecycle would need to preserve this invariant.

The re-eval validates both the original analysis and the new harness: a sub-2% optimization remains sub-2% when measured more precisely, and the harness reports that accurately instead of mis-flagging noise as signal. Worth the 2 hours of re-verification to have numeric evidence rather than analytical reasoning.

Archive tag (`archive/exp-057`) preserves the full implementation for future reference. If a workload emerges where batch inserts are tens of millions of rows (putting the CPU win into millisecond range), the implementation is a `git cherry-pick` away.
