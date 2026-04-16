# Experiment 061: C-side hash for unchanged stream re-queries

**Date:** 2026-04-16
**Status:** Skipped (architectural fit issue; benchmark cannot measure)

## Problem

Stream re-queries with unchanged results currently:
1. Decode all cells into Dart objects (String allocations + int/double boxing)
2. Hash the values list via FNV-1a (experiment 031 — worker-side hash)
3. If hash matches `lastHash`, discard the decoded result

For a 100-row result with text columns, that's ~10μs of wasted allocation per unchanged re-query. Experiment 031 wins by avoiding the SendPort transfer cost when results are unchanged, but still pays the decode cost on the worker.

## Hypothesis

Hash the result in C during cell reads, before any Dart-heap allocation. If the hash matches, short-circuit without decoding. Only pay decode costs when the result actually changed.

## Analysis (Why Not Implemented)

SQLite's `sqlite3_step` is **destructive** — once you step through all rows, you can't rewind without `sqlite3_reset` and re-execution. This creates an asymmetric tradeoff:

- **Unchanged case:** step + hash in C → match → skip decode. Savings: ~10μs per query.
- **Changed case:** step + hash in C → mismatch → must re-execute query + step + decode. Cost: ~500μs for a typical query (re-running B-tree traversal + index lookups).

Break-even requires **unchanged rate > ~95%** in the real workload.

Inspection of the streaming benchmarks (`streaming.dart`) reveals that every test case has unchanged rate **0%**: writes always change the watched query's result (e.g., `SELECT COUNT(*)` on a table we're inserting into). A benchmark showing this optimization's value would require streams watching column-disjoint data from writes — e.g., stream watches `users.name`, write modifies `users.avatar_url` — which the current suite does not exercise.

This is the same pattern as experiments 052 (column-level dependency tracking) and 055 (columnar typed arrays): architecturally valuable for real-world workloads but below the benchmark noise floor — or worse, would show as a regression.

### Alternative considered: hash during existing decode

Instead of a separate hash pass, merge hashing into the decode loop. This saves ~1μs per result by eliminating the second walk over the values list. Below noise; not worth a separate experiment.

## Decision

**Skipped.** The optimization is valid in principle and would benefit real apps with low unchanged rates (common in production: many streams watch largely-stable filtered data while writes happen elsewhere). Not implemented because:

1. Current benchmarks would show a regression (unchanged rate = 0%)
2. The alternative "hash during decode" saves only ~1μs per result — below noise
3. The implementation requires persistent cell buffers (text/blob data must survive across step calls) — a non-trivial change in the cell buffer contract

Revisit when the benchmark suite includes realistic stream patterns with column-disjoint or row-disjoint writes. Pairs naturally with experiment 052 (column-level dependency tracking) — both need the same benchmark support.
