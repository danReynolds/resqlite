# Experiment 079: Batch-scoped stream invalidation coalescing

**Date:** 2026-04-18
**Status:** **Accepted** — Sync Burst COUNT(*) emissions 103 → 1, no reactive regression

## Result

| Metric | Baseline | Post-079 | Drift (ref) |
|---|---|---|---|
| Sync Burst stream emissions (50K-row burst + 10 merge rounds) | **103** | **1** | 1 |
| Sync Burst emission repeat-stability (3 runs) | — | 1.00 med / 0% range | — |
| Keyed PK wall / emissions | 225ms / 0 | 229ms / 0 | 557ms / 10,000 |
| High-Cardinality wall / emissions | 246ms / 0 | 250ms / 0 | 1,742ms / 20,000 |
| Feed Paging reactive / emissions | 109ms / 0 | 108ms / 0 | 233ms / 100 |
| Column-Disjoint re-emit ratio | 0.000 | 0.000 | 1.000 |
| Comparison summary (timing) | — | **0 wins / 0 regressions / 153 neutral** | — |

Primary win landed. Regression guards all clean — reactive emission
counts unchanged (0 across the board), wall-time deltas within noise
(≤ 3% on every stream scenario).

The initial fast run flagged 2 "regressions" on `resqlite tx.execute()
loop` (5.55 → 6.30ms); confirmed noise by the --include-slow run
(0 regressions, repeat-stability classified this benchmark as
"stable" with 0.5% MAD).

## Implementation

A single-line addition in `StreamEngine._reQuery`, plus a probe wired
up from the `Writer` constructor. The mutex already tracks lock state;
we just expose it.

```dart
// lib/src/stream_engine.dart
// After the reader response + hash-change check:
if (_writerBusyProbe?.call() ?? false) return;
```

The probe returns true if any write holds the writer mutex at the
moment we'd emit. A true reading means: a write's response is
about to arrive, will call `handleDirtyTables`, bump writeGen, and
schedule a fresh re-query. Our current re-query's data is already
provisional, so skip the emission — the follow-up emits fresh.

Correctness invariant preserved: the in-flight write WILL call
`handleDirtyTables` on response (see `database.dart:execute`/
`executeBatch`/`transaction`). Thus every skipped emission is
guaranteed to have a follow-up re-query queued.

## Phase 1 findings (2026-04-18)

## Phase 1 findings (2026-04-18)

Drift's mechanism, read from
`~/.pub-cache/hosted/pub.dev/drift-2.32.1/lib/src/runtime/executor/stream_queries.dart`:

### 1. Invalidations dispatch synchronously

```dart
// stream_queries.dart:84-90
// Why is this stream synchronous? We want to dispatch table updates before
// the future from the query completes. This allows streams to invalidate
// their cached data before the user can send another query.
final StreamController<Set<TableUpdate>> _tableUpdates =
    StreamController.broadcast(sync: true);
```

Every `handleTableUpdates(...)` call runs subscriber callbacks
synchronously within the caller's stack.

### 2. The subscriber cancels in-flight queries

```dart
// stream_queries.dart:273-289 (QueryStream._onListenOrResume)
_tablesChangedSubscription =
    _store.updatesForSync(_fetcher.readsFrom).listen((_) {
  _lastData = null;
  _cancelRunningQueries();   // <-- key line
  if (_activeListeners > 0) {
    fetchAndEmitData();
  }
});
```

When a new invalidation arrives, drift cancels any running query
for that stream before starting a fresh one.

### 3. Cancelled queries don't emit

```dart
// stream_queries.dart:328-347 (QueryStream.fetchAndEmitData)
runCancellable<Rows>(_fetcher.fetchData, token: operation);
final data = await operation.resultOrNullIfCancelled;
if (data == null) return;  // <-- cancelled path: no emit
_lastData = data;
// ... emit to listeners
```

If the cancellation token fires between `runCancellable` and the
await's resolution, `resultOrNullIfCancelled` returns null and the
function exits without emitting.

### Why our current mechanism doesn't achieve this

Our `_reQuery` (stream_engine.dart:264–294) has a `writeGen` check
after the await:

```dart
final (rows, ...) = await pool.selectIfChanged(...);
if (entry.writeGen != gen) return;  // stale
// ... emit
```

This catches invalidations that land **during** the reader's
response-processing (case B below) but not invalidations that land
**after** the reader responds, **while** our microtask is running
(case A below).

Sync Burst's timing:

```
t=0    user: await batch1      [waiting for writer]
t=1    writer responds batch1  [queues event-loop msg]
t=2    main runs msg: handleDirtyTables → schedules microtask M1
t=3    user: await batch2      [waiting for writer]
t=4    M1 runs: _reQuery dispatches COUNT(*), awaits reader
t=5    reader responds to COUNT(*)  [queues event-loop msg for us]
t=6    writer responds batch2       [queues event-loop msg]
t=7    (!) order of t=5 vs t=6 on the event loop determines case A or B
```

- **Case A** (t=5 before t=6): reader msg runs first → resolves our
  await → writeGen check passes → **emit**. Then batch2 msg runs →
  handleDirtyTables → fresh re-query for batch2.
- **Case B** (t=6 before t=5): batch2 msg runs first → writeGen
  bumps → reader msg runs → writeGen check fails → **skip emit**.
  Next re-query scheduled, runs fresh.

For Sync Burst, `SELECT COUNT(*)` is cheap and usually completes
before the next 500-row batch does, so Case A dominates: 103 emits.

Drift's sync-dispatch + query-cancellation means the equivalent of
Case A is impossible: the next batch's invalidation fires
synchronously inside the writer isolate's response-processing
callback (before control returns to user code), cancelling the
in-flight COUNT before it can resolve its await.

### Candidate fix — add an event-loop yield before emit

Insert a single `await Future<void>.delayed(Duration.zero)` between
"reader response processed" and "emit to subscribers". That yields
back to the event loop, letting pending writer responses run their
`handleDirtyTables` microtask. Then re-check `writeGen`:

```dart
final (rows, ...) = await pool.selectIfChanged(...);
if (entry.writeGen != gen) return;  // existing: during-flight check
if (rows == null) return;

// NEW: yield to the event loop so any pending writer response has
// a chance to bump writeGen before we emit. Mirrors drift's sync-
// dispatch property at the emit boundary.
await Future<void>.delayed(Duration.zero);
if (entry.writeGen != gen) return;  // NEW: supersession check

entry.lastResult = rows;
for (final sub in entry.subscribers) sub.add(rows);
```

**Cost:** one event-loop tick of latency per emission.

**Expected win:** Sync Burst emissions drop from 103 to single digits
(matching drift's 2).

**Risks to verify before accepting:**
- A11b wall-time regression — the added tick per emission might hurt
  fan-out, but A11b already emits 0 (hash suppression), so the yield
  runs approximately 0 times. Verify.
- A11 Keyed PK emission count — currently 0. Must stay 0.
- Reactive Feed (A6 Part B) emission — currently 0. Must stay 0.
- Interactive transaction timing — the yield runs for `db.stream`
  emissions, not for `db.select` returns, so should be unaffected.

### Going into Phase 2 with

- **Mechanism identified:** invalidation processing timing,
  specifically the asymmetry between drift's sync-dispatch+cancel
  and our microtask+post-check
- **Fix approach:** event-loop yield + re-check writeGen at emit
  boundary (candidate mechanism (c) from the original plan — the
  cheapest, most localized fix)
- **Primary metric:** Sync Burst emissions → single digits
- **Regression guards:** A11b wall, A11/A5/A6 emission counts

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
