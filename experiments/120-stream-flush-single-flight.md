# Experiment 120: Stream flush single-flight admission

**Date:** 2026-05-01
**Status:** In Review
**Direction:** `stream-rerun-dispatch`, `measurement-system`

## Problem

Experiment 118 eliminated ReaderPool wake amplification: overloaded dispatch
still parks, but `dispatcherWakeRetryTotal` stays at zero. The remaining
stream-shaped pressure is therefore not another wake-policy problem.

The next suspect is stream re-query admission. `StreamEngine._flushQueue`
checks `pool.hasAvailableWorker` before starting each re-query, but `_requery`
then awaited the already-resolved pool again before it actually called
`selectIfChanged`. That extra async gap meant the flush loop could observe
stale worker availability and admit more re-queries than the reader pool could
take immediately, leaving the excess work to park inside `ReaderPool._dispatch`.

## Hypothesis

If `_flushQueue` is made single-flight and each admitted re-query consumes a
reader slot before the loop checks availability again, then app-shaped stream
workloads should stop producing parked dispatchers.

Accept for review if:

- A11c overlap and keyed-PK profile rows reduce `dispatcherParkedTotal` and
  `dispatcherMaxParkedConcurrent`;
- `dispatcherWakeRetryTotal` remains zero;
- A11c disjoint stays at zero parked dispatchers;
- release guardrails do not reproduce exp 100's high-cardinality fan-out
  regression.

## Approach

`StreamEngine` now tracks whether a queue flush is already active. Re-entrant
flush requests mark `_flushAgain` instead of starting another overlapping
admission pass.

The flush loop also passes the already-resolved `ReaderPool` into `_requery`.
That removes the redundant `await _pool` inside `_requery`, so the call to
`pool.selectIfChanged` reaches `ReaderPool._dispatch` synchronously. Each
admitted re-query marks a worker busy before `_flushQueue` tests
`pool.hasAvailableWorker` again.

Added a focused profile harness:

```text
benchmark/profile/stream_flush_single_flight_profile.dart
```

It measures the A11c baseline/disjoint/overlap and keyed-PK subscription
shapes under `-DRESQLITE_PROFILE=true`.

## Results

Profile commands:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_flush_single_flight_profile.dart --label=baseline
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_flush_single_flight_profile.dart --label=candidate
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_flush_single_flight_profile.dart --label=candidate-confirm
```

Profile counter A/B:

| workload | baseline wall_ms | candidate wall_ms | baseline parked | candidate parked | baseline max_parked | candidate max_parked | baseline retries | candidate retries |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 135.32 | 95.94 | 0 | 0 | 0 | 0 | 0 | 0 |
| A11c disjoint | 125.29 | 106.72 | 0 | 0 | 0 | 0 | 0 | 0 |
| A11c overlap | 281.82 | 139.95 | 3084 | 0 | 46 | 0 | 0 | 0 |
| keyed PK subscriptions | 283.39 | 225.62 | 1106 | 0 | 46 | 0 | 0 | 0 |

Candidate confirmation pass:

| workload | wall_ms | parked_total | wake_retry_total | max_parked |
|---|---:|---:|---:|---:|
| A11c baseline | 88.80 | 0 | 0 | 0 |
| A11c disjoint | 95.00 | 0 | 0 | 0 |
| A11c overlap | 159.21 | 0 | 0 | 0 |
| keyed PK subscriptions | 427.66 | 0 | 0 | 0 |

The keyed-PK profile wall time is noisy because the profile harness waits for a
quiet stream-emission window. The stable decision signal is the counter result:
both candidate passes keep the previously parking stream workloads at zero
parks, zero wake retries, and zero max parked dispatchers.

Release guardrail commands:

```text
dart run benchmark/suites/many_streams_writer_throughput.dart
dart run benchmark/suites/keyed_pk_subscriptions.dart
dart run benchmark/suites/high_cardinality_fanout.dart
```

Adjacent baseline/candidate release comparison:

| workload | baseline | candidate | delta | read |
|---|---:|---:|---:|---|
| A11c no-streams baseline | 27.41 ms | 30.46 ms | +11.1% | noise/control; no stream flush path |
| A11c disjoint | 22.00 ms | 20.23 ms | -8.0% | supportive |
| A11c overlap | 54.40 ms | 47.69 ms | -12.3% | win |
| Keyed PK subscriptions | 222.46 ms | 222.71 ms | +0.1% | neutral |
| High-cardinality fan-out | 240.19 ms | 237.31 ms | -1.2% | neutral |

## Decision

**Accept for review.**

The implementation removes the remaining profile-visible stream dispatch
parking without changing public API shape and without repeating exp 100's
high-cardinality fan-out regression. The release-suite win is modest, but the
profile counter gate is decisive: the workloads that previously parked inside
`ReaderPool._dispatch` no longer enter the parked path.

## Future Notes

This closes the specific stream-admission accuracy issue exposed by the exp 115
counters. Further stream-rerun work should not target ReaderPool parking unless
a new workload makes `dispatcherParkedTotal` nonzero again. The next likely
stream wins are more precise invalidation before re-query work is scheduled
or keyed/row-level observer APIs for the keyed-PK miss path.
