---
title: Stream Invalidation Becomes a Subsystem
slug: 2026-04-12-stream-engine
date: 2026-04-12
summary: Reactive queries required their own invalidation engine once dependency capture, dirty-table dispatch, deduplication, and stale-result handling became shared concerns.
tags: StreamEngine, result hashing, fanout
tone: green
---

# Stream Invalidation Becomes a Subsystem

## Problem Statement

The public `stream()` API is small: run a query now, then emit again when writes change the data the query depends on. The implementation was not small. It needed to identify dependencies, receive write invalidations, suppress duplicate work, handle stale results, and keep errors from leaving subscribers hanging.

The problem was no longer "rerun reads after writes." It was to build a stream engine with explicit correctness and performance rules.

## Background

The dependency side uses SQLite's authorizer hook on reader connections. While a stream query runs, SQLite reports table reads. resqlite records those tables instead of maintaining a SQL parser.

The write side uses SQLite's preupdate hook on the writer connection. A completed write response includes the table names it touched. The stream engine intersects those dirty tables with active stream dependencies and schedules re-queries only where needed.

The two hooks solve different halves of the problem. [`sqlite3_set_authorizer()`](https://www.sqlite.org/c3ref/set_authorizer.html) is invoked while SQLite compiles statements and can reveal which tables a statement reads. The [preupdate hook](https://www.sqlite.org/c3ref/preupdate_blobwrite.html) runs around row changes and can identify the tables dirtied by a write. Dart's [stream API](https://dart.dev/libraries/async/using-streams) supplies the public subscription model, but the database layer still needs to decide which streams should receive new events and which reruns are stale or redundant.

That basic loop needed several additional pieces:

- Per-subscriber buffered controllers so broadcast timing did not drop events.
- Generation counters so stale re-query results could not overwrite newer ones.
- Deduplication so identical SQL and params shared one underlying stream entry.
- Error propagation so bad SQL reached subscribers.
- Result-change detection so unchanged results did not emit.

## Hypothesis

Stream work should be reduced before it reaches the main isolate. If an invalidation can be coalesced, rejected, or proven unchanged inside the database/reader machinery, then widgets should not pay for a re-query result that does not change what they render.

## What We Tried

The first stream engine established dependency capture and dirty-table dispatch. Later experiments tightened the expensive cases:

- [Experiment 045](../../../experiments/045-microtask-invalidation-coalescing.md) batched multiple synchronous dirty-table reports into one microtask flush.
- [Experiment 075](../../../experiments/075-native-hash-selectifchanged.md) moved unchanged-result hashing into C so unchanged re-queries could skip Dart decode.
- [Experiment 077](../../../experiments/077-cheap-check-first-sweep.md) added cheap fast-rejects before scheduling unnecessary stream work.
- [Experiment 083](../../../experiments/083-stream-rerun-pre-dispatch-queue.md) moved high-fanout coalescing before `ReaderPool` admission so stale reruns did not pile up waiting for readers.

## Results

Microtask coalescing directly improved the changed-fanout benchmark:

| Benchmark | Baseline | Coalesced | Delta |
|---|---:|---:|---:|
| Fan-out (10 streams) | 0.24 ms | **0.13 ms** | -46% |
| Fan-out main-isolate | 0.24 ms | **0.13 ms** | -46% |
| Invalidation latency | 0.05 ms | 0.04 ms | within noise |

Native unchanged-result hashing targeted a different workload:

| Benchmark | Baseline | Native hash | Delta |
|---|---:|---:|---:|
| Unchanged fanout throughput | 0.44 ms | **0.27 ms** | -39% |
| Invalidation latency, changed result | 0.05 ms | 0.05 ms | within noise |
| Fan-out, changed result | 0.18 ms | 0.22 ms | within noise |

The pre-dispatch queue addressed the high-fanout backlog that ordinary coalescing could not:

| Scenario | Baseline | Pre-dispatch queue |
|---|---:|---:|
| A11 reruns started | 1,024 | **737** |
| A11 stale reruns | 968 | **553** |
| A11 pool wait / rerun | 2,155 us | **0.3 us** |
| A11b high-card fan-out | 427.35 ms | **229.49 ms** |

## Outcome

Streaming became its own subsystem because it had its own failure modes. Correctness depended on dependency capture, generation ordering, and error propagation. Performance depended on doing less work when many streams were invalidated but few results changed.

The detailed architecture walkthrough is [How resqlite Makes Queries Reactive](../streaming.html). The story-level point is that reactive SQLite needed more than a callback after writes; it needed a measured invalidation engine.

## Related Experiments

- [Experiment 045: Microtask invalidation coalescing](../../../experiments/045-microtask-invalidation-coalescing.md)
- [Experiment 075: Native-buffered hash for selectIfChanged](../../../experiments/075-native-hash-selectifchanged.md)
- [Experiment 077: Cheap-check-first sweep](../../../experiments/077-cheap-check-first-sweep.md)
- [Experiment 083: Stream rerun pre-dispatch queue](../../../experiments/083-stream-rerun-pre-dispatch-queue.md)

## Reference Docs

- [Dart streams](https://dart.dev/libraries/async/using-streams)
- [SQLite authorizer callbacks](https://www.sqlite.org/c3ref/set_authorizer.html)
- [SQLite preupdate hook](https://www.sqlite.org/c3ref/preupdate_blobwrite.html)
