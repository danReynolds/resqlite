# Experiment 073: Single-slot schema-cache fast-path

**Date:** 2026-04-16
**Status:** Rejected (no measurable impact)

## Problem

On every call to `decodeQuery`, the worker does two `LinkedHashMap` operations
against `schemaCache` for LRU tracking:

```dart
var schema = schemaCache.remove(sql);     // op 1
if (schema != null) {
  schemaCache[sql] = schema;              // op 2  (promote MRU)
} else { ... }
```

Originally proposed as **stmt-pointer-keyed schema cache** (key by `stmt.address`
to avoid the SQL string hash/equality), but pointer reuse after C-cache
eviction introduces a real correctness gap. The safer equivalent is a
single-slot fast-path keyed on `identical(sql, lastSchemaSql)`.

## Hypothesis

For hot loops where the same SQL string instance is reused, `identical()`
is a pointer compare and avoids both map operations. Expected savings
~20 ns per query — worth measuring.

## Approach

Added a single-slot fast-path in `query_decoder.dart`:

```dart
String? _lastSchemaSql;
RowSchema? _lastSchema;

if (identical(sql, _lastSchemaSql)) {
  schema = _lastSchema!;
} else {
  // existing Map lookup path
  _lastSchemaSql = sql;
  _lastSchema = schema;
}
```

Correctness preserved: `identical()` misses fall through to the regular
Map path unchanged. Different String instances with identical content
still hit via the map.

All 126 tests pass.

## Results

Benchmarked with `--repeat=5` against `round1-baseline-stable.md`.

Every relevant benchmark was **within noise**:

| Benchmark | Baseline (ms) | exp050 (ms) | Verdict |
|---|---:|---:|---|
| Point Query Throughput (qps) | 136,054 | 97,599 | within noise (±61% MAD) |
| Select → Maps / 10 rows | 0.01 | 0.01 | no change |
| Select → Maps / 1000 rows | 0.39 | 0.40 | within noise |
| Select → Maps / 10000 rows | 5.22 | 5.56 | within noise |
| Streaming / Invalidation Latency | 0.04 | 0.06 | within noise (±50% MAD) |
| Streaming / Stream Churn | 1.63 | 2.38 | within noise (±40% MAD) |

## Why It Didn't Move the Needle

Dart `String` objects cache their `hashCode`. For a SQL string reused from
the same call-site, both the existing path and the fast-path do the same
effective work — a cached-hash Map lookup with identity-compare short
circuit. The nominal ~20 ns saved is well below the measurement floor of
the existing benchmarks.

The fast-path would likely show its worth when:

1. The `schemaCache` is near its 32-entry cap — full map lookup has more
   bucket work than a single slot.
2. The workload cycles through many distinct SQLs but revisits each.

Neither scenario is exercised by the default suite — most suites use ≤ 10
distinct SQL strings, and the map is never full.

## Decision

Rejected for the default benchmark suite. The change is correct and low
risk; it could be revisited alongside a dynamic-SQL benchmark that
actually saturates the cache.

## Follow-ups

- Add a "dynamic SQL" benchmark (many distinct literal strings, cache at
  capacity) before revisiting this or any cache-sizing experiments.
- If that benchmark motivates it, the **stmt-pointer-keyed** variant with
  a C-side eviction counter (shared-memory Int32 that Dart reads before
  each lookup) becomes the structurally cleaner approach.
