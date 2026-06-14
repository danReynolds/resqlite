# Experiment 168: Resolved runtime cache for Database hot paths

**Date:** 2026-06-14
**Status:** Rejected
**Direction:** `stream-rerun-dispatch`

## Problem

Exp 159 attacked fixed per-round-trip overhead inside `Writer._request` by
caching `_sendPort` and removing the `await _workerPort.future` microtask
hop. It left two structural notes:

- *Sequential-write residual is the round-trip floor itself (port wake +
  event-loop scheduling in both isolates).*
- Further reduction needs *cross-call request batching (group commit) or
  a different transport.*

Every public `Database` method (`select`, `selectBytes`, `execute`,
`executeBatch`, `transaction`) still does
`final ... = await _runtime;` at the top. `_runtime` is a single Future
created in the constructor and completed once reader pool + writer have
spawned. After that point every call awaits an already-resolved Future,
which still schedules its continuation as a microtask. That is one
microtask hop above the writer/reader call, on every Database method
call.

If exp 159's residual is really port-wake + event-loop scheduling, the
same pattern at the layer above should chip another hop off every call.
Whether it actually moves the focused benchmark is the question.

## Hypothesis

Mirror exp 159's `_sendPort` cache one layer up: populate a
sync-readable `_resolvedRuntime` field inside `_runtime`'s body the
moment its spawn awaits complete, and let post-open callers read the
field directly instead of awaiting an already-resolved Future. Removes
one microtask hop per call. At ~1–2 µs per hop the upper bound on
`sequential-awaited (2000 writes)` is ~2–4 ms out of a ~32 ms median:
roughly 6–12% theoretical, comfortably above the focused-benchmark
noise band exp 159 used to accept its win.

## Approach

`lib/src/database.dart`:

- New nullable field `_DatabaseRuntime? _resolvedRuntime`.
- Inside the existing `Future.sync(() async { ... })` body, after
  `ReaderPool.spawn` and `Writer.spawn` complete, assign the runtime
  record to `_resolvedRuntime` before `return runtime`.
- Hot paths replace `final ... = await _runtime;` with
  `final ... = _resolvedRuntime ?? await _runtime;`. Five call sites:
  `select`, `selectBytes`, `execute`, `executeBatch`, `transaction`.
- `close` and `diagnostics` keep their `await _runtime` — they are
  called rarely and benefit nothing.
- `stream` keeps `Stream.fromFuture(_runtime).asyncExpand(...)` — the
  one-shot stream wraps the future, not an `await`, and is invoked
  once per stream creation.

Safety: `_resolvedRuntime` is set inside the same microtask that
completes `_runtime`, so callers awaiting `_runtime` and callers reading
the cache see the same runtime record. There is no "partially
initialized" window observable from main isolate code.

No public API change. No new test scaffolding. No temporary
instrumentation — the implementation is pure overhead removal.

## Results

Focused benchmark: `dart run benchmark/experiments/writer_pipelining.dart`,
two passes, 7 rounds each, order flipped between passes (per the JOURNAL
"phase-ordered A/B" lesson).

| pass | shape | baseline | candidate | delta |
|---|---|---:|---:|---:|
| 1 | sequential-awaited (2000) | 32.169 ms | 31.425 ms | −2.3% |
| 1 | concurrent-burst (10×200) | 24.465 ms | 25.818 ms | +5.5% |
| 1 | transaction-guardrail (50×10) | 4.587 ms | 4.244 ms | −7.5% |
| 2 | sequential-awaited (2000) | 31.794 ms | 32.603 ms | +2.5% |
| 2 | concurrent-burst (10×200) | 24.089 ms | 25.138 ms | +4.4% |
| 2 | transaction-guardrail (50×10) | 4.093 ms | 4.342 ms | +6.1% |

Sequential-awaited flips sign between passes (−2.3% / +2.5%);
transaction-guardrail flips sign with the same magnitude (−7.5% /
+6.1%); concurrent-burst is consistently small-positive (+4–5%) but
inside the round-to-round spread on the same lane.

Excluding round-0 warmup outliers (each shape has a ~2× first-round
spike from cold spawn) does not change the picture: sequential-awaited
moves to −1.5% / +1.7%, same alternating-sign pattern.

`dart analyze lib`: clean. `dart test test/database_test.dart
test/stream_test.dart`: 75/75 pass.

## Decision

**Rejected — below the focused-benchmark noise floor across two
order-flipped passes.** The theoretical 6–12% headroom did not show up
in measured wall time; the deltas alternate sign between passes at the
same magnitude as round-to-round variance on a single phase. That is
the signature of "the optimization is at or below the floor of this
harness," not "the optimization regressed."

No runtime code kept. The implementation pattern (sync field plus null-
coalesce on await) is preserved here as evidence so a future runner can
tell whether their new evidence changes the calculus.

## Future Notes

- The microtask hop in `await _runtime` is real but small relative to
  the writer round-trip (~15 µs in the same harness). Saving one hop
  per call is ~2–4 ms across 2000 sequential writes — at or below this
  harness's per-round spread. Reopen if a future workload measures the
  sequential-write floor cleanly enough to resolve sub-1µs/call deltas
  (e.g., a 10k-write lane with tighter inter-round variance, or a
  Tracelite scenario whose primary metric tracks per-call dispatch
  cost).
- Same shape as the recent rejection cluster around dispatch overhead
  reduction (exp 148, exp 151, exp 145): callback / scheduling counters
  may move but measured-elapsed does not. Once the per-call overhead
  drops below ~2 µs the focused harness can't separate it from machine
  jitter.
- Exp 159's "further reduction needs request batching across calls
  (group commit) or a different transport" remains the correct
  framing: the round-trip floor is the floor, and trimming individual
  microtask hops at the Database layer above the writer does not move
  it. The next candidate in this direction should be group-commit-
  shaped, not hop-shaped.
- Do not retry this exact change without a new measurement system that
  can resolve sub-1µs per-call deltas on real workloads. Repeating the
  measurement against the same harness will reproduce the same
  alternating-sign noise.
