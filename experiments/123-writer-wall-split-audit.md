# Experiment 123: Writer wall split audit

**Date:** 2026-05-05
**Status:** In Review
**Direction:** `stream-rerun-dispatch`, `parameter-encoding-and-binding`, `measurement-system`
**Benchmark Run:** None

## Problem

After experiments 120-122, the measured stream workloads no longer park
dispatchers in `ReaderPool`. The remaining stream-rerun question moved higher
in the write path: how much wall is spent awaiting the writer isolate, how much
of that is the actual write helper/native call, how much is dirty dependency
fetch, and how much sits in `StreamEngine.onDependencyChanges` after the writer
reply?

The same missing split also affects parameter work. Experiments 113 and 116
show wide batch rows are a real dimension, but another parameter-encoding
implementation should know whether wide batches are still dominated by the
write call or by isolate/request overhead.

## Hypothesis

A profile-only writer split can narrow the next optimization target without
changing public API or production behavior:

- If dirty dependency fetch is material, optimize dirty table/column
  marshalling.
- If the write helper dominates wide batch wall, parameter encoding remains a
  plausible implementation area.
- If stream overlap wall is mostly writer-roundtrip residual plus
  invalidation, future stream work should target completion/scheduling rather
  than native write speed.

Accept this as a measurement experiment if the counters are profile-gated,
the harness reports stable repeated rows for A11c, keyed-PK, and wide-batch
shapes, and `signals.json` can remove or narrow at least one blocked
measurement item.

## Approach

Added profile-only writer timing to the internal write response path:

- `writer_roundtrip_us` is measured on the main isolate around the locked
  writer request.
- `writer_write_call_us` is measured inside the writer isolate around
  `executeWrite` / `executeBatchWrite`.
- `writer_dirty_fetch_us` is measured inside the writer isolate around
  dirty table/column dependency fetch.
- `writer_request_count` counts profiled top-level writer requests.

The counters are accumulated in `ProfileCounters` only when
`-DRESQLITE_PROFILE=true` is compiled in. The normal response objects carry a
nullable internal `WriterProfileSample`; when profile mode is off it remains
`null`.

Added:

```text
benchmark/profile/writer_wall_split_audit.dart
```

The harness reuses the shared A11c and keyed-PK profile workloads and adds the
10,000-row x 20-parameter wide-batch shape from exp 116. It runs three passes
by default and writes:

```text
benchmark/profile/results/exp-123-writer-wall-split-aggregate.md
```

Research note: SQLite's official `SQLITE_TRACE_PROFILE` callback would expose
statement runtime, but the current resqlite build intentionally compiles
SQLite with `SQLITE_OMIT_TRACE`. A first implementation attempt failed to link
`sqlite3_trace_v2` for that reason. This experiment does not remove
`SQLITE_OMIT_TRACE`; changing the production SQLite compile surface is a
separate build-config experiment, not a profile-only counter.

Sources checked:

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
[`benchmark/profile/results/exp-123-writer-wall-split-aggregate.md`](../benchmark/profile/results/exp-123-writer-wall-split-aggregate.md).

Pass 1 is retained in the artifact because it captures warmup sensitivity. The
decision read uses passes 2-3:

| workload | wall_ms | roundtrip / wall | write call / roundtrip | dirty fetch / roundtrip | residual / roundtrip | invalidate / wall |
|---|---:|---:|---:|---:|---:|---:|
| A11c baseline | 32.69-34.68 | 83.95-87.06% | 70.14-72.01% | 0.31-0.60% | 27.68-29.27% | 0.00% |
| A11c disjoint | 24.68-25.84 | 66.87-72.93% | 40.58-46.66% | 0.50-0.60% | 52.74-58.92% | 9.88-11.11% |
| A11c overlap | 57.95-64.80 | 60.12-61.16% | 27.26-31.57% | 0.82-0.84% | 67.59-71.92% | 8.52-10.75% |
| keyed PK subscriptions | 20.00-24.98 | 83.36-85.34% | 42.56-52.70% | 0.77-0.80% | 46.52-56.64% | 10.46-10.54% |
| Wide batch insert | 28.73-40.45 | 99.94-99.97% | 83.13-83.30% | 0.09-0.10% | 16.60-16.76% | 0.00% |

Dirty dependency fetch is not an active target on these shapes: after warmup it
is under 1% of writer roundtrip everywhere.

A11c overlap is not native-write-call dominated. The write helper accounts for
27-32% of writer roundtrip, while the residual bucket accounts for 68-72%.
Combined with exp 121's invalidation fraction, the next stream measurement
should target completion/event-loop scheduling rather than dirty fetch or
native write work.

Wide batch insert is the opposite: writer roundtrip is essentially all wall,
and the write helper accounts for 83% of that roundtrip. That keeps
parameter/native write-call work interesting for wide batches, but this
experiment does not split Dart parameter packing from SQLite stepping.

Validation:

```text
dart pub get
dart analyze --fatal-infos lib benchmark/profile/writer_wall_split_audit.dart benchmark/profile/audit_workloads.dart test/profile_counters_test.dart test/database_test.dart test/stream_invalidation_coalescing_test.dart
dart test test/profile_counters_test.dart test/database_test.dart test/stream_invalidation_coalescing_test.dart
dart run benchmark/check_experiment_signals.dart
dart run benchmark/check_generated_data.dart
dart run -DRESQLITE_PROFILE=true benchmark/profile/writer_wall_split_audit.dart --markdown --repeats=3
```

## Decision

**Accept for review -- measurement.**

This run removes dirty-dependency fetch from the active optimization list and
narrows the remaining stream-rerun target to completion/scheduling or other
roundtrip residual work. It also preserves the wide-batch parameter signal:
large batch writes still spend most of their wall inside the write helper.

The narrower SQLite statement split is **deferred**, not solved. The official
SQLite trace-profile API is unavailable under resqlite's current
`SQLITE_OMIT_TRACE` build. Reopening exact statement-runtime timing should
start as a build-config/profileability experiment, not as a hidden dependency
inside another performance change.

## Future Notes

- For stream-rerun work, the next measurement should be a completion-side
  scheduling counter or trace. Writer dirty fetch is too small to justify
  another pass under current workloads.
- For parameter work, add a focused split that separates Dart parameter
  packing from the native write call before attempting another wide-batch
  encoder change.
- Do not remove `SQLITE_OMIT_TRACE` casually. If exact SQLite statement timing
  becomes necessary, evaluate the build-size/runtime implications explicitly.
