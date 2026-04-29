---
title: Flat-List ResultSet Design
slug: 2026-04-08-flat-list-resultset
date: 2026-04-08
summary: resqlite's row representation changed from per-row `LinkedHashMap` instances to a shared schema plus one flat value list, reducing transfer-graph size while preserving the map API.
tags: ResultSet, Row facade, read path
tone: green
---

# Flat-List ResultSet Design

## Problem Statement

The false starts made the shape of the solution clearer. resqlite did not need a clever byte format that pushed decode back to the UI isolate, and it did not need to give up the row-map API. It needed to stop storing every row as a separate mutable map when query results are more regular than that.

The read path no longer looked limited by SQLite execution. Native connection state, statement caching, and mutex reductions had helped, but `List<Map<String, Object?>>` still produced a large transfer graph. resqlite needed a row representation that preserved the map-like API without paying for one mutable hash map per row.

## Background

Database result rows have a constrained shape:

- Every row in a result has the same columns.
- Rows are immutable after query completion.
- Most access is by column name, iteration, or JSON encoding.
- Column names can be shared across the whole result.

That shape does not require a full `LinkedHashMap` for every row. The public API could remain map-like while the storage became specialized for query results.

The SQLite side of this path is the normal prepared-statement loop: compile SQL with [`sqlite3_prepare_v2()` or `sqlite3_prepare_v3()`](https://www.sqlite.org/c3ref/prepare.html), call [`sqlite3_step()`](https://www.sqlite.org/c3ref/step.html) until it stops returning rows, and read each column with the [`sqlite3_column_*()` family](https://www.sqlite.org/c3ref/column_blob.html). resqlite was not trying to replace that lifecycle. The question was what Dart shape should be built from those column values before the result crossed isolates.

That distinction matters for FFI-heavy libraries. SQLite already exposes row values one statement step at a time. A wrapper can either mirror that row shape directly into Dart maps, or it can recognize that column metadata is stable across the result and store values in a representation better suited to transfer and iteration.

## Hypothesis

If values are stored in one flat row-major list and column metadata is shared once, then `Isolate.exit()` will validate far fewer structural objects. The main isolate can still expose `Map<String, Object?>` behavior by creating cheap row facades on demand.

## What We Tried

[Experiment 008](../../../experiments/008-flat-list-lazy-resultset.md) built the representation in three steps. The design deliberately changed storage first and presentation second:

1. Store all row values in one `List<Object?>`.
2. Store column names and the name-to-index map in one shared `RowSchema`.
3. Create lightweight `Row` objects lazily when callers access `result[i]`.

The storage layout is simple:

```text
values = [row0_col0, row0_col1, ..., row0_colN, row1_col0, ...]
```

`Row` implements `Map<String, Object?>`, but lookup is:

1. Find the column index in the shared schema.
2. Compute `rowOffset + columnIndex`.
3. Return the value from the flat list.

Values are still decoded on the worker. The main isolate does not decode UTF-8 or materialize SQLite values; it creates only small facades.

## Results

The 20,000-row benchmark showed the representation change clearly:

| Implementation (20,000 rows) | Wall | Main | vs sqlite3 |
|---|---:|---:|---:|
| `LinkedHashMap` + `Isolate.exit` | 24.95 ms | 1.57 ms | +12% slower |
| Flat list + eager rows | 19.39 ms | 1.74 ms | -12% faster |
| Flat list + lazy `ResultSet` | **18.03 ms** | **2.52 ms** | **-13% faster** |
| sqlite3 baseline | 20.65 ms | 20.65 ms | - |

Main-isolate time across sizes confirmed that the design matched the Flutter constraint:

| Rows | resqlite main | sqlite3 main | sqlite_async main |
|---:|---:|---:|---:|
| 1,000 | **0.10 ms** | 0.79 ms | 0.17 ms |
| 5,000 | **0.47 ms** | 3.90 ms | 0.87 ms |
| 20,000 | **2.52 ms** | 20.65 ms | - |

The structural object count dropped from hundreds of thousands of map-related objects to a small set of shared containers plus the actual values.

## Outcome

The flat-list `ResultSet` became the core read-path representation. It kept the caller-facing API ordinary while removing the per-row map infrastructure from the isolate transfer graph.

The broader engineering lesson was that API shape and storage shape do not have to be the same. resqlite could expose map-like rows without storing rows as maps.

This was the first major positive turn in the story. With large result transfer under control, the next bottleneck moved to the other end of the size spectrum: tiny reads were still paying too much to create one-off workers.

## Related Experiments

- [Experiment 008: Flat value list with lazy ResultSet](../../../experiments/008-flat-list-lazy-resultset.md)
- [Experiment 032: Row Map facade overrides](../../../experiments/032-row-map-facade.md)

## Reference Docs

- [SQLite prepared statements](https://www.sqlite.org/c3ref/prepare.html)
- [SQLite statement stepping](https://www.sqlite.org/c3ref/step.html)
- [SQLite column access APIs](https://www.sqlite.org/c3ref/column_blob.html)
- [Dart C interop with `dart:ffi`](https://dart.dev/interop/c-interop)
