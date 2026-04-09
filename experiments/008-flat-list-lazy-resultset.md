# Experiment 008: Flat Value List with Lazy ResultSet

**Date:** 2026-04-06
**Status:** Accepted (the breakthrough)
**Commit:** [`a18492c`](https://github.com/danReynolds/dune/commit/a18492c), [`666da73`](https://github.com/danReynolds/dune/commit/666da73)

## Problem

At 20,000 rows, the `Isolate.exit()` validation walk cost 8.44ms — 38% of total `select()` time. Investigation revealed the Dart VM's `MessageValidator` walks every heap object in the transfer graph. A `LinkedHashMap` with 6 entries creates ~8-10 internal objects (hash table buckets, linked list entries, key-value nodes). For 20,000 rows: 160,000-200,000 internal objects to validate.

## Hypothesis

Query result rows are immutable, fixed-schema, and read-only. They don't need `LinkedHashMap`'s hash table or insertion-order linked list. Replacing them with a simpler structure would reduce the object count in the `Isolate.exit` graph, cutting validation time.

## What We Built

Three changes, each building on the previous:

### 1. Flat value list
All rows' values stored in a single `List<Object?>`:
```
values = [row0_col0, row0_col1, ..., row0_colN, row1_col0, ...]
```

### 2. Lightweight Row class
`Row` implements `Map<String, Object?>` via `MapMixin`. Looks up column index in a shared `RowSchema` (one small map for the whole result set), then indexes into the flat list. No per-row hash table.

### 3. Lazy Row creation
`ResultSet` creates `Row` objects on-demand when `result[i]` is accessed, not on the worker. Row creation is just 3 field assignments (list ref, schema ref, offset int) — nanoseconds. The actual values are already fully decoded in the flat list.

`Isolate.exit` transfers: 1 ResultSet + 1 RowSchema + 1 List<Object?> + actual values = **~3 structural objects** instead of ~200,000.

## Results

### Progression at 20,000 rows

| Implementation | Wall | Main | vs sqlite3 |
|---|---|---|---|
| LinkedHashMap + Isolate.exit | 24.95 ms | 1.57 ms | +12% slower |
| Flat list + eager Row wrappers | 19.39 ms | 1.74 ms | -12% faster |
| **Flat list + lazy ResultSet** | **18.03 ms** | **2.52 ms** | **-13% faster** |
| sqlite3 (baseline) | 20.65 ms | 20.65 ms | — |

### Main-isolate time across sizes

| Rows | resqlite main | sqlite3 main | sqlite_async main |
|---|---|---|---|
| 1,000 | **0.10 ms** | 0.79 ms | 0.17 ms |
| 5,000 | **0.47 ms** | 3.90 ms | 0.87 ms |
| 20,000 | **2.52 ms** | 20.65 ms | — |

### Why the lazy ResultSet doesn't hurt main-isolate time

Unlike the ByteBackedResultSet (experiment 008b), the lazy `Row` creation is trivial — 3 field assignments, no decode work. The values in the flat list are already fully-decoded Dart `String`/`int`/`double` objects built on the worker. Main-isolate time for accessing a row is nanoseconds, not microseconds.

## Why Accepted

This was the single most impactful optimization in the entire project. Reducing the `Isolate.exit` object graph from ~200k to ~3 structural objects was more impactful than C-native query execution, NOMUTEX, or connection pooling. It transformed resqlite from 12% slower than sqlite3 to 13% faster.

**Key lesson:** The number of Dart heap objects matters more than their size for `Isolate.exit` performance. Data structure choice had more impact than any systems-level optimization.
