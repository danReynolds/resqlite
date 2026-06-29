# Experiment 159: Writer request pipelining + persistent reply port

**Date:** 2026-06-09
**Status:** Accepted
**Direction:** `stream-rerun-dispatch`

## Problem

Exp 147 split writer-side burst wall and found SQLite-facing calls are a
minority of write cost (9.4% on A11c overlap, 18.1% keyed-PK); after
subtracting stream invalidation, **residual writer/request wall is the
largest bucket** (71.8% overlap, 63.3% keyed-PK, 73.4% even with zero
streams). Exp 148 showed that batching reader replies reduces callback
counters without moving measured elapsed. A closed residual-split branch
(PR #143, not merged) subdivided the residual further and concluded that
no single writer-side sub-bucket clears the decision threshold — "future
stream-dispatch work needs a workload-shape or scheduling-model change
rather than another sub-bucket optimization."

This experiment is that scheduling-model change. Three structural costs
sat on every write round-trip:

1. **A fresh `RawReceivePort` per request** (`Writer._request`): one port
   allocate/register/teardown cycle per write. The reader pool removed its
   equivalent in exp 040; the writer never did.
2. **A guaranteed microtask hop before every send**: `_request` awaited
   `_workerPort.future` — a future that resolved once at spawn and never
   again — so every send deferred to the microtask queue before reaching
   `SendPort.send`.
3. **Async completers on the reply path**: the reader pool switched its
   per-worker completers to `Completer.sync` (exp 032); the writer's reply
   path still paid the extra scheduling hops.

Separately, the write lock was held across the **entire round-trip** for
standalone writes, so concurrent `db.execute()` callers fully serialized:
send → worker exec → reply → main-isolate resume → unlock → next send.
The worker idled between requests even when more writes were queued on
the main isolate.

## Hypothesis

Caching the worker `SendPort`, replacing per-request reply ports with one
persistent port + FIFO completer queue, and completing synchronously
removes fixed scheduling overhead from every write. Releasing the write
lock after the *send* (instead of after the reply) lets concurrent
standalone writes pipeline through the worker's port FIFO, overlapping
worker-side execution with main-isolate reply processing.

Safety argument: the writer isolate processes its port in FIFO order and
sends exactly one reply per request (handlers reply or throw; the
entrypoint converts throws into replies), so a FIFO queue of completers
matches replies to callers. A standalone write sent before a BEGIN is
fully processed at `txDepth == 0` — including its dirty-set harvest —
before the transaction opens, so holding the lock across the write's
reply adds no exclusion a later BEGIN actually needs. Transactions still
hold the lock from BEGIN through COMMIT/ROLLBACK, so no standalone write
can be sent into an open transaction.

## Approach

- `Writer._sendPort` cached at spawn; `_request` sends synchronously
  (no awaits before `SendPort.send`).
- One persistent `RawReceivePort _replyPort` + `ListQueue<Completer>`
  pending queue; completers are `Completer.sync` (reader-pool pattern).
- `Writer.execute` / `Writer.executeBatch` (the standalone entry points
  `Database.execute` / `Database.executeBatch` call) acquire the mutex,
  send, release in `finally`, and await the reply outside the lock. The
  raw lock-held sends are named `executeInTransaction` /
  `executeBatchInTransaction` / `selectInTransaction` — used by
  `Transaction.*`, which runs under the enclosing transaction's lock —
  and carry `assert(_mutex.isLocked)` so calling one without the lock
  fails loudly in debug builds. `Database.transaction` keeps `locked()`
  across the full transaction.
- New tests: pipelined writes racing a rolled-back transaction stay
  isolated; an error reply consumes exactly its own FIFO slot.
- New focused benchmark `benchmark/experiments/writer_pipelining.dart`
  with sequential-awaited, concurrent-burst, and transaction-guardrail
  shapes — the burst shape is the first benchmark in the repo where a
  caller has more than one standalone write outstanding.

## Results

### Focused benchmark (writer_pipelining.dart, 7 rounds, medians)

| shape | baseline | candidate | delta |
|---|---:|---:|---:|
| concurrent-burst (10×200 writes), pass 1 | 113.2 ms | 72.6 ms | **−36%** |
| concurrent-burst (10×200 writes), pass 2 | 100.5 ms | 55.3 ms | **−45%** |
| sequential-awaited (2000 writes), pass 2 | 72.7 ms | 74.5 ms | neutral |
| transaction-guardrail (50×10), pass 2 | 13.0 ms | 12.2 ms | neutral |

### Writer wall split audit (exp 147 harness, single pass, back-to-back)

| workload | baseline wall | candidate wall | residual_us baseline → candidate |
|---|---:|---:|---:|
| A11c baseline (0 streams) | 96.4 ms | 78.2 ms | 70,729 → 55,385 |
| A11c disjoint | 101.0 ms | 83.8 ms | 56,185 → 45,729 |
| A11c overlap | 202.5 ms | 192.1 ms | 143,527 → 139,549 |
| keyed PK subscriptions | 45.8 ms | 39.1 ms | 28,296 → 22,583 |

Residual writer/request wall drops on every workload; the pure
round-trip shape (0 streams) improves most, consistent with the change
targeting fixed per-round-trip overhead. Single-pass: direction signal
only.

### Tracelite A/B (stream-rerun-dispatch direction, two passes)

The canonical stream scenarios issue writes sequentially (`await` per
write plus an event-loop yield), so the pipelining component never
engages there — these scenarios act as guardrails for the
persistent-port / sync-completion components.

**Pass 1 (baseline collected first, candidate second)** flagged
high-cardinality-fanout +19.4% (CI 21.0..122ms) and
many-streams-writer-throughput +11.9% (CI 22.1..120ms), keyed-PK
too-noisy (max CV 49.9%). The candidate phase showed within-run CVs of
0.20–0.46 against the baseline phase's 0.01–0.06 — a contamination
signature, with the two sides collected in disjoint time blocks.

**Pass 2 (order flipped: exp-159 code collected first, main second)**
showed all three scenarios neutral with tight CVs (0.01–0.03 for the
exp-159 phase):

| scenario | delta (main vs exp-150) | 95% CI | verdict |
|---|---:|---|---|
| high-cardinality-fanout | +1.02% | −1.73..9.11 ms | neutral |
| many-streams-writer-throughput | −0.26% | −12.9..9.89 ms | neutral |
| keyed-pk-subscriptions | +4.00% | −9.88..34.5 ms | neutral |

exp-150's absolute medians in the clean pass (hcf 361.9–362.8 ms,
many-streams 576.5–582.3 ms) are equal to or better than main's own
medians from pass 1 (364.8–371.5 / 579.8–596.0 ms), confirming the pass-1
flags were environment drift, not the change. This follows exp 144's
two-independent-passes rule for regression flags; the order flip is what
makes the second pass discriminating.

## Decision

**In Review (accept-shaped).** The change is a pure overhead removal on
the per-write round-trip plus a scheduling-model change for concurrent
standalone writes:

- Concurrent writes — the workload shape the closed residual split pointed
  at — improve 36–45% on the focused benchmark.
- The canonical stream guardrails are neutral in a clean pass, including
  keyed-PK (the exp 148 killer).
- Sequential writes and transactions are neutral; residual_us drops on
  every audit workload.
- No public API change; transaction semantics preserved and covered by
  two new tests (rollback isolation, FIFO error slot consumption).

## Future Notes

- All existing release/tracelite write workloads issue writes
  sequentially, so the pipelining win is only visible in the focused
  concurrent-burst benchmark. Promoting a concurrent-write scenario into
  release or tracelite coverage (exp 116 pattern) would make regressions
  in this path publicly visible.
- The remaining residual on sequential writes is the round-trip floor
  itself (port wake + event-loop scheduling in both isolates). Further
  reduction needs request batching across calls (group commit) or a
  different transport (shared memory, when the Dart SDK allows it).
- For future A/B gates: a phase-ordered collection (all baseline runs,
  then all candidate runs) is vulnerable to time-correlated machine
  drift. An order-flipped second pass discriminates drift from real
  regressions cheaply.
