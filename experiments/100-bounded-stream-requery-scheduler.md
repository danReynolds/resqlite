# Experiment 100: Bounded stream re-query scheduler

**Date:** 2026-04-25
**Status:** Rejected

## Problem

Experiment 083 fixed the worst stream invalidation backlog by coalescing
re-runs before they enter the reader pool. The remaining issue is high fan-out:
when many active streams are invalidated by the same write, the stream engine
can still hand one re-query per stream to `ReaderPool`.

That is useful when only a few streams are dirty and readers are idle. It is
less useful when dozens of streams are invalidated at once, because stream
re-query work can occupy every reader slot and delay unrelated reads.

## Hypothesis

Bound stream re-query dispatch to roughly the reader-pool width for large
fan-out invalidations, while preserving the legacy eager path for small
fan-out invalidations where readers are immediately available.

This should improve unrelated read availability during high fan-out stream
invalidations without regressing the common one-stream path or existing stream
drain benchmarks.

## Approach

Added a small scheduler in `StreamEngine`:

- `_flushQueue()` now schedules one drain task instead of independently
  dispatching every time an invalidation arrives.
- Small fan-out invalidations still dispatch immediately when enough readers
  are idle.
- Larger invalidations track `_activeRequeries` and dispatch at most
  `ReaderPool.workerCount` stream re-queries into the pool at once.
- Each bounded re-query re-flushes the queue on completion so the next dirty
  stream can run.

Added a focused benchmark harness at
`benchmark/experiments/stream_scheduler.dart` that measures one row update
feeding 1, 8, 32, and 64 distinct active streams.

The candidate also included a correctness stress test covering 64 distinct
streams invalidated by a single write.

## Results

Artifacts:

- `benchmark/results/2026-04-25T14-06-42-baseline-for-exp100.md`
- `benchmark/results/2026-04-25T14-06-42-baseline-for-exp100.json`
- `benchmark/results/2026-04-25T13-58-21-exp100-bounded-stream-scheduler.md`
- `benchmark/results/2026-04-25T13-58-21-exp100-bounded-stream-scheduler.json`

Focused benchmark command:

```bash
dart \
  -DRESQLITE_STREAM_SCHEDULER_ROUNDS=3000 \
  -DRESQLITE_STREAM_SCHEDULER_REPEATS=5 \
  run benchmark/experiments/stream_scheduler.dart
```

Baseline was run through the baseline worktree package config, using the same
benchmark script.

The table uses the final adjacent baseline/candidate rerun. Each cell is the
median of five full benchmark runs; each full run contains 3,000 write +
stream-drain cycles per workload.

| Workload | Baseline p50 | Candidate p50 | Baseline p95 | Candidate p95 | Baseline p99 | Candidate p99 | Baseline updates/sec | Candidate updates/sec | Read |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 1 stream | 0.033 ms | 0.033 ms | 0.053 ms | 0.055 ms | 0.096 ms | 0.093 ms | 26.7k | 26.0k | neutral |
| 8 streams | 0.117 ms | 0.103 ms | 0.228 ms | 0.170 ms | 0.339 ms | 0.250 ms | 7.3k | 8.7k | win |
| 32 streams | 0.454 ms | 0.357 ms | 0.711 ms | 0.814 ms | 1.094 ms | 1.501 ms | 2.1k | 2.4k | mixed |
| 64 streams | 0.958 ms | 0.804 ms | 1.577 ms | 1.492 ms | 2.307 ms | 2.311 ms | 1.0k | 1.1k | win |

This looked promising in isolation, but it did not measure the main reason to
bound re-queries: protecting unrelated reads while stream re-query work is
backlogged.

After adding that probe workload, the hypothesis did not hold:

| Workload | Baseline p50 | Candidate p50 | Baseline p95 | Candidate p95 | Baseline p99 | Candidate p99 | Baseline cycles/sec | Candidate cycles/sec |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Probe read during 64-stream fan-out | 0.141 ms | 0.151 ms | 0.204 ms | 0.287 ms | 0.338 ms | 0.724 ms | 1.1k | 1.1k |

The release suite was worse for the existing app-shaped high-fanout benchmark:

| Metric | Fresh baseline | Candidate | Result |
|---|---:|---:|---|
| High-Cardinality Stream Fan-out (100 streams × 200 writes) | 236.54 ms | 479.42 ms | 103% slower |
| Keyed PK Subscriptions (50 streams × 200 random-PK writes) | 216.78 ms | 215.35 ms | neutral |
| Reactive feed with 100 concurrent writes | 108.43 ms | 105.89 ms | neutral |

The high-cardinality result is the deciding signal. This scheduler can improve
some synthetic fan-out timings, but the standard benchmark that most closely
resembles high-cardinality reactive apps regresses materially.

Correctness checks passed:

- `dart analyze lib/src/stream_engine.dart lib/src/reader/reader_pool.dart benchmark/experiments/stream_scheduler.dart benchmark/generate_history.dart test/stream_invalidation_coalescing_test.dart test/benchmark_pipeline_test.dart`
- `dart test test/stream_invalidation_coalescing_test.dart test/stream_test.dart test/reader_pool_test.dart test/benchmark_pipeline_test.dart test/benchmark_generated_outputs_test.dart`
- `node --check` on the extracted `docs/experiments/index.html` script

Full `dart test` was not used for this experiment because a clean worktree is
missing gitignored Drift generated files under `benchmark/drift/*.g.dart`.

## Decision

Reject.

The implementation is correct, but the performance trade-off is wrong. Bounding
stream re-query admission helps only some synthetic drain shapes, does not
improve the targeted unrelated-read-under-fanout scenario, and more than
doubles the standard high-cardinality stream fan-out runtime.

The broader lesson is useful: a stream scheduler must optimize the app-shaped
mix, not just the number of re-query tasks admitted to the reader pool. If this
area is revisited, the benchmark should start from competing normal reads
during reactive fan-out and from A11b, not from isolated all-stream drain time.
