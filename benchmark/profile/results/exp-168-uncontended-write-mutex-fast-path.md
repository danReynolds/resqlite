# Experiment 168 — Uncontended writer-mutex synchronous fast path

Focused benchmark: `benchmark/experiments/writer_pipelining.dart` (exp 159).
Three paired passes, each 7 rounds. The reported number is the round
median; per-round numbers follow in brackets. Baseline and candidate
swapped between passes; the worktree-local `lib/src/mutex.dart` and
`lib/src/writer/writer.dart` are stashed/popped between sides.

Machine: MacBook Pro 14in (`Platform.numberOfProcessors - 1 = ?`). One
process. Stopwatch wall.

## sequential-awaited (2000 writes)

| pass | baseline median (ms) | candidate median (ms) | delta |
|---:|---:|---:|---:|
| 1 | 31.643 | 30.386 | -4.0% |
| 2 | 33.922 | 30.868 | -9.0% |
| 3 | 32.686 | 31.042 | -5.0% |
| **cross-pass median** | **32.686** | **30.868** | **-5.6%** |

## concurrent-burst (10 × 200 writes)

| pass | baseline median (ms) | candidate median (ms) | delta |
|---:|---:|---:|---:|
| 1 | 25.272 | 24.156 | -4.4% |
| 2 | 25.259 | 24.607 | -2.6% |
| 3 | 26.194 | 24.943 | -4.8% |
| **cross-pass median** | **25.272** | **24.607** | **-2.6%** |

## transaction-guardrail (50 tx × 10 writes)

| pass | baseline median (ms) | candidate median (ms) | delta |
|---:|---:|---:|---:|
| 1 | 4.134 | 4.199 | +1.6% |
| 2 | 4.282 | 4.281 | 0.0% |
| 3 | 4.305 | 4.240 | -1.5% |
| **cross-pass median** | **4.282** | **4.240** | **-1.0%** |

The transaction path still goes through `Writer.locked`, which holds the
write lock continuously across BEGIN/body/COMMIT and is unchanged here.
This row exists as a guardrail: any cross-pass move ≥ ±5 % would
indicate the fast path leaked an unintended effect.

## Raw round timings

### sequential-awaited (ms)

| pass | side | round 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---:|:--|---:|---:|---:|---:|---:|---:|---:|
| 1 | baseline | 78.597 | 39.458 | 33.105 | 31.172 | 31.643 | 30.727 | 31.044 |
| 1 | candidate | 77.546 | 36.699 | 31.707 | 30.386 | 28.876 | 30.006 | 29.316 |
| 2 | baseline | 73.278 | 40.326 | 33.922 | 31.102 | 34.759 | 31.053 | 31.304 |
| 2 | candidate | 76.537 | 37.315 | 32.459 | 30.868 | 30.806 | 30.621 | 30.284 |
| 3 | baseline | 75.636 | 41.264 | 33.497 | 32.686 | 32.145 | 32.424 | 32.007 |
| 3 | candidate | 77.571 | 37.139 | 32.891 | 30.610 | 30.762 | 31.042 | 30.304 |

Round 1 is dominated by JIT warmup on every pass and on both sides. The
median is taken over all seven rounds; even with round 1 included the
candidate side is monotonically faster on rounds 4–7 in every pass.

### concurrent-burst (ms)

| pass | side | round 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---:|:--|---:|---:|---:|---:|---:|---:|---:|
| 1 | baseline | 33.844 | 27.037 | 25.510 | 25.272 | 23.721 | 24.645 | 23.539 |
| 1 | candidate | 31.317 | 26.109 | 25.285 | 24.156 | 24.101 | 23.702 | 23.297 |
| 2 | baseline | 35.188 | 27.966 | 26.940 | 25.259 | 24.363 | 24.581 | 24.482 |
| 2 | candidate | 30.089 | 25.789 | 24.607 | 24.930 | 24.005 | 23.358 | 23.449 |
| 3 | baseline | 33.068 | 27.740 | 26.491 | 26.194 | 25.163 | 24.727 | 24.804 |
| 3 | candidate | 30.531 | 26.158 | 25.626 | 24.502 | 24.943 | 23.471 | 23.016 |

### transaction-guardrail (ms)

| pass | side | round 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---:|:--|---:|---:|---:|---:|---:|---:|---:|
| 1 | baseline | 10.104 | 4.488 | 4.077 | 4.107 | 4.134 | 4.187 | 3.999 |
| 1 | candidate | 10.406 | 4.777 | 4.060 | 4.199 | 3.872 | 4.280 | 4.010 |
| 2 | baseline | 13.760 | 4.485 | 4.067 | 4.221 | 4.120 | 4.334 | 4.282 |
| 2 | candidate | 10.380 | 4.826 | 4.382 | 4.281 | 4.121 | 4.242 | 4.265 |
| 3 | baseline | 10.184 | 4.992 | 4.202 | 4.155 | 4.305 | 4.409 | 4.233 |
| 3 | candidate | 10.590 | 4.704 | 4.233 | 4.240 | 4.041 | 4.270 | 4.209 |

## Interpretation

The exp 159 send-gated writer-lock pattern still acquires the mutex via
`await _mutex.lock()`. Because `Mutex.lock` is an `async` function whose
implicit Future hops once before resuming the caller, every uncontended
standalone write paid one microtask hop on its way to `SendPort.send`.
Adding `Mutex.tryLock()` (returns `true` when the lock was acquired
without waiting — the conventional spelling for this primitive in
Java / Rust / Python / Go) and rewriting `Writer.execute` /
`Writer.executeBatch` as non-`async` removes that hop.

`transaction-guardrail` continues to use `Writer.locked`, which holds
the mutex across the whole transaction body and still goes through the
async slow path. Its near-zero delta across three passes is the
guardrail signal that the change did not change what callers see when
the lock is genuinely held.

The improvement is small per write (~1–2 µs of saved microtask
scheduling) but compounds across 2000 sequential writes (~3 ms) and
2000 concurrent-burst writes (~1 ms after pipelining absorbs some of
the savings). That's enough signal at the focused-benchmark resolution
to land monotonically across all three passes' confidence intervals.
