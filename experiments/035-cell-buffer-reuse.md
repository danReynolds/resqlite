# Experiment 035: Reuse Cell Buffer Across Queries

**Date:** 2026-04-09
**Status:** Accepted

## Change

Hoisted the cell buffer (calloc'd native memory + TypedList views) to worker-
isolate scope. The buffer persists across queries and grows to the high-water
column count. Eliminates calloc + free per query.

Safe because each worker isolate is single-threaded (one query at a time).

## Results

Part of cumulative +17% point query improvement. Eliminates 1 calloc + 1 free
+ 4 TypedList view allocations per query.

## Decision

**Accepted** — eliminates real allocations on every query. The buffer is small
(16 bytes × column count, typically <256 bytes) and persists for the worker's
lifetime.
