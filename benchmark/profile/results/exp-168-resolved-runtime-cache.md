# Exp 168 - Resolved runtime cache for Database hot paths

Date: 2026-06-14

Focused benchmark:

```bash
dart run benchmark/experiments/writer_pipelining.dart
```

The benchmark is the same one exp 159 used. It runs three shapes per round
(seven rounds total): `sequential-awaited` (2000 `await db.execute(...)`),
`concurrent-burst` (10 × 200 `Future.wait` over `db.execute(...)`), and
`transaction-guardrail` (50 transactions × 10 writes).

## Candidate

A nullable `_DatabaseRuntime? _resolvedRuntime` field on `Database`, populated
synchronously inside `_runtime`'s body the moment `ReaderPool.spawn` and
`Writer.spawn` complete. Hot paths (`select`, `selectBytes`, `execute`,
`executeBatch`, `transaction`) replaced `await _runtime` with
`_resolvedRuntime ?? await _runtime`. `close` and `diagnostics` kept `await
_runtime` — they are cold. `stream` keeps `Stream.fromFuture(_runtime)`. No
public API change.

The optimization removes one microtask hop per hot-path call: after open,
`_runtime` is an already-resolved Future whose `await` continuation still
schedules as a microtask. Theoretical upper bound at ~1-2 µs/hop:
~2-4 ms / ~32 ms ≈ 6-12% on `sequential-awaited`.

## Pass 1 — baseline first, then candidate

| Shape | Baseline median | Candidate median | Delta |
|---|---:|---:|---:|
| sequential-awaited (2000) | 32.169 ms | 31.425 ms | −2.3% |
| concurrent-burst (10×200) | 24.465 ms | 25.818 ms | +5.5% |
| transaction-guardrail (50×10) | 4.587 ms | 4.244 ms | −7.5% |

Sequential and transaction shapes trend with the hypothesis; concurrent-burst
trends against. Mixed signal at sub-1ms absolute deltas on sub-30ms medians.

## Pass 2 — candidate first, then baseline (order flipped)

| Shape | Baseline median | Candidate median | Delta |
|---|---:|---:|---:|
| sequential-awaited (2000) | 31.794 ms | 32.603 ms | +2.5% |
| concurrent-burst (10×200) | 24.089 ms | 25.138 ms | +4.4% |
| transaction-guardrail (50×10) | 4.093 ms | 4.342 ms | +6.1% |

Sequential and transaction shapes reverse sign at the same magnitude as
pass 1. Concurrent-burst stays small-positive (regression) on both passes
but the spread inside each phase covers the delta.

## Round-level spread

`sequential-awaited` candidate pass 2 rounds:
[74.447, 37.249, 32.961, 31.703, 31.043, 30.327, 32.603] ms

Excluding the round-0 cold-spawn warmup (~70-80ms everywhere), per-round
spread is ~30-37 ms — a ~7 ms range that fully contains the candidate
deltas.

## Conclusion

Reject. The microtask hop in `await _runtime` is real but smaller than the
focused-harness noise floor at ~1-2 µs per call. Two order-flipped passes
produced alternating-sign deltas inside per-round variance on the same
shape. Same pattern as the recent overhead-removal rejection cluster
(exp 145, exp 148, exp 151): theoretical hop savings may move but
measured-elapsed at sub-1 µs/call does not separate from machine jitter on
this harness.

No runtime code kept. Exp 159's framing for the next sequential-write
reduction stays in place: the floor is round-trip count and transport
shape, not per-call microtask hops at the `Database` layer above the
writer.
