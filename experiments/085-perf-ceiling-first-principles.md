# Experiment 085: Performance ceiling analysis — first-principles pass

**Date:** 2026-04-19
**Status:** Research complete. No implementation.

## TL;DR

Measured resqlite against first-principles architectural floors on
every workload we track. **Conclusion: resqlite is within ~1–2 μs of
the architectural floor on every workload, and the remaining gap is
feature-enabling overhead, not waste.** Further time-axis optimization
would require architectural changes (shared-memory IPC, dedicated
checkpoint isolate) measured in weeks of work for single-digit-μs
wins that users won't perceive.

The only axes with compressible room:
1. **p99 tail latency** on sustained workloads (exp 083 partial win,
   architectural fix deferred).
2. **Stream re-invalidation overhead on batched writes** (~144 μs/
   batch on Sync Burst; requires predicate-aware invalidation, weeks
   of work).
3. **Memory for double-heavy schemas** (exp 084 showed a real but
   narrow ~2.5× win; deferred pending user need).

For anything simpler, **we are at the ceiling**. This doc records why,
with numbers, so future perf work starts from an accurate picture.

## Methodology

Three data sources, all reproducible on main:

1. **Profile mode** (`benchmark/run_profile.dart`, 5 runs):
   noop baselines (dispatch floors), single_insert, point_query,
   merge_rounds. Captures p50/p90/p99/max wall time + work_us (total
   minus dispatch floor) + RSS + SQLite counters + decoder
   allocation counts.

2. **Release mode** (`benchmark/results/2026-04-18T10-27-16-*.md`):
   resqlite against drift / sqlite_async / sqlite3 on the same
   schemas. Gives us a concrete reference point: sqlite3 runs on
   the main thread with no isolate hop, so its number approximates
   the "bare SQLite + Dart FFI" floor.

3. **Architectural floors derived from documented VM costs**:
   SendPort transit, isolate wake, FFI @Native isLeaf, sqlite3
   prepare/bind/step costs. Values cited from Dart VM design docs
   and the profile-mode noop measurements.

All resqlite numbers are median of 5 runs of `run_profile.dart` on
macOS arm64 (M1 Pro 10-core, 26.2), Dart 3.11.0 stable, SQLite as
shipped in resqlite (3.46 with `SQLITE_DEFAULT_WAL_SYNCHRONOUS=1` +
`SQLITE_DEFAULT_MEMSTATUS=0` + xxhash extension).

## The architectural floor — derived

What does a resqlite call MUST cost, ignoring all SQL work and decode
overhead?

| Layer | Cost (one way) | Notes |
|---|---:|---|
| Main → worker SendPort transit | ~1 μs | RawReceivePort fast path |
| Worker isolate wake + handler dispatch | ~1–2 μs | Event loop scheduling |
| Worker → main SendPort transit | ~1 μs | Reply port |
| Main `Future.then` continuation + await | ~0.5–1 μs | Microtask queue |
| **Round-trip floor (reader)** | **~4–5 μs** | |
| Writer mutex acquire + release | ~0.5 μs | FFI into C mutex |
| Writer dirty-tables / authorizer setup | ~1–2 μs | exp 070 persistent buf |
| **Round-trip floor (writer)** | **~6–8 μs** | |

**Observed dispatch floors** (`noop` workload, median of 5 runs):
- Reader (SELECT 1): **6 μs**
- Writer (UPDATE WHERE 1=0): **10 μs**

The observed floors are consistent with the derived floor plus 1–2 μs
of irreducible overhead from cross-isolate handshake and continuation
bookkeeping. **We cannot go below these floors without replacing
SendPort with shared-memory IPC.** That's a weeks-of-foundation-work
change (Tier 4 on the exp 080 portfolio), deferred until a user
workload makes sub-6μs reads a concrete requirement.

### Reference: sqlite3 package as the "no-isolate" floor

sqlite3 (the Dart package) runs entirely on the main thread via
synchronous FFI. Its measured cost approximates "bare Dart FFI +
bare SQLite" with zero isolate overhead.

Release-mode measurements (same machine):

| Operation | resqlite | sqlite3 (main) | Gap | Interpretation |
|---|---:|---:|---:|---|
| Point query (1 row, 6 cols) | 7.3 μs | **5.2 μs** | +2.1 μs | Isolate round-trip |
| Single insert | 17 μs | **8.9 μs** | +8.1 μs | Writer round-trip + hooks |
| Batch insert 100 | 0.55 μs/row | **0.49 μs/row** | +0.06 μs | Amortized, at floor |
| Batch insert 10k | 0.44 μs/row | **0.41 μs/row** | +0.03 μs | Fully amortized |
| Select 1k rows | 0.365 ms | **1.072 ms** | **−0.707 ms** | resqlite wins via decode path |
| Select 10k rows | 4.35 ms | **14.07 ms** | **−9.7 ms** | resqlite wins by 3.2× |

Two directions emerge clearly:

1. **Small-op latency:** resqlite trails sqlite3 by ~2 μs (reads) /
   ~8 μs (writes). That gap is pure isolate cost.
2. **Result-set throughput:** resqlite LEADS sqlite3 2–3× on
   medium-to-large selects because of exp-018 / exp-075 / exp-077
   decode-path optimizations (C-side cell buffer, cached prepare,
   fast ASCII decode). The isolate hop is dwarfed by decode savings
   once results exceed ~100 rows.

## Per-workload decomposition

### Point query — at the floor, by 1 μs

Measured: **7 μs median / 10 μs p90 / 26 μs p99**.

Decomposition vs sqlite3 (5.2 μs):

| Component | Cost | Notes |
|---|---:|---|
| Reader dispatch floor | 6 μs | observed noop median |
| SQLite PK lookup + step | ~500 ns | cached stmt, hot b-tree |
| FFI overhead (bind + step + reset) | ~300 ns | 3 @Native isLeaf calls |
| Cell decode (6 cols) | ~200 ns | optimized buffer-step |
| **Floor estimate** | **~7 μs** | matches measured |

**Headroom: zero on current architecture.** The 2.1 μs gap vs sqlite3
is exactly the isolate round-trip. To close it, replace SendPort
with shared memory — architectural, not optimizational.

`work_us_median` = 1 μs (total minus reader floor). That 1 μs is the
entire cost of "SQLite PK lookup + decode + type check" on the hot
path. It cannot be meaningfully reduced; SQLite isn't the bottleneck.

### Single insert — at the writer floor, ~8 μs above sqlite3

Measured: **16–17 μs median / 21 μs p90 / 50 μs p99**.

Decomposition vs sqlite3 (8.9 μs):

| Component | Cost | Notes |
|---|---:|---|
| Writer dispatch floor | 10 μs | observed noop median |
| sqlite3_step (INSERT + preupdate hook) | ~3 μs | page cache write, WAL frame append |
| Bind 5 params + reset | ~500 ns | cached stmt |
| dirtyTables marshaling | ~500 ns | exp 070 persistent buf |
| Authorizer read-tables capture | ~1 μs | per-stream setup on write path |
| **Floor estimate** | **~15–17 μs** | matches measured |

**Headroom: zero on current architecture + features.** The 8 μs gap
vs sqlite3 splits as:
- ~6 μs writer round-trip (feature: UI-thread offloading)
- ~2 μs writer-specific overhead (feature: stream invalidation)

Both are feature-enabling, not waste. Exp 081 attempted to skip
dirtyTables on zero-affected-row writes and found savings below the
noise floor — the overhead is broadly distributed, no single knob
removes a meaningful chunk.

`work_us_median` = 6–8 μs = the "real SQLite work" (bind + step +
reset + hook fire). Can't be reduced at this layer; this IS SQLite.

### Batched insert — at the sqlite3 floor

Measured: 100 rows = 55 μs total, 0.55 μs/row.

The isolate round-trip is paid ONCE per batch (10 μs) for ALL 100
rows. Per-row cost = 0.55 μs, within noise of sqlite3's 0.49 μs/row.

**Headroom: zero.** At 0.55 μs/row we are inside the statement-reuse
inner loop of SQLite itself. No architectural win possible at this
scale.

For larger batches (1k, 10k rows), resqlite asymptotes to matching
sqlite3 within 3–7% — the isolate hop becomes statistical noise.

### Large selects — ABOVE sqlite3

Measured: 1k rows = 0.37 ms, 10k rows = 4.35 ms. sqlite3 takes 1.07
and 14.07 respectively.

**resqlite is 3× faster than sqlite3 on large selects.** The decode-
path optimizations (C-side cell buffer, cached prepare, fast ASCII
text decode, lazy Row/ResultSet view) beat sqlite3's Dart binding's
per-cell FFI chatty approach.

**Headroom: genuinely negative.** We're already past sqlite3's
theoretical floor because of work done at a lower layer.

Exp 084 investigated whether columnar typed arrays would help further
(memory + transfer savings). Finding: modern Dart's SMI tagging moots
the int case, leaving only a ~2.5× win on double-heavy schemas. EV
doesn't justify the implementation cost absent a specific user need.

### Merge rounds — at the floor

Measured: 104 μs per batch, 1.04 μs/row.

Decomposition:
- Dispatch: 10 μs amortized across 100 rows = 0.1 μs/row
- Per-row INSERT OR REPLACE: b-tree traversal + WAL frame + preupdate
  hook fire × 100 = ~90 μs
- WAL fsync at batch boundary: ~5 μs

This is essentially the SQLite hot-path cost. No architectural win
available.

The `work_us_median` of 94 μs (out of 104) is 90% inside SQLite's
b-tree + WAL code. We can't optimize through SQLite; that's its own
engineering project.

### Memory — within arena noise for realistic workloads

Profile mode's `diagnostics_delta` block per workload (5-run medians):

| Workload | SQLite page cache Δ | SQLite stmt Δ | WAL Δ |
|---|---:|---:|---:|
| noop | 0 | 0 | 0 |
| single_insert | 0 | 0 | +1.71 MB |
| point_query | −17 KB | 0 | 0 |
| merge_rounds | +22 KB | +2 KB | +8 KB |

What this says:
- **Page cache is stable.** No leaks; stays within default cache
  size (~2 MB).
- **Statement cache growth is bounded.** 2 KB for merge_rounds is one
  prepared statement entry — well within the 32-stmt cache.
- **WAL grows with writes** as expected; passive checkpoint at 500
  pages keeps it bounded.

Exp 084 explored decode-time allocation. Conclusion: modern Dart's
SMI tagging already captures ~95% of the theoretical columnar win
for int columns. Remaining win is narrow (doubles only).

**Headroom: near-zero on the time axis. Narrow win available on
double-heavy decode if/when it matters.**

## What's left that's actually compressible

Three candidates with real-but-narrow EV:

### 1. p99 tail latency on sustained workloads (exp 083 partial)

Measured p99/p50 ratio: 3–5× on merge_rounds. Exp 083 showed passive
WAL checkpoints contribute: disabling them dropped merge_rounds p99
by 57%. But naïve disabling regresses single-insert p50 due to WAL
growth.

Fix path: dedicated checkpoint isolate with its own SQLite connection,
woken from the writer when WAL crosses threshold, runs independently
so it never blocks the writer.

Estimated effort: 1–2 weeks. Real surface area (reader snapshot
interaction, connection lifecycle).

User impact: modest. p99 of 50 μs → 30 μs won't show up in Flutter
frame budgets (16 ms at 60 fps, 8 ms at 120 fps). Matters only on
heavily-loaded apps where p99 spikes stack.

### 2. Stream re-invalidation cost on batched writes

Exp 080's fidelity side-finding: Sync Burst merge-rounds shows 144 μs/
batch of stream-engine overhead on top of the 107 μs isolated-profile
work. That's ~60% overhead on top of pure write cost when a stream
is active.

Exp 077 already handles the "no stream watches this table" case
cheaply. The remaining cost is: running the re-query when a stream's
read-tables intersect the dirty-tables, even if the rows the query
returns didn't change.

Fix paths (ordered by invasiveness):
- Profile-mode decomposition of where the 144 μs actually goes
  (~2 hours — may reveal non-obvious opportunity)
- Cross-batch emission coalescing (exp 079 territory — rejected for
  correctness concerns)
- Predicate-aware invalidation via SQLite update_hook + query
  predicate tracking (weeks of work, significant complexity)

User impact: moderate on apps with active streams. The 144 μs is
the dominant per-batch overhead on reactive workloads.

### 3. Memory for double-heavy schemas (exp 084 deferred)

Columnar typed arrays still offer ~2.5× backing reduction on float
columns. Narrow fit (financial, analytics, scientific schemas),
~1 week integration. Preserved integration plan in exp 084's doc.

User impact: contingent on user workload. Defer until concrete need.

## What's NOT compressible

For the record, so future experimenters don't re-investigate:

1. **Reader dispatch < 6 μs.** Requires replacing SendPort. Exp 082
   tried micro-optimizations on the Dart side; all below noise
   floor.

2. **Writer dispatch < 10 μs.** Same — features (mutex, hooks) are
   mandatory, round-trip is architectural. Exp 081 attempted
   Dart-side skips; below noise.

3. **Single-insert < 16 μs.** Cannot remove: writer round-trip
   (feature: UI-thread) + SQLite insert work (feature: durability).

4. **Point-query < 7 μs.** Same reasoning as reader dispatch.

5. **Decode for small results (<10 rows).** Already at the floor.
   Beyond this size, resqlite already beats sqlite3.

## User-impact reality check

For a typical Flutter app on a mid-tier 60 fps device:
- Per-frame budget: 16 ms
- Per-query latency tolerance: ~1 ms before UI jitter becomes
  perceptible
- Current worst case: merge_rounds max at 1 ms (p99 ~0.25 ms)

resqlite is already operating **two orders of magnitude** below
frame-budget concern on all measured workloads. Further time-axis
optimization has essentially zero user-perceptible impact.

Where optimization WOULD matter:
- A sustained write burst on a weak device that causes GC pauses
  above the frame budget (the "tail" case — exp 083 territory).
- A production-memory-pressure situation on a low-RAM Android
  device with repeatedly-large result sets (the "exp 084 double
  schema" case).

Both are contingent on specific production workloads.

## Recommendations

**Don't optimize for time.** We're at the architectural floor on
every measured workload. Further time-axis work has diminishing
returns and potentially negative ROI (complexity cost, regression
risk).

**Consider next, in priority order:**

1. **Profile-mode decomposition of the 144 μs stream overhead.**
   ~2 hours to learn whether it has a compressible component. If
   not, retire the candidate. If yes, decide based on what the
   breakdown reveals.

2. **Surface p99 + max in release-mode output.** Infrastructure,
   not experiment. A few hours. Adds tail-regression visibility to
   CI without changing column semantics of the dashboard (requires
   coordinated updates to parse_results / generate_devices /
   generate_history / dashboard HTML).

3. **Park architectural candidates** (dedicated checkpoint isolate,
   shared-memory IPC) on the backlog. Revisit when a specific user
   report of frame drops or latency tail emerges.

4. **Shift focus to non-performance axes.** DX, observability, docs,
   API ergonomics, new integrations. Performance is no longer the
   limiting factor in resqlite's value prop — architectural
   capabilities like streams and transactions are, and they have
   product surface area that performance alone doesn't.

## Reproduction

```bash
# Profile-mode measurements (5 runs used for this analysis):
dart run -DRESQLITE_PROFILE=true benchmark/run_profile.dart \
  --out=/tmp/p1.json
# ...repeat 5×, diff with benchmark/profile/diff.dart

# Release-mode peer comparison:
dart run benchmark/run_release.dart my-ceiling-check --repeat=5

# Columnar spike (memory-axis sanity check, exp 084):
dart run benchmark/profile/columnar_spike.dart
```

## Appendix: noop-subtract as a first-principles tool

The single most important tool from exp 080 was `work_us = total_us -
noop_median_us`. It lets us say:
- Point query: 1 μs work on 6 μs dispatch (dispatch-bound)
- Single insert: 7 μs work on 10 μs dispatch (mixed)
- Merge rounds: 94 μs work on 10 μs dispatch (work-bound)

That classification tells you where optimization is even theoretically
possible:
- Dispatch-bound: only architectural wins (SendPort replacement)
- Work-bound: SQL / decode / memory optimizations
- Mixed: both axes available

Every future resqlite perf experiment should lead with this
classification before picking a mechanism.
