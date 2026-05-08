# Experiment 128: Batched stream re-queries

**Date:** 2026-05-07
**Status:** In Review
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** None

## Problem

Experiment 127 showed that the remaining A11c overlap cost is not dirty
dependency fetch, reader-pool parking, or listener delivery. The active signal
is many small `selectIfChanged` completions: each dirty stream sends its own
reader request and gets its own reader reply, even when a single invalidation
made dozens of streams dirty at once.

That leaves a concrete implementation candidate: keep the same correctness
contract, but batch multiple dirty stream re-queries into one reader-worker
message.

## Hypothesis

If `StreamEngine._flushQueue` ships the current dirty queue as bounded reader
batches, A11c overlap should improve because 50 stream re-queries no longer
require 50 main-isolate reader replies. Disjoint writes should stay unchanged
because column-level dependency elision still keeps the queue empty.

Accept if the focused A11c profile and standalone many-streams suite both show a
clear overlap win, with no stream coalescing or reader-pool correctness
regression. Defer keyed-PK if batching helps only modestly there; keyed-PK's
real unlock is row/key-range invalidation, not fewer replies for the same
table-level re-query set.

## Approach

Added `SelectIfChangedBatchRequest` to the reader-worker protocol. The request
contains a bounded list of stream re-query inputs. One reader worker executes
them serially and returns per-query results, including per-item errors so one
bad stream does not poison unrelated entries in the batch.

`StreamEngine._flushQueue` now sends up to one 64-entry batch per available
reader worker. Single-entry queues still use the existing `selectIfChanged`
path. The batch completion path preserves the same dirty/in-flight semantics as
the single-entry path:

- if the entry was dirtied again while the batch was in-flight, discard the
  intermediate result and requeue the entry;
- if the result hash is unchanged, suppress emission;
- if rows changed, update the cached hash/row count/result and emit;
- if the stream was canceled before completion, ignore its result.

This keeps the public API unchanged and does not introduce an intentional
latency delay.

## Results

Profile command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/writer_wall_split_audit.dart --repeats=3
```

Fresh A/B against PR #100 head `9a46228`:

| workload | baseline wall_ms | candidate wall_ms | baseline reader replies | candidate reader replies |
|---|---:|---:|---:|---:|
| A11c overlap pass 2 | 71.16 | 57.03 | 2266 | 35 |
| A11c overlap pass 3 | 56.27 | 37.28 | 3168 | 31 |
| keyed PK pass 2 | 19.17 | 22.00 | 1097 | 41 |
| keyed PK pass 3 | 21.34 | 14.06 | 1057 | 41 |

The direct counter signal is the A11c reply collapse: thousands of reader
replies become ~31-35 batched replies after warmup. A11c wall improves in both
decision passes. Keyed-PK reply count also collapses, but wall is mixed/noisy;
that workload still needs finer invalidation so unwatched PK writes do not
re-query all 50 streams.

Standalone release-shape guardrails:

```text
dart run benchmark/suites/many_streams_writer_throughput.dart
dart run benchmark/suites/keyed_pk_subscriptions.dart
```

Against the same PR #100 baseline:

| suite | metric | baseline | candidate | delta |
|---|---|---:|---:|---:|
| Many-Streams overlap | wall med | 65.90 ms | 24.57 ms | -62.7% |
| Many-Streams overlap | writes/sec | 7587 | 20347 | +168.2% |
| Many-Streams disjoint | wall med | 25.42 ms | 22.86 ms | -10.1% |
| Many-Streams ratio | overlap/disjoint | 0.386 | 0.930 | +0.544 |
| Keyed PK subscriptions | wall med | 226.20 ms | 218.29 ms | -3.5% |

Validation:

```text
dart analyze --fatal-infos lib/src/reader/read_worker.dart lib/src/reader/reader_pool.dart lib/src/stream_engine.dart
dart test test/stream_invalidation_coalescing_test.dart test/reader_pool_test.dart --timeout 60s
dart test test/stream_test.dart --name "batched re-query error does not block successful peer stream"
dart run -DRESQLITE_PROFILE=true benchmark/profile/writer_wall_split_audit.dart --repeats=3
dart run build_runner build --delete-conflicting-outputs
dart run benchmark/suites/many_streams_writer_throughput.dart
dart run benchmark/suites/keyed_pk_subscriptions.dart
```

## Decision

**Accepted for review.**

This consumes exp 127's stream signal with a focused implementation. A11c
overlap is the target and it moves strongly: standalone writer throughput rises
from 7,587 to 20,347 writes/sec, while profile-mode reader replies collapse
from thousands to a few dozen. The implementation keeps batching internal to
reader workers and preserves single-stream error/cancel behavior.

Keyed-PK is not solved by this. Batching reduces reply count, but the workload
still re-queries every watched stream for table-level miss writes. The next
keyed-PK improvement should target row/key-range invalidation rather than
reader reply batching.

## Future Notes

- Watch mixed read/write fairness. A batch occupies one reader worker while it
  serially hashes multiple stream queries; the current cap of 64 bounds that
  monopolization.
- Keyed-PK needs a different direction: simple primary-key/range dependency
  metadata or another safe way to avoid re-querying streams whose watched row
  could not have changed.
- If future profiles show huge batches causing read starvation, tune the batch
  cap by workload shape instead of reverting to per-stream replies.
