# Experiment 142: Single-row text parameter direct encoding

**Date:** 2026-06-08
**Status:** Rejected
**Direction:** `parameter-encoding-and-binding`
**Benchmark Run:** Tracelite A/B retest, `exp-142-tracelite-single-row-text`

## Problem

PR #130 proposed applying the exp 125 / exp 126 direct text payload packing
pattern to the single-row `allocateParams` path. That path is used by
parameterized reads and single-row writes that do not go through the wide-batch
matrix encoder.

The old focused harness showed strong local wins on small string-heavy shapes,
but it was produced by the pre-Tracelite experiment loop. The reassessment
question was whether the change still looked merge-worthy when retested against
current `origin/main` with the integrated Tracelite baseline/candidate workflow
and peer guardrails.

## Hypothesis

Removing the temporary `List<Uint8List?>` plus per-string `Uint8List` allocation
from `allocateParams` should improve standardized workloads that include
single-row string parameter binding, or at least stay neutral.

Accept only if Tracelite clears the primary `resqlite` improvement gate on the
closest current lanes and `sqlite_async` guardrails remain clean. Reject or
defer if the primary lanes are neutral/noisy or trend slower, because the change
adds more custom string-encoding logic to a hot binding path.

## Approach

Created two resqlite worktrees from current `origin/main` at
`1979ec3c4069ffa960df465971b23e5e53323768`:

- Baseline: `/Users/dan/.codex/worktrees/retest-exp142-baseline`
- Candidate: `/Users/dan/.codex/worktrees/retest-exp142-candidate`

The candidate reapplied only the code and focused harness from PR #130:

- `lib/src/native/resqlite_bindings.dart`
- `benchmark/experiments/single_row_param_encoding.dart`

Candidate patch shape:

- pass 1 measures string UTF-8 byte length without allocating temporary encoded
  byte lists,
- ASCII-only parameter rows use a direct `codeUnitAt` copy into the existing
  native parameter buffer,
- mixed/non-ASCII rows use the shared `_writeUtf8` encoder from the batch path,
- int, double, blob, null, wide-batch, narrow-batch, and public API behavior are
  unchanged.

Before the A/B run, both retest worktrees resolved dependencies with ARM64 Dart.
The candidate then passed:

```text
/Users/dan/Coding/flutter_arm64/bin/cache/dart-sdk/bin/dart analyze \
  lib/src/native/resqlite_bindings.dart \
  benchmark/experiments/single_row_param_encoding.dart

/Users/dan/Coding/flutter_arm64/bin/cache/dart-sdk/bin/dart test \
  test/database_test.dart test/transaction_test.dart
```

Ran the integrated Tracelite A/B workflow with pinned Tracelite
`a2bf3648836fcf680d0aceccb18c2b31a2109586` and ARM64 Dart:

```text
/Users/dan/Coding/flutter_arm64/bin/cache/dart-sdk/bin/dart run \
  benchmark/run_tracelite_experiment.dart \
  --dart=/Users/dan/Coding/flutter_arm64/bin/cache/dart-sdk/bin/dart \
  --tracelite-root=/Users/dan/Coding/tracelite \
  --baseline-root=/Users/dan/.codex/worktrees/retest-exp142-baseline \
  --candidate-root=/Users/dan/.codex/worktrees/retest-exp142-candidate \
  --label=exp-142-tracelite-single-row-text \
  --direction=parameter-encoding-and-binding \
  --suite-scenarios=chat-sim,narrow-batch-insert \
  --policy-scenarios=chat-sim,narrow-batch-insert \
  --interfaces=sqlite_async,resqlite \
  --guardrail-peers=sqlite_async \
  --runs=2 \
  --min-repetitions=5 \
  --max-repetitions=12 \
  --out-dir=build/tracelite-experiments/exp-142-tracelite-single-row-text
```

Artifacts:

- `build/tracelite-experiments/exp-142-tracelite-single-row-text/resqlite-tracelite-experiment.json`
- `build/tracelite-experiments/exp-142-tracelite-single-row-text/baseline/history.json`
- `build/tracelite-experiments/exp-142-tracelite-single-row-text/candidate/history.json`
- `build/tracelite-experiments/exp-142-tracelite-single-row-text/decision/decision.json`
- `build/tracelite-experiments/exp-142-tracelite-single-row-text/decision/insights.md`

## Results

The wrapper collected both sides and wrote the decision artifacts:

| step | status |
|---|---|
| baseline suite history | ok |
| candidate suite history | ok |
| decision artifact | inconclusive |

Tracelite decision policy:

| field | value |
|---|---:|
| expectation | improvement |
| primary threshold | 38.0% |
| max guardrail regression | 28.5% |
| max CV | 28.5% |

Primary comparisons:

| role | scenario | peer | metric | baseline | candidate | change | max CV | p | status | effect |
|---|---|---|---|---:|---:|---:|---:|---:|---|---|
| primary | `chat-sim` | `resqlite` | `measured_elapsed_ns` | 15.7 ms | 16.7 ms | +6.86% | 24.2% | 0.716 | neutral | inconclusive |
| primary | `narrow-batch-insert` | `resqlite` | `measured_elapsed_ns` | 11.8 ms | 13.7 ms | +16.4% | 27.5% | 0.057 | neutral | inconclusive |

Guardrail comparisons:

| role | scenario | peer | metric | baseline | candidate | change | max CV | p | status | effect |
|---|---|---|---|---:|---:|---:|---:|---:|---|---|
| guardrail | `chat-sim` | `sqlite_async` | `measured_elapsed_ns` | 27.4 ms | 27.8 ms | +1.41% | 20.3% | 0.460 | neutral | pass |
| guardrail | `narrow-batch-insert` | `sqlite_async` | `measured_elapsed_ns` | 12.1 ms | 11.6 ms | -3.68% | 15.3% | 0.800 | neutral | pass |

Decision insights:

| severity | finding | detail |
|---|---|---|
| warning | Decision is inconclusive | Evidence is not strong enough for a production decision. |
| warning | Primary metric did not clear | `chat-sim` changed +6.86% with max CV 24.2%, p=0.716, 95% delta CI -1.02 ms..3.17 ms. |
| warning | Primary metric did not clear | `narrow-batch-insert` changed +16.4% with max CV 27.5%, p=0.057, 95% delta CI -575 us..4.44 ms. |

The baseline and candidate `explain` artifacts also warned that these short
lanes are partly harness-dominated. That limits how much we can infer about the
exact micro-cost, but it does not create positive evidence for carrying more
custom binding code: the closest standardized lanes did not improve and both
resqlite primary rows moved slower.

The decision graph-data export validated and produced:

| dataset | rows |
|---|---:|
| `scenario_series` | 2240 |
| `peer_summary` | 16 |
| `decision_summary` | 1 |
| `decision_comparisons` | 4 |

## Decision

Reject. Do not carry the `allocateParams` direct text encoding code from PR
#130.

The old focused harness remains a useful clue that single-row text parameter
encoding can be made faster in isolation, but the current Tracelite retest did
not convert that clue into production evidence. On the closest available
standard lanes, the candidate was neutral/inconclusive and directionally slower:
+6.86% on `chat-sim` and +16.4% on `narrow-batch-insert`.

This reinforces exp 146's parameter-encoding lesson: small and narrow binding
changes should stay on the generic path unless a current workload shows
parameter encoding is material and a Tracelite A/B decision clears the primary
gate. If a future app profile shows high-frequency single-row string parameter
binding as a real bottleneck, add a Tracelite scenario or profile lane that
directly covers that shape before retrying this implementation.

## Future Notes

The current Tracelite scenario set does not perfectly isolate the original
focused harness shape from PR #130. That is a reason to avoid overclaiming a
runtime regression, not a reason to merge the code. A future retry should first
add or select a scenario where single-row string parameter encoding is a
material fraction of measured time, then rerun the integrated A/B workflow.

## Validation

- `/Users/dan/Coding/flutter_arm64/bin/cache/dart-sdk/bin/dart pub get` in
  both retest worktrees
- `/Users/dan/Coding/flutter_arm64/bin/cache/dart-sdk/bin/dart analyze lib/src/native/resqlite_bindings.dart benchmark/experiments/single_row_param_encoding.dart`
- `/Users/dan/Coding/flutter_arm64/bin/cache/dart-sdk/bin/dart test test/database_test.dart test/transaction_test.dart`
- `/Users/dan/Coding/flutter_arm64/bin/cache/dart-sdk/bin/dart run benchmark/run_tracelite_experiment.dart ...`
