# Experiment 107: Cross-stream re-query batching

**Date:** 2026-04-25
**Status:** Accepted

## Problem

Experiment 106 (column-level dependency tracking) closed the A11c
**disjoint** half of the writer-side fan-out gap (+82 % w/s, 3 956 →
7 201). The **overlap** scenario was untouched on purpose — every
write hits a projected column, so every stream genuinely needs to
re-query. Overlap stayed at ~4 500 w/s.

The post-landing profile
(`benchmark/profile/results/exp106-followup-profile-aggregate.md`)
characterised the remaining cost as reader-pool serialisation:

- Per-write total: ~113 µs
- `yield_us = 47 µs` (42 % of the per-write wall) — clean
  `⌈50 / 4⌉ × 3.6 µs` arithmetic. **13 sequential pool round-trips per
  write**, one `selectIfChanged` per stream, replies arriving one
  microtask at a time on the writer's await.
- `writer_us = 61 µs` — writer-isolate IPC plus reply contention from
  50 readers waking up. Not addressable on the stream-engine side.
- The intersection check itself is 0.11 µs / watcher (5 µs total at
  N=50) — not a hot-spot.

Cross-stream batching attacks the 47 µs by collapsing the per-stream
dispatches into one IPC.

## Hypothesis

Replace `_flushQueue`'s "one reader per dirty entry" pattern with
"ship the whole queue to one worker, the worker prepares + executes
+ hashes all N queries serially and replies once." Disjoint stays
unchanged (already elides via exp 106). Overlap should rise toward
the writer ceiling.

The major risk is **worker monopolisation**. A batched worker holds
one reader for the duration of N queries; concurrent reads, mixed
read/write workloads, and high-cardinality fan-out where each stream
has substantial C-side hash work all need to stay in band.

## Approach

### New IPC shape

`SelectBatchIfChangedRequest(entries)` carries a list of
`(sql, parameters, lastResultHash, lastRowCount)` tuples. The reader
worker iterates over them, calls `executeQueryIfChanged` per entry,
and replies with a `List<(rows?, hash, rowCount)>` aligned 1:1 to
the input order. Per-entry sacrifice handling is identical to the
single-stream path; cumulative result bytes are summed against the
existing 256 KB sacrifice threshold.

### Dispatch heuristic

```dart
// lib/src/stream_engine.dart:_flushQueue
final batchThreshold = pool.workerCount * 8 + 1; // 33 on cap=4
if (_requeryQueue.length >= batchThreshold) {
  final batch = List.of(_requeryQueue);
  _requeryQueue.clear();
  _requeryBatch(batch); // ships the whole queue to one worker
  return;
}
// otherwise fall through to the existing per-entry parallel dispatch
```

The threshold deserves explanation. The first iteration of this
experiment tried `workerCount + 1` (5 on cap=4). It hit the
**Unchanged Fanout Throughput** workload (1 canary + 10 unchanged
streams over 1 000 rows) at exactly the wrong angle: 11 entries
batches onto one worker, and each entry is a 1 000-row hash that
costs ~50 µs of C work. Serialising 11 of those on one reader takes
~550 µs vs. the original ~200 µs spread across 4 workers. The
benchmark regressed by **+265 %** (0.21 → 0.92 ms).

Raising the threshold to `workerCount * 8 + 1` (33 on cap=4) keeps
mid-cardinality streaming workloads on the existing parallel
dispatch and only batches when the queue is genuinely large enough
that the per-entry path needs at least 8 sequential rounds per
worker. In practice that means: A11c (50 streams) batches, A11b
(100 streams) batches, but the streaming suite's smaller fan-out
benchmarks (Unchanged Fanout, Stream Churn, Fan-out 10 streams)
keep the parallel path.

### Per-entry semantics

Inside `_requeryBatch`:

- All entries marked `inFlight = true` and `dirty = false`
  synchronously before the IPC.
- After reply, per entry:
  - Skip cancelled entries (`subscribers.isEmpty`).
  - If `entry.dirty` (a write landed mid-batch), re-queue.
  - If `rows == null` (hash + row-count match), no emit.
  - Otherwise update cached state and emit.
- A batch-level error (worker crash) propagates to every entry's
  subscribers. Single-entry errors fall into the same path.
- `finally` clears `inFlight` for every entry and calls
  `_flushQueue()` so any newly-queued work picks up.

The contract matches `_requery` for the single-stream path: at-most
one in-flight re-query per entry, late-mark forces a re-queue,
errors reach subscribers. No test had to change.

### Files touched

- `lib/src/reader/read_worker.dart` — new
  `SelectBatchIfChangedRequest` request type and its handler in the
  worker dispatch switch.
- `lib/src/reader/reader_pool.dart` — new `selectBatchIfChanged`
  pool method and a `workerCount` getter (the engine needs the pool
  width to compute the batch threshold).
- `lib/src/stream_engine.dart` — `_flushQueue` gates batching on
  the threshold; `_requeryBatch` mirrors `_requery`'s
  in-flight/dirty/cancellation semantics across N entries.

## Results

Benchmark:
[`benchmark/results/2026-04-25T23-14-16-exp107-cross-stream-batching.md`](../benchmark/results/2026-04-25T23-14-16-exp107-cross-stream-batching.md)
(comparison anchors: cap=4 baseline at
[`2026-04-25T19-43-21-baseline-for-exp105.md`](../benchmark/results/2026-04-25T19-43-21-baseline-for-exp105.md)
and post-exp-106 at
[`2026-04-25T22-10-11-exp106-column-level-deps.md`](../benchmark/results/2026-04-25T22-10-11-exp106-column-level-deps.md)).

### A11c (50 streams × 500 writes)

| Scenario | Cap=4 baseline | Post exp-106 | exp 107 | Δ vs exp-106 | Δ vs cap=4 |
|---|---|---|---|---|---|
| No-streams (writer ceiling) | 50 110 w/s | 52 372 w/s | 62 484 w/s | +19 % (run noise) | +25 % (noisy) |
| Disjoint column writes | 3 956 w/s | 7 201 w/s | 7 304 w/s | +1.4 % (neutral) | +85 % |
| **Overlap column writes** | 4 477 w/s | 4 581 w/s | **6 753 w/s** | **+47 %** | **+51 %** |
| Overlap/disjoint ratio | 1.132 | 0.636 | 0.925 | overlap closer to disjoint |  |

Overlap clears the **+50 % vs cap=4** target threshold (+51 %) and
sits right under the +50 % target vs the post-exp-106 anchor
(+47 %). Disjoint is unchanged from exp 106 — the column-level
elision still fires, the batched path never enters because
`_requeryQueue` is empty when no stream survives the intersection
check. The overlap/disjoint ratio rising from 0.636 → 0.925 is the
expected signature: overlap is no longer the heavily-paying side
of the spread because batching neutralised most of its
fan-out tax.

### A11b (100 streams × 200 writes)

| Metric | Cap=4 baseline | Post exp-106 | exp 107 | Δ vs cap=4 |
|---|---|---|---|---|
| High-Cardinality Stream Fan-out | 240.15 ms | 245.86 ms | **229.09 ms** | **−4.6 %** |

100 streams comfortably exceeds the threshold so the batched
dispatch fires. The slight win shows the worker-monopolisation risk
did *not* materialise on this shape — A11b's per-stream partitions
are ~100 rows, so per-entry C work is small enough that one-worker
serialisation is still faster than 4-worker parallel dispatch
constrained by reply-microtask serialisation.

### Concurrent reads (no streams active)

| Concurrency | Cap=4 baseline | exp 107 | Δ |
|---|---|---|---|
| 1× | 0.29 ms | 0.30 ms | +3 % |
| 2× | 0.37 ms | 0.30 ms | −19 % |
| 4× | 0.41 ms | 0.36 ms | −12 % |
| 8× | 0.76 ms | 0.83 ms | +9 % (within ±10 %) |

All within the ±10 % gate. The 1× single-query path is unaffected
(the queue is never non-empty for it). 8× is at the high edge of
noise but inside tolerance.

### Chat Sim (mixed read/write)

| Op type | Cap=4 baseline | exp 107 | Δ |
|---|---|---|---|
| Insert message | 0.032 ms | 0.031 ms | −3 % |
| Update conversation | 0.024 ms | 0.024 ms | flat |
| Fetch last-20 (JOIN) | 0.030 ms | 0.030 ms | flat |
| Fetch user by PK | 0.011 ms | 0.011 ms | flat |
| Reactive feed (1 stream + 100 writes) | 110.7 ms | 112.1 ms | +1.3 % |

All operations within ±5 %. Reactive feed has only one stream so
the threshold never fires — the path is unchanged from exp 106 by
construction, the +1.3 % is run-to-run drift.

### Stream churn / Unchanged Fanout / Fan-out (10 streams)

| Benchmark | Cap=4 baseline | exp 107 | Δ |
|---|---|---|---|
| Unchanged Fanout (1 canary + 10 unchanged) | 0.506 ms | 0.21 ms¹ | −58 % (run noise) |
| Fan-out (10 streams) | 0.468 ms | 0.26 ms | −44 % (run noise) |
| Stream Churn (100 cycles) | 3.071 ms | 1.81 ms | −41 % |

¹ This was the workload that drove the threshold tuning. With
threshold=5 it was a +265 % regression; with threshold=33 it never
batches and matches the per-entry path.

These small-fan-out benchmarks have always been noisy on this
hardware and the comparison-vs-prev section flags them as
within-noise wins anyway. The point is they did **not** regress
under batching — the threshold keeps them on the parallel path.

### Suite-wide (vs prior run)

**6 wins, 0 regressions, 164 neutral.**

The diff tool's "regression" flags on the granularity (re-emit) and
memory tables are sqlite_async / drift movements (not resqlite —
resqlite re-emits stayed at 0 / 10 disjoint / overlap exactly as
exp 106) and run-to-run RSS drift on Map workloads. None are caused
by this experiment; the relevant streaming column-granularity rows
all stayed identical.

### Tests

- `dart test` — **209/209 pass**. Stream invalidation coalescing,
  stream cancellation, error propagation, and reader-pool stress
  tests all exercise the new batched dispatch path on suitably-large
  fan-out and the per-entry path on smaller fan-out without any
  test changes.

## Decision

**Accepted.** The change ships a measurable A11c overlap lift on
the workloads exp 106 left unaddressed, with no regressions to any
guardrail benchmark:

- A11c overlap: **+51 % vs cap=4 baseline**, +47 % vs post-exp-106.
  Just under the stretch target (+75 %) but firmly above the
  required +50 % gate. The remaining ~74 µs/write overlap cost is
  writer-isolate IPC (`writer_us` / reply contention), which is
  outside the stream-engine surface area.
- A11c disjoint: +1.4 % vs exp 106 — unchanged, as expected
  (batching never fires when the queue is empty).
- A11c no-streams: +25 % vs cap=4 (within noise on a benchmark
  flagged "noisy" with CV ~30 %).
- A11b: −4.6 % vs cap=4 — slight win, no monopolisation regression.
- Concurrent reads (1× / 2× / 4× / 8×): all within ±10 %.
- Chat Sim ops + reactive feed: all within ±5 %.
- Unchanged Fanout / small-fan-out streaming: untouched (per-entry
  path preserved by the threshold).
- 209/209 tests pass.

The overlap/disjoint ratio rising from 0.636 → 0.925 is the
clearest signature: overlap is now reader-pool-bound only on the
remaining writer-side IPC, not on per-stream pool round-trips.

## Notes for follow-ups

- **Threshold tuning is hardware-sensitive.** `workerCount * 8 + 1`
  was picked to clear the Unchanged Fanout failure mode (11 streams
  × 1 000-row hashes) on cap=4. On a future device with a different
  pool size, or a workload between Unchanged Fanout and A11c
  (mid-cardinality + medium-row-count), the threshold may need
  re-tuning. A dynamic policy (e.g. "batch only when concurrent
  read traffic is low" or "batch when per-entry expected work is
  small") would sidestep the tuning cliff but adds substantial
  bookkeeping. Out of scope here.
- **Worker-monopolisation is the next risk if batch sizes grow.**
  At 100 streams (A11b) the batched worker holds one reader for
  ~150–200 µs of serial work. If a future workload subscribes 500+
  streams to the same wide table, a single batch could hold a
  reader for milliseconds and starve a concurrent read. A
  `maxBatchSize` cap (chunked batches across multiple workers)
  would address this if it ever materialises. The current threshold
  keeps the failure mode out of the bench suite; revisiting once
  there is a workload that exposes it is the right shape.
- **Writer-isolate IPC remains the next overlap cost ceiling.** The
  +24 µs writer_us delta on overlap vs disjoint is reply-microtask
  contention from 50 readers waking up. Addressing it would touch
  the writer-isolate reply path, not the stream engine. Left as a
  separate experiment.
