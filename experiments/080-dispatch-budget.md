# Experiment 080: Dispatch budget research pass (Phase 1)

**Date:** 2026-04-18
**Status:** Phase 1 complete — measurements taken, candidates identified, no implementation yet

## Goal

Before committing to any new optimization experiments (Phase 2+), figure
out where each millisecond actually goes on the workloads where resqlite
currently trails sqlite3: single inserts, point queries, merge rounds.

## Methodology

Two layers of instrumentation, both designed to leave production code
near-untouched:

### Layer 1 — `ProfiledDatabase` composition wrapper

`benchmark/profile/profiled_database.dart` — wraps `Database` (which is
`final class`, so composition not subclass), records per-call wall time
via `Stopwatch`. Zero production code changed. Records go into
`ProfileSample` objects serialized to JSON for reproducibility.

### Layer 2 — Timeline markers at isolate boundaries

Two production code edits, both one-liners:
- `lib/src/writer/write_worker.dart` — `Timeline.startSync('writer.handle.X')`
  / `finishSync()` around the per-message dispatch
- `lib/src/reader/read_worker.dart` — same for reader

Near-zero cost when no tracer is attached (a single load + branch in
`Timeline.startSync`). Enables cross-isolate breakdown in DevTools when
run with `dart --observe` — no custom protocol needed.

### Baseline: noop dispatch floor

Added two "empty SQL" workloads to isolate pure round-trip cost:
- `SELECT 1` — reader-side dispatch floor
- `UPDATE items SET id = id WHERE 1 = 0` — writer-side dispatch floor
  (acquires writer mutex, runs authorizer + preupdate, commits empty frame)

## Results

100 iterations per workload. All numbers in microseconds. Median + p90
+ p99 from ~10K–50K samples per op.

### Dispatch floors (what every call costs before doing any real work)

| Path | Floor (p50) | Floor (p90) | Floor (p99) |
|---|---|---|---|
| Reader (SELECT 1) | **7μs** | 15μs | 45μs |
| Writer (UPDATE WHERE 1=0) | **10μs** | 19μs | 58μs |

The 3μs gap between reader and writer is attributable to the writer's
extra per-call machinery: mutex acquisition, preupdate hook enable/
disable, dirtyTables assembly, transaction state tracking.

### Target workloads

| Workload | Median total | Dispatch | Actual work | Dispatch % |
|---|---|---|---|---|
| Single insert | 16μs | 10μs | ~6μs | **63%** |
| Point query (PK lookup) | 7μs | 7μs | ~0μs | **~100%** |
| Merge rounds (100-row batch) | 107μs | 10μs | ~97μs | 9% |

Immediately apparent:

1. **Point queries are at the dispatch floor.** The 7μs per lookup is
   essentially 100% isolate round-trip — the actual `SELECT * WHERE id
   = ?` does almost no measurable work on our end (single-row result,
   stmt cached, reader's work is indistinguishable from noop). To make
   point queries faster we must make dispatch faster — no algorithm
   change or query-plan change will help.

2. **Single inserts are ~63% dispatch-bound.** The 6μs of "real work"
   (prepare reuse via cache, bind, step, commit) is nearly
   irreducible. Halving dispatch would halve total per-insert time.

3. **Batched writes amortize dispatch cleanly.** At 100 rows per batch,
   dispatch is 9% of total. This is why `executeBatch` is already fast
   — batching is the fix, and we already ship it. No work needed here.

### Implied ceiling vs sqlite3

Using the public dashboard's normalized-PRAGMA numbers:

| Workload | sqlite3 | resqlite | Gap | Achievable | Method |
|---|---|---|---|---|---|
| Point query | 5.2μs | 7μs | 1.35× | ~5.5μs (ceiling) | Cut dispatch 20–30% |
| Single insert | 8.9μs | 16μs | 1.8× | ~10–12μs | Cut dispatch 30–50% |
| Merge rounds | 95μs | 107μs | 1.13× | ~95–100μs | Minor C-side tuning |

**We cannot cross sqlite3 on these workloads** without removing the
writer isolate (which kills the Flutter UI-thread story). But the gaps
can narrow meaningfully: **the 1.8× single-insert gap could become
~1.2× with a 30–50% dispatch reduction.**

### Tail latency observations

p99 is 3–10× median across every workload. One outlier on single
insert was **34 ms** (vs 16μs median — 2000×!). Candidates:

- **WAL checkpoint jitter** — we run a periodic passive scheduler (exp
  029). If a passive checkpoint fires mid-insert, it blocks the writer.
- **GC pauses** — allocation during dispatch (message objects, param
  lists, result lists) can trigger generational GC.
- **Isolate scheduler preemption** — OS-level thread scheduling may
  leave the writer isolate unscheduled for longer than usual.

A separate p99-reduction pass might be worth more than absolute
median-reduction work, because Flutter UI quality is dominated by
worst-case frame budget. A 2× p99 improvement ≫ a 10% p50 improvement
for perceived smoothness.

### Benchmark-fidelity side finding

The Sync Burst merge-rounds benchmark reports **251μs per batch**, but
my isolated profile shows **107μs per batch**. The gap (~144μs) is the
cost of having an active `SELECT COUNT(*)` stream during the write:
each committed batch triggers the stream-engine path (writeGen bump,
_scheduleReQuery, reader hash-recompute, etc), and that work adds up.

That's not a bug — it's a legitimate real-world cost. But it means
benchmark numbers for "write cost" on scenarios with active streams
are actually measuring "write + stream invalidation". Useful to know
when attributing gains/losses across experiments.

## Candidate optimizations (Phase 2 portfolio)

Ordered by (expected impact × confidence) / effort.

### Tier 1 — highest expected impact

**C1. Reduce writer dispatch floor (10μs → target 6–7μs)**
- Specifically: investigate the 3μs writer/reader delta. Candidates:
  - Preupdate hook enable/disable is called per-request — could it
    skip the enable if no streams are active? (Partial exp 077 territory,
    but the hook enable/disable itself isn't what 077 optimized.)
  - Authorizer hook — same question.
  - dirtyTables buffer — exp 070 made the buffer persistent, but is
    the zero-write path still paying for a traversal?
- Scope: 1 experiment. Medium confidence. 2–3 day effort.

**C2. Reduce reader dispatch floor (7μs → target 5μs)**
- Already mined heavily (exp 019, 030, 040). But with a 5μs sqlite3
  baseline, any reduction here is pure point-query QPS gain.
- Candidates:
  - Isolate-wake overhead — measure where in the 7μs the time is spent
    (main→reader send, reader receive, reader→main send, main receive).
    Probably need more Timeline markers or manual instrumentation.
  - Message object pooling — every query allocates a `ReadRequest`,
    request+response allocation may be visible.
- Scope: 1 diagnostic sub-experiment (add fine-grained timing within
  a single call) + 1 optimization experiment based on findings. 3–5
  day effort together.

### Tier 2 — worth measuring before committing

**C3. Tail-latency / p99 investigation**
- Hypothesis: WAL checkpoint blocks + GC pauses dominate p99.
- Approach: instrument the checkpoint scheduler to log when it fires
  relative to ongoing requests; correlate with p99 spikes. Either
  (a) tune the checkpoint cadence, or (b) offload checkpoints to a
  dedicated mini-isolate so they never block the writer.
- High potential value (frame-quality wins). Medium-high effort (3–5
  days including measurement).

**C4. Stream-invalidation cost on batched writes**
- The 144μs-per-batch cost on Sync Burst is avoidable-ish. Each batch
  triggers a full re-query even when hash suppression will drop the
  emission. Could we defer the actual `selectIfChanged` dispatch if a
  newer batch is already queued on the writer?
- This partially overlaps with the exp 079 rejected direction, but
  targets a different mechanism (defer the re-query dispatch itself,
  not defer the emission).
- Requires care to avoid the correctness bugs exp 079 hit.
- 3–5 day effort.

### Tier 3 — speculative

**C5. Revisit exp 055 (columnar typed arrays) with memory harness**
- Rejected previously as below time-benchmark floor. The new memory
  benchmarks show resqlite p90 RSS deltas of 7–33 MB on 10K-row ops.
  Columnar arrays would target that directly.
- If memory is a real constraint for mobile (which it is), this could
  be a second-axis win.
- Low-medium confidence. Only worth if memory becomes a focal point.

**C6. FFI call consolidation**
- Each query path crosses FFI 5–10 times (prepare, bind×N, step,
  reset, finalize). exp 009 batched some of these. Are there still
  multi-FFI paths that could be collapsed into a single C entry
  point?
- Low-medium confidence without measurement. Would be a sub-experiment
  inside C1/C2.

### Tier 4 — explicitly deferred

- Removing the writer isolate (architectural; sacrifices the Flutter pitch)
- API surface changes (watchRow etc; user explicitly said no to these)
- IVM / materialized views (way out of scope)

## Fidelity wins this phase delivered

Beyond "we know where time goes," this instrumentation pays ongoing
dividends:

1. **The 2 Timeline markers let any future profiling session (DevTools,
   `dart observe`) see cross-isolate breakdowns without re-adding
   instrumentation.** Standard Dart idiom, essentially free.

2. **`ProfiledDatabase` wrapper is reusable** — any future experiment
   can instantiate it to capture per-call timing for a specific
   workload. No permanent production code needed.

3. **The `dispatch_budget.dart` harness produces a reproducible JSON**
   that can be diff'd across experiments. Run before/after an
   optimization to measure its exact impact on dispatch vs work split,
   not just aggregate wall time.

4. **Baseline noop floors (7μs reader / 10μs writer)** — gives every
   future experiment a "this is the floor, don't expect to go below"
   anchor. Exp 063 (SelectOne fast path) was rejected for "below
   benchmark floor" — if we'd had these numbers, we'd have known it
   was because the benchmark was noise-limited AT the dispatch floor,
   not because the optimization was useless.

5. **The noop-subtract technique**: total_time - noop_baseline =
   actual_work_time. Lets us split dispatch from work cleanly without
   needing in-isolate instrumentation beyond what's there. This is
   the biggest methodological unlock — future experiments can report
   "this saves X μs of work on top of Y μs of unavoidable dispatch"
   instead of just raw total-time deltas.

## Recommendation

Proceed to Phase 2 with **C1 as the first experiment**. Concrete
hypothesis ("writer's 3μs overhead over reader is from zero-write-path
authorizer/preupdate/dirtyTables work"), measurable acceptance
criterion (writer floor ≤ 8μs), well-scoped effort (2–3 days).

If C1 is accepted, C2 (reader floor reduction) is the next logical
target. C3 (tail latency) can run in parallel because it's orthogonal
(p99 vs p50).

Explicitly *not* recommending:
- Anything in Tier 3/4 until Tier 1 is exhausted.
- Any API changes — user has said no.
- Time spent on merge rounds: 9% dispatch / 91% work means the
  remaining gap vs sqlite3 there is irreducible given architecture.

## Reproducing this analysis

```bash
# Check out this branch
git checkout exp-080-dispatch-profile

# Run the harness
dart run benchmark/profile/dispatch_budget.dart

# For cross-isolate timeline (optional — requires DevTools):
dart --observe --profile-period=100 benchmark/profile/dispatch_budget.dart
# Open the service URL in DevTools → Performance tab → record.

# Raw JSON output goes to:
ls -t benchmark/profile/results/dispatch_budget_*.json
```

Production code footprint: 2 added Timeline markers (one per worker
isolate), 2 new imports. All other code lives in `benchmark/profile/`
and can be deleted without consequence.
