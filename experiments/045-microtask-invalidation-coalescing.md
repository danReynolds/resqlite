# Experiment 045: Microtask invalidation coalescing

**Date:** 2026-04-15
**Status:** Accepted

## Problem

In `StreamEngine.handleDirtyTables` (stream_engine.dart:68), each write dispatches re-queries immediately. When multiple rapid `db.execute()` calls happen synchronously (e.g., a loop of inserts without an explicit transaction), each triggers a separate invalidation pass. If 5 inserts each dirty the same table, a stream watching that table gets 5 re-queries — only the last result matters.

The `reQueryGeneration` counter already handles correctness (stale results are discarded), but the redundant re-queries waste reader pool capacity.

## Hypothesis

Accumulate dirty tables within a Dart microtask and flush once. The Dart event loop provides a natural coalescing boundary: `scheduleMicrotask` fires after the current synchronous work completes. Multiple `handleDirtyTables` calls within the same synchronous execution batch are unioned into a single invalidation pass.

## Approach

```dart
Set<String>? _pendingDirtyTables;
bool _flushScheduled = false;

void handleDirtyTables(List<String> dirtyTables) {
  if (dirtyTables.isEmpty) return;
  _writeGeneration++;

  // Accumulate dirty tables.
  if (_pendingDirtyTables == null) {
    _pendingDirtyTables = Set<String>.from(dirtyTables);
  } else {
    _pendingDirtyTables!.addAll(dirtyTables);
  }

  if (!_flushScheduled) {
    _flushScheduled = true;
    scheduleMicrotask(_flushDirtyTables);
  }
}

void _flushDirtyTables() {
  _flushScheduled = false;
  final tables = _pendingDirtyTables;
  _pendingDirtyTables = null;
  // ... existing invalidation logic using `tables`
}
```

## Results

**18 wins, 0 regressions** (3 repeats vs baseline).

| Benchmark | Baseline (ms) | Coalesced (ms) | Delta |
|---|---|---|---|
| Fan-out (10 streams) | 0.24 | 0.13 | **-46%** |
| Fan-out [main] | 0.24 | 0.13 | **-46%** |
| Invalidation latency | 0.05 | 0.04 | -20% (within noise) |

The fan-out improvement is the direct signal: the benchmark performs rapid sequential writes that trigger multiple invalidations on the same stream set. Coalescing reduces these to a single re-query dispatch per microtask.

## Decision

**Accepted.** Clean 46% improvement on the fan-out benchmark with zero regressions. The change is a strict behavioral improvement — fewer redundant re-queries, less reader pool contention — with no observable latency increase for single-write scenarios (invalidation latency unchanged).

Correctness is preserved by `_writeGeneration` and `reQueryGeneration` — stale results from in-flight re-queries are already discarded on arrival.
