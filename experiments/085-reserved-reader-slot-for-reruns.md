# Experiment 085: Reserved reader slot for reruns

**Date:** 2026-04-20
**Status:** Rejected (full-capacity variant); reserved-slot policy kept

## Problem

Experiment 083 introduced two changes together:

1. a bounded pre-dispatch rerun queue
2. a policy that leaves one reader free for non-rerun work

Those needed to be isolated. If the win came mostly from "keep one
reader free", then the queue might be less essential than it looked. If
the queue did most of the work, then the reserved slot was a secondary
policy choice.

## Hypothesis

If the queue itself is the real win, then allowing reruns to use all
readers should:

- keep most of the `A11` / `A11b` benefit
- but potentially regress mixed workloads by letting reruns monopolize
  the whole reader pool

## Approach

Built a queue variant identical to Experiment 083 except for one runtime
change:

- reruns may use full `readerCount`
- no reserved reader slot for fresh reads / initial stream queries

This isolates the contribution of the reserved-slot policy.

## Results

### Scenario profiler: queue does most of the high-fan-out work

Compared to the reserved-slot queue from Experiment 083:

| Scenario | Metric | Reserved slot | Full capacity |
|---|---|---:|---:|
| A11 | wall | 451586 us | **440844 us** |
| A11 | reruns started | **737** | 981 |
| A11 | stale reruns | **553** | 779 |
| A11 | pool wait / rerun | 0.3 us | **0.0 us** |
| A11b | wall | 428234 us | **426687 us** |
| A11b | reruns started | **705** | 884 |
| A11b | stale reruns | **552** | 730 |
| A11b | pool wait / rerun | 0.1 us | **0.0 us** |

This shows the queue is the main reason `A11` / `A11b` improved. The
reserved reader is not what eliminated the reader-pool wait bottleneck.

### Real suite sections: reserved slot matters for balanced behavior

Single direct suite comparison:

| Scenario | Reserved slot | Full capacity |
|---|---:|---:|
| A6 Feed Reactive | **110.176 ms** | 118.982 ms |
| A11 Keyed PK | **214.57 ms** | 222.15 ms |
| A11b High-card fan-out | **231.65 ms** | 232.39 ms |
| A7 bulk burst | **50.53 ms** | 205.86 ms |
| A7 merge rounds | **3.34 ms** | 9.76 ms |

The `A7` regression is the important signal: without a reserved reader,
reruns can monopolize the pool and sync-burst behavior degrades badly.

## Decision

Reject the full-capacity variant as the default policy.

The isolated result is useful:

- the **queue** is the main source of the `A11` / `A11b` win
- the **reserved reader** is the safeguard that keeps reruns from taking
  over the whole pool on broader workloads

So the reserved slot is not the primary optimization, but it is an
important part of making the scheduler safe and well-balanced.
