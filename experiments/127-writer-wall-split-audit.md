# Experiment 127: Writer wall split audit

**Date:** 2026-05-07
**Status:** In Review
**Direction:** `stream-rerun-dispatch`, `parameter-encoding-and-binding`, `measurement-system`
**Benchmark Run:** None

## Problem

After experiments 120-122, the measured stream workloads no longer park
dispatchers in `ReaderPool`. Experiment 121 also showed that
`StreamEngine.onDependencyChanges` is only an edge-of-noise target. That left
one blocked signal in `signals.json`: how much stream-fanout wall is spent
awaiting the writer isolate, how much of that is the actual writer helper call,
and how much is dirty dependency fetch?

The same split matters for the parameter path. Experiments 125 and 126 just
removed string-encoding allocation from wide batches; the next parameter idea
should know whether wide-batch wall still sits inside the write helper or has
moved mostly to isolate/request overhead.

A previous closed PR (#93) attempted this measurement as exp 123, but it did
not merge. This run replays the useful shape on current `origin/main` after exp
126 and records it under the next current experiment number.

## Hypothesis

A profile-only writer split can narrow the next optimization target without
changing public API or production behavior:

- If dirty dependency fetch is material, optimize dirty table/column
  marshalling.
- If the write helper dominates wide batch wall, parameter encoding remains a
  plausible implementation area.
- If stream overlap wall is mostly writer-roundtrip residual plus invalidation,
  split completion-side work so future stream work targets the actual source
  rather than dirty fetch, native write speed, or generic reader-pool wakeups.

Accept this as a measurement experiment if the counters are profile-gated,
the harness reports repeated rows for A11c, keyed-PK, and wide-batch shapes,
and `signals.json` can remove or narrow at least one blocked measurement item.

## Approach

Added profile-only writer timing to the internal write response path:

- `writer_roundtrip_us` is measured on the main isolate around each writer
  request after the caller has entered the writer lock where applicable, so
  concurrent write queueing is not folded into the residual bucket.
- `writer_write_call_us` is measured inside the writer isolate around
  `executeWrite` / `executeBatchWrite`.
- `writer_dirty_fetch_us` is measured inside the writer isolate around dirty
  table/column dependency fetch.
- `writer_request_count` counts profiled write, batch, and commit requests,
  including transaction-body writes.
- `stream_requery_await_us` / `stream_requery_count` measure per-entry
  `selectIfChanged` await cost. This is accumulated per stream re-query, so
  overlapping work can sum above workload wall.
- `stream_requery_changed_count`, `stream_requery_unchanged_count`, and
  `stream_requery_discarded_count` classify whether re-query completions
  emitted, found the result unchanged, or were discarded because another write
  dirtied the stream while the re-query was in-flight.
- `reader_dispatch_wait_us` and `reader_reply_delivery_us` separate reader-pool
  parking from the synchronous main-isolate reply handler.
- `stream_emit_us` measures the synchronous `StreamController.add` fan-out
  loop for changed stream results.

The counters are accumulated in `ProfileCounters` only when
`-DRESQLITE_PROFILE=true` is compiled in. Profile samples use dedicated
internal response subtypes, so normal production write responses do not carry
an always-null profile field over `SendPort`.

Added:

```text
benchmark/profile/writer_wall_split_audit.dart
```

The harness reuses the shared A11c and keyed-PK profile workloads and adds the
10,000-row x 20-parameter wide-batch shape from exp 116. It runs three passes
by default and writes:

```text
benchmark/profile/results/exp-127-writer-wall-split-aggregate.md
```

Research note: SQLite's official `SQLITE_TRACE_PROFILE` callback would expose
statement runtime, but the current resqlite build intentionally compiles SQLite
with `SQLITE_OMIT_TRACE`. This experiment does not remove that compile flag;
changing the production SQLite compile surface is a separate build-config
experiment, not a profile-only counter.

Sources checked in the prior unmerged attempt and still applicable here:

- Dart `SendPort.send`: https://api.dart.dev/dart-isolate/SendPort/send.html
- Dart `Stopwatch.elapsed`: https://api.dart.dev/dart-core/Stopwatch/elapsed.html
- SQLite trace hook: https://www.sqlite.org/c3ref/trace_v2.html
- SQLite trace profile event: https://www.sqlite.org/c3ref/c_trace.html

## Results

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/writer_wall_split_audit.dart --markdown --repeats=3
```

Full output is in
[`benchmark/profile/results/exp-127-writer-wall-split-aggregate.md`](../benchmark/profile/results/exp-127-writer-wall-split-aggregate.md).

Pass 1 is retained in the artifact because it captures warmup sensitivity.
The decision read uses passes 2-3:

| workload | wall_ms | roundtrip / wall | write call / roundtrip | dirty fetch / roundtrip | residual / roundtrip | invalidate / wall |
|---|---:|---:|---:|---:|---:|---:|
| A11c baseline | 24.63-29.14 | 64.09-78.03% | 44.31-51.85% | 0.63-1.34% | 46.81-55.05% | 0.00% |
| A11c disjoint | 23.18-24.12 | 62.36-63.07% | 45.30-46.06% | 0.57-0.83% | 53.11-54.13% | 11.40-12.35% |
| A11c overlap | 63.52-73.37 | 62.43-62.70% | 25.25-33.19% | 0.93-2.45% | 64.36-73.82% | 8.68-9.11% |
| keyed PK subscriptions | 17.14-25.23 | 79.60-81.49% | 30.66-36.80% | 0.32-1.04% | 62.17-69.01% | 10.14-13.03% |
| Wide batch insert | 15.05-16.39 | 98.98-99.80% | 71.30-74.51% | 0.07% | 25.42-28.63% | 0.00% |

Dirty dependency fetch is not an active target on these shapes after warmup:
it is tiny relative to write-helper and residual writer-roundtrip costs.

A11c overlap is not native-write-call dominated. The write helper accounts for
23-31% of writer roundtrip, while the residual bucket accounts for 68-76%.
Combined with exp 121's invalidation fraction, the next stream measurement
should target completion/event-loop scheduling or reply delivery rather than
dirty fetch or native write work.

Wide batch insert remains write-helper dominated: writer roundtrip is almost
the entire workload wall, and the write helper is about 71-75% of that
roundtrip. That keeps parameter/native write-call work interesting for wide
batches, but this experiment does not split Dart parameter packing from SQLite
stepping.

The completion/reply counters answer the follow-up stream question directly:

| workload | re-queries | changed / unchanged / discarded | await avg | dispatcher parks | reply delivery avg | emit avg |
|---|---:|---:|---:|---:|---:|---:|
| A11c overlap pass 2 | 3311 | 21 / 1446 / 1844 | 87.50 us | 0 | 8.00 us | 11.71 us |
| A11c overlap pass 3 | 3105 | 27 / 1299 / 1779 | 79.77 us | 0 | 7.95 us | 6.52 us |
| keyed PK pass 2 | 1162 | 3 / 382 / 777 | 84.53 us | 0 | 6.74 us | 13.33 us |
| keyed PK pass 3 | 1115 | 3 / 322 / 790 | 61.91 us | 0 | 7.28 us | 6.33 us |

The unlocked stream work is not another reader-pool wake policy: dispatch
parking is zero. It is also not listener delivery: changed-result emit is tiny.
The material signal is duplicate/stale `selectIfChanged` work. On A11c overlap,
500 writes still drive roughly 3.1k-3.3k stream re-query completions, and most
of those either find the result unchanged or are discarded because another write
dirtied the stream while the re-query was already in-flight.

Validation:

```text
dart pub get
dart analyze --fatal-infos lib/src/profile_counters.dart lib/src/writer/write_worker.dart lib/src/writer/writer.dart benchmark/profile/writer_wall_split_audit.dart benchmark/profile/audit_workloads.dart test/profile_counters_test.dart
dart test test/profile_counters_test.dart --timeout 60s
dart run -DRESQLITE_PROFILE=true benchmark/profile/writer_wall_split_audit.dart --markdown --repeats=3
```

## Decision

**Accept for review -- measurement.**

This run removes dirty-dependency fetch and writer-wall split from the blocked
measurement list. It also resolves the completion/reply-delivery question far
enough to choose a stream implementation target: reduce duplicate/stale
`selectIfChanged` work, not reader-pool parking or controller emission. For
parameter work, wide batches still have write-helper headroom, but the next
measurement should split Dart parameter packing from the native write call
before another encoder change.

The narrower SQLite statement split is **deferred**, not solved. The official
SQLite trace-profile API is unavailable under resqlite's current
`SQLITE_OMIT_TRACE` build. Reopening exact statement-runtime timing should
start as a build-config/profileability experiment, not as a hidden dependency
inside another performance change.

## Future Notes

- For stream-rerun work, try a bounded implementation that reduces stale or
  unchanged `selectIfChanged` completions. Plausible candidates are
  generation-aware burst coalescing, simple row-range dependency elision for
  partitioned primary-key streams, or cross-stream `selectIfChanged` batching.
- For parameter work, add a focused split that separates Dart parameter packing
  from the native write call before attempting another wide-batch encoder
  change.
- Do not remove `SQLITE_OMIT_TRACE` casually. If exact SQLite statement timing
  becomes necessary, evaluate the build-size/runtime implications explicitly.
