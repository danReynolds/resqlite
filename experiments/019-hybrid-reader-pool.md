# Experiment 019: Hybrid Reader Pool (SendPort + Sacrificial Isolate.exit)

**Date:** 2026-04-08
**Status:** Accepted
**Commit:** [`e07d95b`](https://github.com/danReynolds/dune/commit/e07d95b)

## Hypothesis

A persistent reader pool eliminates the ~80μs isolate spawn overhead per query.
For small results, SendPort.send (copy) is cheaper than the spawn cost saved.
For large results, the worker sacrifices itself via Isolate.exit (zero-copy)
and the pool auto-respawns a replacement.

## Design

- 4 persistent reader isolates spawned on Database.open
- Workers receive queries via SendPort, execute on C reader pool
- After query, check `rows * cols > 1500`:
  - Below threshold: `replyPort.send(resultSet)` — worker stays alive
  - Above threshold: `Isolate.exit(replyPort, resultSet)` — worker dies, pool respawns
- Both paths use the same flat `ResultSet` format (from shared `query_worker.dart`)
- Exit port on each worker detects death and auto-spawns replacement
- C reader connections persist across worker deaths (managed by C pool)

## Key Insight

Previous experiment 011 rejected the pool because it used `List<Map>` via SendPort,
which copies string keys per row. Using `ResultSet` (flat `List<Object?>` + `RowSchema`)
dramatically reduces the copy cost — the flat list contains only primitive values
(int/double/String/null), and RowSchema is shared across all rows.

## Results

| Rows | Isolate.exit | Hybrid Pool | Path | Delta |
|---:|---:|---:|:---|:---|
| 1 | 0.11ms | 0.02ms | SendPort | **83% faster** |
| 10 | 0.13ms | 0.04ms | SendPort | **68% faster** |
| 50 | 0.12ms | 0.04ms | SendPort | **68% faster** |
| 100 | 0.12ms | 0.04ms | SendPort | **64% faster** |
| 500 | 0.24ms | 0.17ms | Sacrifice | **28% faster** |
| 1000 | 0.40ms | 0.39ms | Sacrifice | tied |
| 5000 | 1.83ms | 1.76ms | Sacrifice | tied |

**Point query: 45k qps** (was 14k) — beats sqlite_reactive's 37k qps.

## Why It Works Now (When Experiment 011 Rejected It)

Experiment 011 used `List<Map<String, Object?>>` for SendPort transfer. Each map
contains N string keys that must be serialized per row. At 5k rows × 6 columns,
that's 30k extra string copies.

This experiment uses `ResultSet` — a flat `List<Object?>` with a single `RowSchema`
containing column names once. SendPort copies the flat list (primitives only) and
the schema (6 strings). The copy cost is proportional to value count, not value
count × key count.

## Code Changes

- New `query_worker.dart` — shared FFI bindings and query execution logic
- New `reader_pool.dart` — hybrid pool with sacrifice + auto-respawn
- `database.dart` — adds `selectPool()`, spawns pool on open
