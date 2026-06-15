# Experiment 170: Synchronous uncontended writer mutex fast-path

**Date:** 2026-06-12
**Status:** Rejected
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** Paired focused + release-suite medians (no Tracelite gate; see Decision).

## Problem

After exp 159 + 161, the residual writer/request wall on A11c overlap is
still the largest bucket (71.8%; exp 147), and the Single Inserts release
row sits at ~3 ms for 100 sequential `await db.execute(...)` calls. Exp
159 named two structural candidates for the remaining floor:

> cross-call request batching (group commit) or a different transport when
> the Dart SDK allows shared-memory result passing.

Both are large. This experiment tested a narrower question first: how
much of the sequential-write residual is plain `async`/`await` scheduling
overhead inside `Writer.execute` itself?

The hot path goes through two microtask hops per write that the
uncontended sequential shape doesn't actually need:

1. `await _mutex.lock()` — `Mutex.lock()` is `async` and always returns a
   `Future` even when `_completer == null`, so `await` schedules a
   microtask before the body resumes.
2. The wrapping `async` on `Writer.execute` — `return reply;` from an
   `async` function unwraps the returned `Future<ExecuteResponse>` via the
   async-state-machine, costing one more scheduling hop on top of
   `Database.execute`'s own `await write()`.

Sequential `await db.execute()` always finds the writer mutex free; both
hops are pure overhead in that case.

## Hypothesis

A `Mutex.tryLock()` that synchronously acquires when uncontended, plus a
non-`async` `Writer.execute` / `Writer.executeBatch` that returns the
reply `Future` directly, should drop one or two microtask hops per write
on the serial-await shape. Concurrent burst (200 calls through
`Future.wait`) should benefit too, because the old code serialized every
call through the mutex's `await _completer.future` chain.

Acceptance criterion (set before running the candidate): the focused
`benchmark/experiments/writer_pipelining.dart` `sequential-awaited (2000
writes)` median moves outside the run-to-run noise band (>5%), with no
regression on `concurrent-burst` or `transaction-guardrail`.

## Approach

`lib/src/mutex.dart`

```dart
bool tryLock() {
  if (_completer != null) return false;
  _completer = Completer<void>();
  return true;
}
```

Never jumps a parked waiter — when `_completer != null` it falls through
so the caller takes the `async` `lock()` slow path, preserving FIFO
fairness.

`lib/src/writer/writer.dart`

- `Writer.execute` and `Writer.executeBatch` become non-`async` and try
  the fast path first: `tryLock()`, sync send through
  `executeInTransaction` / `executeBatchInTransaction`, `unlock()`,
  return the reply `Future` directly.
- A private `_executeSlow` / `_executeBatchSlow` keeps the existing
  `async` shape for the contended path (mid-transaction send racing a
  standalone write, or close racing parked writers).

Behavioral change forced by the fast path: `db.execute()` calls issued
synchronously *before* `db.close()` now all complete through the worker
port FIFO, rather than W2/W3 being rejected by the post-lock-wake
`_closed` re-check. The re-check still fires for the genuinely contended
case (a write parked behind an in-flight transaction when close runs)
and is still covered by the rewritten test
`close() during a contended write lock rejects queued writers without
hanging` in `test/transaction_test.dart`.

No public API change. `Mutex.run` and `Mutex.lock` unchanged; nothing
outside `Writer.execute` / `executeBatch` calls `tryLock`.

## Results

### Focused benchmark (writer_pipelining.dart, 7 rounds, paired runs)

Three paired runs interleaved (baseline / candidate / baseline / candidate / …)
to control for the time-correlated drift `JOURNAL.md` flagged after
exp 159.

| run | sequential-awaited (2000 writes) baseline | candidate | concurrent-burst (10×200) baseline | candidate | transaction-guardrail (50 tx ×10) baseline | candidate |
|---|---:|---:|---:|---:|---:|---:|
| A | 34.268 ms | 34.759 ms | 27.524 ms | 26.981 ms | 4.611 ms | 4.770 ms |
| B | 34.047 ms | 33.442 ms | 27.493 ms | 26.669 ms | 4.714 ms | 4.535 ms |
| C | 33.585 ms | 34.723 ms | 28.119 ms | 27.330 ms | 4.500 ms | 4.929 ms |
| median | **34.047** | **34.723** | **27.524** | **26.981** | **4.611** | **4.770** |
| delta vs baseline | — | **+2.0%** | — | **−2.0%** | — | **+3.4%** |

### Release write suite (writes.dart, 5 warmup + 7 iterations, paired runs)

| run | Single Inserts (100 sequential) baseline | candidate | Concurrent Single Inserts (100 concurrent) baseline | candidate |
|---|---:|---:|---:|---:|
| A | 3.099 ms | 3.153 ms | 1.184 ms | 1.134 ms |
| B | 3.082 ms | 2.982 ms | 1.241 ms | 1.146 ms |
| C | 3.169 ms | 3.501 ms | 1.231 ms | 1.135 ms |
| median | **3.099** | **3.153** | **1.231** | **1.135** |
| delta vs baseline | — | **+1.7%** | — | **−7.8%** |

Concurrent Single Inserts is the row exp 161 promoted specifically to
make this kind of scheduling change visible on a public lane; the
−7.8 % median there is the only signal that survives the noise band on
both the focused and release shapes.

### Tests

`dart test test/database_test.dart test/transaction_test.dart
test/diagnostics_test.dart` — 93 passed. The old
`close() during contention rejects queued writers without hanging` test
was rewritten as two tests (see Approach) to cover both the new
synchronous-before-close behavior and the still-required contended-path
re-check.

## Decision

**Rejected — below current signal on the primary acceptance lane.**

The hypothesis targeted the `sequential-awaited` shape, but the
sequential medians moved +1.7 % to +2.0 % — inside the per-run noise
band on both benchmarks and in the *wrong* direction. The +3.4 % on the
transaction guardrail is also inside noise, but it confirms the
optimization is not buying back overhead the slow path now pays.

The −7.8 % on Concurrent Single Inserts is the only consistent positive
signal across paired runs, but exp 159 already owns this lane and lands
−58 % to −61 % on the same row. A second pass at the same workload that
trades behavioral surface area for a sub-decision-threshold marginal
improvement is not worth merging by itself.

The behavior change (writes issued sync-before-close all succeed instead
of W2/W3 being rejected by the post-lock-wake `_closed` re-check) is
arguably an improvement, but it does not justify shipping a code shape
that adds a slow-path branch without a primary-metric win.

Would reopen if: (a) a future Dart SDK makes `await` over a resolved
`Future` provably more expensive than today (then sequential might
shift), or (b) a workload appears where main-isolate scheduling — not
worker-side execution — is the dominant write cost (Tracelite profile
should show the `sequential-awaited` shape spending much more wall in
main-isolate spans than the writer-handle span; currently it does not).

## Future Notes

- Per exp 159 + 161, the next bounded implementation candidates for the
  sequential-write floor are still cross-call request batching
  (group commit) or a shared-memory transport — both larger than this
  experiment.
- The rewritten `close()` contention test is now structured around a
  long-running transaction holding the lock rather than the mutex's
  microtask hop, so it remains valid regardless of whether a future
  candidate revisits sync-acquire.
- `Mutex.tryLock` is not added to the codebase by this rejection — keep
  the API surface as it was. If a future experiment revisits this idea,
  start from the diff on this branch.
