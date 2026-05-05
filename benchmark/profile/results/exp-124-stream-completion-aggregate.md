# Experiment 124 - Stream Completion Audit

Profile-mode harness: `benchmark/profile/stream_completion_audit.dart`

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`)

Wall-clock convention: `wall_us` is writer-side burst wall - the stopwatch stops on the last write. Emission drains run after the stopwatch so the denominator is not padded with idle waiting (same convention as exp 119 / exp 121, enforced by `audit_workloads.dart`).

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_completion_audit.dart --markdown
```

## Counters

| workload | shape | wall_ms | completion_us | completion_count | invalidate_us | invalidate_count | parked_total | max_parked | emissions |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 0 streams x 500 writes | 42.76 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| A11c disjoint | 50 streams x 500 writes | 38.12 | 0 | 0 | 8646 | 500 | 0 | 0 | 0 |
| A11c overlap | 50 streams x 500 writes | 85.11 | 25018 | 3696 | 12159 | 500 | 0 | 0 | 28 |
| keyed PK subscriptions | 50 streams x 200 random writes | 24.28 | 7414 | 1173 | 2814 | 200 | 0 | 0 | 3 |

## Derived fractions

| workload | completion_us / wall_us | invalidate_us / wall_us | us per completion | us per write |
|---|---:|---:|---:|---:|
| A11c baseline | 0.00% | 0.00% | 0.00 | 0.00 |
| A11c disjoint | 0.00% | 22.68% | 0.00 | 0.00 |
| A11c overlap | 29.39% | 14.29% | 6.77 | 50.04 |
| keyed PK subscriptions | 30.54% | 11.59% | 6.32 | 37.07 |

## Reading the table

- `completion_us` is the cumulative wall-clock microseconds spent in the synchronous body of `StreamEngine._requery` and `_createStream` *after* the reader-pool `await` returns: the result-change check, `entry.emit(rows)` to subscribers, and the trailing `_flushQueue` kickoff. This is the work the main-isolate event loop runs in response to a stream re-query reply - the completion-side scheduling cost exp 120 / exp 121 left as an open counter for `stream-rerun-dispatch`.
- `completion_count` increments once per resumed `_requery` body (plus initial-emit body in `_createStream`). For A11c workloads it is dominated by re-query completions during the burst.
- `completion_us / wall_us` is the fraction of writer-side burst wall attributable to completion-side scheduling on the main isolate. Compare against `invalidate_us / wall_us` (exp 121) to see whether the remaining writer-side wall sits in invalidation traversal or completion-side scheduling.
- `parked_total` and `max_parked` should both stay at zero post-exp-120, reproducing exp 120's acceptance signal as a sanity check.

## Interpretation

See `experiments/124-stream-completion-counter.md` for the decision and follow-up notes attached to these numbers.
