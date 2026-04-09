# Experiment 011: Persistent Reader Worker Pool (with Hybrid Sacrificial Exit)

**Date:** 2026-04-07
**Status:** Rejected (thoroughly tested — three approaches tried)

## Problem

Every `select()` call spawns a one-off isolate via `Isolate.spawn` + `Isolate.exit`. The spawn cost (~0.07-0.09ms) is paid per query. For high-frequency small queries (single-row lookups, pagination), this overhead is a significant fraction of total query time.

## Approaches Tested

### Approach A: All results via SendPort.send (persistent workers)

Workers stay alive, all results go through `SendPort.send()` deep copy.

**Results at 5000 rows:**

| Metric | One-off isolates | Persistent pool (SendPort) | Change |
|---|---|---|---|
| select_5k_wall | 3008 μs | 5961 μs | **+98% worse** |
| param_100q_wall | 27130 μs | 51943 μs | **+91% worse** |

**Why it failed:** `SendPort.send()` must serialize the entire object graph (maps with strings), copy to the receiver's heap, and deserialize. This serialization far exceeds `Isolate.exit()`'s validation walk. At 5000 rows, the copy cost is ~3ms — double the total query time with `Isolate.exit()`.

### Approach B: Hybrid — SendPort for small, Isolate.exit for large (sacrificial workers)

Workers use `SendPort.send()` for small results (< 2000 cells) and `Isolate.exit()` for large results (worker dies, pool respawns replacement).

**Results:**

| Metric | One-off | Hybrid | Change |
|---|---|---|---|
| select_5k_wall | 3008 μs | 2890 μs | -4% (uses Isolate.exit, same path) |
| select 10 rows | 0.11 ms | 0.14 ms | +27% worse |
| select 100 rows | 0.11 ms | 0.09 ms | -18% better |

**Why it was inconclusive:** At 5000 rows the hybrid uses `Isolate.exit()` (same as one-off), so it's equivalent. At small sizes, the results are within noise.

### Approach C: Optimized hybrid — direct map building, no intermediate ResultSet

Eliminated the intermediate `ResultSet → Map` conversion. Workers build `Map` objects directly in one pass.

**Component breakdown (measured):**

| Component | Time |
|---|---|
| Bare `Isolate.spawn` + `Isolate.exit` (no work) | 0.070 - 0.091 ms |
| `SendPort` round-trip (no payload) | 0.010 ms |
| `SendPort` round-trip (10 maps) | 0.026 ms |
| **SendPort advantage over spawn** | **~60-80 μs** |

The 60-80μs advantage is real in raw messaging. But in the full query pipeline:

**Rapid-fire benchmark (500 sequential single-row lookups):**

| Approach | Total | Per query |
|---|---|---|
| One-off isolates | **53.4 ms** | **106.7 μs** |
| Hybrid pool | 64.9 ms | 129.8 μs |

**The one-off isolates are 22% faster even for single-row lookups.**

## Analysis

The persistent reader pool fails because:

1. **`SendPort.send()` serialization cost exceeds `Isolate.exit()` validation cost** for any non-trivial object graph. Even 10 maps with strings cost ~16μs to serialize vs ~0μs for `Isolate.exit()` validation of the same objects.

2. **`Isolate.spawn` is cheaper than expected.** Dart's VM-level isolate spawn is highly optimized (~70μs). It's not comparable to OS process creation. The persistent pool only saves this 70μs per query.

3. **The SendPort request serialization adds overhead too.** Sending the SQL string + params to the worker, having the worker receive and deserialize them, then sending the result back — that's two serialization round-trips instead of zero (one-off isolates capture everything in a closure).

4. **The hybrid approach (sacrificial workers) adds respawn complexity.** Detecting dead workers, respawning them, and managing the pool state adds code complexity for marginal-to-negative performance benefit.

5. **At the query sizes where spawn overhead matters (<100 rows), the total query time is already <0.1ms.** Saving 60μs on a 100μs query is meaningful in percentage terms but invisible to users (well under a frame budget).

## Why Rejected

Three approaches tried, all worse than or equal to one-off isolates:
- Pure SendPort: 98% slower at 5k rows
- Hybrid sacrificial: equivalent at large sizes, inconclusive at small
- Optimized hybrid: 22% slower on rapid-fire single-row lookups

The one-off `Isolate.spawn` + `Isolate.exit` architecture is optimal for resqlite's read path across all result sizes.

**Key lesson:** Dart's `Isolate.exit()` ownership transfer is fundamentally cheaper than `SendPort.send()` serialization for complex object graphs. The `Isolate.spawn` cost (~70μs) is a fixed overhead that is always less than the `SendPort.send()` copy cost for any result with strings. Persistent worker pools only make sense when results are trivial primitives (ints, bools) that serialize cheaply.
