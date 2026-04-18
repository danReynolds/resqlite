# Experiment 079: Batch-scoped stream invalidation coalescing

**Date:** 2026-04-18
**Status:** Planned

## Problem

The Sync Burst (A7) benchmark exposes a surprising emission-count gap:

| Library | Sync Burst `COUNT(*)` emissions (100 batches × 500 rows + 10 merge rounds) |
|---|---|
| resqlite       | 103 |
| sqlite_async   | 110 |
| drift          | **2** |

Drift's active stream fires only twice across the entire burst, while
ours fires once per batch commit. Same workload, same schema, same
invalidation contract (every commit that touches the watched table
must eventually produce an emission). Drift is doing some form of
aggressive stream-side coalescing that we don't.

This matters because Sync Burst models a realistic pattern — offline-
first clients applying batched server deltas while the local UI shows
live counts. Every emission is a UI-thread wake-up; going from 103
to ~2 would be a material win for sync-heavy Flutter apps.

We already have two layers of coalescing:

1. **Microtask-level**: `handleDirtyTables` accumulates into
   `_pendingDirtyTables` and defers to `scheduleMicrotask`, so
   multiple writes within one synchronous batch collapse. But
   consecutive `await peer.executeBatch(...)` calls yield between
   microtasks — each batch is its own tick, so microtask coalescing
   doesn't help.
2. **Per-stream re-query coalescing (PR #17)**: de-duplicates
   concurrent re-query dispatches per stream via `writeGen`. Prevents
   re-query pile-up but doesn't reduce emission count when dispatches
   are serialized across ticks.

Neither helps here. Drift has a third layer that we're missing.

## Hypothesis

Drift's `customSelect().watch()` stream emits on a Dart
`StreamController` that's connected to its `StreamQueryStore` via a
listener. One of these paths applies a coalescing window — likely a
microtask- or scheduleMicrotask-based "emit only the last value per
tick" behavior. When 100 `batch()` commits happen over ~60ms of wall
time, the resulting notifications either (a) collide within the
`StreamController`'s update window, or (b) get throttled by drift's
`StreamQueryStore.updatedTables` → `ValueStream` → listener path
such that rapid updates only produce one final emission per listener
tick.

We should replicate the stream-side coalescing: if a stream would
re-query and emit a result that's equal to the result of a more
recent scheduled re-query, skip the intermediate emission.

This is distinct from hash suppression (exp 075) which skips emission
when the result is byte-identical to the *previous emission*. The new
mechanism skips re-query *results* that are logically superseded by a
newer pending re-query for the same stream.

## Approach

### Phase 1: Diagnostic (before any code)

Before we change anything, characterize drift's actual mechanism so
we replicate the right thing:

1. **Instrument the Sync Burst benchmark for both peers** with
   timestamps of: commit-time, invalidation-scheduled-time, re-query-
   started-time, emission-delivered-time per batch. Goal: understand
   where drift drops the 98 "missing" emissions.

2. **Read drift's `StreamQueryStore.updatedTables` implementation**
   in `~/.pub-cache/hosted/pub.dev/drift-2.32.1/lib/src/runtime/data_stream.dart`
   (or wherever the stream-update machinery lives). Extract the exact
   coalescing mechanism.

3. **Hypothesis-or-refute the three candidate mechanisms**:
   - **(a) Throttle/debounce at stream level**: drift has a default
     emit-rate limiter. If so, we'd need to match the throttle interval
     for fairness — and consider whether to apply it ourselves.
   - **(b) Isolate round-trip batching**: drift's async-isolate worker
     accumulates notifications and sends them on some interval, not
     per-commit. If so, our writer isolate could do the same.
   - **(c) Stream-side "last-value wins per event loop tick"**:
     drift's `StreamController.add` is deduped by the listener seeing
     only the most recent value per microtask. If so, we need to
     replicate at the stream boundary.

   Deliverable: a short note (500 words) in the experiment file
   that identifies the exact mechanism with a line-by-line source
   citation.

### Phase 2: Implementation (after diagnostic)

Details depend on Phase 1. Sketch:

**If mechanism is (a) throttle:**
- Add an opt-in `Stream<T> stream(sql, {Duration? coalesce})` parameter
- Default `coalesce = null` (current behavior — emit on every commit)
- When set, use `StreamTransformer.fromHandlers` with a debounce that
  drops intermediate emissions when a newer one is scheduled within
  `coalesce`
- Concern: might hide real state changes the user expects to see.
  Not a default.

**If mechanism is (b) writer isolate batching:**
- In `write_worker.dart`, accumulate `dirtyTables` across N batches
  with a flush on `Future.microtask` or a short (100μs) yield
- Concern: delays all stream re-queries by up to the flush window,
  including ones that would've completed faster. Measure before/after
  on A11b high-card fan-out to ensure no regression there.

**If mechanism is (c) stream-side last-value wins:**
- In `_scheduleReQuery`, if there's already a pending re-query AND
  the most recent emission was the current result, drop the
  intermediate re-query entirely
- Pairs well with the `writeGen` counter from PR #17 — the stream
  entry already tracks "has a newer write happened since the last
  emission". If the re-query result equals the last emission's hash
  AND `writeGen` was bumped, skip the emission.
- This is the cleanest layer; doesn't add latency, doesn't change
  user-facing API.

My bet based on drift's architecture is (c) — drift's
`StreamController` with its customSelect wiring naturally coalesces
because it uses `broadcast()` + microtask-scheduled add calls.

### Phase 3: Measurement

Primary metric: **Sync Burst COUNT(*) emissions on resqlite**
(target: single-digit count, matching drift's 2–5 range).

Secondary metrics (regression guards):
- **A11b High-Cardinality Fan-out** wall time (current: 247ms).
  Must not regress — this is the PR #17 regression guard. If batch-
  coalescing adds latency to sub-millisecond re-query dispatches,
  this benchmark catches it.
- **A11 Keyed PK Subscriptions** emissions (current: 0 hits thanks
  to hash suppression). Must stay 0.
- **A5 Chat Sim** per-op wall times. Must not regress.
- **Reactive Feed (A6 Part B)** emissions (current: 0 via hash
  suppression on the top-50). Must stay 0.

Tertiary:
- No new invalidation races. Verify with the
  `benchmark_keyed_pk_subscriptions_test.dart` correctness path —
  the committed PRNG seed hits 3 watched PKs; we currently emit 0
  (hash suppression). Post-change: should still emit 0.

### Acceptance bar

Accept if:
1. Sync Burst emissions drop below 10 (from 103) on resqlite
2. No regression >5% on any other reactive benchmark
3. No correctness failures in the test suite (emission counts
   remain within the existing assertions)
4. New mechanism is documented with a commit invariant comment
   in `stream_engine.dart`

Reject if:
- The mechanism adds observable latency to individual writes'
  invalidation (A11b regresses)
- The implementation requires API surface changes that users would
  need to opt into (undermines the "just works" reactive story)
- The savings don't generalize — if it only helps the Sync Burst
  pattern without helping realistic sync workloads

## Why not the drift default throttle approach?

Drift's default behavior is NOT to throttle — the stream emits on
every notifyUpdates. The coalescing emerges from drift's Dart-side
plumbing, not an explicit throttle call. That makes it safe to
replicate: users don't need to set a throttle duration, and we don't
need to pick a default value.

## Prior art

- **Experiment 045**: microtask invalidation coalescing — collapsed
  rapid sequential writes into one pass per microtask. Same *idea*
  scaled smaller. Exp 079 extends this to cross-microtask boundaries.
- **Experiment 075**: native hash-based unchanged result suppression
  — skips emission when the result byte-identical to previous.
  Complementary: 079 addresses "should even re-query?" where 075
  addresses "should emit what we re-queried?"
- **PR #17**: per-stream re-query coalescing (writeGen counter).
  Complementary: PR #17 ensures at most one in-flight re-query per
  stream; 079 ensures the re-query results that DO complete are
  the only ones users see.

## Rough effort estimate

- Phase 1 (diagnostic): 2–4 hours. Code instrumentation + reading
  drift internals.
- Phase 2 (implementation): depends on mechanism. (c) is ~50 LOC
  in `stream_engine.dart`. (b) is ~100 LOC in writer + stream engine.
  (a) is an API change, skip if avoidable.
- Phase 3 (measurement): 30 min for benchmark run + write-up.

Total: one experiment cycle.

## Out of scope

- Changing drift's behavior to use it as a "baseline" — we're learning
  from drift, not matching it
- Introducing a user-facing throttle parameter on `stream()`
- Touching the preupdate hook or authorizer pipeline
- Any changes to hash suppression (exp 075) or PR #17's write-gen
  coalescing

## Open questions

- Does the mechanism also help the Reactive Feed (A6 Part B) workload?
  Currently resqlite emits 0 there thanks to hash suppression; unclear
  if 079's mechanism would stack or no-op.
- What's the interaction with interactive `transaction()` calls? If
  a user does `await tx.execute(...); await tx.select(...); await
  tx.execute(...)` — does the intra-transaction `tx.select` see a
  stale snapshot if we defer notification too aggressively? Need to
  verify the mechanism only affects *external* stream notifications,
  not intra-transaction reads.
- What if drift's mechanism is "just" its StreamController's natural
  broadcast behavior, and not something we can replicate without
  restructuring our entry-level stream? Then the experiment may need
  to be rejected with "no cheap fix" as the takeaway.
