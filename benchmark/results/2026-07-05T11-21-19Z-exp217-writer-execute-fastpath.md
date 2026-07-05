# Focused benchmark results — exp 217 writer.execute() fast-path

Focused harnesses only. No release-suite run.

## `benchmark/experiments/write_result_direct_read.dart`

Median µs per `db.execute()` call, 2000 calls/sample × 13 samples, two order-flipped passes.

Pair 1 (candidate first, then baseline):

| Shape | Candidate µs/call | Baseline µs/call | Delta |
|---|---:|---:|---:|
| noop update  |  6.418 |  6.548 | -2.0% |
| point update | 13.761 | 14.216 | -3.2% |
| param update | 14.052 | 14.283 | -1.6% |

Pair 2 (baseline first, then candidate):

| Shape | Baseline µs/call | Candidate µs/call | Delta |
|---|---:|---:|---:|
| noop update  |  6.796 |  6.589 | -3.0% |
| point update | 14.502 | 13.828 | -4.6% |
| param update | 16.173 | 14.012 | -13.4% |

Interpretation: candidate reproduces same-direction wins on all three lanes
across the order-flipped pair. Pair 2's param update baseline (16.173 µs, min
15.432 / max 19.090) is a slow outlier vs pair 1's baseline (14.283 µs, min
14.059 / max 15.931); pair 2's candidate value (14.012 µs) matches pair 1's
candidate (14.052 µs), so the load-bearing param delta is the ~1.6% figure,
not the -13.4% pair-2 reading.

The noop lane (~6.5 µs writer floor) is the cleanest signal: candidate lands at
6.418 / 6.589, baseline at 6.548 / 6.796 — a **2-3% floor reduction**, which
matches the mechanism (removed `_PendingWrite` allocation + list churn +
extra completer indirection).

## `benchmark/experiments/writer_pipelining.dart`

Millisecond-precision harness, 7 rounds per lane (round 1 discarded as JIT
warmup), two order-flipped passes.

Pair 1 (baseline first, then candidate):

| Lane | Baseline ms | Candidate ms | Delta |
|---|---:|---:|---:|
| sequential-awaited (2000 writes)  | 36.903 | 32.912 | -10.8% |
| concurrent-burst (10 × 200)       | 21.939 | 21.879 |  -0.3% |
| transaction-guardrail (50 × 10)   |  4.454 |  4.511 |  +1.3% |

Pair 2 (candidate first, then baseline):

| Lane | Candidate ms | Baseline ms | Delta (baseline vs candidate) |
|---|---:|---:|---:|
| sequential-awaited (2000 writes)  | 32.328 | 32.375 |  +0.1% |
| concurrent-burst (10 × 200)       | 21.339 | 20.499 |  -3.9% |
| transaction-guardrail (50 × 10)   |  4.123 |  4.402 |  +6.8% |

Interpretation: at millisecond resolution, the fast-path signal is
inconsistent — pair 1's sequential-awaited win (-10.8%) does not reproduce in
pair 2 (baseline 32.375 vs candidate 32.328, essentially flat), because pair
1's baseline (36.903) was an anomalously slow single-sample median. Pair 2's
baseline warms into the same ~32 ms band as candidate. This mirrors the
exp 195 pattern where the ms-precision `wide_cols.dart` harness could not
resolve the µs-scale per-call setup work that `select_bytes_repeated_calls.dart`
did resolve.

The 2000-write sequential lane's median-of-7-rounds standard deviation makes
it a ~1 ms-noise instrument; the mechanism's expected saving (~200-500 ns per
write × 2000 writes = 0.4-1.0 ms) is at or below that floor. Cite
`write_result_direct_read.dart` (which reports per-call µs) as the load-bearing
harness for this experiment.

Concurrent-burst (-3.9% pair 2 baseline-faster) and transaction-guardrail
(+6.8% pair 2 baseline-slower) show sign reversal across the order flip and
are drift-suspected by exp 177 rules; both lanes' mechanisms are unchanged by
the fast-path (concurrent bursts still fall into the pump via `_mutex.isLocked`;
transactions hold the mutex from BEGIN through COMMIT/ROLLBACK, unchanged).
