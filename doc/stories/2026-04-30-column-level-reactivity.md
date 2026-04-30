---
title: Column-Level Reactivity
slug: 2026-04-30-column-level-reactivity
date: 2026-04-30
summary: Column-level dependency tracking moves stream invalidation from broad table wakeups toward query-aware dispatch, while table-level invalidation remains the correctness fallback.
tags: reactive streams, SQLite hooks, benchmark
tone: green
---

# Column-Level Reactivity

## Problem Statement

Reactive SQLite usually starts with table-level invalidation: if a stream reads `tasks`, any write to `tasks` wakes it. That rule is correct, but it is broader than the query actually observes. A stream selecting `id`, `title`, and `done` does not need to re-run when a write only changes `sync_state`.

Before this work, resqlite already had two useful pieces: table dependency tracking to know which streams might be affected, and native result hashing to suppress unchanged emissions after a re-query. That made the public behavior clean, but it still paid the writer-side fan-out cost. Under many active streams, a write could dispatch work to every watcher on a table, only for the hash check to discover later that most results had not changed.

The missing optimization belonged earlier in the pipeline: when a write is provably column-disjoint from a stream, the stream should not be scheduled at all.

## Background

SQLite gives enough information to build that rule without adding a SQL parser. The [`sqlite3_set_authorizer()` callback](https://www.sqlite.org/c3ref/set_authorizer.html) reports table and column names while a statement is compiled. On the reader side, those `SQLITE_READ` events reveal the columns a stream query can observe. On the writer side, update statements reveal which columns are assigned. The [`sqlite3_preupdate_hook()`](https://www.sqlite.org/c3ref/preupdate_blobwrite.html) then confirms which tables actually changed at runtime.

That division matters because dependency tracking has two layers with different jobs:

| Layer | Role | Failure behavior |
|---|---|---|
| Table dependencies | Correctness boundary | Unknown tables mean "invalidate broadly." |
| Column dependencies | Dispatch optimization | Unknown columns mean "fall back to table-level." |

If table dependencies are unavailable, resqlite treats the write as affecting everything. If column dependencies are unavailable, it falls back to table-level invalidation. Overflow, allocation failure, trigger-only writes, or missing column metadata can cost extra work, but they must not create a stale stream.

## Hypothesis

Column-aware stream invalidation should improve writer throughput under many-stream fan-out when writes touch columns outside the active projections. The same benchmark must still force overlapping writes to re-query, so the optimization cannot hide real changes.

## What Changed

The native layer now records table-column pairs during reader statement prepare and writer statement prepare. Writer execution combines that prepared-statement column metadata with preupdate-hook table facts. Dart receives a structured `TableDependencies` value whose entries can be:

- a table dependency with no column detail, meaning "this table changed";
- a table-column dependency with fixed column names, meaning "these columns on this table changed";
- an all-tables dependency, used when the table set itself is unknown.

`StreamEngine` still indexes active streams by table first. When a write shares a table with a stream and both sides have fixed column details for that table, it checks the column intersection. Empty intersection means the stream is skipped. Any uncertainty reverts to the older table-level behavior.

INSERT and DELETE still behave as table-wide invalidations. Even if individual column values are known, row membership changed, so every projection over that table can observe the mutation.

## Results

The April 30, 2026 MacBook Pro release run includes two useful signals. The first is a guardrail: do disjoint writes stay quiet while overlapping writes still wake the stream? The second is the real performance question: does writer-side dispatch get cheaper when 50 active streams are column-disjoint from the write?

`Streaming (Column Granularity)` verifies the correctness shape:

| Scenario | resqlite re-emits |
|---|---:|
| Disjoint column writes | 0 |
| Overlapping column writes | 10 |

That table is not the whole story. Result hashing can also suppress unchanged emissions after work has already been scheduled. The stronger signal is `Many-Streams Writer Throughput`, which measures writer-side fan-out with 50 active streams:

| Library | Disjoint/sec | Overlap/sec | Ratio |
|---|---:|---:|---:|
| resqlite | 6752 | 4503 | 0.667x |
| sqlite_async | 2062 | 2009 | 0.975x |
| drift | 211 | 108 | 0.510x |

The resqlite spread is the intended signature. Disjoint writes avoid stream dispatch, while overlapping writes still do the work because the selected result can change. `sqlite_async` is close to a 1.0 overlap/disjoint ratio, which means it performs nearly the same writer-side work in both cases. Drift is much slower overall in this workload; its ratio is lower, but at 211 writes/sec disjoint and 108 writes/sec overlap it is not showing the same high-throughput dispatch-elision shape.

Compared with the experiment baseline for the same 50-stream workload, Experiment 106 raised resqlite's disjoint writer throughput from 3956 to 7201 writes/sec in the isolated experiment run while leaving overlap essentially unchanged. The release run settles at 6752 disjoint writes/sec and 4503 overlap writes/sec, which is the production benchmark signal after the feature landed.

## Outcome

Column-level reactivity is now a user-visible feature, not only an internal optimization. A stream no longer has to wake up for every write to a table it mentions; when SQLite can prove the write touches unrelated columns, resqlite keeps the stream idle.

The important engineering contract is conservative degradation: precision is optional, correctness is not. Column metadata may disappear and fall back to table-level invalidation, but a missed dependency must not become a stale stream.

The practical mental model is:

- SELECT dependencies describe what a stream can observe.
- UPDATE dependencies describe what a write claims to modify.
- The preupdate hook confirms that a table actually changed.
- Only when both sides are concrete and disjoint does dispatch get skipped.

## Related Experiments

- [Experiment 052: Column-level dependency tracking](../../../experiments/052-column-level-dependencies.md)
- [Experiment 075: Native-buffered hash for selectIfChanged](../../../experiments/075-native-hash-selectifchanged.md)
- [Experiment 106: Column-level dependency dispatch elision](../../../experiments/106-column-level-deps.md)

## Reference Docs

- [April 30 benchmark run](../../../benchmark/results/2026-04-30T13-39-30-MacBook Pro 14in.md)
- [Benchmark scope](../../../benchmark/SCOPE.md)
- [SQLite authorizer callbacks](https://www.sqlite.org/c3ref/set_authorizer.html)
- [SQLite preupdate hook](https://www.sqlite.org/c3ref/preupdate_blobwrite.html)
