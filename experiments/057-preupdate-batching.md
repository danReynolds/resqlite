# Experiment 057: Preupdate hook batching for batch inserts

**Date:** 2026-04-16
**Status:** Rejected (savings below noise floor)

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
