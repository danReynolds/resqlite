# Experiment 153: Explicit row observer for keyed PK streams

**Date:** 2026-06-09
**Status:** In Review
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** Tracelite A/B experiment, `exp-153-row-observer-keyed-pk`,
plus focused keyed-PK benchmark mode

## Problem

Experiment 134 proved the keyed-PK miss path has real headroom: when a stream
watching `WHERE id = ?` could be intersected with writer-side dirty rowids, the
keyed-PK profile dropped intersection entries from 10,000 to 3 and writer-burst
wall from 25.54 ms to 12.45 ms. That implementation was rejected because it
recognized row identity by inspecting SQL text.

The question for this run was whether callers can express the same row identity
explicitly without turning the default stream API into a SQL recognizer or
making the public surface obviously too ugly to carry.

## Hypothesis

An opt-in row observer API can keep ordinary `stream()` behavior conservative
while allowing keyed detail-screen streams to skip miss-path re-query work:

- streams declare the table and primary key they observe;
- writes declare the table and primary keys they changed;
- the stream engine keeps table dependencies as the correctness layer and uses
  row identity only as a narrower candidate filter.

Accept for review if the opt-in path materially reduces keyed-PK write-loop
work, normal stream workloads stay neutral under Tracelite, and the API is small
enough to review as a prototype. Reject if the focused win only works through
SQL inference, if guardrails regress, or if the API requires broad public
surface area before it can be evaluated.

## Approach

The candidate adds an explicit `RowIdentity(table, primaryKey)` value and two
prototype entry points:

```dart
db.streamWithRowObservation(
  'SELECT id, body, updated_at FROM items WHERE id = ?',
  parameters: [id],
  row: RowIdentity(table: 'items', primaryKey: id),
);

await db.executeWithRowChanges(
  'UPDATE items SET body = ?, updated_at = ? WHERE id = ?',
  parameters: [body, updatedAt, id],
  rowChanges: [RowIdentity(table: 'items', primaryKey: id)],
);
```

No row identity is inferred from SQL text. `StreamEngine` indexes the explicit
row only after the initial dependency read proves the stream actually depends
on that table. If a write has no explicit row changes for a dirty table, normal
table/column invalidation still applies.

Transactions reject non-empty `rowChanges` for this prototype. Transaction-wide
row accumulation, triggers, cascades, composite primary keys, aliases, and
schema-aware validation need a larger production design.

The keyed-PK benchmark now reports both `resqlite stream()` and
`resqlite row-observed stream()` in the same run, with write-loop and settle
splits so the 200 ms quiet-window floor does not hide the dispatch win.

## Results

### Focused keyed-PK benchmark

Command:

```text
dart run benchmark/suites/keyed_pk_subscriptions.dart
```

Run A:

| Library | Wall med | Write-loop med | Settle med | Total emits | Observed hits |
|---|---:|---:|---:|---:|---:|
| `resqlite stream()` | 280.38 ms | 78.72 ms | 202.11 ms | 0 | 3 |
| `resqlite row-observed stream()` | 212.79 ms | 10.55 ms | 202.24 ms | 0 | 3 |

Run B:

| Library | Wall med | Write-loop med | Settle med | Total emits | Observed hits |
|---|---:|---:|---:|---:|---:|
| `resqlite stream()` | 242.38 ms | 40.16 ms | 202.23 ms | 0 | 3 |
| `resqlite row-observed stream()` | 212.34 ms | 10.57 ms | 202.24 ms | 0 | 3 |

The row-observed path reduced write-loop median by 86.6% in run A and 73.7% in
run B. Wall-time improvement was smaller, 24.1% and 12.4%, because the benchmark
deliberately waits for a 200 ms quiet window after writes stop. Emission counts
do not show the win: both resqlite modes emit zero post-baseline rows here
because existing hash suppression already hides unchanged miss-path results.
The saved work is re-query dispatch, not listener delivery.

### Tracelite guardrails

The integrated Tracelite A/B wrapper ran against current `origin/main`
(`c14bbbd42da1ce00d3ea620c5eb7c5f578701e95`) using pinned Tracelite
`a2bf3648836fcf680d0aceccb18c2b31a2109586`:

```text
dart run benchmark/run_tracelite_experiment.dart \
  --dart=/usr/local/bin/dart \
  --tracelite-root=/Users/dan/.codex/worktrees/tracelite-pinned-a2bf364-exp153 \
  --baseline-root=/Users/dan/.codex/worktrees/resqlite-exp153-baseline \
  --candidate-root=/Users/dan/.codex/worktrees/resqlite-exp153-row-observer-keyed-pk \
  --label=exp-153-row-observer-keyed-pk \
  --direction=stream-rerun-dispatch \
  --runs=2 \
  --min-repetitions=5 \
  --max-repetitions=12 \
  --out-dir=build/tracelite-experiments/exp-153-row-observer-keyed-pk-run2
```

The decision step exited 65 because `--expect=improvement` did not clear, but
the preserved decision artifact is useful as a guardrail read:

| role | scenario | peer | metric | baseline | candidate | change | max CV | p | status | effect |
|---|---|---|---|---:|---:|---:|---:|---:|---|---|
| primary | `high-cardinality-fanout` | `resqlite` | `measured_elapsed_ns` | 404 ms | 432 ms | +7.09% | 14.7% | 0.631 | neutral | inconclusive |
| primary | `keyed-pk-subscriptions` | `resqlite` | `measured_elapsed_ns` | 329 ms | 319 ms | -2.88% | 26.5% | 0.860 | neutral | inconclusive |
| primary | `many-streams-writer-throughput` | `resqlite` | `measured_elapsed_ns` | 615 ms | 600 ms | -2.46% | 3.74% | 0.123 | neutral | inconclusive |

Guardrails passed. The formal keyed-PK lane should not be treated as the opt-in
proof, though: Tracelite's scenario does not call this new prototype API, so the
focused benchmark is the direct evidence for row-observer benefit.

## Decision

**Accept for review as an explicit prototype.**

The implementation is not a SQL recognizer, the focused keyed-PK benchmark shows
the intended miss-path re-query reduction, and the standard stream-dispatch
Tracelite guardrails did not flag a general stream regression. This is a real
implementation experiment rather than a measurement-only branch.

The public API is still the main review risk. `streamWithRowObservation` plus
`executeWithRowChanges` is small enough to evaluate, but a production API should
probably be schema-aware and harder to misuse than "trust me, these are the
changed rows." Review should decide whether this lands as-is, stays internal to
benchmarking, or becomes a different row-watch shape before release.

## API Assessment

What worked:

- explicit row identity avoids SQL text parsing entirely;
- ordinary `stream()` callers keep conservative table/column invalidation;
- wrong-table row hints are ignored because the engine only indexes row
  observations after dependency tracking confirms the table is read;
- writes without row hints still re-query conservatively.

What is not settled:

- transaction-scoped row change accumulation;
- composite primary keys and `WITHOUT ROWID` tables;
- triggers, cascades, and statement shapes that affect rows not present in
  caller-supplied `rowChanges`;
- whether the write-side API should be generated/schema-aware instead of raw
  `RowIdentity` lists;
- whether the stream-side API should be `watchRow(...)`, a stream option, or a
  table helper rather than a second SQL method.

## Future Notes

If this PR is rejected, keep the focused benchmark split and API assessment as
evidence that row-level precision is worth revisiting only with an ergonomic
explicit design. Do not go back to SQL recognition.

If this PR is accepted, the next useful benchmark work is a Tracelite scenario
that exercises the explicit row-observer API directly. The current Tracelite
`keyed-pk-subscriptions` lane is still valuable as a guardrail, but it is not
an opt-in API proof.

## Validation

- `dart pub get` in candidate and baseline worktrees.
- `dart run build_runner build --delete-conflicting-outputs` in candidate and
  baseline worktrees.
- `dart analyze --fatal-infos lib/resqlite.dart lib/src/dependency_tracking.dart lib/src/database.dart lib/src/stream_engine.dart benchmark/shared/peer.dart benchmark/suites/keyed_pk_subscriptions.dart test/stream_row_observation_test.dart test/benchmark_keyed_pk_subscriptions_test.dart`
- `dart test test/stream_row_observation_test.dart test/benchmark_keyed_pk_subscriptions_test.dart --reporter compact`
- `dart run benchmark/suites/keyed_pk_subscriptions.dart` twice after the
  side-by-side benchmark split.
- Tracelite A/B command shown above.
