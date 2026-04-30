---
title: Column-Level Reactivity
slug: 2026-04-30-column-level-reactivity
date: 2026-04-30
summary: Column-level dependency tracking lets resqlite skip stream work when writes touch columns a query cannot observe, while table-level tracking remains the correctness fallback.
tags: reactive streams, SQLite hooks, benchmark
tone: green
---

# Column-Level Reactivity

## Problem Statement

Reactive SQLite usually starts with table-level invalidation: if a stream reads
`tasks`, any write to `tasks` wakes it. That is correct, but it is broader than
the query actually observes. A stream selecting `id`, `title`, and `done` does
not need to re-run when a write only changes `sync_state`.

resqlite already had table dependency tracking and native result hashing.
Hashing suppressed unchanged emissions, but it still paid the writer-side
dispatch and re-query scheduling cost. The missing feature was earlier in the
pipeline: when a write is provably column-disjoint from a stream, the stream
should not be dispatched at all.

## Background

SQLite gives enough information to build that rule without adding a SQL parser.
The authorizer callback reports table and column names while a statement is
compiled. On the reader side, that reveals the columns a stream query can
observe. On the writer side, it reveals the columns a prepared mutation intends
to change. The preupdate hook then confirms which tables actually changed at
runtime.

The important design constraint is that these two dependency layers do not have
the same job:

- Table dependencies are the correctness layer.
- Column dependencies are an optimization layer.

If table dependencies are unavailable, resqlite treats the write as affecting
everything. If column dependencies are unavailable, it falls back to table-level
invalidation. That means overflow, allocation failure, trigger-only writes, or
missing column metadata can cost extra work, but they do not create a stale
stream.

## Hypothesis

Column-aware stream invalidation should improve write throughput under
many-stream fan-out when writes touch columns outside the active projections.
The same benchmark should still force overlap writes to re-query, so the
optimization cannot hide real changes.

## What Changed

The native layer now records table-column pairs during reader statement prepare
and writer statement prepare. Writer execution combines that prepared-statement
column metadata with preupdate-hook table facts. Dart receives a structured
`TableDependencies` value whose entries can be either:

- a table dependency with no column detail, meaning "this table changed";
- a table-column dependency with fixed column names, meaning "these columns on
  this table changed";
- an all-tables dependency, used only when the table set itself is unknown.

`StreamEngine` indexes active streams by table first. When a write shares a
table with a stream and both sides have fixed column details for that table, it
checks the column intersection. Empty intersection means the stream is skipped.
Any uncertainty reverts to the older table-level behavior.

INSERT and DELETE still behave as table-wide invalidations. Even if individual
column values are known, row membership changed, so every projection over that
table can observe the mutation.

## Results

The April 30, 2026 MacBook Pro release run includes both the micro signal and
the many-stream writer signal.

`Streaming (Column Granularity)` verifies the correctness shape:

| Scenario | resqlite re-emits |
|---|---:|
| Disjoint column writes | 0 |
| Overlapping column writes | 10 |

`A11c Many-Streams Writer Throughput` measures writer-side fan-out with 50
active streams:

| Library | Disjoint writes/sec | Overlap writes/sec | Overlap/disjoint |
|---|---:|---:|---:|
| resqlite | 6,752 | 4,503 | 0.667 |
| sqlite_async | 2,062 | 2,009 | 0.975 |
| drift | 211 | 108 | 0.510 |

The resqlite spread is the intended signature. Disjoint writes avoid stream
dispatch. Overlapping writes still do the work because the selected result can
change.

## Outcome

Column-level reactivity is now a user-visible feature, not only an internal
optimization. A stream no longer has to wake up for every write to a table it
mentions; when SQLite can prove the write touches unrelated columns, resqlite
keeps the stream idle.

The safety contract is the part worth preserving as the code evolves:
precision is optional, correctness is not. Column metadata may disappear and
fall back to table-level invalidation, but a missed dependency must not become a
stale stream.

## Related Experiments

- [Experiment 052: Column-level dependency tracking](../../../experiments/052-column-level-dependencies.md)
- [Experiment 075: Native-buffered hash for selectIfChanged](../../../experiments/075-native-hash-selectifchanged.md)
- [Experiment 106: Column-level dependency dispatch elision](../../../experiments/106-column-level-deps.md)

## Reference Docs

- `benchmark/results/2026-04-30T13-39-30-MacBook Pro 14in.md`
- [Benchmark scope](../../../benchmark/SCOPE.md)
- [SQLite authorizer callbacks](https://www.sqlite.org/c3ref/set_authorizer.html)
- [SQLite preupdate hook](https://www.sqlite.org/c3ref/preupdate_blobwrite.html)
