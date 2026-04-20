# Experiment 084: Late dispatch generation stamp

**Date:** 2026-04-20
**Status:** Rejected

## Problem

The old stream rerun path captured `writeGen` too early: when the rerun
was requested, not when it actually got a reader. That made it plausible
that a simpler fix than a bounded scheduler might work:

- keep the existing pool behavior
- stamp the generation only when the rerun is actually dispatched
- judge staleness against that later stamp

## Hypothesis

If the main issue is "reruns are marked stale because they waited too
long before starting", then moving the generation stamp to actual reader
dispatch time should recover most of the benefit with much less code than
the pre-dispatch queue.

## Approach

Built a simpler variant in a separate branch:

- no bounded pre-dispatch rerun queue
- no reserved reader slot
- still only one in-flight rerun per stream entry
- rerun generation stamped immediately before `ReaderPool` hands the
  request to a reader

That means a rerun no longer treats pool wait time as part of its stale
window.

## Results

### Scenario profiler: real but partial improvement

Median of two runs, compared to the clean observability baseline:

| Scenario | Metric | Baseline | Late stamp |
|---|---|---:|---:|
| A11 | reruns started | 1081 | **937.5** |
| A11 | stale reruns | 1026 | **792.5** |
| A11 | wall | 442207 us | **440106.5 us** |
| A11 | pool wait / rerun | 2155 us | **1715.8 us** |
| A11b | reruns started | 1039 | **925** |
| A11b | stale reruns | 933 | **790** |
| A11b | wall | 459509 us | **432653.5 us** |
| A11b | pool wait / rerun | 3880 us | **3028.1 us** |

So the idea helped. It fixed part of the "stamped too early" problem.

### But it did not remove the real bottleneck

Compared to Experiment 083's bounded queue:

| Scenario | Metric | Late stamp | Pre-dispatch queue |
|---|---|---:|---:|
| A11 | reruns started | 937.5 | **737** |
| A11 | stale reruns | 792.5 | **553** |
| A11 | pool wait / rerun | 1715.8 us | **0.3 us** |
| A11b | reruns started | 925 | **705** |
| A11b | stale reruns | 790 | **552** |
| A11b | pool wait / rerun | 3028.1 us | **0.1 us** |

The simpler fix still left the real bottleneck alive: reruns were still
allowed to pile up inside `ReaderPool`.

## Decision

Rejected as the main fix.

This variant is valuable because it proved two things:

1. The original path really was stamping too early.
2. Fixing only that does not solve the broader queue-contention problem.

So the late-stamp idea is a legitimate partial improvement, but it is
materially weaker than the bounded pre-dispatch queue because it leaves
the scarce reader bottleneck saturated.
