# Experiment 178: Missing-benchmark-run declaration guard

**Date:** 2026-06-16
**Status:** In Review
**Direction:** `measurement-system`
**Benchmark Run:** none (CI guardrail / methodology tooling; no runtime code, structural counter evidence below)

## Problem

The resqlite-experiment contract ties every chartable experiment to a benchmark
result file: `docs/experiments/history.json` is built by mapping each
experiment to a `benchmark/results/<ISO-timestamp>-<label>.md` run, and a chart
point appears only when the experiment doc's `**Date:**` matches at least one
run's filename-timestamp date. The skill spells out the failure mode directly:

> Drop the result file and the experiment is invisible on the chart (though it
> still shows in the text list).

`generate_history.dart` already guards the *wrong-file* version of this: when an
**Accepted** experiment's chart slot points at a baseline-shaped run while a
candidate-shaped run also exists for the date,
`_assertAcceptedExperimentsLinkToCandidates` fails the build (the exp-109 chart
mixup). And the repo has the intended **opt-out** signal for experiments that
genuinely have no release run — a `**Benchmark Run:**` header reading `none`
/ `n/a` / `not applicable` / `tracelite`, recognised by
`_skipsReleaseBenchmarkRunMapping` (Tracelite A/B and focused-harness
experiments use it: exp 149, 169, 174, 177).

What is *not* guarded is the most common silent case: a chartable experiment
whose linker found **no run at all** and which **never declared** that absence.
That is exactly what happens when a runner forgets to commit the result file, or
gives it a date that does not match the doc's `**Date:**`. The experiment then
drops off the chart with no error anywhere in CI — indistinguishable from a
deliberate "no release run".

### Structural evidence the gap is live

Running the generator on current `main` and tallying experiments whose linker
produced a `null` benchmark run, by status:

| Status     | null-run count | declare `**Benchmark Run:**`? |
|------------|---------------:|-------------------------------|
| accepted   | 7              | 0 of 7                        |
| in_review  | 16             | 5 of 16 (121, 143, 147, 149, 169 — plus 174/177 focused/none) |
| rejected   | 25             | (out of scope — see below)    |

Of the 23 chartable (accepted + in_review) experiments with no linked run, only
~5 declare the opt-out header. The other ~17 are silently unmapped. Several
predate the per-experiment-result-file convention (003–038), but several recent
ones do not (116, 118, 119, 125, 126, 136, 161, 172) — they were measured with
Tracelite or focused harnesses and simply never declared it. A forgotten result
file today produces the identical `null` with no signal that anything is wrong.

## Hypothesis

The "no run AND no declaration" case is a small, deterministic, structural rule.
Encoding it as a build-time guard — alongside the existing
`_assertAcceptedExperimentsLinkToCandidates` — turns the silent
chart-invisibility failure into a loud CI error for new work, without any
runtime behavior change and without depending on noisy wall-time numbers.

## Approach

- `benchmark/generate_history.dart`:
  - `_attachBenchmarkRunMappings` now **returns** the set of experiment ids that
    opted out via `**Benchmark Run:**` (it already collected them into
    `skipRunMappingIds`; previously the set was discarded after mapping).
  - New pure detector `findUndeclaredMissingRunExperiments(experiments,
    optOuts, {cutoff})`: returns one issue line per **accepted/in-review**
    experiment whose number is `>= cutoff`, whose linker found no run, and which
    is not in the opt-out set. Pure + parameterised so it is unit-testable
    without the `exit(1)` side effect.
  - New `_assertNewExperimentsLinkOrDeclareRun` wrapper prints the issues and
    `exit(1)`s, mirroring the existing baseline-link assertion. Wired into
    `buildHistoryData` right after `_assertAcceptedExperimentsLinkToCandidates`,
    so it runs in both `generate_history.dart` and the CI
    `check_generated_data.dart` job.
  - Cutoff `_benchmarkRunDeclarationCutoff = 178`: experiments below it are
    grandfathered (same pattern as `signals.json`'s
    `experimentEntriesRequiredFrom: 110`), so no retroactive edits to ~17 older
    docs are required. The cutoff is documented to bump only alongside a
    backfill pass.
  - Scoped to **accepted + in_review** (the statuses the chart plots). Rejected
    experiments commonly and legitimately carry no release run, so they are not
    in scope.

- `test/benchmark_pipeline_test.dart`: a `missing-run-without-declaration guard`
  group with six tests — fires on a `>= cutoff` chartable experiment with no run
  and no opt-out; stays silent when the opt-out header is declared, when a run
  is linked, when below cutoff, and for rejected experiments; plus a regression
  anchor that runs the real `experiments/` tree through the detector and asserts
  it stays clean at the shipped cutoff.

This is methodology tooling in the class of exp 161 / 169 / 177: it changes no
runtime code (`lib/`, `native/`, `hook/` untouched) and is not a
measurement-that-unlocks-an-implementation, so the paired-run carry rule does
not apply — the deliverable is the guard itself.

## Results

Structural / behavioral evidence (machine load is irrelevant — no wall-time
claim):

| Check                                                   | Result |
|---------------------------------------------------------|--------|
| Guard fires on synthetic missing-run exp `>= 178`       | yes (1 issue) |
| Guard silent when `**Benchmark Run:**` opt-out declared | yes |
| Guard silent when a run is linked                       | yes |
| Guard silent below cutoff (177, 116)                    | yes |
| Guard silent for rejected experiments                   | yes |
| Live `experiments/` tree at cutoff 178                  | clean (no false positive) |
| `dart run benchmark/generate_history.dart`              | `history.json is current` (unchanged) |
| `dart run benchmark/check_generated_data.dart`          | up to date |
| `dart run benchmark/check_experiment_signals.dart`      | valid |
| `dart test test/benchmark_pipeline_test.dart`           | 14/14 pass |

The generated `history.json` is byte-for-byte unchanged: the guard adds a check,
not a field, and is a no-op on the current tree (no chartable experiment `>= 178`
exists yet, and all pre-178 experiments are grandfathered).

## Decision

**Accepted (In Review).** A bounded, no-runtime-code CI guardrail that converts
a documented silent failure (forgotten result file / date mismatch →
invisible chart point, no error) into a loud build failure for new experiments,
reusing the repo's existing `**Benchmark Run:**` opt-out signal as the escape
hatch. Would reopen / extend if: a backfill pass annotates the ~17 pre-178
silently-unmapped chartable experiments (then the cutoff can drop toward the
start of the result-file convention), or if rejected experiments later need
chart coverage (then widen the status scope).

## Future Notes

- The cutoff is the only knob. To pull more history under the guard, annotate
  the older unmapped docs with `**Benchmark Run:**` (or commit their missing
  result files) and lower `_benchmarkRunDeclarationCutoff` in the same change.
- The detector is deliberately status-scoped to accepted/in_review. If the
  experiments page ever charts rejected experiments that ship a result file,
  revisit the scope rather than the cutoff.
