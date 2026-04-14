# Experiment 040: Reader Slot Event Port Cleanup

**Date:** 2026-04-14
**Status:** Accepted

## Problem

The reader pool had accumulated protocol complexity that no longer matched the
real invariants of the system.

At this point the pool already guaranteed:

1. one in-flight request per worker
2. synchronous request handling inside the worker isolate
3. worker respawn on sacrifice

But the implementation still carried extra protocol/state:

- a per-request reply port
- a separate per-worker control port
- duplicated slot state via `_alive` and `_busy`

That meant more moving pieces in the hot read path than the model actually
needed.

## Hypothesis

Collapse the protocol down to the real invariants:

- one command port into the worker
- one event port back to the pool for that worker lifetime
- one `_pendingCompleter` as the authoritative in-flight state

This should:

- simplify the slot state machine
- reduce `RawReceivePort` churn
- remove duplicated bookkeeping
- slightly improve small-read overhead

## What Changed

In `lib/src/reader/read_worker.dart` and `lib/src/reader/reader_pool.dart`:

- removed `replyPort` from `ReadRequest`
- changed the worker to receive one persistent event `SendPort` at spawn time
- merged normal replies, sacrifice payloads, and `onExit` notifications onto one
  per-worker event port
- removed redundant `_alive` and `_busy` flags
- made `_pendingCompleter` the authoritative "in-flight request" bit
- kept respawn boundaries intact by recreating the event port per worker
  lifecycle

The resulting slot state is now just:

- `_sendPort` — worker can accept commands
- `_pendingCompleter` — worker has one request in flight
- `_eventPort` — replies and lifecycle events for this worker lifetime
- `_closed` — do not respawn during shutdown

## Benchmark

Full suite, 3 repeats:

- Current: [benchmark/results/2026-04-14T10-22-58-event-port-cleanup.md](../benchmark/results/2026-04-14T10-22-58-event-port-cleanup.md)
- Baseline: [benchmark/results/2026-04-14T09-32-07-fresh-run.md](../benchmark/results/2026-04-14T09-32-07-fresh-run.md)

Comparison summary:

- 6 wins
- 0 regressions
- 57 neutral

Read-path highlights:

| Metric | Before | After | Result |
|---|---:|---:|---|
| Point query throughput | 101,010 qps | 116,659 qps | **+15% win** |
| `select()` maps, 10K rows | 5.60 ms | 4.84 ms | **-14% win** |
| `selectBytes()`, 1K rows | 0.50 ms | 0.49 ms | within noise |
| `selectBytes()`, 10K rows | 6.05 ms | 5.88 ms | within noise |
| Concurrent reads | mixed | mixed | within noise |

The strongest measured signal is improved per-query dispatch overhead, which is
exactly where this cleanup was expected to help.

## Decision

**Accepted** — this is both a code-quality and a performance win.

The protocol now matches the actual semantics of the reader pool more closely,
and the benchmark confirms that the simplification did not trade correctness for
speed. The gain is not dramatic, but it is real, targeted, and comes with less
state to reason about in the slot lifecycle.
