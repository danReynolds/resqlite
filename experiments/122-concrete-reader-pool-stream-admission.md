# Experiment 122: Concrete reader-pool stream admission

**Date:** 2026-05-02
**Status:** In Review
**Direction:** `stream-rerun-dispatch`, `measurement-system`

## Problem

Experiment 118 eliminated ReaderPool wake amplification: overloaded dispatch
still parks, but `dispatcherWakeRetryTotal` stays at zero. The remaining
stream-shaped pressure is therefore not another wake-policy problem.

Experiment 119 identified stream re-query admission/completion as the next
target. Exp 120 then landed the first half of that fix on main: each
`_flushQueue` pass snapshots `ReaderPool.availableWorkerCount` and admits only
that many entries.

That still left the async boundary that review called out. PR #85 first tried
to guard overlapping flushes with `_isFlushingQueue` / `_flushAgain`, but that
was treating the symptom. The root issue was that `StreamEngine` held a
`Future<ReaderPool>`. Even after that future had resolved, stream re-query
admission still crossed an async handoff before the re-query could claim a
reader slot.

The simpler fix is to initialize `StreamEngine` only after the reader pool has
spawned, so the stream engine owns a concrete `ReaderPool`. That makes
`_flushQueue` a synchronous admission step again: snapshot
`availableWorkerCount`, dequeue only that many entries, and let completed
re-queries trigger the next flush.

## Hypothesis

If `StreamEngine` owns a concrete `ReaderPool`, `_flushQueue` no longer needs
an async single-flight guard. Each flush pass can synchronously bound admission
by `ReaderPool.availableWorkerCount`, and each admitted re-query reaches
`ReaderPool._dispatch` without first awaiting the pool future. That should
preserve exp 120's zero-park counter result while reducing the implementation
to a single queue and the existing re-query completion drain.

Accept for review if:

- A11c overlap and keyed-PK profile rows keep `dispatcherParkedTotal` and
  `dispatcherMaxParkedConcurrent` at zero after rebasing on exp 120;
- `dispatcherWakeRetryTotal` remains zero;
- A11c disjoint stays at zero parked dispatchers;
- release guardrails do not reproduce exp 100's high-cardinality fan-out
  regression.

## Approach

`Database` now initializes the reader pool first, then constructs
`StreamEngine(readerPool)`, then spawns the writer. The three initialized
components are published through a single initialization future so public API
methods still await readiness without exposing partially initialized state.

`StreamEngine` now stores `ReaderPool` directly instead of `Future<ReaderPool>`.
`_flushQueue` stays synchronous and bounded:

```dart
final dequeued = _requeryQueue.take(_pool.availableWorkerCount).toList();

for (final entry in dequeued) {
  _requery(entry);
  _requeryQueue.remove(entry);
}
```

There is no `_isFlushingQueue` or `_flushAgain` state. Re-query completion
already calls `_flushQueue()` from `finally`, so entries beyond current reader
capacity remain queued until a worker frees.

Added a focused profile harness:

```text
benchmark/profile/stream_concrete_pool_profile.dart
```

It measures the A11c baseline/disjoint/overlap and keyed-PK subscription
shapes under `-DRESQLITE_PROFILE=true`. The A11c and keyed-PK setup now lives
in `benchmark/profile/audit_workloads.dart` so this harness, the exp 119
dispatch pressure audit, and the exp 121 invalidation traversal audit cannot
drift apart.

The test-only `Database.streamEngine` getter is removed. The tests that need
stream registry size now read it through `Database.diagnostics().streamLength`,
which keeps the verification path on a public diagnostics surface instead of a
private engine handle. The stream recovery test also uses public writes to
trigger re-query after a schema break rather than calling
`StreamEngine.onDependencyChanges` directly.

The stream coalescing tests now include a close-race case that starts
overlapping stream invalidations and closes the database while re-queries are
active, asserting that close completes and all subscriber streams receive done.

External check: the current Dart async documentation still frames `await` as an
asynchronous boundary for `Future` work, and `Completer.sync` remains the
documented tool for synchronous propagation only when completing in tail
position. That supports keeping this fix local to stream admission order rather
than changing the reader-pool waiter contract again.

Sources checked:

- Dart async/await guide:
  https://dart.dev/libraries/async/async-await
- `Completer.sync` API:
  https://api.dart.dev/dart-async/Completer/Completer.sync.html

## Results

Profile commands:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_concrete_pool_profile.dart --label=baseline
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_concrete_pool_profile.dart --label=candidate
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_concrete_pool_profile.dart --label=candidate-confirm
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_concrete_pool_profile.dart --label=candidate-current
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_concrete_pool_profile.dart --label=post-rebase
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_concrete_pool_profile.dart --label=concrete-pool-rebased
```

Profile counter A/B:

| workload | baseline wall_ms | candidate wall_ms | baseline parked | candidate parked | baseline max_parked | candidate max_parked | baseline retries | candidate retries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 135.32 | 95.94 | 0 | 0 | 0 | 0 | 0 | 0 |
| A11c disjoint | 125.29 | 106.72 | 0 | 0 | 0 | 0 | 0 | 0 |
| A11c overlap | 281.82 | 139.95 | 3084 | 0 | 46 | 0 | 0 | 0 |
| keyed PK subscriptions | 283.39 | 225.62 | 1106 | 0 | 46 | 0 | 0 | 0 |

Original PR confirmation pass:

| workload | wall_ms | parked_total | wake_retry_total | max_parked |
|---|---:|---:|---:|---:|
| A11c baseline | 104.35 | 0 | 0 | 0 |
| A11c disjoint | 100.13 | 0 | 0 | 0 |
| A11c overlap | 145.34 | 0 | 0 | 0 |
| keyed PK subscriptions | 223.75 | 0 | 0 | 0 |

Post-rebase confirmation on top of exp 120:

| workload | wall_ms | parked_total | wake_retry_total | max_parked |
|---|---:|---:|---:|---:|
| A11c baseline | 89.25 | 0 | 0 | 0 |
| A11c disjoint | 90.72 | 0 | 0 | 0 |
| A11c overlap | 137.25 | 0 | 0 | 0 |
| keyed PK subscriptions | 427.75 | 0 | 0 | 0 |

Concrete-pool rebased confirmation:

| workload | wall_ms | parked_total | wake_retry_total | max_parked |
|---|---:|---:|---:|---:|
| A11c baseline | 197.57 | 0 | 0 | 0 |
| A11c disjoint | 313.75 | 0 | 0 | 0 |
| A11c overlap | 697.27 | 0 | 0 | 0 |
| keyed PK subscriptions | 83.80 | 0 | 0 | 0 |

The keyed-PK profile wall time is noisy because the profile harness waits for a
quiet stream-emission window. The stable decision signal is the counter result:
all candidate passes, including the post-exp-120 rebase, keep the stream
workloads at zero parks, zero wake retries, and zero max parked dispatchers.

Release guardrail commands:

```text
dart run benchmark/suites/many_streams_writer_throughput.dart
dart run benchmark/suites/keyed_pk_subscriptions.dart
dart run benchmark/suites/high_cardinality_fanout.dart
```

Adjacent baseline/candidate release comparison:

| workload | baseline | candidate | delta | read |
|---|---:|---:|---:|---|
| A11c no-streams baseline | 27.41 ms | 26.47 ms | -3.4% | noise/control; no stream flush path |
| A11c disjoint | 22.00 ms | 21.23 ms | -3.5% | neutral/supportive |
| A11c overlap | 54.40 ms | 48.37 ms | -11.1% | win |
| Keyed PK subscriptions | 222.46 ms | 233.45 ms | +4.9% | neutral |
| High-cardinality fan-out | 240.19 ms | 245.25 ms | +2.1% | neutral |

## Decision

**Accept for review.**

The implementation is a simplification follow-up to exp 120, not a new public
read/write API and not a fresh claim that current main still parks under the
focused profile. It preserves the zero-park counter result after rebasing onto
exp 120, removes the async admission boundary that made single-flight tempting,
and keeps test coverage on public diagnostics plus public stream invalidation
behavior. The earlier A/B still documents why the admission area was worth
closing; the post-rebase result documents that the concrete-pool admission path
stays neutral on the counter gate.

## Future Notes

This closes the specific stream-admission accuracy issue exposed by the exp 115
counters. Further stream-rerun work should not target ReaderPool parking unless
a new workload makes `dispatcherParkedTotal` nonzero again. The next likely
stream wins are more precise invalidation before re-query work is scheduled
or keyed/row-level observer APIs for the keyed-PK miss path.
