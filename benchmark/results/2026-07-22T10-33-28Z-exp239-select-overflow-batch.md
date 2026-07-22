# Experiment 239: transparent select overflow batching

- **Date:** 2026-07-22
- **Environment:** Apple M1 Pro, macOS 26.2, Dart 3.12.2
  (`macos_arm64`)
- **Baseline:** `683a64d` (`origin/main`)
- **Candidate:** `ce518de` (runtime preserved at `archive/exp-239`)
- **Harness:**
  [`benchmark/experiments/select_overflow_batch.dart`](../experiments/select_overflow_batch.dart)
  — identical public `Future.wait(db.select(...))` calls in detached baseline
  and candidate worktrees, five warmups, lane-isolated medians, and a complete
  baseline-first/candidate-first order flip.
- **Decision:** Rejected — homogeneous small-read targets win, but the
  predeclared heterogeneous point-latency guard reproduces a regression.

Delta is candidate minus baseline. Negative is candidate-faster.

## Homogeneous small-read targets and controls

Each leg ran the sequential, four-way, twenty-way point, and twenty-way
roughly-ten-row lanes for 31 measured rounds in one small-read-only process.
This removed the large-result allocation/respawn pollution seen in an initial
all-lanes JIT probe.

| Lane | Pass | Baseline median µs | Candidate median µs | Delta | Baseline p95 µs | Candidate p95 µs |
|---|---|---:|---:|---:|---:|---:|
| Sequential point [control] | base→cand | 493 | 447 | -9.3% | 923 | 561 |
| Sequential point [control] | cand→base | 399 | 479 | +20.1% | 646 | 896 |
| Four-way point [control] | base→cand | 84 | 70 | -16.7% | 138 | 161 |
| Four-way point [control] | cand→base | 95 | 73 | -23.2% | 289 | 180 |
| **Twenty-way point [target]** | base→cand | 344 | 254 | **-26.2%** | 670 | 685 |
| **Twenty-way point [target]** | cand→base | 365 | 244 | **-33.2%** | 754 | 467 |
| **Twenty-way ~10-row [target]** | base→cand | 365 | 288 | **-21.1%** | 756 | 766 |
| **Twenty-way ~10-row [target]** | cand→base | 386 | 269 | **-30.3%** | 837 | 704 |

The two load-bearing targets clear the preset 15% median-throughput gate in
both orderings. Four-way admission never batches and does not regress. The
sequential control sign-flips, so its one slower leg is drift rather than a
reproduced regression. Peak observed RSS differed by +0.3% and +1.7% in the
two passes.

## Twenty-large-read guard

Twenty concurrent 10,000-row reads ran alone for 15 measured rounds. This
guard exercises aggregate result sacrifice and reader respawn pressure.

| Pass | Baseline median µs | Candidate median µs | Delta | Baseline p95 µs | Candidate p95 µs | Peak RSS delta |
|---|---:|---:|---:|---:|---:|---:|
| base→cand | 23,030 | 18,064 | -21.6% | 32,861 | 25,432 | -1.0% |
| cand→base | 27,693 | 27,601 | -0.3% | 38,073 | 39,039 | +4.4% |

The large lane is neutral-to-faster and remains inside the preset 5% elapsed
and 10% RSS regression bounds. The candidate reduces worker-envelope and
respawn count, but the throughput win itself does not reproduce and is not
part of the acceptance claim.

## Alternating large + point guard — load-bearing rejection

Ten large reads and ten point reads were submitted in alternating order. The
total burst and the tenth point completion were measured for 15 rounds. This
is the shape that tests whether an internal batch can safely infer policy from
queue pressure alone.

| Metric | Pass | Baseline median µs | Candidate median µs | Delta | Baseline p95 µs | Candidate p95 µs | p95 delta |
|---|---|---:|---:|---:|---:|---:|---:|
| Total burst | base→cand | 15,783 | 19,816 | **+25.6%** | 26,060 | 23,583 | -9.5% |
| Total burst | cand→base | 17,368 | 19,638 | **+13.1%** | 22,292 | 24,191 | +8.5% |
| **Point completion** | base→cand | 14,757 | 16,518 | **+11.9%** | 19,086 | 22,304 | **+16.9%** |
| **Point completion** | cand→base | 14,930 | 16,770 | **+12.3%** | 20,236 | 22,551 | **+11.4%** |

Point-completion p95 exceeds the preset 10% regression limit in both
orderings. Total median also regresses 13-26%. Peak observed RSS remains
bounded (+4.5% / -2.2%), so the failure is scheduling, not memory: a point
query placed in the same worker envelope as large reads cannot complete until
the whole envelope returns. Baseline dispatch can give the next free worker to
that point query independently.

## Interpretation

The exp 209 request-amortisation mechanism is real without a public API:
bounded batching of already-parked homogeneous small selects removes enough
main↔reader messages to improve the focused targets 21-33%, while preserving
the pool's first four-way wave. But queue depth contains no query-cost or
latency-priority information. The same hidden policy groups heterogeneous
work into an indivisible reply envelope and reproduces head-of-line blocking.

That guard is load-bearing. Shipping the candidate would make ordinary
`Future.wait(db.select(...))` performance depend on neighboring query cost in
a way callers cannot see or opt out of. The runtime is therefore rejected and
preserved at `archive/exp-239`; the public API and reader scheduler remain
unchanged.

## Validation notes

- `dart analyze` on the prototype reader files, focused test, and harness:
  clean.
- `dart test test/reader_pool_test.dart`: 24/24 passed with the prototype,
  including per-member error isolation and aggregate-sacrifice respawn.
- An AOT attempt was discarded because standalone `dart compile exe` does not
  bundle this package's native asset; the lane-isolated JIT pair is the
  decision receipt.
- Review found that aggregate sacrifice would increase exposure to the
  existing reader respawn-versus-close startup race. The prototype was already
  rejected on performance policy, so that lifecycle issue was not expanded
  into this experiment's runtime surface.
