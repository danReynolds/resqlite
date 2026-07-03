# Exp 213: Transaction body write coalescing moonshot

**Date:** 2026-07-03
**Status:** Rejected
**Category:** Moonshot
**Direction:** `transaction-control-paths`
**Benchmark Run:** none (focused-harness experiment; no release-suite metric maps to `Future.wait([tx.execute(...) x N])` inside `db.transaction()`)
**Archive:** [`archive/exp-213`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-213)

## Problem

[Exp 159](159-writer-pipelining.md) and [exp 180](180-group-commit-request-batching.md)
attacked the same "per-write isolate round-trip" ceiling from opposite ends
for **standalone** writes: pipelining held the writer lock only across the
send, and group commit coalesces a burst of concurrent `db.execute()` calls
into a single `MultiExecuteRequest`. The release Concurrent Single Inserts
lane [exp 161](161-concurrent-writes-release-coverage.md) added dropped from
~2.9 ms to ~1.1 ms as a result.

None of that machinery applies **inside** `db.transaction()`. A caller
writing

```dart
await db.transaction((tx) async {
  await Future.wait([
    for (var i = 0; i < 100; i++)
      tx.execute('INSERT INTO items(...) VALUES (?, ?)', [key_i, val_i]),
  ]);
});
```

still pays one full writer round-trip per statement. Every `Transaction.execute`
call goes through `_writer.executeLocked` → one `ExecuteRequest` message → one
reply. The concurrent burst is invisible to the writer: it sees N sequential
requests, exactly as it would for `await`/`await` pairs.

The moonshot lane names this ceiling as a candidate to attack:

> [`transaction-control-paths`](signals.json) openCandidate 2026-07-03:
> "full savepoint-scope command batching that fuses begin/body/release-or-rollback
> into one writer request".

Doing that for the whole savepoint scope (including BEGIN and RELEASE) breaks
callback semantics — a `runZoned` body cannot be statically batched. But the
narrower shape — coalescing the **inner** execute calls when the caller has
already lined up N futures in one microtask — needs neither an API change nor
semantic surgery.

## Hypothesis

The assumption we are challenging is: **every awaited `tx.execute()` inside
`db.transaction()` must be its own writer round-trip.**

That assumption is workload-agnostic. For a `Future.wait(...)` burst it costs
nothing to be wrong: the caller already handed us N logically-parallel writes,
and the writer will process them serially anyway. If we buffer them until the
current microtask yields and then send them as a single `MultiExecuteRequest`,
N round-trips collapse toward 1 with no observable change in ordering,
atomicity, or per-statement error surfacing (`MultiExecuteResponse` already
carries per-statement outcomes).

The catch: any per-call overhead we add to `Transaction.execute` also lands
on the vastly more common **sequential-await** pattern
(`await tx.execute(...); await tx.execute(...)`), where there is nothing to
batch. So the moonshot only wins if the buffered path exists **and** the
sequential-await pattern stays neutral against pre-213.

## Approach

`Transaction.execute` splits into two paths.

**Fast path (sequential-await)** — no writes in flight and the buffer is
empty, so the caller is in the common serial pattern. A dedicated async
helper `_fastPathExecute` sends synchronously via `_writer.executeLocked` and
awaits the reply exactly the way pre-213 did (one microtask hop, no
completer, no batch outcome switch):

```dart
if (_pendingWrites.isEmpty && _inFlightWrites == 0) {
  return _fastPathExecute(sql, parameters, correlationId);
}
```

**Slow path (concurrent-burst)** — another `tx.execute` is already in flight
(`Future.wait` case) or the buffer already has entries. The call is buffered
into `_pendingWrites`, a `scheduleMicrotask(_flushPending)` is queued the
first time, and the returned Future is a `Completer<WriteResult>.sync()` that
resolves once the flush's reply distributes per-statement outcomes. On flush:

- Group size 1 → single `_writer.executeLocked` (same wire shape as fast
  path). This is the case that Future.wait boils down to when only one call
  buffered before the microtask ran.
- Group size > 1 → `_writer.multiExecuteLocked` sends one
  `MultiExecuteRequest` carrying `N` `(sql, params)` pairs. The writer
  handler already tolerates `txDepth > 0` — each statement runs against the
  still-open outer transaction, per-statement dirty sets accumulate through
  the enclosing commit, and per-statement failures return as
  `ResqliteException` entries in `MultiExecuteResponse.outcomes` that
  complete individual futures with errors.

Any operation that must observe the effects of buffered writes flushes first:
`Transaction.select` (reads must see the writes), `Transaction.executeBatch`
(inherits FIFO order against the batch), `Transaction.transaction` (buffered
writes must land in the outer scope before the inner savepoint begins,
otherwise an inner rollback would also drop them), and `Writer.transaction`'s
close path (fire-and-forget writes must reach SQLite before COMMIT/ROLLBACK
— matches pre-213 sync-send semantics). The close-path guard uses a
`hasPendingWrites` getter so the sequential-await pattern skips the
`await tx.drainForClose()` microtask hop entirely when the buffer is already
empty; without that guard the empty-drain was measurable per-tx overhead
(`tx-single-write` regressed +1-5% before the guard was added).

The `_inFlightWrites` counter is the pivot between the two paths. Any write
the fast path issues increments it before send and the `finally` decrements
it after the reply. A concurrent second call landing while the first is
in-flight therefore takes the slow path — the burst pattern.

Four load-bearing guards emerged during PR review: `_inFlightWrites` (fast
path vs slow path arbiter), `hasPendingWrites` on `drainForClose` (empty-drain
guard), `List<Object?>.of(parameters)` at buffer time (parameter aliasing
snapshot), and the restored `TraceliteProfile.traceAsync` wrap on the fast
path (Dart-side span parity for profile builds). None were in the first draft;
each was required by a measured regression or a correctness hazard Copilot
flagged.

No public API changes. `Database.transaction`, `Transaction.execute`, and
`Transaction.select` keep their signatures.

## Results

Two order-flipped focused passes on
[`benchmark/experiments/tx_body_write_coalescing.dart`](../benchmark/experiments/tx_body_write_coalescing.dart)
(7 rounds per side, median-of-7 in ms). Verdicts from
`benchmark/ab_drift_check.dart` (exp 177's classifier applied to the paired
per-run values):

| Lane | Pass 1 Δ | Pass 2 Δ | Verdict |
|---|---|---|---|
| **tx-burst-future-wait** (20 tx × 100 writes) | **−26.0 %** | **−31.2 %** | **REPRODUCED (real effect)** |
| tx-sequential-await (100 tx × 20 writes) | −0.5 % | +3.1 % | neutral (both below 3 % effect floor) |
| tx-single-write (1000 tx × 1 write) | +1.6 % | −4.6 % | neutral (sign reversal — drift) |
| tx-interleaved-select (50 tx × 10 execute+select) | +1.7 % | −0.1 % | neutral |

The burst pattern is roughly **~28 % faster** — that is the writer seeing one
100-statement `MultiExecuteRequest` per transaction instead of 100 individual
`ExecuteRequest` messages, and the per-round-trip floor disappearing
accordingly. Every other lane sits inside the drift-check tool's 3 % effect
floor across the order-flip: the fast path plus the `hasPendingWrites` guard
held the common sequential-await pattern at pre-213 cost.
`writer_pipelining.dart`'s `transaction-guardrail` row moved +1.6 % on a single
pass (within noise); standalone-write paths are structurally untouched.

## Outcome

**Rejected.** The measurement is clean, the drift check is reproduced, the
common patterns are neutral — the moonshot's implementation goal was met.
The rejection is about the **pattern**, not the numbers.

`Future.wait([tx.execute(...) × N])` inside `db.transaction()` is not a
shape resqlite is trying to encourage:

- Bulk writes with identical SQL already have [`executeBatch`](../lib/resqlite.dart),
  which sends one `BatchRequest` and runs the whole matrix in C. That is the
  right API for that job.
- Bulk writes with *different* SQL where the caller wants atomicity are
  legitimate but rare in practice, and users reaching for them are already
  handling per-statement error surfacing that the burst pattern makes more
  awkward, not less.
- Bulk writes with different SQL without atomicity needs are already covered
  by [exp 180](180-group-commit-request-batching.md) — standalone
  `db.execute()` outside a transaction, coalesced into a
  `MultiExecuteRequest` on the writer's side.

The remaining pattern — `Future.wait([tx.execute × N])` specifically inside
`db.transaction()` — has no strong idiomatic case. Accepting a runtime
change that carries four load-bearing guards, extends `MultiExecuteRequest`
semantics across two experiments (180 standalone-autocommit and 213
inherit-outer-tx), and adds persistent `_pendingWrites` /
`_flushScheduled` / `_inFlightWrites` state per `Transaction` — all to
improve one workload shape we are not actively steering users toward — is
not a good trade against maintenance cost that every future writer-path
change will have to reason about.

The runtime prototype is preserved at `archive/exp-213`. Reopen the
direction if any of the following change:

1. A production profile or downstream report surfaces
   `Future.wait([tx.execute × N])`-inside-tx as a real hot path (not
   speculation about it being possible).
2. A new design collapses the guard set from four to one — e.g. a
   detection primitive that distinguishes burst from sequential without
   the per-`Transaction` state, or a writer-side change that makes
   inside-tx multi-execute strictly cheaper without a Dart-side buffer.
3. The full savepoint-scope openCandidate (BEGIN + body + COMMIT in one
   round-trip) becomes tractable — the body-only fusion in exp 213 is
   ~1 % of tx wall clock; that other 99 % is where the direction's real
   headroom sits, if any remains.

The `full savepoint-scope command batching` openCandidate was intended
as a target; exp 213 shows the body-only variant is measurable but not
worth carrying. The full-scope variant remains blocked on callback
semantics + no-public-API-growth (both exp 197 constraints), and no new
angle emerged from this run.

The focused benchmark
(`benchmark/experiments/tx_body_write_coalescing.dart`) is retained as
the durable harness — any future transaction-body write experiment
should include its four lanes so the same workload/complexity trade-off
is legible.

## Test plan

- [x] `dart analyze --fatal-infos lib test` (drift-peer test error unrelated
      to this branch)
- [x] `dart test test/transaction_test.dart` (47/47 pass on prototype,
      including 7 correctness tests covering Future.wait burst, per-stmt
      WriteResult, mid-batch failure surfacing, tx.select flush,
      fire-and-forget close-flush, nested-savepoint outer-flush, and
      parameter aliasing snapshot)
- [x] `dart test test/write_coalescing_test.dart` (exp 180 standalone
      coalescing behavior unchanged; the invalidation-flake there is
      pre-existing on `origin/main`, see `task_97e2eec8`)
- [x] Focused `benchmark/experiments/tx_body_write_coalescing.dart`
      order-flipped pair + `ab_drift_check.dart` verdict
- [x] `benchmark/experiments/writer_pipelining.dart` guardrail
      (transaction-guardrail lane +1.6 %, within noise)
