# resqlite Benchmarks

This folder serves **three distinct purposes**, each with its own
entry point. Choosing the right one matters because the production
code path you measure differs between them.

| Purpose | Entry point | resqlite code instrumented? |
|---|---|---|
| **Peer comparison / public dashboard** | [`run_release.dart`](./run_release.dart) | **No** — pristine, zero diagnostic overhead |
| **Trace-backed production gate** | [`run_tracelite.dart`](./run_tracelite.dart) | **No for peer timing; yes for opt-in trace hooks** |
| **Trace-backed baseline/candidate decision** | [`decide_tracelite.dart`](./decide_tracelite.dart) | **No for peer timing; yes for opt-in trace hooks** |
| **Trace-backed experiment profile** | [`profile/run_tracelite_profile.dart`](./profile/run_tracelite_profile.dart) | **Yes** — Timeline markers, per-call profiling, tracelite spans, workload summaries, insights, graph data |
| **Legacy profile JSON compatibility** | [`run_profile.dart`](./run_profile.dart) | **Yes** — Timeline markers + per-call profiling only |
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

If you're running an experiment on a branch and want trace-backed local
diagnostics, use `profile/run_tracelite_profile.dart`. It runs the profile
workloads with `RESQLITE_PROFILE` and `RESQLITE_TRACELITE`, then makes
tracelite workload summaries, insights, graph data, and parity evidence from the
same run. `run_profile.dart` remains available as the direct legacy JSON
harness when an old experiment note or diff tool specifically needs that shape.

See [EXPERIMENTS.md](./EXPERIMENTS.md) for the experiment-mode
workflow and A/B tabulation tools.

## Documentation

- [`METHODOLOGY.md`](./METHODOLOGY.md) — measurement rules, statistical approach, fairness protocol, peer version policy, Definition of Done for new workloads
- [`SCOPE.md`](./SCOPE.md) — exact peer versions, hardware tested, known gaps, what we test and what we don't
- [`AUDIT.md`](./AUDIT.md) — how benchmark results propagate from Dart code to the public dashboard (parsers, generators, chart builders)
- [`HARDWARE_RESULTS.md`](./HARDWARE_RESULTS.md) — device registry pointing at canonical result files per device
- [`EXPERIMENTS.md`](./EXPERIMENTS.md) — experiment-mode workflow using tracelite profile artifacts, with legacy JSON compatibility where needed

## Release Mode (peer comparison)

Pristine code, no diagnostic overhead. Feeds the public dashboard.

From this package root:

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

Experiment-only scripts live under [`benchmark/experiments`](./experiments) and
are intentionally not part of the default suite.

Recommended workflow for performance decisions:

1. Pick a pinned baseline with `--compare-to=...`
2. Run at least `--repeat=5`
3. Trust stable cases first; treat `Repeat Stability: noisy` rows as advisory

## Tracelite Presets

Trace-backed release benchmarking uses the pinned tracelite checkout as the
runner and artifact owner:

```bash
git clone https://github.com/danReynolds/tracelite /path/to/tracelite
git -C /path/to/tracelite checkout resqlite-profiling-gate-2026-06-02-r9
```

```bash
dart run benchmark/run_tracelite.dart \
  --preset=production \
  --tracelite-root=/path/to/tracelite \
  --resqlite-root="$PWD" \
  --label=prepublish-YYYY-MM-DD \
  --graph-data-dir=docs/benchmarks/data/tracelite/latest
```

`run_tracelite.dart` has three presets. Every preset records
`tracelite_source`, `resqlite_source`, the resolved Tracelite dependency
binding, graph data, and Tracelite insight artifacts that explain trace health,
noise, and bottleneck signals. The resqlite production wrapper defaults to
Tracelite's direct `script` runner because the long-lived `worker` runner is
not yet accepted for multi-scenario reactive resqlite suites. Explicit
`--runner=worker` is still useful for targeted trace investigations and records
worker preflight/native-asset metadata, but it is not the publish gate default.
Explicit CLI flags override preset defaults. The wrapper also builds
Tracelite's `build/libsqlite_traced.dylib` SQLite shim for
fresh macOS checkouts, then reuses it while it is newer than the shim sources,
so CI does not depend on a pre-warmed Tracelite build directory and local runs
do not repeatedly pay toolchain startup.
After dependency resolution, the wrapper launches `suite-history` with
`dart run bin/tracelite.dart ...` so Dart regenerates native-assets metadata for
the configured SDK architecture before peer runs start. Graph export,
validation, and explanation then invoke Tracelite as `dart bin/tracelite.dart
...` from the source checkout to avoid paying native-assets startup again.

| Preset | Use when | Default shape |
|---|---|---|
| `ci` | Routine PR smoke and trace-health checks | Tracelite `ci` profile, `runs=1`, `interfaces=resqlite`, tiny `narrow-batch-insert`, `point-select`, `keyed-pk-subscriptions`, and `sqlite-diagnostics` scenarios, 3 minute suite-run timeout |
| `experiment` | Collect focused baseline/candidate artifacts for a perf change | Tracelite `production` profile, `runs=3`, `interfaces=sqlite_async,resqlite`, `feed-paging`, `chat-sim`, and `keyed-pk-subscriptions`, 10 minute suite-run timeout |
| `production` | Pre-publish or major perf-change gate | Tracelite `production` profile, `warmup-runs=1`, `runs=5`, `interfaces=resqlite`, release-policy workloads plus `sqlite-diagnostics` trace-health coverage, 20 minute suite-run timeout |

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
`f56ecb8d4f2df5bdb3646f2cf3439450fd64272d`
(`resqlite-profiling-gate-2026-06-02-r9`). The wrapper records
`tracelite_source` in its manifest and fails if the checkout is not at that
revision or is dirty. It also records `resqlite_source` and verifies that
Tracelite's resolved `resqlite` package points at the checkout under test. If
`/path/to/tracelite/pubspec_overrides.yaml` is missing, the wrapper creates an
ignored override for `--resqlite-root`; if an existing override points anywhere
else, the gate fails before running the suite. Use
`--allow-unpinned-tracelite` or `--allow-dirty-tracelite` only for local
tracelite development.

The wrapper records the Dart executable and architecture in its manifest. On
Apple Silicon, prefer an arm64 Dart SDK via `--dart=/path/to/arm64/dart`; x64
Dart under Rosetta can make traced native-assets builds much slower and less
useful as a routine development signal.

The `production` preset first runs one unrecorded
`tracelite suite --profile=production` warmup, then runs
`tracelite suite-history --profile=production --runs=5`. The warmup stabilizes
native-assets, child-process, and reactive cold-start effects before the
recorded history is used for strict policy calibration. The recorded history
repeats only the resqlite release-policy surface needed to calibrate
thresholds:

- metric: `measured_elapsed_ns`
- peer: `resqlite`
- interface: `resqlite`
- production suite scenarios: high-cardinality fanout, many-streams writer
  throughput, and sqlite diagnostics
- strict elapsed-time policy scenarios: high-cardinality fanout and
  many-streams writer throughput
- repetition bounds: `--min-repetitions=7 --max-repetitions=30`
- noise target: `--target-rse-percent=10`
- robust within-run noise percentile: `--within-run-noise-percentile=0.75`
- threshold gate: `--threshold-floor-percent=5 --threshold-ceiling-percent=50`
- guardrail gate: `--guardrail-floor-percent=3`
- noise gate: `--noise-gate-floor-percent=5 --noise-gate-ceiling-percent=50
  --noise-gate-multiplier=1.5`
- outlier gates: `--max-outlier-percent=15 --max-run-outlier-percent=20`

It writes `build/tracelite-benchmarks/<label>/history.json`,
`policy-calibration.json`, `policy-calibration.md`, `insights.json`,
`insights.md`, and `graph-data/`. The dashboard can read
`docs/benchmarks/data/tracelite/latest/index.json` when the graph-data output is
published there.

Use the default strict mode for CI and publish gates. `--no-strict` is only for
local exploratory runs where the requested history is intentionally too small to
pass the repetition and noise gates. Suite failures and trace diagnostics still
make the wrapper manifest invalid; graph data is exported when possible so the
failed run can be inspected. If a failed suite produced no compare artifacts,
graph export is skipped with an explicit wrapper step instead of masking the
suite failure with a secondary export crash. Wrapper steps also bound child
startup and execution, and the shim build has a short dedicated timeout, so
native-assets or toolchain stalls are recorded as failed manifest steps instead
of leaving the gate unbounded.

`narrow-batch-insert`, `point-select`, `feed-paging`, `sync-burst`,
`chat-sim`, `large-working-set`, and `keyed-pk-subscriptions` are diagnostic
workloads. Routine CI samples a smaller diagnostic set with `--preset=ci`.
Use explicit `--interfaces=sqlite3,drift,sqlite_async,resqlite` and
`--suite-scenarios=...` overrides when a release investigation needs peer or
full diagnostic coverage; do not repeat the full matrix five times during
normal development.

Current calibration state: the r8 pin includes bounded `suite-history`
execution, suite-run timeout recording, forwarding of the policy
`--min-repetitions` floor into each suite run, and `dart run` suite-history
launches so Tracelite regenerates native-assets metadata for the configured
Dart SDK architecture. The r9 pin adds the long-lived worker runner for
native-assets-heavy peers, worker preflight trace validation, and filtered
native-asset/runtime-library metadata. The wrapper keeps `--runner=script` as
the default because local r9 validation found that a multi-scenario worker run
can still leave unmatched reactive trace events in
`keyed-pk-subscriptions`. The wrapper also reuses a fresh SQLite shim, rebuilds it
when the cached Mach-O architecture does not match the Dart VM, and runs the
compiler natively on Apple Silicon while still producing the requested target
architecture.

Latest full production evidence is still the pre-worker r8 run:
`production-pin-r8-resqlite-policy-2026-06-02-r3`
passed with Tracelite source
`4b4165693c752c8e73da3237c117fa5699c0bb79`, resqlite source
`a830f3a6ec2a229ecd09a0685664633f71da4322`, 5/5 suite-history runs `ok`,
policy calibration `ready`, graph-data export and validation `ok`, and
explain completed. The suite-history phase took about 15.2 minutes locally
under the x64 Dart SDK; the full wrapper run took about 15.7 minutes excluding
the outer `dart run` startup. The r9 script-runner pin must replace this
evidence before final pre-publish signoff.

Current worker evidence: local Tracelite r9 worker checks passed
`narrow-batch-insert` for `resqlite` and `feed-paging` for
`sqlite_async,resqlite`, with preflight metadata, native-asset/runtime-library
metadata, graphable spans, and trace diagnostics `0/0/0`. The same runner is
not yet clean for the full reactive CI scenario sequence, so keep worker as an
explicit investigation mode.

Current r9 smoke evidence:
`ci-pin-r9-script-arm64-final-2026-06-02` passed with the arm64 Dart SDK,
source pinning, dependency binding, script-mode `suite-history`, policy
calibration `ready`, graph-data export and validation `ok`, explain completed,
and manifest `dart_runtime.dart_matches_host_architecture=true`.

Historical artifacts also produced an accepted routine no-regression decision:

```bash
dart run benchmark/decide_tracelite.dart \
  --tracelite-root=/path/to/tracelite \
  --baseline=build/tracelite-benchmarks/sole-gate-2026-05-31-resqlite-pinned-source/run-001-20260531T154622Z/manifest.json \
  --candidate=build/tracelite-benchmarks/sole-gate-2026-05-31-resqlite-pinned-source/run-005-20260531T155915Z/manifest.json \
  --policy=build/tracelite-benchmarks/sole-gate-2026-05-31-resqlite-pinned-source/policy-calibration.json \
  --label=sole-gate-2026-05-31-resqlite-pinned-no-regression
```

That decision passed trace health, primary, and guardrail gates and exported
validated graph data with suite and decision rows. Its wrapper manifest also
recorded `tracelite_source.source_ok=true` and `revision_matches_pin=true`.

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
- primary scenarios: the production gate's release-policy scenarios
- guardrail metrics: `measured_elapsed_ns`

It writes `build/tracelite-decisions/<label>/decision.json`,
`decision.md`, `insights.json`, `insights.md`,
`resqlite-tracelite-decision.json`, and `graph-data/`. Exit code `0` means
accepted. Rejected and inconclusive decisions preserve artifacts and exit
non-zero.

## Profile Mode (experiment vs baseline)

See [`EXPERIMENTS.md`](./EXPERIMENTS.md) for the full workflow. The preferred
profile path is tracelite-backed:

```bash
dart run benchmark/profile/run_tracelite_profile.dart \
  --tracelite-root=/path/to/tracelite \
  --label=exp-N
```

`run_tracelite_profile.dart` validates the pinned tracelite checkout before
creating a region or exporting graph data. It writes
`build/tracelite-profile/exp-N/` with:

- primary tracelite artifacts: `workload-summary.json`,
  `workload-summary.md`, `insights.json`, `insights.md`, `graph-data/`, and
  the raw `.tlt-region`;
- compatibility/parity artifacts: the legacy `profile.json` and
  `parity-diff.txt`.

Use direct `run_profile.dart` only when you intentionally need the old standalone
JSON A/B flow without tracelite artifacts.

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

From this package root:

```bash
dart run benchmark/head_to_head_worker.dart \
  --out=/tmp/resqlite_main_h2h.json
```

### 2. Run verifier core cases

From a checkout of `sqlite_reactive_verifier`:

```bash
flutter pub run bin/sqlite_reactive_benchmark.dart \
  --libraries=sqlite_reactive,sqlite_async,sqlite3 \
  --benchmarks=open_only,cold_open,single_row_crud,batch_write_transaction,read_under_write,large_result_read,large_result_read_large,repeated_point_query \
  --db-root=/tmp/resqlite_main_rebench \
  --out-json=/tmp/resqlite_main_rebench_core.json
```

### 3. Run verifier reactive cases

From a checkout of `sqlite_reactive_verifier`:

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

- [`2026-04-08-codex-main-four-way.md`](./results/2026-04-08-codex-main-four-way.md)
