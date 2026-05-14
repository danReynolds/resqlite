# resqlite Benchmarks

This folder serves **three distinct purposes**, each with its own
entry point. Choosing the right one matters because the production
code path you measure differs between them.

| Purpose | Entry point | resqlite code instrumented? |
|---|---|---|
| **Peer comparison / public dashboard** | [`run_release.dart`](./run_release.dart) | **No** — pristine, zero diagnostic overhead |
| **Trace-backed production gate** | [`run_tracelite.dart`](./run_tracelite.dart) | **No for peer timing; yes for opt-in trace hooks** |
| **Experiment vs baseline (resqlite-only A/B)** | [`run_profile.dart`](./run_profile.dart) | **Yes** — Timeline markers + per-call profiling |
| **Cross-library comparison via verifier harness** | `sqlite_reactive_verifier` | N/A (separate package) |

**Rule of thumb.** If you're publishing a number that will end up on
the public dashboard, or comparing resqlite against drift /
sqlite_async / sqlite3, use `run_release.dart` — it runs the exact
code a downstream user ships, with no instrumentation that could
distort the comparison.

If you're running the release gate for resqlite itself, use
`run_tracelite.dart`. It runs tracelite's cross-library production suite,
calibrates the resqlite release policy from repeated history, and can export the
graph-data bundle consumed by the benchmark dashboard. This is the preferred
pre-publish benchmark/profiling entry point once a local tracelite checkout is
available, but this PR should not delete the old regular profiling path until
the tracelite sole-framework gate has current production evidence.

If you're running an experiment on a branch and want to know whether
your change helped or hurt, use `run_profile.dart` — it compiles in
Timeline markers and wraps every call in `ProfiledDatabase`, so you
see dispatch-vs-work split, p99/max, cross-isolate timelines in
DevTools, and per-call JSON you can diff against a baseline. Both
your experiment branch AND its baseline run under the same profile
build, so the diagnostic overhead cancels out in the A/B delta.

See [EXPERIMENTS.md](./EXPERIMENTS.md) for the experiment-mode
workflow and A/B tabulation tools.

## Documentation

- [`METHODOLOGY.md`](./METHODOLOGY.md) — measurement rules, statistical approach, fairness protocol, peer version policy, Definition of Done for new workloads
- [`SCOPE.md`](./SCOPE.md) — exact peer versions, hardware tested, known gaps, what we test and what we don't
- [`AUDIT.md`](./AUDIT.md) — how benchmark results propagate from Dart code to the public dashboard (parsers, generators, chart builders)
- [`HARDWARE_RESULTS.md`](./HARDWARE_RESULTS.md) — device registry pointing at canonical result files per device
- [`EXPERIMENTS.md`](./EXPERIMENTS.md) — experiment-mode workflow using `run_profile.dart` and diff tools

## Release Mode (peer comparison)

Pristine code, no diagnostic overhead. Feeds the public dashboard.

From [`packages/resqlite`](/Users/dan/Coding/dune_gemini/packages/resqlite):

```bash
dart run benchmark/run_release.dart my-label
```

Useful options:

```bash
dart run benchmark/run_release.dart my-label --repeat=5
dart run benchmark/run_release.dart my-label --repeat=5 --compare-to=benchmark/results/2026-04-08T14-44-58-final.md
```

`run_release.dart`:
- accepts an explicit `--compare-to=...` baseline instead of always diffing against the latest file
- supports `--repeat=N` to rerun the full package-local suite multiple times
- emits a `Repeat Stability` section for resqlite medians
- uses a noise-aware comparison threshold of `max(10%, 3 × current MAD%)` with a `±0.02 ms` absolute floor for ultra-fast cases
- reports median (p50) and p90 per workload — same columns the dashboard parsers expect. Tail-percentile views (p99, max) are intentionally kept out of the release output and live in profile mode instead

That runs the package-local suites:

- select maps
- select bytes
- schema shapes
- scaling
- concurrent reads
- parameterized queries
- writes

Experiment-only scripts live under [benchmark/experiments](/Users/dan/Coding/dune_gemini/packages/resqlite/benchmark/experiments) and are intentionally not part of the default suite.

Recommended workflow for performance decisions:

1. Pick a pinned baseline with `--compare-to=...`
2. Run at least `--repeat=5`
3. Trust stable cases first; treat `Repeat Stability: noisy` rows as advisory

## Tracelite Production Gate

Trace-backed release benchmarking uses the local tracelite checkout as the
runner and artifact owner:

```bash
dart run benchmark/run_tracelite.dart \
  --tracelite-root=/path/to/tracelite \
  --label=prepublish-YYYY-MM-DD \
  --graph-data-dir=docs/benchmarks/data/tracelite/latest
```

The wrapper runs `tracelite suite-history --profile=production --runs=5` with
the calibrated resqlite release-gate scope:

- metric: `measured_elapsed_ns`
- peer: `resqlite`
- scenarios: chat simulation, feed paging, high-cardinality fanout,
  large working set, many-streams writer throughput, narrow batch insert,
  sqlite diagnostics, and sync burst
- repetition bounds: `--min-repetitions=5 --max-repetitions=30`
- noise target: `--target-rse-percent=10`
- threshold gate: `--threshold-floor-percent=5 --threshold-ceiling-percent=50`
- guardrail gate: `--guardrail-floor-percent=3`
- noise gate: `--noise-gate-floor-percent=5 --noise-gate-ceiling-percent=50
  --noise-gate-multiplier=1.5`

It writes `build/tracelite-benchmarks/<label>/history.json`,
`policy-calibration.json`, `policy-calibration.md`, and `graph-data/`. The
dashboard can read `docs/benchmarks/data/tracelite/latest/index.json` when the
graph-data output is published there.

Use the default strict mode for a publish gate. `--no-strict` is only for
local smoke runs where the requested history is intentionally too small to pass
the repetition and noise gates.

`point-select` and `keyed-pk-subscriptions` remain diagnostic workloads until
their current variance fits under the 50% release-gate threshold ceiling.

This gate is the candidate replacement for routine resqlite profiling, not yet
the only accepted framework. Before removing the old path as a fallback, keep
the PR draft until the scoped production history, policy calibration, graph-data
validation, and at least one real baseline/candidate decision are recorded from
current artifacts.

Current evidence: strict 2026-05-31 scoped runs against this PR completed 5/5
production suite histories, but policy calibration was still `not_ready`.
The first run rejected `feed-paging`, `large-working-set`, and
`narrow-batch-insert`. Row-sizing probes made those three pass in isolation, but
the full retuned gate still rejected `feed-paging`, `large-working-set`, and
`sync-burst`. The remaining noisy workloads need more stable definitions, a
documented diagnostic-lane split, or an explicit outlier policy before this
becomes the sole regular profiling workflow.

## Profile Mode (experiment vs baseline)

See [`EXPERIMENTS.md`](./EXPERIMENTS.md) for the full workflow. Short
version:

```bash
# On main (baseline)
dart run -DRESQLITE_PROFILE=true benchmark/run_profile.dart \
  --out=benchmark/profile/results/baseline.json

# On exp-N branch
dart run -DRESQLITE_PROFILE=true benchmark/run_profile.dart \
  --out=benchmark/profile/results/exp-N.json

# Compare
dart run benchmark/profile/diff.dart \
  benchmark/profile/results/baseline.json \
  benchmark/profile/results/exp-N.json
```

The `-DRESQLITE_PROFILE=true` flag compiles in Timeline markers and
wraps scenarios in `ProfiledDatabase`. Because both runs use the
same flag, any diagnostic overhead cancels out in the delta — what
you see is the signal of your actual change.

For a tracelite-backed run that also emits graphable artifacts, use the
workflow wrapper:

```bash
dart run benchmark/profile/run_tracelite_profile.dart \
  --tracelite-root=/path/to/tracelite \
  --label=exp-N
```

It writes `build/tracelite-profile/exp-N/` with the legacy profile JSON,
the `.tlt-region`, `workload-summary.json`, `workload-summary.md`,
`graph-data/`, and a parity diff between the legacy JSON and tracelite's
workload summary. `run_profile.dart` remains the direct low-level harness;
the wrapper is the preferred path when the result should feed tracelite or
resqlite Pages data.

To publish only graphable data to GitHub Pages while keeping raw traces and
legacy JSON out of `docs/`, add:

```bash
--graph-data-dir=docs/benchmarks/data/tracelite/latest
```

The dashboard consumes `docs/benchmarks/data/tracelite/latest/index.json`
when present and hides the tracelite section when the bundle is absent. The
wrapper validates the graph-data bundle with tracelite before finishing, so a
malformed Pages handoff fails the profile run instead of surfacing later as an
empty dashboard section.

## Main-only Four-Way Comparison

Run `resqlite` in its own process, then run the verifier for the peer libraries.

### 1. Run resqlite

From [`packages/resqlite`](/Users/dan/Coding/dune_gemini/packages/resqlite):

```bash
dart run benchmark/head_to_head_worker.dart \
  --out=/tmp/resqlite_main_h2h.json
```

### 2. Run verifier core cases

From [`packages/sqlite_reactive_verifier`](/Users/dan/Coding/dune_gemini/packages/sqlite_reactive_verifier):

```bash
flutter pub run bin/sqlite_reactive_benchmark.dart \
  --libraries=sqlite_reactive,sqlite_async,sqlite3 \
  --benchmarks=open_only,cold_open,single_row_crud,batch_write_transaction,read_under_write,large_result_read,large_result_read_large,repeated_point_query \
  --db-root=/tmp/resqlite_main_rebench \
  --out-json=/tmp/resqlite_main_rebench_core.json
```

### 3. Run verifier reactive cases

From [`packages/sqlite_reactive_verifier`](/Users/dan/Coding/dune_gemini/packages/sqlite_reactive_verifier):

```bash
flutter pub run bin/sqlite_reactive_benchmark.dart \
  --libraries=sqlite_reactive,sqlite_async \
  --benchmarks=stream_invalidation_latency,burst_coalescing,reactive_fanout_shared_query,reactive_fanout_unique_queries \
  --db-root=/tmp/resqlite_main_rebench \
  --out-json=/tmp/resqlite_main_rebench_reactive.json
```

### 4. Read the outputs

The generated files are:

- `/tmp/resqlite_main_h2h.json`
- `/tmp/resqlite_main_rebench_core.json`
- `/tmp/resqlite_main_rebench_reactive.json`

`resqlite` and the verifier are intentionally run as separate commands because loading them into the same VM can hit native asset / SQLite symbol conflicts.

This is the preferred way to compare `resqlite` against:

- `sqlite_reactive`
- `sqlite_async`
- `sqlite3`

## Current Main Baseline

Latest checked-in main-only baseline:

- [2026-04-08-codex-main-four-way.md](/Users/dan/Coding/dune_gemini/packages/resqlite/benchmark/results/2026-04-08-codex-main-four-way.md)
