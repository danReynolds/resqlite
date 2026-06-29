# Experiment 118: FIFO dispatch waiters with counter gate

**Date:** 2026-05-01
**Status:** Accepted
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** none (acceptance gated on exp 115 profile-mode counters dropping `dispatcherWakeRetryTotal` to zero; no release-suite run because the change is invisible to wall-time outside `kProfileMode`)

## Problem

Experiment 114 showed that the old shared-completer reader-pool wakeup could be
structurally wasteful: one worker-free event woke every parked dispatcher, one
caller won the slot, and the rest scanned the pool and re-parked. That result
was rejected after rebasing because the release stream workloads stopped
exercising the parked-dispatcher path once exp 106 elided most stream re-runs
before reader-pool admission.

Experiment 115 closed the measurement gap by adding profile-only counters for
parked dispatchers, wake retries, and max parked concurrency. That makes the
same dispatch-policy change evaluable without relying first on a noisy wall-time
delta.

## Hypothesis

Replacing the single shared dispatch completer with FIFO one-shot waiters should
turn each worker-free event into one resumed dispatcher. On a workload that
exceeds the four-reader pool, `dispatcherWakeRetryTotal` should drop to zero
while `dispatcherMaxParkedConcurrent` still proves the workload reached the
parked path.

Accept for PR review if:

- profile counters show sustained parking on the workload
- wake retries drop from the shared-completer baseline to zero
- reader-pool correctness tests pass
- release concurrent-read medians do not show an obvious targeted regression

## Approach

`ReaderPool` now keeps a `Queue<Completer<void>>` of parked dispatch waiters
instead of one shared `_workerAvailable` completer.

- `_dispatch` enqueues a fresh sync completer when no worker is available.
- `_notifyAvailable` completes only the oldest waiter.
- `close()` drains every waiter so parked dispatchers can observe `_closed`.
- The exp 115 counters remain in place and now measure whether the FIFO policy
  eliminates re-park wake amplification.

Counter comments and the dispatcher profile harness wording were updated so
they describe both the old shared-completer baseline and the new FIFO behavior.

## Results

Profile-mode command:

```text
/Users/dan/Coding/flutter_arm64/bin/dart run -DRESQLITE_PROFILE=true benchmark/profile/dispatcher_park_profile.dart
```

Median of three full harness runs:

| concurrency | baseline parked | FIFO parked | baseline retries | FIFO retries | baseline max parked | FIFO max parked | baseline wall | FIFO wall |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 8 | 10 | 4 | 6 | 0 | 4 | 4 | 0.34 ms | 0.32 ms |
| 16 | 78 | 12 | 66 | 0 | 12 | 12 | 0.78 ms | 0.60 ms |
| 32 | 406 | 28 | 378 | 0 | 28 | 28 | 1.20 ms | 1.28 ms |

The direct signal is clean:

- `dispatcherWakeRetryTotal` drops to zero at every overloaded concurrency.
- `dispatcherParkedTotal` drops to exactly the unavoidable
  `concurrency - pool_size` shape.
- `dispatcherMaxParkedConcurrent` is unchanged, proving both baseline and
  candidate exercised the same parked-dispatcher depth.

Release concurrent-read command:

```text
/Users/dan/Coding/flutter_arm64/bin/dart run benchmark/suites/concurrent_reads.dart
```

Single-pass release medians for resqlite:

| concurrency | baseline wall | FIFO wall | delta |
|---:|---:|---:|---:|
| 1 | 0.301 ms | 0.347 ms | +15.3 % |
| 2 | 0.325 ms | 0.326 ms | +0.3 % |
| 4 | 0.400 ms | 0.402 ms | +0.5 % |
| 8 | 0.863 ms | 0.724 ms | -16.1 % |

The release wall-time result is supportive only at 8x and too small/noisy to be
the primary acceptance signal. The profile counters are the decision signal.

## Decision

**Keep in review.** The experiment succeeds on the newly enabled counter gate:
FIFO dispatch eliminates wake amplification on a workload that demonstrably
parks past the worker count. The production diff is small and release
concurrent reads do not show an obvious targeted regression, but the PR should
still be reviewed as a behavior-preserving reader-pool scheduling change.

## Future Notes

The next dispatch experiment should not try another queue policy until it has a
workload whose `dispatcherWakeRetryTotal` or `dispatcherMaxParkedConcurrent`
shows remaining headroom. If this PR merges, reader-pool wake amplification is
no longer the main dispatch signal; future work should look for admission,
completion batching, or stream-rerun sources that still produce measurable
parking.
