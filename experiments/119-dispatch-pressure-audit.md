# Experiment 119: Post-FIFO dispatch pressure audit

**Date:** 2026-05-01
**Status:** In Review
**Direction:** `stream-rerun-dispatch`, `measurement-system`
**Benchmark Run:** none (profile-mode audit only; the deliverable is the post-FIFO counter snapshot, not a release-suite delta)

## Problem

Experiment 118 fixed the old shared-completer wake amplification inside
`ReaderPool._dispatch`: overloaded reads still park, but FIFO waiters keep
`dispatcherWakeRetryTotal` at zero.

That leaves a sharper question before trying another dispatch optimization:
does current main still have real workloads that create reader-pool dispatch
pressure, or did exp 118 close the remaining dispatch signal?

## Hypothesis

After FIFO waiters, real stream workloads should not show a wake-retry signal.
If they still show `dispatcherParkedTotal` or high
`dispatcherMaxParkedConcurrent`, the next useful work is not another
ReaderPool wake policy. It should target stream re-query admission,
completion-side scheduling, or a more precise invalidation source before work
reaches the pool.

Accept this as a measurement experiment if:

- a direct-read control still proves the counters are live;
- post-FIFO workloads keep `dispatcherWakeRetryTotal` at zero;
- at least one app-shaped stream workload identifies whether remaining
  pressure is absent, admission-shaped, or completion-shaped.

## Approach

Added a resqlite-only profile harness:

```text
benchmark/profile/dispatch_pressure_audit.dart
```

The harness runs three shapes with `-DRESQLITE_PROFILE=true`:

- a direct-read overload control: 32 concurrent selects against the clamped
  reader pool;
- A11c-style many-stream writer throughput: 50 streams, 500 writes, disjoint
  and overlapping columns;
- keyed-PK subscriptions: 50 fixed primary-key streams, 200 deterministic
  random writes.

The harness snapshots the exp 115 counters around the measured work and writes
a committable aggregate markdown file under `benchmark/profile/results/`.

## Results

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`)

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/dispatch_pressure_audit.dart --markdown
```

Single profile pass:

| workload | shape | wall_ms | parked_total | wake_retry_total | max_parked | invalidate_count | intersection_entries | emissions | observed_hits |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| direct reads control | 32 concurrent selects, median burst | 1.18 | 28 | 0 | 28 | 0 | 0 | 0 | 0 |
| A11c baseline | 0 streams x 500 writes | 98.37 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| A11c disjoint | 50 streams x 500 writes | 105.59 | 0 | 0 | 0 | 500 | 25000 | 0 | 0 |
| A11c overlap | 50 streams x 500 writes | 149.54 | 3590 | 0 | 46 | 500 | 25000 | 7 | 0 |
| keyed PK subscriptions | 50 streams x 200 random writes | 431.56 | 1152 | 0 | 46 | 200 | 10000 | 3 | 3 |

The direct-read control proves the counters are live: overloaded reads still
park exactly as expected, with zero wake retries.

The important post-FIFO result is that every workload keeps
`dispatcherWakeRetryTotal = 0`. The remaining pressure is not shared-wake
amplification.

Two stream workloads still show real parking:

- A11c overlap creates 3,590 dispatch parks and reaches 46 parked dispatchers.
- Keyed-PK subscriptions create 1,152 dispatch parks and also reach 46 parked
  dispatchers, even though visible emissions match the 3 observed PK hits.

Disjoint A11c stays at zero parks, which confirms column-level invalidation
skips reader-pool work before admission when the write is projection-disjoint.

## Decision

**Accept for review — measurement.**

Experiment 119 changes the next dispatch question. ReaderPool wake policy is
not the active target anymore because wake retries are gone. Current main still
has stream-shaped dispatch pressure, but it is admission/completion pressure:
overlap and keyed-PK workloads enqueue enough stream re-query work to create
parked dispatchers despite coalesced or hash-suppressed visible emissions.

## Future Notes

The natural next dispatch experiment is a bounded stream re-query admission
change, such as making `_flushQueue` single-flight or otherwise preventing
multiple flush passes from racing beyond current reader availability. Accept
only if it reduces `dispatcherParkedTotal`/`dispatcherMaxParkedConcurrent` on
A11c overlap or keyed-PK without hurting disjoint writes.

If an admission-only change reduces counters but not wall time, branch out.
The remaining larger wins probably require more precise invalidation before
stream re-query work is scheduled, or a different active direction such as
wide batch parameter encoding.
