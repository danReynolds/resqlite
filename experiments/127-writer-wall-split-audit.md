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
  future stream work should target completion/scheduling rather than dirty
  fetch or native write speed.

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
| A11c baseline | 19.97-20.46 | 74.45-77.01% | 55.21-56.23% | 0.25-0.70% | 43.07-44.53% | 0.00% |
| A11c disjoint | 20.17-23.82 | 62.65-63.09% | 46.99-47.86% | 0.17-0.33% | 51.81-52.85% | 11.39-15.15% |
| A11c overlap | 50.06-57.15 | 60.79-61.92% | 23.49-31.36% | 0.58-0.71% | 68.06-75.80% | 8.07-10.16% |
| keyed PK subscriptions | 14.24-15.95 | 79.18-79.25% | 30.56-31.54% | 0.40-0.59% | 67.86-69.04% | 12.72-14.01% |
| Wide batch insert | 21.08-24.50 | 99.64-99.77% | 68.28-69.81% | 0.04% | 30.14-31.69% | 0.00% |

Dirty dependency fetch is not an active target on these shapes after warmup:
it stays below 1% of writer roundtrip in every pass-2/pass-3 row.

A11c overlap is not native-write-call dominated. The write helper accounts for
23-31% of writer roundtrip, while the residual bucket accounts for 68-76%.
Combined with exp 121's invalidation fraction, the next stream measurement
should target completion/event-loop scheduling or reply delivery rather than
dirty fetch or native write work.

Wide batch insert remains write-helper dominated: writer roundtrip is almost
the entire workload wall, and the write helper is about 68-70% of that
roundtrip. That keeps parameter/native write-call work interesting for wide
batches, but this experiment does not split Dart parameter packing from SQLite
stepping.

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
measurement list. For stream-rerun work, the next useful signal is
completion-side scheduling/reply-delivery cost. For parameter work, wide
batches still have write-helper headroom, but the next measurement should split
Dart parameter packing from the native write call before another encoder
change.

The narrower SQLite statement split is **deferred**, not solved. The official
SQLite trace-profile API is unavailable under resqlite's current
`SQLITE_OMIT_TRACE` build. Reopening exact statement-runtime timing should
start as a build-config/profileability experiment, not as a hidden dependency
inside another performance change.

## Future Notes

- For stream-rerun work, build a completion-side scheduling or reply-delivery
  counter before attempting another dispatch implementation.
- For parameter work, add a focused split that separates Dart parameter packing
  from the native write call before attempting another wide-batch encoder
  change.
- Do not remove `SQLITE_OMIT_TRACE` casually. If exact SQLite statement timing
  becomes necessary, evaluate the build-size/runtime implications explicitly.
