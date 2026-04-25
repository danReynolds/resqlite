# A11c writer-fanout profile aggregate

Reconnaissance pass on **A11c many-streams writer-throughput** to inform
the next experiment choice (exp 052 vs other levers).

- Branch: `benchmark-a11c-writer-throughput`
- Profile harness: `benchmark/profile/many_streams_writer_profile.dart` (resqlite-only)
- Configuration: `rowCount=5000 streamCount=50 writeCount=500 iters=3 warmup=1`
- Runs: 3× standard (baseline / disjoint / overlap) + 1× scaling sweep (N=0,5,10,25,50)
- Hardware: macOS Darwin 25.2.0, M-class (`numberOfProcessors-1` clamped to 4 → reader pool size = 4)

## Methodology

Each per-write sample splits the wall into:

- `writer_us`: `await db.execute(...)` — writer-isolate round-trip (writer.locked → mutex → SQL exec → WAL commit → reply) **plus** the synchronous prefix of `StreamEngine.invalidate(...)` that runs inside `Database.execute` before the future resolves. Synchronous fanout bookkeeping (mark dirty, push to `_requeryQueue`, kick `_flushQueue`) lands in this bucket; the actual reader-pool dispatches do not.
- `yield_us`: `await Future<void>.delayed(Duration.zero) × 2` — the microtask drain. Where reader-pool `selectIfChanged` dispatches actually run, replies arrive, listener microtasks fire.
- `total_us`: full per-write wall, await-to-await.

The synchronous-vs-async split for invalidate is recovered as the
`scenario.writer − baseline.writer` delta. We did not modify
production code.

## Top-line: 3-run medians (N=50 streams)

Per-iteration medians, then median across 3 runs:

| scenario | writer_us p50 | yield_us p50 | total_us p50 | writes/sec |
|---|---:|---:|---:|---:|
| baseline (no streams) | 22 | 8 | **31** | ~32k |
| disjoint (50 streams) | 60 | 51 | **116** | ~8.6k |
| overlap (50 streams)  | 56 | 44 | **100** | ~10k |

Per-run values (writer p50 / yield p50 / total p50 µs):

| run | baseline | disjoint | overlap |
|---|---|---|---|
| 1 | 22 / 8 / 31 | 60 / 51 / 116 | 56 / 45 / 104 |
| 2 | 28 / 10 / 40 | 60 / 57 / 119 | 59 / 40 / 100 |
| 3 | 22 / 8 / 31 | 61 / 42 / 110 | 52 / 44 / 100 |

## Fanout deltas vs no-streams baseline (3-run median)

| scenario | Δwriter_us | Δyield_us | Δtotal_us |
|---|---:|---:|---:|
| disjoint (N=50) | **+38** | **+43** | **+85** |
| overlap (N=50)  | **+34** | **+36** | **+69** |

Of the **~85 µs/write fanout cost** at N=50:
- ~38 µs (45 %) lands in `writer_us` — the synchronous `_streamEngine.invalidate` body and event-loop pressure on the writer's reply microtask.
- ~43 µs (51 %) lands in `yield_us` — reader-pool `selectIfChanged` dispatches, replies, listener microtasks.
- ~4 µs (4 %) is jitter.

This roughly matches the suite-reported 4–5× drop (32k → 8.6k w/s).

## Stream-count scaling (disjoint only, N ∈ {0, 5, 10, 25, 50})

| N | writer_us p50 | yield_us p50 | total_us p50 | Δtotal vs N=0 |
|---:|---:|---:|---:|---:|
| 0 | 28 | 10 | 40 | 0 |
| 5 | 56 | 18 | 79 | +39 |
| 10 | 51 | 18 | 74 | +34 |
| 25 | 49 | 26 | 80 | +40 |
| 50 | 63 | 41 | 108 | +68 |

**The fanout cost is NOT linear in N.** Going from N=5 → N=50 adds only ~30 µs of total cost (10× more streams → 1.4× more wall). Most of the per-write cost is incurred the moment **any** stream is subscribed: the N=0 → N=5 step alone adds +39 µs.

This is consistent with the reader-pool architecture: pool size is **clamp(numProcessors-1, 2, 4) = 4** on this hardware. Once 4 selectIfChanged dispatches are in flight, the remaining 46 wait in `_requeryQueue`, getting dispatched as readers free. Per-write wall is gated on **reader-pool round-trip latency × ceil(N/4)** plus a fixed per-write shared overhead (~30 µs) that doesn't depend on N at all.

## Disjoint-vs-overlap delta (exp 075 hash short-circuit)

3-run medians:

| metric | disjoint | overlap | Δ (overlap − disjoint) |
|---:|---:|---:|---:|
| total_us p50 | 116 | 100 | **−16** |
| writer_us p50 | 60 | 56 | −4 |
| yield_us p50 | 51 | 44 | −7 |

**Overlap is *faster* than disjoint at p50** by ~16 µs/write, contrary to the suite's expectation of overlap < disjoint or ratio ≈ 1.0. Two readings of this:

1. **Listener delivery is cheap**, and disjoint pays slightly more on the worker side because `executeQueryIfChanged` (exp 075) walks the result rows and computes a streaming hash even when the result will compare equal — the hash work isn't free. Overlap delivers a ready buffer to the listener; disjoint computes the hash, finds it equal, returns null, but still walked the bytes.
2. **Tail behavior is opposite**: p99 in run 1 was disjoint=301 vs overlap=525, so overlap has heavier tails (occasional listener delivery latency spikes). The suite measures wall over 500 writes including those tails; this profile reports per-write p50.

Either way: **exp 075's hash short-circuit saves at most ~16 µs/write at N=50**, and even that sign is sensitive to which percentile you read. The hash short-circuit is doing useful work, but it is not the dominant source of fanout cost.

## p99 / max tails

Per-write p99 (3-run median, µs):

| scenario | writer p99 | yield p99 | total p99 |
|---:|---:|---:|---:|
| baseline | 86 | 35 | 108 |
| disjoint | 190 | 192 | 345 |
| overlap | 340 | 243 | 451 |

Tails are 3-5× the median. No single dominant tail driver: writer and yield both stretch. Likely a mix of GC and reader-pool head-of-line blocking. No checkpoint stall signature in the per-iteration emission counts (steady across iters).

## Findings

1. **Per-write fanout cost ≈ 85 µs at N=50**, decomposed roughly evenly between (a) synchronous invalidate + event-loop pressure on the writer reply (~38 µs), and (b) reader-pool dispatches + microtask drains (~43 µs).

2. **Cost is reader-pool-bounded, not per-stream linear.** N=5 → N=50 (10×) adds only ~30 µs because the 4-worker reader pool serializes selectIfChanged dispatches into batches of ≤4. Most of the cost is shared per-write overhead that fires once any stream exists.

3. **Exp 075 hash short-circuit saves at most ~16 µs/write at N=50**, sometimes appears net-negative depending on tail handling. Useful but not the bottleneck.

4. **Listener delivery is cheap**; the per-stream re-query cost on a 100-row partition of a wide table dominates the per-stream side. Listener emit is one `controller.add` + one microtask hop per active stream.

## Recommendation: where to optimize next

**Exp 052 (writer-side dispatch elision via column-tracking) would only save the disjoint case from running selectIfChanged at all.** Based on this profile, that's a saving of ~85 µs/write on disjoint workloads — i.e. it would lift disjoint writes/sec from ~8.6k toward the no-streams baseline of ~32k. Useful, but:

- It does NOT help overlap (which still must re-query). At N=50, A11c-overlap also drops to ~10k — exp 052 leaves that untouched.
- The benchmark scenario where exp 052 shines (column-disjoint heavy writes with many streams) is real but narrow.

**The bigger lever** is the shared per-write overhead that scales as ~`O(ceil(N / poolSize))` reader round-trips. Two follow-ons that would help BOTH disjoint and overlap, ranked by expected payoff:

a. **Exp 071/093/094-style writer-side re-query batching.** Instead of letting `_flushQueue` dispatch up to `poolSize` selectIfChanged calls per write, coalesce all queued entries for the same dirty-table set into one writer-issued (or reader-issued) batch query that returns the changed bits for all subscribed projections. The cost goes from `O(N/poolSize × dispatch_cost)` to `O(1) × batched_cost`. This was rejected before (071/093/094 each for different reasons — rebench under A11c-shaped load to see which assumption broke).

b. **Increase reader pool size when stream count is high.** Static `clamp(2, 4)` was tuned for read throughput against a small subscriber set. With 50 streams active, a pool of 8 or even 16 would parallelize fanout further and reduce per-write `yield_us`. Cheap to try; needs measurement on read-mix workloads to confirm no regression there.

c. **Exp 052 as a follow-up after batching.** Once batching is in place, column-elision becomes a clean micro-optimization on top — but the batched-fanout gain is bigger and benefits both scenarios.

## Conclusion

**Do not jump to exp 052 yet.** A11c's drop is dominated by per-write reader-pool serialization, not per-stream dispatch — and exp 052 only helps the column-disjoint half of the benchmark. The profile points first at re-query batching (revisit 071/093/094 under A11c) and possibly a larger reader pool.

## Harness gaps

- The current harness can't separate **synchronous-invalidate cost** from **writer-reply event-loop pressure** without modifying production code (both land in `writer_us`). Adding a `Timeline.startSync('streamEngine.invalidate')` span inside `StreamEngine.invalidate` (gated by `kProfileMode`) would clean that up — recommended if any of the levers above are pursued.
- Per-stream re-query cost is observed only as an aggregate `yield_us` — we don't know how much is reader IPC vs. C-side hash walk vs. listener microtask. Adding `Timeline.startSync` markers around `selectIfChanged` request/reply in the stream engine would surface that. Already exists in `read_worker.dart` at the worker side; the main-isolate dispatch side is uninstrumented.
- Listener emission counts (`emitCounts`) consistently read 0 in measure iterations because the 50 ms post-loop drain is shorter than 50-stream emission backlog. This does not affect the timing analysis (each per-write `yield_us` captures the dispatch cost as it lands), but the totals are unreliable as a "did the listener actually run" signal at this configuration.
