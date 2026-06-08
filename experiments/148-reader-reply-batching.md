# Experiment 148: Reader reply batching

**Date:** 2026-06-08
**Status:** Rejected
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** Tracelite A/B experiment, `exp-148-reader-reply-batching`

## Problem

Experiment 136 made reader-completion churn look like the next bounded stream
implementation target. On A11c overlap, the main-isolate reader worker port
handler chain accounted for 28.57% of total wall (burst + drain), at about
18 us per callback across 4,228 callbacks per burst. Subscriber fanout was
less than 1% of that chain, so the plausible target was not `StreamEntry.emit`;
it was the repeated reader reply / Future resolution / `_requery` continuation
for streams that usually short-circuit as unchanged.

The question for this run was whether collapsing multiple stream re-query
replies into one reader-worker response would turn that profile signal into an
end-to-end win on the stream rerun dispatch suite.

## Hypothesis

Batching stream re-query work inside a reader worker should reduce the number
of main-isolate completion handlers when many dirty streams hash as unchanged.
That should improve A11c overlap or many-stream writer throughput, or at least
stay neutral on keyed-PK subscriptions.

Reject if the candidate only improves the profile counter but fails to clear
the Tracelite primary gate, or if keyed-PK / disjoint-shaped work regresses.

## Approach

Created two resqlite worktrees from `origin/main` at
`8c783e787485eaace3a77612aaab2f9528c53b39`:

- Baseline: `/Users/dan/.codex/worktrees/resqlite-exp148-baseline`
- Candidate: `/Users/dan/.codex/worktrees/resqlite-exp148-reader-reply-batching`

Candidate commit:

- `b7e15acfb1f2bcf2cbdee3a069ad6462a250c9d3`

Candidate patch:

- added `SelectIfChangedBatchRequest` / `SelectIfChangedBatchResult` to the
  reader worker protocol
- added `ReaderPool.selectIfChangedBatch(...)`
- changed `StreamEngine._flushQueue()` to admit up to four bounded chunks of
  eight stream entries, preserving the single-entry path for unbatched work
- added `_requeryBatch(...)`, keeping the existing dirty-while-in-flight
  requeue behavior and per-entry error propagation

Before running the formal suite, a profile smoke compared exp 136's completion
counter harness on baseline vs candidate:

| workload | version | total_ms | completion_us | completion_count | completion_us / total |
|---|---|---:|---:|---:|---:|
| A11c overlap | baseline | 336.40 | 109,562 | 4,527 | 32.57% |
| A11c overlap | candidate | 288.30 | 55,649 | 1,425 | 19.30% |
| keyed PK subscriptions | baseline | 450.55 | 17,919 | 1,171 | 3.98% |
| keyed PK subscriptions | candidate | 446.73 | 15,708 | 715 | 3.52% |

That confirmed the implementation changed the intended mechanism, so the full
Tracelite A/B run was worth doing.

Ran the integrated Tracelite workflow with pinned Tracelite
`a2bf3648836fcf680d0aceccb18c2b31a2109586`:

```text
dart run benchmark/run_tracelite_experiment.dart \
  --dart=/usr/local/bin/dart \
  --tracelite-root=/Users/dan/Coding/tracelite \
  --baseline-root=/Users/dan/.codex/worktrees/resqlite-exp148-baseline \
  --candidate-root=/Users/dan/.codex/worktrees/resqlite-exp148-reader-reply-batching \
  --label=exp-148-reader-reply-batching \
  --direction=stream-rerun-dispatch \
  --runs=2 \
  --min-repetitions=5 \
  --max-repetitions=12 \
  --out-dir=build/tracelite-experiments/exp-148-reader-reply-batching
```

Artifacts:

- `build/tracelite-experiments/exp-148-reader-reply-batching/resqlite-tracelite-experiment.json`
- `build/tracelite-experiments/exp-148-reader-reply-batching/baseline/history.json`
- `build/tracelite-experiments/exp-148-reader-reply-batching/candidate/history.json`
- `build/tracelite-experiments/exp-148-reader-reply-batching/decision/decision.json`
- `build/tracelite-experiments/exp-148-reader-reply-batching/decision/insights.md`

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
| primary threshold | 28.0% |
| max guardrail regression | 21.0% |
| max CV | 21.0% |

Decision comparisons:

| role | scenario | peer | metric | baseline | candidate | change | max CV | p | status | effect |
|---|---|---|---|---:|---:|---:|---:|---:|---|---|
| primary | `high-cardinality-fanout` | `resqlite` | `measured_elapsed_ns` | 368 ms | 387 ms | +5.18% | 10.1% | 0.315 | neutral | inconclusive |
| primary | `keyed-pk-subscriptions` | `resqlite` | `measured_elapsed_ns` | 301 ms | 341 ms | +13.5% | 13.5% | 0.000694 | neutral | inconclusive |
| primary | `many-streams-writer-throughput` | `resqlite` | `measured_elapsed_ns` | 592 ms | 611 ms | +3.28% | 5.14% | 0.165 | neutral | inconclusive |

Decision insights:

| severity | finding | detail |
|---|---|---|
| warning | Decision is inconclusive | Evidence is not strong enough for a production decision. |
| warning | Primary metric did not clear | `high-cardinality-fanout` changed by +5.18% with neutral status; 95% CI -10.97 ms..49.09 ms. |
| warning | Primary metric did not clear | `keyed-pk-subscriptions` changed by +13.5% with neutral status; 95% CI 13.87 ms..67.34 ms. |
| warning | Primary metric did not clear | `many-streams-writer-throughput` changed by +3.28% with neutral status; 95% CI -7.66 ms..46.53 ms. |

The decision step exited 65 because `--expect=improvement` was not met. The
artifacts were still preserved and are the source of this writeup.

## Decision

Reject.

The mechanism worked, but the product-level result did not. The candidate
reduced completion callback count and completion counter wall in the profile
smoke, yet the formal Tracelite suite did not show a measured-elapsed
improvement. The keyed-PK subscription lane was slower by 13.5% with a
positive confidence interval, even though it stayed inside the configured
guardrail threshold.

Do not merge the reader-worker batch protocol or `_requeryBatch(...)` shape.
The extra protocol surface and stream-engine complexity are not justified by a
counter-only win.

Future stream-dispatch work should move past plain reader-reply batching and
split the residual writer/request bucket from exp 147 more narrowly: dirty-set
harvest, writer reply send, main-isolate request resolution, and drain-time
coordination are better next targets than another worker-side reply batch.

## Workflow Notes

This was a useful stress test for the Tracelite experiment workflow under a
real implementation attempt:

- The profile smoke found a real mechanism-level change quickly.
- The integrated A/B run then prevented a counter-only optimization from being
  mistaken for a mergeable performance win.
- Tracelite preserved baseline history, candidate history, decision JSON,
  graph data, and decision insights even when the expectation failed.
- The result belongs in the rejected experiment record, not as runtime code.

## Validation

- `dart analyze lib/src/reader/read_worker.dart lib/src/reader/reader_pool.dart lib/src/stream_engine.dart`
- `dart test test/stream_test.dart test/stream_invalidation_coalescing_test.dart`
- `dart run -DRESQLITE_PROFILE=true benchmark/profile/completion_scheduling_audit.dart --markdown` on baseline and candidate
- `dart run benchmark/run_tracelite_experiment.dart --dart=/usr/local/bin/dart --tracelite-root=/Users/dan/Coding/tracelite --baseline-root=/Users/dan/.codex/worktrees/resqlite-exp148-baseline --candidate-root=/Users/dan/.codex/worktrees/resqlite-exp148-reader-reply-batching --label=exp-148-reader-reply-batching --direction=stream-rerun-dispatch --runs=2 --min-repetitions=5 --max-repetitions=12 --out-dir=build/tracelite-experiments/exp-148-reader-reply-batching`
- `dart run benchmark/finalize_experiment.dart --experiment=experiments/148-reader-reply-batching.md`
