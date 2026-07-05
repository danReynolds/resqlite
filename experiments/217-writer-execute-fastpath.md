# Experiment 217: writer `execute()` fast-path bypasses the exp 180 coalescing pump

**Date:** 2026-07-05
**Status:** Accepted
**Category:** Moonshot
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** none — focused
  [`benchmark/experiments/write_result_direct_read.dart`](../benchmark/experiments/write_result_direct_read.dart)
  (two order-flipped passes, load-bearing) and
  [`benchmark/experiments/writer_pipelining.dart`](../benchmark/experiments/writer_pipelining.dart)
  (two order-flipped passes, guard); raw pair tables in
  [`benchmark/results/2026-07-05T11-21-19Z-exp217-writer-execute-fastpath.md`](../benchmark/results/2026-07-05T11-21-19Z-exp217-writer-execute-fastpath.md).
  No release-suite run — `writer_pipelining.dart`'s ms-precision sequential
  lane cannot resolve the ~200-500 ns per-write mechanism this change removes
  (the exp 195 pattern), so the release write-suite would be less informative
  than the focused µs harness that already resolves the signal. The linked
  focused pair table is documentation, not a release-suite artifact (no
  `resqlite metrics` section, so `generate_history.dart` skips it), which is
  why the header opts out of release-run linking — the exp 211 pattern.

## Problem

[Exp 180](180-group-commit-request-batching.md) added a coalescing pump inside
`Writer.execute()` — every standalone write buffers a `_PendingWrite`, schedules
`_drainPendingWrites`, and completes through the pump's completer. Concurrent
bursts collapse to ~2 round-trips instead of N, and the release
`Concurrent Single Inserts` lane [exp 161](161-concurrent-writes-release-coverage.md)
dropped from ~2.9 ms to ~1.1 ms as a result.

But the pump runs on *every* standalone `db.execute()`, including the vastly
more common sequential-await pattern where there is nothing to coalesce.
Each such write pays for machinery it never uses:

- one `_PendingWrite` object allocation
- `List<_PendingWrite>.of(_pendingWrites)` (a fresh list allocation) and
  `_pendingWrites.clear()`
- the pump's own `Completer` plus a two-step distribution
  (`caller.completer.complete(await singleReply)`) instead of the caller
  awaiting the reply future directly

[Exp 214](214-write-result-direct-read.md) built
[`benchmark/experiments/write_result_direct_read.dart`](../benchmark/experiments/write_result_direct_read.dart),
a microsecond-precision writer floor harness (median µs per call over 2000
calls/sample × 13 samples). Its no-op-update lane sits at a ~6.5 µs floor —
small enough that per-write scheduling costs sub-µs in scale are directly
resolvable.

## Hypothesis

The assumption we are challenging is: **the exp 180 coalescing pump imposes no
measurable per-write cost on the sequential-await path.**

If that assumption is right, then adding a fast-path that skips the pump when
nothing else is in flight should be neutral — the pump's overhead is
sub-noise. If the assumption is wrong, we should see a floor reduction on the
noop-update lane, in a magnitude consistent with removing one small
allocation + a completer indirection (a few hundred nanoseconds per write, ie
2-4% of a 6.5 µs floor).

Reject if the deltas do not reproduce same-sign across order-flipped passes, or
if concurrent-burst / transaction lanes regress (the pump semantics for those
paths must stay intact).

## Approach

Single-file change to
[`lib/src/writer/writer.dart`](../lib/src/writer/writer.dart). Add one fast-path
branch at the top of `Writer.execute()`:

```dart
if (_pendingWrites.isEmpty && !_draining && !_mutex.isLocked) {
  return _fastPathExecute(sql, parameters, traceCorrelationId);
}
```

`_fastPathExecute` mirrors the shape `executeBatch` already uses: lock the
mutex, send synchronously via `_request`, unlock, and return the reply future
directly:

```dart
Future<ExecuteResponse> _fastPathExecute(
  String sql, List<Object?> parameters, int? traceCorrelationId,
) async {
  await _mutex.lock();
  final Future<ExecuteResponse> reply;
  try {
    _ensureOpen();
    reply = _request<ExecuteResponse>(
      (replyPort) => ExecuteRequest(sql, parameters, replyPort,
          traceCorrelationId: traceCorrelationId),
    );
  } finally {
    _mutex.unlock();
  }
  return reply;
}
```

Correctness rests on three properties preserved from exp 180:

1. **Concurrent bursts still coalesce.** `Mutex.lock()`'s body sets
   `_completer` **synchronously** before its returned Future yields. So the
   first fast-path caller in a burst locks the mutex; any concurrent caller
   arriving before the first caller's send observes `_mutex.isLocked == true`
   and falls through to the pump path, buffering into `_pendingWrites` exactly
   as before. The group commit shape is preserved for the shape it was
   designed for.

2. **Transaction ordering is unchanged.** `Database.transaction` acquires the
   mutex via `writer.locked(...)`. A concurrent `db.execute()` arriving during
   a transaction sees `_mutex.isLocked == true` and takes the pump path, which
   queues on the same mutex — indistinguishable from pre-217 behavior.

3. **Close semantics are unchanged.** Both entry paths check `_closed` at
   entry and again inside the mutex via `_ensureOpen()`, so close-during-write
   still surfaces `ResqliteConnectionException.databaseClosed()`.

The pump path is retained unchanged for slow-path callers.

## Results

Raw pair tables live in
[`benchmark/results/2026-07-05T11-21-19Z-exp217-writer-execute-fastpath.md`](../benchmark/results/2026-07-05T11-21-19Z-exp217-writer-execute-fastpath.md).
Negative deltas mean the candidate was faster.

`write_result_direct_read.dart` (µs/call, load-bearing harness):

| Pair | Shape | Baseline µs | Candidate µs | Delta |
|---|---|---:|---:|---:|
| pair 1 (candidate first) | noop update  |  6.548 |  6.418 | -2.0% |
| pair 1 (candidate first) | point update | 14.216 | 13.761 | -3.2% |
| pair 1 (candidate first) | param update | 14.283 | 14.052 | -1.6% |
| pair 2 (baseline first)  | noop update  |  6.796 |  6.589 | -3.0% |
| pair 2 (baseline first)  | point update | 14.502 | 13.828 | -4.6% |
| pair 2 (baseline first)  | param update | 16.173 | 14.012 | -13.4% |

`writer_pipelining.dart` (ms medians, guard harness):

| Pair | Lane | Baseline ms | Candidate ms | Delta |
|---|---|---:|---:|---:|
| pair 1 | sequential-awaited (2000)     | 36.903 | 32.912 | -10.8% |
| pair 1 | concurrent-burst (10 × 200)   | 21.939 | 21.879 |  -0.3% |
| pair 1 | transaction-guardrail (50×10) |  4.454 |  4.511 |  +1.3% |
| pair 2 | sequential-awaited (2000)     | 32.375 | 32.328 |  +0.1% |
| pair 2 | concurrent-burst (10 × 200)   | 20.499 | 21.339 |  +4.1% |
| pair 2 | transaction-guardrail (50×10) |  4.402 |  4.123 |  -6.3% |

The noop-update floor lane is the cleanest signal: **-2 to -3% reproduced
across both order-flipped passes**, matching the predicted "few hundred
nanoseconds saved per write on a 6.5 µs floor" mechanism. Point update
reproduces at -3 to -5%. The param-update pair-2 outlier (-13.4%) is
dominated by that pair's slow baseline spread (min 15.432 / max 19.090 vs
pair 1's 14.059 / 15.931); the candidate value itself (14.012) matches
pair 1's candidate (14.052), so the reproducing param-update delta is the
~1.6% figure.

`writer_pipelining.dart` reports at millisecond precision, and the mechanism's
absolute per-write saving (~200-500 ns × 2000 writes = 0.4-1.0 ms) sits at or
below its noise floor. This mirrors exp 195's finding that ms-precision
`wide_cols.dart` could not resolve sub-µs per-query work while
`select_bytes_repeated_calls.dart` did. Pair 1's sequential-awaited win
(-10.8%) does not reproduce in pair 2 (+0.1%) — pair 1's baseline (36.903 ms)
was an anomalously slow median while pair 2's baseline (32.375 ms) sits in
the same band as candidate. Cite `write_result_direct_read.dart` as the
load-bearing harness for this experiment.

Concurrent-burst and transaction-guardrail lanes stay neutral across both
passes (with sign-reversal patterns characteristic of drift, per exp 177's
classifier). The fast-path does not change the mechanism for either — concurrent
callers still fall into the pump via `_mutex.isLocked`, and transactions hold
the mutex end-to-end via `Writer.locked`.

## Outcome

**Accepted (in review).** The assumption that the exp 180 coalescing pump
imposes no measurable per-write cost on the sequential-await path is
falsified. Removing the `_PendingWrite` allocation, the list churn, and the
completer indirection recovers **~2-3%** on the writer floor
(`write_result_direct_read.dart` noop lane) and **~3-5%** on `point update`,
reproduced same-direction across two order-flipped passes. Concurrent-burst
and transaction guardrails stay neutral (drift-classified where flagged).

The win is deliberately small: this is a micro-scheduling cleanup around a
specific write shape, not a new transport primitive. Its value is that it
falsifies a background assumption cheaply — the exp 180 pump was applied
uniformly under the belief that its per-write cost was negligible, and the
µs-precision harness shows that belief was slightly wrong on the exact shape
the pump can't help.

## Assumption challenged

The exp 180 coalescing pump was worth applying uniformly to every standalone
write path, including the sequential-await shape where nothing coalesces.

## Test plan

- [x] `dart pub get`
- [x] `dart run build_runner build`
- [x] `dart analyze --fatal-infos lib test benchmark`
- [x] `dart test test/database_test.dart -j 1` (53/53 passed on candidate)
- [x] focused order-flipped A/B via `write_result_direct_read.dart` (two passes)
- [x] focused order-flipped A/B via `writer_pipelining.dart` (two passes)

## Future notes

- If a future change proves the pump's mechanism helps a workload the current
  harnesses do not stress (rare `_mutex.isLocked` bypass hits, high-cardinality
  sub-µs write bursts), the fast-path is a single-line disable at the top of
  `execute()`.
- `write_result_direct_read.dart` is now the durable per-µs writer-floor
  harness for any future write-path scheduling change (as
  `select_bytes_repeated_calls.dart` is for the selectBytes encoder path).
