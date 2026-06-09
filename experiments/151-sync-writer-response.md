# Experiment 151: Synchronous Writer Response Resolution

**Date:** 2026-06-09
**Status:** Rejected
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** Tracelite A/B experiment, `exp-151-sync-writer-response`
**Archive:** Not created; the candidate was a one-line private completer change,
and the snippet below is enough to recreate it if a future runtime or workload
changes the request-resolution trade-off.

## Problem

Experiment 147 left the largest stream-fanout bucket in writer/request
residual rather than SQLite-facing write work. On A11c overlap, SQLite was
9.4% of writer-side burst wall and invalidation was 18.8%, leaving 71.8% as
writer/request residual. Keyed-PK had the same shape, with 63.3% residual.

The updated runner instructions also warned against a standalone residual-split
profiling PR. The bounded question for this run was therefore: can a concrete
request-resolution change reduce that residual bucket without adding another
permanent counter?

## Hypothesis

`Writer._request` resolves responses through a per-request `RawReceivePort` and
an async `Completer<T>()`. Switching that completer to `Completer<T>.sync()`
should remove one response-resolution scheduling hop and make write completion
behave more like the reader completion path, which already uses synchronous
completers for hot reply handling.

This is only worth carrying if the Tracelite stream-dispatch lanes show an
end-to-end measured-elapsed improvement. Reject if the candidate merely moves
profile counters, is neutral, or makes keyed-PK / many-streams work slower.

## Approach

The candidate changed only the writer response completer:

```dart
final completer = Completer<T>.sync();
```

No temporary instrumentation was added. A focused correctness run covered
database, transaction, and stream behavior before performance measurement. A
writer-wall profile smoke checked that the candidate touched the intended
request/residual area, then the formal integrated Tracelite A/B wrapper ran
against the stream preset.

Tracelite A/B command:

```text
dart run benchmark/run_tracelite_experiment.dart \
  --dart=/usr/local/bin/dart \
  --tracelite-root=/Users/dan/.codex/worktrees/tracelite-pinned-a2bf364 \
  --baseline-root=/Users/dan/.codex/worktrees/resqlite-exp151-baseline \
  --candidate-root=/Users/dan/.codex/worktrees/resqlite-exp151-stream-scheduling \
  --label=exp-151-sync-writer-response \
  --direction=stream-rerun-dispatch \
  --runs=2 \
  --min-repetitions=5 \
  --max-repetitions=12 \
  --out-dir=build/tracelite-experiments/exp-151-sync-writer-response
```

Artifacts:

- `build/tracelite-experiments/exp-151-sync-writer-response/resqlite-tracelite-experiment.json`
- `build/tracelite-experiments/exp-151-sync-writer-response/baseline/history.json`
- `build/tracelite-experiments/exp-151-sync-writer-response/candidate/history.json`
- `build/tracelite-experiments/exp-151-sync-writer-response/decision/decision.json`
- `build/tracelite-experiments/exp-151-sync-writer-response/decision/insights.md`

## Results

The wrapper collected clean baseline and candidate histories:

| step | status |
|---|---|
| baseline suite history | ok |
| candidate suite history | ok |
| graph data export | valid |
| decision artifact | inconclusive |

Tracelite decision policy:

| field | value |
|---|---:|
| expectation | improvement |
| primary threshold | 28.5% |
| max guardrail regression | 21.5% |
| max CV | 21.5% |

Decision comparisons:

| role | scenario | peer | metric | baseline | candidate | change | max CV | p | status | effect |
|---|---|---|---|---:|---:|---:|---:|---:|---|---|
| primary | `high-cardinality-fanout` | `resqlite` | `measured_elapsed_ns` | 380 ms | 391 ms | +2.92% | 8.20% | 0.529 | neutral | inconclusive |
| primary | `keyed-pk-subscriptions` | `resqlite` | `measured_elapsed_ns` | 318 ms | 377 ms | +18.5% | 50.5% | 0.432 | too_noisy | inconclusive |
| primary | `many-streams-writer-throughput` | `resqlite` | `measured_elapsed_ns` | 587 ms | 669 ms | +14.0% | 17.1% | 0.000325 | neutral | inconclusive |
| guardrail | `keyed-pk-subscriptions` | `resqlite` | `measured_elapsed_ns` | 318 ms | 377 ms | +18.5% | 50.5% | 0.432 | too_noisy | inconclusive |

Decision insights:

| severity | finding | detail |
|---|---|---|
| warning | Decision is inconclusive | Evidence is not strong enough for a production decision. |
| warning | Guardrails are inconclusive | One guardrail comparison needs cleaner or repeated evidence. |
| warning | Noise is the next action | Keyed-PK exceeded the 21.5% CV gate. |
| warning | Primary metric did not clear | High-cardinality fanout changed +2.92% with neutral status and CI -16.6 ms..38.8 ms. |
| warning | Primary metric did not clear | Keyed-PK changed +18.5% with too-noisy status and CI -29.9 ms..148 ms. |
| warning | Primary metric did not clear | Many-streams writer throughput changed +14.0% with neutral status and CI -6.06 ms..171 ms. |

The profile smoke was also not a clean win. A first current-tree pass looked
materially worse on A11c overlap, and a warmed rerun was mixed: overlap and
disjoint moved favorably, but no-stream writer wall moved the wrong way. The
formal Tracelite result is the decision source.

## Decision

Reject.

Synchronous writer response resolution is a coherent request-scheduling
implementation attempt, but it did not clear the stream-dispatch primary gate
and trended slower on the two write-heavy lanes that matter most here:
keyed-PK subscriptions (+18.5%, too noisy) and many-streams writer throughput
(+14.0%, neutral but wrong direction).

The runtime change was removed before opening the PR. This is not a
measurement-only branch: the run consumed a concrete implementation candidate
and used existing Tracelite artifacts to reject it.

## Future Notes

- Do not retry the same `Completer<T>.sync()` writer response-resolution change
  unless a Dart runtime change or a new workload changes the scheduling cost
  model.
- Writer/request residual remains the largest named bucket, but a future run
  needs a more structural candidate than making the existing response future
  synchronous.
- The updated runner instructions affected this run directly: instead of
  opening another residual-split profiling PR, the branch attempted the narrow
  request-resolution change, measured it with the integrated stream A/B, then
  removed the rejected code.

## Validation

- `dart pub get` in both candidate and baseline worktrees.
- `dart test test/database_test.dart test/transaction_test.dart test/stream_test.dart test/stream_invalidation_coalescing_test.dart test/stream_dependency_shapes_test.dart`
- `dart run -DRESQLITE_PROFILE=true benchmark/profile/writer_sqlite_wall_audit.dart` on baseline and candidate smoke passes.
- `dart run benchmark/run_tracelite_experiment.dart --dart=/usr/local/bin/dart --tracelite-root=/Users/dan/.codex/worktrees/tracelite-pinned-a2bf364 --baseline-root=/Users/dan/.codex/worktrees/resqlite-exp151-baseline --candidate-root=/Users/dan/.codex/worktrees/resqlite-exp151-stream-scheduling --label=exp-151-sync-writer-response --direction=stream-rerun-dispatch --runs=2 --min-repetitions=5 --max-repetitions=12 --out-dir=build/tracelite-experiments/exp-151-sync-writer-response`
