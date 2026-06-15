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
also produces a trace, workload summary, insight artifacts, and graph data.
Because both your experiment branch AND the baseline it's compared against run
under the same profile build, the diagnostic overhead cancels out in the delta
-- what you see is the signal of your change.

For branch-vs-baseline timing decisions, prefer the integrated A/B wrapper:

```bash
dart run benchmark/run_tracelite_experiment.dart \
  --tracelite-root=/path/to/tracelite \
  --baseline-root=/path/to/resqlite-baseline \
  --candidate-root=/path/to/resqlite-candidate \
  --label=exp-N-short-slug \
  --direction=parameter-encoding-and-binding
```

It collects repeated Tracelite suite-history artifacts for each checkout, runs
`tracelite decision` over the histories, writes decision insights, and creates a
markdown experiment draft. Baseline and candidate collection use non-strict
suite-history runs so noisy policy calibration does not block the other side
from being measured. A rejected or inconclusive decision is still a completed
experiment artifact when the collection was clean; the generated writeup should
explain what was learned and whether the direction should be reopened,
deferred, or pruned.

For stream re-query dispatch experiments, the wrapper also gates
`warmup_elapsed_ns` as a guardrail. In the keyed and fan-out stream workloads,
that warmup interval is the initial stream-drain phase, so this catches changes
that speed up invalidation by making stream registration slower.

For changes that specifically affect stream registration-time classification,
use `--direction=stream-initial-drain`. That direction runs Tracelite's focused
initial-drain shapes, treats the rowid lookup as the primary scenario, and uses
the text and indexed-int lookup shapes as guardrails. It is the preferred lane
for checking whether rowid-specific stream optimizations pay for their setup
cost without adding a separate resqlite-local benchmark.

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
  enabled. The profile wrapper validates the region and runtime before
  running the workload driver.

If you add new diagnostic instrumentation, gate it the same way.
Never add unconditional instrumentation to production code paths
unless the cost is provably sub-nanosecond per call AND symmetric
across all peers being compared.

## Tracelite profile workflow

Tracelite is the profile workflow for new experiments. It gives one trace file
that can line up resqlite's database, worker, counter, fanout, and native spans
with workload summaries, insight artifacts, and graph data.

The preferred workflow is the wrapper:

```bash
git clone https://github.com/danReynolds/tracelite /path/to/tracelite
git -C /path/to/tracelite checkout 11159638962f5176678f02551a78180f5b9d3bba

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

The JSON artifacts are the structured data that runners and dashboards should
consume. The markdown siblings are review summaries over that data.

The wrapper deliberately shells out to a pinned local tracelite checkout instead
of adding tracelite as a resqlite dependency. It records `tracelite_source` in
the manifest and fails if the checkout is not at the default production pin
`11159638962f5176678f02551a78180f5b9d3bba` or is dirty. Use
`--allow-unpinned-tracelite` or `--allow-dirty-tracelite` only for local
tracelite development. The package code only keeps the compile-time trace
emitters.

For GitHub Pages, keep raw traces in `build/` but write the small graph-data
bundle directly to the dashboard input location:

```bash
dart run benchmark/profile/run_tracelite_profile.dart \
  --tracelite-root=/path/to/tracelite \
  --label=exp-N \
  --graph-data-dir=docs/benchmarks/data/tracelite/latest
```

The dashboard treats `docs/benchmarks/data/tracelite/latest/index.json` as
the canonical tracelite data source when present. The wrapper runs
`tracelite validate-graph-data` after export so malformed graph data fails
before it can be committed for Pages.

`benchmark/profile/run_tracelite_workloads.dart` is the child workload driver
used by the wrapper. It is not a standalone comparison command: it only creates
representative resqlite work and emits spans, counters, diagnostics, and RSS
samples into the active tracelite region. Use the wrapper unless you are
debugging the trace runtime itself.

If you do need to run the child directly while debugging a pre-created region:

```bash
TRACELITE_REGION=/tmp/resqlite.trace \
TRACELITE_RUNTIME=/path/to/libtracelite_runtime.dylib \
dart run \
  -DRESQLITE_PROFILE=true \
  -DRESQLITE_TRACELITE=true \
  benchmark/profile/run_tracelite_workloads.dart
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

## What the profile workload driver runs

`run_tracelite_profile.dart` invokes the workload driver for four
workloads, each run for 100 iterations after a 50-iteration warmup:

| Workload | What it measures | Samples |
|---|---|---|
| **Noop baseline** (`SELECT 1` / `UPDATE WHERE 1=0`) | Dispatch floor — pure isolate round-trip, no SQL work | 10k reads + 10k writes |
| **Single inserts** | Per-op insert cost (dispatch + bind + step + commit + stream invalidation) | 10k |
| **Point queries** | Single-row PK lookup cost (~100% dispatch-bound on resqlite) | 50k |
| **Merge rounds** | 100-row `INSERT OR REPLACE` batches (amortized dispatch) | 1k batches |

The noop baseline runs first. Its median is printed as the dispatch floor, and
the traced samples include enough metadata for tracelite's workload summary to
separate dispatch-heavy work from actual query work.

## Interpreting Tracelite artifacts

Read the workload summary and insights before drawing a conclusion:

- **Workload summary**: p50/p90/p99/max timings, per-workload counters, RSS
  samples, SQLite diagnostics, and profile counter snapshots.
- **Insights**: trace health, workload coverage, bottleneck hints, and
  suspicious outlier or missing-span conditions.
- **Graph data**: the dashboard-ready normalized view. If a run is meant to
  inform a public note or Pages view, validate and link this bundle.

Three things to keep in mind when interpreting:

1. **p99 and max on single runs are noisy.** Even with 1k samples, a
   single GC pause landing in one run and not the other can move p99
   10-20%. Run the A/B multiple times if the p99 story matters to
   your conclusion.
2. **Compare work medians, not total medians, on dispatch-hot
   workloads.** Point queries are ~100% dispatch-bound, so a "+1 us total"
   delta there could be pure dispatch-floor drift between runs, not
   anything your change did.
3. **RSS is a lower bound.** `ProcessInfo.currentRss` doesn't report
   heap space freed by GC but not returned to the OS. A visible RSS
   reduction means the allocation reduction is *at least* that large --
   often much more. SQLite counters and ALLOC counters are exact.

## Memory diagnostics in detail

The profile workflow captures three layers of memory data around each workload,
each answering a different question. In new experiments, read these from the
Tracelite workload summary and insights.

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
`experiments/NNN-my-experiment.md`. Include the relevant Tracelite decision,
workload summary, and insights inline, and link the generated Tracelite
artifact directory. If `run_tracelite_experiment.dart` produced
`<label>-experiment.md`, use that as the starting draft instead of rebuilding
the result table by hand. Do not commit raw trace regions from `build/`; keep
the small graph-data bundle only when it is meant to power Pages.

Before committing, add the README row and `experiments/signals.json` entry,
then run the experiment finalizer:

```bash
dart run benchmark/finalize_experiment.dart \
  --experiment=experiments/NNN-my-experiment.md
```

The finalizer regenerates `docs/experiments/history.json`, runs
`check_generated_data`, and runs `check_experiment_signals`. It also fails on
obvious draft placeholders or experiment files that are not indexed from the
README, which keeps the published experiment timeline in sync with the
writeup.

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
Graph data: build/tracelite-profile/exp-NNN/graph-data/

[paste the relevant workload-summary / insights excerpt here]

## Analysis
<what the numbers mean, whether the hypothesis held, caveats>

## Conclusion
<accept / reject / more work>
```

## DevTools cross-isolate timeline

When `-DRESQLITE_PROFILE=true` is set, the writer and reader isolates still
emit Timeline spans named `writer.handle.<RequestType>` and
`reader.handle.<RequestType>` around each message dispatch. Tracelite is the
maintained artifact path, but the Timeline markers remain useful as a local
debugging fallback while profile-mode counters still depend on the same flag.

To inspect both, create a region through `run_tracelite_profile.dart` or
manually run the child driver with `--observe`:

```bash
TRACELITE_REGION=/tmp/resqlite.trace \
TRACELITE_RUNTIME=/path/to/libtracelite_runtime.dylib \
dart --observe --profile-period=100 \
  -DRESQLITE_PROFILE=true \
  -DRESQLITE_TRACELITE=true \
  benchmark/profile/run_tracelite_workloads.dart
```

Open the service URL printed on startup in DevTools → Performance tab
→ record during the workload. The spans appear in the main, writer,
and reader isolate lanes and let you visually correlate per-op costs
with main-isolate `Future.then` continuations, GC events, and native
allocation.

## Anti-patterns

- **Don't run the workload driver directly for A/B conclusions.** It is an
  event source for tracelite, not the artifact producer or policy decision
  layer.
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
- [`benchmark/profile/run_tracelite_workloads.dart`](./profile/run_tracelite_workloads.dart)
  — the trace-only workload driver used by the wrapper
- [`benchmark/suites/memory.dart`](./suites/memory.dart) — the
  release-mode peer memory comparison suite (what the dashboard
  consumes); profile mode's memory capture is a superset for
  resqlite-only A/B
- [`experiments/080-dispatch-budget.md`](../experiments/080-dispatch-budget.md)
  — the findings that motivated this infrastructure
- [`README.md`](./README.md) § Release Mode vs Profile Mode — the
  dual-purpose framing
