# Experiment 155: Stream rerun version coalescing

**Date:** 2026-06-09
**Status:** Rejected
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** Tracelite A/B experiment, `exp-155-stream-rerun-version-coalesce`
**Archive:** Not created; the runtime candidate was a small private
`StreamEngine` scheduling change and was removed before opening the PR.

## Problem

The `stream-rerun-dispatch` signal map still had one concrete open
implementation candidate after exp 148 and exp 151: try a rerun
version/coalescing change with only the narrow measurement needed in the same
branch.

Current `StreamEngine` already has the important durable coalescing pieces:

- a pre-dispatch `LinkedHashSet<StreamEntry>` queue;
- at most one in-flight re-query per stream entry;
- a dirty flag that schedules one follow-up re-query when an invalidation
  lands while an earlier re-query is in flight;
- worker-side unchanged-result hash suppression.

The remaining hypothesis was narrower: dirty-again cycles may still re-dispatch
too eagerly when a re-query completes while writes are still arriving. A small
version/token scheme might collapse that follow-up boundary without changing
normal single-write dispatch.

This is distinct from:

- exp 084, which stamped generation later but still let reruns pile up inside
  `ReaderPool`;
- exp 148, which batched reader-worker replies and changed reader protocol
  surface;
- exp 151, which changed writer response future completion.

## Hypothesis

If an entry becomes dirty while its re-query is in flight, defer only that
follow-up re-query to the next event turn and track the dirty token on the
entry. Additional invalidations before that event-turn boundary update the same
pending token instead of allowing the completion callback to start an immediate
dirty-again cycle.

The change should be worth keeping only if it reduces completion count or
measured elapsed on the stream-dispatch primary workloads without delaying
normal non-overlapping writes.

## Approach

The candidate added private per-entry state in `lib/src/stream_engine.dart`:

- a monotonic stream-visible dirty version on `StreamEngine`;
- `dirtyVersion`, `queuedVersion`, and `inFlightVersion` on `StreamEntry`;
- `followUpScheduled`, set only for dirty-while-in-flight follow-ups.

Normal dirty entries with no active re-query still entered `_requeryQueue`
immediately. Only the follow-up path inside `_requery` changed: when a re-query
returned and found `entry.dirty == true`, it scheduled a `Timer.run` follow-up
instead of immediately re-adding the entry to `_requeryQueue`.

After the first profile smoke showed no useful mechanism, a second local
sub-variant replaced `Timer.run` with a 1 ms timer to test whether a wider
coalescing window was needed. That sub-variant was much slower and was not used
for the formal Tracelite run.

No temporary counters were kept. Existing exp 136 counters
(`completion_us`, `completion_count`) were enough to tell whether the mechanism
actually collapsed reader completion churn.

## Results

### Mechanism smoke

Command, run on the detached `origin/main` baseline and candidate worktrees:

```text
dart run -DRESQLITE_PROFILE=true \
  benchmark/profile/completion_scheduling_audit.dart --markdown
```

The next-event candidate did not collapse completion churn on A11c overlap:

| workload | version | total_ms | completion_us | completion_count | emissions |
|---|---|---:|---:|---:|---:|
| A11c overlap | baseline | 355.32 | 112,260 | 4,318 | 34 |
| A11c overlap | candidate | 346.53 | 109,897 | 4,405 | 47 |
| keyed PK subscriptions | baseline | 246.35 | 17,920 | 1,154 | 3 |
| keyed PK subscriptions | candidate | 453.51 | 18,986 | 1,042 | 3 |

The keyed-PK completion count moved down, but total wall moved the wrong way.
A11c overlap stayed flat on completion wall and slightly increased completion
count, so the candidate did not hit the intended mechanism.

The 1 ms sub-variant reduced A11c overlap completion count but made wall much
worse:

| workload | version | total_ms | completion_us | completion_count | emissions |
|---|---|---:|---:|---:|---:|
| A11c overlap | 1 ms candidate | 712.13 | 218,592 | 3,935 | 26 |
| keyed PK subscriptions | 1 ms candidate | 318.69 | 32,390 | 1,133 | 3 |

That made the wider delay unacceptable before any formal suite run.

### Tracelite A/B

Formal command, using pinned Tracelite `a2bf3648836fcf680d0aceccb18c2b31a2109586`:

```text
dart run benchmark/run_tracelite_experiment.dart \
  --tracelite-root=/Users/dan/.codex/worktrees/tracelite-pinned-a2bf364 \
  --baseline-root=/Users/dan/.codex/worktrees/resqlite-exp155-baseline-20260609-1315 \
  --candidate-root=/Users/dan/.codex/worktrees/resqlite-exp155-stream-rerun-version-coalesce-20260609-1315 \
  --label=exp-155-stream-rerun-version-coalesce \
  --direction=stream-rerun-dispatch \
  --runs=2 \
  --preset=experiment \
  --out-dir=build/tracelite-experiments/exp-155-stream-rerun-version-coalesce
```

Decision artifacts:

- `build/tracelite-experiments/exp-155-stream-rerun-version-coalesce/baseline/history.json`
- `build/tracelite-experiments/exp-155-stream-rerun-version-coalesce/candidate/history.json`
- `build/tracelite-experiments/exp-155-stream-rerun-version-coalesce/decision/decision.json`
- `build/tracelite-experiments/exp-155-stream-rerun-version-coalesce/decision/insights.md`

The run overlapped with another worker's exp 153 Tracelite run on the same
stream scenarios, so these numbers are not a clean acceptance basis. They are
still consistent with rejection because the candidate did not clear any primary
gate and the mechanism smoke had already failed.

| scenario | baseline | candidate | change | max CV | p | verdict | effect |
|---|---:|---:|---:|---:|---:|---|---|
| `high-cardinality-fanout` | 414 ms | 412 ms | -0.52% | 11.6% | 0.63 | `neutral` | `inconclusive` |
| `keyed-pk-subscriptions` | 362 ms | 359 ms | -0.88% | 26.1% | ~0.65 | `too_noisy` | `inconclusive` |
| `many-streams-writer-throughput` | 637 ms | 665 ms | +4.32% | 14.3% | 0.68 | `neutral` | `inconclusive` |

Tracelite decision: `inconclusive` for expected improvement.

## Decision

Reject.

The next-event dirty-follow-up token was a coherent implementation attempt, but
it did not reduce the intended completion-side mechanism and did not clear the
stream-dispatch Tracelite primary gate. The 1 ms coalescing-window variant
proved that widening the delay can reduce some completion count, but the wall
cost is too high for a reactive stream scheduler.

The runtime change was removed. No production code or temporary
instrumentation is kept from this experiment.

## Future Notes

- Remove the open `rerun coalescing implementation candidate` from
  `signals.json`; this specific dirty-while-in-flight delayed follow-up shape
  has now been tried.
- Do not retry a timer-delayed stream rerun follow-up unless a new workload
  shows final-state latency can absorb the delay and the profile counter shows
  a much larger completion-count collapse.
- Future stream scheduling work needs a different structure than delaying the
  existing follow-up queue. A useful candidate should either avoid scheduling
  work before the reader sees it, or change the workload shape so the primary
  Tracelite lanes can observe the intended reduction directly.

## Validation

- `dart pub get` in baseline and candidate worktrees.
- `dart analyze lib/src/stream_engine.dart`
- `dart test test/stream_invalidation_coalescing_test.dart test/stream_test.dart test/stream_dependency_shapes_test.dart test/stream_cache_hit_reliability_test.dart`
- `dart test test/stream_invalidation_coalescing_test.dart test/stream_test.dart` after the 1 ms sub-variant.
- `dart run -DRESQLITE_PROFILE=true benchmark/profile/completion_scheduling_audit.dart --markdown` on baseline and candidate smokes.
- `dart run benchmark/run_tracelite_experiment.dart --tracelite-root=/Users/dan/.codex/worktrees/tracelite-pinned-a2bf364 --baseline-root=/Users/dan/.codex/worktrees/resqlite-exp155-baseline-20260609-1315 --candidate-root=/Users/dan/.codex/worktrees/resqlite-exp155-stream-rerun-version-coalesce-20260609-1315 --label=exp-155-stream-rerun-version-coalesce --direction=stream-rerun-dispatch --runs=2 --preset=experiment --out-dir=build/tracelite-experiments/exp-155-stream-rerun-version-coalesce` (decision artifact preserved; expectation failed with exit 65).
