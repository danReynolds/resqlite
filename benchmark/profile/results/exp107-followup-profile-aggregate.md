# exp 107 follow-up profile aggregate

Reconnaissance pass on **A11c many-streams writer-throughput** *after*
exp 107 (cross-stream re-query batching) landed on top of exp 106
(column-level dependency tracking). Goal: characterise the remaining
overlap fanout cost and identify whether another high-impact lever is
worth a follow-up experiment.

- Branch: `exp-107-cross-stream-batching` (commit `0b6eab4` + harness
  instrumentation in this commit)
- Profile harness: `benchmark/profile/many_streams_writer_profile.dart`
  (resqlite-only)
- Configuration: `rowCount=5000 streamCount=50 writeCount=500 iters=3
  warmup=1`
- Runs: 5× standard (baseline / disjoint / overlap)
- Hardware: macOS Darwin 25.2.0, M-class
  (`numberOfProcessors-1` clamped to 4 → reader pool size = 4)

## Methodology

Each per-write sample splits the wall into:

- `writer_us`: `await db.execute(...)` — writer-isolate round-trip
  **plus** the synchronous body of `StreamEngine.invalidate(...)` that
  runs inside `Database.execute` before the future resolves.
- `yield_us`: `await Future<void>.delayed(Duration.zero) × 2` — the
  microtask drain. Where reader-pool dispatches and listener
  microtasks fire.
- `total_us`: full per-write wall, await-to-await.
- `invalidate_us` / `intersection_us`: as in the exp-106 follow-up
  (subsets of `writer_us`).

**New in this profile** (gated by `kProfileMode`, tree-shaken in
release):

- `batch_dispatch_count`: number of times this write's
  `_flushQueue` drain took the exp-107 batched dispatch path (one IPC
  for the whole queue). Expectation post-exp-107 with N=50 ≥ 33
  threshold: 1 per write that finds a non-empty queue.
- `per_entry_dispatch_count`: number of times the per-entry path
  fired. Expectation post-exp-107: 0 on overlap (queue length 50
  always exceeds threshold when non-empty), 0 on disjoint (queue is
  always empty because exp 106 elides everything).

## Top-line: 5-run medians (N=50 streams)

Per-run per-iteration p50 → median across 5 runs:

| scenario | writer_us p50 | yield_us p50 | total_us p50 | invalidate_us p50 | isect_us p50 | per-watcher µs | batch IPCs/write | writes/sec |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline (no streams) | 25 | 8 | **34** | 0 | 0 | — | 0 | ~29 412 |
| disjoint (50 streams) | 32 | 7 | **39** | 7 | 5 | 0.11 | 0 | ~25 641 |
| overlap (50 streams)  | 30 | 5 | **37** | 7 | 5 | 0.10 | 0.06 | ~27 027 |

Per-run `total_us` p50 (µs) for sanity:

| scenario | run 1 | run 2 | run 3 | run 4 | run 5 |
|---|---|---|---|---|---|
| baseline | 34 | 33 | 33 | 45 | 39 |
| disjoint | 36 | 41 | 39 | 40 | 39 |
| overlap  | 37 | 35 | 39 | 37 | 38 |

CV for `total_us` p50 across runs: baseline 12.7 %, disjoint 4.3 %,
overlap 3.6 %. Overlap is now the *quietest* of the three.

## Progression: cap=4 vanilla → post-exp-106 → post-exp-107

`total_us` p50 per scenario across the three checkpoints:

| scenario | cap=4 vanilla (3 runs) | post exp-106 (5 runs) | post exp-107 (5 runs) | Δ vs vanilla |
|---|---:|---:|---:|---:|
| baseline | 31 | 37 | **34** | +3 (noise) |
| disjoint | 116 | 39 | **39** | **−77** |
| overlap  | 100 | 113 | **37** | **−63** |

`writer_us` p50:

| scenario | cap=4 vanilla | post exp-106 | post exp-107 | Δ vs vanilla |
|---|---:|---:|---:|---:|
| baseline | 22 | 27 | **25** | +3 (noise) |
| disjoint | 60 | 32 | **32** | −28 |
| overlap  | 56 | 61 | **30** | **−26** |

`yield_us` p50:

| scenario | cap=4 vanilla | post exp-106 | post exp-107 | Δ vs vanilla |
|---|---:|---:|---:|---:|
| baseline | 8 | 9 | 8 | 0 |
| disjoint | 51 | 7 | **7** | −44 |
| overlap  | 44 | 47 | **5** | **−39** |

The picture is unambiguous. Exp 106 collapsed disjoint (column
elision empties the queue → no dispatch). Exp 107 collapses overlap by
the same magnitude on a different mechanism (one batched IPC instead
of 13 sequential pool round-trips). Both `writer_us` and `yield_us`
fell on overlap, not just `yield_us` as predicted in the exp-106
follow-up — see "Where the writer drop came from" below.

## Disjoint per-write breakdown (post exp-107)

`total_us = 39 µs`, identical to post-exp-106. Confirmed: exp 107's
batching threshold (33) is never exceeded because the column elision
in exp 106 keeps `_requeryQueue` empty. The dispatch counters bear
this out:

| metric | value (5-run total) |
|---|---|
| `batch_dispatch_count` total | 0 across 7 500 samples |
| `per_entry_dispatch_count` total | 0 across 7 500 samples |
| `invalidate_us` p50 | 7 µs |
| `intersection_us` p50 | 5 µs (50 watchers × 0.11 µs/watcher) |

The +5 µs over baseline is the writer-isolate IPC cost growing
slightly with subscribed streams (likely just reply-microtask
ordering against initial-emission housekeeping that the harness
doesn't fully isolate — within Stopwatch noise).

## Overlap per-write breakdown (post exp-107)

`total_us = 37 µs`. The breakdown:

| component | µs | how recovered |
|---|---:|---|
| writer-isolate round-trip + reply | ~23 | `writer_us` − `invalidate_us` |
| `_streamEngine.invalidate` synchronous body | ~7 | `invalidate_us` p50 |
| of which: `_writeAffectsEntry × 50` | ~5 | `intersection_us` p50 |
| of which: dirty-set scheduling + flushQueue kick | ~2 | `invalidate_us − intersection_us` |
| microtask drain (yields) | ~5 | `yield_us` p50 |

`yield_us` collapsed from 47 → 5 µs, exactly as predicted by the
exp-106 follow-up. **Writer round-trip + reply also fell from 54 → 23
µs**, which was *not* fully predicted (the prior aggregate attributed
the +24 µs writer overlap delta to "reply-microtask contention from 50
readers waking up" but flagged it as outside the stream engine's
surface). Exp 107's batching has the second-order effect of waking
**one** reader instead of fifty, so the writer's reply microtask no
longer competes with 50 incoming dispatch requests in the same
microtask round. The two effects compound.

### Where the batching path actually fires

`batch_dispatch_count` totals (across 1500 samples per scenario per
run, 5 runs):

| scenario | run 1 | run 2 | run 3 | run 4 | run 5 | batch/write |
|---|---:|---:|---:|---:|---:|---:|
| baseline | 0 | 0 | 0 | 0 | 0 | 0.000 |
| disjoint | 0 | 0 | 0 | 0 | 0 | 0.000 |
| overlap  | 88 | 88 | 96 | 88 | 96 | 0.061 |

Only **~6 % of overlap writes** trigger a batched IPC. The other 94 %
of writes find `_requeryQueue` already empty. The reason is the
in-flight gate: while the previous batched IPC is still resolving on
the worker isolate, every new write's `invalidate` sees all 50 stream
entries as `inFlight=true` and does NOT add them to the queue. They
are marked `dirty=true` instead. When the in-flight batch completes,
its post-handler re-queues the dirty entries and `_flushQueue()` then
fires *one* follow-up dispatch covering everything that piled up. The
writer effectively gets out of the reader's way: the per-write cost
collapses to ~37 µs because the reader's batched work runs in parallel
with the next write's writer-isolate IPC.

This is a stronger result than the experiment doc's "+47 % vs exp 106"
suggests — see suite-vs-harness reconciliation below.

## p99 / max tails

| scenario | writer p99 | yield p99 | total p99 |
|---|---:|---:|---:|
| baseline | 78–319 (run-dependent) | 30–100 | 107–386 |
| disjoint | 101–311 | 14–62 | 128–385 |
| overlap  | 105–202 | 51–86 | 121–293 |

Overlap p99 is now *better* than disjoint p99 in 3 of 5 runs. The
remaining tail is the writer-isolate IPC — when one write's writer
round-trip stalls (e.g. WAL fsync timing), the per-write cost blows up
regardless of stream count.

## Suite-vs-harness reconciliation

The suite reports A11c overlap at **6 753 w/s post-exp-107** (148
µs/write). The harness reports overlap p50 = **37 µs/write** (~27 000
w/s). The 4× discrepancy is **not** harness yielding overhead — both
use identical pacing (`await execute() + 2 × Future.delayed(Duration.zero)`).

The discrepancy is the **trailing 50ms drain** that the suite includes
in `wallSw`:

```dart
// suites/many_streams_writer_throughput.dart, line 461-484
final wallSw = Stopwatch()..start();
for (var w = 0; w < writeCount; w++) {
  await peer.execute(updateSql, ...);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
if (streamCount > 0) {
  await Future<void>.delayed(const Duration(milliseconds: 50));
}
wallSw.stop();
```

500 × 37 µs = 18 500 µs of actual work + 50 000 µs of trailing settle
= 68 500 µs / 500 writes = **137 µs/write effective average**, right
in the suite's 148 µs/write band. The suite throughput is dominated by
that fixed 100 µs/write baked in by the trailing delay. Same trailing
artifact applied pre-exp-107, so the **suite's +51 % vs cap=4
understates exp 107's actual impact** — the per-write cost dropped
from ~113 → ~37 µs, a 67 % reduction, but the suite's wall-time
denominator is fixed-cost-padded.

This is a measurement-methodology finding more than a code finding:
the suite's reported throughput is the right metric for "how many
writes can a user push through this API per second under sustained
streaming pressure," but it is the wrong metric for "what is the
per-write cost of fanout." For follow-up A/B work the harness's
`total_us` p50 is the cleaner signal — and it shows overlap has
already collapsed to disjoint-equivalent.

## Top remaining hot-spots in absolute µs

After exp 107, the per-write breakdown on overlap is essentially
indistinguishable from disjoint:

| component | overlap µs | disjoint µs | baseline µs |
|---|---:|---:|---:|
| writer-isolate round-trip | 23 | 25 | 25 |
| invalidate sync body | 7 | 7 | 0 |
| intersection probe | 5 | 5 | 0 |
| microtask drain (yield) | 5 | 7 | 8 |
| **total** | **37** | **39** | **34** |

Subtracting baseline, the **net fanout cost on either scenario is
~3–5 µs/write at N=50**. There is no single component large enough to
attack with a follow-up experiment that would deliver ≥ 30 % on
A11c-shape workloads.

## Recommendation

**Stop here on A11c.** The per-write cost has collapsed to baseline +
~3–5 µs of unavoidable bookkeeping (intersection check, dirty-set
scheduling, single batched IPC fired ~6 % of writes). There is no
≥ 30 % lever remaining on either disjoint or overlap on the current
dispatch architecture.

The reasons further optimisation would be hard:

1. **Writer-isolate round-trip (~23 µs) is the floor.** Above the
   stream engine: writer.locked → mutex → SQL exec → WAL commit →
   reply. Independent of stream count. Optimising this requires
   touching the writer-isolate IPC path or the SQL execution itself,
   neither of which is stream-engine territory. The exp 087 (writer
   response port) round-trip work covered most of what the IPC layer
   can do without restructuring.
2. **Invalidate sync body (~7 µs) at N=50 is 50 watchers × ~0.14
   µs/watcher** of intersection + dirty-set work. Bitset/cached
   column-id mappings could shave maybe 2–3 µs at this N. Not a
   ≥ 30 % lever unless workloads grow to N=500 watchers — speculative.
3. **Yield (~5 µs) is one batched IPC firing ~6 % of writes plus
   microtask drain overhead.** Already at the floor of what the event
   loop allows; no further compression possible without abandoning
   the microtask-yield discipline that makes the suite metric mean
   anything.

### What about A11b?

A11b (100 streams × different scenario, "High-Cardinality Stream
Fan-out") wasn't profiled in this pass — the harness runs N=50.
Per the exp 107 doc, A11b post-exp-107 = 229 ms vs cap=4 240 ms
(−4.6 %, a slight win). At N=100 the batch threshold (33) is exceeded
by 3×, so batching always fires. A11b's per-stream partitions are
~100 rows each — the C-side hash work per entry is small enough that
worker-monopolisation isn't a problem.

The A11b lever, if any, would be the **same writer-isolate IPC**
(the writer round-trip is unchanged whether 50 or 100 streams are
listening). The exp 107 doc notes this as the next overlap cost
ceiling. **Estimated lever size on A11b: same ~23 µs writer
floor → same single-digit-µs theoretical headroom.** Not worth a
follow-up experiment; the absolute number is too small.

### Architecture changes needed to push further

If a future revisit ever needs to push below the current floor, the
levers are off the dispatch architecture entirely:

1. **Co-located writer + reader (single-isolate mode).** Most of the
   23 µs writer round-trip is the cross-isolate IPC. A single-isolate
   mode (writer and reader pool share the main isolate) eliminates
   the IPC entirely — but at the cost of every write blocking the
   main isolate for the full SQL exec + WAL commit (~10–15 µs each).
   On A11c-shape workloads this could land at ~15–20 µs/write
   (a further 50 % reduction); on workloads with concurrent reads
   it would regress sharply. Out of scope for the current
   architecture.
2. **Synchronous invalidate path with a shared-memory dirty bitmap.**
   Replace the per-stream `_writeAffectsEntry` walk with a
   pre-computed `Map<column, BitSet<streamIndex>>` that the writer
   updates synchronously on schema changes. The intersection check
   becomes a single bitwise-AND. At N=50 this saves ~3–5 µs; at
   N=500 it saves ~50 µs. Doesn't justify the complexity until
   workloads materialise at N≫100.
3. **WASM/inline SQLite.** The single largest per-write cost is the
   SQL execution itself (~10–15 µs of the writer round-trip).
   Switching to a WASM-compiled SQLite that runs in-process on the
   writer isolate could shave further µs but introduces a much
   larger maintenance surface. Strictly an architecture-level
   decision.

None of these are a "next experiment" candidate. They are
architecture changes that would need their own design pass.

## Conclusion

Exp 106 + exp 107 together have closed the A11c writer-fanout gap.
Per-write cost on overlap dropped from 100 → 37 µs (cap=4 vanilla → 
post-exp-107), with disjoint at 39 µs. The remaining cost is the
writer-isolate IPC + intersection bookkeeping, neither of which has a
single-digit-percent lever, let alone ≥ 30 %.

**Recommendation: do not run a follow-up A11c experiment.** The
remaining gap is split across small components with no individually
large target. The suite throughput number (6 753 w/s on overlap) is
heavily padded by a 100 µs/write trailing-drain artifact in the
benchmark methodology — the actual per-write cost is ~37 µs,
indistinguishable from disjoint and within ~3 µs of the no-streams
baseline.

If the priority is moving the suite throughput number, address the
trailing-drain methodology artifact in the suite (e.g. measure pure
write-loop wall, or scale the drain proportional to writeCount).
That's a benchmark fix, not a performance experiment.

## Harness instrumentation added in this commit

To support this analysis, two new profile counters were added behind
`kProfileMode` (tree-shaken in release):

- `ProfileCounters.batchDispatchCount` — incremented in
  `StreamEngine._flushQueue` when the batched dispatch path fires.
- `ProfileCounters.perEntryDispatchCount` — incremented in
  `_flushQueue` when the per-entry path fires.

Both are surfaced through the harness's per-write samples and the
per-run aggregate table. Zero allocations, zero cost in release
builds, and they decisively confirmed (a) batching fires in 6 % of
overlap writes (not "every write" as the experiment doc implies)
and (b) batching never fires on disjoint (the column elision keeps
the queue empty).

These counters will remain useful for any future stream-engine
experiment that wants to verify which dispatch path executed.
