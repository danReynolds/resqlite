# Experiment 055: Columnar typed arrays for results

**Date:** 2026-04-15
**Status:** Rejected (memory win real but below time-based benchmark floor)

## Problem

Query results use `List<Object?>` in row-major layout. Every int and double is boxed — a 64-bit integer costs ~24 bytes (8 pointer + 16 boxed object) vs 8 bytes in an `Int64List`. For 10,000 rows × 5 numeric columns, that is ~1.2MB vs ~400KB — a 3x memory overhead. This also creates ~50,000 GC-visible objects vs 5 typed arrays.

## Hypothesis

Replace the flat `List<Object?>` with per-column typed arrays: `Int64List` for integer columns, `Float64List` for float columns, `List<String>` for text columns. Expected benefits:
- 75% memory reduction for numeric columns
- 1.8x faster isolate transfer (TypedData `memcpy` vs boxed list deep-copy)
- ~10,000x fewer GC objects for numeric-heavy results
- 10-15% faster row iteration (unboxed access beats pointer chase)

## Research Findings

Detailed benchmarking of Dart VM behavior confirmed the hypothesis:

| Metric | `List<Object?>` | `Int64List` | Ratio |
|---|---|---|---|
| Per-element memory (int) | ~24 bytes | 8 bytes | 3x |
| Allocation 100k elements | 339μs | 11μs | 31x |
| SendPort.send 100k elements | 1,268μs | 285μs | 4.4x |
| Isolate.exit 500k elements | 2,329μs | 820μs | 2.8x |
| GC objects per 10k ints | ~10,001 | 1 | 10,000x |

For realistic mixed-type schemas (2 int + 1 double + 2 string + 1 nullable string), columnar iteration was 1.1-1.4x faster than flat boxed, and isolate transfer was 1.8x faster.

## Why Not Implemented

1. **Throughput is not the bottleneck.** At 10k rows, select() takes 5.57ms. Allocation is ~3% of that. Even a 10x allocation speedup saves ~0.15ms — below the benchmark noise floor.

2. **Memory wins don't show in time-based benchmarks.** The 75% memory reduction is real and valuable for apps, but the benchmark suite measures wall time, not memory. GC pressure differences only manifest under sustained allocation (production workloads), not in isolated benchmark iterations.

3. **Large surface area change.** The `Row` class implements `Map<String, Object?>`. `ResultSet` extends `List<Map<String, Object?>>`. Changing the internal storage requires modifying Row, ResultSet, RowSchema, the decode loop, the sacrifice threshold logic, the hash function, and all stream result caching. The risk of subtle behavior changes outweighs the measurable benefit.

4. **String columns remain boxed.** Dart strings are heap objects regardless. For text-heavy schemas (common in CRUD apps: names, emails, descriptions), there is no memory win for the dominant column type.

5. **The sacrifice threshold already handles transfer cost.** Results >256KB use Isolate.exit (zero-copy). Results <256KB use SendPort (copy). The columnar transfer speedup only matters for the SendPort path, and at <256KB the absolute transfer time is already sub-millisecond.

## Decision

**Rejected — assessed but not implemented.** The memory benefits are real but would require a different benchmark methodology (memory profiling, GC pause tracking) to validate. The throughput benefits are too small relative to the benchmark noise floor to justify the architectural complexity.

**Future consideration:** If memory profiling shows GC pressure from large result sets in production apps, columnar storage would be the right fix. The implementation path is clear: typed column arrays in `RawQueryResult`, schema stores per-column types, `Row` dispatches by column type index. Not architecturally difficult — just not worth the risk for a marginal throughput win.
