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

- `writer_roundtrip_us` is measured on the main isolate around each writer
  request after the caller has entered the writer lock where applicable, so
  concurrent write queueing is not folded into the residual bucket.
- `writer_write_call_us` is measured inside the writer isolate around
  `executeWrite` / `executeBatchWrite`.
- `writer_dirty_fetch_us` is measured inside the writer isolate around
  dirty table/column dependency fetch.
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
| A11c baseline | 18.35-20.02 | 75.92-76.79% | 53.19-56.58% | 0.06-0.62% | 42.80-46.74% | 0.00% |
| A11c disjoint | 21.05-22.50 | 61.46-65.95% | 45.05-47.27% | 0.25-0.26% | 52.47-54.70% | 12.90-13.19% |
| A11c overlap | 48.96-54.60 | 53.02-60.10% | 27.88-29.07% | 0.46-0.64% | 70.30-71.66% | 8.57-11.09% |
| keyed PK subscriptions | 16.59-16.66 | 79.14-80.05% | 28.44-31.26% | 0.40-0.61% | 68.13-71.15% | 11.75-12.55% |
| Wide batch insert | 33.29-37.37 | 99.80-99.87% | 34.05-75.31% | 0.03-0.08% | 24.61-65.91% | 0.00% |

Dirty dependency fetch is not an active target on these shapes: after warmup it
is under 1% of writer roundtrip everywhere.

A11c overlap is not native-write-call dominated. The write helper accounts for
28-29% of writer roundtrip, while the residual bucket accounts for 70-72%.
Combined with exp 121's invalidation fraction, the next stream measurement
should target completion/event-loop scheduling rather than dirty fetch or
native write work.

Wide batch insert is the opposite on the outer shape: writer roundtrip is
essentially all wall. The write-helper share is less stable in profile mode,
but it is still large enough to keep parameter/native write-call work
interesting for wide batches. This experiment does not split Dart parameter
packing from SQLite stepping.

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
