# Experiment 145: Inline stream flush dequeue

**Date:** 2026-06-08
**Status:** Rejected
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** None

## Problem

`StreamEngine._flushQueue` bounds stream re-query admission with
`ReaderPool.availableWorkerCount`, then builds a temporary list before it
dequeues entries:

```dart
final dequeued = _requeryQueue.take(_pool.availableWorkerCount).toList();
```

`ReaderPool.availableWorkerCount` also used `_workers.where(...).length`.
Both are small Dart collection helpers on a stream fan-out path. Exp 120 and
exp 122 already fixed the correctness and dispatch-pressure shape of stream
admission, but the current implementation still had a tiny allocation-shaped
cleanup available.

## Hypothesis

Replacing the helper chain with straight loops should remove avoidable
collection objects without changing stream ordering or public behavior:

- count available workers with a manual loop;
- dequeue directly from the `LinkedHashSet` while capacity remains;
- leave `_requery` completion-driven follow-up flushes unchanged.

Accept only if the focused stream profile shows a clear improvement or at
least a neutral result across the measured stream shapes. Reject if the result
is mixed, because exp 120/122 already drove `dispatcherParkedTotal`,
`dispatcherWakeRetryTotal`, and `dispatcherMaxParkedConcurrent` to zero.

## Approach

The candidate patch changed only two private methods:

```dart
int get availableWorkerCount {
  var count = 0;
  for (final worker in _workers) {
    if (worker.isAvailable) count++;
  }
  return count;
}
```

```dart
var available = _pool.availableWorkerCount;
while (available > 0 && _requeryQueue.isNotEmpty) {
  final entry = _requeryQueue.first;
  _requeryQueue.remove(entry);
  _requery(entry);
  available--;
}
```

The implementation was tested with the existing profile-mode stream admission
harness, then reverted after the result did not clear the acceptance bar. No
runtime code from this experiment is kept.

## Results

Focused command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_concrete_pool_profile.dart --label=<label>
```

Full aggregate record:

- [`benchmark/profile/results/exp-145-stream-flush-inline-dequeue.md`](../benchmark/profile/results/exp-145-stream-flush-inline-dequeue.md)

Two-pass profile A/B:

| workload | baseline runs ms | baseline median ms | candidate runs ms | candidate median ms | delta |
|---|---:|---:|---:|---:|---:|
| A11c baseline | 51.41, 80.57 | 65.99 | 55.22, 48.40 | 51.81 | -21.5% |
| A11c disjoint | 56.21, 64.47 | 60.34 | 61.05, 58.62 | 59.84 | -0.8% |
| A11c overlap | 116.18, 147.79 | 131.99 | 111.64, 125.62 | 118.63 | -10.1% |
| keyed PK subscriptions | 25.06, 24.79 | 24.93 | 23.85, 32.06 | 27.96 | +12.2% |

Counter result:

| workload | baseline parked/retries/max | candidate parked/retries/max |
|---|---:|---:|
| A11c baseline | 0 / 0 / 0 | 0 / 0 / 0 |
| A11c disjoint | 0 / 0 / 0 | 0 / 0 / 0 |
| A11c overlap | 0 / 0 / 0 | 0 / 0 / 0 |
| keyed PK subscriptions | 0 / 0 / 0 | 0 / 0 / 0 |

The wall-time rows are mixed and noisy. A11c overlap trends better, but the
keyed-PK row moves the wrong way on the two-run median and the main dispatch
counters were already zero on baseline. That means the patch is not removing
the active stream bottleneck; at best it is a sub-signal allocation cleanup.

## Decision

Rejected.

The code is mechanically correct, but it does not produce decision-quality
evidence under the current profile workload. Keeping it would add churn to a
stream-admission path that is already behaviorally settled by exp 120 and exp
122.

The important result is negative: do not spend another implementation pass on
`_flushQueue` collection-helper cleanup unless a future allocation profile
shows this exact temporary list or availability count as material.

## Future Notes

Future stream-dispatch work still needs the signal requested by
`signals.json`: completion-side scheduling cost or writer-side dispatch wall.
This experiment does not change that route. It only closes the small
`take(...).toList()` cleanup as below current signal.
