# Experiment 021: SQLITE_DEFAULT_PCACHE_INITSZ=128

**Date:** 2026-04-08
**Status:** Accepted (slight positive trend)

## Hypothesis

Pre-allocating 128 page cache slots per connection at startup (instead of the
default ~20) avoids incremental malloc pressure during the first few queries.
With 2-4 readers + 1 writer, each connection does startup page cache growth
that this flag batches into a single contiguous allocation.

## Change

Added compile flag: `SQLITE_DEFAULT_PCACHE_INITSZ=128`

(Applied on top of experiment 020 — cumulative.)

## Results

| Benchmark | Before | After | Delta |
|---|---|---|---|
| Wide schema 1000 rows | 1.13ms | 1.01ms | -11% |
| Select Maps 5000 rows | 2.60ms | 2.25ms | -13% |
| All others | — | — | Neutral |

2 wins, 0 regressions, 15 neutral.

## Decision

**Accepted** — slight positive trend on larger result sets. Zero code complexity,
minimal memory cost (~512KB total across all connections at 4KB pages). The
improvement likely comes from fewer reallocs during page cache warm-up in the
benchmark's per-test Database.open cycle.
