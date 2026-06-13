# Experiment 168: Synchronous fast path for uncontended writer mutex

**Date:** 2026-06-13
**Status:** In Review
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** Focused `benchmark/experiments/writer_pipelining.dart`,
three paired passes with stash/pop side-flipping

## Problem

[Exp 159](159-writer-pipelining.md) made the writer's request path
synchronous and pipelined concurrent standalone writes by holding the
write lock only across the send. It still relied on
`await _mutex.lock()` to acquire the mutex, even on the common no-
transaction-in-flight path. `Mutex.lock` is an `async` function whose
implicit Future hops once before resuming the caller — every
uncontended `db.execute` / `db.executeBatch` paid that microtask hop on
its way to `SendPort.send`.

The exp 159 follow-up notes called out the remaining sequential-write
floor explicitly:

> The remaining residual on sequential writes is the round-trip floor
> itself (port wake + event-loop scheduling in both isolates).

Group commit and shared-memory transport are large structural items
under that bucket; this experiment chips off the smaller part: the
per-write scheduling hop that the mutex's `async` wrapper still added,
even when the lock was free.

## Hypothesis

Adding a `Mutex.tryLock()` that returns `true` when the lock can be
acquired without waiting (matching the conventional Java / Rust /
Python / Go spelling for the same primitive), and rewriting
`Writer.execute` / `Writer.executeBatch` as non-`async` around that
fast path, should remove one microtask hop per uncontended standalone
write. Dart's single-threaded execution model makes checking the
completer and claiming the slot in one synchronous call safe.

If the focused `writer_pipelining` `sequential-awaited` median improves
monotonically across paired passes and `transaction-guardrail`
(unchanged code path) stays neutral, the change clears its own bar and
should land. If the sequential delta is inside per-pass noise or
`transaction-guardrail` moves materially, reject the change as below
the floor.

## Approach

### `Mutex.tryLock`

```dart
bool tryLock() {
  if (_completer == null) {
    _completer = Completer<void>();
    return true;
  }
  return false;
}
```

Returns `true` when the lock was acquired synchronously (the caller
owns it and must `unlock` exactly as if it had `await`ed `lock()`);
`false` when the lock is already held. The conventional spelling for
this primitive in `java.util.concurrent.locks.Lock.tryLock`, Rust's
`Mutex::try_lock`, Python's `Lock.acquire(blocking=False)`, and Go
1.18+ `sync.Mutex.TryLock`. The existing `lock()` is unchanged; the
existing `isLocked` getter and `tryLock()` answer the same question
from different sides (one reads, one claims), so the two compose for
callers that want a peek before committing to a claim.

### `Writer.execute` / `Writer.executeBatch`

Both lose their `async` keyword. The body splits into:

1. **Fast path** — `tryLock()` returned `true`. We hold the mutex
   synchronously, check `_closed`, call the
   `executeInTransaction` / `executeBatchInTransaction` send (which
   already runs synchronously through `_request`), unlock, and return
   the reply `Future`. Any synchronous throw (e.g. `_closed` or
   `assertUniformParamSets` from `executeBatchInTransaction`) is
   converted to `Future.error` via a small `try`/`catch` so the public
   contract — `Writer.execute(...)` always returns a `Future` — is
   preserved.
2. **Awaiting-lock path** — `tryLock()` returned `false`. The reply
   path defers to a new `_executeAwaitingLock` /
   `_executeBatchAwaitingLock` `async` helper that `await`s
   `_mutex.lock()`, then mirrors the original try/finally body. This
   matches the old async function's semantics for the contended case
   bit for bit.

`Writer.locked` (used by `Database.transaction`) is intentionally
unchanged — transactions hold the mutex across the whole body and the
microtask hop is dominated by the BEGIN/COMMIT round-trips, so adding
the fast path there would only add code without a measurable signal.
That choice also makes `transaction-guardrail` a clean control
benchmark for this run.

### Test update

`test('close() during contention rejects queued writers without
hanging')` was written to exercise the close-vs-queued-writer race
under the old behavior, where back-to-back `db.execute` calls all
parked on the lock for one microtask while `close()` set `_closed`.
With the fast path, three back-to-back `db.execute` calls each take
the lock and release it synchronously: their `ExecuteRequest`s are
already on the worker's port FIFO before `close()` runs.

The test now uses a long-running transaction to force the queue, then
closes mid-transaction. The original assertion (queued writers wake to
see `_closed` and throw) is preserved; only the trigger changed. A
second new test pins the new fast-path semantics: writes submitted
synchronously before `close()` succeed.

## Results

Focused aggregate:
[`benchmark/profile/results/exp-168-uncontended-write-mutex-fast-path.md`](../benchmark/profile/results/exp-168-uncontended-write-mutex-fast-path.md)

Three paired passes of `benchmark/experiments/writer_pipelining.dart`,
sides swapped between passes (the side under test was stashed/popped
on each side flip):

| shape | baseline cross-pass median | candidate cross-pass median | delta |
|---|---:|---:|---:|
| `sequential-awaited` (2000 writes) | 32.686 ms | 30.868 ms | **-5.6%** |
| `concurrent-burst` (10 × 200 writes) | 25.272 ms | 24.607 ms | **-2.6%** |
| `transaction-guardrail` (50 tx × 10) | 4.282 ms | 4.240 ms | -1.0% (within noise) |

The direction is consistent across all three passes for the two paths
the change touches. Per-pass deltas:

| shape | pass 1 | pass 2 | pass 3 |
|---|---:|---:|---:|
| `sequential-awaited` | -4.0% | -9.0% | -5.0% |
| `concurrent-burst` | -4.4% | -2.6% | -4.8% |
| `transaction-guardrail` | +1.6% | 0.0% | -1.5% |

The transaction guardrail stays inside ±2 % across the three passes —
the expected null result for an untouched code path.

## Decision

**In Review (accept-shaped).**

The change is a focused overhead removal on the per-write floor:

- `sequential-awaited` improves -4 % to -9 % across three independent
  passes (cross-pass median -5.6 %), with rounds 4–7 monotonically
  faster on the candidate side in every pass.
- `concurrent-burst` improves -2.6 % to -4.8 %. The pipelining win
  from exp 159 is the larger effect on this shape; one fewer
  microtask hop per write contributes the remainder.
- `transaction-guardrail` stays neutral, confirming the change does
  not leak into the path that still goes through `Writer.locked`.
- No public API change. The mutex contract (await `lock()` then call
  `unlock()`) is unchanged; `tryLock()` is an additive opt-in.
- Existing transaction / pipeline / FIFO / close-race tests pass
  unchanged. The single test that asserted close-vs-back-to-back race
  semantics is updated to force the queue with a transaction; a new
  test pins the new fast-path semantics.

## Future Notes

- The remaining sequential-write floor is now port-wake +
  reply-handler scheduling. The next structural candidates are
  cross-call request batching (group commit) and shared-memory
  transport when the Dart SDK exposes one — both flagged on exp 159.
- A release-suite A/B (`Single Inserts (100 sequential)` and
  `Concurrent Single Inserts (100 concurrent)` rows that exp 161
  promoted) is the natural soak-window check. CI release runs and PR
  review should watch those two metrics; the focused benchmark used
  here was chosen so the soak run does not need a new public lane.
- `Writer.locked` (transactions) could plausibly use the same
  `tryLock` fast path. It was left untouched here so
  `transaction-guardrail` could serve as a clean control. Revisit if
  a future workload shows the transaction-start microtask hop is
  material.

## Validation

- `dart pub get`
- `dart analyze lib/src/mutex.dart lib/src/writer/writer.dart`
- `dart test test/transaction_test.dart test/database_test.dart
  test/profile_counters_test.dart test/stream_test.dart
  test/stream_invalidation_coalescing_test.dart
  test/stream_dependency_shapes_test.dart
  test/stream_cache_hit_reliability_test.dart
  test/stream_overflow_fallback_test.dart
  test/stream_trigger_cascade_test.dart test/reader_pool_test.dart
  test/query_decoder_test.dart test/diagnostics_test.dart`
- Focused A/B: `dart run benchmark/experiments/writer_pipelining.dart`
  (three paired passes; details in the aggregate above).
