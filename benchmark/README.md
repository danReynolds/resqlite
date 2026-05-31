# resqlite Benchmarks

This folder serves **three distinct purposes**, each with its own
entry point. Choosing the right one matters because the production
code path you measure differs between them.

| Purpose | Entry point | resqlite code instrumented? |
|---|---|---|
| **Peer comparison / public dashboard** | [`run_release.dart`](./run_release.dart) | **No** — pristine, zero diagnostic overhead |
| **Trace-backed production gate** | [`run_tracelite.dart`](./run_tracelite.dart) | **No for peer timing; yes for opt-in trace hooks** |
| **Trace-backed baseline/candidate decision** | [`decide_tracelite.dart`](./decide_tracelite.dart) | **No for peer timing; yes for opt-in trace hooks** |
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
pre-publish benchmark/profiling entry point. The wrapper requires the local
tracelite checkout to match the pinned production source revision by default.

If you already have baseline and candidate tracelite suite manifests, use
`decide_tracelite.dart`. It applies the calibrated release-lane policy to
`tracelite decision`, writes a durable decision artifact, and exports graph data
for the dashboard. The wrapper intentionally defaults guardrails to
`measured_elapsed_ns`; lower-level timing totals are still useful diagnostics,
but they are not calibrated release blockers yet.

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

## Tracelite Presets

Trace-backed release benchmarking uses the pinned tracelite checkout as the
runner and artifact owner:

```bash
git clone https://github.com/danReynolds/tracelite /path/to/tracelite
git -C /path/to/tracelite checkout resqlite-profiling-gate-2026-05-31
```

```bash
dart run benchmark/run_tracelite.dart \
  --preset=production \
  --tracelite-root=/path/to/tracelite \
  --resqlite-root="$PWD" \
  --label=prepublish-YYYY-MM-DD \
  --graph-data-dir=docs/benchmarks/data/tracelite/latest
```

`run_tracelite.dart` has three presets. Every preset still records
`tracelite_source`, `resqlite_source`, and the resolved Tracelite dependency
binding, exports graph data, and validates that graph-data bundle. Explicit CLI
flags override preset defaults. The wrapper also rebuilds Tracelite's
`build/libsqlite_traced.dylib` SQLite shim for fresh macOS checkouts before any
preset runs, so CI does not depend on a pre-warmed Tracelite build directory.

| Preset | Use when | Default shape |
|---|---|---|
| `ci` | Routine PR smoke and trace-health checks | Tracelite `ci` profile, `runs=1`, `interfaces=resqlite`, tiny `narrow-batch-insert`, `point-select`, `keyed-pk-subscriptions`, and `sqlite-diagnostics` scenarios |
| `experiment` | Collect focused baseline/candidate artifacts for a perf change | Tracelite `production` profile, `runs=3`, `interfaces=sqlite_async,resqlite`, `feed-paging`, `chat-sim`, and `keyed-pk-subscriptions` |
| `production` | Pre-publish or major perf-change gate | Tracelite `production` profile, `runs=5`, full peer matrix and full suite |

Routine CI should use:

```bash
dart run benchmark/run_tracelite.dart \
  --preset=ci \
  --tracelite-root=/path/to/tracelite \
  --resqlite-root="$PWD" \
  --label=ci-smoke
```

Perf experiments should start focused, then override scenarios to match the
change:

```bash
dart run benchmark/run_tracelite.dart \
  --preset=experiment \
  --tracelite-root=/path/to/tracelite \
  --resqlite-root="$PWD" \
  --label=exp-123-baseline \
  --suite-scenarios=high-cardinality-fanout,many-streams-writer-throughput \
  --policy-scenarios=high-cardinality-fanout,many-streams-writer-throughput
```

The default pin is
`bcb3f3f419a09aa682948595fdb8ab002af637dc`
(`resqlite-profiling-gate-2026-05-31`). The wrapper records
`tracelite_source` in its manifest and fails if the checkout is not at that
revision or is dirty. It also records `resqlite_source` and verifies that
Tracelite's resolved `resqlite` package points at the checkout under test. If
`/path/to/tracelite/pubspec_overrides.yaml` is missing, the wrapper creates an
ignored override for `--resqlite-root`; if an existing override points anywhere
else, the gate fails before running the suite. Use
`--allow-unpinned-tracelite` or `--allow-dirty-tracelite` only for local
tracelite development.

The `production` preset runs
`tracelite suite-history --profile=production --runs=5`. It separates suite
coverage from release-gate policy:

- metric: `measured_elapsed_ns`
- peer: `resqlite`
- production suite scenarios: narrow batch insert, point select, feed paging,
  sync burst, chat simulation, large working set, keyed-PK subscriptions,
  high-cardinality fanout, many-streams writer throughput, and sqlite
  diagnostics
- production strict policy scenarios: chat simulation, high-cardinality fanout,
  many-streams writer throughput, narrow batch insert, and sqlite diagnostics
- repetition bounds: `--min-repetitions=5 --max-repetitions=30`
- noise target: `--target-rse-percent=10`
- robust within-run noise percentile: `--within-run-noise-percentile=0.75`
- threshold gate: `--threshold-floor-percent=5 --threshold-ceiling-percent=50`
- guardrail gate: `--guardrail-floor-percent=3`
- noise gate: `--noise-gate-floor-percent=5 --noise-gate-ceiling-percent=50
  --noise-gate-multiplier=1.5`
- outlier gates: `--max-outlier-percent=10 --max-run-outlier-percent=20`

It writes `build/tracelite-benchmarks/<label>/history.json`,
`policy-calibration.json`, `policy-calibration.md`, and `graph-data/`. The
dashboard can read `docs/benchmarks/data/tracelite/latest/index.json` when the
graph-data output is published there.

Use the default strict mode for CI and publish gates. `--no-strict` is only for
local exploratory runs where the requested history is intentionally too small to
pass the repetition and noise gates. Suite failures and trace diagnostics still
make the wrapper manifest invalid; graph data is exported when possible so the
failed run can be inspected. If a failed suite produced no compare artifacts,
graph export is skipped with an explicit wrapper step instead of masking the
suite failure with a secondary export crash.

`point-select`, `feed-paging`, `sync-burst`, `large-working-set`, and
`keyed-pk-subscriptions` are diagnostic suite workloads by default: they are
still measured and exported to graph data, but they do not block the strict
publish policy until their current variance fits under the 50% release-gate
threshold ceiling.

Current evidence: the strict pinned-source
`sole-gate-2026-05-31-resqlite-pinned-source` run completed 5/5 production
suite histories, exported graph data, and passed graph-data validation. Its
manifest recorded `tracelite_source.source_ok=true` and
`revision_matches_pin=true`, with `tracelite_resqlite_dependency`
matching the resqlite checkout under test. Its release-lane
`policy-calibration.json` was
`ready` for 5/5 groups with a 27.5% primary threshold, 20.5% max regression
guardrail, and 20.5% max-CV gate. The gate uses the p75 within-run noise policy
and the outlier ceilings listed above.

The same artifacts also produced an accepted routine no-regression decision:

```bash
dart run benchmark/decide_tracelite.dart \
  --tracelite-root=/path/to/tracelite \
  --baseline=build/tracelite-benchmarks/sole-gate-2026-05-31-resqlite-pinned-source/run-001-20260531T154622Z/manifest.json \
  --candidate=build/tracelite-benchmarks/sole-gate-2026-05-31-resqlite-pinned-source/run-005-20260531T155915Z/manifest.json \
  --policy=build/tracelite-benchmarks/sole-gate-2026-05-31-resqlite-pinned-source/policy-calibration.json \
  --label=sole-gate-2026-05-31-resqlite-pinned-no-regression
```

That decision passed trace health, primary, and guardrail gates for the
release-lane `measured_elapsed_ns` metric and exported validated graph data with
suite and decision rows. Its wrapper manifest also recorded
`tracelite_source.source_ok=true` and `revision_matches_pin=true`.

The decision path also rejected a known injected read-path regression:

```bash
dart run benchmark/decide_tracelite.dart \
  --tracelite-root=/path/to/tracelite \
  --baseline=build/tracelite-benchmarks/sole-gate-2026-05-31-resqlite-pinned-source/run-001-20260531T154622Z/manifest.json \
  --candidate=build/tracelite-decisions/known-read-delay-regression/candidate/manifest.json \
  --policy=build/tracelite-benchmarks/sole-gate-2026-05-31-resqlite-pinned-source/policy-calibration.json \
  --label=known-read-delay-regression-pinned-policy
```

That artifact reported `rejected`: trace health passed, while primary and
guardrail gates rejected the delayed candidate on `chat-sim`,
`narrow-batch-insert`, and `sqlite-diagnostics`. Its graph-data bundle
validated. The decision wrapper manifest recorded the pinned tracelite source as
clean and matching.

This is now credible as the primary resqlite pre-publish profiling path. The
source pin is enforced by the wrapper instead of living only in operator notes.
`run_profile.dart` remains as the low-level compatibility/parity harness, but
routine regression decisions should use the tracelite gate or decision wrapper.

The remaining noisy workloads stay in the diagnostic lane until they have stable
workload definitions or separate calibrated thresholds.

## Tracelite Baseline/Candidate Decision

Use this after collecting baseline and candidate suite manifests:

```bash
dart run benchmark/decide_tracelite.dart \
  --tracelite-root=/path/to/tracelite \
  --baseline=build/tracelite-baseline/manifest.json \
  --candidate=build/tracelite-candidate/manifest.json \
  --policy=build/tracelite-benchmarks/prepublish/policy-calibration.json \
  --label=exp-123-no-regression
```

`decide_tracelite.dart` uses the same tracelite source pin and writes the same
`tracelite_source` manifest block as the production gate wrapper.

Defaults:

- expectation: `no_regression`
- primary peer: `resqlite`
- primary metric: `measured_elapsed_ns`
- primary scenarios: the five release-lane scenarios from the production gate
- guardrail metrics: `measured_elapsed_ns`

It writes `build/tracelite-decisions/<label>/decision.json`,
`decision.md`, `resqlite-tracelite-decision.json`, and `graph-data/`. Exit code
`0` means accepted. Rejected and inconclusive decisions preserve artifacts and
exit non-zero.

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

`run_tracelite_profile.dart` also validates the pinned tracelite checkout before
creating a region or exporting graph data.

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
