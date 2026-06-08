# Experiment 146: Lower batch packing threshold

**Date:** 2026-06-08
**Status:** Rejected
**Direction:** `parameter-encoding-and-binding`
**Benchmark Run:** Tracelite A/B experiment, `exp-146-lower-batch-pack-threshold`

## Problem

Experiments 125 and 126 justified direct text payload packing for large wide
batches. The live guard keeps the ASCII fast path narrow:

- `paramCount >= 8`
- `totalParamCount >= 8192`

The remaining question was whether that guard is too conservative. If direct
ASCII packing is cheap enough, lowering the threshold could bring the allocation
win to smaller generated-statement batches without waiting for very wide or
very large rows.

## Hypothesis

Lowering the ASCII batch-packing guard to `paramCount >= 2` and
`totalParamCount >= 64` should improve the narrow batch-insert lane, or at
least stay neutral, because it removes temporary UTF-8 list allocation from a
larger set of batch writes.

Reject if Tracelite cannot show a primary improvement on `resqlite`
`narrow-batch-insert`, if guardrails are too noisy to support the change, or if
the result merely broadens a fast path without measurable benefit.

## Approach

Created two resqlite worktrees from `origin/main` at
`423a74eda5d05c2d7fc6f0ba70fd978fb6c345d0`:

- Baseline: `/Users/dan/.codex/worktrees/resqlite-exp146-baseline`
- Candidate: `/Users/dan/.codex/worktrees/resqlite-exp146-candidate`

Candidate patch:

```diff
-const int _asciiBatchMinParamCount = 8;
-const int _asciiBatchMinTotalParamCount = 8192;
+const int _asciiBatchMinParamCount = 2;
+const int _asciiBatchMinTotalParamCount = 64;
```

Ran the integrated Tracelite A/B workflow with pinned Tracelite
`a2bf3648836fcf680d0aceccb18c2b31a2109586` and ARM64 Dart:

```text
/Users/dan/Coding/flutter_arm64/bin/cache/dart-sdk/bin/dart run \
  benchmark/run_tracelite_experiment.dart \
  --dart=/Users/dan/Coding/flutter_arm64/bin/cache/dart-sdk/bin/dart \
  --tracelite-root=/Users/dan/Coding/tracelite \
  --baseline-root=/Users/dan/.codex/worktrees/resqlite-exp146-baseline \
  --candidate-root=/Users/dan/.codex/worktrees/resqlite-exp146-candidate \
  --label=exp-146-lower-batch-pack-threshold \
  --direction=parameter-encoding-and-binding \
  --runs=3 \
  --min-repetitions=7 \
  --max-repetitions=30 \
  --out-dir=build/tracelite-experiments/exp-146-lower-batch-pack-threshold
```

Before the final run, stale multi-day Dart test processes from an unrelated
`dune_core` checkout were terminated because they were consuming significant
CPU and would have polluted local benchmark stability.

Artifacts:

- `build/tracelite-experiments/exp-146-lower-batch-pack-threshold/resqlite-tracelite-experiment.json`
- `build/tracelite-experiments/exp-146-lower-batch-pack-threshold/baseline/history.json`
- `build/tracelite-experiments/exp-146-lower-batch-pack-threshold/candidate/history.json`
- `build/tracelite-experiments/exp-146-lower-batch-pack-threshold/decision/decision.json`
- `build/tracelite-experiments/exp-146-lower-batch-pack-threshold/decision/insights.md`

## Results

The integrated wrapper completed clean baseline and candidate collection:

| step | status |
|---|---|
| baseline suite history | ok |
| candidate suite history | ok |
| decision artifact | inconclusive |

Tracelite decision policy:

| field | value |
|---|---:|
| expectation | improvement |
| primary threshold | 24.0% |
| max guardrail regression | 18.0% |
| max CV | 18.0% |

Decision comparisons:

| role | scenario | peer | metric | baseline | candidate | change | max CV | p | status | effect |
|---|---|---|---|---:|---:|---:|---:|---:|---|---|
| primary | `narrow-batch-insert` | `resqlite` | `measured_elapsed_ns` | 11.45 ms | 11.62 ms | +1.45% | 13.2% | 0.513 | neutral | inconclusive |
| guardrail | `narrow-batch-insert` | `sqlite_async` | `measured_elapsed_ns` | 14.93 ms | 12.28 ms | -17.7% | 64.9% | 0.615 | too_noisy | inconclusive |

Decision insights:

| severity | finding | detail |
|---|---|---|
| warning | Decision is inconclusive | Evidence is not strong enough for a production decision. |
| warning | Guardrails are inconclusive | One guardrail comparison needs cleaner or repeated evidence. |
| warning | Primary metric did not clear | `resqlite` changed by +1.45% with status `neutral`; 95% CI -0.81 ms..1.14 ms. |

The graph-data export validated and produced decision-level data:

| dataset | rows |
|---|---:|
| `scenario_series` | 1680 |
| `peer_summary` | 12 |
| `decision_summary` | 1 |
| `decision_comparisons` | 2 |

## Decision

Reject.

The result does not justify lowering the ASCII batch-packing threshold. The
primary resqlite lane is neutral, not an improvement, and the guardrail is too
noisy to add confidence. Since the candidate only broadens an optimization
guard, there is no correctness or maintainability reason to carry it without a
clear timing win.

Keep the current large-wide-batch guard from exp 125. Small and narrow batch
writes should stay on the generic path unless a future workload shows parameter
encoding is a material part of wall time.

## Workflow Notes

This experiment also validated the new Tracelite A/B workflow:

- The wrapper retargeted `/Users/dan/Coding/tracelite/pubspec_overrides.yaml`
  to the baseline worktree, then the candidate worktree, and restored the
  original override afterwards.
- Baseline and candidate collection run non-strictly so noisy policy
  calibration does not prevent collecting both sides. The decision step remains
  the gate that reports accepted, rejected, or inconclusive evidence.
- Suite-history graph export used `--suite-history` inputs for both sides, so
  the visualizer gets all repeated-run samples instead of a single suite
  manifest.
