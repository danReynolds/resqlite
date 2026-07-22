# Experiment 239: transparent select overflow batching

**Date:** 2026-07-22
**Status:** Rejected
**Category:** Moonshot
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** none — focused
  [`benchmark/experiments/select_overflow_batch.dart`](../benchmark/experiments/select_overflow_batch.dart),
  detached-worktree A/B with identical public calls, lane isolation, and a
  complete order flip; receipt in
  [`benchmark/results/2026-07-22T10-33-28Z-exp239-select-overflow-batch.md`](../benchmark/results/2026-07-22T10-33-28Z-exp239-select-overflow-batch.md).
  No release-suite lane represents twenty heterogeneous reads issued in one
  burst, so the focused harness is the durable gate.
**Archive:** [`archive/exp-239`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-239)

## Problem

[Experiment 209](https://github.com/danReynolds/resqlite/pull/223) proved that
one reader-isolate envelope can amortize many small unrelated SELECTs:
twenty point reads improved 60-73% and twenty roughly-ten-row reads improved
42-46%. Four large reads regressed 175-308% because the explicit batch ran
serially on one worker instead of using the four-reader pool.

The implementation exposed `selectAll`, however, which required callers to
predict the crossover and choose a second public read API. The PR was closed
under resqlite's near-frozen-API rule: a real mechanism win was not enough to
justify making every caller choose batching versus parallelism from query
shape.

That left one materially different question. The reader pool already knows
which requests have missed its first parallel wave and are parked behind busy
workers. Could it amortize only those overflow requests internally, keeping
ordinary `Future.wait(db.select(...))`, without imposing exp 209's one-worker
large-read penalty or adding public policy?

## Hypothesis

Assumption challenged: **a reader-pool request that is already parked must pay
its own isolate message and completion callback; internal batching necessarily
requires callers to opt into a second API.**

The candidate keeps the first pool-wide wave unchanged, batches only a FIFO
prefix of already-parked plain `SelectRequest`s, shards that overflow across
the available workers, and caps an envelope at four queries. The primary gate
is at least 15% faster median wall for twenty point reads and twenty
roughly-ten-row reads in both orderings.

The moonshot is rejected if any hidden-policy cost reproduces: four-way or
sequential admission regresses, twenty 10,000-row reads lose more than 5%, peak
RSS grows more than 10%, or point completion p95 in an alternating
large/point burst regresses more than 10%.

## Approach

The prototype changes only the private reader protocol and pool scheduler:

- replace waiter-only parking with a FIFO queue of concrete request/completer
  pairs;
- dispatch immediately whenever a request fits in the first available-reader
  wave;
- when a reader becomes free, batch only the queue's contiguous plain-select
  prefix, with width `min(4, ceil(prefix / readerCount))`;
- keep `selectWithDeps`, `selectIfChanged`, and `selectBytes` on individual
  envelopes and stop batching at any such request, preserving FIFO admission;
- execute batch members through the existing `executeQuery` path, preserve
  result order, and isolate an error to its original future;
- aggregate estimated result bytes and use the existing `Isolate.exit`
  sacrifice path once per envelope above 256 KiB; and
- retain one-call/one-reader-message behavior under Tracelite until batched
  correlation has an explicit representation.

The public API and every benchmark call stay byte-for-byte unchanged. The
focused harness runs the same `Future.wait(db.select(...))` source in a
detached `origin/main` worktree and in the candidate worktree.

Prototype correctness coverage forced a one-reader overflow batch containing
one bad SQL statement (only that future failed) and a batch of four
individually-sub-threshold results whose aggregate crossed the sacrifice
threshold (all results arrived and the replacement reader served the next
query).

## Results

The homogeneous premise is confirmed. In a lane-isolated 31-round
order-flipped pair:

| Lane | Baseline→candidate | Candidate→baseline |
|---|---:|---:|
| Twenty point reads | **-26.2%** | **-33.2%** |
| Twenty ~10-row reads | **-21.1%** | **-30.3%** |
| Four-way point control | -16.7% | -23.2% |
| Sequential point control | -9.3% | +20.1% (sign-flip/drift) |

Both targets clear the preset 15% bar. Four-way reads never enter the batch
path and do not regress. Sequential medians sign-flip, so there is no
reproduced control regression. Peak RSS stays within 1.7%.

Twenty concurrent 10,000-row reads also avoid exp 209's serial-batch failure:
candidate median is -21.6% in one ordering and -0.3% in the other, with p95
and RSS within the preset bounds. Sharding keeps all readers productive, and
one aggregate sacrifice can avoid several reader respawns.

The load-bearing heterogeneous guard fails:

| Alternating 10 large + 10 point | Baseline→candidate | Candidate→baseline |
|---|---:|---:|
| Total burst median | **+25.6%** | **+13.1%** |
| Point completion median | **+11.9%** | **+12.3%** |
| Point completion p95 | **+16.9%** | **+11.4%** |

The point p95 regression exceeds the declared 10% kill threshold in both
orderings, and total median regresses 13-26%. Queue pressure proves that work
is waiting; it does not reveal query cost. When a point read shares an
envelope with large reads, its future cannot complete until every member in
that envelope has executed and the one aggregate reply returns. Baseline can
admit that point independently on the next free reader.

## Decision

**Rejected.** Transparent overflow batching captures exp 209's request
amortization on homogeneous small-read bursts without adding API, but it
silently converts neighboring heterogeneous query cost into head-of-line
latency. Ordinary `Future.wait(db.select(...))` would become sensitive to an
internal grouping callers cannot observe, predict, or disable.

The mixed guard is the exact condition needed to justify hidden policy, so the
small-read wins cannot override it. Runtime and focused correctness additions
are reverted; the reader scheduler remains unchanged. The benchmark harness
is retained, and the measured prototype is preserved at `archive/exp-239`.

Review also found that aggregating individually-sub-threshold results would
make the existing reader respawn-versus-close startup race substantially more
common. That lifecycle issue is independent of the performance rejection and
should be fixed before any future mechanism deliberately increases sacrifice
frequency.

Would reopen only with new information that removes the hidden-policy problem:

- a reliable private cost signal that distinguishes cheap from expensive
  SELECTs before grouping, without parsing SQL or adding public annotations;
- a worker protocol that can return individual member completions while still
  removing enough message/completion overhead to clear the small-read bar; or
- production evidence that a narrowly identifiable homogeneous burst shape
  dominates and can be recognized without caller choice.

Do not retry queue-depth-only batching or move the batch threshold around the
mixed guard. If API policy changes, exp 209 remains the simpler explicit
implementation and this harness supplies its heterogeneous regression gate.

## Test plan

- [x] `dart analyze` on the changed reader files, focused test, and harness
- [x] `dart test test/reader_pool_test.dart` — 24/24 with the prototype
- [x] focused homogeneous A/B, 31 rounds, both side/lane orderings
- [x] isolated large-result and alternating large/point guards, 15 rounds,
  both side orderings
- [x] `dart run benchmark/finalize_experiment.dart --experiment=experiments/239-select-overflow-batching.md`
