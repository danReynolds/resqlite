# Running Performance Experiments

This document covers the **experiment-vs-baseline** benchmark workflow
— i.e. when you have a change on a branch and you want to know whether
it helped or hurt. For peer comparison against drift / sqlite_async /
sqlite3 (the numbers that feed the public dashboard), use
[`run_release.dart`](./run_release.dart) instead. See the
[benchmark README](./README.md) for the distinction.

## Why a separate harness

The release-mode suite (`run_release.dart`) runs resqlite's production
code *exactly as downstream users ship it* — no instrumentation, no
wrappers, no compile-time flags. That's deliberate: any overhead we
add to resqlite but not to the peers would silently skew the
comparison numbers on the public dashboard.

But when you're investigating "did my change help?", you want the
opposite. You want rich diagnostics:

- Per-call timing so you can see p50, p90, **p99**, and max
  (tail-latency regressions hide in p99 and max — exp 083 found a
  57% p99 delta on merge workloads from a single compile-time
  constant change while p50/p90 barely moved).
- Dispatch-vs-work split (from subtracting the noop floor) so you
  can say "this saved X μs of work on top of Y μs of unavoidable
  dispatch" instead of just "total got faster."
- Cross-isolate Timeline spans visible in DevTools (`writer.handle.*`
  / `reader.handle.*`) so you can see where each microsecond goes.
- **Memory diagnostics** — per-workload RSS deltas, SQLite
  per-connection memory counters (page cache / schema cache / stmt
  cache / WAL bytes), and Dart-side allocation counters (rows
  decoded, cells decoded). This is the axis exp 055's columnar
  typed arrays and similar memory-targeted experiments live on —
  wins there are invisible to time-only benchmarks.

Profile mode gives you all of this. Because both your experiment
branch AND the baseline it's compared against run under the same
`-DRESQLITE_PROFILE=true` build, the diagnostic overhead cancels out
in the delta — what you see is the signal of your change.

## The compile-time gate

All profile-mode instrumentation in resqlite's production code paths
is gated behind:

```dart
// lib/src/profile_mode.dart
const bool kProfileMode =
    bool.fromEnvironment('RESQLITE_PROFILE', defaultValue: false);
```

When you run without `-DRESQLITE_PROFILE=true`, the gate is `false`
and Dart's AOT compiler tree-shakes every `if (kProfileMode) { ... }`
branch away entirely. Zero bytes, zero cycles on the hot path. That's
why `run_release.dart` can use the same resqlite source code as
`run_profile.dart` without any overhead.

Currently gated:

- `Timeline.startSync` / `finishSync` markers around per-message
  dispatch in the writer (`lib/src/writer/write_worker.dart`) and
  reader (`lib/src/reader/read_worker.dart`) isolates.
- `ProfileCounters.rowsDecoded` / `cellsDecoded` increments in the
  `benchmark/profile/profiled_database.dart` wrapper's `select()`
  method. The counter fields themselves live in
  `lib/src/profile_counters.dart` and cost nothing unless incremented.

If you add new diagnostic instrumentation, gate it the same way.
Never add unconditional instrumentation to production code paths
unless the cost is provably sub-nanosecond per call AND symmetric
across all peers being compared.

## The three-command workflow

```bash
# 1. On main (baseline)
git checkout main
dart run -DRESQLITE_PROFILE=true benchmark/run_profile.dart \
  --out=benchmark/profile/results/baseline.json

# 2. On your experiment branch
git checkout exp-N-my-change
dart run -DRESQLITE_PROFILE=true benchmark/run_profile.dart \
  --out=benchmark/profile/results/exp-N.json

# 3. Compare
dart run benchmark/profile/diff.dart \
  benchmark/profile/results/baseline.json \
  benchmark/profile/results/exp-N.json
```

The diff tool prints one table per workload with p50/p90/p99/max/work
deltas in both absolute μs and percent. Exit code is always 0 — it's
a reporting tool, not a pass/fail gate. The experimenter interprets
deltas against their hypothesis.

## What `run_profile.dart` runs

Four workloads, each run for 100 iterations after a 50-iteration
warmup:

| Workload | What it measures | Samples |
|---|---|---|
| **Noop baseline** (`SELECT 1` / `UPDATE WHERE 1=0`) | Dispatch floor — pure isolate round-trip, no SQL work | 10k reads + 10k writes |
| **Single inserts** | Per-op insert cost (dispatch + bind + step + commit + stream invalidation) | 10k |
| **Point queries** | Single-row PK lookup cost (~100% dispatch-bound on resqlite) | 50k |
| **Merge rounds** | 100-row `INSERT OR REPLACE` batches (amortized dispatch) | 1k batches |

The noop baseline runs first. Its median becomes the dispatch floor,
and every subsequent workload's JSON includes a `work_us_median =
total_us_median - dispatch_floor_us` column. That's the key
methodology for distinguishing "our change saved dispatch cost" from
"our change saved query work."

## Interpreting a diff

Example output from `dart run benchmark/profile/diff.dart A.json B.json`:

```
## merge_rounds
  TIME executeBatch:
    p50      110μs →    106μs      -4μs  (-3.6%)
    p90      178μs →    131μs     -47μs  (-26.4%)
    p99      607μs →    335μs    -272μs  (-44.8%)
    max     4034μs →    800μs   -3234μs  (-80.2%)
    work      99μs →     95μs      -4μs  (-4.0%)
  MEMORY (process RSS):
    rss Δ   1.53 MB →   0.05 MB  -1.48 MB  (-96.9%)
  SQLITE (per-connection counters, per-workload delta):
    page cache    21.3 KB →    21.3 KB          +0 B  (+0.0%)
    stmt           2.0 KB →     2.0 KB          +0 B  (+0.0%)
    wal            8.0 KB →     8.0 KB          +0 B  (+0.0%)
  ALLOC (decoder counters, per-workload delta):
    rows                50000 →      50000            +0
    cells              300000 →     300000            +0
```

Reading this:

- **TIME p50 barely moved** (−3.6%). The median case is unaffected.
- **TIME p99 dropped 44.8%**. The tail shrank dramatically. Something
  that was happening ~1% of the time — a WAL checkpoint, a GC pause,
  a scheduler stall — is happening less often or being resolved
  faster in the candidate build.
- **TIME max dropped 80%**. The absolute worst case got much better.
- **TIME work dropped 4μs**. The dispatch-subtracted time (i.e.
  actual per-batch SQL work) is 4μs faster at the median.
- **MEMORY rss Δ dropped 97%**. Far less process memory grew during
  this workload — a strong allocation-reduction signal. (Note: RSS is
  a lower bound; the Dart VM retains heap pages after GC so small
  wins may show as zero.)
- **SQLITE counters unchanged**. The SQLite-internal memory (page
  cache, stmt cache, WAL) is identical across builds — the change
  didn't affect SQLite-level memory, only Dart-heap allocation.
- **ALLOC counters unchanged**. The decoder materialized the same
  number of rows and cells — the workload produced the same data.
  If an exp-055-style columnar-typed-arrays candidate were being
  tested, you'd look for the rows/cells columns staying identical
  (same work) while RSS Δ dropped (less allocation for that work).

Three things to keep in mind when interpreting:

1. **p99 and max on single runs are noisy.** Even with 1k samples, a
   single GC pause landing in one run and not the other can move p99
   10–20%. Run the A/B multiple times if the p99 story matters to
   your conclusion. Exp 083 used 5 runs per variant and took medians
   of percentiles across runs.
2. **Compare work medians, not total medians, on dispatch-hot
   workloads.** Point queries are ~100% dispatch-bound — a "+1μs total"
   delta there could be pure dispatch-floor drift between runs, not
   anything your change did. The `work` column subtracts that.
3. **RSS is a lower bound.** `ProcessInfo.currentRss` doesn't report
   heap space freed by GC but not returned to the OS. A visible RSS
   reduction means the allocation reduction is *at least* that large —
   often much more. SQLite counters and ALLOC counters are exact.

## Memory diagnostics in detail

`run_profile.dart` captures three layers of memory data around each
workload, each answering a different question:

**Process RSS** (`rss_before_mb`, `rss_after_mb`, `rss_delta_mb`) —
coarse, inclusive of everything: Dart heap, SQLite's internal
buffers, FFI allocations, OS page tables, and any other process
memory. The methodology mirrors `benchmark/suites/memory.dart` —
heap-churn preamble, two churn passes, then baseline capture. Lower
bound on actual allocation because the VM retains freed pages. Best
for broad "did this change reduce total memory pressure" questions.

**SQLite per-connection counters** (`diagnostics_before`,
`diagnostics_after`, `diagnostics_delta`) — exact bytes reported by
SQLite's `sqlite3_db_status` API for page cache, schema cache, and
prepared statement cache, plus the `-wal` sidecar file size on disk.
Cross-isolate aware (the underlying FFI call aggregates across the
writer + idle readers). Best for distinguishing "SQLite held more
pages" from "Dart heap grew."

**Decoder allocation counters** (`allocation_delta`) — exact count
of rows and cells that passed through the decode path and reached
user code. Currently populated main-isolate-side via the
`ProfiledDatabase` wrapper, so it sees reader-pool results but not
internal stream re-queries unless they route through a harness call
site. Best for sanity checking that two runs did the same work (a
candidate that decodes fewer rows because it was hash-short-
circuited is not comparable).

If you need per-SQLite-type counts (e.g. "how many int cells got
boxed into the `List<Object?>`, the exp 055 metric), that's a
worker-isolate counter that requires a cross-isolate snapshot
round-trip — not shipped today. Add the round-trip as part of the
experiment that needs it; `lib/src/profile_counters.dart` has room
for new fields.

## Writing results to `experiments/NNN-*.md`

When you finalize an experiment (accept or reject), create
`experiments/NNN-my-experiment.md`. Include the diff output inline and
commit the `*.json` files to `benchmark/profile/results/` so the
measurement is reproducible.

Template:

```markdown
# Experiment NNN: <short title>

**Date:** YYYY-MM-DD
**Status:** Accepted / Rejected / Mixed

## Hypothesis
<what you expected the change to do and why>

## Approach
<what the code change was, 1-2 paragraphs>

## Results

Baseline: benchmark/profile/results/baseline.json
Candidate: benchmark/profile/results/exp-NNN.json

[paste `diff.dart` output here]

## Analysis
<what the numbers mean, whether the hypothesis held, caveats>

## Conclusion
<accept / reject / more work>
```

## DevTools cross-isolate timeline

When `-DRESQLITE_PROFILE=true` is set, the writer and reader isolates
emit Timeline spans named `writer.handle.<RequestType>` and
`reader.handle.<RequestType>` around each message dispatch. To see
them:

```bash
dart --observe --profile-period=100 \
  -DRESQLITE_PROFILE=true benchmark/run_profile.dart
```

Open the service URL printed on startup in DevTools → Performance tab
→ record during the workload. The spans appear in the main, writer,
and reader isolate lanes and let you visually correlate per-op costs
with main-isolate `Future.then` continuations, GC events, and native
allocation.

## Anti-patterns

- **Don't run `run_profile.dart` without `-DRESQLITE_PROFILE=true`
  and think you're measuring the same thing.** Without the flag the
  Timeline markers are tree-shaken out; you still get ProfiledDatabase
  wall times but no cross-isolate breakdown. `run_profile.dart` prints
  a warning at startup when the flag is missing.
- **Don't mix a profile-mode JSON with a release-mode result for
  diffing.** The output formats are different; diff.dart only reads
  profile-mode JSON. If you're comparing release numbers, use
  `run_release.dart --compare-to=baseline.md` instead.
- **Don't put `-DRESQLITE_PROFILE=true` in CI's release benchmark
  step.** The CI workflow in `.github/workflows/ci.yml` runs
  `run_release.dart` precisely because release numbers are what feed
  the public dashboard. Adding the profile flag there would change
  what's published.

## See also

- [`lib/src/profile_mode.dart`](../lib/src/profile_mode.dart) — the
  compile-time gate
- [`lib/src/profile_counters.dart`](../lib/src/profile_counters.dart)
  — allocation counter module; add new fields here for future
  memory-axis experiments
- [`lib/src/diagnostics.dart`](../lib/src/diagnostics.dart) —
  the public SQLite per-connection memory API (not profile-gated;
  production users can call `Database.diagnostics()` at runtime)
- [`benchmark/profile/profiled_database.dart`](./profile/profiled_database.dart)
  — the per-call timing wrapper, also home of the main-side counter
  increments
- [`benchmark/profile/dispatch_budget.dart`](./profile/dispatch_budget.dart)
  — the original Phase-1 harness that `run_profile.dart` is built on
- [`benchmark/suites/memory.dart`](./suites/memory.dart) — the
  release-mode peer memory comparison suite (what the dashboard
  consumes); profile mode's memory capture is a superset for
  resqlite-only A/B
- [`experiments/080-dispatch-budget.md`](../experiments/080-dispatch-budget.md)
  — the findings that motivated this infrastructure
- [`README.md`](./README.md) § Release Mode vs Profile Mode — the
  dual-purpose framing
