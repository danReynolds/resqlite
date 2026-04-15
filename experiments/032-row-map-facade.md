# Experiment 032: Row Map Facade Overrides

**Date:** 2026-04-09
**Status:** Accepted

## Problem

`resqlite`'s transport/result shape is strong: one shared `RowSchema`, one flat
values list, and lazy `Row` wrappers. But `Row` itself uses `MapMixin`, and
many of the default `MapBase` operations are intentionally skeletal rather than
optimal.

That means `Row` can be excellent at transport and still pay avoidable cost on
the main isolate for common `Map`-style operations like:

- `containsKey`
- `forEach`
- `entries`
- `values`
- `Map.from(row)`

## Hypothesis

Keep the transport shape exactly as-is, but override the hot `Map` members on
`Row` so they operate directly on the flat values list instead of going through
generic `MapMixin` behavior.

This should improve main-isolate row consumption without hurting the isolate
transfer story that makes `ResultSet` fast in the first place.

## What We Built

In `lib/src/row.dart`:

- override `containsKey`
- override `containsValue`
- override `length`, `isEmpty`, `isNotEmpty`
- override `values`
- override `entries`
- override `forEach`
- add lightweight custom iterables for `values` and `entries`

Importantly:

- `ResultSet` shape did not change
- `RowSchema` shape did not change
- `row.keys` still uses schema names directly

## Benchmark

Added targeted microbenchmark:

- `benchmark/experiments/row_map_facade.dart`

This compares `resqlite` `Row` against a `LinkedHashMap` built from the same row
data for the operations we care about.

### Before

| Case | Row median (ms) | Map median (ms) | Delta (ms) |
|---|---:|---:|---:|
| hot lookup | 5.732 | 5.299 | +0.433 |
| containsKey | 16.266 | 9.806 | +6.460 |
| iterate keys + lookup | 12.600 | 14.741 | -2.141 |
| forEach | 15.207 | 6.994 | +8.213 |
| entries iteration | 15.162 | 9.029 | +6.133 |
| values iteration | 20.146 | 4.931 | +15.215 |
| Map.from clone | 7.246 | 5.896 | +1.350 |

### After

| Case | Row median (ms) | Map median (ms) | Delta (ms) |
|---|---:|---:|---:|
| hot lookup | 5.683 | 5.189 | +0.494 |
| containsKey | 11.545 | 9.170 | +2.375 |
| iterate keys + lookup | 12.352 | 14.484 | -2.132 |
| forEach | 6.670 | 6.892 | -0.222 |
| entries iteration | 8.024 | 8.911 | -0.887 |
| values iteration | 3.233 | 4.943 | -1.710 |
| Map.from clone | 5.261 | 5.838 | -0.577 |

## Result

This is a clear improvement.

The transport shape already seemed right. The problem really was the
main-isolate `MapMixin` facade.

What improved materially:

- `containsKey`: much closer to `LinkedHashMap`
- `forEach`: now slightly faster than `LinkedHashMap`
- `entries`: now faster than `LinkedHashMap`
- `values`: major improvement, now faster than `LinkedHashMap` in the latest run
- `Map.from(row)`: now slightly faster than `Map.from(map)`

What did not change much:

- direct hot `row['field']` lookups
- the existing `keys + lookup` path, which was already good

## Why Accepted

This keeps the best part of the current design — the result transport shape —
while making `Row` behave much more like a performant `Map` on the main
isolate.
