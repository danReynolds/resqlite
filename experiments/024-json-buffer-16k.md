# Experiment 024: Increase JSON Buffer Initial Size to 16KB

**Date:** 2026-04-08
**Status:** Accepted (negligible impact, but sensible default)

## Hypothesis

Starting the JSON output buffer at 4KB causes 2-3 reallocs (each a full memcpy)
for typical results. 16KB covers most results in a single allocation.

## Change

Changed `buf_init(&b, 4096)` to `buf_init(&b, 16384)` in `resqlite_query_bytes()`.

## Results

All neutral — 1 win (narrow schema, likely noise), 1 regression (select 100 rows,
likely noise), 15 neutral. No clear signal.

The lack of signal suggests that realloc overhead at 4KB was already negligible —
the doubling strategy means even a 100KB result only reallocs 5 times (4→8→16→32→
64→128KB), and `realloc` on modern allocators is often a no-op for small sizes
(the allocator has slack space).

## Decision

**Accepted** — no measurable impact but 16KB is a more sensible initial size for
a JSON serializer that typically produces 10-100KB results. The 12KB extra initial
allocation is negligible (freed immediately after the query).
