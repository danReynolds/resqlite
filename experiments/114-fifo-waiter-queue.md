## Experiment 114: FIFO waiter queue for ReaderPool dispatch

**Date:** 2026-04-30
**Status:** Rejected
**Direction:** `stream-rerun-dispatch`

## Problem

[Exp 105](105-reader-pool-sizing.md)'s profile attributed A11c writer
throughput loss to "completion-side microtask churn on the main
isolate" — the per-write wall closely matched
`pool_round_trip × ⌈N/pool_size⌉ + ~30 µs flat`.

There was a small mechanism in the same neighborhood that nothing had
attacked yet: [`ReaderPool._dispatch`](../lib/src/reader/reader_pool.dart)
parked every backpressured caller on a **single shared `Completer<void>`**.
When a worker became free, `_notifyAvailable()` completed that one
completer, which woke every parked dispatcher in the same microtask.
Each woken dispatcher re-scanned the worker list, exactly one of them
won the freed slot, and the remaining `N − 1` each fell through to the
`_workerAvailable ??= Completer.sync()` arm and re-parked on a brand
new shared completer.

So every "one worker freed" event triggered an O(N) scan-and-re-park
burst at exactly the moment the main isolate was already busy with
completion handlers.

## Hypothesis

Replacing the single shared completer with a FIFO queue of one-shot
waiters should let each worker-free event wake exactly one parked
dispatcher — the one that arrived first — and leave the others
asleep. Same FIFO-by-arrival fairness, same sync-completer scheduling
semantics, no other behavioral change.

Accept if A11c overlap, A11b/streaming fan-out, and the long-text
unchanged-fanout stream workload show repeatable wins outside the
per-benchmark MDE_ci threshold, with no regression on point queries
or the no-streams writer baseline.

## Approach

`lib/src/reader/reader_pool.dart`:

- Replace `Completer<void>? _workerAvailable` with
  `final Queue<Completer<void>> _waiters = Queue<Completer<void>>()`.
- `_notifyAvailable()` becomes
  `if (_waiters.isNotEmpty) _waiters.removeFirst().complete()`.
- `_dispatch` parks itself with a fresh
  `final waiter = Completer<void>.sync(); _waiters.add(waiter); await
  waiter.future`.
- `close()` drains the queue with
  `while (_waiters.isNotEmpty) _waiters.removeFirst().complete()`.

The waiter is `Completer<void>.sync()` to preserve the previous
in-handler wake-and-claim behavior. `Queue` is imported from
`dart:collection`. Steady-state memory is unchanged (the queue is
empty when no backpressure exists).

Validation pre-benchmark: `dart test test/reader_pool_test.dart` (21/21,
including 50-concurrent-query stress) and
`dart test test/database_test.dart test/stream_test.dart test/transaction_test.dart`
(102/102).

## Results

### First measurement (pre-rebase, against baseline missing exp 106 polish)

The first benchmark pass landed before [exp 106 polish](106-column-level-deps.md)
(PR #48) merged. Against that older baseline, 5-pass A/B reported
**11 wins, 1 derived-metric regression, 164 neutral**:

| Benchmark | Δ |
|---|---:|
| Streaming / Long-Text Unchanged Fanout (8 streams × 256 rows × 4KB TEXT) | -32 % |
| Many-Streams Writer Throughput / Overlapping column writes (50 × 500) | -10 % |
| Streaming / Fan-out (10 streams) | -18 % |

These looked like the predicted dispatch-heavy stream wins. The PR was
opened on that evidence.

### Re-measurement after rebase onto main with exp 106

Artifacts (the canonical pair for this experiment):
- `benchmark/results/2026-04-30T13-49-15-baseline-for-exp114.md`
- `benchmark/results/2026-04-30T14-07-26-exp114-fifo-waiters.md`

Same change, same workloads, but rebased on top of exp 106 polish.
**Suite-level: 4 wins, 0 regressions, 172 neutral.** The streaming
wins above all collapsed into the noise floor:

| Benchmark | Pre-rebase Δ | Post-rebase Δ | Post-rebase MDE |
|---|---:|---:|---:|
| Long-Text Unchanged Fanout | **-32 %** | +1.7 % | ±44 % |
| Streaming Fan-out (10 streams) | **-18 %** | -15 % | ±43 % |
| A11c Overlapping column writes | **-10 %** | +4.7 % | ±35 % |

What's left after the rebase:

| Benchmark | Δ | Notes |
|---|---:|---|
| Concurrent Reads 2× concurrency (wall) | -35 % | Above ±26 % threshold but on a 0.34 ms benchmark with 2 queries vs 4 workers — no parking expected; likely run-noise the rebased pass happened to capture |
| Concurrent Reads 2× concurrency (main) | -35 % | Same caveat |
| Scaling 5000 rows + jsonEncode | -11 % | Above ±11 % threshold; not a target path |
| Concurrent Reads 8× concurrency | -19 % | Within ±24 % noise threshold but trending in the right direction |

The Concurrent Reads 2× win does not justify the change on its own:
2 in-flight reads vs 4 workers means zero parked dispatchers, so the
FIFO swap should be invisible there. The 8× case (where parking
genuinely happens) is within noise.

## Decision

**Rejected — implementation reverted, exp 106 absorbed the contention.**

Why the rebase erased the targeted wins:

1. Exp 114 only does work when there are **parked dispatchers** in the
   pool — `_notifyAvailable` is a no-op against an empty `_waiters`
   queue, and the dispatch loop never reaches its park branch when a
   slot is free.
2. The marquee benchmarks (Long-Text Unchanged Fanout, A11c Overlap,
   Streaming Fan-out) used to fire 8 / 50 / 10 stream re-queries per
   write, all of which contended for 4 worker slots, so 4–46 callers
   were parked per write.
3. Exp 106 polish elides those stream re-queries on the **writer
   side**, before they reach the pool: a write to column X skips every
   stream whose projected columns don't intersect X. The streams that
   used to pile up in `_waiters` are now never scheduled.
4. With ~0–1 in-flight stream reruns per write post-exp-106, the
   parked-dispatcher path is rarely hit, so the FIFO swap has no
   workload to express its win on.

Exp 114's structural improvement is real (fewer wakeups per worker-free
event is provably better), but it is invisible against current main.
Following the same pattern as exp 099 (8-byte FNV fold that didn't run
because the benchmark didn't carry long cells), the implementation is
reverted and the doc + benchmark artifacts ship as the durable record.
The change can be cherry-picked later if a workload reintroduces
sustained parked-dispatcher contention.

## Future Notes

The change becomes interesting again if any of these emerge:

- A read-only concurrency workload that genuinely fills `_waiters`
  past the worker count for sustained periods (the existing Concurrent
  Reads 8× shape only briefly parks; a longer-running variant could
  expose it).
- A streaming workload whose column projections all intersect the
  modified columns (so exp 106's elision can't fire and reruns pile
  back up in the pool).
- A profile mode that directly counts parked-dispatcher-events per
  worker-free, so the wake-amplification cost can be measured without
  needing a workload that surfaces it as wall time.

If revisiting, the implementation pattern is straightforward:
`Queue<Completer<void>> _waiters` instead of
`Completer<void>? _workerAvailable`, with `_notifyAvailable` doing
`removeFirst().complete()` and `close()` draining the queue. See the
git history of this PR for the exact diff.
