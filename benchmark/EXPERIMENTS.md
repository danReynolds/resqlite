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

The default profile workflow now runs this through tracelite, so the same run
also produces a trace, workload summary, insight artifacts, graph data, and
legacy JSON parity evidence. Because both your experiment branch AND the
baseline it's compared against run under the same profile build, the diagnostic
overhead cancels out in the delta — what you see is the signal of your change.

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
why `run_release.dart` can use the same resqlite source code as the
Tracelite profile workflow without any overhead.

Currently gated:

- `Timeline.startSync` / `finishSync` markers around per-message
  dispatch in the writer (`lib/src/writer/write_worker.dart`) and
  reader (`lib/src/reader/read_worker.dart`) isolates.
- `ProfileCounters.rowsDecoded` / `cellsDecoded` increments in the
  `benchmark/profile/profiled_database.dart` wrapper's `select()`
  method. The counter fields themselves live in
  `lib/src/profile_counters.dart` and cost nothing unless incremented.
- Optional tracelite mirror events when both `RESQLITE_PROFILE` and
  `RESQLITE_TRACELITE` are enabled. These cover public database
  operation spans, transaction bodies, reader/writer handling,
  reader-pool dispatch, correlated stream invalidation and re-query,
  profile counters, and embedded SQLite calls when `trace_sqlite` is
  enabled. The runtime attach is best-effort;
  missing `TRACELITE_REGION` or runtime symbols leave the normal
  profile harness unchanged.

If you add new diagnostic instrumentation, gate it the same way.
Never add unconditional instrumentation to production code paths
unless the cost is provably sub-nanosecond per call AND symmetric
across all peers being compared.

## Tracelite profile workflow

Tracelite is the preferred profile workflow for new experiments. It gives one
trace file that can line up resqlite's database, worker, counter, fanout, and
native spans with workload summaries, insight artifacts, graph data, and a
compatibility diff against the old JSON shape.

The preferred workflow is the wrapper:

```bash
git clone https://github.com/danReynolds/tracelite /path/to/tracelite
git -C /path/to/tracelite checkout resqlite-profiling-gate-2026-06-02-r10

dart run benchmark/profile/run_tracelite_profile.dart \
  --tracelite-root=/path/to/tracelite \
  --label=exp-N
```

By default it writes `build/tracelite-profile/exp-N/`.

Primary tracelite artifacts:

- `profile.tlt-region`: the raw tracelite region.
- `workload-summary.json` and `workload-summary.md`: tracelite's
  resqlite workload summary export.
- `insights.json` and `insights.md`: Tracelite's interpretation of trace
  health, workload coverage, and bottleneck signals.
- `graph-data/`: normalized JSON datasets for downstream dashboards.

Compatibility/parity artifacts:

- `profile.json`: the legacy `run_profile.dart` artifact, for existing
  diff tools and older experiment notes.
- `parity-diff.txt`: `benchmark/profile/diff.dart` comparing the legacy
  JSON against tracelite's workload summary.

The wrapper deliberately shells out to a pinned local tracelite checkout instead
of adding tracelite as a resqlite dependency. It records `tracelite_source` in
the manifest and fails if the checkout is not at the default production pin
`d058647a123df0f4af223a110564b862de2eda05` or is dirty. Use
`--allow-unpinned-tracelite` or `--allow-dirty-tracelite` only for local
tracelite development. The package code only keeps the compile-time trace
emitters.

For GitHub Pages, keep raw traces and legacy JSON in `build/` but write the
small graph-data bundle directly to the dashboard input location:

```bash
dart run benchmark/profile/run_tracelite_profile.dart \
  --tracelite-root=/path/to/tracelite \
  --label=exp-N \
  --graph-data-dir=docs/benchmarks/data/tracelite/latest
```

The dashboard treats `docs/benchmarks/data/tracelite/latest/index.json` as
the canonical tracelite data source when present. New profiling views should
use this graph-data bundle, not the legacy profile JSON compatibility shape.
The wrapper runs `tracelite validate-graph-data` after export so malformed
graph data fails before it can be committed for Pages.

You can still run the low-level harness directly when a region is already
active or when an older note specifically needs raw legacy profile JSON:

```bash
TRACELITE_REGION=/tmp/resqlite.trace \
TRACELITE_RUNTIME=/path/to/libtracelite_runtime.dylib \
dart run \
  -DRESQLITE_PROFILE=true \
  -DRESQLITE_TRACELITE=true \
  benchmark/run_profile.dart \
  --out=benchmark/profile/results/tracelite.json
```

For SQLite-level timing inside resqlite's embedded sqlite3mc build,
enable the native asset hook path from the consuming package:

```yaml
hooks:
  user_defines:
    resqlite:
      trace_sqlite: true
      tracelite_root: /path/to/tracelite
```

`trace_sqlite` rewrites the embedded sqlite3mc public SQLite symbols
behind `tlt_` names, compiles the tracelite runtime and SQLite shim
into `libresqlite`, and lets the shim own the normal SQLite ABI
symbols. Keep this out of release benchmark runs; it is for trace
capture, not public dashboard numbers.

## Legacy three-command workflow

Use this direct legacy workflow only when you need old JSON A/B diffing without
tracelite artifacts. New experiment notes should prefer the tracelite wrapper
above and link the workload summary, insights, graph data, and parity diff.

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

## What the profile workload harness runs

`run_tracelite_profile.dart` invokes the low-level profile harness for four
workloads, each run for 100 iterations after a 50-iteration warmup:

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

The profile harness captures three layers of memory data around each workload,
each answering a different question. In new experiments, read these from the
Tracelite profile wrapper's workload summary and compatibility `profile.json`.

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
`experiments/NNN-my-experiment.md`. Include the relevant Tracelite workload
summary, insights, and parity-diff evidence inline, and link the generated
Tracelite artifact directory. Do not commit raw profile JSONs from
`benchmark/profile/results/`; the CI guard rejects those because they are large,
local, and hardware-specific. Commit the aggregate markdown or experiment
writeup instead.

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

Tracelite profile: build/tracelite-profile/exp-NNN/
Workload summary: build/tracelite-profile/exp-NNN/workload-summary.md
Insights: build/tracelite-profile/exp-NNN/insights.md
Legacy parity JSON: build/tracelite-profile/exp-NNN/profile.json

[paste the relevant workload-summary / insights / parity-diff excerpt here]

## Analysis
<what the numbers mean, whether the hypothesis held, caveats>

## Conclusion
<accept / reject / more work>
```

## DevTools cross-isolate timeline

When `-DRESQLITE_PROFILE=true` is set, the writer and reader isolates
emit Timeline spans named `writer.handle.<RequestType>` and
`reader.handle.<RequestType>` around each message dispatch. To see
them in DevTools, intentionally run the low-level harness directly:

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
