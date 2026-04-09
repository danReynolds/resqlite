# Experiment 008b: Byte-Backed Lazy Maps (ByteBackedResultSet)

**Date:** 2026-04-06
**Status:** Rejected as default (informed the flat-list design)

## Problem

`Isolate.exit` validation walks O(n) Dart objects. Transferring a single `Uint8List` is O(1). Could we transfer results as bytes and wrap them in lazy `Map` objects on main that decode from the buffer on access?

## Hypothesis

Worker sends results as a `Uint8List` (O(1) transfer). Main wraps in `ByteBackedResultSet` where each `ByteBackedRow` implements `Map<String, Object?>` and decodes values from the byte buffer lazily. For partial access (e.g., Flutter ListView rendering 20 visible items from 20,000), this would be dramatically faster than materializing all maps.

## What We Built

`ByteBackedResultSet` — backed by a `Uint8List` containing the compact binary row format from `resqlite_query_to_rows`. Pre-computed cell offsets for O(1) field access. `ByteBackedRow` decodes values via `ByteData.getInt64/getFloat64` and `utf8.decode` on demand.

## Results

At 20,000 rows:

| Path | Wall | Main |
|---|---|---|
| Direct maps + Isolate.exit | 27.45 ms | **2.12 ms** |
| ByteBackedResultSet (full access) | **11.92 ms** | 7.29 ms |
| ByteBackedResultSet (20 rows only) | **4.50 ms** | **0.01 ms** |

### The trade-off

- **Wall time:** ByteBackedResultSet wins (11.92ms vs 27.45ms) by eliminating the Isolate.exit validation cliff
- **Partial access main-isolate:** ByteBackedResultSet wins spectacularly (0.01ms for 20 visible rows)
- **Full access main-isolate:** Direct maps win (2.12ms vs 7.29ms) because maps arrive pre-built

The 7.29ms on main for full access comes from `utf8.decode` and value construction happening on the main isolate — the expensive kind of lazy.

## Why Rejected as Default

Our guiding principle: minimize main-isolate work above all else. A library can't predict how callers will access data, but it can guarantee the main isolate doesn't do heavy lifting. The byte-backed approach moved decode work to main, violating this principle for the full-access case.

## What It Taught Us

1. The `Isolate.exit` validation cost is real and large at 20k+ rows (8.44ms)
2. Transferring a Uint8List is O(1) — the validation cliff is avoidable
3. "Lazy" is only good if what you defer is cheap — utf8.decode is not cheap
4. The solution needed to reduce the validation cost WITHOUT moving decode to main

These insights directly led to the flat-list approach (experiment 008), which achieves the reduced object count (low validation cost) while keeping values pre-decoded (no main-isolate decode work).
