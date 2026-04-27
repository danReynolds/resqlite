# Experiment 105: Raise reader pool worker cap

**Date:** 2026-04-25
**Status:** Rejected

## Problem

A11c (Many-Streams Writer Throughput) ships measuring writer
throughput while N=50 reactive streams are subscribed. resqlite's
writer drops from ~50k w/s with no streams to ~4k w/s with 50 streams
subscribed — a ~12× fan-out tax in the no-streams-baseline-relative
metric, ~5–6× when measured against a steady-state burst.

The A11c profile reconnaissance run
([`benchmark/profile/results/a11c-writer-fanout-aggregate.md`](../benchmark/profile/results/a11c-writer-fanout-aggregate.md))
attributed the drop primarily to **reader-pool serialization**:

- Pool size today: `clamp(numProcessors - 1, 2, 4)` — 4 workers on M1
  Pro.
- Per-write fan-out cost is *not* linear in N. N=0→5 streams adds
  +39 µs, N=5→50 only ~30 µs more. Once 4 selectIfChanged dispatches
  are in flight, the rest queue and drain in batches of ≤4.
- Per-write wall ≈ `pool_round_trip × ⌈N/pool_size⌉ + ~30 µs flat`.

The profile recommended raising the pool cap as *"the cheapest
possible win — a config knob, not an architectural change"*.

## Hypothesis

Raising the static cap from 4 to 8 should halve the batch count
(`⌈50/4⌉=13` → `⌈50/8⌉=7`) at N=50, lifting A11c writer throughput
from ~4k w/s toward 6–8k w/s. Non-streaming workloads should be
unaffected (or faintly improved on the high-concurrency reads).

## Approach

Single-line change in
[`lib/src/database.dart`](../lib/src/database.dart):

```dart
// before
final readerCount = (Platform.numberOfProcessors - 1).clamp(2, 4);
// after
final readerCount = (Platform.numberOfProcessors - 1).clamp(2, 8);
```

No new public API, no `Database.open()` option — just a
saturation-point tuning. Deferred the configurable approach pending
evidence the static change is a net win.

Cap=16 and cap=2/1 were also tried as a sanity check on the
saturation-point and reverse-direction questions.

## Results

The hypothesis was wrong: **raising the pool cap regresses A11c
substantially**, and lowering it would help A11c at the cost of
read concurrency. The 5–6× fan-out drop is *not* dominated by
reader-pool serialization the way the profile predicted.

### A11c standalone sweep (3 runs each, post-warmup median, M1 Pro)

| Cap | baseline w/s | disjoint w/s | overlap w/s | Disjoint vs cap=4 |
|---:|---:|---:|---:|---:|
| 1   | 14.1k–22.4k | 6.3k–6.5k | 6.5k–6.9k | **+57 %** |
| 2   | 17.3k–22.2k | 5.4k–5.7k | 5.9k–6.0k | **+42 %** |
| 4 *(current)* | 19.6k–27.3k | 3.7k–4.0k | 4.2k–4.4k | baseline |
| 8   | 19.3k–23.5k | 2.7k–2.9k | 2.8k–2.8k | **−31 %** |
| 16  | 26.1k       | 2.4k       | 2.6k       | **−40 %** |

The relationship is **monotonically inverse**: more readers → fewer
A11c writes/sec. The no-streams baseline is reader-pool-independent
(the writer path doesn't dispatch to the reader pool); the variance
there is run-to-run noise.

### A11c inside the full release suite (single iteration, post-warmup)

Baseline (cap=4) vs candidate (cap=8), from the `--include-slow`
release run:

| Scenario | Baseline (ms) | Candidate (ms) | Δ wall | Baseline w/s | Candidate w/s | Δ w/s |
|---|---:|---:|---:|---:|---:|---:|
| No-streams baseline | 9.98 | 10.32 | +3 % | 50,110 | 48,450 | −3 % (noise) |
| Disjoint (50 streams) | 126.39 | 196.27 | **+55 %** | 3,956 | 2,547 | **−36 %** |
| Overlap (50 streams) | 111.69 | 170.77 | **+53 %** | 4,477 | 2,928 | **−35 %** |

### Concurrent reads (cross-check)

The A11c regression is not free. Lowering the pool cap to chase the
A11c win regresses concurrent reads, and raising the cap *also*
regresses some concurrency points:

| Cap | 1× | 2× | 4× | 8× |
|---:|---:|---:|---:|---:|
| 2 | 0.337 ms | 0.421 ms | 1.035 ms | 1.295 ms |
| 4 *(current)* | 0.332 ms | 0.375 ms | 0.418 ms | 0.823 ms |
| 8 | 0.446 ms | 0.373 ms | 0.670 ms | 0.590 ms |

The release-suite comparison shows the same shape — 4× concurrent at
cap=8 is **+241 %** slower than cap=4 in the full suite (suite
fixture noise larger than standalone run). 1× concurrent reads
regress +14 %. 8× concurrent reads improve.

### Suite-level summary (cap=4 → cap=8)

Artifacts:

- Baseline: [`benchmark/results/2026-04-25T19-43-21-baseline-for-exp105.md`](../benchmark/results/2026-04-25T19-43-21-baseline-for-exp105.md)
- Candidate: [`benchmark/results/2026-04-25T19-47-54-exp105-reader-pool-8.md`](../benchmark/results/2026-04-25T19-47-54-exp105-reader-pool-8.md)

**19 wins, 17 regressions, 134 neutral.**

Notable regressions beyond A11c (all single-iteration, MDE flagged
on the comparison):

| Workload | Baseline | Candidate | Delta |
|---|---:|---:|---:|
| A11b High-Cardinality Fan-out (100 streams × 200 writes) | 240.15 ms | 452.63 ms | **+88 %** |
| Concurrent Reads 4× | 0.41 ms | 1.40 ms | **+241 %** |
| Single Inserts (100 sequential) | 1.92 ms | 3.04 ms | **+58 %** |
| Schema Shapes / Narrow 1000 rows | 0.11 ms | 0.18 ms | **+56 %** |
| Batch Insert 10000 rows | 4.61 ms | 5.52 ms | **+20 %** |
| selectBytes 10000 rows | 3.93 ms | 4.98 ms | **+27 %** |
| Point Query qps | 118,279 | 103,355 | **−13 %** |

The A11b regression (+88 %) is structurally aligned with the A11c
finding — both benchmarks use writer-side fan-out across many
subscribed streams, and both pay the same microtask-queue tax when
more readers complete simultaneously. Single Inserts and Batch
Insert regressions are unexpected (writer path, no reader
involvement) and likely reflect cross-isolate scheduling pressure
from idle reader threads competing for cores; cap=8 leaves only one
core for the main isolate and the writer on the M1 Pro 8-core test
host, versus cap=4 leaving five.

## Why Rejected

The proposed change makes the headline target — A11c writer
throughput — **worse**, not better, and triggers a broad cascade of
single-digit-to-50% regressions across writer-heavy and
many-streams workloads. Three takeaways:

1. **The profile's interpretation is incomplete.** It correctly
   observed that per-write fan-out walls scale as
   `⌈N/pool_size⌉ × round_trip`. But the benchmark wall *also*
   includes the cost of the writer-side handle-and-resolve cycle for
   each completed selectIfChanged: every reply microtask hops through
   the main isolate, runs StreamEngine result-equality short-circuit,
   and on overlap delivers to the listener. With cap=8, 8 replies
   arrive simultaneously and queue 8 microtasks behind the next
   pending write, instead of 4. The serialization that the profile
   flagged as the bottleneck was actually *throttling* completion-side
   work into a steady stream the writer could interleave with.
   Removing the throttle just moves the bottleneck.

2. **Cap=4 is at the right point on the curve.** Lowering helps
   A11c (where main-isolate completion handling dominates) but hurts
   concurrent reads (where parallel dispatch dominates). Raising
   helps 8× concurrent reads but regresses everything else. The
   default sits where neither side regresses materially.
   Per-workload tuning — e.g. a `Database.open()` option — would
   help niche workloads but adds a knob no shipping app would know
   to flip without first running A11c-shaped probes.

3. **Idle-isolate cost is real on bounded-core hardware.** On an
   8-core M1 Pro, raising cap from 4 to 8 removes the writer's
   easy-scheduling headroom. The Single Inserts and Schema Shapes
   regressions are not reader-pool-related — they're the writer
   getting evicted from a core by idle reader isolates the OS hasn't
   parked yet. This makes the cap a function of host concurrency,
   not just app-level subscriber load; a `cores-1` style upper bound
   already encodes that, and the current `clamp(2, 4)` is the
   correct realization.

The real lever for A11c is **batching the per-write fan-out itself**,
not parallelizing it harder. Re-query batching (revisit exp 071 / 093
/ 094 under A11c) and column-tracking dispatch elision (exp 052) both
remain on the table; this experiment closes off the pool-cap path.

## Decision

Reject.

Recommendation to the maintainer: **do not tag** `archive/exp-105`.
The implementation is a one-line change; preserving it adds nothing.
The valuable artifact is this writeup — the cap-vs-A11c sweep and
the suite-wide regression cascade revising the profile's
interpretation.
