# Experiment 052: Column-level dependency tracking

**Date:** 2026-04-15
**Status:** Deferred (architectural fit valid, benchmark cannot measure)

## Problem

The stream invalidation engine currently tracks dependencies at table granularity. A stream watching `SELECT name FROM users WHERE active = 1` re-queries on any write to `users`, even if the write only modifies unrelated columns like `avatar_url`. In a CRUD app with multiple streams on the same table watching different fields, this causes many unnecessary re-queries.

## Hypothesis

Capture read dependencies at `table.column` granularity instead of just `table`. When a write occurs, use `sqlite3_preupdate_old` and `sqlite3_preupdate_new` to diff which columns actually changed, then only invalidate streams whose column dependencies intersect with the changed columns.

## Approach (Designed, Not Built)

1. **Authorizer:** Stop discarding `arg2` (column name) in the authorizer callback. Build `"table.column"` read-set entries.
2. **Preupdate hook:** For UPDATE ops, iterate columns and call `sqlite3_preupdate_old`/`sqlite3_preupdate_new`, comparing values. Build a "dirty columns" set alongside the dirty tables set. For INSERT/DELETE, mark all columns of the touched table as dirty (conservative).
3. **Stream engine:** Change the inverted index from `table → stream keys` to `table.column → stream keys`. Invalidation checks column-level intersection.

## Why Not Implemented

Inspection of `streaming.dart` shows that every streaming benchmark uses schemas where every stream watches every column of the same table:

- `SELECT COUNT(*) FROM items` — aggregates all data
- `SELECT * FROM items ORDER BY id` — selects all columns

And every write touches columns that all active streams watch. **Unchanged rate is 0%** in the current suite.

This optimization's value scales with the disjoint-column rate — how often a write's changed columns don't intersect with a stream's read columns. The current benchmarks have 0% disjoint rate, so this experiment would show no measurable benefit (or even a slight regression from the added preupdate work).

This is the same pattern as experiments 055 (columnar arrays) and 061 (C-side hash): architecturally valuable for real workloads, benchmark-invisible without a matching test harness.

## Preupdate Hook Cost Analysis

Research into `sqlite3_preupdate_old` / `sqlite3_preupdate_new` (see `experiments/061-c-side-hash.md` research section):

- First call per row: triggers `sqlite3BtreePayload` + `vdbeUnpackRecord` for the entire row (~1-5μs)
- Subsequent column accesses: cached array lookup (~free)
- Total per-write overhead: ~3-11μs for a 10-column UPDATE touching 2 columns

Against ~50-500μs of SQLite write work, this is 1-5% overhead. Real but acceptable for the invalidation savings it enables.

## Decision

**Deferred.** Implementation path is clear (~200-300 lines of C + Dart). Rejected for round 2 because the current benchmarks can't validate the win — and we'd have a hard time justifying the code complexity with a 0% unchanged-rate benchmark.

**Prerequisite for revisit:** Add a benchmark that exercises column-disjoint streams (e.g., stream A watches `users.name`, stream B watches `users.avatar_url`; writes only modify `avatar_url`). That benchmark would show where column-level tracking pays off.

Pairs naturally with experiment 061 (C-side hash for unchanged re-queries) — both need the same benchmark support and together would capture the full "don't do work when results didn't change" story.
