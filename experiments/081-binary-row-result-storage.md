# Experiment 081: Binary row result storage under `select()`

**Date:** 2026-04-20
**Status:** Rejected

## Problem

`select()` returns row-shaped results as a shared flat `List<Object?>`
backed by `ResultSet` / `Row`. That shape is already lean compared with
materialized maps, but we suspected there might still be headroom in the
result object itself:

- fewer boxed numeric cells
- denser hand-off to the main isolate
- lower RSS on large scans

The question was whether a more compact internal row format could improve
performance without changing the public `List<Map<String, Object?>>`
contract.

## Hypothesis

Replace the flat row-major `List<Object?>` backing store with a row-major
binary representation:

- fixed-width numeric columns stored unboxed in an 8-byte slot slab
- nulls tracked by a bitmap
- object/text/blob values stored in sidecars
- `Row` continues to implement `Map<String, Object?>`

Expected outcome:

- lower hand-off cost for numeric-heavy results
- lower RSS for large scans
- preserved consumer DX (`row['name']`)

## Approach

Prototype branch:
- `lib/src/row.dart`
- `lib/src/query_decoder.dart`
- `test/binary_row_storage_test.dart`

The decoder opportunistically chose a binary-row builder for result sets
with fixed-width numeric columns, falling back to the ordinary flat path
if later rows violated the expected shape. The `Row` facade remained
unchanged from the consumer’s point of view.

To avoid fooling ourselves with a transfer-only win, the profile harness
was extended with:

- `mixed_scan`
- `numeric_scan_consume`
- `mixed_scan_consume`

Those workloads separately measured:

1. `db.select()` return time
2. full row consumption on the main isolate

## Results

Matched control artifact:
- `/tmp/resqlite-exp096-control-profile.json`

Candidate artifact:
- `/tmp/resqlite-exp096-profile.json`

Key deltas versus control:

### Numeric-heavy scans

| Workload | Control | Candidate | Delta |
|---|---:|---:|---:|
| `numeric_scan` select p50 | 3382μs | 2977μs | **-12%** |
| `numeric_scan_consume` select p50 | 3394μs | 2918μs | **-14%** |
| `numeric_scan_consume` consume p50 | 234μs | 1374μs | **+487%** |

### Mixed-schema scans

| Workload | Control | Candidate | Delta |
|---|---:|---:|---:|
| `mixed_scan` select p50 | 3127μs | 3354μs | **+7%** |
| `mixed_scan_consume` select p50 | 3052μs | 3888μs | **+27%** |
| `mixed_scan_consume` consume p50 | 203μs | 997μs | **+391%** |

### Spillover on small results

| Workload | Control | Candidate | Delta |
|---|---:|---:|---:|
| noop reader floor | 7μs | 10μs | **+43%** |
| point query p50 | 7μs | 10μs | **+43%** |

## Decision

Rejected.

The prototype improved transfer/return time for some numeric-heavy scans,
but it did so by making row access substantially more expensive on the
main isolate. That is the wrong trade-off for resqlite’s contract, where:

- `Map`-style row access is the public surface
- main-isolate jank matters
- large results already use `Isolate.exit` for hand-off

The important learning is that a result-object experiment must be judged
on **transfer + consume**, not on `db.select()` return time alone. Once
consumption was measured explicitly, the binary-row direction lost
decisively.

This does **not** mean result transport is fully solved; it means a
generic binary-row replacement for `select()` is not the right path under
the current API contract.
