---
title: Persistent Reader Pool Design
slug: 2026-04-10-reader-pool
date: 2026-04-10
summary: After the row representation improved, small reads were dominated by isolate setup, so resqlite moved to persistent reader workers with a separate large-result transfer path.
tags: reader pool, sacrifice path, point queries
tone: amber
---

# Persistent Reader Pool Design

## Problem Statement

The flat-list `ResultSet` fixed the large-result transfer problem, but it exposed a different bottleneck on small reads. Every `select()` still spawned a fresh isolate, ran the query, transferred the result with `Isolate.exit()`, and terminated.

For large result sets, isolate setup was a small fraction of total time. For point queries, it dominated. A one-row lookup should not pay the full cost of creating a fresh isolate.

## Background

The first persistent-pool attempt, [Experiment 011](../../../experiments/011-persistent-reader-pool.md), was rejected because it still moved `List<Map<String, Object?>>` through `SendPort.send()`. Copying maps with repeated column keys erased the benefit of reusing workers.

[Experiment 012](../../../experiments/012-sendport-vs-spawn-deep-dive.md) showed the raw trade-off more carefully. A `SendPort` round trip with no payload was around 6 us, while `Isolate.spawn` plus `Isolate.exit` was around 47-50 us. The pool had a real messaging advantage, but the result representation and protocol overhead had to be small enough for that advantage to survive.

This is the practical difference between a worker pool and a one-shot task helper. Dart isolates communicate by message passing, as described in the [Dart isolate guide](https://dart.dev/language/isolates). [`SendPort.send`](https://api.dart.dev/dart-isolate/SendPort/send.html) lets a long-lived worker reply and then accept more work, but ordinary mutable messages may be copied. [`Isolate.exit`](https://api.dart.dev/dart-isolate/Isolate/exit.html) can transfer ownership of the final message more efficiently, but only because the sending isolate exits. A pool therefore has to decide when keeping the worker alive is worth copying, and when the result is large enough to sacrifice the worker.

The flat-list `ResultSet` changed the economics. A small result was no longer a graph of repeated maps and keys. It was one compact values list plus one shared schema.

## Hypothesis

A persistent reader pool should be faster if it uses two transfer paths:

1. Small results return through `SendPort.send()` so the worker stays alive.
2. Large results return through `Isolate.exit()` so the data transfers without copying, and the sacrificed worker is replaced.

This hybrid should remove spawn overhead for small reads without regressing large-result transfer.

## What We Tried

[Experiment 019](../../../experiments/019-hybrid-reader-pool.md) implemented the hybrid pool. Four reader workers stayed alive. Each query chose a path based on result size:

- Below the threshold: send the `ResultSet` over `SendPort`.
- Above the threshold: call `Isolate.exit(replyPort, resultSet)`, intentionally killing the worker.

The pool then evolved through follow-up experiments:

- [Experiment 030](../../../experiments/030-dedicated-reader-assignment.md) assigned each Dart worker a fixed native reader index, removing the C reader-pool mutex from the hot path.
- [Experiment 039](../../../experiments/039-byte-size-sacrifice-threshold.md) replaced a cell-count sacrifice threshold with a byte-size estimate.
- [Experiment 040](../../../experiments/040-reader-slot-event-port-cleanup.md) simplified the worker protocol to one command port, one event port, and one authoritative pending completer.

## Results

The initial hybrid pool made small reads much faster:

| Rows | One-off `Isolate.exit` | Hybrid pool | Path | Delta |
|---:|---:|---:|---|---:|
| 1 | 0.11 ms | **0.02 ms** | SendPort | 83% faster |
| 10 | 0.13 ms | **0.04 ms** | SendPort | 68% faster |
| 100 | 0.12 ms | **0.04 ms** | SendPort | 64% faster |
| 500 | 0.24 ms | **0.17 ms** | sacrifice | 28% faster |
| 5,000 | 1.83 ms | **1.76 ms** | sacrifice | tied |

Point-query throughput moved from roughly 14K qps to about 45K qps in that experiment.

Dedicated reader assignment then removed redundant native coordination:

| Metric | Before | After |
|---|---:|---:|
| Point query throughput | 37-50K qps | **42-51K qps** |
| CRUD ops/s | 18-23K | 18-23K |
| Read under write | 0.30-0.41 ms | 0.30-0.48 ms |

The later event-port cleanup showed that simplifying the protocol also moved the target metric:

| Metric | Before | After | Result |
|---|---:|---:|---:|
| Point query throughput | 101,010 qps | **116,659 qps** | +15% |
| `select()` maps, 10K rows | 5.60 ms | **4.84 ms** | -14% |

## Outcome

The reader pool was accepted only after the row representation changed. The same architectural idea was a rejection with per-row maps and a win with flat results.

The lesson is that a layer can be correct when introduced and become overhead after the surrounding design changes. Persistence helped by removing isolate setup from small reads, and later wins came from deleting coordination that persistence made redundant.

## Related Experiments

- [Experiment 011: Persistent reader worker pool](../../../experiments/011-persistent-reader-pool.md)
- [Experiment 012: SendPort vs Isolate.spawn deep dive](../../../experiments/012-sendport-vs-spawn-deep-dive.md)
- [Experiment 019: Hybrid reader pool](../../../experiments/019-hybrid-reader-pool.md)
- [Experiment 030: Dedicated reader assignment](../../../experiments/030-dedicated-reader-assignment.md)
- [Experiment 039: Byte-size sacrifice threshold](../../../experiments/039-byte-size-sacrifice-threshold.md)
- [Experiment 040: Reader slot event-port cleanup](../../../experiments/040-reader-slot-event-port-cleanup.md)

## Reference Docs

- [Dart isolates](https://dart.dev/language/isolates)
- [Dart `SendPort.send`](https://api.dart.dev/dart-isolate/SendPort/send.html)
- [Dart `Isolate.exit`](https://api.dart.dev/dart-isolate/Isolate/exit.html)
- [Flutter concurrency and isolates](https://docs.flutter.dev/perf/isolates)
