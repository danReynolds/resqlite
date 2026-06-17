# Experiment 182: Skip preupdate dependency tracking when no streams active

**Date:** 2026-06-17
**Status:** Rejected
**Direction:** `stream-rerun-dispatch`
**Archive:** [`archive/exp-182`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-182)
**Benchmark Run:** Focused `dep_tracking_skip.dart` (two order-flipped passes) + release-suite single-pass A/B + Tracelite `stream-rerun-dispatch` decision; see Results.

## Problem

After exp 159 cleared the writer reply/request path, exp 147's residual
writer/request bucket on stream-active workloads stayed the largest
remaining slice. The recent rejection cluster (exp 170 `Mutex.tryLock` +
non-`async` Writer.execute, exp 171 cached `_resolvedRuntime`, exp 151
`Completer<T>.sync()` writer response) attacked that bucket by trimming
microtask hops; all three sat at or below the focused-harness noise floor.
The JOURNAL ["Mirroring a rejected experiment on the symmetric path does
not reopen its rejection"](JOURNAL.md) calls for a mechanism change, not
another scheduling tweak.

Looking elsewhere in the per-write path, the writer always populates a
dirty table / column set via SQLite's `preupdate_hook` (`native/resqlite.c
:preupdate_hook` → `dirty_set_add` + `dirty_columns_add_for_active_stmt`)
on every row mutation, then harvests it back to Dart at reply via
`getDirtyTableDependencies` (two FFI calls + `toDartString` per dirty
entry + `TableDependency` construction). When no streams are registered,
`StreamEngine.onDependencyChanges` short-circuits with `_entries.isEmpty`
— the harvest result is consumed by an immediate return. The accumulation
work in C and the marshalling work in Dart are then both wasted.

## Hypothesis

Toggling `preupdate_hook` off at the C level (and skipping the reply
harvest) when `_streamEngine.length == 0` at request-send time should
reduce per-row preupdate cost on wide / batch writes and the per-write
harvest cost on single-row writes, without affecting workloads that have
streams active. Acceptance criterion (set before running): Single Inserts
and Concurrent Single Inserts move at least 3% on the release suite with
neutral keyed-PK / A11c / many-streams measured-elapsed under Tracelite.

## Approach

1. **Native (`native/resqlite.c`, `native/resqlite.h`).** Added a
   `track_dirty` field to `resqlite_db` (default 1) and a fast `if
   (!sdb->track_dirty) return;` at the top of `preupdate_hook` so the
   per-row `dirty_set_add` + `dirty_columns_add_for_active_stmt` work is
   skipped wholesale when off. New FFI exporter
   `resqlite_set_track_dirty(db, enabled)` lets the writer isolate flip
   the flag.
2. **Bindings (`lib/src/native/resqlite_bindings.dart`).** FFI binding
   `resqliteSetTrackDirty(db, int)`, mirrored from the header.
3. **Request shape (`lib/src/writer/write_worker.dart`).** Added a
   `tracksDirty: bool` field to `ExecuteRequest`, `BatchRequest`,
   `CommitRequest`, plus a new `DrainRequest` no-op barrier. The writer
   isolate caches the native flag in `_WriterState.nativeTrackEnabled`
   and uses `_ensureTrackDirty(state, enabled)` to call the FFI only on
   transitions.
4. **Handler gating.**
   - `_handleExecute` / `_handleBatch` at `txDepth == 0`: track and harvest
     follow the request flag. When off, the harvest call is replaced with
     `TableDependencies.none` (the C dirty set was never populated).
   - In-transaction handlers always force track on (BEGIN is the natural
     enable point) because the harvest decision must wait for COMMIT-time
     stream presence.
   - `_handleCommit` at `newDepth == 0`: harvests if the flag is set,
     otherwise calls `discardDirtyTableDependencies` to drain the
     accumulated state without marshalling it back.
5. **Send-side gate (`lib/src/writer/writer.dart`).** `Writer.execute`,
   `executeBatch`, and the commit half of `transaction` read
   `_streamEngine.length > 0` at send time. On a false reading they flip
   `_sentUntracked = true`.
6. **Race fence (`lib/src/stream_engine.dart` + `lib/src/database.dart`).**
   The writer exposes `drainIfUntracked` which sends a `DrainRequest`
   only when `_sentUntracked == true` (the no-op message lands behind
   all in-flight requests in the worker's FIFO; its reply implies they
   all committed). `StreamEngine` calls it from `_createStream`'s
   `Future.sync` body right before the initial reader-pool query, so a
   newly registered stream cannot race against an in-flight write that
   was sent with `tracksDirty = false`.

No public API change; native default keeps the existing behavior so any
caller that does not opt into the new flag (e.g., the older binding
prebuilds) gets identical semantics.

`dart test test/` — **303 passed**, including the stream suite
(`stream_test.dart`, `stream_invalidation_coalescing_test.dart`,
`stream_dependency_shapes_test.dart`, `stream_cache_hit_reliability_test
.dart`, `stream_trigger_cascade_test.dart`) and the writer / transaction
suites.

## Results

### Focused benchmark (`benchmark/experiments/dep_tracking_skip.dart`, 9 rounds + 3 warmup, two order-flipped passes)

Pass 1 (baseline first):

| Lane | Baseline | Candidate | Δ |
|---|---:|---:|---:|
| sequential-awaited (2000 writes, no streams) | 28.065 ms | 27.006 ms | **−3.8%** |
| wide-batch-no-streams (10000 rows × 20 params) | 12.104 ms | 11.816 ms | **−2.4%** |
| tx-loop-no-streams (50 tx × 100 writes) | 21.950 ms | 22.856 ms | +4.1% |
| with-streams guardrail (1000 writes, 1 stream) | 19.426 ms | 19.942 ms | +2.7% |

Pass 2 (candidate first):

| Lane | Candidate | Baseline | Δ (cand vs base) |
|---|---:|---:|---:|
| sequential-awaited (2000 writes, no streams) | 26.977 ms | 28.481 ms | **−5.3%** |
| wide-batch-no-streams (10000 rows × 20 params) | 12.258 ms | 13.032 ms | **−5.9%** |
| tx-loop-no-streams (50 tx × 100 writes) | 22.834 ms | 21.814 ms | +4.7% |
| with-streams guardrail (1000 writes, 1 stream) | 19.524 ms | 18.820 ms | +3.7% |

The two no-stream non-tx lanes agree across both order-flipped passes —
real wins. The with-streams guardrail also agrees across passes in the
same direction (+2.7% / +3.7%), and `benchmark/ab_drift_check.dart`
classifies that signature as `reproduced` rather than drift — the
optimization carries measurable per-write overhead even when tracking is
on. The tx-loop lane is noisy (35–40% within-pass spread on both sides);
both passes lean +4% but cannot be distinguished from variance.

### Release-suite A/B (`run_release.dart`, single pass each side)

| Lane | Baseline | Candidate | Δ |
|---|---:|---:|---:|
| Single Inserts (100 sequential) — resqlite | 1.54 ms | 1.46 ms | **−5.2%** (within MDE) |
| Concurrent Single Inserts (100 concurrent) | 1.04 ms | 1.00 ms | **−3.8%** (within MDE) |
| Batch Insert (1000 rows) | 0.41 ms | 0.39 ms | −4.9% (within MDE) |
| Batch Insert (10000 rows) | 4.00 ms | 3.73 ms | **−6.8%** (within MDE) |
| Wide Batch Insert (10000 rows × 20 params) | 12.80 ms | 12.60 ms | −1.6% (within MDE) |
| Batched Write Inside Transaction (100 rows / tx.execute loop) | 0.41 ms | 0.56 ms | +37% (single-pass noise at sub-1ms) |

Overall: 5 wins / 6 regressions / 156 neutral. Every flagged regression
is on a sub-1ms metric where the per-benchmark MDE (~±0.06 ms) is half
the absolute swing the metric takes between adjacent runs on this
machine. Without a second order-flipped pass these regressions cannot be
distinguished from per-run drift — same shape as the exp 144 single-pass
swing (19/18/124 vs 30/2/129 across reruns on a vendoring-only change).

### Tracelite decision (`run_tracelite_experiment.dart --direction=stream-rerun-dispatch --runs=3`)

Decision: **`inconclusive`**. Primary metric (`measured_elapsed_ns` on
`resqlite`):

| Scenario | Baseline | Candidate | Δ | Max CV | Verdict |
|---|---:|---:|---:|---:|---|
| `high-cardinality-fanout` | 332 ms | 334 ms | +0.55% | 0.48% | `neutral` → `pass` |
| `keyed-pk-subscriptions` | 239 ms | 236 ms | −1.16% | 10.2% | `too_noisy` → `inconclusive` |
| `many-streams-writer-throughput` | 552 ms | 553 ms | +0.17% | 0.49% | `neutral` → `pass` |

Stream measured-elapsed is neutral on the two stable primaries and too
noisy on keyed-pk-subscriptions. But the warmup guardrail tells a
different story:

| Scenario | Baseline | Candidate | Δ | Max CV | Verdict |
|---|---:|---:|---:|---:|---|
| `high-cardinality-fanout` warmup | 25.7 ms | 29.0 ms | +12.4% | 13.1% | `too_noisy` |
| `keyed-pk-subscriptions` warmup | 19.6 ms | 26.6 ms | +35.9% | 11.7% | `too_noisy` |
| `many-streams-writer-throughput` warmup | 25.9 ms | 31.3 ms | +21.0% | 8.63% | `too_noisy` |

All three stream-direction warmups regressed by 12–36% in the same
direction. `too_noisy` removes the gate signal but the direction
matches the focused benchmark's with-streams regression: the candidate
adds measurable per-write overhead when streams are active, and the
warmup phase — where streams are being registered and the
`drainIfUntracked` barrier fires once per `_entries`-empty-to-nonempty
transition — concentrates it.

## Decision

**Rejected.** The optimization works as designed on the no-stream write
shapes it targeted:

- ~4–5% on Single Inserts release lane (sub-MDE on the public guard, but
  matched in the focused `dep_tracking_skip.dart` sequential lane at
  −3.8% / −5.3% across order-flipped passes).
- ~3–6% on no-stream wide batch (the wider the row, the more preupdate
  fires the C-level flag skips per batch).

But the per-call gate it adds on the stream-active path costs back what
it earns:

- ~3% slower on the focused `with-streams guardrail` lane across both
  order-flipped passes — reproduced, not drift.
- Tracelite stream-direction warmup elapsed +12–36% across all three
  scenarios in the same direction (gated `too_noisy`, but the matched
  direction is the same signal the focused harness shows).

Resqlite's primary use case is reactive streams, so the workload mix in
which the candidate helps (write-heavy without active streams) is
narrower than the one it slows (any window of writes with at least one
active stream). Net unfavorable on the realistic mix. The implementation
also brings complexity that has no upside when tracking is on: a
`tracksDirty` field threaded through four request types, a `DrainRequest`
barrier, a Dart-side `_sentUntracked` flag, and a writer-isolate mirror
of the native flag with FFI-call elision.

Acceptance criterion did not clear: the Tracelite primary gate stayed
`inconclusive` (the keyed-pk-subscriptions primary was too noisy and one
of the three stream warmups regressed beyond the 5% noise gate even
though `too_noisy` precluded a hard fail).

**Would reopen if** a real workload shows write throughput without
active streams is on a hot path the library should care about — at that
point the focused `dep_tracking_skip.dart` harness gives a clean signal
for the no-stream lanes, and the with-streams overhead would need a
different mitigation (e.g., reads the streamEngine flag once per request
build via a cached `bool hasStreams` on the writer to amortize, or
restricts the gate to single-row standalone writes where the per-write
overhead is smallest).

## Future Notes

- `archive/exp-182` keeps the full implementation reachable for
  cherry-pick; the per-row preupdate skip is the load-bearing piece for
  any future revisit.
- The `DrainRequest` no-op barrier is also useful on its own as a
  test-side fence (e.g., "drain the writer FIFO so the next assertion
  sees post-commit state"). If a future experiment needs it, factor it
  out of this archive separately.
- The `track_dirty` field and `resqlite_set_track_dirty` FFI are sound;
  if a follow-up needs to *selectively* disable the preupdate hook (e.g.,
  for an admin-only bulk-load API that opts out of stream invalidation),
  the C-side mechanism here is the starting point.
