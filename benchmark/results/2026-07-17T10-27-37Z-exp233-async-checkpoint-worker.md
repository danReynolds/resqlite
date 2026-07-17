# Exp 233 async checkpoint worker A/B

**Date:** 2026-07-17
**Base:** `origin/main` at `2394edab4c3d`
**Host:** Darwin 25.2.0 arm64
**Dart:** 3.12.2 stable, macOS arm64

## Method

The same focused harness ran from a detached baseline worktree and the
candidate worktree. Each side used seven repeats, 3,000 sequential 8 KiB
writes per sustained repeat, one foreground read per 100 writes, and a 250 ms
settle observation:

```text
dart run benchmark/experiments/async_checkpoint_worker.dart \
  --label=<side> --repeats=7 --writes=3000 \
  --read-every=100 --settle-ms=250
```

Two comparisons were taken in opposite order. The first-threshold lane is exp
132's 10,000-row x 20-parameter mixed-emoji batch, which produces 529 WAL
frames and crosses the current 500-frame hook threshold in one commit. The
sustained lane uses awaited single-row writes so it can expose checkpoint/write
contention rather than only the first offloaded checkpoint.

## Decision summary

Lower is better for every latency column.

| Pair | Metric | Baseline | Candidate | Delta |
|---|---|---:|---:|---:|
| baseline first | first crossing p50 | 61.883 ms | 27.027 ms | **-56.3%** |
| baseline first | sustained write p50 | 0.041 ms | 0.138 ms | **+236.6%** |
| baseline first | sustained write p95 | 0.109 ms | 0.493 ms | **+352.3%** |
| baseline first | sustained write p99 | 0.659 ms | 1.502 ms | **+127.9%** |
| baseline first | foreground read p95 | 0.218 ms | 0.259 ms | **+18.8%** |
| candidate first | first crossing p50 | 66.178 ms | 35.878 ms | **-45.8%** |
| candidate first | sustained write p50 | 0.044 ms | 0.117 ms | **+165.9%** |
| candidate first | sustained write p95 | 0.112 ms | 0.373 ms | **+233.0%** |
| candidate first | sustained write p99 | 0.429 ms | 1.069 ms | **+149.2%** |
| candidate first | foreground read p95 | 0.207 ms | 0.325 ms | **+57.0%** |

The offload removes roughly half of the first threshold-crossing commit wall in
both orderings, but it makes the sustained write path 2.7-3.4x slower at p50,
3.3-4.5x slower at p95, and 2.3-2.5x slower at p99. The read guard regresses in
both orderings. This clears the mechanism target and fails the predeclared
sustained-tail and foreground-read kill conditions.

## First threshold-crossing raw wall

| Pair | Side | Repeat wall (ms) | p50 | p95 / max |
|---|---|---|---:|---:|
| baseline first | baseline | 61.883, 66.852, 81.389, 69.901, 48.904, 43.649, 58.433 | 61.883 | 81.389 |
| baseline first | candidate | 40.379, 39.472, 24.890, 25.203, 27.027, 27.272, 25.510 | 27.027 | 40.379 |
| candidate first | candidate | 47.219, 40.634, 22.323, 21.319, 24.496, 35.878, 39.417 | 35.878 | 47.219 |
| candidate first | baseline | 66.178, 87.545, 68.940, 49.814, 55.602, 150.281, 43.971 | 66.178 | 150.281 |

For every candidate threshold repeat, the immediate observational NOOP sample
reported `log=529, checkpointed=0`; after 250 ms it reported
`log=529, checkpointed=529`. Every baseline repeat had already checkpointed all
529 frames before the write future completed. This directly verifies that the
candidate moved checkpoint work off the writer's reply path.

## Sustained per-repeat write tails

| Pair | Side | Repeat | p50 ms | p95 ms | p99 ms | max ms |
|---|---|---:|---:|---:|---:|---:|
| baseline first | baseline | 1 | 0.055 | 0.140 | 1.234 | 21.913 |
| baseline first | baseline | 2 | 0.044 | 0.135 | 2.399 | 74.991 |
| baseline first | baseline | 3 | 0.038 | 0.110 | 0.190 | 12.879 |
| baseline first | baseline | 4 | 0.039 | 0.097 | 0.522 | 30.823 |
| baseline first | baseline | 5 | 0.040 | 0.105 | 0.547 | 34.445 |
| baseline first | baseline | 6 | 0.039 | 0.083 | 0.134 | 18.984 |
| baseline first | baseline | 7 | 0.041 | 0.098 | 0.260 | 24.078 |
| baseline first | candidate | 1 | 0.173 | 0.801 | 2.157 | 15.035 |
| baseline first | candidate | 2 | 0.113 | 0.423 | 1.675 | 19.186 |
| baseline first | candidate | 3 | 0.147 | 0.320 | 0.529 | 4.383 |
| baseline first | candidate | 4 | 0.155 | 0.566 | 1.801 | 30.750 |
| baseline first | candidate | 5 | 0.129 | 0.311 | 1.309 | 10.761 |
| baseline first | candidate | 6 | 0.129 | 0.462 | 1.355 | 4.145 |
| baseline first | candidate | 7 | 0.130 | 0.477 | 1.665 | 19.320 |
| candidate first | candidate | 1 | 0.170 | 0.621 | 1.318 | 6.836 |
| candidate first | candidate | 2 | 0.147 | 0.549 | 1.320 | 6.388 |
| candidate first | candidate | 3 | 0.120 | 0.264 | 0.881 | 5.843 |
| candidate first | candidate | 4 | 0.132 | 0.295 | 1.026 | 26.377 |
| candidate first | candidate | 5 | 0.097 | 0.220 | 0.967 | 7.314 |
| candidate first | candidate | 6 | 0.102 | 0.205 | 0.333 | 6.470 |
| candidate first | candidate | 7 | 0.095 | 0.178 | 0.973 | 7.068 |
| candidate first | baseline | 1 | 0.060 | 0.172 | 0.585 | 29.884 |
| candidate first | baseline | 2 | 0.045 | 0.104 | 0.645 | 32.630 |
| candidate first | baseline | 3 | 0.043 | 0.119 | 0.270 | 17.338 |
| candidate first | baseline | 4 | 0.041 | 0.098 | 0.265 | 23.330 |
| candidate first | baseline | 5 | 0.043 | 0.126 | 0.335 | 22.336 |
| candidate first | baseline | 6 | 0.040 | 0.087 | 0.145 | 15.893 |
| candidate first | baseline | 7 | 0.040 | 0.102 | 0.423 | 12.767 |

## WAL progress

The baseline sustained lane ended each repeat with a stable below-threshold
remainder (`log=301, checkpointed=0`) both immediately and after 250 ms.

The candidate's sustained WAL grew as high as 12,377 frames. In the
baseline-first pair, immediate pending-frame counts were
`561, 70, 78, 4, 90, 78, 4`; all but one four-frame remainder settled by 250
ms. In the candidate-first pair they were
`12, 82, 4, 24, 7771, 5049, 9273`; the last two repeats still had 2,689 and
3,625 pending frames after 250 ms.

The implementation explains the repeated work: the WAL hook uses a level
trigger (`pages_in_wal >= 500`). Offloading the first checkpoint lets the writer
continue while the frame count remains above that level, so later commits keep
setting `requested` or `running_rerun`. The four-state coalescer limits duplicate
messages, but it does not re-arm on a new WAL generation or a fresh high-water
mark. The worker therefore competes with sustained writes and readers instead
of performing one bounded offloaded checkpoint.

## Outcome

Rejected. The exact prototype is preserved at `archive/exp-233`; runtime and
checkpoint-worker-specific tests are removed from the publication branch.

Reopen only with a reset-aware or high-water trigger that cannot stay armed for
an entire burst, and require the same sustained write/read lanes to remain
neutral or improve. A representative downstream trace showing inline
checkpoint wall is materially user-visible would also strengthen the value
case; this experiment establishes a large first-crossing ceiling, not incidence.
