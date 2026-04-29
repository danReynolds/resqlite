---
title: Writer Isolate and Invalidation Data
slug: 2026-04-16-write-path
date: 2026-04-16
summary: The persistent writer isolate serialized SQLite mutations, preserved transaction state, and produced the dirty-table data used by reactive queries.
tags: writer isolate, preupdate hook, batch execution
tone: violet
---

# Writer Isolate and Invalidation Data

## Problem Statement

SQLite in WAL mode supports many concurrent readers but only one writer. resqlite needed to preserve that serialization rule, keep write work off the main isolate, support interactive transactions, and report the dirty-table facts that reactive streams depend on.

The write path was therefore not just a queue of `execute()` calls. It was the owner of mutation order, transaction state, and invalidation data.

## Background

Three shapes were considered:

1. Run writes on the main isolate.
2. Spawn a one-off isolate for each write.
3. Keep a persistent writer isolate that owns the write connection.

The persistent writer matched SQLite's model best. It processes write messages sequentially and keeps transaction state alive across calls. That matters for interactive transactions, where `BEGIN`, multiple reads/writes, nested savepoints, and `COMMIT` all need one consistent writer context.

The writer also owns the preupdate hook. As SQLite mutates rows, resqlite records touched table names. When the write finishes, the response includes affected rows, last insert ID, and the dirty-table set consumed by the stream engine.

The SQLite constraints are explicit here. In [write-ahead logging mode](https://www.sqlite.org/wal.html), readers and a writer can overlap, but there is still only one active writer. SQLite's [transaction rules](https://www.sqlite.org/lang_transaction.html) also make transaction lifetime meaningful: a `BEGIN`, subsequent statements, savepoints, and `COMMIT` have to run against a coherent connection state. resqlite's writer isolate maps that native constraint onto Dart by giving mutation work one owner.

The hot path is still the ordinary prepared-statement API. Parameters are attached with the [`sqlite3_bind_*()` family](https://www.sqlite.org/c3ref/bind_blob.html), statements are stepped, reset, and reused, and transaction-control SQL can be executed either through [`sqlite3_exec()`](https://www.sqlite.org/c3ref/exec.html) or cached prepared statements. The experiments below are about reducing repeated work in that lifecycle, not changing SQLite's serialization model.

## Hypothesis

A persistent writer isolate should make write behavior easier to reason about, and native batching should keep write throughput competitive despite the isolate boundary. If the writer also returns dirty tables with each completed mutation, stream invalidation can stay tied to the write that caused it.

## What We Tried

The core design put all mutations on a single writer isolate and moved batch execution into native code. `executeBatch()` serializes parameter sets into native storage, crosses the FFI boundary once, and lets C loop through bind, step, reset, and commit.

Several follow-up experiments then reduced fixed costs:

- [Experiment 014](../../../experiments/014-writer-tuning.md) accepted `BEGIN IMMEDIATE` and removed redundant `sqlite3_clear_bindings`, while rejecting `locking_mode=EXCLUSIVE` because it blocked readers.
- [Experiment 101](../../../experiments/101-tx-stmt-cache.md) replaced repeated `sqlite3_exec("BEGIN/COMMIT/ROLLBACK")` calls with cached transaction-control statements.
- [Experiment 109](../../../experiments/109-inline-param-buffer.md) packed text/blob parameter bytes into the reusable parameter buffer and passed explicit UTF-8 lengths to SQLite.

## Results

The baseline write path was already fast enough that many single changes fell near the noise floor. The later accepted wins were concentrated where the hypothesis predicted: transaction boundaries and bind-heavy workloads.

Cached transaction statements removed repeated prepare/finalize work:

| Workload | Baseline | Cached tx statements | Delta |
|---|---:|---:|---:|
| Batched write inside transaction, 100 rows | 0.59 ms | **0.52 ms** | -13% |
| Growing-stream invalidation, batch insert 100 | 0.60 ms | **0.52 ms** | -14% |
| Interactive transaction | 0.05 ms | 0.05 ms | within noise |

Inline-packed parameters removed per-text/blob native allocations and skipped SQLite's internal `strlen` walk:

| Workload | Baseline | Inline param buffer | Delta |
|---|---:|---:|---:|
| Single inserts, 100 sequential | 1.88 ms | **1.61 ms** | -14% |
| Batch insert, 10,000 rows | 4.21 ms | **3.68 ms** | -13% |
| Batched write inside transaction | 0.43 ms | **0.39 ms** | -10% |
| No-streams write throughput, 200 inserts | 4.03 ms | **3.40 ms** | -16% |

The rejected piece in Experiment 014 is also part of the evidence. `PRAGMA locking_mode=EXCLUSIVE` looked attractive as a writer optimization, but it caused `SQLITE_BUSY` on reader connections. That made it incompatible with the reader-pool architecture.

## Outcome

The writer isolate remained a first-class subsystem because it owns three connected responsibilities:

1. Execute mutations in SQLite's single-writer order.
2. Preserve transaction semantics across async calls.
3. Publish dirty-table data for reactive streams.

The deeper walkthrough is [How resqlite Writes Data](../writing.html). The experiment record shows that the durable write-path wins came less from changing SQLite semantics and more from removing repeated setup from hot paths.

## Related Experiments

- [Experiment 014: Writer connection tuning](../../../experiments/014-writer-tuning.md)
- [Experiment 101: Cached transaction statements](../../../experiments/101-tx-stmt-cache.md)
- [Experiment 109: Inline-packed parameter buffer](../../../experiments/109-inline-param-buffer.md)

## Reference Docs

- [SQLite write-ahead logging](https://www.sqlite.org/wal.html)
- [SQLite transactions](https://www.sqlite.org/lang_transaction.html)
- [SQLite value binding APIs](https://www.sqlite.org/c3ref/bind_blob.html)
- [SQLite one-step execution interface](https://www.sqlite.org/c3ref/exec.html)
