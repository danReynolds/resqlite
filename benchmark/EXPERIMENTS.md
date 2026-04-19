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
  executeBatch:
    p50      110μs →    106μs      -4μs  (-3.6%)
    p90      178μs →    131μs     -47μs  (-26.4%)
    p99      607μs →    335μs    -272μs  (-44.8%)
    max     4034μs →    800μs   -3234μs  (-80.2%)
    work      99μs →     95μs      -4μs  (-4.0%)
```

Reading this:

- **p50 barely moved** (−3.6%). The median case is unaffected.
- **p99 dropped 44.8%**. The tail shrank dramatically. Something that
  was happening ~1% of the time — a WAL checkpoint, a GC pause, a
  scheduler stall — is happening less often or being resolved faster
  in the candidate build.
- **max dropped 80%**. The absolute worst case got much better.
- **work dropped 4μs**. The dispatch-subtracted time (i.e. actual
  per-batch SQL work) is 4μs faster at the median.

Two things to keep in mind when interpreting:

1. **p99 and max on single runs are noisy.** Even with 1k samples, a
   single GC pause landing in one run and not the other can move p99
   10–20%. Run the A/B multiple times if the p99 story matters to
   your conclusion. Exp 083 used 5 runs per variant and took medians
   of percentiles across runs.
2. **Compare work medians, not total medians, on dispatch-hot
   workloads.** Point queries are ~100% dispatch-bound — a "+1μs total"
   delta there could be pure dispatch-floor drift between runs, not
   anything your change did. The `work` column subtracts that.

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
- [`benchmark/profile/profiled_database.dart`](./profile/profiled_database.dart)
  — the per-call timing wrapper
- [`benchmark/profile/dispatch_budget.dart`](./profile/dispatch_budget.dart)
  — the original Phase-1 harness that `run_profile.dart` is built on
- [`experiments/080-dispatch-budget.md`](../experiments/080-dispatch-budget.md)
  — the findings that motivated this infrastructure
- [`README.md`](./README.md) § Release Mode vs Profile Mode — the
  dual-purpose framing
