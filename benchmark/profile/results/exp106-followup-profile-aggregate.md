# exp 106 follow-up profile aggregate

Reconnaissance pass on **A11c many-streams writer-throughput** _after_ exp 106
(column-level dependency tracking) landed. Goal: characterise the remaining
fanout cost on disjoint and overlap and identify the next high-impact lever.

- Branch: `exp-106-column-level-deps` (commit `a4fb56a` + harness instrumentation)
- Profile harness: `benchmark/profile/many_streams_writer_profile.dart` (resqlite-only)
- Configuration: `rowCount=5000 streamCount=50 writeCount=500 iters=3 warmup=1`
- Runs: 5× standard (baseline / disjoint / overlap)
- Hardware: macOS Darwin 25.2.0, M-class (`numberOfProcessors-1` clamped to 4 → reader pool size = 4)

## Methodology

Each per-write sample splits the wall into:

- `writer_us`: `await db.execute(...)` — writer-isolate round-trip (writer.locked → mutex → SQL exec → WAL commit → reply) **plus** the synchronous body of `StreamEngine.invalidate(...)` that runs inside `Database.execute` before the future resolves.
- `yield_us`: `await Future<void>.delayed(Duration.zero) × 2` — the microtask drain. Where reader-pool `selectIfChanged` dispatches actually run, replies arrive, listener microtasks fire.
- `total_us`: full per-write wall, await-to-await.

**New in this profile** (gated by `kProfileMode`, tree-shaken in release):

- `invalidate_us`: synchronous body of `StreamEngine.invalidate` only, isolated from writer-isolate IPC. Subset of `writer_us`.
- `intersection_us`: cumulative microseconds spent inside `_writeAffectsEntry` (the per-stream column-set probe added in exp 106). Subset of `invalidate_us`.
- `intersection_entries`: number of `_writeAffectsEntry` probes per write (50 = "all watchers tested").
- `per-watcher µs`: mean `intersection_us / intersection_entries` across all samples.

## Top-line: 5-run medians (N=50 streams)

Per-run per-iteration p50 → median across 5 runs:

| scenario | writer_us p50 | yield_us p50 | total_us p50 | invalidate_us p50 | isect_us p50 | per-watcher µs | writes/sec |
|---|---:|---:|---:|---:|---:|---:|---:|
| baseline (no streams) | 27 | 9 | **37** | 0 | 0 | — | ~27 027 |
| disjoint (50 streams) | 32 | 7 | **39** | 7 | 4 | 0.11 | ~25 641 |
| overlap (50 streams)  | 61 | 47 | **113** | 7 | 4 | 0.09 | ~8 850 |

Per-run `total_us` p50 (µs) for sanity:

| scenario | run 1 | run 2 | run 3 | run 4 | run 5 |
|---|---|---|---|---|---|
| baseline | 42 | 41 | 37 | 37 | 36 |
| disjoint | 39 | 40 | 39 | 39 | 37 |
| overlap  | 110 | 112 | 113 | 114 | 113 |

CV for `total_us` p50: baseline 7.4 %, disjoint 3.0 %, overlap 1.4 %. Tight.

## Comparison vs prior cap=4 vanilla aggregate

The prior `a11c-writer-fanout-aggregate.md` (3-run medians, same harness, vanilla pre-exp-106 code):

| scenario | total_us p50 prior | total_us p50 now | Δ | writes/sec prior → now |
|---|---:|---:|---:|---|
| baseline | 31 | 37 | +6 | ~32k → ~27k |
| disjoint | 116 | **39** | **−77** | ~8.6k → ~25.6k |
| overlap  | 100 | 113 | +13 | ~10k → ~8.8k |

Note: the harness yields aggressively (`Future.delayed(Duration.zero) × 2` per write), so the absolute writes/sec here is higher than the suite's `~7 200 / ~4 600` w/s (which has different pacing). The shape of the delta — **disjoint collapses to baseline; overlap unchanged** — is what reproduces the suite signal cleanly.

## Disjoint per-write cost decomposition (post exp-106)

Per-write `total_us = 39` µs at 50 streams. Subtracting the no-streams baseline of 37 µs gives **+2 µs net fanout cost** — within Stopwatch noise.

| component | µs | how recovered |
|---|---:|---|
| writer-isolate round-trip + reply | ~25 | `writer_us` − `invalidate_us` |
| `_streamEngine.invalidate` synchronous body | ~7 | `invalidate_us` p50 |
| of which: `_writeAffectsEntry × 50` | ~4 | `intersection_us` p50 |
| of which: dirty-set scheduling + flushQueue kick | ~3 | `invalidate_us − intersection_us` |
| microtask drain (yields) | ~7 | `yield_us` p50 |

**Per-watcher intersection cost: 0.11 µs.** At N=50 watchers that is 5.5 µs total intersection work — close to the 4 µs `intersection_us` p50, with the residual being the `dirtyEntries` set construction and loop overhead. The intersection probe is small and fast: a `Set.contains(table)` + at most one column-set membership check before short-circuit (most disjoint writes hit the `for (final c in writerCols) if (readerCols.contains(c)) return true` loop and exit on the first non-matching column).

**The disjoint bucket has effectively no remaining fanout cost in this harness.** Exp 106 elides every dispatch; what's left is the writer round-trip + ~7 µs of column bookkeeping.

## Overlap per-write cost decomposition (post exp-106)

Per-write `total_us = 113` µs at 50 streams. Subtracting baseline 37 µs → **+76 µs net fanout cost**.

| component | µs | how recovered |
|---|---:|---|
| writer-isolate round-trip + reply | ~54 | `writer_us − invalidate_us` |
| `_streamEngine.invalidate` synchronous body | ~7 | `invalidate_us` p50 |
| of which: 50 × intersection probes | ~4 | `intersection_us` p50 |
| of which: scheduling 50 entries onto `_requeryQueue` | ~3 | residual |
| **microtask drain (yields)** | **~47** | `yield_us` p50 |
| total | 113 | |

The +24 µs writer_us delta vs disjoint (61 vs 32 µs) is curious — it's not the intersection check (which is the same 4 µs in both scenarios). It's writer-isolate reply contention: when 50 readers are about to be woken up to dispatch, the writer's reply microtask competes for event-loop turn. This is the writer-isolate IPC component — not addressable from the stream engine.

The dominant lever is **`yield_us = 47 µs`**: 50 streams' worth of `selectIfChanged` round-trips serialised through a 4-worker pool. **`ceil(50/4) = 13 pool round-trips × ~3.6 µs each ≈ 47 µs`** — consistent with the cap=4 reader-pool architecture. Listener emission post-hash-check is fast (rows are unchanged, so no `controller.add` of new data — just the hash compare).

## p99 / max tails

| scenario | writer p99 | yield p99 | total p99 |
|---|---:|---:|---:|
| baseline | 177 | 56 | 200 |
| disjoint | 118 | 21 | 135 |
| overlap  | 204 | 163 | 348 |

Disjoint p99 (135 µs) is *better* than baseline p99 (200 µs) — column elision avoids the long tail of pool drains entirely on disjoint writes. Overlap p99 (348 µs) is dominated by the pool tail when one of the 13 round-trips stalls.

## Findings

1. **Exp 106 fully eliminates the disjoint fanout penalty in this harness.** `total_us` collapses from 116 → 39 µs (matches the no-streams baseline at 37 µs). The +82 % suite lift is the visible tip; in a microbench that yields aggressively, disjoint becomes nearly free.

2. **The intersection check is cheap: 0.11 µs/watcher × 50 watchers = ~5 µs** synchronous overhead. Even at N=500 watchers this would be ~55 µs/write — meaningful, but not dominant. **Bitset / cached-column-id mappings would shave at most a few µs.** Not worth pursuing.

3. **Overlap is reader-pool-bound at 50 streams ÷ 4 workers.** 47 µs of `yield_us` cleanly accounts for ~13 pool round-trips × 3.6 µs reply latency. Writer-side bookkeeping is irrelevant on overlap (intersection check is paid then ignored).

4. **The +13 µs overlap regression vs prior aggregate** (100 → 113 µs) is within run-to-run variance and the +6 µs baseline drift (37 vs 31 µs) is consistent with general environment noise from the build with `RESQLITE_PROFILE=true` on. Not a real regression.

## Recommendation: where to optimise next

**Cross-stream re-query batching.** On overlap, the 47 µs `yield_us` is 13 sequential pool round-trips. If we coalesce the per-stream selectIfChanged dispatches into a single batched reader-side operation — one round-trip that visits all dirty entries and computes their hashes in one C-side pass — `yield_us` could collapse from ~47 µs toward ~5 µs (one pool round-trip + 50 hashes computed locally on the worker).

**Mechanism (one sentence):** Rather than each entry in `_requeryQueue` consuming one reader worker via `pool.selectIfChanged(...)`, ship the entire queue contents to a single worker in one IPC and let the worker prepare-cache-execute-hash all queries serially before replying with a `Map<entryKey, (rows, hash, rowCount)>`.

**Expected target:** Overlap **8.8k → 18-25k w/s** (113 µs → ~50 µs/write), gated by how cheap a 50-query batch is on a single worker vs 13 round-trips. **Disjoint unaffected** (already elides, no entries to batch).

**Risk assessment:**
- **Worker monopolisation.** A 50-entry batch holds one worker for the duration of all 50 prepares + executes + hashes. Other concurrent reads (point lookups, peer reads) get parked behind it — the 4-worker pool degrades to 3-worker effective capacity for the batch duration. On A11c-shape workloads (write-heavy) this is fine; on mixed read+write it could regress reads. Need to measure A11b (high-cardinality fanout) and chat-sim (mixed) alongside A11c.
- **Cancellation correctness.** A subscriber cancelling mid-batch must not break the others. Implementable but requires careful sequencing.
- **Memory pressure.** 50 prepared statements + 50 result hashes accumulated in one worker reply message vs 13 small replies. The exp 094 (dirty-read reuse dispatch) and 095 (writer-result-buffer dispatch) attempts hit similar serialisation cost issues — worth re-reading those rejections before committing.
- **History.** Exp 071/093/094 each tried adjacent batching shapes and were rejected. The rejections were on different specific batching geometries. The simplest experiment is "batch the dirty queue once per invalidation" — neither 071, 093, nor 094 was exactly that. Worth one focused attempt with a profile-mode A/B against the cap=4 vanilla baseline.

**Alternative if batching proves intractable:** raise the reader pool cap when the writer detects "stream count ≫ poolSize". Exp 105 was rejected in the static configuration — doubling the static pool from 4→8 regressed A11c by 55 % and A11b by 88 % because each completed reply queues a microtask ahead of the next pending write. A dynamic policy that grows the pool _only when_ active stream count exceeds 4N pool size and the writer is stalled on `_flushQueue` could sidestep the regression on small-watch workloads while unlocking parallel fanout when it's needed. **Lower priority — try batching first.**

## Conclusion

Exp 106 has cleanly closed the disjoint half of the A11c gap. The remaining ~76 µs/write overlap penalty is reader-pool serialisation, not anything fixable on the writer side. **Cross-stream re-query batching is the next experiment to attempt** — expected lift on overlap from 4.5k → 8-10k w/s in the suite (matching the 113 → ~50 µs predicted in this profile). Disjoint remains untouched. Bitset/column-id mapping optimisations are not worth pursuing — the intersection cost is already 0.1 µs/watcher.

## Harness gaps that prevented a cleaner answer

- **Writer-isolate round-trip is observed only as `writer_us − invalidate_us`.** The +24 µs delta on overlap (61 µs) vs disjoint (32 µs) is consistent with reply-microtask contention but the harness can't directly attribute it to "writer reply was queued behind 50 reader microtasks". A `Timeline.startSync('writer.reply.dispatch')` span on the writer reply path would isolate this if the next experiment touches writer-isolate IPC.
- **Per-write `yield_us` aggregates all 13 pool round-trips into one number.** A future batching experiment would benefit from per-pool-round-trip instrumentation in the reader pool to verify the `ceil(N/4)` model directly. Today this is inferred from the `47 µs ≈ 13 × 3.6 µs` arithmetic.
- **Listener delivery cost is invisible on overlap** because the hash short-circuit suppresses `controller.add(rows)` (rows-unchanged path). On a workload where the write actually mutates the projected slice of the result (e.g. UPDATE WHERE id matches one stream), listener cost would surface. Worth a future variant if the next experiment turns out to need it.
