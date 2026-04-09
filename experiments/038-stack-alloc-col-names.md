# Experiment 038: Stack Allocation for Column Name Arrays

**Date:** 2026-04-09
**Status:** Accepted

## Change

In `write_json_to_buf`, replaced heap-allocated `col_names` and `col_name_lens`
arrays with stack-allocated arrays for column counts ≤64 (covers virtually all
real schemas). Falls back to malloc for >64 columns.

## Results

No isolated signal — eliminates 2 malloc + 2 free per selectBytes query, but
these are tiny allocations (typically <128 bytes). Saves ~50ns per query.

## Decision

**Accepted** — trivial change (4 lines), eliminates unnecessary heap allocations.
64 columns × (8 + 4) bytes = 768 bytes on stack, well within safe limits.
