---
title: Optimization After the Read Path Stabilized
slug: 2026-04-22-follow-up-optimization
date: 2026-04-22
summary: Once the main read-path architecture was stable, later experiments focused on stream fanout, write-path allocation, benchmark coverage, and reusable research records.
tags: benchmark process, allocation, experiment log
tone: amber
---

# Optimization After the Read Path Stabilized

## Problem Statement

After the core architecture settled, the project stopped being a search for one breakthrough and became a discipline problem. There were still performance wins available, but they were smaller, more workload-dependent, and easier to misread.

Once point queries reached the 100K qps range and large reads had a stable representation, more read-path experiments became harder to interpret. Many changes were small enough to disappear into benchmark noise, and some improvements on synthetic workloads did not help app-shaped scenarios.

The project needed a stronger process for deciding what to try, what to reject, and which benchmark signal should count.

## Background

The early project had obvious bottlenecks: main-isolate work, isolate transfer graphs, per-query spawn overhead, and per-row map storage. Later work was different. The remaining opportunities were spread across stream fanout, transaction setup, parameter allocation, memory behavior, and benchmark coverage. The project needed a way to keep learning without accepting every local improvement as a global win.

That meant each experiment needed a sharper hypothesis and a clearer acceptance bar. A small optimization should not be accepted only because one benchmark moved once. It needed to move the workload it structurally targeted, avoid regressions elsewhere, and leave behind useful evidence even when rejected.

The repository's benchmark process became part of the design. The [benchmark methodology](../../../benchmark/METHODOLOGY.md) separates workload types and measurement concerns, while the [experiment index](../../../benchmark/EXPERIMENTS.md) keeps the accepted and rejected records discoverable. This matters because the same micro-optimization can look good in isolation and still be wrong for a stream fanout, transaction, or application-shaped workload.

## Hypothesis

The highest-value work after the read path stabilized would come from:

1. Optimizing adjacent systems such as streams and writes.
2. Adding benchmarks that isolate realistic workloads.
3. Recording rejected ideas well enough that future work does not repeat them.

## What We Tried

The experiment log became the primary research artifact. Accepted, rejected, and in-review experiments all kept the same basic shape: problem, hypothesis, implementation approach, results, and decision.

The later optimization pass included both wins and deliberate rejections:

- [Experiment 083](../../../experiments/083-stream-rerun-pre-dispatch-queue.md) attacked stream reruns before they entered `ReaderPool`.
- [Experiment 095](../../../experiments/095-writer-result-buffer.md) tested a persistent native writer result buffer and rejected it.
- [Experiment 100](../../../experiments/100-bounded-stream-requery-scheduler.md) tested bounded stream scheduling and rejected it after app-shaped fanout regressed.
- [Experiment 101](../../../experiments/101-tx-stmt-cache.md) accepted cached transaction-control statements.
- [Experiment 109](../../../experiments/109-inline-param-buffer.md) accepted inline-packed text/blob parameter storage.

The project also added [experiments/signals.json](../../../experiments/signals.json), a machine-readable map of research directions, prior evidence, and what future agents should watch.

## Results

The important pattern is visible in the accepted and rejected records:

| Experiment | Decision | Load-bearing result |
|---|---|---|
| 083 pre-dispatch stream queue | In review | A11b high-card fan-out 427.35 ms -> **229.49 ms** |
| 095 persistent writer result buffer | Rejected | Full suite: 0 wins, 14 regressions, 139 neutral |
| 100 bounded stream scheduler | Rejected | High-cardinality stream fan-out 236.54 ms -> **479.42 ms** regression |
| 101 cached tx statements | Accepted | Batched write in tx 0.59 ms -> **0.52 ms** |
| 109 inline param buffer | Accepted | Single inserts 1.88 ms -> **1.61 ms**; batch insert 10K 4.21 ms -> **3.68 ms** |

The rejected experiments were not failures of the process. They were the process working: they preserved the hypothesis, the benchmark result, and the reason not to carry the change forward.

## Outcome

The documentation split became intentional:

- `experiments/` is the lab notebook.
- `experiments/signals.json` is the research map.
- `experiments/JOURNAL.md` is the transferable lesson file.
- `doc/stories/` is the curated chronological history.

The early read-path results made the project direction clear. The later optimization and process work made that direction repeatable. Future stories should keep that pattern: state the problem, identify the hypothesis, describe what changed, and show the benchmark signal that justified the decision.

The final story in this sequence is different. It is not about accepting a resqlite optimization. It is about how a real application failure tested whether the project could debug below its own abstractions when the obvious database explanation was wrong.

## Related Experiments

- [Experiment 083: Stream rerun pre-dispatch queue](../../../experiments/083-stream-rerun-pre-dispatch-queue.md)
- [Experiment 095: Persistent writer result buffer](../../../experiments/095-writer-result-buffer.md)
- [Experiment 100: Bounded stream re-query scheduler](../../../experiments/100-bounded-stream-requery-scheduler.md)
- [Experiment 101: Cached transaction statements](../../../experiments/101-tx-stmt-cache.md)
- [Experiment 109: Inline-packed parameter buffer](../../../experiments/109-inline-param-buffer.md)

## Reference Docs

- [Benchmark methodology](../../../benchmark/METHODOLOGY.md)
- [Experiment index](../../../benchmark/EXPERIMENTS.md)
- [Research signals](../../../experiments/signals.json)
