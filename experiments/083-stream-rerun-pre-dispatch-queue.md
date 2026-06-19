# Experiment 083: Stream rerun pre-dispatch queue

**Date:** 2026-04-20
**Status:** In Review
**PR:** [#25](https://github.com/danReynolds/resqlite/pull/25)
**Benchmark Run:** none (predates the per-experiment-result-file convention; the measured wins live in PR #25's commentary, not in a same-day exp-083 release artifact)

## Problem

High-fan-out stream scenarios (`A11`, `A11b`) were still spending a large
amount of time on reruns that eventually finished stale.

The new stream timing counters showed the cost was not:

- SQLite execution
- result delivery
- main-isolate apply time

It was mostly **reader-pool wait time**. Under bursty writes, many
different streams each contributed one rerun, and those reruns sat inside
the generic `ReaderPool` queue long enough to become stale before they
mattered.

## Hypothesis

If reruns are coalesced **before** they enter `ReaderPool`, instead of
after they are already waiting for a reader, then:

- fewer reruns should actually start
- fewer reruns should finish stale
- reader-pool wait time should collapse toward zero
- high-fan-out scenarios should improve without changing `stream(sql)`
  semantics

## Approach

Added a bounded pre-dispatch rerun queue in `StreamEngine`.

Instead of immediately dispatching every rerun request to `ReaderPool`:

- `StreamEngine` keeps a queue of stream entries needing reruns
- only a bounded number of reruns may be dispatched at once
- repeated invalidations for a queued entry collapse there by bumping
  `writeGen`
- one reader slot is left free for non-rerun work

Supporting observability was added so the decision could be based on
measured queue wait, worker execution, and completion time rather than
wall-clock alone.

## Results

### Scenario profiler: direct bottleneck hit

Compared to the pre-queue observability baseline:

| Scenario | Metric | Baseline | Pre-dispatch queue |
|---|---|---:|---:|
| A11 | reruns started | 1024 | **737** |
| A11 | stale reruns | 968 | **553** |
| A11 | pool wait / rerun | 2155 us | **0.3 us** |
| A11b | reruns started | 1123 | **705** |
| A11b | stale reruns | 1020 | **552** |
| A11b | pool wait / rerun | 3880 us | **0.1 us** |

Worker execution stayed small in both cases (roughly 44-46 us per rerun),
which confirms the optimization is hitting the real bottleneck: queued
reruns waiting on readers.

### Real suite sections: broad behavior stays in band

Three alternating baseline/candidate pairs were run. Median summary:

| Scenario | Baseline | Candidate |
|---|---:|---:|
| A6 Feed Reactive | 111.991 ms | **111.826 ms** |
| A11 Keyed PK | 225.37 ms | **217.35 ms** |
| A11b High-card fan-out | 427.35 ms | **229.49 ms** |
| A7 bulk burst | 56.59 ms | **54.38 ms** |
| A7 merge rounds | 3.02 ms | 3.17 ms |

Interpretation:

- `A6` stayed flat
- `A11` improved
- `A11b` stabilized and avoided the bad-tail baseline runs
- `A7` stayed broadly in band, with a small merge-round regression but no
  collapse

## Primary Metrics

- Keyed PK Subscriptions (v1)
- High-Cardinality Stream Fan-out (v1)

## Guardrail Metrics

- Feed Paging (v1) / Reactive feed with 100 concurrent writes
- Sync Burst (v1) / Bulk insert: 50000 rows × 500-row chunks
- Sync Burst (v1) / Merge rounds: 10 × 100 rows

## Decision

Keep this in review.

This is the first stream scheduler change that directly attacked the
measured bottleneck instead of changing timing heuristics around it. The
important learning is:

- stale-rerun churn was mostly a **queue-admission** problem
- the right fix was to coalesce stream work before `ReaderPool`, not to
  add delays after reruns were already in flight

The remaining review question is code complexity versus benefit, not
whether the optimization is hitting the right layer.
