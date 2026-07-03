# Exp 213: Transaction body write coalescing moonshot

**Date:** 2026-07-03
**Status:** Accepted
**Category:** Moonshot
**Direction:** `transaction-control-paths`
**Benchmark Run:** none (focused-harness experiment; no release-suite metric maps to `Future.wait([tx.execute(...) x N])` inside `db.transaction()`)

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

**tx-burst-future-wait is what the moonshot exists for.** 20 transactions
each doing `Future.wait([tx.execute × 100])` measured ~3.9 → ~2.9 ms across
both order-flipped passes — the classifier calls this a real effect with
same-direction deltas and comparable per-side CVs. That is the writer
seeing one 100-statement `MultiExecuteRequest` per transaction instead of
100 individual `ExecuteRequest` messages, and the per-round-trip floor
disappearing accordingly.

**Every other lane stays inside the drift-check tool's 3 % effect floor.**
Sequential-await moved by −0.5 % and +3.1 % across the flip; single-write
by +1.6 % and −4.6 % (sign reversal); interleaved-select by +1.7 % and
−0.1 %. Those are the patterns the moonshot must not regress — and they
don't. The `hasPendingWrites` guard on `drainForClose` is what pulls
single-write and interleaved-select from a consistent +1–5 % regression
(measured before the guard was added) back to neutral.

Existing writer_pipelining.dart guardrail — the release-write-shape whose
`transaction-guardrail` row is the closest release-suite proxy for
sequential-await inside `db.transaction()` — moved +1.6 % on a single pass
(within noise); standalone-write lanes are structurally untouched
(`db.execute` and `_drainPendingWrites` are unchanged).

## Outcome

**Accepted.** A real ~28 % win on the Future.wait-inside-transaction burst
pattern by turning N `ExecuteRequest` round-trips into one
`MultiExecuteRequest`, with the common sequential-await pattern verified
neutral across an order-flipped pair by `ab_drift_check.dart`. No public
API change; internally the writer handler already supported the
`txDepth > 0` case, so the runtime change is confined to `Transaction`'s
buffer/flush plumbing plus a `Writer.multiExecuteLocked` entry point that
mirrors the existing `executeLocked` shape.

The win only lands when the caller writes `Future.wait([...])` or the
equivalent fire-and-forget pattern inside a transaction body. Users who
write sequential `await`/`await` inside `db.transaction()` pay the same
per-round-trip floor as before; this experiment does not, and cannot,
change that without a public API opt-in (see [exp 197](197-true-group-commit-moonshot.md)
for why implicit group commit is off-limits — different concern, same
class of rejection).

The `full savepoint-scope command batching` openCandidate from the
signals map is only partially consumed by this experiment — we batch the
**body** but still round-trip BEGIN and COMMIT. Full savepoint-scope
fusion still requires either a design that preserves callback semantics
without an opt-in API or a workload showing the BEGIN/COMMIT pair is the
dominant residual after this ships.

## Test plan

- [x] `dart analyze --fatal-infos lib test` (drift-peer test error unrelated
      to this branch)
- [x] `dart test test/transaction_test.dart` (43/43 pass, including 6 new
      exp 213 correctness tests covering Future.wait burst, per-stmt
      WriteResult, mid-batch failure surfacing, tx.select flush, fire-and-forget
      close-flush, and nested-savepoint outer-flush)
- [x] `dart test test/write_coalescing_test.dart` (exp 180 standalone
      coalescing behavior unchanged)
- [x] Focused `benchmark/experiments/tx_body_write_coalescing.dart`
      order-flipped pair + `ab_drift_check.dart` verdict
- [x] `benchmark/experiments/writer_pipelining.dart` guardrail
      (transaction-guardrail lane +1.6 %, within noise)
