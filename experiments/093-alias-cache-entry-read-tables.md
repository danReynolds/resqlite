# Experiment 093: Alias cache entry's read tables instead of copying

**Date:** 2026-04-22
**Status:** Rejected
**Archive:** [`archive/exp-093`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-093)

## Problem

On every reader query, `resqlite_get_read_tables` copied the read-table
list out of a per-reader `resqlite_read_set` scratch buffer. That scratch
was populated on each query by `read_set_load_from_cache_entry`, which
called `read_set_reset` (freeing every previously-owned string) and then
`read_set_add` (which `strdup`s each table name back in) for every
dependency of the cached statement.

For a statement whose authorizer captured N read tables, that meant **N
`free` + N `strdup` + N `memcpy`** of the captured strings on every
reader query — even on cache hits where the table list on the cache
entry was already authoritative and immutable.

## Hypothesis

Eliminate the per-query `strdup`/`free` churn by having
`resqlite_get_read_tables` alias directly into the cache entry's
`read_tables` array. The cache entry's string storage lives for the
cache's lifetime (invalidated as a unit on DDL), so as long as we stash
a pointer to the currently-active entry on the reader we can serve the
lookup with **zero string operations** — just a pointer follow + copy
of `N char*` values.

Expected savings: `2 × N × (strdup cost)` per query — order of a few
hundred nanoseconds on a 3–4 table statement. Not large by itself, but
the path runs on every stream registration / initial query, and the
target is "cheap-check-first" territory continuous with exp 077.

## Approach

Added a `resqlite_cached_stmt* current_read_entry` field to
`resqlite_reader`. `get_or_prepare_reader` publishes the entry pointer
on both the cache-hit path (after `sqlite3_reset`) and the cache-miss
path (after insertion). Fresh-prepare failure clears the alias to NULL
so stale pointers can't leak out.

`resqlite_get_read_tables` now reads
`readers[reader_id].current_read_entry->read_tables` directly, dropping
the `read_set_load_from_cache_entry` call from the hot path entirely.

Safety argument: a reader is held exclusively for the duration of a
query (pool-assigned dedicated slot, exp 030). Between the
`get_or_prepare_reader` return and the
`resqlite_get_read_tables`/release sequence there is no opportunity for
the cache to mutate on the same reader, so the aliased pointer is valid
for as long as it's read.

## Results

Three-run profile-mode A/B comparison (candidate vs. baseline), medians
of percentiles across runs. Raw JSONs are gitignored; the aggregate is
at `benchmark/profile/results/exp-093-aggregate.md`.

| workload / metric | baseline | candidate | Δ% | baseline CV |
|---|---:|---:|---:|---:|
| merge_rounds executeBatch p50 | 106 μs | 109 μs | +2.8% | 2.4% |
| merge_rounds executeBatch p99 | 280 μs | 615 μs | +119.6% | 30.1% |
| merge_rounds executeBatch max | 816 μs | 1726 μs | +111.5% | 7.0% |
| noop execute p99 | 69 μs | 96 μs | +39.1% | 14.5% |
| noop execute max | 569 μs | 936 μs | +64.5% | 16.4% |
| noop select p99 | 53 μs | 71 μs | +34.0% | 19.3% |
| point_query select p99 | 33 μs | 38 μs | +15.2% | 14.6% |
| point_query select max | 1179 μs | 2732 μs | +131.7% | 92.7% |
| single_insert execute p99 | 77 μs | 130 μs | +68.8% | 14.4% |
| single_insert execute max | 1379 μs | 1612 μs | +16.9% | 13.4% |
| **work medians (all workloads)** | — | — | +0–3 μs | — |

Full per-run values are in the aggregate file.

## Decision

Rejected — twice over:

1. **Work medians are unchanged.** Every workload's "work"
   measurement (C-side query execution) is within 0–3 μs of baseline —
   i.e., within the noise floor. The change saves the `strdup`/`free`
   pair, but that saving does not show up against everything else the
   work line measures.

2. **Tail metrics regressed, but the regression pattern is not
   attributable to the change.** `noop` workloads regressed on p99 and
   max just as much as `point_query` and `single_insert`, even though
   `noop execute` never runs a reader query and therefore never touches
   `read_set_load_from_cache_entry`. That's a strong hint the pattern
   is run-to-run variance (each side had only 3 samples; baseline CV on
   `point_query max` was 92.7 %) rather than a real regression from
   the change.

Combine the two: the change's hoped-for savings are below the
measurement floor, and there is no signal in the data that justifies
shipping it. Same class as exp 076 (pre-bound stmt cache rejected in
pre-implementation analysis: "bind is ~0.3 % of re-query wall time").
The `strdup`/`free` pair per query is real work, but at our query
rates it's just not visible.

## What this tells us

- The cache-hit read-table path is not the place to look for wins.
  `resqlite_get_read_tables` is called at most once per stream-
  registered query (not on plain reads, not on re-queries — exp 075's
  two-pass hash skips dep lookup on unchanged results), and even when
  it runs, N is typically 1–3. The absolute savings ceiling is tiny.
- For future optimizations in this area, 3 profile-runs per side is
  too few to resolve effects at this magnitude. Need ≥ 7 runs per side
  for a tail-metrics claim, or a focused microbenchmark of the
  `strdup`/`free` pair itself.

## Archive

The implementation (including the `current_read_entry` field, the
safety-comment block, and the `get_or_prepare_reader` publishing
points) is tagged `archive/exp-093` for future re-evaluation if the
calculus changes (many-tables queries becoming common, or a broader
cache-entry aliasing effort that would share this infrastructure).
