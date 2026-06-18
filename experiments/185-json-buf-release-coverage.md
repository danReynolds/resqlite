# Experiment 185: JSON buffer reclaim release coverage

**Date:** 2026-06-18
**Status:** In Review
**Direction:** `result-transfer-shape`, `measurement-system`
**Benchmark Run:** none - focused `dart run benchmark/suites/sqlite_diagnostics.dart` only; no full release run artifact.

## Problem

Exp 183 closed exp 174's `selectBytes` memory trade-off: large byte results now
keep the native-view transfer win while a high-threshold shrink reclaims
pathologically retained reader `json_buf` capacity after later small byte reads.
The proof lived in the focused `json_buf_retention.dart` audit. The public
release path could still miss a regression that removed the shrink, changed the
`last_used_len` guard, or accidentally let `Diagnostics.readerJsonBufHighWaterBytes`
stay inflated after a one-off large `selectBytes` burst.

Exp 183 left the next step explicitly: promote a release lane that asserts the
diagnostic stays bounded after a representative one-off concurrent-burst
`selectBytes` workload, following exp 161's "make the focused win visible on a
public lane" pattern.

## Hypothesis

The existing `SQLite Diagnostics` release section is the right home for this
guard. It already captures resqlite-only point-in-time diagnostics that are not
wall-clock timings. Adding `json_buf` KiB to that table, plus one bounded
`selectBytes` reclaim workload, should make exp 183's memory bound visible in
release artifacts without adding another focused harness or changing runtime
behavior.

Accept if the diagnostics suite:

- emits a `JSON buf (KiB)` column carried through markdown, sidecar, and history
  parsing;
- keeps legacy benchmark files parseable when they do not have that column;
- runs a one-off large burst followed by small settles and fails if the
  post-settle `json_buf` total remains above a conservative bound.

## Approach

`benchmark/suites/sqlite_diagnostics.dart` now adds:

- `JSON buf (KiB)` to every `SQLite Diagnostics` table row, sourced from
  `Diagnostics.readerJsonBufHighWaterBytes`.
- `JSON buffer reclaim (8 large selectBytes + 64 small settles)`, which seeds a
  large `selectBytes` payload above 1 MiB, issues 8 concurrent large reads to
  grow the reader pool buffers, then issues 64 small reads so exp 183's shrink
  path should return every reader to the initial cap.
- A hard guard: after the settle reads, the row throws if total `json_buf`
  capacity exceeds 512 KiB.

`benchmark/shared/parse_results.dart`, `benchmark/shared/release_artifact.dart`,
and `benchmark/generate_history.dart` now carry optional `jsonBufKiB` in
`sqliteDiagnosticsMetrics`. The field is optional so old markdown/sidecars
without the new column still parse normally.

No production runtime code changed.

## Results

Focused diagnostics suite:

```text
dart run benchmark/suites/sqlite_diagnostics.dart
```

New release diagnostics row:

| Row | SQLite total | Page cache | Stmt | WAL | JSON buf | Readers busy |
|---|---:|---:|---:|---:|---:|---:|
| JSON buffer reclaim (8 large selectBytes + 64 small settles) / resqlite | 2280.1 KiB | 2250.3 KiB | 24.0 KiB | 2088.2 KiB | **64.0 KiB** | 0 |

The guard threshold is 512 KiB, so the observed 64.0 KiB value is the expected
four-reader initial cap from exp 183's shrink policy. If the shrink regresses,
this row stays inflated after the small settles and the diagnostics suite fails
instead of merely publishing a larger number.

Parser compatibility checks:

| Check | Result |
|---|---|
| Old `SQLite Diagnostics` table without `JSON buf (KiB)` | parses with `jsonBufKiB == null` |
| New table with `JSON buf (KiB)` | parses `jsonBufKiB` into sidecar/history data |
| Diagnostics benchmark test | runs end-to-end with the new subsection |

Validation:

```text
dart pub get
dart analyze --fatal-infos benchmark/suites/sqlite_diagnostics.dart benchmark/shared/parse_results.dart benchmark/shared/release_artifact.dart benchmark/generate_history.dart test/benchmark_parse_results_test.dart test/benchmark_sqlite_diagnostics_test.dart
dart test test/benchmark_parse_results_test.dart test/benchmark_sqlite_diagnostics_test.dart
dart run benchmark/suites/sqlite_diagnostics.dart
dart run benchmark/check_experiment_signals.dart
dart run benchmark/finalize_experiment.dart --experiment=experiments/185-json-buf-release-coverage.md
```

## Decision

**In Review - measurement support.** This consumes exp 183's open candidate by
turning the focused `json_buf` reclaim signal into a public diagnostics guard.
Future `selectBytes` memory-policy changes now have two distinct public lanes:
exp 175's `selectBytes() large bytes` timing row for transfer latency, and exp
185's `JSON buffer reclaim` diagnostics row for bounded native-buffer retention.

## Future Notes

- Keep this row green before changing exp 183's 1 MiB shrink trigger, 256 KiB
  `last_used_len` guard, or target cap.
- If a future platform legitimately needs a higher retained buffer after small
  settles, raise the 512 KiB guard only in the same experiment that proves the
  new bound is safe.
- Do not use this row as a latency signal. It is a diagnostics guard; transfer
  throughput stays covered by exp 175's large `selectBytes()` timing row.
